(** March type checker — bidirectional Hindley-Milner with provenance.

    Architecture:
      §1   Provenance (reason chains for error messages)
      §2   Internal type representation (ty, tvar, scheme)
      §3   Fresh variable generation + level management
      §4   Type utilities (repr, occurs, free_ids)
      §5   Pretty-printing
      §6   Elm-style error message parts
      §7   Type environment
      §8   Generalization and instantiation
      §9   Built-in types + base environment
      §10  Unification
      §11  Surface-type → internal-type conversion
      §12  Linearity tracking
      §13  Pattern inference
      §14  Expression checking (bidirectional: infer / check)
      §15  Declaration checking
      §16  Module entry point

    Key design choices:
    - Bidirectional: [infer_expr] synthesises a type; [check_expr] verifies
      against a known expected type.  Annotations and fn return types drive
      the "checking" direction; everything else is inferred.
    - Provenance: every [unify] call carries a [reason] that explains *why*
      the expected type was expected.  Errors say "I expected X because Y".
    - Error recovery: unification failures record a diagnostic and return;
      the [TError] sentinel unifies with anything so checking continues.
    - Linearity: linear/affine vars are tracked via mutable [bool ref]
      "used" flags in the environment. *)

module Ast  = March_ast.Ast
module Err  = March_errors.Errors
module StringSet = Set.Make(String)

(* =================================================================
   §1  Provenance — why was this type expected?
   ================================================================= *)

(** A [reason] explains why an expected type was expected.
    Carried through [unify] calls so errors can say more than
    "I expected X but found Y". *)
type reason =
  | RAnnotation of Ast.span            (** User wrote `: T` *)
  | RFnReturn   of string * Ast.span   (** Declared return of fn `name` *)
  | RFnArg      of Ast.span * int      (** Argument #i at a call site *)
  | RMatchArm   of Ast.span            (** All match arms must agree *)
  | RLetBind    of Ast.span            (** Rhs of a let binding *)
  | RBuiltin    of string              (** Invariant baked into the language *)
  | RBecause    of reason * string     (** Chain: A because "..." *)

let rec span_of_reason = function
  | RAnnotation sp       -> Some sp
  | RFnReturn (_, sp)    -> Some sp
  | RFnArg (sp, _)       -> Some sp
  | RMatchArm sp         -> Some sp
  | RLetBind sp          -> Some sp
  | RBuiltin _           -> None
  | RBecause (r, _)      -> span_of_reason r

let string_of_reason = function
  | RAnnotation _        -> "I got this expectation from the type annotation."
  | RFnReturn (name, _)  ->
    Printf.sprintf "This is the declared return type of `%s`." name
  | RFnArg (_, i)        ->
    Printf.sprintf "This is argument #%d of a function call." (i + 1)
  | RMatchArm _          -> "All branches of a match must have the same type."
  | RLetBind _           -> "This is the right-hand side of a let binding."
  | RBuiltin s           -> s
  | RBecause (_, s)      -> s

(* =================================================================
   §2  Internal type representation
   ================================================================= *)

(** Internal (elaborated) type.  Richer than the surface [Ast.ty]:
    carries unification variables with level information, and a [TError]
    sentinel that unifies with anything for graceful error recovery. *)
type ty =
  | TCon    of string * ty list          (** Int, List(a), Map(k,v) *)
  | TVar    of tvar ref                  (** Unification variable *)
  | TArrow  of ty * ty                   (** a -> b *)
  | TTuple  of ty list                   (** (a, b, c) — unit when empty *)
  | TRecord of (string * ty) list
    (** { x : Int, y : Float }
        INVARIANT: field list is sorted lexicographically by field name.
        All TRecord values must be constructed via [List.sort (fun (a,_) (b,_) ->
        String.compare a b) flds] — never by bare [TRecord flds].
        Unification compares field-name lists with structural (=), which is
        order-sensitive; an unsorted TRecord will produce spurious type mismatches
        that are very hard to diagnose.  See [assert_trecord_sorted] below. *)
  | TLin    of Ast.linearity * ty        (** linear / affine wrapper *)
  | TNat    of int                       (** Type-level natural literal *)
  | TNatOp  of Ast.nat_op * ty * ty      (** n + m, n * m *)
  | TChan   of session_ty ref            (** Linear session-typed channel endpoint *)
  | TError                               (** Error sentinel *)
  | TRefine of ty * string * Ast.expr
    (** Refinement type [{ base | predicate }] carrying the binder name and the
        predicate expression.  Transparent to unification — [repr] strips it to
        the base — so refinements never disturb base-type inference; the
        predicate is read only at the deliberate sites that emit obligations. *)

(** Local session type — per-endpoint view of a binary protocol.
    Computed by projecting the global [Ast.protocol_def] onto one role. *)
and session_ty =
  | SSend   of ty * session_ty           (** Send a value of type T, then follow S (binary) *)
  | SRecv   of ty * session_ty           (** Receive a value of type T, then follow S (binary) *)
  | SChoose of (string * session_ty) list (** Actively select a branch label *)
  | SOffer  of (string * session_ty) list (** Passively wait for the other side to pick *)
  | SEnd                                 (** Session complete — channel must be closed *)
  | SRec    of string * session_ty       (** Recursive binding: Rec(X, S) *)
  | SVar    of string                    (** Back-reference to a recursive binder *)
  | SError                               (** Error sentinel *)
  (* MPST: role-annotated send/recv for multi-party protocols (N>2 participants). *)
  | SMSend  of string * ty * session_ty  (** Send to role: MSend(target_role, T, S) *)
  | SMRecv  of string * ty * session_ty  (** Receive from role: MRecv(source_role, T, S) *)

and tvar =
  | Unbound of int * int   (** id, generalization level *)
  | Link    of ty          (** Solved: points to this type *)

(** Lightweight type-class constraints.
    [CNum t] asserts t must be Int or Float (arithmetic).
    [COrd t] asserts t must be Int, Float, or String (ordered).
    [CInterface (name, t)] asserts t must implement interface [name].
    [CADTBound (adt, t)] asserts t must be a constructor of ADT named [adt].
    [CTNatBound t] asserts t must be a type-level natural number (TNat). *)
type constraint_ =
  | CNum of ty
  | COrd of ty
  | CInterface of string * ty
  | CADTBound of string * ty
  | CTNatBound of ty

(** A type scheme encodes Hindley-Milner polymorphism.
    [Poly(ids, cs, ty)] represents ∀(α₁ … αₙ). τ where the αᵢ are the
    [Unbound] variable ids that are quantified, and [cs] are class
    constraints that must be discharged at each use site. *)
type scheme =
  | Mono of ty
  | Poly of int list * constraint_ list * ty

(* =================================================================
   §3  Fresh variable generation + level management
   ================================================================= *)

let _counter = ref 0
let fresh_id () = incr _counter; !_counter

(** Create a fresh unification variable at [level]. *)
let fresh_var level = TVar (ref (Unbound (fresh_id (), level)))

(* =================================================================
   §4  Type utilities
   ================================================================= *)

(** Follow a chain of [Link]s, applying path compression. *)
let rec repr = function
  | TVar r as t ->
    (match !r with
     | Link t' ->
       let t'' = repr t' in
       r := Link t'';     (* path compression *)
       t''
     | Unbound _ -> t)
  (* Refinements are transparent to everything that canonicalises through [repr]:
     it strips to the base, so unification/occurs/etc. never see [TRefine]. *)
  | TRefine (base, _, _) -> repr base
  | t -> t

(** Does unification variable [id] at [level] appear free in [t]?
    Also adjusts levels of encountered unbound vars (for correct
    generalization — this is the standard Rémy/Damas-Milner trick). *)
let rec occurs id level t =
  match t with
  | TVar r ->
    (match !r with
     | Unbound (id', l) ->
       if id = id' then true
       else (if l > level then r := Unbound (id', level); false)
     | Link t -> occurs id level t)
  | TCon   (_, args)    -> List.exists (occurs id level) args
  | TArrow (a, b)       -> occurs id level a || occurs id level b
  | TTuple ts           -> List.exists (occurs id level) ts
  | TRecord flds        -> List.exists (fun (_, t) -> occurs id level t) flds
  | TLin   (_, t)       -> occurs id level t
  | TNatOp (_, a, b)    -> occurs id level a || occurs id level b
  | TChan  _            -> false  (* session_ty is not polymorphic *)
  | TRefine (base, _, _) -> occurs id level base
  | TNat _ | TError     -> false

(* =================================================================
   §5  Pretty-printing (used in error messages)
   ================================================================= *)

(** Cache of tvar id → display name ("a", "b", … "z", "a1", …) *)
let _tvar_names : (int, string) Hashtbl.t = Hashtbl.create 16
let _tvar_ctr    = ref 0

let tvar_display_name id =
  match Hashtbl.find_opt _tvar_names id with
  | Some n -> n
  | None   ->
    let i = !_tvar_ctr in
    incr _tvar_ctr;
    let n =
      let base = String.make 1 (Char.chr (Char.code 'a' + i mod 26)) in
      if i < 26 then base else base ^ string_of_int (i / 26)
    in
    Hashtbl.add _tvar_names id n; n

(* -----------------------------------------------------------------
   Nominal-name recovery for structural record types.

   [TRecord] carries no nominal name (records unify purely structurally),
   so a declared `type R = { … }` is indistinguishable from an anonymous
   record by the time it reaches [pp_ty].  To recover the declared name for
   display (hover, inlay hints, "add type annotation"), we maintain a
   global index keyed by the record's *field-name signature* (the sorted,
   comma-joined field names).  The index is populated at every record-type
   declaration site during typechecking.

   Ambiguity: if two distinct record types share an identical field-name
   set, recovery would be unsound, so we mark that signature poisoned
   (mapped to [None]) and [pp_ty] then falls back to structural rendering.

   This index only affects *rendering* — never unification, generalization,
   lowering, or codegen — so it cannot change type-checking semantics. *)
let _record_names : (string, string option) Hashtbl.t = Hashtbl.create 64

(** Build the field-name signature for a record's field list. *)
let record_field_sig (flds : (string * 'a) list) =
  flds
  |> List.map fst
  |> List.sort String.compare
  |> String.concat ","

(** Register that a record type named [name] has the given field-name list.
    Idempotent for the same (signature, name) pair; poisons the signature if
    a different name later claims the same field set.  Qualified names
    (containing '.') do not poison a previously-registered bare name, and an
    unqualified name is preferred for display. *)
let register_record_name ~name (field_names : string list) =
  let sg =
    field_names |> List.sort String.compare |> String.concat ","
  in
  if sg <> "" then
    match Hashtbl.find_opt _record_names sg with
    | None -> Hashtbl.replace _record_names sg (Some name)
    | Some (Some existing) when existing = name -> ()
    | Some (Some existing) ->
      (* Prefer an unqualified (bare) name; treat a qualified alias of the
         same underlying type as non-conflicting. *)
      let bare s = match String.rindex_opt s '.' with
        | Some i -> String.sub s (i + 1) (String.length s - i - 1)
        | None -> s
      in
      if bare existing = bare name then begin
        (* Same simple name (one is qualified) — keep the bare form. *)
        if String.contains existing '.' && not (String.contains name '.') then
          Hashtbl.replace _record_names sg (Some name)
      end else
        Hashtbl.replace _record_names sg None  (* genuine ambiguity: poison *)
    | Some None -> ()  (* already poisoned *)

(** Recover the declared name for a record's field list, if unambiguous. *)
let recover_record_name (flds : (string * 'a) list) =
  match Hashtbl.find_opt _record_names (record_field_sig flds) with
  | Some (Some name) -> Some name
  | _ -> None

let rec pp_ty ?(parens = false) t =
  let t = repr t in
  let s = match t with
    | TError -> "<error>"
    | TCon (name, []) -> name
    | TCon (name, args) ->
      Printf.sprintf "%s(%s)" name
        (String.concat ", " (List.map (pp_ty ~parens:false) args))
    | TVar r ->
      (match !r with
       | Unbound (id, _) -> tvar_display_name id
       | Link t'         -> pp_ty t')
    | TArrow (a, b) ->
      let inner =
        Printf.sprintf "%s -> %s" (pp_ty ~parens:true a) (pp_ty b)
      in
      if parens then Printf.sprintf "(%s)" inner else inner
    | TTuple []  -> "()"
    | TTuple ts  ->
      Printf.sprintf "(%s)" (String.concat ", " (List.map (pp_ty ~parens:false) ts))
    | TRecord [] -> "{}"
    | TRecord flds ->
      (match recover_record_name flds with
       | Some name -> name
       | None ->
         let fs = List.map (fun (n, t) -> n ^ " : " ^ pp_ty t) flds in
         "{ " ^ String.concat ", " fs ^ " }")
    | TLin (Ast.Linear,        t) -> "linear " ^ pp_ty ~parens:true t
    | TLin (Ast.Affine,        t) -> "affine " ^ pp_ty ~parens:true t
    | TLin (Ast.Unrestricted,  t) -> pp_ty t
    | TNat n                      -> string_of_int n
    | TNatOp (Ast.NatAdd, a, b)   ->
      Printf.sprintf "%s + %s" (pp_ty a) (pp_ty b)
    | TNatOp (Ast.NatMul, a, b)   ->
      Printf.sprintf "%s * %s" (pp_ty a) (pp_ty b)
    | TChan r -> "Chan(" ^ pp_session_ty !r ^ ")"
    | TRefine (base, _, _) -> pp_ty ~parens base  (* unreachable: repr strips it *)
  in s

(** Pretty-print a type with line-wrapping.
    If the flat representation fits within [width] chars, return it unchanged.
    Otherwise indent arguments across multiple lines for readability. *)
and pp_ty_pretty ?(indent = 0) ?(width = 60) t =
  let flat = pp_ty t in
  if String.length flat <= width - indent then flat
  else
    match repr t with
    | TCon (name, (_::_ as args)) ->
      let pad = String.make (indent + 2) ' ' in
      let close_pad = String.make indent ' ' in
      let formatted = List.map (pp_ty_pretty ~indent:(indent + 2) ~width) args in
      name ^ "(\n" ^ pad ^ String.concat (",\n" ^ pad) formatted ^ "\n" ^ close_pad ^ ")"
    | TRecord ((_::_) as flds) ->
      let pad = String.make (indent + 2) ' ' in
      let close_pad = String.make indent ' ' in
      let fs = List.map (fun (n, t) ->
        n ^ " : " ^ pp_ty_pretty ~indent:(indent + String.length n + 3) ~width t) flds in
      "{\n" ^ pad ^ String.concat (",\n" ^ pad) fs ^ "\n" ^ close_pad ^ "}"
    | TTuple ((_::_) as ts) ->
      let pad = String.make (indent + 2) ' ' in
      let close_pad = String.make indent ' ' in
      let formatted = List.map (pp_ty_pretty ~indent:(indent + 2) ~width) ts in
      "(\n" ^ pad ^ String.concat (",\n" ^ pad) formatted ^ "\n" ^ close_pad ^ ")"
    | _ -> flat

(** Find which argument of a type constructor differs between two types
    of the same constructor. Returns (1-based index, expected, found) for
    the first differing argument, or None if no structural difference found. *)
and find_arg_mismatch name args1 args2 =
  let rec aux i = function
    | [], [] -> None
    | t1 :: rest1, t2 :: rest2 ->
      if pp_ty t1 = pp_ty t2 then aux (i + 1) (rest1, rest2)
      else Some (i, name, t1, t2)
    | _ -> None
  in
  aux 1 (args1, args2)

and pp_session_ty = function
  | SSend (t, s)        -> Printf.sprintf "Send(%s, %s)" (pp_ty t) (pp_session_ty s)
  | SRecv (t, s)        -> Printf.sprintf "Recv(%s, %s)" (pp_ty t) (pp_session_ty s)
  | SChoose bs          ->
    let arms = List.map (fun (l, s) -> l ^ ": " ^ pp_session_ty s) bs in
    "Choose{" ^ String.concat ", " arms ^ "}"
  | SOffer bs           ->
    let arms = List.map (fun (l, s) -> l ^ ": " ^ pp_session_ty s) bs in
    "Offer{" ^ String.concat ", " arms ^ "}"
  | SEnd                -> "End"
  | SRec (x, s)         -> Printf.sprintf "Rec(%s, %s)" x (pp_session_ty s)
  | SVar x              -> x
  | SError              -> "<session_error>"
  | SMSend (role, t, s) -> Printf.sprintf "MSend(%s, %s, %s)" role (pp_ty t) (pp_session_ty s)
  | SMRecv (role, t, s) -> Printf.sprintf "MRecv(%s, %s, %s)" role (pp_ty t) (pp_session_ty s)

(* =================================================================
   §6  Elm-style error message parts
   ================================================================= *)

(** Structured pieces of an error message.  The terminal / LSP renderer
    decides how to colour each variant.  Compose them to build
    conversational messages like Elm's. *)
type message_part =
  | MPText   of string          (** Prose text *)
  | MPCode   of string          (** Inline code — rendered monospace *)
  | MPType   of ty              (** A type — rendered via [pp_ty] *)
  | MPBreak                     (** Paragraph break *)
  | MPBullet of message_part list

let render_parts parts =
  let buf = Buffer.create 64 in
  let rec go = function
    | MPText s  -> Buffer.add_string buf s
    | MPCode s  -> Buffer.add_char buf '`'; Buffer.add_string buf s;
                   Buffer.add_char buf '`'
    | MPType t  -> Buffer.add_char buf '`'; Buffer.add_string buf (pp_ty t);
                   Buffer.add_char buf '`'
    | MPBreak   -> Buffer.add_char buf '\n'
    | MPBullet ps ->
      Buffer.add_string buf "\n  - ";
      List.iter go ps
  in
  List.iter go parts;
  Buffer.contents buf

(* =================================================================
   §7  Type environment
   ================================================================= *)

(** Linear-use record: name, qualifier, "has been used" flag. *)
type lin_entry = {
  le_name : string;
  le_lin  : Ast.linearity;
  le_used : bool ref;
}

(** Constructor info — populated from [DType] declarations.
    Describes one variant of a sum type so we can give [ECon] and
    [PatCon] real types instead of fresh variables. *)
type ctor_info = {
  ci_type    : string;           (** Parent type name, e.g. "Result" *)
  ci_params  : string list;      (** Type param names in declaration order *)
  ci_arg_tys : Ast.ty list;      (** Surface arg types of this constructor *)
  ci_vis     : Ast.visibility;   (** Constructor visibility (Public/Private) *)
}

(** One entry in the import tracker — records an imported name or alias and
    whether it was referenced at least once during typechecking. *)
type import_entry = {
  ie_span    : Ast.span;
  ie_desc    : string;              (** human-readable warning message *)
  ie_matches : string -> bool;      (** does looking up [name] count as "using" this? *)
  ie_used    : bool ref;
}

(** Computed session-type information for a declared [protocol].
    Stored in [env.protocols] after [DProtocol] is checked. *)
type proto_info = {
  pi_def         : Ast.protocol_def;
  pi_projections : (string * session_ty) list;  (** role → local session type *)
  pi_span        : Ast.span;
}

module StrMap = Map.Make(String)

type env = {
  vars    : scheme StrMap.t;               (** Term variable → scheme *)
  types   : int StrMap.t;                  (** Type constructor name → arity *)
  ctors   : ctor_info list StrMap.t;       (** Data constructor name → all infos (head = most recent) *)
  records : (string list * (string * Ast.ty) list) StrMap.t;
    (** Named record type definitions: name → (type_params, [(field, surface_ty)]) *)
  level   : int;                           (** Current generalization level *)
  lin     : lin_entry list;                (** Linear/affine use tracking *)
  errors  : Err.ctx;
  pending_constraints : constraint_ list ref; (** Accumulated use-site constraints *)
  type_map : (Ast.span, ty) Hashtbl.t;
  interfaces : Ast.interface_def StrMap.t; (** Registered interfaces *)
  sigs       : (string * Ast.sig_def) list;       (** Registered module signatures *)
  mod_needs  : string list;
  (** Capabilities declared via [needs] in the current module scope, as dot-joined paths *)
  module_caps : (string * string list) list;
  (** Capabilities required by checked sub-modules: module name → list of cap paths.
      Populated when a [DMod] is fully checked; used for transitive enforcement. *)
  protocols  : proto_info StrMap.t; (** Registered session-type protocols *)
  impls      : ty list StrMap.t; (** Registered interface implementations: iface_name → impl types *)
  import_tracker : import_entry list ref;
  (** Accumulated import/alias entries for unused-import warning detection.
      Shared (mutable) across all env copies derived from the same root. *)
  local_fns : unit StrMap.t;
  (** Function names DEFINED by the module currently being checked (set from
      the pass-1 / DMod forward-reference prebind).  A bulk import
      ([import X] / [import X except (...)]) must NOT rebind these bare
      names: the local definition shadows the import.  Without this guard
      the import clobbers the local fn's pass-1 placeholder with the
      imported module's concrete scheme, and check_fn then unifies the
      local definition against the WRONG function's type (manifesting as
      nonsense arity/type errors on the local fn's header). *)
  fn_arities : (int * Ast.span) StrMap.t;
  (** Declared parameter count of functions DEFINED in the current module
      scope (populated alongside [local_fns] in the pass-1 prebind).  March
      has no partial application — calling a known function with the wrong
      number of arguments panics at runtime (and the compiler miscompiles
      under-application into a body call with a garbage argument).  Used to
      reject wrong-arity calls of these functions at the call site. *)
  proof_caps : (string * string) list;
  (** Proof cap registry: full cap path → declaring module name.
      Populated by [DProofCap] during check_decl; checked by check_module_needs. *)
  always_linear_types : string list;
  (** Set of type constructor names declared with [always_linear type].
      Any binding whose inferred type is [TCon(name, _)] with [name] in this list
      is automatically tracked as linear — no per-site [linear] annotation needed. *)
  current_module : string;
  (** Name of the module currently being typechecked, empty string at top level. *)
  cur_fn_public : bool;
  (** True while checking the body of a PUBLIC (fn, not pfn) function — read by
      the proof-cap mint gate. Lambdas inherit it; nested named fns/modules reset
      it via their own check_fn. *)
  cap_qual_prefix : string;
  (** Accumulated dotted-path prefix of enclosing [DMod]s, for keying
      [cap_closures] so it matches TIR's fully-qualified function-name
      convention (see [lib/tir/lower.ml]'s [mod_prefix] accumulation).  Unlike
      [current_module] (which is REPLACED, not accumulated, on entry to each
      nested module — see the [Ast.DMod] branch of [check_decl] — and is used
      elsewhere for unrelated purposes that must not be perturbed),
      [cap_qual_prefix] accumulates across nesting: "" at the entry module,
      then "Lib", then "Lib.Sub", etc., mirroring [prebind_mod_members]'s
      [prefix ^ "." ^ mname.txt] recursion. The entry module's own name is
      NOT included (TIR unwraps the entry module), so this starts empty. *)
  no_panic_mod : bool;
  (** True when the module currently being checked has `cap no_panic`.
      Set by [check_decl] on [DOpts ["no_panic"]]; read by [check_no_panic_module]. *)
  no_panic_modules : string list;
  (** Names of modules (siblings/imports) that have been verified as [cap no_panic].
      Functions from these modules are treated as safe in [check_no_panic_module]. *)
  nonexhaustive_match_spans : Ast.span list ref;
  (** Spans of every NON-exhaustive [match] discovered by [check_exhaustiveness]
      anywhere in the compilation.  A non-exhaustive match lowers to a runtime
      "no matching clause" panic, so it is a panic surface that
      [check_no_panic_module] must reject — but only for matches nested inside a
      `cap no_panic` module's OWN function bodies (attributed by span
      containment, see [span_within]).  A mutable ref shared (like
      [import_tracker]) across every env copy so all sites append to one list;
      recording here is cheap and never itself an error — the read/attribution
      is gated inside [check_no_panic_module], which only runs for
      `cap no_panic` modules, so a PLAIN module's non-exhaustive match stays a
      Warning and is never promoted to an error. *)
  cap_producer_ivars : (int, Ast.span) Hashtbl.t;
  (** Inner cap-argument [TVar] id → the [cap_narrow] application span that
      produced it.  A [cap_narrow(cap)] result is [Cap(a)]; we tag [a]'s id here.
      [unify] consults this table: the instant [a] (or any var linked to it) is
      bound to a nominal proof cap [TCon(p,[])] with [p] in [proof_caps], it is a
      forge (a proof cap can ONLY come from [mint_cap] in a public declaring-
      module fn or from a parameter pass-through — never from [cap_narrow]) and
      the binding is rejected.  IO caps are not in [proof_caps], so legitimate
      IO-lattice narrowing ([Cap(IO) -> Cap(IO.Network)]) is unaffected in every
      position, including laundering through a polymorphic function.  A shared
      hashtable (like [cap_closures]) so every env copy sees the same tags. *)
  cap_narrow_factory_fns : (string, Ast.span) Hashtbl.t;
  (** Names of user functions whose body IS (or launders) a [cap_narrow] result —
      a "cap-narrow factory" (e.g. `fn mk(cap) do cap_narrow(cap) end`).  A
      cross-module reference to such a fn resolves to its PREBOUND scheme (whose
      vars are distinct from the pass-2 [check_fn] vars we tag), so the unify hook
      cannot see the taint through the call.  We instead record the factory name
      here and, at the call site, taint the call's result.  (NOTE: this path does
      not yet close the nested-module cross-resolution route — see the batch-a
      report's Critical-fix section; it is retained as it closes same-module
      factory calls and is harmless.)  Shared hashtable so every env copy sees the
      same factory set. *)
  mint_cap_sites : (Ast.span * ty * bool * string) list ref;
  (** Every [mint_cap(_)] application site, recorded as
      (span, result_type, cur_fn_public, current_module).  The mint GATE is
      checked by a post-checking sweep ([check_mint_cap_sites]): the result
      type is pinned by later unification (so it can only be inspected after the
      whole compilation is checked), while the enclosing-fn/module CONTEXT
      ([cur_fn_public], [current_module]) must be captured HERE because it is
      per-site and unavailable at sweep time.  A [mint_cap] typechecks iff its
      pinned result is [Cap(P)] with [P] a proof cap whose declaring module is
      [current_module] AND [cur_fn_public]; a proof cap from another module, a
      private fn, or a non-proof (IO) target is rejected. *)
  pure_mod : bool;
  (** True when the module currently being checked has `cap pure`.
      Set by [check_decl] on [DOpts ["pure"]]; read by [check_pure_module]. *)
  no_extern_mod : bool;
  (** True when the module currently being checked has `cap no_extern`.
      Set by [check_decl] on [DOpts ["no_extern"]]; read by [check_no_extern_module]. *)
  deterministic_mod : bool;
  (** True when the module currently being checked has `cap deterministic`.
      Set by [check_decl] on [DOpts ["deterministic"]]; read by [check_deterministic_module]. *)
  cap_closures : (string, string list) Hashtbl.t;
  (** Per-function inferred IO-capability closure: fully-qualified function
      name ("Mod.fn") → normalized list of cap paths that function requires,
      as computed by [check_module_needs] (declared [needs] in scope, Cap-typed
      signatures, body-scanned builtin calls, extern-implied caps, and
      transitively-imported module needs). Mutated in place (shared across all
      [env] copies derived from the same root, like [type_map]) so it survives
      threading through [check_decl]'s per-declaration env folds. Read via
      [fn_capability_closures]; a later hot-deploy manifest task consumes this. *)
  own_cap_closures : (string, string list) Hashtbl.t;
  (** Per-function OWN inferred IO-capability closure: fully-qualified function
      name ("Mod.fn") -> normalized list of cap paths that function's own
      signature/body/extern usage requires, WITHOUT the [module_wide_caps]
      merge that [cap_closures] performs. Accumulated across the multiple
      [record_fn_caps] call sites per function (sig + body + extern) exactly
      like [cap_closures], just without folding in the module-level [needs].
      This is the projection the migrate_state IO-free check needs: a
      [migrate_state] function living in an actor module that declares
      [needs IO.Console] for its *handlers* must not be falsely flagged just
      because the module-wide merge would attribute that cap to it too.
      Read via [fn_own_capability_closures]. *)
  local_mods : string list StrMap.t;
  (** In-file nested modules → their PRIVATE value/function member names.
      Populated by the [Ast.DMod] export step.  A same-file qualified reference
      to a private member (e.g. `A.secret` where `secret` is a [pfn]) never gets
      an "A.secret" key in [vars] (only public members are exported), so the
      registry-based [qualified_error_msg] would misreport "Unknown module `A`"
      for a module that plainly exists in this file.  This lets that path
      recognize the member is merely private and emit the accurate
      "Function `secret` is private to module `A`." instead. *)
}

let make_env errors type_map = {
  vars = StrMap.empty; types = StrMap.empty; ctors = StrMap.empty; records = StrMap.empty;
  level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
  interfaces = StrMap.empty; sigs = [];
  mod_needs = []; module_caps = []; protocols = StrMap.empty; impls = StrMap.empty;
  import_tracker = ref [];
  local_fns = StrMap.empty;
  fn_arities = StrMap.empty;
  proof_caps = [];
  always_linear_types = [];
  current_module = "";
  cur_fn_public = false;
  cap_qual_prefix = "";
  no_panic_mod = false;
  no_panic_modules = [];
  nonexhaustive_match_spans = ref [];
  cap_producer_ivars = Hashtbl.create 16;
  cap_narrow_factory_fns = Hashtbl.create 16;
  mint_cap_sites = ref [];
  pure_mod = false;
  no_extern_mod = false;
  deterministic_mod = false;
  cap_closures = Hashtbl.create 64;
  own_cap_closures = Hashtbl.create 64;
  local_mods = StrMap.empty;
}

let enter_level env = { env with level = env.level + 1 }
let leave_level env = { env with level = env.level - 1 }

(** Value restriction for capability-producer applications.  Lower every
    [Unbound] TVar reachable in [ty] to level 0 IN PLACE, so [generalize]
    (which quantifies vars at [l > level] for any [level >= 0]) can NEVER
    quantify them.  The result type of a [cap_narrow]/[mint_cap] application is
    expansive (a function call) and must not be let-generalized: if
    [let x = cap_narrow(cap)] generalized [x] to [∀a. Cap(a)], each use would
    instantiate a FRESH [a] pinned to that use's type while the compiler's
    single recorded result node stayed an unbound quantified var — defeating the
    post-checking proof-cap sweep and REOPENING the forge in every let-/generic-
    flow position (a value narrowed once and reused as different caps).  Pinning
    the result to a single monomorphic var makes the use-site's type flow back to
    the recorded node, so the sweep sees the concrete cap.  Consequence: a single
    [cap_narrow]/[mint_cap] value used at two DIFFERENT cap types no longer
    typechecks (the one var can't unify with both) — that pattern is not
    least-privilege threading and does not occur in real code. *)
let rec demote_to_monomorphic (t : ty) : unit =
  match t with
  | TVar r ->
    (match !r with
     | Unbound (id, l) -> if l > 0 then r := Unbound (id, 0)
     | Link t'         -> demote_to_monomorphic t')
  | TCon   (_, args)    -> List.iter demote_to_monomorphic args
  | TArrow (a, b)       -> demote_to_monomorphic a; demote_to_monomorphic b
  | TTuple ts           -> List.iter demote_to_monomorphic ts
  | TRecord flds        -> List.iter (fun (_, t) -> demote_to_monomorphic t) flds
  | TLin   (_, t)       -> demote_to_monomorphic t
  | TNatOp (_, a, b)    -> demote_to_monomorphic a; demote_to_monomorphic b
  | TChan  _            -> ()
  | TRefine (base, _, _) -> demote_to_monomorphic base
  | TNat _ | TError     -> ()

(** Tag the inner cap-argument var of a [cap_narrow] result [Cap(a)] so [unify]
    can reject the instant [a] is bound to a nominal proof cap — closing the
    forge even when the value is laundered through a polymorphic function.  Two
    shapes are tagged: [Cap(a)] (tag the inner var [a]) and a bare var [r] (the
    whole value type is a still-unknown var — as happens when a laundering fn's
    return decouples from its param; tag [r] itself).  If the type is already a
    concrete cap, tagging is a no-op. *)
let tag_cap_producer_result (env : env) (rty : ty) (sp : Ast.span) : unit =
  match repr rty with
  | TCon ("Cap", [inner]) ->
    (match repr inner with
     | TVar r ->
       (match !r with
        | Unbound (id, _) -> Hashtbl.replace env.cap_producer_ivars id sp
        | Link _ -> ())
     | _ -> ())
  | TVar r ->
    (match !r with
     | Unbound (id, _) -> Hashtbl.replace env.cap_producer_ivars id sp
     | Link _ -> ())
  | _ -> ()

(** True if [ty] carries a [cap_narrow]-tagged cap-producer var anywhere — the
    inner var of a [Cap(a)] whose [a] is tagged, or a bare tagged var.  Used to
    propagate the forge taint through a call: an argument whose type is tainted
    laundered a cap_narrow result, so the call's result must be tainted too. *)
let ty_has_tagged_cap_producer (env : env) (ty : ty) : bool =
  let tagged r = match !r with
    | Unbound (id, _) -> Hashtbl.mem env.cap_producer_ivars id
    | Link _ -> false in
  let rec go t = match repr t with
    | TVar r             -> tagged r
    | TCon   (_, args)   -> List.exists go args
    | TArrow (a, b)      -> go a || go b
    | TTuple ts          -> List.exists go ts
    | TRecord flds       -> List.exists (fun (_, t) -> go t) flds
    | TLin   (_, t)      -> go t
    | TNatOp (_, a, b)   -> go a || go b
    | TRefine (base, _, _) -> go base
    | TChan _ | TNat _ | TError -> false
  in go ty

let lookup_var  name env = StrMap.find_opt name env.vars
let lookup_type name env = StrMap.find_opt name env.types
let lookup_ctor name env =
  match StrMap.find_opt name env.ctors with
  | Some (ci :: _) -> Some ci
  | _ -> None

(** Find the constructor [name] that belongs to [type_name] among the candidates
    registered under that bare name.  A bare constructor name can be shared by
    several ADTs (e.g. `Text` in both `Inline` and `XmlNode`); [lookup_ctor]
    returns only the most-recently-registered candidate, which is order- and
    module-arrangement-dependent.  When the expected/scrutinee type is known,
    this lets us pick the candidate that actually matches it. *)
let lookup_ctor_in_type name type_name env =
  match StrMap.find_opt name env.ctors with
  | Some cis -> List.find_opt (fun (ci : ctor_info) -> ci.ci_type = type_name) cis
  | None -> None

(** Add [ci] under [key] in [ctors], keeping all infos for the same name.
    Deduplicates: if a ctor_info structurally identical (same ci_type,
    ci_params, and ci_arg_tys) already exists, no-op.  Two types with
    the same short name but different arity (e.g. stdlib's `Tree(a)` and
    a user's `Tree`) are kept as distinct candidates. *)
let add_ctor (key : string) (ci : ctor_info) (ctors : ctor_info list StrMap.t) =
  let lst = Option.value ~default:[] (StrMap.find_opt key ctors) in
  let same c =
    c.ci_type = ci.ci_type
    && c.ci_params = ci.ci_params
    && c.ci_arg_tys = ci.ci_arg_tys
  in
  if List.exists same lst then ctors
  else StrMap.add key (ci :: lst) ctors

(* ── Qualified module resolution ─────────────────────────────────────
   When a qualified name like "Map.get" isn't in the local env, we load
   the module via the registry and inject its exports into env on demand. *)

(** Simple edit distance for "did you mean" suggestions. *)
let edit_distance (a : string) (b : string) : int =
  let m = String.length a and n = String.length b in
  if m = 0 then n
  else if n = 0 then m
  else begin
    let d = Array.make_matrix (m + 1) (n + 1) 0 in
    for i = 0 to m do d.(i).(0) <- i done;
    for j = 0 to n do d.(0).(j) <- j done;
    for i = 1 to m do
      for j = 1 to n do
        let cost = if a.[i-1] = b.[j-1] then 0 else 1 in
        d.(i).(j) <- min (min (d.(i-1).(j) + 1) (d.(i).(j-1) + 1))
                         (d.(i-1).(j-1) + cost)
      done
    done;
    d.(m).(n)
  end

(** Split a qualified name "Mod.member" into (module, member).
    Returns None if the name contains no dot. *)
let split_qualified (name : string) : (string * string) option =
  match String.index_opt name '.' with
  | None -> None
  | Some i ->
    Some (String.sub name 0 i, String.sub name (i + 1) (String.length name - i - 1))

(** Suggest a module name similar to [name] from stdlib files on disk. *)
let suggest_module_name (name : string) : string option =
  match March_modules.Module_registry.find_stdlib_dir () with
  | None -> None
  | Some dir ->
    let best = ref None in
    let best_dist = ref max_int in
    (try
       let entries = Sys.readdir dir in
       (* Sort so equal-distance ties break deterministically. *)
       Array.sort compare entries;
       Array.iter (fun entry ->
         if Filename.check_suffix entry ".march" then begin
           let base = Filename.chop_suffix entry ".march" in
           let parts = String.split_on_char '_' base in
           let mod_name = String.concat "" (List.map String.capitalize_ascii parts) in
           let d = edit_distance (String.lowercase_ascii name) (String.lowercase_ascii mod_name) in
           if d > 0 && d < !best_dist && d <= 2 then begin
             best := Some mod_name;
             best_dist := d
           end
         end
       ) entries
     with _ -> ());
    !best

(** Forward ref filled after [surface_ty] and [generalize] are defined.
    Injects interface method bindings for cross-module [ExInterface] exports. *)
let inject_iface_exports_ref
  : (string -> March_modules.Module_registry.module_exports -> env -> env) ref =
  ref (fun _mod_name _exports env -> env)

(** Load a module's exports into an env, returning the updated env.
    Injects "Mod.name" bindings for functions/values, types, and constructors.
    Interface method bindings are handled separately via inject_iface_exports_ref. *)
let load_module_into_env (mod_name : string) (exports : March_modules.Module_registry.module_exports) (env : env) : env =
  List.fold_left (fun env entry ->
    let open March_modules.Module_registry in
    let qname = mod_name ^ "." ^ entry.ex_name in
    match entry.ex_kind with
    | ExFn | ExValue ->
      (* Visibility gate (mirrors the [ExCtor] arm below): a private [pfn] /
         private [let] is NOT importable across modules. Skipping the binding
         here (rather than adding it) lets the later [lookup_var] miss fall
         through to [qualified_error_msg], which detects [not e.ex_public] and
         reports "<name> is private to module `<mod>`." — the same message the
         [ExCtor] path already produces for private constructors.
         [ExType]/[ExRecord] stay UNGATED on purpose: March uses the opaque-type
         pattern, where a private [ptype]'s bare NAME stays referenceable across
         modules (e.g. `ConsistentHash.HashRing(String)` on a public param) while
         only its CONSTRUCTOR is hidden — enforced by the [ExCtor] gate below. *)
      if not entry.ex_public then env
      else if StrMap.mem qname env.vars then env
      else { env with vars = StrMap.add qname (Mono (fresh_var 0)) env.vars }
    | ExType arity ->
      if StrMap.mem qname env.types then env
      else { env with types = StrMap.add qname arity env.types }
    | ExRecord (arity, field_decls) ->
      let env1 = if StrMap.mem qname env.types then env
                 else { env with types = StrMap.add qname arity env.types } in
      let param_names = List.init arity (fun i -> Printf.sprintf "$t%d" i) in
      { env1 with records = StrMap.add qname (param_names, field_decls) env1.records }
    | ExCtor (parent_type, _ctor_arity) ->
      begin
        (* Find the parent type's param names from the module's type exports *)
        let type_arity = List.fold_left (fun acc e ->
          match e.ex_kind with ExType a when e.ex_name = parent_type -> a | _ -> acc
        ) 0 exports.me_entries in
        let param_names = List.init type_arity (fun i ->
          Printf.sprintf "$t%d" i) in
        let arg_tys = List.init _ctor_arity (fun i ->
          Ast.TyVar { txt = Printf.sprintf "$a%d" i; span = Ast.dummy_span }) in
        let ci = {
          ci_type = mod_name ^ "." ^ parent_type;
          ci_params = param_names;
          ci_arg_tys = arg_tys;
          ci_vis = if entry.ex_public then Ast.Public else Ast.Private;
        } in
        { env with ctors = add_ctor qname ci env.ctors }
      end
    | ExInterface _ -> env  (* handled by inject_iface_exports_ref after surface_ty is available *)
  ) env exports.me_entries

(** Try to resolve a qualified variable by loading its module.
    Returns (updated_env, scheme option). *)
let resolve_qualified_var (name : string) (env : env) : env * scheme option =
  match split_qualified name with
  | None -> env, None
  | Some (mod_name, _member) ->
    match March_modules.Module_registry.ensure_loaded mod_name with
    | None -> env, None
    | Some exports ->
      let env' = load_module_into_env mod_name exports env in
      env', lookup_var name env'

(** Try to resolve a qualified type by loading its module.
    Returns (updated_env, arity option). *)
let resolve_qualified_type (name : string) (env : env) : env * int option =
  match split_qualified name with
  | None -> env, None
  | Some (mod_name, _member) ->
    match March_modules.Module_registry.ensure_loaded mod_name with
    | None -> env, None
    | Some exports ->
      let env' = load_module_into_env mod_name exports env in
      env', lookup_type name env'

(** Try to resolve a qualified constructor by loading its module.
    Returns (updated_env, ctor_info option). *)
let resolve_qualified_ctor (name : string) (env : env) : env * ctor_info option =
  match split_qualified name with
  | None -> env, None
  | Some (mod_name, _member) ->
    match March_modules.Module_registry.ensure_loaded mod_name with
    | None -> env, None
    | Some exports ->
      let env' = load_module_into_env mod_name exports env in
      env', lookup_ctor name env'

(** Suggest a variable name close to [name] from [env.vars].
    Returns the closest match with edit distance ≤ 2 that isn't a qualified name. *)
let suggest_var_in_scope (name : string) (env : env) : string option =
  let name_lo   = String.lowercase_ascii name in
  let max_dist  = if String.length name <= 3 then 1 else 2 in
  let best      = ref None in
  let best_dist = ref max_int in
  StrMap.iter (fun k _ ->
    (* Skip qualified names (Mod.member) — those are suggested elsewhere. *)
    if not (String.contains k '.') then begin
      let d = edit_distance name_lo (String.lowercase_ascii k) in
      if d > 0 && d <= max_dist && d < !best_dist then begin
        best      := Some k;
        best_dist := d
      end
    end
  ) env.vars;
  !best

(** Produce an error message for a qualified name that failed to resolve. *)
let qualified_error_msg (name : string) (env : env) : string =
  match split_qualified name with
  | None -> Printf.sprintf "I cannot find `%s`." name
  | Some (mod_name, member)
    when (match StrMap.find_opt mod_name env.local_mods with
          | Some priv -> List.mem member priv
          | None -> false) ->
    (* An in-file nested module `mod_name` declares `member` privately (`pfn` /
       private `let`).  Private members are never exported into [env.vars], so
       the registry lookup below would misreport "Unknown module" for a module
       that plainly exists in this file.  Report the real cause instead. *)
    Printf.sprintf "Function `%s` is private to module `%s`." member mod_name
  | Some (mod_name, member) ->
    match March_modules.Module_registry.ensure_loaded mod_name with
    | None ->
      let hint = match suggest_module_name mod_name with
        | Some s -> Printf.sprintf " Did you mean `%s`?" s
        | None -> ""
      in
      Printf.sprintf "Unknown module `%s`.%s" mod_name hint
    | Some exports ->
      (* Module exists but member not found — check private *)
      let open March_modules.Module_registry in
      let priv = List.find_opt (fun e -> e.ex_name = member && not e.ex_public) exports.me_entries in
      match priv with
      | Some _ ->
        Printf.sprintf "Function `%s` is private to module `%s`." member mod_name
      | None ->
        let public_names = List.filter_map (fun e ->
          if e.ex_public then Some e.ex_name else None
        ) exports.me_entries in
        let suggestions = List.filter (fun n ->
          edit_distance (String.lowercase_ascii member) (String.lowercase_ascii n) <= 2
        ) public_names in
        let hint = match suggestions with
          | [] -> ""
          | ss -> " Did you mean " ^ String.concat " or " (List.map (fun s -> Printf.sprintf "`%s.%s`" mod_name s) ss) ^ "?"
        in
        Printf.sprintf "Module `%s` does not export `%s`.%s" mod_name member hint

(** All parent types of ctors in [env] that share [name] (multiple types may
    define the same variant). Returns list of type names (deduplicated).
    O(log n) — just a single map lookup on the ctor_info list. *)
let all_ctors_named (name : string) (env : env) : string list =
  match StrMap.find_opt name env.ctors with
  | None -> []
  | Some cis ->
    let seen = Hashtbl.create 4 in
    List.filter_map (fun ci ->
      if Hashtbl.mem seen ci.ci_type then None
      else begin Hashtbl.add seen ci.ci_type (); Some ci.ci_type end
    ) cis

(** Suggest constructors close to [name]: case-insensitive match or first-2-char
    prefix match with length difference ≤ 2. Returns [(ctor_name, type_name)]. *)
let suggest_ctors (name : string) (env : env) : (string * string) list =
  let name_lo = String.lowercase_ascii name in
  let seen = Hashtbl.create 8 in
  StrMap.fold (fun k cis acc ->
    let k_lo = String.lowercase_ascii k in
    let close =
      k_lo = name_lo ||
      (String.length name_lo >= 2 && String.length k_lo >= 2 &&
       String.sub k_lo 0 2 = String.sub name_lo 0 2 &&
       abs (String.length k - String.length name) <= 2)
    in
    if not close then acc
    else
      List.fold_left (fun acc ci ->
        let key = k ^ "/" ^ ci.ci_type in
        if Hashtbl.mem seen key then acc
        else begin Hashtbl.add seen key (); (k, ci.ci_type) :: acc end
      ) acc cis
  ) env.ctors []

let bind_var name sch env =
  { env with vars = StrMap.add name sch env.vars }

let bind_vars bindings env =
  List.fold_left (fun e (n, s) -> bind_var n s e) env bindings

(** Extend env with a new linear/affine variable. *)
let bind_linear name lin ty env =
  let le = { le_name = name; le_lin = lin; le_used = ref false } in
  { env with
    vars = StrMap.add name (Mono ty) env.vars;
    lin  = le :: env.lin }

(* =================================================================
   §8  Generalization and instantiation
   ================================================================= *)

(** [generalize level ty] quantifies all [Unbound] vars at a level
    strictly greater than [level].  Called after leaving a let-binding
    level to achieve let-polymorphism.

    The returned [Poly] scheme uses freshly-allocated [TVar] refs for
    each quantified variable.  This breaks aliasing between the scheme
    and any mutable [TVar] refs still held by other parts of the program
    (e.g. forward-reference placeholders shared with mutually-recursive
    functions processed later in pass 2).  Without the copy, a later
    function body can unify the original TVar — silently corrupting an
    already-stored Poly scheme and causing the second call site to see a
    monomorphized type instead of a fresh instantiation. *)
let generalize level ty =
  let ids = ref [] in
  let rec collect t = match repr t with
    | TVar r ->
      (match !r with
       | Unbound (id, l) when l > level ->
         if not (List.mem id !ids) then ids := id :: !ids
       | _ -> ())
    | TCon   (_, args)   -> List.iter collect args
    | TArrow (a, b)      -> collect a; collect b
    | TTuple ts          -> List.iter collect ts
    | TRecord flds       -> List.iter (fun (_, t) -> collect t) flds
    | TLin   (_, t)      -> collect t
    | TNatOp (_, a, b)   -> collect a; collect b
    | TChan  _           -> ()   (* session_ty has no polymorphic variables *)
    | TRefine (base, _, _) -> collect base  (* unreachable: repr strips it *)
    | TNat _ | TError    -> ()
  in
  collect ty;
  if !ids = [] then Mono ty
  else begin
    (* Allocate fresh, isolated TVar refs for each quantified id.
       Level 0 is used so these sentinel refs are never themselves
       generalized or lowered by occurs-check level adjustments. *)
    let refresh = List.map (fun id -> (id, ref (Unbound (id, 0)))) !ids in
    let rec copy t =
      (* Preserve a refinement wrapper through generalization so the predicate
         survives into the scheme; only the base is copied. *)
      match t with
      | TRefine (base, b, p) -> TRefine (copy base, b, p)
      | _ ->
      match repr t with
      | TVar r ->
        (match !r with
         | Unbound (id, _) ->
           (match List.assoc_opt id refresh with
            | Some new_r -> TVar new_r
            | None -> t)
         | Link _ -> assert false)  (* repr always resolves links *)
      | TCon   (n, args)   -> TCon   (n, List.map copy args)
      | TArrow (a, b)      -> TArrow (copy a, copy b)
      | TTuple ts          -> TTuple (List.map copy ts)
      | TRecord flds       -> TRecord (List.map (fun (n, t) -> (n, copy t)) flds)
      | TLin   (l, t)      -> TLin   (l, copy t)
      | TNatOp (op, a, b)  -> TNatOp (op, copy a, copy b)
      | TChan  _           -> t   (* session_ty has no polymorphic variables *)
      | TRefine (base, _, _) -> copy base  (* unreachable: a behind-a-link refinement, repr-stripped *)
      | TNat _ | TError    -> t
    in
    Poly (!ids, [], copy ty)
  end

(** [instantiate level env sch] replaces each quantified variable in [sch]
    with a fresh unification variable at [level].  Any class constraints
    carried by [sch] are instantiated and appended to [env.pending_constraints]
    so they can be discharged at the enclosing declaration boundary. *)
let instantiate level env = function
  | Mono ty -> ty
  | Poly (ids, cs, ty) ->
    let subst = List.map (fun id -> (id, fresh_var level)) ids in
    (* Proof-cap forge taint survives generalization: if a quantified var was a
       [cap_narrow]-tagged cap-producer var (e.g. an un-annotated helper
       `fn mk(cap) do cap_narrow(cap) end` whose return got generalized), tag its
       fresh instantiation too, so the unify hook still fires when the laundered
       result is bound to a proof cap at THIS call site. *)
    List.iter (fun (id, fresh) ->
        if Hashtbl.mem env.cap_producer_ivars id then
          let cn_sp = Hashtbl.find env.cap_producer_ivars id in
          (match fresh with
           | TVar r -> (match !r with Unbound (nid, _) -> Hashtbl.replace env.cap_producer_ivars nid cn_sp | Link _ -> ())
           | _ -> ())) subst;
    let rec inst t =
      (* Preserve a refinement wrapper through instantiation so call sites see
         the predicate on the parameter type; only the base is instantiated. *)
      match t with
      | TRefine (base, b, p) -> TRefine (inst base, b, p)
      | _ ->
      match repr t with
      | TVar r ->
        (match !r with
         | Unbound (id, _) ->
           (match List.assoc_opt id subst with
            | Some t' -> t'
            | None    -> t)
         | Link _ -> assert false  (* repr always follows links; this is unreachable *))
      | TCon   (n, args)   -> TCon   (n, List.map inst args)
      | TArrow (a, b)      -> TArrow (inst a, inst b)
      | TTuple ts          -> TTuple (List.map inst ts)
      | TRecord flds       -> TRecord (List.map (fun (n, t) -> (n, inst t)) flds)
      | TLin   (l, t)      -> TLin   (l, inst t)
      | TNatOp (op, a, b)  -> TNatOp (op, inst a, inst b)
      | TChan  _           -> t   (* session_ty has no polymorphic variables *)
      | TRefine (base, _, _) -> inst base  (* unreachable: a behind-a-link refinement, repr-stripped *)
      | TNat _ | TError    -> t
    in
    let inst_cs = List.map (function
        | CNum t -> CNum (inst t)
        | COrd t -> COrd (inst t)
        | CInterface (n, t) -> CInterface (n, inst t)
        | CADTBound (n, t) -> CADTBound (n, inst t)
        | CTNatBound t -> CTNatBound (inst t)) cs
    in
    env.pending_constraints := inst_cs @ !(env.pending_constraints);
    inst ty

(* =================================================================
   §9  Built-in types + base environment
   ================================================================= *)

let t_int    = TCon ("Int",    [])
let t_float  = TCon ("Float",  [])
let t_bool   = TCon ("Bool",   [])
let t_string = TCon ("String", [])
let t_unit   = TTuple []
let t_atom   = TCon ("Atom",   [])

let t_list   a     = TCon ("List",   [a])
let t_option a     = TCon ("Option", [a])
let t_result a e   = TCon ("Result", [a; e])
let t_pid    a     = TCon ("Pid",    [a])

let _t_list   = t_list
let _t_option = t_option
let _t_result = t_result
let _t_pid    = t_pid

(* =================================================================
   Capability hierarchy for needs / Cap checking.
   Moved to March_caps.Cap_lattice (Phase5C-A.1) — shared with
   March_refinecheck.Cap_infer, which previously carried a verbatim
   duplicate of this table.
   ================================================================= *)

(** Maps builtin function names to the IO capability they require.
    Used by the body-scanning pass (Phase 2) to detect missing [needs] declarations. *)
let builtin_cap_table : (string * string) list = [
  (* IO.Console *)
  ("println",               "IO.Console");
  ("print",                 "IO.Console");
  (* IO.FileRead *)
  ("file_exists",           "IO.FileRead");
  ("file_read",             "IO.FileRead");
  ("file_open",             "IO.FileRead");
  ("file_read_line",        "IO.FileRead");
  ("file_read_chunk",       "IO.FileRead");
  ("file_stat",             "IO.FileRead");
  ("dir_exists",            "IO.FileRead");
  ("dir_list",              "IO.FileRead");
  ("csv_open",              "IO.FileRead");
  ("csv_next_row",          "IO.FileRead");
  (* IO.FileWrite *)
  ("file_write",            "IO.FileWrite");
  ("file_append",           "IO.FileWrite");
  ("file_delete",           "IO.FileWrite");
  ("file_rename",           "IO.FileWrite");
  ("dir_mkdir",             "IO.FileWrite");
  ("dir_mkdir_p",           "IO.FileWrite");
  ("dir_rmdir",             "IO.FileWrite");
  ("dir_rm_rf",             "IO.FileWrite");
  (* IO.FileSystem — needs both read+write *)
  ("file_copy",             "IO.FileSystem");
  (* IO.NetConnect *)
  ("tcp_connect",           "IO.NetConnect");
  ("tcp_send_all",          "IO.NetConnect");
  ("tcp_recv_all",          "IO.NetConnect");
  ("tcp_recv_exact",        "IO.NetConnect");
  ("tcp_recv_http",         "IO.NetConnect");
  ("tcp_recv_http_headers", "IO.NetConnect");
  ("tcp_recv_chunk",        "IO.NetConnect");
  ("tcp_recv_chunked_frame","IO.NetConnect");
  ("ws_recv",               "IO.NetConnect");
  ("ws_send",               "IO.NetConnect");
  ("ws_select",             "IO.NetConnect");
  (* IO.Network *)
  ("dns_resolve",           "IO.Network");
  (* IO.NetListen *)
  ("tcp_listen",            "IO.NetListen");
  ("tcp_accept",            "IO.NetListen");
  ("http_server_listen",    "IO.NetListen");
  ("http_server_spawn_n",   "IO.NetListen");
  ("http_server_wait",      "IO.NetListen");
  (* IO.Process *)
  ("process_env",           "IO.Process");
  ("process_set_env",       "IO.Process");
  ("process_cwd",           "IO.Process");
  ("process_argv",          "IO.Process");
  ("process_pid",           "IO.Process");
  ("process_exit",          "IO.Process");
  ("process_spawn_sync",    "IO.Process");
  ("process_spawn_lines",   "IO.Process");
  ("process_spawn_async",   "IO.Process");
  ("process_read_line",     "IO.Process");
  ("process_write",         "IO.Process");
  ("process_kill_proc",     "IO.Process");
  ("process_wait_proc",     "IO.Process");
  (* IO.Clock *)
  ("unix_time",             "IO.Clock");
  ("unix_time_ms",          "IO.Clock");
  ("uuid_v7",               "IO.Clock");
  (* IO.Random *)
  ("random_bytes",          "IO.Random");
  ("stdlib_random_bytes",   "IO.Random");
  ("uuid_v4",               "IO.Random");
  (* IO.Spawn *)
  ("task_spawn",            "IO.Spawn");
  ("task_spawn_link",       "IO.Spawn");
  ("task_spawn_steal",      "IO.Spawn");
  ("task_spawn_with_cancel","IO.Spawn");
  ("get_work_pool",         "IO.Spawn");
  (* IO.Mut — shared mutable state via Vault *)
  ("vault_new",             "IO.Mut");
  ("vault_set",             "IO.Mut");
  ("vault_set_ttl",         "IO.Mut");
  ("vault_get",             "IO.Mut");
  ("vault_drop",            "IO.Mut");
  ("vault_update",          "IO.Mut");
  ("vault_put_new",         "IO.Mut");
  ("vault_incr",            "IO.Mut");
  ("vault_push_capped",     "IO.Mut");
  ("vault_ns_set",          "IO.Mut");
  ("vault_ns_get",          "IO.Mut");
  ("vault_ns_drop",         "IO.Mut");
  ("vault_keys",            "IO.Mut");
  ("vault_whereis",         "IO.Mut");
  ("vault_size",            "IO.Mut");
  (* IO.NetConnect.TLS — encrypted transport; tls_close/tls_ctx_free are cleanup, no cap *)
  ("tls_client_ctx",        "IO.NetConnect.TLS");
  ("tls_server_ctx",        "IO.NetConnect.TLS");
  ("tls_connect",           "IO.NetConnect.TLS");
  ("tls_accept",            "IO.NetConnect.TLS");
  ("tls_read",              "IO.NetConnect.TLS");
  ("tls_write",             "IO.NetConnect.TLS");
  ("tls_negotiated_alpn",   "IO.NetConnect.TLS");
  ("tls_peer_cn",           "IO.NetConnect.TLS");
]

(** [cap_subsumes parent child] — true if [parent] is an ancestor of (or equal to) [child].
    E.g., cap_subsumes "IO" "IO.FileRead" = true.
    See [March_caps.Cap_lattice.cap_subsumes]. *)
let cap_subsumes = March_caps.Cap_lattice.cap_subsumes

(** [cap_path_of_names names] joins AST name list to dot-string. *)
let cap_path_of_names names =
  String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names)

(** [cap_paths_in_surface_ty ty] returns all Cap(X) paths referenced in [ty]. *)
let rec cap_paths_in_surface_ty (ty : Ast.ty) : string list =
  match ty with
  | Ast.TyCon (con, [arg]) when con.txt = "Cap" ->
    (match arg with
     | Ast.TyCon (name, []) -> [name.txt]
     | _ -> [])
  (* Tagged(X, T) is not a Cap — skip its args to avoid false capability extraction *)
  | Ast.TyCon (con, _) when con.txt = "Tagged" -> []
  | Ast.TyCon (_, args) -> List.concat_map cap_paths_in_surface_ty args
  | Ast.TyArrow (a, b) ->
    cap_paths_in_surface_ty a @ cap_paths_in_surface_ty b
  | Ast.TyTuple ts -> List.concat_map cap_paths_in_surface_ty ts
  | Ast.TyRecord fields ->
    List.concat_map (fun (_, t) -> cap_paths_in_surface_ty t) fields
  | Ast.TyLinear (_, t) -> cap_paths_in_surface_ty t
  | _ -> []

(* =================================================================
   §9b  Standard interfaces — Eq, Ord, Show, Hash
   These are pre-registered in every module so that builtin types
   (Int, Float, String, Bool) already satisfy the constraints and
   user code can write `impl Eq(MyType)` without re-declaring the
   interface.
   ================================================================= *)

(** Extract the unification-variable id from a fresh TVar. *)
let get_tvar_id = function
  | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
  | _ -> 0

(** Build an [Ast.interface_def] for a builtin interface with a single
    type parameter named "a". [methods] is a list of (method_name, surface_ty). *)
let mk_builtin_iface name methods =
  let mk_n txt = { Ast.txt; span = Ast.dummy_span } in
  let mk_method (mname, mty) =
    { Ast.md_name = mk_n mname; md_ty = mty; md_default = None }
  in
  { Ast.iface_name        = mk_n name;
    iface_param           = mk_n "a";
    iface_superclasses    = [];
    iface_assoc_types     = [];
    iface_methods         = List.map mk_method methods }

let _mk_n txt = { Ast.txt; span = Ast.dummy_span }

(** Pre-declared standard interfaces.  These are injected into every
    module's initial environment so users can write impls for them. *)
let builtin_interfaces : (string * Ast.interface_def) list =
  let av       = Ast.TyVar  { txt = "a";      span = Ast.dummy_span } in
  let bool_t   = Ast.TyCon  ({ txt = "Bool";   span = Ast.dummy_span }, []) in
  let int_t    = Ast.TyCon  ({ txt = "Int";    span = Ast.dummy_span }, []) in
  let string_t = Ast.TyCon  ({ txt = "String"; span = Ast.dummy_span }, []) in
  [
    ("Eq",   mk_builtin_iface "Eq" [
       ("eq",      Ast.TyArrow (av, Ast.TyArrow (av, bool_t)));
     ]);
    ("Ord",  mk_builtin_iface "Ord" [
       ("compare", Ast.TyArrow (av, Ast.TyArrow (av, int_t)));
     ]);
    ("Show", mk_builtin_iface "Show" [
       ("show",    Ast.TyArrow (av, string_t));
     ]);
    ("Hash", mk_builtin_iface "Hash" [
       ("hash",    Ast.TyArrow (av, int_t));
     ]);
  ]

(** Concrete type implementations for the standard interfaces.
    These ensure that Int/Float/String/Bool satisfy Eq, Ord, Show, Hash
    out of the box. *)
let builtin_impls : (string * ty) list =
  [ (* Eq *)
    ("Eq",   t_int);   ("Eq",   t_float); ("Eq",   t_string);
    ("Eq",   t_bool);  ("Eq",   t_unit);  ("Eq",   t_atom);
    (* Ord *)
    ("Ord",  t_int);   ("Ord",  t_float); ("Ord",  t_string);
    (* Show — Atom included so `show(:tag)` / `show` on an Atom-typed value
       typechecks (compiled backend lowers it to Show$Atom.show; the
       interpreter renders VAtom a as ":" ^ a).  Without this, a direct
       `show(a)` on a concretely-Atom-typed `a` failed with "Atom does not
       implement interface Show" in BOTH modes even though `println(a)`
       worked via the generic prelude path. *)
    ("Show", t_int);   ("Show", t_float); ("Show", t_string);
    ("Show", t_bool);  ("Show", t_unit);  ("Show", t_atom);
    (* Hash *)
    ("Hash", t_int);   ("Hash", t_float); ("Hash", t_string);
    ("Hash", t_bool);
  ]

(** Build a scheme [∀a. CInterface(iface, a) => mk_ty(a)] for a builtin
    interface method binding. *)
let mk_iface_method_scheme iface_name mk_ty =
  let a = fresh_var 0 in
  Poly ([get_tvar_id a], [CInterface (iface_name, a)], mk_ty a)

(** Method bindings for the standard interfaces.  These are added to
    every module's initial [vars] so that [eq], [compare], [show],
    and [hash] resolve as polymorphic functions at call sites.
    Both unqualified (eq) and qualified (Eq.eq) forms are registered
    so that [Eq.eq(x, y)] resolves via the EField module-path lookup. *)
let builtin_interface_bindings : (string * scheme) list =
  [ ("eq",      mk_iface_method_scheme "Eq"   (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("compare", mk_iface_method_scheme "Ord"  (fun a -> TArrow (a, TArrow (a, t_int))));
    ("show",    mk_iface_method_scheme "Show" (fun a -> TArrow (a, t_string)));
    ("hash",    mk_iface_method_scheme "Hash" (fun a -> TArrow (a, t_int)));
    (* Qualified forms: Eq.eq, Ord.compare, Show.show, Hash.hash *)
    ("Eq.eq",      mk_iface_method_scheme "Eq"   (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("Ord.compare",mk_iface_method_scheme "Ord"  (fun a -> TArrow (a, TArrow (a, t_int))));
    ("Show.show",  mk_iface_method_scheme "Show" (fun a -> TArrow (a, t_string)));
    ("Hash.hash",  mk_iface_method_scheme "Hash" (fun a -> TArrow (a, t_int)));
  ]

(** Built-in binary operator schemes.
    We use level-0 fresh vars for polymorphic ops — they will be
    properly instantiated each time [instantiate] is called. *)
let builtin_bindings : (string * scheme) list =
  (* Extract the id from a fresh TVar (always succeeds for fresh vars) *)
  let get_id = function
    | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
    | _ -> 0
  in
  (* ∀a. f(a) — unconstrained polymorphism *)
  let poly1 f =
    let a = fresh_var 0 in
    Poly ([get_id a], [], f a)
  in
  (* ∀a:Num. f(a) — a must be Int or Float *)
  let poly1_num f =
    let a = fresh_var 0 in
    Poly ([get_id a], [CNum a], f a)
  in
  (* ∀a:Ord. f(a) — a must be Int, Float, or String (legacy COrd path) *)
  let _poly1_ord f =
    let a = fresh_var 0 in
    Poly ([get_id a], [COrd a], f a)
  in
  (* ∀a:Iface. f(a) — a must implement the named interface *)
  let poly1_iface iname f =
    let a = fresh_var 0 in
    Poly ([get_id a], [CInterface (iname, a)], f a)
  in
  (* ∀a b. f(a, b) — two unconstrained type variables *)
  let poly2 f =
    let a = fresh_var 0 in
    let b = fresh_var 0 in
    Poly ([get_id a; get_id b], [], f a b)
  in
  [
    (* Arithmetic: Num-constrained so they work on Int and Float *)
    ("+",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("-",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("*",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("/",  poly1_num (fun a -> TArrow (a, TArrow (a, a))));
    ("%",  Mono (TArrow (t_int,    TArrow (t_int,    t_int))));
    ("negate", poly1_num (fun a -> TArrow (a, a)));
    (* Float-specific operators — always monomorphic *)
    ("+.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("-.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("*.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("/.", Mono (TArrow (t_float, TArrow (t_float, t_float))));
    (* Ordering comparisons: Ord interface-constrained (Int, Float, String) *)
    ("<",  poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    (">",  poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("<=", poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    (">=", poly1_iface "Ord" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("&&", Mono (TArrow (t_bool,   TArrow (t_bool,   t_bool))));
    ("||", Mono (TArrow (t_bool,   TArrow (t_bool,   t_bool))));
    (* Equality: Eq interface-constrained *)
    ("==", poly1_iface "Eq" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("!=", poly1_iface "Eq" (fun a -> TArrow (a, TArrow (a, t_bool))));
    ("++",             Mono (TArrow (t_string, TArrow (t_string, t_string))));
    ("print",          Mono (TArrow (t_string, t_unit)));
    ("println",        Mono (TArrow (t_string, t_unit)));
    ("print_int",      Mono (TArrow (t_int,    t_unit)));
    ("print_float",    Mono (TArrow (t_float,  t_unit)));
    (* Tap bus: ∀a. a -> a  (sends value to tap bus, returns it unchanged) *)
    ("tap",            poly1 (fun a -> TArrow (a, a)));
    (* Property-testing primitive: ∀a. (Bool -> a) -> Result(a, String).
       Runs the thunk (a 1-arg lambda whose argument is ignored — used
       because the typechecker doesn't handle `() -> a` well in argument
       position), catching any runtime failure (assert, panic, match
       failure, division by zero, etc.) and returning Err(msg) on failure
       or Ok(result) on success. Call as `__try_call(fn _ -> body)`.
       The thunk must return Bool (not a generic `a`): the C runtime stores
       the Ok field in the uniform low-bit-tagged immediate representation,
       which would corrupt a heap pointer.  See __try_call in
       runtime/march_runtime.c. *)
    ("__try_call",     Mono
        (TArrow (TArrow (t_bool, t_bool), t_result t_bool t_string)));
    (* Value-carrying try: ∀a. (Bool -> a) -> Result(a, String).  Unlike
       __try_call, the thunk's result type is the type variable `a`, so the
       compiled thunk returns its value in the uniform representation (heap
       pointers raw, immediates low-bit-tagged).  __try_call_val stores that
       uniform value into the Ok field as-is — exactly how __try_call already
       stores the heap march_string into its Err field — so a heap result
       (e.g. a nested Result) round-trips without corruption.  Used by
       Depot.Transaction.run to guard a callback that returns Result(v, String).
       See __try_call_val in runtime/march_runtime.c. *)
    ("__try_call_val", poly1 (fun a ->
        TArrow (TArrow (t_bool, a), t_result a t_string)));
    ("int_to_string",  Mono (TArrow (t_int,    t_string)));
    ("float_to_string",Mono (TArrow (t_float,  t_string)));
    ("bool_to_string", Mono (TArrow (t_bool,   t_string)));
    ("string_to_int",   Mono (TArrow (t_string, t_option t_int)));
    ("string_to_float", Mono (TArrow (t_string, t_option t_float)));
    ("string_length",   Mono (TArrow (t_string, t_int)));
    ("string_concat",  Mono (TArrow (t_string, TArrow (t_string, t_string))));
    ("read_line",      Mono (TArrow (t_unit,   t_string)));
    ("not",            Mono (TArrow (t_bool,   t_bool)));
    (* List helpers: ∀a. ... *)
    ("head",   poly1 (fun a -> TArrow (t_list a, a)));
    ("tail",   poly1 (fun a -> TArrow (t_list a, t_list a)));
    ("is_nil", poly1 (fun a -> TArrow (t_list a, t_bool)));
    (* Generic to_string: ∀a. a -> String *)
    ("to_string", poly1 (fun a -> TArrow (a, t_string)));
    (* Record introspection builtins: ∀a b. fully polymorphic — runtime checks type *)
    ("record_keys",      poly1 (fun a -> TArrow (a, t_list t_string)));
    ("record_values",    poly2 (fun a b -> TArrow (a, t_list b)));
    ("record_entries",   poly2 (fun a b -> TArrow (a, t_list (TTuple [t_string; b]))));
    ("record_get",       poly2 (fun a b -> TArrow (a, TArrow (t_string, t_option b))));
    ("record_put",       poly2 (fun a b -> TArrow (a, TArrow (t_string, TArrow (b, a)))));
    ("record_has_key",   poly1 (fun a -> TArrow (a, TArrow (t_string, t_bool))));
    ("record_from_list", poly2 (fun a b -> TArrow (t_list (TTuple [t_string; a]), b)));
    (* Generic to_json/from_json: fully polymorphic — runtime dispatches via impl_tbl.
       ∀a b. a -> b  — this avoids shadowing when multiple types derive Json. *)
    ("to_json",   poly2 (fun a b -> TArrow (a, b)));
    ("from_json",  poly2 (fun a b -> TArrow (a, b)));
    (* Actor/respond: ∀a. a -> Unit *)
    ("respond", poly1 (fun a -> TArrow (a, t_unit)));
    (* Actor builtins *)
    ("kill",     poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_unit)));
    ("is_alive", poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_bool)));
    ("actor_get_int", poly1 (fun a -> TArrow (TCon ("Pid", [a]), TArrow (t_int, t_int))));
    (* Int primitives *)
    ("int_abs",         Mono (TArrow (t_int,   t_int)));
    ("int_pow",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_div",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_mod",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_div_euclid",  Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_mod_euclid",  Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_to_float",    Mono (TArrow (t_int,   t_float)));
    ("int_max_value",   Mono (TArrow (t_unit,  t_int)));
    ("int_min_value",   Mono (TArrow (t_unit,  t_int)));
    (* Int bitwise primitives *)
    ("int_and",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_or",          Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_xor",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_not",         Mono (TArrow (t_int,   t_int)));
    ("int_shl",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_shr",         Mono (TArrow (t_int,   TArrow (t_int, t_int))));
    ("int_popcount",    Mono (TArrow (t_int,   t_int)));
    (* Float primitives *)
    ("float_abs",       Mono (TArrow (t_float, t_float)));
    ("float_floor",     Mono (TArrow (t_float, t_int)));
    ("float_ceil",      Mono (TArrow (t_float, t_int)));
    ("float_round",     Mono (TArrow (t_float, t_int)));
    ("float_truncate",  Mono (TArrow (t_float, t_int)));
    ("float_to_int",    Mono (TArrow (t_float, t_int)));
    ("float_is_nan",    Mono (TArrow (t_float, t_bool)));
    ("float_is_infinite",Mono (TArrow (t_float, t_bool)));
    ("float_infinity",  Mono (TArrow (t_unit,  t_float)));
    ("float_neg_infinity",Mono (TArrow (t_unit, t_float)));
    ("float_nan",       Mono (TArrow (t_unit,  t_float)));
    ("float_epsilon",   Mono (TArrow (t_unit,  t_float)));
    ("unix_time",       Mono (TArrow (t_unit,  t_float)));
    ("unix_time_ms",    Mono (TArrow (t_unit,  t_int)));
    ("uuid_v7",         Mono (TArrow (t_unit,  t_string)));
    ("uuid_v7_at",      Mono (TArrow (t_int,   t_string)));
    ("float_from_string",Mono (TArrow (t_string, t_option t_float)));
    ("float_to_string", Mono (TArrow (t_float,  t_string)));
    (* Math primitives *)
    ("math_sqrt",   Mono (TArrow (t_float, t_float)));
    ("math_cbrt",   Mono (TArrow (t_float, t_float)));
    ("math_pow",    Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("math_exp",    Mono (TArrow (t_float, t_float)));
    ("math_exp2",   Mono (TArrow (t_float, t_float)));
    ("math_log",    Mono (TArrow (t_float, t_float)));
    ("math_log2",   Mono (TArrow (t_float, t_float)));
    ("math_log10",  Mono (TArrow (t_float, t_float)));
    ("math_sin",    Mono (TArrow (t_float, t_float)));
    ("math_cos",    Mono (TArrow (t_float, t_float)));
    ("math_tan",    Mono (TArrow (t_float, t_float)));
    ("math_asin",   Mono (TArrow (t_float, t_float)));
    ("math_acos",   Mono (TArrow (t_float, t_float)));
    ("math_atan",   Mono (TArrow (t_float, t_float)));
    ("math_atan2",  Mono (TArrow (t_float, TArrow (t_float, t_float))));
    ("math_sinh",   Mono (TArrow (t_float, t_float)));
    ("math_cosh",   Mono (TArrow (t_float, t_float)));
    ("math_tanh",   Mono (TArrow (t_float, t_float)));
    (* String primitives *)
    ("string_is_empty",     Mono (TArrow (t_string, t_bool)));
    ("string_slice",        Mono (TArrow (t_string, TArrow (t_int, TArrow (t_int, t_string)))));
    ("string_contains",     Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_starts_with",  Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_ends_with",    Mono (TArrow (t_string, TArrow (t_string, t_bool))));
    ("string_index_of",     Mono (TArrow (t_string, TArrow (t_string, t_option t_int))));
    ("string_replace",      Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_replace_all",  Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_split",        Mono (TArrow (t_string, TArrow (t_string, t_list t_string))));
    ("string_join",         Mono (TArrow (t_list t_string, TArrow (t_string, t_string))));
    ("string_trim",         Mono (TArrow (t_string, t_string)));
    ("string_trim_start",   Mono (TArrow (t_string, t_string)));
    ("string_trim_end",     Mono (TArrow (t_string, t_string)));
    ("string_to_uppercase", Mono (TArrow (t_string, t_string)));
    ("string_to_lowercase", Mono (TArrow (t_string, t_string)));
    ("string_chars",        Mono (TArrow (t_string, t_list t_string)));
    ("string_from_chars",   Mono (TArrow (t_list t_string, t_string)));
    ("string_repeat",       Mono (TArrow (t_string, TArrow (t_int, t_string))));
    ("string_reverse",      Mono (TArrow (t_string, t_string)));
    ("string_pad_left",     Mono (TArrow (t_string, TArrow (t_int, TArrow (t_string, t_string)))));
    ("string_pad_right",    Mono (TArrow (t_string, TArrow (t_int, TArrow (t_string, t_string)))));
    ("string_byte_length",  Mono (TArrow (t_string, t_int)));
    ("string_split_first",   Mono (TArrow (t_string, TArrow (t_string, t_option (TTuple [t_string; t_string])))));
    ("string_grapheme_count",Mono (TArrow (t_string, t_int)));
    (* Char primitives — in March, a "char" is a single-char String *)
    ("char_is_alpha",        Mono (TArrow (t_string, t_bool)));
    ("char_is_digit",        Mono (TArrow (t_string, t_bool)));
    ("char_is_alphanumeric", Mono (TArrow (t_string, t_bool)));
    ("char_is_whitespace",   Mono (TArrow (t_string, t_bool)));
    ("char_is_uppercase",    Mono (TArrow (t_string, t_bool)));
    ("char_is_lowercase",    Mono (TArrow (t_string, t_bool)));
    ("char_to_uppercase",    Mono (TArrow (t_string, t_string)));
    ("char_to_lowercase",    Mono (TArrow (t_string, t_string)));
    ("char_to_int",          Mono (TArrow (t_string, t_int)));
    ("char_from_int",        Mono (TArrow (t_int, t_string)));
    (* Comparison primitives *)
    ("compare_int",    Mono (TArrow (t_int,    TArrow (t_int,    t_int))));
    ("compare_float",  Mono (TArrow (t_float,  TArrow (t_float,  t_int))));
    ("compare_string", Mono (TArrow (t_string, TArrow (t_string, t_int))));
    (* Diverging primitives *)
    ("panic",       poly1 (fun a -> TArrow (t_string, a)));
    ("panic_",      poly1 (fun a -> TArrow (t_string, a)));
    ("todo_",       poly1 (fun a -> TArrow (t_string, a)));
    ("unreachable_",poly1 (fun a -> TArrow (t_unit,   a)));
    (* Task builtins — thunks use fn x -> expr (single Int param, ignored).
       task_spawn calls the thunk with 0, wraps result in Task(a). *)
    ("task_spawn",         poly1 (fun a -> TArrow (TArrow (t_int, a), TCon ("Task", [a]))));
    ("task_await",         poly1 (fun a -> TArrow (TCon ("Task", [a]), t_result a t_string)));
    ("task_await_unwrap",  poly1 (fun a -> TArrow (TCon ("Task", [a]), a)));
    ("task_yield",         Mono (TArrow (t_unit, t_unit)));
    ("task_spawn_steal",   poly1 (fun a -> TArrow (TCon ("WorkPool", []), TArrow (TArrow (t_int, a), TCon ("Task", [a])))));
    ("task_reductions",    Mono (TArrow (t_unit, t_int)));
    (* Zero-arg: pmap_threshold() parses as EApp(f,[]); infer_app returns the
       declared type directly, so declare as Mono Int (not TArrow unit Int). *)
    ("pmap_threshold",     Mono t_int);
    ("get_work_pool",      Mono (TCon ("WorkPool", [])));
    (* Capability builtins *)
    ("root_cap",   Mono (TCon ("Cap", [TCon ("IO", [])])));
    ("cap_narrow", poly1 (fun a -> TArrow (TCon ("Cap", [TCon ("IO", [])]), TCon ("Cap", [a]))));
    (* mint_cap: the gated proof-cap mint. Same scheme as cap_narrow
       (Cap(IO) -> Cap(a)); the GATE (declaring-module + public fn, proof-cap
       target only) is enforced in the EApp special-case, not the scheme.
       Runtime-erased: aliases cap_narrow in eval/defun/llvm (caps compile to
       null/VUnit). *)
    ("mint_cap",   poly1 (fun a -> TArrow (TCon ("Cap", [TCon ("IO", [])]), TCon ("Cap", [a]))));
    (* Phase 1: Monitor/link builtins *)
    ("monitor",      poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (TCon ("Pid", [b]), t_int))));
    ("demonitor",    Mono (TArrow (t_int, t_unit)));
    ("mailbox_size", poly1 (fun a -> TArrow (TCon ("Pid", [a]), t_int)));
    (* Phase 4: Actor state introspection — reads a named field from actor state *)
    ("get_actor_field", poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (t_string, t_option b))));
    (* Phase 4: Flush the async message queue — runs all pending handlers *)
    ("run_until_idle", Mono (TArrow (t_unit, t_unit)));
    (* Phase 6a: Register a cleanup resource with an actor — called on kill/crash *)
    ("register_resource", poly1 (fun a -> TArrow (TCon ("Pid", [a]),
        TArrow (t_string, TArrow (TArrow (t_unit, t_unit), t_unit)))));
    (* Phase 6b: Register a linear value with an actor; Drop impl resolved at runtime *)
    ("own", poly2 (fun a b -> TArrow (TCon ("Pid", [a]), TArrow (b, t_unit))));
    (* Phase 3: Epoch-based capability builtins *)
    ("get_cap",      poly1 (fun a -> TArrow (TCon ("Pid", [a]), TCon ("Option", [TCon ("Cap", [a])]))));
    ("send_checked", poly1 (fun a -> TArrow (TCon ("Cap", [a]), TArrow (a, t_atom))));
    ("revoke_cap",   poly1 (fun a -> TArrow (TCon ("Cap", [a]), t_atom)));
    ("is_cap_valid", poly1 (fun a -> TArrow (TCon ("Cap", [a]), t_bool)));
    (* Utility: convert Int to Pid (unsafe but needed for supervisor state fields) *)
    ("pid_of_int",   poly1 (fun a -> TArrow (t_int, TCon ("Pid", [a]))));
    (* Phase 5: task_spawn_link — like task_spawn but links to spawner *)
    ("task_spawn_link", poly1 (fun a -> TArrow (TArrow (t_int, a), TCon ("Task", [a]))));
    (* Phase 5B: cancellation token builtins.
       task_cancel_token_new() is zero-arg: EApp(f,[]) → infer_app returns type
       directly (see infer_app: | [], t -> t), so declare as Mono CancelToken,
       not as TArrow(t_unit, CancelToken). *)
    ("task_cancel_token_new",  Mono (TCon ("CancelToken", [])));
    ("task_cancel",            Mono (TArrow (TCon ("CancelToken", []), t_unit)));
    ("task_is_cancelled",      Mono (TArrow (TCon ("CancelToken", []), t_bool)));
    ("task_spawn_with_cancel", poly1 (fun a ->
        TArrow (TArrow (t_int, a),
        TArrow (TCon ("CancelToken", []),
                TCon ("Task", [a])))));
    ("task_cancel_by_id",      poly1 (fun a -> TArrow (TCon ("Task", [a]), t_unit)));
    (* File I/O builtins *)
    ("file_exists",     Mono (TArrow (t_string, t_bool)));
    ("file_read",       poly1 (fun e -> TArrow (t_string, t_result t_string e)));
    ("file_write",      poly1 (fun e -> TArrow (t_string, TArrow (t_string, t_result t_unit e))));
    ("file_append",     poly1 (fun e -> TArrow (t_string, TArrow (t_string, t_result t_unit e))));
    ("file_delete",     poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("file_copy",       poly1 (fun e -> TArrow (t_string, TArrow (t_string, t_result t_unit e))));
    ("file_rename",     poly1 (fun e -> TArrow (t_string, TArrow (t_string, t_result t_unit e))));
    ("file_stat",       poly1 (fun e -> TArrow (t_string, t_result (TCon ("FileStat", [])) e)));
    ("file_open",       poly1 (fun e -> TArrow (t_string, t_result t_int e)));
    ("file_read_line",  Mono (TArrow (t_int, t_option t_string)));
    ("file_read_chunk", Mono (TArrow (t_int, TArrow (t_int, t_option t_string))));
    ("file_close",      Mono (TArrow (t_int, t_unit)));
    (* Structured cleanup: try_finally(action: () -> a, cleanup: () -> b) : a *)
    ("try_finally",
      poly2 (fun a b -> TArrow (TArrow (t_int, a),
                                TArrow (TArrow (t_int, b), a))));
    (* CSV builtins — csv_next_row returns CsvRow (declared in csv.march) *)
    ("csv_open",     poly1 (fun e -> TArrow (t_string, TArrow (t_string, TArrow (t_atom, t_result t_int e)))));
    ("csv_next_row", Mono (TArrow (t_int, TCon ("CsvRow", []))));
    ("csv_close",    Mono (TArrow (t_int, t_atom)));
    (* TCP/HTTP transport builtins *)
    (* tcp_listen(port): binds+listens on port, returns Ok(listen_fd) or Err(reason) *)
    ("tcp_listen",              Mono (TArrow (t_int, t_result t_int t_string)));
    (* tcp_accept(listen_fd): blocks until a client connects, returns Ok(client_fd) or Err *)
    ("tcp_accept",              Mono (TArrow (t_int, t_result t_int t_string)));
    ("tcp_connect",             poly1 (fun e -> TArrow (t_string, TArrow (t_int, t_result t_int e))));
    ("tcp_send_all",            poly1 (fun e -> TArrow (t_int, TArrow (t_string, t_result t_unit e))));
    ("tcp_recv_all",            poly1 (fun e -> TArrow (t_int, TArrow (t_int, TArrow (t_int, t_result t_string e)))));
    ("tcp_close",               Mono (TArrow (t_int, t_unit)));
    (* tcp_peer_addr(fd): numeric IP of the connected peer; "" when unavailable *)
    ("tcp_peer_addr",           Mono (TArrow (t_int, t_string)));
    ("dns_resolve",             Mono (TArrow (t_string, t_result (t_list t_string) t_string)));
    (* tcp_recv_exact(fd, n): reads exactly n bytes, returns Result(Bytes, String) *)
    ("tcp_recv_exact",          Mono (TArrow (t_int, TArrow (t_int, t_result (TCon ("Bytes", [])) t_string))));
    (* md5(s): returns 32-char lowercase hex digest *)
    ("md5",                     Mono (TArrow (t_string, t_string)));
    ("tcp_recv_http",           poly1 (fun e -> TArrow (t_int, TArrow (t_int, t_result t_string e))));
    ("tcp_recv_http_headers",   poly1 (fun e -> TArrow (t_int, t_result (TTuple [t_string; t_int; t_bool]) e)));
    ("tcp_recv_chunk",          poly1 (fun e -> TArrow (t_int, TArrow (t_int, t_result t_string e))));
    ("tcp_recv_chunked_frame",  poly1 (fun e -> TArrow (t_int, t_result t_string e)));
    (* http_serialize_request(method, host, path, query_opt, headers, body) -> String *)
    ("http_serialize_request",  Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string,
        TArrow (t_option t_string, TArrow (t_list (TCon ("Header", [])), TArrow (t_string, t_string))))))));
    ("http_parse_response",     poly1 (fun e -> TArrow (t_string,
        t_result (TTuple [t_int; t_list (TCon ("Header", [])); t_string]) e)));
    (* http_server_listen(port, max_conns, idle_timeout, pipeline_fn) *)
    ("http_server_listen",      poly1 (fun a -> TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (TArrow (a, a), t_unit))))));
    (* http_server_spawn_n(port, n, max_conns, idle_timeout, pipeline_fn) -> Int (pid) *)
    ("http_server_spawn_n",     poly1 (fun a -> TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (TArrow (a, a), t_int)))))));
    ("http_server_wait",        Mono (TArrow (t_int, t_unit)));
    (* WebSocket builtins — WsFrame and SelectResult declared in websocket.march *)
    ("ws_recv",   Mono (TArrow (t_int, TCon ("WsFrame", []))));
    ("ws_send",   Mono (TArrow (t_int, TArrow (TCon ("WsFrame", []), t_unit))));
    ("ws_select", Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, TCon ("SelectResult", []))))));
    (* Dir I/O builtins *)
    ("dir_exists",      Mono (TArrow (t_string, t_bool)));
    ("dir_list",        poly1 (fun e -> TArrow (t_string, t_result (t_list t_string) e)));
    ("dir_mkdir",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_mkdir_p",     poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_rmdir",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    ("dir_rm_rf",       poly1 (fun e -> TArrow (t_string, t_result t_unit e)));
    (* String extra builtins *)
    ("string_last_index_of", Mono (TArrow (t_string, TArrow (t_string, t_option t_int))));
    (* App/Supervisor builtins *)
    ("worker",          poly1 (fun a -> TArrow (a, TCon ("ChildSpec", []))));
    ("Supervisor.spec", Mono (TArrow (t_atom, TArrow (t_list (TCon ("ChildSpec", [])),
                                                       TCon ("SupervisorSpec", [])))));
    (* Dynamic supervisor builtins *)
    ("dynamic_supervisor", Mono (TArrow (t_atom, TArrow (t_atom, TCon ("ChildSpec", [])))));
    ("Supervisor.start_child",
     poly1 (fun a -> TArrow (t_atom, TArrow (TCon ("ChildSpec", []),
                                             t_result (TCon ("Pid", [a])) t_string))));
    ("Supervisor.stop_child",
     Mono (TArrow (t_atom, TArrow (t_int, t_result t_unit t_string))));
    ("Supervisor.which_children",
     Mono (TArrow (t_atom, t_list t_unit)));   (* simplified; full type is List({pid,...}) *)
    ("Supervisor.count_children",
     Mono (TArrow (t_atom, TCon ("SupervisorSpec", []))));  (* simplified return type *)
    ("App.stop",        Mono (TArrow (t_unit, t_unit)));
    (* Session-typed channel builtins — Chan.send/recv/close are special-cased in
       infer_expr for proper session type advancement. These entries just put the
       names in scope; the real typing is done in the Chan.* EApp branches. *)
    ("Chan.new",    poly2 (fun a b -> TArrow (t_string, TTuple [a; b])));
    ("Chan.send",   poly2 (fun a b -> TArrow (a, TArrow (t_unit, b))));
    ("Chan.recv",   poly1 (fun a -> TArrow (t_unit, a)));
    ("Chan.close",  Mono (TArrow (t_unit, t_unit)));
    ("Chan.choose", poly2 (fun a b -> TArrow (a, TArrow (t_atom, b))));
    ("Chan.offer",  poly1 (fun a -> TArrow (a, TTuple [t_atom; a])));
    (* Byte builtins *)
    ("byte_to_char", Mono (TArrow (t_int, t_string)));
    (* Actor message-passing builtins *)
    ("actor_cast",  poly2 (fun a b -> TArrow (a, TArrow (b, t_unit))));
    ("actor_call",
      let pid_a = fresh_var 0 in
      let msg_b = fresh_var 0 in
      let ret_c = fresh_var 0 in
      Poly ([get_id pid_a; get_id msg_b; get_id ret_c], [],
        TArrow (pid_a, TArrow (msg_b, TArrow (t_int, t_result ret_c t_string)))));
    ("actor_reply", poly2 (fun a b -> TArrow (a, TArrow (b, t_unit))));
    (* Logger builtins — 0-arg variants typed as Mono(result) so foo() works *)
    ("logger_set_level",   Mono (TArrow (t_int, t_unit)));
    ("logger_get_level",   Mono t_int);
    ("logger_add_context", Mono (TArrow (t_string, TArrow (t_string, t_unit))));
    ("logger_clear_context", Mono t_unit);
    ("logger_get_context", Mono (t_list (TTuple [t_string; t_string])));
    ("logger_write",       Mono (TArrow (t_string, TArrow (t_string,
        TArrow (t_list (TTuple [t_string; t_string]),
        TArrow (t_list (TTuple [t_string; t_string]), t_unit))))));
    (* Logger v2: structured field stack.  LogValue and LogField are
       declared in stdlib/logger.march; the builtins are typed
       polymorphic on those constructors and the typechecker
       reconciles them at the call site. *)
    ("logger_add_field",     poly1 (fun a -> TArrow (t_string, TArrow (a, t_unit))));
    ("logger_field_count",   Mono t_int);
    ("logger_pop_to_depth",  Mono (TArrow (t_int, t_unit)));
    ("logger_get_fields",    poly1 (fun a -> a));
    (* Logger v2 appender pipeline.  Polymorphic so the LogEntry /
       Appender constructor types declared in stdlib/logger.march
       unify at the call site. *)
    ("logger_register_appender",
       poly1 (fun a -> TArrow (t_string, TArrow (a, t_unit))));
    ("logger_remove_appender",   Mono (TArrow (t_string, t_unit)));
    ("logger_clear_appenders",   Mono t_unit);
    ("logger_appender_names",    Mono (t_list t_string));
    ("logger_dispatch",
       poly1 (fun a -> TArrow (t_string, TArrow (t_string,
              TArrow (t_string, TArrow (a, t_unit))))));
    ("logger_set_module_level",
       Mono (TArrow (t_string, TArrow (t_int, t_unit))));
    ("logger_clear_module_level", Mono (TArrow (t_string, t_unit)));
    ("logger_module_level",       Mono (TArrow (t_string, t_int)));
    (* Process builtins — 0-arg variants typed as Mono(result) *)
    ("process_env",        Mono (TArrow (t_string, t_option t_string)));
    ("process_set_env",    Mono (TArrow (t_string, TArrow (t_string, t_unit))));
    ("process_cwd",        Mono t_string);
    ("process_exit",       Mono (TArrow (t_int, t_unit)));
    ("process_argv",       Mono (t_list t_string));
    ("process_pid",        Mono t_int);
    ("process_spawn_sync", poly1 (fun e ->
        TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("ProcessResult", [])) e))));
    ("process_spawn_lines", poly2 (fun a e ->
        TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("Seq", [a])) e))));
    (* Async (non-blocking) process spawn *)
    ("process_spawn_async", poly1 (fun e ->
        TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("LiveProcess", [])) e))));
    ("process_read_line", Mono
        (TArrow (TCon ("LiveProcess", []), t_option t_string)));
    ("process_write", Mono
        (TArrow (TCon ("LiveProcess", []), TArrow (t_string, t_unit))));
    ("process_kill_proc", Mono
        (TArrow (TCon ("LiveProcess", []), t_unit)));
    ("process_wait_proc", Mono
        (TArrow (TCon ("LiveProcess", []), t_int)));
    (* Actor self/receive builtins — 0-arg: foo() parses as EApp(f,[])
       so infer_app returns the type directly without unwrapping TArrow *)
    ("self",    Mono t_int);
    ("receive", poly1 (fun a -> a));
    (* Crypto / encoding builtins *)
    ("sha256",          Mono (TArrow (TCon ("Bytes", []), TCon ("Bytes", []))));
    (* hmac_sha256(key, msg): String-domain HMAC. Canonical signature matches
       the native runtime (march_hmac_sha256 reads march_string args) and the
       eval builtin — both return Result(Bytes, String). *)
    ("hmac_sha256",     Mono (TArrow (t_string, TArrow (t_string,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    (* hmac_sha256_bytes(key, msg): Bytes-domain HMAC, bare Bytes result *)
    ("hmac_sha256_bytes", Mono (TArrow (TCon ("Bytes", []), TArrow (TCon ("Bytes", []),
        TCon ("Bytes", [])))));
    ("pbkdf2_sha256",   Mono (TArrow (t_string, TArrow (TCon ("Bytes", []),
        TArrow (t_int, TArrow (t_int,
        TCon ("Result", [TCon ("Bytes", []); t_string])))))));
    ("base64_encode",   Mono (TArrow (TCon ("Bytes", []), t_string)));
    ("base64_decode",   Mono (TArrow (t_string,
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("random_bytes",    Mono (TArrow (t_int, TCon ("Bytes", []))));
    (* stdlib_* variants — used by module wrappers that shadow the base names.
       stdlib_base64_encode accepts String only at the type-checker level;
       callers should convert Bytes to String with bytes_to_string first. *)
    ("stdlib_sha256",         Mono (TArrow (t_string, t_string)));
    ("stdlib_random_bytes",   Mono (TArrow (t_int, TCon ("Bytes", []))));
    ("stdlib_base64_encode",  Mono (TArrow (t_string, t_string)));
    ("stdlib_base64_decode",  Mono (TArrow (t_string,
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_hmac_sha256",    Mono (TArrow (t_string, TArrow (t_string,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    (* Compress builtins — gzip, deflate, zstd, brotli C-level shims.
       Called directly by stdlib/compress.march and any code that needs
       compression without `import Compress` (not in stdlib_file_list). *)
    ("stdlib_gzip_encode",    Mono (TArrow (TCon ("Bytes", []), TArrow (t_int,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    ("stdlib_gzip_decode",    Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_deflate_encode", Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_deflate_decode", Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_zstd_encode",    Mono (TArrow (TCon ("Bytes", []), TArrow (t_int,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    ("stdlib_zstd_decode",    Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    ("stdlib_brotli_encode",  Mono (TArrow (TCon ("Bytes", []), TArrow (t_int,
        TCon ("Result", [TCon ("Bytes", []); t_string])))));
    ("stdlib_brotli_decode",  Mono (TArrow (TCon ("Bytes", []),
        TCon ("Result", [TCon ("Bytes", []); t_string]))));
    (* NativeArray builtins — flat OCaml arrays for fast numeric loops (P10).
       NativeIntArr / NativeFloatArr are opaque types (0-arity constructors).
       These builtins are interpreter-path only; compiled mode support is
       tracked in specs/optimizations.md P10 Phase 2. *)
    (* Int array *)
    ("native_int_arr_make",
       Mono (TArrow (t_int, TArrow (t_int, TCon ("NativeIntArr", [])))));
    ("native_int_arr_length",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_get",
       Mono (TArrow (TCon ("NativeIntArr", []), TArrow (t_int, t_int))));
    ("native_int_arr_set",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (t_int, TArrow (t_int, TCon ("NativeIntArr", []))))));
    ("native_int_arr_sum",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_map",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (TArrow (t_int, t_int), TCon ("NativeIntArr", [])))));
    ("native_int_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeIntArr", []),
                   TArrow (TArrow (a, TArrow (t_int, a)), a)))));
    ("native_int_arr_from_list",
       Mono (TArrow (t_list t_int, TCon ("NativeIntArr", []))));
    ("native_int_arr_to_list",
       Mono (TArrow (TCon ("NativeIntArr", []), t_list t_int)));
    (* Float array *)
    ("native_float_arr_make",
       Mono (TArrow (t_int, TArrow (t_float, TCon ("NativeFloatArr", [])))));
    ("native_float_arr_length",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_int)));
    ("native_float_arr_get",
       Mono (TArrow (TCon ("NativeFloatArr", []), TArrow (t_int, t_float))));
    ("native_float_arr_set",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (t_int, TArrow (t_float, TCon ("NativeFloatArr", []))))));
    ("native_float_arr_sum",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_float)));
    ("native_float_arr_map",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (TArrow (t_float, t_float), TCon ("NativeFloatArr", [])))));
    ("native_float_arr_fold",
       poly1 (fun a ->
         TArrow (a, TArrow (TCon ("NativeFloatArr", []),
                   TArrow (TArrow (a, TArrow (t_float, a)), a)))));
    ("native_float_arr_from_list",
       Mono (TArrow (t_list t_float, TCon ("NativeFloatArr", []))));
    ("native_float_arr_to_list",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_list t_float)));
    ("native_int_arr_filter_mask",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (TCon ("TypedArray", [t_bool]), TCon ("NativeIntArr", [])))));
    ("native_float_arr_filter_mask",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (TCon ("TypedArray", [t_bool]), TCon ("NativeFloatArr", [])))));
    (* TypedArray builtins — contiguous native arrays for columnar DataFrame storage *)
    ("typed_array_create",   poly1 (fun a ->
        TArrow (t_int, TArrow (a, TCon ("TypedArray", [a])))));
    ("typed_array_get",      poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, a))));
    ("typed_array_set",      poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, TArrow (a, TCon ("TypedArray", [a]))))));
    ("typed_array_length",   poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), t_int)));
    ("typed_array_slice",    poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (t_int, TArrow (t_int, TCon ("TypedArray", [a]))))));
    ("typed_array_map",      poly2 (fun a b ->
        TArrow (TCon ("TypedArray", [a]), TArrow (TArrow (a, b), TCon ("TypedArray", [b])))));
    ("typed_array_filter",   poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), TArrow (TCon ("TypedArray", [t_bool]), TCon ("TypedArray", [a])))));
    ("typed_array_fold",     poly2 (fun a b ->
        TArrow (TCon ("TypedArray", [a]), TArrow (b, TArrow (TArrow (b, TArrow (a, b)), b)))));
    ("typed_array_from_list", poly1 (fun a ->
        TArrow (t_list a, TCon ("TypedArray", [a]))));
    ("typed_array_to_list",  poly1 (fun a ->
        TArrow (TCon ("TypedArray", [a]), t_list a)));
    (* RingBuf builtins — mutable fixed-capacity circular buffer.
       RingBuf(a) is a non-sendable type: the typechecker rejects it in send() payloads. *)
    ("ring_buf_make",        poly1 (fun a ->
        TArrow (t_int, TCon ("RingBuf", [a]))));
    ("ring_buf_push",        poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), TArrow (a, t_unit))));
    ("ring_buf_pop",         poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_option a)));
    ("ring_buf_get",         poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), TArrow (t_int, t_option a))));
    ("ring_buf_peek_oldest", poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_option a)));
    ("ring_buf_peek_newest", poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_option a)));
    ("ring_buf_size",        poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_int)));
    ("ring_buf_cap",         poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_int)));
    ("ring_buf_clear",       poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_unit)));
    ("ring_buf_to_list",     poly1 (fun a ->
        TArrow (TCon ("RingBuf", [a]), t_list a)));
    (* TLS builtins — tls_client_ctx, tls_server_ctx, etc. *)
    ("tls_client_ctx",       poly1 (fun e ->
        TArrow (t_string, TArrow (t_list t_string, TArrow (t_int, TArrow (t_int,
          t_result t_int e))))));
    ("tls_server_ctx",       poly1 (fun e ->
        TArrow (t_string, TArrow (t_string, TArrow (t_string, TArrow (t_list t_string,
          TArrow (t_int, t_result t_int e)))))));
    ("tls_connect",          poly1 (fun e ->
        TArrow (t_int, TArrow (t_int, TArrow (t_string, t_result t_int e)))));
    ("tls_accept",           poly1 (fun e ->
        TArrow (t_int, TArrow (t_int, t_result t_int e))));
    ("tls_read",             poly1 (fun e ->
        TArrow (t_int, TArrow (t_int, t_result t_string e))));
    ("tls_write",            poly1 (fun e ->
        TArrow (t_int, TArrow (t_string, t_result t_int e))));
    ("tls_close",            Mono (TArrow (t_int, t_unit)));
    ("tls_ctx_free",         Mono (TArrow (t_int, t_unit)));
    ("tls_negotiated_alpn",  Mono (TArrow (t_int, t_option t_string)));
    ("tls_peer_cn",          Mono (TArrow (t_int, t_option t_string)));
    (* HTML template builtins — generated by ~H sigil desugar *)
    (* html_auto_escape: ∀a. a -> String
       Accepts any value: Html.Safe, IOList, String, or other (escaped).
       The desugar emits html_auto_escape(x) for each ${x} in ~H sigils. *)
    ("html_auto_escape",   poly1 (fun a -> TArrow (a, t_string)));
    (* iolist_hash_fnv1a: IOList -> String
       FNV-1a 64-bit hash over segments, returns 16-char hex string.
       Used by IOList.hash and Html.content_hash for ETag generation. *)
    ("iolist_hash_fnv1a",  Mono (TArrow (TCon ("IOList", []), t_string)));
    (* Distributed OTP L4 — function-by-identity remote registry.
       remote_ref_hashes(module, fn) returns (sig_hash, impl_hash) from the CAS
       pipeline (compiled path) or deterministic FNV-1a hashes (eval path).
       remote_register_stub(impl_hash, sig_hash, stub) enrolls a marshalling stub
       in the C-level registry; stub type is unconstrained (poly) so the caller
       can pass any function value. Returns 0 on success, -1 on failure.
       remote_count() returns the number of enrolled remote targets (testing). *)
    ("remote_ref_hashes",    Mono (TArrow (t_string, TArrow (t_string, TTuple [t_string; t_string]))));
    ("remote_register_stub", poly1 (fun a -> TArrow (t_string, TArrow (t_string, TArrow (a, t_int)))));
    ("remote_count",         Mono t_int);
    (* Compiler-emitted enroll/stub dispatch builtins (L4).
       remote_check(impl_hash, sig_hash): 0=not enrolled, 1=sig match, 2=TypeMismatch.
       remote_invoke(impl_hash, args): calls the enrolled stub or None if not found. *)
    ("remote_check",  Mono (TArrow (t_string, TArrow (t_string, t_int))));
    ("remote_invoke", Mono (TArrow (t_string, TArrow (TCon ("List", [t_int]),
                        TCon ("Option", [TCon ("Result", [TCon ("List", [t_int]); t_string])])))));
  ]

let builtin_types : (string * int) list =
  [ ("Int",    0); ("Float",  0); ("Bool",  0); ("String", 0);
    ("Char",   0); ("Byte",   0); ("Atom",  0); ("Unit",   0);
    ("List",   1); ("Option", 1); ("Array", 1); ("Set",    1); ("Seq",    1);
    ("TypedArray", 1);
    ("Result", 2); ("Map",    2);
    ("Pid",    1); ("Cap",    1); ("Future",1); ("Stream", 1);
    ("Task",   1); ("WorkPool", 0); ("Node",   0);
    ("ChildSpec", 0); ("SupervisorSpec", 0);
    ("Vector", 2); ("Matrix", 3); ("NDArray", 2);
    (* Tagged(X, T) — specialization tag constructor: phantom policy/width tags *)
    ("Tagged", 2);
    (* Alloc and Panic — future capability roots excluded from realtime contexts *)
    ("Alloc", 0); ("Panic", 0);
    (* Capability token types — used as arguments to Cap(X).
       Mirrors the full 18-entry hierarchy in lib/caps/cap_lattice.ml. *)
    ("IO",            0); ("IO.Console",    0); ("IO.FileSystem", 0);
    ("IO.FileRead",   0); ("IO.FileWrite",  0); ("IO.Network",    0);
    ("IO.NetConnect", 0); ("IO.NetListen",  0); ("IO.Process",    0);
    ("IO.Clock",      0); ("IO.Random",     0); ("IO.Database",   0);
    ("IO.Spawn",      0); ("IO.Mut",        0); ("IO.Telemetry",  0);
    ("IO.Foreign",    0); ("IO.Foreign.Blocking", 0); ("IO.NetConnect.TLS", 0);
    (* NativeArray opaque types — flat numeric arrays (P10) *)
    ("NativeIntArr",   0); ("NativeFloatArr", 0); ]

(** Built-in constructor table for Option, Result, and List, which are
    pre-registered types.  User-declared types are added via [DType].
    Each constructor is registered under both its bare name ("Some") and its
    type-qualified name ("Option.Some") so that users can write either form. *)
let builtin_ctors : (string * ctor_info) list =
  let mk_var s = Ast.TyVar { txt = s; span = Ast.dummy_span } in
  let mk_list_ty s = Ast.TyCon ({ txt = "List"; span = Ast.dummy_span }, [mk_var s]) in
  let some_ci  = { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = [mk_var "a"]; ci_vis = Ast.Public } in
  let none_ci  = { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = []; ci_vis = Ast.Public } in
  let ok_ci    = { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "a"]; ci_vis = Ast.Public } in
  let err_ci   = { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "e"]; ci_vis = Ast.Public } in
  let nil_ci   = { ci_type = "List";   ci_params = ["a"];      ci_arg_tys = []; ci_vis = Ast.Public } in
  let cons_ci  = { ci_type = "List";   ci_params = ["a"];
                   ci_arg_tys = [mk_var "a"; mk_list_ty "a"]; ci_vis = Ast.Public } in
  [ ("Some",        some_ci);  ("Option.Some", some_ci);
    ("None",        none_ci);  ("Option.None", none_ci);
    ("Ok",          ok_ci);    ("Result.Ok",   ok_ci);
    ("Err",         err_ci);   ("Result.Err",  err_ci);
    ("Nil",         nil_ci);   ("List.Nil",    nil_ci);
    ("Cons",        cons_ci);  ("List.Cons",   cons_ci);
  ]

let base_env errors type_map =
  let env = make_env errors type_map in
  let env = bind_vars builtin_bindings env in
  let env = bind_vars builtin_interface_bindings env in
  { env with
    types      = List.fold_left (fun m (k, v) -> StrMap.add k v m) StrMap.empty builtin_types;
    ctors      = List.fold_left (fun m (k, v) -> add_ctor k v m) StrMap.empty builtin_ctors;
    interfaces = List.fold_left (fun m (k, v) -> StrMap.add k v m) StrMap.empty builtin_interfaces;
    impls      = List.fold_left (fun m (k, v) ->
                   let lst = Option.value ~default:[] (StrMap.find_opt k m) in
                   StrMap.add k (v :: lst) m) StrMap.empty builtin_impls;
  }

(* =================================================================
   §10  Unification
   ================================================================= *)

(** Format a type for display in an error message.
    Uses pretty-printing with line-wrapping for long types. *)
let format_ty_for_error t =
  let flat = pp_ty t in
  if String.length flat > 50 then
    "\n    " ^ String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 t))
  else "`" ^ flat ^ "`"

(** Report a type mismatch with a conversational Elm-style message. *)
let report_mismatch env ~span ~reason expected found =
  (* Build headline, using pretty-printing for long types.
     Convention: `expected` = inferred type of the expression (what was provided);
                 `found`    = required type from context (what was needed).
     Headline uses standard compiler phrasing: "expected <required> but got <provided>". *)
  let exp_str = format_ty_for_error expected in
  let fnd_str = format_ty_for_error found in
  let headline =
    if String.length (pp_ty expected) > 50 || String.length (pp_ty found) > 50 then
      Printf.sprintf "expected:\n    %s\nbut got:\n    %s"
        (String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 found)))
        (String.concat "\n    " (String.split_on_char '\n' (pp_ty_pretty ~indent:4 ~width:60 expected)))
    else
      render_parts
        [ MPText "expected "; MPText fnd_str;
          MPText " but got "; MPText exp_str; MPText "." ]
  in
  let why_note =
    match reason with
    | None   -> []
    | Some r -> [ string_of_reason r ]
  in
  (* Contextual hint: when both types share the same constructor but differ
     in one argument, identify which argument mismatches. *)
  let mismatch_note =
    match repr expected, repr found with
    | TCon (name1, args1), TCon (name2, args2)
      when name1 = name2 && List.length args1 = List.length args2 ->
      (match find_arg_mismatch name1 args1 args2 with
       | Some (i, cname, exp_arg, fnd_arg) ->
         let ordinal = match i with 1 -> "1st" | 2 -> "2nd" | 3 -> "3rd"
           | n -> string_of_int n ^ "th" in
         [ Printf.sprintf "The %s argument of `%s` mismatches: expected `%s` but got `%s`."
             ordinal cname (pp_ty fnd_arg) (pp_ty exp_arg) ]
       | None -> [])
    | TRecord flds1, TRecord flds2 ->
      (* Find first field that differs *)
      let notes = List.filter_map (fun (name, t1) ->
        match List.assoc_opt name flds2 with
        | Some t2 when pp_ty t1 <> pp_ty t2 ->
          Some (Printf.sprintf "Field `%s` mismatches: expected `%s` but got `%s`."
            name (pp_ty t2) (pp_ty t1))
        | None ->
          Some (Printf.sprintf "Field `%s` is present in the expected type but missing in the found type." name)
        | _ -> None) flds1
      in
      (match notes with n :: _ -> [n] | [] -> [])
    | _ -> []
  in
  (* Common-case hints for frequently-confused types.
     NOTE: `expected` here = the inferred type of the expression (what was provided);
           `found`    here = the required type from context (what was needed).
     Matches are on (provided, required) order. *)
  let common_hint =
    match repr expected, repr found with
    | TCon ("Int", []), TCon ("Float", []) ->
      (* User provided Int, Float was required *)
      [ "Int and Float are distinct types in March.\n\
         Use `int_to_float(x)` to convert, or write a Float literal like `1.0`." ]
    | TCon ("Float", []), TCon ("Int", []) ->
      (* User provided Float, Int was required *)
      [ "Float and Int are distinct types in March.\n\
         Use `float_to_int(x)` to truncate, or write an Int literal like `1`." ]
    | TCon ("Int", []), TCon ("Bool", []) ->
      (* Expression was Int but Bool was required *)
      [ "March does not coerce Int to Bool.\n\
         Try an explicit comparison, e.g. `x != 0`." ]
    | TCon ("Int", []), TCon ("String", []) ->
      (* Expression was Int but String was required *)
      [ "Use `int_to_string(x)` to convert an Int to a String." ]
    | TCon ("Float", []), TCon ("String", []) ->
      (* Expression was Float but String was required *)
      [ "Use `float_to_string(x)` to convert a Float to a String." ]
    | TArrow _, _ ->
      [ "This value is a function. Did you forget to apply it to its arguments?" ]
    | _, TArrow _ ->
      [ "A function was expected here.\n\
         Did you mean to pass this as a callback?" ]
    | _ -> []
  in
  (* Same-printed-name disambiguation.
     March has a single global type namespace, so a user-defined type can share
     its printed name with a stdlib type (e.g. local `Config` vs `Config` from the
     standard library).  When that happens unification fails but both sides render
     identically, yielding the baffling "expected `Config` but got `Config`".
     Detect the case — the two reprs print the same string but are structurally
     distinct — and explain it.  We compare structural shapes (TCon vs TRecord,
     constructor name, argument count) rather than exact identity so we only fire
     when the types genuinely differ despite printing alike. *)
  let same_name_note =
    let pe = pp_ty (repr expected) and pf = pp_ty (repr found) in
    let structurally_distinct =
      match repr expected, repr found with
      | TCon (n1, a1), TCon (n2, a2) ->
        n1 <> n2 || List.length a1 <> List.length a2
      | TCon _, TRecord _ | TRecord _, TCon _ -> true
      | _ -> false
    in
    if pe = pf && structurally_distinct then
      [ Printf.sprintf
          "Two distinct types are both named `%s` — they print the same but have \
           different definitions. March has a single global type namespace, so a \
           local type collides with any same-named type from another module or the \
           standard library.\n\
           Rename one of them (e.g. `App%s`), or qualify/avoid the import that \
           brings the other `%s` into scope."
          pe pe pe ]
    else []
  in
  let labels =
    match reason with
    | Some r ->
      (match span_of_reason r with
       | Some rsp when rsp <> span ->
         [ { Err.lbl_span = rsp;
             lbl_message  = "the expected type comes from here" } ]
       | _ -> [])
    | None -> []
  in
  Err.report env.errors
    { Err.severity = Error; span; message = headline;
      labels; notes = why_note @ mismatch_note @ common_hint @ same_name_note;
      code = None; fix = None }

(** Structural equality for session types (used by [unify] for [TChan] cases).
    Intentionally ignores payload types — only checks session structure shape. *)
let rec session_ty_equal s1 s2 =
  match s1, s2 with
  | SEnd, SEnd -> true
  | SError, SError -> true
  | SSend (_, s1'), SSend (_, s2') -> session_ty_equal s1' s2'
  | SRecv (_, s1'), SRecv (_, s2') -> session_ty_equal s1' s2'
  | SChoose bs1, SChoose bs2 | SOffer bs1, SOffer bs2 ->
    List.length bs1 = List.length bs2 &&
    List.for_all2 (fun (l1, s1') (l2, s2') ->
        l1 = l2 && session_ty_equal s1' s2') bs1 bs2
  | SRec (x1, s1'), SRec (x2, s2') -> x1 = x2 && session_ty_equal s1' s2'
  | SVar x1, SVar x2 -> x1 = x2
  | SMSend (r1, _, s1'), SMSend (r2, _, s2') -> r1 = r2 && session_ty_equal s1' s2'
  | SMRecv (r1, _, s1'), SMRecv (r2, _, s2') -> r1 = r2 && session_ty_equal s1' s2'
  | _ -> false

(** Exact structural equality including payload types.
    Used by MPST mergeability check to determine if branches can be merged.
    Two branches can be merged only if they are completely identical. *)
let rec session_ty_exact_equal s1 s2 =
  match s1, s2 with
  | SEnd, SEnd -> true
  | SError, SError -> true
  | SSend (t1, s1'), SSend (t2, s2') ->
    pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SRecv (t1, s1'), SRecv (t2, s2') ->
    pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SChoose bs1, SChoose bs2 | SOffer bs1, SOffer bs2 ->
    List.length bs1 = List.length bs2 &&
    List.for_all2 (fun (l1, s1') (l2, s2') ->
        l1 = l2 && session_ty_exact_equal s1' s2') bs1 bs2
  | SRec (x1, s1'), SRec (x2, s2') -> x1 = x2 && session_ty_exact_equal s1' s2'
  | SVar x1, SVar x2 -> x1 = x2
  | SMSend (r1, t1, s1'), SMSend (r2, t2, s2') ->
    r1 = r2 && pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | SMRecv (r1, t1, s1'), SMRecv (r2, t2, s2') ->
    r1 = r2 && pp_ty t1 = pp_ty t2 && session_ty_exact_equal s1' s2'
  | _ -> false

(** Normalize type-level nat arithmetic.
    Reduces concrete sub-expressions and applies identity / annihilation laws.
    The result is in weak-head normal form: outer-most TNatOp is simplified as
    far as possible, sub-expressions are recursively normalized. *)
let rec normalize_tnat t =
  match repr t with
  | TNatOp (op, a, b) ->
    let a = normalize_tnat a and b = normalize_tnat b in
    (match op, a, b with
     | Ast.NatAdd, TNat m, TNat n  -> TNat (m + n)
     | Ast.NatAdd, t',    TNat 0   -> t'
     | Ast.NatAdd, TNat 0, t'      -> t'
     | Ast.NatMul, TNat m, TNat n  -> TNat (m * n)
     | Ast.NatMul, _,     TNat 0   -> TNat 0
     | Ast.NatMul, TNat 0, _       -> TNat 0
     | Ast.NatMul, t',    TNat 1   -> t'
     | Ast.NatMul, TNat 1, t'      -> t'
     | _                           -> TNatOp (op, a, b))
  | t -> t

(** Assert that a [TRecord]'s field list satisfies the sorted-name invariant.
    Raises [Failure] with a diagnostic if the invariant is violated.
    Called at every TRecord unification site to catch construction-path bugs
    early — a misordered TRecord produces confusing "type mismatch" errors
    that look like unrelated failures.
    Only active in debug builds (guarded by [Sys.getenv_opt]) to avoid overhead
    in production; set [MARCH_DEBUG_TC=1] to enable. *)
let assert_trecord_sorted flds label =
  match Sys.getenv_opt "MARCH_DEBUG_TC" with
  | Some _ ->
    let names = List.map fst flds in
    let sorted = List.sort String.compare names in
    if names <> sorted then
      failwith (Printf.sprintf
        "INVARIANT VIOLATION: TRecord %s has unsorted fields [%s]; expected [%s]. \
         All TRecord values must be constructed with List.sort."
        label
        (String.concat ", " names)
        (String.concat ", " sorted))
  | None -> ()

(** Forward ref to [expand_record], which is defined later because it depends on
    [surface_ty].  [unify] uses it to reconcile a nominal record [TCon] with the
    structural [TRecord] the same type expands to elsewhere (see the
    [TCon]/[TRecord] case in [unify]).  Wired up immediately after
    [expand_record] is defined. *)
let expand_record_ref : (env -> ty -> ty option) ref =
  ref (fun _ _ -> None)

(** Unify [t1] and [t2], reporting any mismatch to [env.errors].
    Uses [TError] as a recovery sentinel — if either side is [TError]
    the constraint is silently satisfied (the error was already reported). *)
let rec unify env ~span ?(reason = None) t1 t2 =
  let t1 = normalize_tnat t1 and t2 = normalize_tnat t2 in
  match t1, t2 with
  (* Error sentinel absorbs everything *)
  | TError, _ | _, TError -> ()

  (* Same variable — trivially unified *)
  | TVar r1, TVar r2 when r1 == r2 -> ()

  (* Bind a variable *)
  | TVar r, t | t, TVar r ->
    (match !r with
     | Unbound (id, level) ->
       if occurs id level t then begin
         report_mismatch env ~span ~reason t1 t2;
         r := Link TError
       end else begin
         (* Proof-cap forge hook: if [r] is a tagged [cap_narrow]-result inner
            var (see [cap_producer_ivars]), reject the instant it is bound to a
            nominal proof cap — a cap_narrow value can NEVER become a proof cap,
            in any position or flow (direct, let-generalized, or laundered
            through a polymorphic function). If it binds to ANOTHER var, propagate
            the tag so the check fires when that var is eventually pinned. IO caps
            are not in [proof_caps], so IO-lattice narrowing is never affected. *)
         (match Hashtbl.find_opt env.cap_producer_ivars id with
          | Some cn_sp ->
            let forge_error p =
              Err.error env.errors ~span:cn_sp
                (render_parts [
                  MPText "cap_narrow cannot produce "; MPCode ("Cap(" ^ p ^ ")");
                  MPText " — "; MPCode ("Cap(" ^ p ^ ")");
                  MPText " is a proof capability, not an IO capability.";
                  MPBreak;
                  MPText "hint: a proof capability may only be minted by a public function of its declaring module via ";
                  MPCode "mint_cap";
                  MPText "; cap_narrow only attenuates IO capabilities." ])
            in
            (match repr t with
             (* Tag is on the inner cap var: [a] binds directly to a proof cap. *)
             | TCon (p, []) when List.mem_assoc p env.proof_caps -> forge_error p
             (* Tag is on a whole-value var (laundered result): binds to Cap(P). *)
             | TCon ("Cap", [inner]) ->
               (match repr inner with
                | TCon (p, []) when List.mem_assoc p env.proof_caps -> forge_error p
                | TVar r2 ->
                  (* Cap of an unbound var: propagate the tag to the inner var. *)
                  (match !r2 with
                   | Unbound (id2, _) -> Hashtbl.replace env.cap_producer_ivars id2 cn_sp
                   | Link _ -> ())
                | _ -> ())
             (* Binds to another bare var: propagate the tag so the check fires
                when that var is eventually pinned. *)
             | TVar r2 ->
               (match !r2 with
                | Unbound (id2, _) -> Hashtbl.replace env.cap_producer_ivars id2 cn_sp
                | Link _ -> ())
             | _ -> ())
          | None -> ());
         r := Link t
       end
     | Link _ -> assert false)  (* repr should have resolved links *)

  | TCon (n1, a1), TCon (n2, a2) ->
    if n1 = n2 && List.length a1 = List.length a2 then
      List.iter2 (unify env ~span ~reason) a1 a2
    else
      (report_mismatch env ~span ~reason t1 t2)

  | TArrow (a1, b1), TArrow (a2, b2) ->
    unify env ~span ~reason a1 a2;
    unify env ~span ~reason b1 b2

  | TTuple ts1, TTuple ts2 when List.length ts1 = List.length ts2 ->
    List.iter2 (unify env ~span ~reason) ts1 ts2

  | TRecord f1, TRecord f2 ->
    (* Defensive: check the sorted-name invariant when debug mode is on.
       A TRecord with unsorted fields produces confusing mismatches here
       because ns1 <> ns2 even if the field sets are identical. *)
    assert_trecord_sorted f1 "lhs";
    assert_trecord_sorted f2 "rhs";
    let ns1 = List.map fst f1 and ns2 = List.map fst f2 in
    if ns1 <> ns2 then
      report_mismatch env ~span ~reason t1 t2
    else
      List.iter2
        (fun (_, t1) (_, t2) -> unify env ~span ~reason t1 t2)
        f1 f2

  (* Reconcile a nominal record [TCon] with its structural [TRecord] form.
     A record type's *name* and its *field structure* are interchangeable in
     March's structural record model, but the two representations reach [unify]
     from different paths: [surface_ty] expands a record annotation to a
     [TRecord], while lighter-weight converters (notably [prebind_fn_scheme],
     which pre-binds cross-module function signatures in Pass 1 without record
     field information) leave the same type as a nominal [TCon(Name)].  When a
     cross-module qualified reference like `Cfg.Site` meets the owning module's
     own structural use, the two sides collide as `TCon` vs `TRecord`.  Expand
     the [TCon] side via the [expand_record_ref] hook (a no-op unless [Name]
     denotes a known record that is not also a colliding variant — variants and
     opaque types stay nominal) and retry; fall back to a genuine mismatch if it
     does not name an unambiguous record. *)
  | (TCon _ as tc), (TRecord _ as tr) | (TRecord _ as tr), (TCon _ as tc) ->
    (match !expand_record_ref env tc with
     | Some (TRecord _ as expanded) -> unify env ~span ~reason expanded tr
     | _ -> report_mismatch env ~span ~reason t1 t2)

  | TLin (l1, inner1), TLin (l2, inner2) when l1 = l2 ->
    unify env ~span ~reason inner1 inner2

  (* Transparent coercion: a linear/affine value is structurally the same
     type as its inner (unrestricted) type.  This allows e.g. a field of
     type [linear Int] to unify with an expected [Int] at a use site while
     still preserving the TLin wrapper for linearity tracking in let-bindings. *)
  | TLin (_, inner), other | other, TLin (_, inner) ->
    unify env ~span ~reason inner other

  | TNat n1, TNat n2 when n1 = n2 -> ()

  (* Structural unification for nat ops that could not be fully normalized
     (e.g. both sides have the same un-solved variable structure). *)
  | TNatOp (op1, a1, b1), TNatOp (op2, a2, b2) when op1 = op2 ->
    unify env ~span ~reason a1 a2;
    unify env ~span ~reason b1 b2

  (* Solve: one side is a concrete nat, the other is a partially-known op.
     E.g. TVar a + TNat 2 = TNat 5  →  a = 3. *)
  | TNatOp (op, a, b), TNat n ->
    solve_nat_eq env ~span ~reason op a b n
  | TNat n, TNatOp (op, a, b) ->
    solve_nat_eq env ~span ~reason op a b n

  (* Session-typed channels unify by checking their current session states match. *)
  | TChan r1, TChan r2 ->
    if not (session_ty_equal !r1 !r2) then
      Err.error env.errors ~span
        (Printf.sprintf
           "Session type mismatch: expected channel at `%s` but found `%s`."
           (pp_session_ty !r1) (pp_session_ty !r2))

  | _ ->
    report_mismatch env ~span ~reason t1 t2

(** Solve a type-level nat equation: (op a b) = n.
    Handles exactly the cases where one operand is an unbound TVar and
    the other is a concrete TNat, so we can isolate the variable.
    Falls back to [report_mismatch] for anything more complex. *)
and solve_nat_eq env ~span ~reason op a b n =
  match op, a, b with
  (* a + k = n  →  a = n - k  (when n >= k) *)
  | Ast.NatAdd, TVar _, TNat k when n >= k ->
    unify env ~span ~reason a (TNat (n - k))
  (* k + a = n  →  a = n - k  (when n >= k) *)
  | Ast.NatAdd, TNat k, TVar _ when n >= k ->
    unify env ~span ~reason b (TNat (n - k))
  (* a * k = n  →  a = n / k  (when k divides n) *)
  | Ast.NatMul, TVar _, TNat k when k <> 0 && n mod k = 0 ->
    unify env ~span ~reason a (TNat (n / k))
  (* k * a = n  →  a = n / k  (when k divides n) *)
  | Ast.NatMul, TNat k, TVar _ when k <> 0 && n mod k = 0 ->
    unify env ~span ~reason b (TNat (n / k))
  | _ ->
    report_mismatch env ~span ~reason (TNatOp (op, a, b)) (TNat n)

(* =================================================================
   §11  Surface-type → internal-type conversion
   ================================================================= *)

(** True when [name] denotes a variant/sum type in scope — i.e. some
    constructor has it as its parent type ([ci_type], matched bare or as a
    [.name] suffix since [ci_type] may be module-qualified).

    Records register in [env.records] under their BARE name globally, so a
    user's `type Color = Red | Green | Blue` collides in that flat namespace
    with, e.g., stdlib `Plot.Color = { r, g, b }`.  Without this guard the
    record-structural expansion below (and in [register_impl_shape]) rewrites
    the variant's `impl Eq(Color)` to the record's `TRecord{r,g,b}` shape,
    which then never matches the variant's `TCon("Color")` dispatch target —
    the derived impl becomes invisible and the type "does not implement Eq".
    A variant type is never itself a record, so suppressing the expansion for
    variant names only removes incorrect expansions. *)
let name_is_variant env name =
  let matches ci_type =
    ci_type = name ||
    (let n = String.length name and l = String.length ci_type in
     l > n && ci_type.[l - n - 1] = '.' && String.sub ci_type (l - n) n = name)
  in
  StrMap.exists
    (fun _ cis -> List.exists (fun (ci : ctor_info) -> matches ci.ci_type) cis)
    env.ctors

(** Convert a surface [Ast.ty] to an internal [ty].
    [tvars] accumulates a mapping from type-variable *names* to fresh
    unification-variable ids (so that two mentions of [a] in the same
    annotation get the same variable). *)
let rec surface_ty env ~(tvars : (string * ty) list ref) (s : Ast.ty) : ty =
  match s with
  | Ast.TyCon (name, args) ->
    (* Special case: Chan(Role, Proto) — session-typed channel endpoint.
       Users write Chan(RoleName, ProtoName) in type annotations.
       The parser produces TyCon("Chan", [TyCon("Role",[]), TyCon("Proto",[])]).
       We intercept this before the normal type-lookup path. *)
    (match name.txt, args with
     | "Chan", [Ast.TyCon (role, []); Ast.TyCon (proto, [])] ->
       (match StrMap.find_opt proto.txt env.protocols with
        | None ->
          Err.error env.errors ~span:proto.span
            (Printf.sprintf "I don't know a protocol called `%s`." proto.txt);
          TChan (ref SError)
        | Some pi ->
          (match List.assoc_opt role.txt pi.pi_projections with
           | None ->
             Err.error env.errors ~span:role.span
               (Printf.sprintf
                  "Protocol `%s` has no role called `%s`.\n\
                   Known roles: %s"
                  proto.txt role.txt
                  (String.concat ", " (List.map fst pi.pi_projections)));
             TChan (ref SError)
           | Some sty ->
             TLin (Ast.Linear, TChan (ref sty))))
     | "Chan", _ when name.txt = "Chan" ->
       Err.error env.errors ~span:name.span
         "Chan expects exactly two type arguments: Chan(RoleName, ProtocolName)";
       TChan (ref SError)
     | _ ->
    let arity = match lookup_type name.txt env with
      | Some a -> a
      | None   ->
        (* Try qualified module resolution: "Mod.Type" *)
        match resolve_qualified_type name.txt env with
        | _, Some a -> a
        | _ ->
          Err.error env.errors ~span:name.span
            (qualified_error_msg name.txt env);
          0
    in
    (* March uses a single global type namespace: a type declared inside a
       module has its *bare* name as its canonical identity.  Both the type's
       own registration and the result type of its constructors use the bare
       form (see the constructor `ci_type = name.txt` sites and the "ci_type is
       the BARE type name" note in Pass 1b).  A *qualified* reference like
       `Token.Token` from outside the module must therefore resolve to the SAME
       nominal `TCon` as the bare `Token`, otherwise a value produced inside the
       module (bare) fails to unify against the qualified annotation with the
       baffling "expected `Token.Token` but got `Token`".  Canonicalize the
       constructor name to its bare suffix whenever that suffix denotes a type
       of the same arity in scope. *)
    let canon_name =
      (* The bare suffix is the component after the LAST '.' (the type's own
         name); everything before is the module path.  Using rindex rather than
         [split_qualified] (which splits at the FIRST dot for module-load
         purposes) also canonicalizes arbitrarily-nested refs like `A.B.Type`. *)
      match String.rindex_opt name.txt '.' with
      | Some i ->
        let bare = String.sub name.txt (i + 1) (String.length name.txt - i - 1) in
        (match lookup_type bare env with Some a when a = arity -> bare | _ -> name.txt)
      | None -> name.txt
    in
    let args' = List.map (surface_ty env ~tvars) args in
    if List.length args' <> arity then
      Err.error env.errors ~span:name.span
        (Printf.sprintf "`%s` expects %d type argument(s) but got %d."
           name.txt arity (List.length args'));
    (* If this is a named record type, expand it structurally so that
       type annotations like `: Point` unify correctly with record literals.
       Skip when the name also denotes a variant (see [name_is_variant]): the
       local variant shadows a same-named record from another module. *)
    (match StrMap.find_opt name.txt env.records with
     | Some (params, field_decls)
       when List.length params = List.length args'
            && not (name_is_variant env name.txt) ->
       let saved = !tvars in
       List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
       let flds = List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls in
       tvars := saved;
       TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
     | _ ->
       (* For qualified names not in env.records, check the module registry for
          ExRecord entries. This handles record types in modules loaded lazily
          (not pre-registered via stdlib_file_list) so cross-module field access
          and structural unification work correctly without env threading. *)
       let registry_record =
         match split_qualified name.txt with
         | None -> None
         | Some (mod_name, member) ->
           let open March_modules.Module_registry in
           (match ensure_loaded mod_name with
            | None -> None
            | Some exports ->
              List.fold_left (fun acc entry ->
                match acc with
                | Some _ -> acc
                | None ->
                  (match entry.ex_kind with
                   | ExRecord (arity, fields) when entry.ex_name = member ->
                     let params = List.init arity
                       (fun i -> Printf.sprintf "$t%d" i) in
                     Some (params, fields)
                   | _ -> None)
              ) None exports.me_entries)
       in
       (match registry_record with
        | Some (params, field_decls)
          when List.length params = List.length args'
               && not (name_is_variant env name.txt) ->
          let saved = !tvars in
          List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
          let flds = List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls in
          tvars := saved;
          TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
        | _ ->
          (* Normalize built-in unit/bool so surface annotations unify with internal reps *)
          match canon_name with
          | "Unit" -> t_unit
          | _ -> TCon (canon_name, args'))))

  | Ast.TyVar name ->
    (match List.assoc_opt name.txt !tvars with
     | Some t -> t
     | None   ->
       let t = fresh_var env.level in
       tvars := (name.txt, t) :: !tvars;
       t)

  | Ast.TyArrow (a, b) ->
    TArrow (surface_ty env ~tvars a, surface_ty env ~tvars b)

  | Ast.TyTuple ts ->
    TTuple (List.map (surface_ty env ~tvars) ts)

  | Ast.TyRecord flds ->
    let flds' = List.map (fun (n, t) -> (n.Ast.txt, surface_ty env ~tvars t)) flds in
    TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds')

  | Ast.TyLinear (lin, t) ->
    TLin (lin, surface_ty env ~tvars t)

  | Ast.TyNat n  -> TNat n
  | Ast.TyNatOp (op, a, b) ->
    TNatOp (op, surface_ty env ~tvars a, surface_ty env ~tvars b)

  | Ast.TyChan (role, proto) ->
    (* Look up the protocol and project onto the given role. *)
    (match StrMap.find_opt proto.txt env.protocols with
     | None ->
       Err.error env.errors ~span:proto.span
         (Printf.sprintf "I don't know a protocol called `%s`." proto.txt);
       TChan (ref SError)
     | Some pi ->
       (match List.assoc_opt role.txt pi.pi_projections with
        | None ->
          Err.error env.errors ~span:role.span
            (Printf.sprintf
               "Protocol `%s` has no role called `%s`.\n\
                Known roles: %s"
               proto.txt role.txt
               (String.concat ", " (List.map fst pi.pi_projections)));
          TChan (ref SError)
        | Some sty ->
          TChan (ref sty)))
  (* Carry the refinement in the internal type.  It is transparent to
     unification (repr strips it), so base-type inference is unchanged; the
     predicate is read only at the deliberate obligation sites. *)
  | Ast.TyRefine (base, binder, pred) ->
    let b = match binder with None -> "_" | Some n -> n.Ast.txt in
    TRefine (surface_ty env ~tvars base, b, pred)

(* Now that surface_ty and generalize are defined, wire up the forward ref so
   resolve_qualified_var can inject interface method bindings cross-module. *)
let () = inject_iface_exports_ref := (fun mod_name exports env ->
  let open March_modules.Module_registry in
  List.fold_left (fun env entry ->
    match entry.ex_kind with
    | ExInterface idef ->
      List.fold_left (fun env (m : Ast.method_decl) ->
        let qname = mod_name ^ "." ^ idef.iface_name.txt ^ "." ^ m.md_name.txt in
        if StrMap.mem qname env.vars then env
        else begin
          (* Use level 1 for the interface type parameter so generalize 0 quantifies it. *)
          let a = fresh_var 1 in
          let tvars = ref [(idef.iface_param.txt, a)] in
          let ty = surface_ty env ~tvars m.md_ty in
          let a_id = match a with
            | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
            | _ -> 0
          in
          let base_sch = generalize 0 ty in
          let sch = match base_sch with
            | Poly (ids, cs, t) ->
              Poly (ids, CInterface (idef.iface_name.txt, a) :: cs, t)
            | Mono t ->
              Poly ([a_id], [CInterface (idef.iface_name.txt, a)], t)
          in
          { env with vars = StrMap.add qname sch env.vars }
        end
      ) env idef.iface_methods
    | _ -> env
  ) env exports.me_entries)

(** Instantiate a constructor's type at the current level.
    Creates fresh unification variables for each type parameter of the
    parent type, then converts the constructor's argument surface-types
    using those variables.  Returns [(arg_tys, result_ty)]:
    - [arg_tys]   : the expected type of each constructor argument
    - [result_ty] : the type the fully-applied constructor produces *)
let instantiate_ctor env (ci : ctor_info) : ty list * ty =
  (* One fresh unification variable per type parameter *)
  let fresh_pairs = List.map (fun name -> (name, fresh_var env.level)) ci.ci_params in
  let tvars = ref fresh_pairs in
  (* Convert each argument's surface type, substituting the fresh vars *)
  let arg_tys = List.map (surface_ty env ~tvars) ci.ci_arg_tys in
  (* Build TCon(ParentType, [fresh_a; fresh_b; …]) *)
  let result_ty = TCon (ci.ci_type, List.map snd fresh_pairs) in
  (arg_tys, result_ty)

(** Try to expand a [TCon] of a named record type to [TRecord].
    Returns the [TRecord] type if the name is a known record def, else [None].
    Falls back to the module registry for cross-module record types that were
    loaded lazily (not pre-registered in env.records via stdlib_file_list). *)
let expand_record env ty =
  match repr ty with
  | TRecord _ as t -> Some t
  | TCon (name, args) ->
    let record_info =
      match StrMap.find_opt name env.records with
      | Some _ as r -> r
      | None ->
        (* Qualified type like "NodeIdentity.Identity": check registry for ExRecord *)
        (match split_qualified name with
         | None -> None
         | Some (mod_name, member) ->
           let open March_modules.Module_registry in
           match ensure_loaded mod_name with
           | None -> None
           | Some exports ->
             List.fold_left (fun acc entry ->
               match acc with
               | Some _ -> acc
               | None ->
                 match entry.ex_kind with
                 | ExRecord (arity, fields) when entry.ex_name = member ->
                   let params = List.init arity (fun i ->
                     Printf.sprintf "$t%d" i) in
                   Some (params, fields)
                 | _ -> None
             ) None exports.me_entries)
    in
    (match record_info with
     | Some (params, field_decls) when List.length params = List.length args ->
       let tvars = ref (List.combine params args) in
       let flds = List.map (fun (fn, fty) -> (fn, surface_ty env ~tvars fty)) field_decls in
       Some (TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds))
     | _ -> None)
  | _ -> None

(* Wire up the forward ref so [unify] (defined earlier) can reconcile a nominal
   record [TCon] with its structural [TRecord] form.  Guard with
   [name_is_variant] exactly as [surface_ty]'s own record-expansion does: in a
   global-namespace collision a variant and a record can share a printed name
   (and the record leaks into [env.records] under that bare name), so a bare
   [TCon] naming the *variant* must NOT be expanded into the colliding record's
   structure — that would silently unify two genuinely distinct types and
   swallow the "two distinct types share the name" diagnostic. *)
let () = expand_record_ref := (fun env ty ->
  match repr ty with
  | TCon (name, _) when name_is_variant env name -> None
  | _ -> expand_record env ty)

(** Register per-field linear sentinels for a named record variable [varname].
    When [ty] is or expands to a TRecord with linear fields, adds phantom
    ["varname#fieldname"] entries to env.lin so that EField accesses on
    that variable can detect double-use of individual linear fields. *)
let bind_linear_field_sentinels varname ty env =
  match expand_record env (repr ty) with
  | Some (TRecord flds) ->
    List.fold_left (fun acc_env (fname, fty) ->
        match repr fty with
        | TLin (lin, _) when lin <> Ast.Unrestricted ->
          let key = varname ^ "#" ^ fname in
          let le = { le_name = key; le_lin = lin; le_used = ref false } in
          { acc_env with lin = le :: acc_env.lin }
        | _ -> acc_env
      ) env flds
  | _ -> env

(* =================================================================
   §12  Linearity tracking
   ================================================================= *)

(** Record a use of variable [name].  Errors if a linear var is used
    more than once. *)
let record_use name span env =
  (* Mark any import entry that matches this name as used. *)
  if !(env.import_tracker) <> [] then
    List.iter (fun ie -> if ie.ie_matches name then ie.ie_used := true)
      !(env.import_tracker);
  match List.find_opt (fun e -> e.le_name = name) env.lin with
  | None -> ()   (* unrestricted — no tracking needed *)
  | Some le ->
    (match le.le_lin with
     | Ast.Linear when !(le.le_used) ->
       Err.error env.errors ~span
         (Printf.sprintf
            "The linear value `%s` is used more than once here.\n\
             Linear values must be consumed exactly once — they cannot \
             be copied or ignored." name)
     | Ast.Affine when !(le.le_used) ->
       Err.error env.errors ~span
         (Printf.sprintf
            "The affine value `%s` is used more than once here.\n\
             Affine values may be used at most once." name)
     | (Ast.Linear | Ast.Affine) ->
       le.le_used := true
     | Ast.Unrestricted -> ())

(** [bind_vars_with_linearity bindings env] is like [bind_vars] except it
    checks the repr'd type of each binding after unification: if the type
    has resolved to a [TLin] wrapper, the variable is registered as a
    linear/affine binding (tracked in [env.lin]) rather than an ordinary one.
    Use this wherever pattern-bound variables inherit linearity from the
    scrutinee, e.g. in match arms. *)
let bind_vars_with_linearity (bindings : (string * scheme) list) env =
  List.fold_left (fun acc_env (name, sch) ->
      match sch with
      | Mono t ->
        (match repr t with
         | TLin (lin, inner) when lin <> Ast.Unrestricted ->
           bind_linear name lin inner acc_env
         | t' ->
           let env1 = bind_var name (Mono t') acc_env in
           bind_linear_field_sentinels name t' env1)
      | _ -> bind_var name sch acc_env
    ) env bindings

(** [bind_pattern_bindings scrut_expr bindings env] adds [bindings] to [env].
    Linearity is propagated in two ways:
    1. If a binding's type (after unification) is [TLin], it is registered as
       linear (catches cases where the type annotation carries linearity).
    2. If [scrut_expr] is a linear/affine variable, ALL top-level bindings
       inherit that linearity — this covers the common pattern of matching
       a linearly-typed variable bound with the [linear x: T] syntax, where
       the internal type is plain [T] without a [TLin] wrapper. *)
let bind_pattern_bindings scrut_expr (bindings : (string * scheme) list) env =
  (* Check whether the scrutinee is itself a tracked linear variable. *)
  let inherited_lin =
    match scrut_expr with
    | Ast.EVar sname ->
      (match List.find_opt (fun le -> le.le_name = sname.txt) env.lin with
       | Some le when le.le_lin <> Ast.Unrestricted -> Some le.le_lin
       | _ -> None)
    | _ -> None
  in
  List.fold_left (fun acc_env (name, sch) ->
      match sch with
      | Mono t ->
        (match repr t with
         | TLin (lin, inner) when lin <> Ast.Unrestricted ->
           (* Binding type carries TLin — use that linearity. *)
           bind_linear name lin inner acc_env
         | t' ->
           (match inherited_lin with
            | Some lin ->
              (* Scrutinee was linear: the bound variable inherits its linearity. *)
              bind_linear name lin t' acc_env
            | None ->
              let env1 = bind_var name (Mono t') acc_env in
              bind_linear_field_sentinels name t' env1))
      | Poly (_, _, t) ->
        (* Generalised binding: bind normally but also add field sentinels for
           any linear fields in the underlying type. *)
        let env1 = bind_var name sch acc_env in
        bind_linear_field_sentinels name (repr t) env1
    ) env bindings

(** After a scope closes, check that every in-scope linear var was used. *)
let check_linear_all_consumed env ~scope_span in_scope_names =
  List.iter (fun le ->
      if List.mem le.le_name in_scope_names
      && le.le_lin = Ast.Linear
      && not !(le.le_used) then
        Err.error env.errors ~span:scope_span
          (Printf.sprintf
             "The linear value `%s` was never used.\n\
              Linear values must be consumed exactly once — did you \
              mean to pass it somewhere?" le.le_name)
    ) env.lin

(* =================================================================
   §13  Pattern inference
   ================================================================= *)

(** Infer the type that a pattern *expects*, and return the list of
    (name, scheme) bindings it introduces.

    We don't yet resolve constructor types through a type registry —
    ADT patterns produce fresh type variables.  That will be fixed
    when [DType] declarations populate the type registry. *)
let rec infer_pattern ?expected env (pat : Ast.pattern)
    : (string * scheme) list * ty =
  match pat with
  | Ast.PatWild _ ->
    [], fresh_var env.level

  | Ast.PatVar name ->
    let t = fresh_var env.level in
    (* Record in type_map so lower.ml can look up the resolved type via ty_of_span.
       Unification happens after infer_pattern returns; repr t follows the link. *)
    Hashtbl.replace env.type_map name.span t;
    [(name.txt, Mono t)], t

  | Ast.PatLit (lit, _) ->
    [], ty_of_lit lit

  | Ast.PatTuple (ps, _) ->
    let bs_tys  = List.map (infer_pattern env) ps in
    let bindings = List.concat_map fst bs_tys in
    let tys      = List.map snd bs_tys in
    bindings, TTuple tys

  | Ast.PatCon (name, ps) ->
    (* When the bare constructor name is ambiguous and the scrutinee type is
       known (threaded in from [infer_match] / nested constructor arguments),
       prefer the candidate whose parent type matches, instead of relying on
       [lookup_ctor]'s order-dependent "most recently registered wins". *)
    (let ci_opt =
       let by_expected =
         if String.contains name.txt '.' then None
         else
           match expected with
           | Some t ->
             (match repr t with
              | TCon (tn, _) -> lookup_ctor_in_type name.txt tn env
              | _ -> None)
           | None -> None
       in
       match by_expected with
       | Some _ as r -> r
       | None ->
         match lookup_ctor name.txt env with
         | Some _ as r -> r
         | None ->
           let _, resolved = resolve_qualified_ctor name.txt env in
           resolved
     in
     match ci_opt with
     | None ->
       let candidates = suggest_ctors name.txt env in
       let hint =
         if candidates = [] then
           qualified_error_msg name.txt env
         else
           let lines = List.map (fun (k, ty) ->
               Printf.sprintf "  • `%s` — from type `%s`" k ty
             ) candidates in
           "Did you mean one of:\n" ^ String.concat "\n" lines
       in
       Err.error env.errors ~span:name.span
         (Printf.sprintf "I don't know a constructor called `%s`.\n%s"
            name.txt hint);
       let bindings = List.concat_map fst (List.map (infer_pattern env) ps) in
       bindings, TError
     | Some ci ->
       (* Emit a hint when the bare constructor name is ambiguous across types. *)
       let all_types = all_ctors_named name.txt env in
       (if List.length all_types > 1 && not (String.contains name.txt '.') then
         Err.hint env.errors ~span:name.span
           (Printf.sprintf
              "Constructor `%s` is defined by multiple types (%s). \
               Use a qualified form to disambiguate, e.g. `%s.%s`."
              name.txt
              (String.concat ", " all_types)
              (List.hd all_types)
              name.txt));
       let arg_tys, result_ty = instantiate_ctor env ci in
       let n_expected = List.length arg_tys in
       let n_got      = List.length ps in
       if n_expected <> n_got then begin
         Err.error env.errors ~span:name.span
           (Printf.sprintf
              "Constructor `%s` expects %d argument(s) in a pattern but I got %d."
              name.txt n_expected n_got);
         let bindings = List.concat_map fst (List.map (infer_pattern env) ps) in
         bindings, TError
       end else begin
         let all_bindings = ref [] in
         List.iter2 (fun pat arg_ty ->
             let bindings, pat_ty = infer_pattern ~expected:arg_ty env pat in
             all_bindings := bindings @ !all_bindings;
             unify env ~span:name.span
               ~reason:(Some (RBuiltin
                 (Printf.sprintf "I'm checking the pattern for constructor `%s`."
                    name.txt)))
               pat_ty arg_ty
           ) ps arg_tys;
         !all_bindings, result_ty
       end)

  | Ast.PatAtom (_, ps, _) ->
    let bs_tys   = List.map (infer_pattern env) ps in
    let bindings  = List.concat_map fst bs_tys in
    bindings, t_atom

  | Ast.PatRecord (flds, _) ->
    let bindings = ref [] in
    let fld_tys = List.map (fun (name, pat) ->
        let bs, t = infer_pattern env pat in
        bindings := bs @ !bindings;
        (name.Ast.txt, t)
      ) flds
    in
    let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys in
    !bindings, TRecord sorted

  | Ast.PatAs (inner, name, _) ->
    let bindings, t = infer_pattern env inner in
    Hashtbl.replace env.type_map name.span t;
    (name.txt, Mono t) :: bindings, t

and ty_of_lit = function
  | Ast.LitInt    _ -> t_int
  | Ast.LitFloat  _ -> t_float
  | Ast.LitBool   _ -> t_bool
  | Ast.LitString _ -> t_string
  | Ast.LitAtom   _ -> t_atom

(* =================================================================
   §14  Expression checking — bidirectional
   ================================================================= *)

(** Extract a source span from an expression (outermost node). *)
let span_of_expr : Ast.expr -> Ast.span = function
  | Ast.ELit  (_, sp)           -> sp
  | Ast.EVar  name              -> name.span
  | Ast.EApp  (_, _, sp)        -> sp
  | Ast.ECon  (_, _, sp)        -> sp
  | Ast.ELam  (_, _, sp)        -> sp
  | Ast.EBlock (_, sp)          -> sp
  | Ast.ELet  (_, sp)           -> sp
  | Ast.EMatch (_, _, sp)       -> sp
  | Ast.ETuple (_, sp)          -> sp
  | Ast.ERecord (_, sp)         -> sp
  | Ast.ERecordUpdate (_, _, sp) -> sp
  | Ast.EField (_, _, sp)       -> sp
  | Ast.EIf   (_, _, _, sp)     -> sp
  | Ast.ECond (_, sp)           -> sp
  | Ast.EPipe (_, _, sp)        -> sp
  | Ast.EAnnot (_, _, sp)       -> sp
  | Ast.EHole (_, sp)           -> sp
  | Ast.EAtom (_, _, sp)        -> sp
  | Ast.ESend (_, _, sp)        -> sp
  | Ast.ESpawn (_, sp)          -> sp
  | Ast.EResultRef _            -> Ast.dummy_span
  | Ast.EDbg (_, sp)            -> sp
  | Ast.ELetFn (_, _, _, _, sp) -> sp
  | Ast.ELetQ  (_, _, _, sp)   -> sp
  | Ast.EAssert (_, sp)         -> sp
  | Ast.ESigil (_, _, sp)       -> sp

(* ══════════════════════════════════════════════════════════════════
   §E  Pattern exhaustiveness checking
   ══════════════════════════════════════════════════════════════════

   Implements a simplified version of Maranget's "Warnings for
   Pattern Matching" algorithm.  We build a pattern matrix (one row
   per branch, one column per nested level of structure) and look for
   a value that no row matches.  Missing values are reported as
   Warning diagnostics.
*)

(** Simplified pattern for exhaustiveness analysis. *)
type spat =
  | SPWild                          (** _ or any variable binding *)
  | SPCon  of string * spat list    (** Constructor: Some(x), None *)
  | SPLit  of Ast.literal           (** Literal: 0, true, "hi" *)
  | SPTup  of spat list             (** Tuple: (a, b) *)

(** Normalize an AST pattern to a [spat]. *)
let rec norm_pat (p : Ast.pattern) : spat =
  match p with
  | Ast.PatWild _            -> SPWild
  | Ast.PatVar  _            -> SPWild
  | Ast.PatAs  (p', _, _)    -> norm_pat p'
  | Ast.PatRecord _          -> SPWild   (* conservative *)
  | Ast.PatCon  (n, args)    ->
    (* Qualified constructor patterns ("MarchType.TBool", "Ast.Query")
       carry their full dotted text; exhaustiveness compares against the
       scrutinee type's BARE ctor names, so keep only the last segment. *)
    let bare = match String.rindex_opt n.txt '.' with
      | Some i -> String.sub n.txt (i + 1) (String.length n.txt - i - 1)
      | None -> n.txt
    in
    SPCon (bare, List.map norm_pat args)
  | Ast.PatAtom (n, args, _) -> SPCon (":" ^ n, List.map norm_pat args)
  | Ast.PatTuple (ps, _)     -> SPTup (List.map norm_pat ps)
  | Ast.PatLit  (l, _)       -> SPLit l

(** All [(ctor_name, arity)] pairs for a type name, in declaration order.
    Qualified aliases (keys containing '.') are skipped so that exhaustiveness
    analysis only sees each constructor once under its bare name. *)
let ctors_for_type (env : env) type_name =
  StrMap.fold (fun k cis acc ->
    if String.contains k '.' then acc
    else
      match List.find_opt (fun (ci : ctor_info) -> ci.ci_type = type_name) cis with
      | Some ci -> (k, List.length ci.ci_arg_tys) :: acc
      | None -> acc
  ) env.ctors []

(** Instantiate a surface type with a substitution from param names to internal
    types.  Used to reconstruct constructor argument types. *)
let rec inst_ty (subst : (string * ty) list) (surf : Ast.ty) : ty =
  match surf with
  | Ast.TyVar name ->
    (match List.assoc_opt name.txt subst with
     | Some t -> t
     | None   -> TError)  (* unresolved type param — use error sentinel *)
  | Ast.TyCon (name, []) ->
    (match List.assoc_opt name.txt subst with
     | Some t -> t
     | None   -> TCon (name.txt, []))
  | Ast.TyCon (name, args) ->
    TCon (name.txt, List.map (inst_ty subst) args)
  | Ast.TyArrow (a, b) -> TArrow (inst_ty subst a, inst_ty subst b)
  | Ast.TyTuple ts     -> TTuple (List.map (inst_ty subst) ts)
  | _                  -> TError

(** Instantiated argument types for [ctor_name] given the parent type's
    concrete type arguments (e.g. [Int] for Option(Int)). *)
let ctor_arg_tys (env : env) ctor_name parent_args =
  match lookup_ctor ctor_name env with
  | None -> []
  | Some ci ->
    let n = List.length ci.ci_params in
    let m = List.length parent_args in
    if n <> m then List.map (fun _ -> TError) ci.ci_arg_tys
    else
      let subst = List.combine ci.ci_params parent_args in
      List.map (inst_ty subst) ci.ci_arg_tys

(** Specialize the pattern matrix for constructor [c] with [a] sub-columns.
    - Wildcard rows → a wildcards prepended to remaining columns.
    - Matching [c] rows → their args prepended to remaining columns.
    - Other constructor rows → dropped. *)
let spec_ctor_mc (c : string) (a : int) (matrix : spat list list)
    : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild               -> Some (List.init a (fun _ -> SPWild) @ rest)
      | SPCon (d, ps) when d = c -> Some (ps @ rest)
      | SPCon _ | SPLit _ | SPTup _ -> None
  ) matrix

(** Specialize the pattern matrix for a tuple of [a] components. *)
let spec_tup_mc (a : int) (matrix : spat list list) : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild               -> Some (List.init a (fun _ -> SPWild) @ rest)
      | SPTup ps when List.length ps = a -> Some (ps @ rest)
      | _ -> None
  ) matrix

(** Specialize the pattern matrix for a literal value [lit].
    Wildcard rows and matching literal rows pass through (minus first col). *)
let spec_lit_mc (lit : Ast.literal) (matrix : spat list list)
    : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild           -> Some rest
      | SPLit l when l = lit -> Some rest
      | _ -> None
  ) matrix

(** Default matrix: rows whose first column is a wildcard, with that
    column removed.  Used for infinite-domain types that need a catch-all. *)
let default_mc (matrix : spat list list) : spat list list =
  List.filter_map (fun row ->
    match row with
    | SPWild :: rest -> Some rest
    | _ -> None
  ) matrix

(** Split a list into the first [n] elements and the remainder. *)
let split_at n lst =
  let rec go acc i = function
    | []       -> (List.rev acc, [])
    | x :: rest ->
      if i >= n then (List.rev acc, x :: rest)
      else go (x :: acc) (i + 1) rest
  in
  go [] 0 lst

(** Produce a concise human-readable example value for [ty].
    Used only to build warning messages, not for type-checking. *)
let rec example_of (ty : ty) : string =
  match repr ty with
  | TCon ("Int",    []) -> "0"
  | TCon ("Float",  []) -> "0.0"
  | TCon ("String", []) -> "\"\""
  | TCon ("Bool",   []) -> "true"
  | TCon ("Char",   []) -> "' '"
  | TCon (n, _)         -> n
  | TTuple []           -> "()"
  | TTuple ts           -> "(" ^ String.concat ", " (List.map example_of ts) ^ ")"
  | TVar _              -> "_"
  | TError              -> "_"
  | TArrow _            -> "<fn>"
  | TRecord _           -> "{ ... }"
  | TChan _             -> "<chan>"
  | TLin (_, t)         -> example_of t
  | TNat n              -> string_of_int n
  | TNatOp _            -> "_"
  | TRefine (base, _, _) -> example_of base  (* unreachable: repr strips it *)

(** Core exhaustiveness algorithm (Maranget-style).

    [find_missing_mc env tys matrix] tries to find an example value
    (represented as a list of strings, one per column) that is not
    matched by any row in [matrix].

    Returns [None] if the matrix is exhaustive for [tys], or
    [Some examples] (a list of column examples) if non-exhaustive.

    Invariant: when called with k columns, a [Some] result contains
    exactly k strings (for the outermost call, k = 1). *)
let rec find_missing_mc (env : env) (tys : ty list) (matrix : spat list list)
    : string list option =
  match tys with
  | [] ->
    (* No columns left: exhaustive iff matrix has ≥1 row covering this point. *)
    if matrix = [] then Some [] else None
  | ty :: rest_tys ->
    let ty = repr ty in
    (* If any row starts with a wildcard, it covers all values in this column.
       Check the wildcard rows' remaining columns via the default matrix. *)
    let has_first_wild =
      List.exists
        (fun row -> match row with SPWild :: _ -> true | _ -> false)
        matrix
    in
    if has_first_wild then begin
      let def = default_mc matrix in
      match find_missing_mc env rest_tys def with
      | None -> None
      | Some rest_exs ->
        (* First column is covered; use a placeholder for the counterexample. *)
        Some ("_" :: rest_exs)
    end else
    match ty with
    | TError -> None   (* error recovery — skip *)
    | TRefine _ -> None  (* unreachable: [ty] was repr'd above, which strips it *)
    | TVar _ ->
      (* Unknown type: treat like infinite domain. *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))
    | TCon ("Bool", []) ->
      (* Bool has exactly two values: true and false (literal patterns). *)
      let check_lit b =
        let sub = spec_lit_mc (Ast.LitBool b) matrix in
        match find_missing_mc env rest_tys sub with
        | None -> None
        | Some rest_exs ->
          Some ((if b then "true" else "false") :: rest_exs)
      in
      (match check_lit true with
       | Some _ as s -> s
       | None        -> check_lit false)
    | TCon (("Int" | "Float" | "String" | "Char" | "Atom"), _) ->
      (* Infinite domains require a wildcard catch-all.
         (No wildcards exist here — checked above — so report missing.) *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))
    | TCon (name, parent_args) ->
      let ctors = ctors_for_type env name in
      if ctors = [] then
        (* Opaque / unknown type: conservative skip. *)
        let def = default_mc matrix in
        (match find_missing_mc env rest_tys def with
         | None -> None
         | Some rest_exs -> Some ("_" :: rest_exs))
      else begin
        (* Collect which constructors appear in the first column. *)
        let seen =
          List.filter_map
            (fun row -> match row with SPCon (c, _) :: _ -> Some c | _ -> None)
            matrix
        in
        (* Is the signature complete? (All ctors present — no wildcards since
           those were handled above.) *)
        let is_complete =
          List.for_all (fun (c, _) -> List.mem c seen) ctors
        in
        if is_complete then
          (* Every constructor appears: check each one's sub-matrix. *)
          List.find_map (fun (ctor_name, arity) ->
            let arg_tys = ctor_arg_tys env ctor_name parent_args in
            let sub      = spec_ctor_mc ctor_name arity matrix in
            let full_tys = arg_tys @ rest_tys in
            match find_missing_mc env full_tys sub with
            | None -> None
            | Some exs ->
              let ctor_exs, rest_exs = split_at arity exs in
              let ctor_str =
                if arity = 0 then ctor_name
                else
                  Printf.sprintf "%s(%s)" ctor_name
                    (String.concat ", " ctor_exs)
              in
              Some (ctor_str :: rest_exs)
          ) ctors
        else begin
          (* Some constructor missing from first col and no wildcards:
             find one and report it. *)
          let def = default_mc matrix in
          match find_missing_mc env rest_tys def with
          | None -> None
          | Some rest_exs ->
            let missing_ctor =
              List.find_opt (fun (c, _) -> not (List.mem c seen)) ctors
            in
            let first_ex = match missing_ctor with
              | Some (c, 0) -> c
              | Some (c, _) ->
                let args = ctor_arg_tys env c parent_args in
                Printf.sprintf "%s(%s)" c
                  (String.concat ", " (List.map example_of args))
              | None -> "_"
            in
            Some (first_ex :: rest_exs)
        end
      end
    | TTuple [] -> None   (* unit — always covered *)
    | TTuple inner_tys ->
      let arity = List.length inner_tys in
      let any_tup =
        List.exists
          (fun row -> match row with SPTup _ :: _ -> true | _ -> false)
          matrix
      in
      if any_tup then begin
        (* At least one tuple pattern: specialize and recurse. *)
        let sub      = spec_tup_mc arity matrix in
        let full_tys = inner_tys @ rest_tys in
        match find_missing_mc env full_tys sub with
        | None -> None
        | Some exs ->
          let tup_exs, rest_exs = split_at arity exs in
          let tup_str =
            Printf.sprintf "(%s)" (String.concat ", " tup_exs)
          in
          Some (tup_str :: rest_exs)
      end else begin
        (* No tuple patterns and no wildcards: entirely missing. *)
        let def = default_mc matrix in
        match find_missing_mc env rest_tys def with
        | None -> None
        | Some rest_exs ->
          let tup_ex =
            Printf.sprintf "(%s)"
              (String.concat ", " (List.map example_of inner_tys))
          in
          Some (tup_ex :: rest_exs)
      end
    | TArrow _ | TRecord _ | TChan _ | TLin _ | TNat _ | TNatOp _ ->
      (* Non-enumerable types: treat like infinite domain. *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))

let span_of_pat : Ast.pattern -> Ast.span = function
  | Ast.PatWild sp          -> sp
  | Ast.PatVar  name        -> name.Ast.span
  | Ast.PatCon  (name, _)   -> name.Ast.span
  | Ast.PatAtom (_, _, sp)  -> sp
  | Ast.PatTuple (_, sp)    -> sp
  | Ast.PatLit  (_, sp)     -> sp
  | Ast.PatRecord (_, sp)   -> sp
  | Ast.PatAs   (_, _, sp)  -> sp

(** Check if [row] is useful relative to [matrix] for scrutinee types [tys].
    Returns false iff every value matched by [row] is already covered by [matrix]. *)
let rec is_useful (env : env) (tys : ty list) (matrix : spat list list)
    (row : spat list) : bool =
  match tys, row with
  | [], _ | _, [] -> matrix = []
  | ty :: rest_tys, q :: row_rest ->
    let ty = repr ty in
    (match q with
     | SPWild ->
       (match ty with
        | TCon ("Bool", []) ->
          (* Use Maranget's signature-completeness: only expand if the matrix
             first column covers both literals; otherwise take the default path.
             This prevents infinite loops on recursive types. *)
          let sigma_t = List.exists (fun row ->
            match row with SPLit (Ast.LitBool true) :: _ -> true | _ -> false) matrix in
          let sigma_f = List.exists (fun row ->
            match row with SPLit (Ast.LitBool false) :: _ -> true | _ -> false) matrix in
          if sigma_t && sigma_f then
            let check_lit b =
              let sub_m = spec_lit_mc (Ast.LitBool b) matrix in
              is_useful env rest_tys sub_m row_rest
            in
            check_lit true || check_lit false
          else
            is_useful env rest_tys (default_mc matrix) row_rest
        | TCon (name, parent_args) when ctors_for_type env name <> [] ->
          let ctors = ctors_for_type env name in
          (* sigma = constructors EXPLICITLY listed in the matrix's first column
             (wildcards are NOT counted — this is the termination invariant). *)
          let sigma = List.filter_map (fun row ->
            match row with SPCon (c, _) :: _ -> Some c | _ -> None) matrix in
          let is_complete =
            List.for_all (fun (c, _) -> List.mem c sigma) ctors in
          if is_complete then
            List.exists (fun (ctor_name, arity) ->
              let arg_tys = ctor_arg_tys env ctor_name parent_args in
              let sub_m = spec_ctor_mc ctor_name arity matrix in
              let wild_args = List.init arity (fun _ -> SPWild) in
              is_useful env (arg_tys @ rest_tys) sub_m (wild_args @ row_rest)
            ) ctors
          else
            is_useful env rest_tys (default_mc matrix) row_rest
        | TTuple inner_tys ->
          let arity = List.length inner_tys in
          let sub_m = spec_tup_mc arity matrix in
          let wild_args = List.init arity (fun _ -> SPWild) in
          is_useful env (inner_tys @ rest_tys) sub_m (wild_args @ row_rest)
        | _ ->
          let def = default_mc matrix in
          is_useful env rest_tys def row_rest)
     | SPCon (name, sub_pats) ->
       let arity = List.length sub_pats in
       let parent_args = match ty with TCon (_, args) -> args | _ -> [] in
       let arg_tys = ctor_arg_tys env name parent_args in
       let sub_m = spec_ctor_mc name arity matrix in
       is_useful env (arg_tys @ rest_tys) sub_m (sub_pats @ row_rest)
     | SPTup sub_pats ->
       let arity = List.length sub_pats in
       let inner_tys = match ty with TTuple ts -> ts | _ -> List.init arity (fun _ -> TError) in
       let sub_m = spec_tup_mc arity matrix in
       is_useful env (inner_tys @ rest_tys) sub_m (sub_pats @ row_rest)
     | SPLit lit ->
       let sub_m = spec_lit_mc lit matrix in
       is_useful env rest_tys sub_m row_rest)

(** Emit Warnings for redundant (unreachable) arms.
    Guarded arms are never flagged, and their patterns are excluded from the
    prefix so that subsequent arms aren't mistakenly flagged as subsumed. *)
let check_redundant_arms (env : env) (scrut_ty : ty)
    (branches : Ast.branch list) =
  let prefix = ref [] in
  List.iter (fun (br : Ast.branch) ->
    let arm_row = [norm_pat br.branch_pat] in
    if br.branch_guard = None then begin
      if not (is_useful env [scrut_ty] !prefix arm_row) then begin
        let pat_sp   = span_of_pat br.branch_pat in
        let body_sp  = span_of_expr br.branch_body in
        let arm_span = { pat_sp with
          March_ast.Ast.end_line = body_sp.March_ast.Ast.end_line;
          March_ast.Ast.end_col  = body_sp.March_ast.Ast.end_col } in
        Err.report env.errors
          { Err.severity = Warning; span = pat_sp;
            message = "This pattern can never be reached.";
            labels  = [];
            notes   = ["An earlier arm already covers all values this pattern matches."];
            code    = Some "redundant_arm";
            fix     = Some (Err.FDelete {
              start_line = arm_span.March_ast.Ast.start_line;
              end_line   = arm_span.March_ast.Ast.end_line }) }
      end;
      prefix := !prefix @ [arm_row]
    end
  ) branches

(** Emit a Warning if the match on [scrut_ty] with [branches] is non-exhaustive.

    When any branch carries a [when] guard, exact coverage is undecidable in
    general (we cannot know at typecheck time whether a guard succeeds), so we do
    NOT emit the ordinary Warning. But a guarded match can still DEFINITELY panic:
    a branch whose pattern is only reachable behind a guard cannot be relied on to
    match, so it contributes nothing to GUARANTEED coverage. If the GUARDLESS
    branches alone are non-exhaustive, then when every guard happens to fail at
    runtime no arm matches and the match panics ("no matching clause"). For the
    guarded case we therefore compute exhaustiveness over the guardless branches
    only and, if that sub-match is non-exhaustive, RECORD the span (so
    [check_no_panic_module] can promote it to an error inside a `cap no_panic`
    module) WITHOUT emitting a global Warning — guarded matches are common in
    ordinary code and get no such warning today, so only `cap no_panic` modules
    (which opt into strictness) are made stricter. *)
let check_exhaustiveness (env : env) (span : Ast.span) (scrut_ty : ty)
    (branches : Ast.branch list) =
  let has_guards =
    List.exists (fun (br : Ast.branch) -> br.branch_guard <> None) branches
  in
  if has_guards then begin
    (* Coverage guaranteed by the GUARDLESS branches only (an all-guarded match
       yields an empty matrix, which [find_missing_mc] correctly reports as
       non-exhaustive rather than crashing). If those alone are exhaustive the
       match can never fall through → safe. Otherwise record the span so
       [check_no_panic_module] rejects it; no global Warning here. *)
    let guardless_matrix =
      List.filter_map
        (fun (br : Ast.branch) ->
          match br.branch_guard with
          | None   -> Some [norm_pat br.branch_pat]
          | Some _ -> None)
        branches
    in
    match find_missing_mc env [scrut_ty] guardless_matrix with
    | None -> ()
    | Some _ ->
      env.nonexhaustive_match_spans := span :: !(env.nonexhaustive_match_spans)
  end
  else begin
    let matrix =
      List.map (fun (br : Ast.branch) -> [norm_pat br.branch_pat]) branches
    in
    match find_missing_mc env [scrut_ty] matrix with
    | None -> ()
    | Some missing ->
      (* Record the non-exhaustive match's span so [check_no_panic_module] can
         reject it as a runtime panic surface inside a `cap no_panic` module.
         Recording is unconditional (cheap, non-error); attribution/promotion to
         an error is gated there by span containment. *)
      env.nonexhaustive_match_spans := span :: !(env.nonexhaustive_match_spans);
      (match missing with
       | ex :: _ ->
         Err.report env.errors
           { Err.severity = Warning; span;
             message = Printf.sprintf "Non-exhaustive pattern match — missing case: %s" ex;
             labels  = [];
             notes   = [ "Add a branch for this case, or use `_ -> ...` as a catch-all." ];
             code    = None; fix = None }
       | [] ->
         Err.report env.errors
           { Err.severity = Warning; span;
             message = "Non-exhaustive pattern match";
             labels  = [];
             notes   = [ "Add a catch-all branch `_ -> ...` to handle any remaining cases." ];
             code    = None; fix = None })
  end

(** Unfold one step of a recursive session type.
    [SRec(x, body)] becomes [body] with every [SVar x] replaced by [SRec(x, body)].
    Keeps unfolding until the outermost constructor is no longer [SRec],
    so callers can pattern-match directly on [SSend] / [SRecv] / etc. *)
let rec unfold_srec s =
  match s with
  | SRec (x, body) ->
    let rec subst_inner s =
      match s with
      | SVar y when y = x          -> SRec (x, body)
      | SSend (t, s')              -> SSend (t, subst_inner s')
      | SRecv (t, s')              -> SRecv (t, subst_inner s')
      | SChoose bs                 -> SChoose (List.map (fun (l, s') -> (l, subst_inner s')) bs)
      | SOffer  bs                 -> SOffer  (List.map (fun (l, s') -> (l, subst_inner s')) bs)
      | SMSend (r, t, s')          -> SMSend (r, t, subst_inner s')
      | SMRecv (r, t, s')          -> SMRecv (r, t, subst_inner s')
      | SRec (y, s') when y <> x  -> SRec (y, subst_inner s')
      | other                      -> other
    in
    unfold_srec (subst_inner body)
  | _ -> s

(** Type constructor names that cannot appear in actor message payloads.
    These types carry mutable state that must remain owned by a single actor. *)
let non_sendable_types = ["RingBuf"]

(** [check_sendable errors span ty] walks [ty] and emits an error for every
    non-sendable type constructor it finds. Call at every [send()] callsite. *)
let rec check_sendable errors span ty =
  match repr ty with
  | TCon (name, args) ->
    if List.mem name non_sendable_types then
      Err.error errors ~span
        (Printf.sprintf
           "Values of type `%s` cannot be sent in actor messages.\n\
            `%s` is a mutable buffer that must be owned by a single actor.\n\
            Pass it as initial actor state at spawn time instead of sending it."
           name name)
    else List.iter (check_sendable errors span) args
  | TArrow (a, b)     -> check_sendable errors span a; check_sendable errors span b
  | TTuple ts         -> List.iter (check_sendable errors span) ts
  | TRecord flds      -> List.iter (fun (_, t) -> check_sendable errors span t) flds
  | TLin (_, t)       -> check_sendable errors span t
  | TNatOp (_, a, b)  -> check_sendable errors span a; check_sendable errors span b
  | TRefine (base, _, _) -> check_sendable errors span base
  | TVar _ | TChan _ | TNat _ | TError -> ()

(** [infer_expr env e] synthesises the type of [e], accumulating any
    errors into [env.errors]. *)
let rec infer_expr env (e : Ast.expr) : ty =
  let result =
    match e with
    (* ── Literals ─────────────────────────────────────────────────── *)
    | Ast.ELit (lit, _) ->
      ty_of_lit lit

    (* ── Variables ────────────────────────────────────────────────── *)
    | Ast.EVar name ->
      record_use name.txt name.span env;
      (match lookup_var name.txt env with
       | Some sch -> instantiate env.level env sch
       | None     ->
         (* Try qualified module resolution: "Mod.func" *)
         match resolve_qualified_var name.txt env with
         | _, Some sch -> instantiate env.level env sch
         | _ ->
           (* Final fallback: for multi-component names like "Conduit.Storage.workflow_load",
              interface methods are registered without the outer module prefix
              (e.g. as "Storage.workflow_load"). Try progressively stripping
              leading dot-separated components. *)
           let rec try_suffix n =
             match String.index_opt n '.' with
             | None -> None
             | Some i ->
               let rest = String.sub n (i + 1) (String.length n - i - 1) in
               (match lookup_var rest env with
                | Some sch -> Some sch
                | None -> try_suffix rest)
           in
           (match try_suffix name.txt with
            | Some sch -> instantiate env.level env sch
            | None ->
              let msg =
                if String.contains name.txt '.' then
                  qualified_error_msg name.txt env
                else begin
                  let base = Printf.sprintf "I cannot find `%s`." name.txt in
                  match suggest_var_in_scope name.txt env with
                  | Some s -> base ^ Printf.sprintf " Did you mean `%s`?" s
                  | None   -> base
                end
              in
              Err.error env.errors ~span:name.span msg;
              TError))

    (* ── Type annotations ─────────────────────────────────────────── *)
    | Ast.EAnnot (e, ann, sp) ->
      let tvars = ref [] in
      let expected = surface_ty env ~tvars ann in
      check_expr env e expected ~reason:(Some (RAnnotation sp));
      expected

    (* ── Typed holes ──────────────────────────────────────────────── *)
    | Ast.EHole (name, sp) ->
      let t = fresh_var env.level in
      let label = match name with Some n -> "?" ^ n.txt | None -> "?" in
      Err.report env.errors
        { Err.severity = Hint; span = sp;
          message = Printf.sprintf "Typed hole %s has type `%s`" label (pp_ty t);
          labels  = [];
          notes   = [ "Fill this hole with an expression of the type shown above." ];
          code    = None; fix = None };
      t

    (* ── Function application ─────────────────────────────────────── *)
    (* ── Session channel operations (special casing for session type advancement) ── *)

    (* Normalize Mod.method(args) → EVar("Mod.method")(args) so that Chan.send etc.
       work whether written as `Chan.send(ch, v)` (field access) or `Chan.send(ch, v)`. *)
    | Ast.EApp (Ast.EField (Ast.ECon ({txt = mod_name; _}, [], _),
                             {txt = meth; _}, _),
                args, sp) ->
      let norm = Ast.EApp (Ast.EVar {txt = mod_name ^ "." ^ meth;
                                     span = Ast.dummy_span}, args, sp) in
      infer_expr env norm

    (* Chan.new(proto_name_string_or_atom) →
         (linear Chan(RoleA, Proto), linear Chan(RoleB, Proto))
       The protocol name is the sole argument; we look it up to generate typed endpoints. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.new"; _ }, [proto_expr], sp) ->
      let proto_name = match proto_expr with
        | Ast.ELit (LitString s, _) | Ast.ELit (LitAtom s, _) -> Some s
        | Ast.EVar n -> Some n.txt
        | Ast.ECon (n, [], _) -> Some n.txt   (* bare Protocol name: Chan.new(MyProto) *)
        | _ -> None
      in
      (match proto_name with
       | None ->
         Err.error env.errors ~span:sp
           "Chan.new: argument must be a protocol name (string, atom, or bare name).";
         TError
       | Some pname ->
         (match StrMap.find_opt pname env.protocols with
          | None ->
            Err.error env.errors ~span:sp
              (Printf.sprintf "Chan.new: protocol `%s` is not declared." pname);
            TError
          | Some pi ->
            (match pi.pi_projections with
             | [(_, sty_a); (_, sty_b)] ->
               (* Return (linear Chan(A, Proto), linear Chan(B, Proto)) *)
               let ty_a = TLin (Ast.Linear, TChan (ref sty_a)) in
               let ty_b = TLin (Ast.Linear, TChan (ref sty_b)) in
               TTuple [ty_a; ty_b]
             | [_] ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf "Chan.new: protocol `%s` has only one role." pname);
               TError
             | [] ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf "Chan.new: protocol `%s` has no roles." pname);
               TError
             | _ ->
               (* 3+ roles: just return first two as a pair *)
               (match pi.pi_projections with
                | (_, sty_a) :: (_, sty_b) :: _ ->
                  TTuple [TLin (Ast.Linear, TChan (ref sty_a));
                          TLin (Ast.Linear, TChan (ref sty_b))]
                | _ -> TError))))

    (* Chan.send(ch, value) → linear Chan at continuation session state.
       Pre-condition: ch must be at SSend(T, S). Post: ch is consumed; returns Chan at S. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.send"; _ }, [ch_expr; val_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SSend (payload_ty, cont) ->
            check_expr env val_expr payload_ty
              ~reason:(Some (RBuiltin "Payload type of Chan.send"));
            TLin (Ast.Linear, TChan (ref cont))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.send: channel is at `%s` but I expected `Send(T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.send: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.recv(ch) → (value, linear Chan at continuation).
       Pre-condition: ch must be at SRecv(T, S). Post: ch consumed; returns (T, Chan at S). *)
    | Ast.EApp (Ast.EVar { txt = "Chan.recv"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SRecv (payload_ty, cont) ->
            TTuple [payload_ty; TLin (Ast.Linear, TChan (ref cont))]
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.recv: channel is at `%s` but I expected `Recv(T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.recv: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.close(ch) → Unit.
       Pre-condition: ch must be at SEnd. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.close"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SEnd -> t_unit
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.close: channel is at `%s` but I expected `End`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.close: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.choose(ch, :label) → linear Chan at chosen branch continuation.
       Pre-condition: ch must be at SChoose(branches). *)
    | Ast.EApp (Ast.EVar { txt = "Chan.choose"; _ }, [ch_expr; label_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      let label_str = match label_expr with
        | Ast.EAtom (s, [], _) -> Some s
        | Ast.ELit (LitAtom s, _) -> Some s
        | _ -> None
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SChoose branches ->
            (match label_str with
             | None ->
               Err.error env.errors ~span:sp
                 "Chan.choose: label must be an atom literal (e.g. :ok).";
               TError
             | Some lbl ->
               (match List.assoc_opt lbl branches with
                | Some cont -> TLin (Ast.Linear, TChan (ref cont))
                | None ->
                  Err.error env.errors ~span:sp
                    (Printf.sprintf
                       "Chan.choose: label `:%s` is not a valid branch of this protocol." lbl);
                  TError))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.choose: channel is at `%s` but I expected `Choose{...}`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.choose: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Chan.offer(ch) → (Atom, linear Chan at some continuation).
       Pre-condition: ch must be at SOffer(branches).
       Returns (label_atom, new_chan) where new_chan is at the continuation
       for whichever branch the other side chose.  The exact continuation is
       not known statically without dependent types, so we return the first
       branch's continuation type as a conservative approximation that still
       lets users write match expressions over the returned atom. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.offer"; _ }, [ch_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SOffer branches ->
            let cont_ty = match branches with
              | (_, sty) :: _ -> TLin (Ast.Linear, TChan (ref sty))
              | []             -> TError
            in
            TTuple [t_atom; cont_ty]
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Chan.offer: channel is at `%s` but I expected `Offer{...}`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Chan.offer: expected a channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* ── MPST multi-party session operations ─────────────────────────
       These mirror Chan.* but work with multi-party protocols (N>2 roles).
       MPST.new(Proto)            → (ep_r1, ep_r2, ..., ep_rN) sorted by role name
       MPST.send(ep, :Role, val)  → new_ep  (must be at SMSend(Role, T, S))
       MPST.recv(ep, :Role)       → (val, new_ep) (must be at SMRecv(Role, T, S))
       MPST.close(ep)             → ()  (must be at SEnd)
    ──────────────────────────────────────────────────────────────────── *)

    | Ast.EApp (Ast.EVar { txt = "MPST.new"; _ }, [proto_expr], sp) ->
      (* Look up the protocol and return a tuple of one TChan per role. *)
      let proto_name = match proto_expr with
        | Ast.ELit (Ast.LitString s, _) -> Some s
        | Ast.EAtom (s, [], _)           -> Some s
        | Ast.ECon (n, [], _)            -> Some n.txt
        | Ast.EVar n                     -> Some n.txt
        | _ -> None
      in
      (match proto_name with
       | None ->
         Err.error env.errors ~span:sp
           "MPST.new: argument must be a protocol name.";
         TError
       | Some pname ->
         (match StrMap.find_opt pname env.protocols with
          | None ->
            Err.error env.errors ~span:sp
              (Printf.sprintf "MPST.new: protocol `%s` is not declared." pname);
            TError
          | Some pi ->
            let n = List.length pi.pi_projections in
            if n < 3 then begin
              Err.error env.errors ~span:sp
                (Printf.sprintf
                   "MPST.new: protocol `%s` has %d role(s) but MPST.new \
                    requires at least 3. Use Chan.new for binary protocols."
                   pname n);
              TError
            end else
              (* Return tuple of TChan endpoints, sorted by role (same as projections order) *)
              TTuple (List.map (fun (_, s_ty) ->
                  TLin (Ast.Linear, TChan (ref s_ty))
                ) pi.pi_projections)))

    | Ast.EApp (Ast.EVar { txt = "MPST.send"; _ }, [ch_expr; role_expr; val_expr], sp) ->
      (* MPST.send(ch, Server, value) — ch must be at SMSend(Server, T, S).
         The role can be written as a bare uppercase name (ECon) or atom (:server). *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SMSend (target_role, payload_ty, cont) ->
            (* Verify the role argument matches *)
            let actual_role = match role_expr with
              | Ast.ECon (n, [], _) -> Some n.txt
              | Ast.EVar n           -> Some n.txt
              | Ast.EAtom (s, [], _) -> Some s
              | Ast.ELit (Ast.LitAtom s, _) -> Some s
              | _ -> None
            in
            (match actual_role with
             | None ->
               Err.error env.errors ~span:sp
                 "MPST.send: second argument must be a role name (e.g. Server).";
               TError
             | Some ar when ar <> target_role ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "MPST.send: channel expects to send to `%s` but you said `%s`."
                    target_role ar);
               TError
             | _ ->
               check_expr env val_expr payload_ty
                 ~reason:(Some (RBuiltin "Payload type of MPST.send"));
               TLin (Ast.Linear, TChan (ref cont)))
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.send: channel is at `%s` but I expected `MSend(Role, T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.send: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    | Ast.EApp (Ast.EVar { txt = "MPST.recv"; _ }, [ch_expr; role_expr], sp) ->
      (* MPST.recv(ch, Source) — ch must be at SMRecv(Source, T, S).
         The role can be written as a bare uppercase name or atom.
         Returns (value, new_chan). *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SMRecv (source_role, payload_ty, cont) ->
            let actual_role = match role_expr with
              | Ast.ECon (n, [], _) -> Some n.txt
              | Ast.EVar n           -> Some n.txt
              | Ast.EAtom (s, [], _) -> Some s
              | Ast.ELit (Ast.LitAtom s, _) -> Some s
              | _ -> None
            in
            (match actual_role with
             | None ->
               Err.error env.errors ~span:sp
                 "MPST.recv: second argument must be a role name (e.g. Client).";
               TError
             | Some ar when ar <> source_role ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "MPST.recv: channel expects to receive from `%s` but you said `%s`."
                    source_role ar);
               TError
             | _ ->
               TTuple [payload_ty; TLin (Ast.Linear, TChan (ref cont))])
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.recv: channel is at `%s` but I expected `MRecv(Role, T, ...)`."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.recv: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    | Ast.EApp (Ast.EVar { txt = "MPST.close"; _ }, [ch_expr], sp) ->
      (* MPST.close(ch) — ch must be at SEnd. *)
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r ->
         (match unfold_srec !r with
          | SEnd -> t_unit
          | SError -> TError
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "MPST.close: channel is at `%s` but the session must be complete \
                  (End) before closing."
                 (pp_session_ty other));
            TError)
       | TError -> TError
       | _ ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "MPST.close: expected a multi-party channel endpoint but got `%s`."
              (pp_ty ch_ty));
         TError)

    (* Restrict cap_narrow (Part 1): its result must never be a nominal proof
       cap. cap_narrow is the ONLY polymorphic cap producer, so closing this
       closes the proof-cap forge in every expression position (inline arg,
       let-binding, return, and laundered through a polymorphic function).
       IO-lattice narrowing (Cap(IO) -> Cap(IO.Network)) is unaffected because IO
       caps are not in env.proof_caps; proof-cap minting goes through `mint_cap`
       (gated).

       WHY A CALL-SITE / POST-CHECKING SWEEP IS INSUFFICIENT: at this point the
       result var `a` in `Cap(a)` is NOT yet pinned — `infer_app` only pins the
       ARGUMENT against `Cap(IO)`; `a` is pinned by LATER unification.  A recorded
       side-table read after checking catches the directly-pinned positions
       (R1/R7), but when the value is laundered through a polymorphic user
       function (`consume(id(cap_narrow(cap)))`) the recorded node stays unbound
       forever — indistinguishable from legitimate laundered IO narrowing.

       THE FIX (two complementary, both here):
       - VALUE RESTRICTION [demote_to_monomorphic]: a cap_narrow application is
         expansive, so its result must never let-generalize.  Demoting the result
         var to level 0 keeps `let x = cap_narrow(cap)` monomorphic so its single
         use pins the one var.
       - USE-SITE HOOK [tag_cap_producer_result] + the [unify] proof-cap-forge
         arm: tag the inner cap var `a`; the instant `a` (or any var it later
         links to) is unified with a nominal proof cap, [unify] rejects it —
         position- and flow-independent, and it fires ONLY for proof caps so
         IO narrowing (including through a polymorphic fn) is never touched. *)
    | Ast.EApp (Ast.EVar { txt = "cap_narrow"; _ } as fv, [arg], sp) ->
      let f_ty = infer_expr env fv in
      let rty = infer_app env sp f_ty [arg] 0 in
      demote_to_monomorphic rty;
      tag_cap_producer_result env rty sp;
      rty

    (* mint_cap (Part 2): the GATED proof-cap mint.  Same Cap(IO) -> Cap(a)
       inference as cap_narrow; the gate — target must be a proof cap whose
       declaring module is the enclosing module, and the enclosing fn must be
       public — is enforced by the post-checking sweep because (like cap_narrow)
       the result var is not pinned until the surrounding unification runs.  We
       capture the enclosing fn/module CONTEXT here (env.cur_fn_public,
       env.current_module — lambdas inherit the enclosing fn's public-ness) since
       that context is unavailable at sweep time. *)
    | Ast.EApp (Ast.EVar { txt = "mint_cap"; _ } as fv, [arg], sp) ->
      let f_ty = infer_expr env fv in
      let rty = infer_app env sp f_ty [arg] 0 in
      (* Same value restriction as cap_narrow: a mint_cap application is
         expansive and must not let-generalize, so the gate sweep sees the
         concrete pinned cap rather than an unbound quantified var. *)
      demote_to_monomorphic rty;
      env.mint_cap_sites :=
        (sp, rty, env.cur_fn_public, env.current_module) :: !(env.mint_cap_sites);
      rty

    | Ast.EApp (f, args, sp) ->
      let f_ty = infer_expr env f in
      (* Reject wrong-arity calls of known (module-defined) functions.  March
         has no partial application: under-application panics at runtime (and
         the compiler miscompiles it into a body call with a garbage arg), and
         curried-style over-application of a function-returning function also
         panics.  infer_app, being curried, silently accepts these.  We only
         flag a direct call of a name in [fn_arities] whose actual callee type
         is at least as deep as its declared arity — so a local binding that
         shadows the name (different shape) is never falsely rejected. *)
      let arity_error =
        match f with
        | Ast.EVar name ->
          (match StrMap.find_opt name.txt env.fn_arities with
           | Some (arity, def_span) ->
             let n_args = List.length args in
             let rec count_arrows t =
               match repr t with TArrow (_, r) -> 1 + count_arrows r | _ -> 0 in
             if n_args <> arity && count_arrows f_ty >= arity then Some (name, arity, n_args, def_span)
             else None
           | None -> None)
        | _ -> None
      in
      (match arity_error with
       | Some (name, arity, n_args, def_span) ->
         List.iter (fun a -> ignore (infer_expr env a)) args;
         Err.report env.errors
           { Err.severity = Err.Error; span = sp;
             message = Printf.sprintf
               "Function `%s` expects %d argument%s, but got %d.\n\
                March has no partial application — a call must supply all arguments."
               name.txt arity (if arity = 1 then "" else "s") n_args;
             labels = [{ Err.lbl_span = def_span;
                         Err.lbl_message = Printf.sprintf "defined here with %d parameter%s"
                           arity (if arity = 1 then "" else "s") }];
             notes = []; code = None; fix = None };
         (* Return the declared return type so downstream inference stays sane. *)
         let rec peel n t =
           if n <= 0 then t
           else match repr t with TArrow (_, r) -> peel (n - 1) r | other -> other in
         peel arity f_ty
       | None ->
         let res = infer_app env sp f_ty args 0 in
         (* If [f] is a cap-narrow-factory fn (its body launders a cap_narrow
            result — recorded in check_fn), taint the call's result so the unify
            hook fires when it is later bound to a proof cap.  This closes the
            cross-module factory route (`consume(mk(cap))`) whose prebound scheme
            hides the per-var taint from the hook. *)
         (match f with
          | Ast.EVar name when Hashtbl.mem env.cap_narrow_factory_fns name.txt ->
            tag_cap_producer_result env res sp
          | _ -> ());
         res)

    (* ── Constructor application ──────────────────────────────────── *)
    | Ast.ECon (name, args, sp) ->
      (let ci_opt = match lookup_ctor name.txt env with
         | Some _ as r -> r
         | None ->
           (* Try qualified module resolution: "Mod.Ctor" *)
           let _, resolved = resolve_qualified_ctor name.txt env in
           resolved
       in
       match ci_opt with
       | None ->
         let candidates = suggest_ctors name.txt env in
         let hint =
           if candidates = [] then
             qualified_error_msg name.txt env
           else
             let lines = List.map (fun (k, ty) ->
                 Printf.sprintf "  • `%s` — from type `%s`" k ty
               ) candidates in
             "Did you mean one of:\n" ^ String.concat "\n" lines
         in
         Err.error env.errors ~span:name.span
           (Printf.sprintf "I don't know a constructor called `%s`.\n%s"
              name.txt hint);
         List.iter (fun a -> ignore (infer_expr env a)) args;
         TError
       | Some ci ->
         (* Warn if a bare constructor name is ambiguous across multiple types.
            Qualified names (containing '.') are already disambiguated — skip. *)
         (if not (String.contains name.txt '.') then begin
           let all_types = all_ctors_named name.txt env in
           if List.length all_types > 1 then
             Err.hint env.errors ~span:name.span
               (Printf.sprintf
                  "Constructor `%s` is defined by multiple types (%s). \
                   Use a qualified form to disambiguate, e.g. `%s.%s`."
                  name.txt
                  (String.concat ", " all_types)
                  (List.hd all_types)
                  name.txt)
         end);
         let arg_tys, result_ty = instantiate_ctor env ci in
         let n_expected = List.length arg_tys in
         let n_got      = List.length args in
         if n_expected <> n_got then begin
           Err.error env.errors ~span:sp
             (Printf.sprintf
                "Constructor `%s` expects %d argument(s) but I got %d."
                name.txt n_expected n_got);
           List.iter (fun a -> ignore (infer_expr env a)) args;
           TError
         end else begin
           List.iter2 (fun arg arg_ty ->
               check_expr env arg arg_ty
                 ~reason:(Some (RBuiltin
                   (Printf.sprintf "Argument to constructor `%s`." name.txt)))
             ) args arg_tys;
           result_ty
         end)

    (* ── Lambdas ──────────────────────────────────────────────────── *)
    | Ast.ELam (params, body, lsp) ->
      (* Snapshot which outer linear vars are unused before entering the lambda.
         Any that become used during body checking were captured by the closure.
         Capturing a linear value in a closure is unsound because the closure
         could be called multiple times, violating the exactly-once guarantee. *)
      let outer_lin_snapshot =
        List.map (fun le -> (le.le_name, !(le.le_used))) env.lin
      in
      let param_tys, env' = bind_lam_params env params in
      let body_ty = infer_expr env' body in
      (* Detect captures: outer linear vars that were unused before but used now. *)
      List.iter (fun le ->
          let was_used_before =
            match List.assoc_opt le.le_name outer_lin_snapshot with
            | Some b -> b
            | None   -> true  (* not in snapshot = lambda's own param, skip *)
          in
          if not was_used_before && !(le.le_used)
          && le.le_lin <> Ast.Unrestricted then
            Err.error env.errors ~span:lsp
              (Printf.sprintf
                 "The linear value `%s` cannot be captured by a closure.\n\
                  A closure may be called multiple times, which would violate \
                  the exactly-once guarantee.\n\
                  Pass `%s` as a parameter to the closure instead."
                 le.le_name le.le_name)
        ) env.lin;
      List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys body_ty

    (* ── do/end block ─────────────────────────────────────────────── *)
    | Ast.EBlock (exprs, _) ->
      infer_block env exprs

    (* ── let binding (block-scoped) ───────────────────────────────── *)
    | Ast.ELet (b, sp) ->
      (* When ELet appears as the last expression in a block it's a
         programmer error, but we give it type Unit and move on.  Still honour
         a type annotation on the binding (`let x : T = e`) so the RHS is
         checked against it, mirroring the normal infer_block ELet arm. *)
      let rhs_ty = infer_let_annotated env sp b.bind_ty b.bind_expr in
      let bindings, pat_ty = infer_pattern env b.bind_pat in
      let reason = Some (RLetBind sp) in
      unify env ~span:sp ~reason rhs_ty pat_ty;
      (* Record variable name type for hover even in tail position *)
      (match b.bind_pat with
       | Ast.PatVar name -> Hashtbl.replace env.type_map name.span (repr rhs_ty)
       | _ -> ());
      ignore bindings;
      t_unit

    (* ── match ────────────────────────────────────────────────────── *)
    | Ast.EMatch (scrut, branches, sp) ->
      let scrut_ty = infer_expr env scrut in
      infer_match env sp scrut scrut_ty branches

    (* ── Tuples ───────────────────────────────────────────────────── *)
    | Ast.ETuple ([], _)  -> t_unit
    | Ast.ETuple (es, _)  -> TTuple (List.map (infer_expr env) es)

    (* ── Record literals ──────────────────────────────────────────── *)
    | Ast.ERecord (flds, _) ->
      let fld_tys = List.map (fun (n, e) -> (n.Ast.txt, infer_expr env e)) flds in
      TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys)

    (* ── Record update: { base with f = e, … } ───────────────────── *)
    | Ast.ERecordUpdate (base, updates, sp) ->
      let base_ty   = infer_expr env base in
      let update_tys =
        List.map (fun (n, e) -> (n.Ast.txt, infer_expr env e)) updates
      in
      (match expand_record env (repr base_ty) with
       | Some (TRecord all_flds) ->
         List.iter (fun (fname, uty) ->
             match List.assoc_opt fname all_flds with
             | Some fty ->
               unify env ~span:sp
                 ~reason:(Some (RBuiltin
                   (Printf.sprintf "field `%s` must keep its original type" fname)))
                 fty uty
             | None ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "This record does not have a field called `%s`.\n\
                     The fields I know about are: %s"
                    fname
                    (String.concat ", " (List.map fst all_flds)))
           ) update_tys;
         base_ty
       | _ ->
       (match repr base_ty with
       | TVar _ ->
         (* Base type not yet known — build a partial record constraint *)
         let partial =
           TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b)
                      update_tys) in
         unify env ~span:sp base_ty partial;
         base_ty
       | other ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "I can only use `{ … with … }` on a record, but this \
               expression has type `%s`." (pp_ty other));
         TError))

    (* ── Field access: e.name ─────────────────────────────────────── *)
    | Ast.EField (e, name, sp) ->
      (* Module member access: if e is a module path (ECon or chained EField),
         try looking up "A.B.name" in env.vars before falling back to record field. *)
      let rec module_path = function
        | Ast.ECon (n, [], _) -> Some n.txt
        | Ast.EField (e2, f, _) ->
          (match module_path e2 with
           | Some prefix -> Some (prefix ^ "." ^ f.txt)
           | None -> None)
        | _ -> None
      in
      let mod_access =
        match module_path e with
        | Some prefix ->
          let qualified = prefix ^ "." ^ name.txt in
          (match lookup_var qualified env with
           | Some sch -> Some (instantiate env.level env sch)
           | None ->
             (* For multi-component paths like Conduit.Storage.workflow_load,
                the interface method may be registered as just "Storage.workflow_load"
                (interface-qualified) without the outer module prefix.
                Try progressively stripping leading path components. *)
             let member = name.txt in
             let rec try_suffix p =
               match String.index_opt p '.' with
               | None -> None
               | Some i ->
                 let rest = String.sub p (i + 1) (String.length p - i - 1) in
                 let candidate = rest ^ "." ^ member in
                 (match lookup_var candidate env with
                  | Some sch -> Some (instantiate env.level env sch)
                  | None -> try_suffix rest)
             in
             try_suffix prefix)
        | None -> None
      in
      (match mod_access with
       | Some ty -> ty
       | None ->
      let e_ty = infer_expr env e in
      (match expand_record env (repr e_ty) with
       | Some (TRecord flds) ->
         (match List.assoc_opt name.txt flds with
          | Some t ->
            (* If the field type is linear/affine, accessing it consumes the
               field.  When the record is held in a named variable, a second
               access on the same variable is caught by [record_use].
               For non-variable expressions we emit a diagnostic here. *)
            (match repr t with
             | TLin (lin, _) when lin <> Ast.Unrestricted ->
               (match e with
                | Ast.EVar vname ->
                  (* Record is held in a named variable: check per-field sentinel.
                     Sentinel "varname#fieldname" was registered by bind_lam_param /
                     bind_pattern_bindings when the variable was bound.  If it
                     exists, record_use will catch a second access; if it doesn't
                     (e.g., variable is outer-scope), fall back to checking the
                     whole-record linear entry via record_use on the variable itself. *)
                  let sentinel = vname.txt ^ "#" ^ name.txt in
                  if List.exists (fun le -> le.le_name = sentinel) env.lin then
                    record_use sentinel sp env
                  else begin
                    (* Sentinel not present — warn that we can't track this field. *)
                    ignore lin;
                    Err.warning env.errors ~span:sp
                      (Printf.sprintf
                         "Field `%s` has a linear type but linearity tracking \
                          is not available for `%s` at this binding site.\n\
                          Ensure `%s` is a locally-bound variable."
                         name.txt vname.txt vname.txt)
                  end
                | _ ->
                  Err.error env.errors ~span:sp
                    (Printf.sprintf
                       "Field `%s` has a linear type; accessing it through \
                        a complex expression loses linearity tracking.\n\
                        Bind the record to a variable first."
                       name.txt))
             | _ -> ());
            t
          | None   ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "This record does not have a field called `%s`.\n\
                  The fields I see are: %s"
                 name.txt
                 (String.concat ", " (List.map fst flds)));
            TError)
       | _ ->
         (match repr e_ty with
          | TVar _ ->
            (* Field-access on an unknown record type — return a fresh var for now.
               A row-polymorphism extension would constrain this properly. *)
            fresh_var env.level
          | other ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "I cannot access field `%s` because this expression has \
                  type `%s`, which is not a record." name.txt (pp_ty other));
            TError))
      (* close the None branch of mod_access match *)
      )

    (* ── if/do/else/end ───────────────────────────────────────────── *)
    | Ast.EIf (cond, then_, else_, _sp) ->
      check_expr env cond t_bool
        ~reason:(Some (RBuiltin "The condition of an if expression must be Bool."));
      let t_then = infer_expr env then_ in
      let t_else = infer_expr env else_ in
      (* Point primary error at the else branch; label points at then branch
         (the source of the expected type), making both branches visible. *)
      let then_sp = span_of_expr then_ in
      let else_sp = span_of_expr else_ in
      unify env ~span:else_sp
        ~reason:(Some (RBecause (RMatchArm then_sp,
          "Both branches of an if expression must return the same type.")))
        t_else t_then;
      t_then

    (* ── match do cond_arm* end ───────────────────────────────────── *)
    | Ast.ECond (arms, sp) ->
      (match arms with
       | [] ->
         Err.error env.errors ~span:sp
           "A `match do` expression needs at least one arm.";
         TError
       | (first_cond, first_body) :: rest ->
         check_expr env first_cond t_bool
           ~reason:(Some (RBuiltin "Each condition in `match do` must be Bool."));
         let result_ty = infer_expr env first_body in
         List.iter (fun (cond_e, body_e) ->
             check_expr env cond_e t_bool
               ~reason:(Some (RBuiltin "Each condition in `match do` must be Bool."));
             let arm_ty = infer_expr env body_e in
             unify env ~span:sp ~reason:(Some (RMatchArm sp)) result_ty arm_ty
           ) rest;
         result_ty)

    (* ── Pipes / Sigils — must be desugared before reaching us ───── *)
    | Ast.EPipe _ ->
      failwith
        "March type checker: encountered EPipe — \
         the desugaring pass must run before type checking."

    | Ast.ESigil _ ->
      failwith
        "March type checker: encountered ESigil — \
         the desugaring pass must run before type checking."

    (* ── Atoms ────────────────────────────────────────────────────── *)
    | Ast.EAtom (_, args, _) ->
      List.iter (fun a -> ignore (infer_expr env a)) args;
      t_atom

    (* ── Actor messaging ──────────────────────────────────────────── *)
    | Ast.ESend (cap, msg, sp) ->
      ignore (infer_expr env cap);
      let msg_ty = infer_expr env msg in
      check_sendable env.errors sp msg_ty;
      (* send() returns the handler's result — unconstrained so callers can
         match on Option(a) (drop semantics) or access record fields (state). *)
      fresh_var env.level

    | Ast.ESpawn (actor, _) ->
      ignore (infer_expr env actor);
      (* Both backends dispatch `spawn` by the actor's *name*, resolved at
         compile time (it selects a statically generated `<Actor>_spawn`
         function).  There is no runtime actor-descriptor value, so the argument
         must be a plain actor name — not a computed expression.  The TIR
         lowering assumes exactly this shape (`ECon(_, [], _)` / `EVar`); reject
         anything else here with a clean diagnostic rather than letting a
         well-typed program reach the internal `failwith` in lowering. *)
      (match actor with
       | Ast.ECon (_, [], _) | Ast.EVar _ -> ()
       | _ ->
         Err.error env.errors ~span:(span_of_expr actor)
           "`spawn` needs a plain actor name written directly, like \
            `spawn(Counter)`.\n\
            A computed actor expression (from an `if`, `match`, or function \
            call) isn't supported: March resolves which actor to spawn at \
            compile time from its name.");
      TCon ("Pid", [fresh_var env.level])

    (* ── REPL result reference ─────────────────────────────────────── *)
    | Ast.EResultRef _ ->
      (* Return a fresh unification variable — EResultRef is substituted
         by the REPL loop before typechecking, so this is a fallback. *)
      fresh_var env.level

    (* ── Debugger breakpoint / value trace ────────────────────────── *)
    | Ast.EDbg (None, _) -> t_unit
    | Ast.EDbg (Some inner, _) -> infer_expr env inner

    (* ── Test assertion ─────────────────────────────────────────────── *)
    | Ast.EAssert (inner, sp) ->
      (* The inner expression must be Bool. Assert evaluates to Unit. *)
      check_expr env inner t_bool ~reason:(Some (RBuiltin "assert expects a Bool expression"));
      Hashtbl.replace env.type_map sp t_unit;
      t_unit

    (* ── Local recursive named function (block-scoped) ─────────────── *)
    | Ast.ELetFn (name, params, ret_ann, body, sp) ->
      (* Typecheck the local fn and return the type of its closure.
         When appearing as a standalone expression (last in block), return
         the function type; the binding is only in effect for block context. *)
      let fn_ty = fresh_var env.level in
      let env_with_self = bind_var name.txt (Mono fn_ty) env in
      let param_tys, env_inner = bind_lam_params env_with_self params in
      let body_ty = infer_block env_inner [body] in
      let ret_ty  = match ret_ann with
        | None -> body_ty
        | Some ann ->
          let tvars = ref [] in
          let expected = surface_ty env ~tvars ann in
          unify env ~span:sp ~reason:None body_ty expected;
          expected
      in
      let arrow_ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
      unify env ~span:sp ~reason:None fn_ty arrow_ty;
      arrow_ty

    | Ast.ELetQ (p, result_expr, body, sp) ->
      (* let? p = result_expr; body
         - result_expr  : Result(t_ok, t_err)
         - p            : t_ok  (binds on Ok branch)
         - body         : Result(t_r, t_err)  (continuation)
         Returns Result(t_r, t_err), propagating Err upward automatically. *)
      (match body with
       | Ast.EBlock ([], _) ->
         Err.error env.errors ~span:sp
           "`let?` cannot be the last expression in a block.\n\
            Add a Result-producing expression after it — for example:\n\
            \n\
            \    let? x = might_fail()\n\
            \    Ok(x + 1)";
         TError
       | _ ->
         let result_ty = infer_expr env result_expr in
         let t_ok  = fresh_var env.level in
         let t_err = fresh_var env.level in
         unify env ~span:sp
           ~reason:(Some (RBuiltin
             "The right-hand side of `let?` must be a Result value."))
           result_ty (t_result t_ok t_err);
         let bindings, pat_ty = infer_pattern env p in
         unify env ~span:sp
           ~reason:(Some (RLetBind sp))
           t_ok pat_ty;
         let env' = bind_pattern_bindings result_expr bindings env in
         let body_ty = infer_expr env' body in
         let t_r = fresh_var env.level in
         unify env ~span:sp
           ~reason:(Some (RBuiltin
             "The code after `let?` must produce a Result with the same error type."))
           body_ty (t_result t_r t_err);
         body_ty)
  in
  Hashtbl.replace env.type_map (span_of_expr e) (repr result);
  result

(** [check_expr env e expected ~reason] verifies [e] has type [expected].
    Uses the "checking" direction for lambdas (peels off arrows) and for
    match expressions (checks each arm against [expected]).  Falls back
    to infer + unify for everything else. *)
and check_expr env (e : Ast.expr) (expected : ty) ~reason =
  let sp = span_of_expr e in
  Hashtbl.replace env.type_map sp (repr expected);
  match e, repr expected with

  (* Lambda in check mode: peel arrow types one-by-one *)
  | Ast.ELam (params, body, lsp), _ ->
    let rec peel ps ty env =
      match ps, repr ty with
      | [], body_ty ->
        check_expr env body body_ty ~reason
      | p :: rest, TArrow (arg_ty, ret_ty) ->
        let env' = bind_lam_param env lsp p (Some arg_ty) in
        peel rest ret_ty env'
      | _, _ ->
        let inferred = infer_expr env (Ast.ELam (params, body, lsp)) in
        unify env ~span:lsp ~reason inferred expected
    in
    peel params expected env

  (* Match in check mode: check each arm against expected *)
  | Ast.EMatch (scrut, branches, msp), _ ->
    let scrut_ty = infer_expr env scrut in
    List.iter (fun (br : Ast.branch) ->
        let bindings, pat_ty = infer_pattern ~expected:scrut_ty env br.branch_pat in
        unify env ~span:msp ~reason:(Some (RMatchArm msp)) scrut_ty pat_ty;
        (* Propagate linearity from scrutinee to pattern-bound variables. *)
        let env' = bind_pattern_bindings scrut bindings env in
        (match br.branch_guard with
         | Some g ->
           check_expr env' g t_bool
             ~reason:(Some (RBuiltin "Match guards must be Bool."))
         | None -> ());
        check_expr env' br.branch_body expected ~reason
      ) branches;
    check_exhaustiveness env msp scrut_ty branches

  (* Constructor in check mode: when the bare constructor name is ambiguous
     across types, use the expected type to pick the candidate whose parent
     type matches — mirroring the pattern path ([infer_pattern]'s by_expected
     logic). Without this, the catch-all below would route through [infer_expr],
     whose [lookup_ctor] makes a registration-order-dependent pick; if it
     guesses the wrong type the result fails to unify. Resolving by expected
     type also lets nested constructors disambiguate recursively (the args are
     checked against the chosen constructor's field types). *)
  | Ast.ECon (name, args, sp), exp_ty
    when (not (String.contains name.txt '.'))
         && (match exp_ty with TCon _ -> true | _ -> false)
         && List.length (all_ctors_named name.txt env) > 1 ->
    (match (match exp_ty with
            | TCon (tn, _) -> lookup_ctor_in_type name.txt tn env
            | _ -> None) with
     | Some ci ->
       let arg_tys, result_ty = instantiate_ctor env ci in
       let n_expected = List.length arg_tys in
       let n_got      = List.length args in
       if n_expected <> n_got then begin
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "Constructor `%s` expects %d argument(s) but I got %d."
              name.txt n_expected n_got);
         List.iter (fun a -> ignore (infer_expr env a)) args
       end else begin
         List.iter2 (fun arg arg_ty ->
             check_expr env arg arg_ty
               ~reason:(Some (RBuiltin
                 (Printf.sprintf "Argument to constructor `%s`." name.txt)))
           ) args arg_tys;
         unify env ~span:sp ~reason result_ty expected
       end
     | None ->
       (* Expected type doesn't name a type defining this constructor —
          fall back to inference so the normal mismatch error is produced. *)
       let inferred = infer_expr env e in
       unify env ~span:sp ~reason inferred expected)

  (* All other expressions: infer then unify *)
  | _ ->
    let inferred = infer_expr env e in
    unify env ~span:sp ~reason inferred expected

(** Thread function application through argument list, tracking arg index. *)
and infer_app env span f_ty args idx =
  match args, repr f_ty with
  | [], t -> t
  | arg :: rest, TArrow (param_ty, ret_ty) ->
    check_expr env arg param_ty
      ~reason:(Some (RFnArg (span, idx)));
    (* Proof-cap forge taint: if this argument laundered a [cap_narrow] result
       (its type — now unified with [param_ty] — carries a tagged cap-producer
       var), taint [ret_ty].  This closes the launder-through-a-polymorphic-fn
       routes (e.g. [consume(id(cap_narrow(cap)))]) where the fn's return
       decouples from its param and would otherwise slip past the direct unify
       hook: the tainted result is then rejected when it is bound to a proof cap.
       Only proof caps are ever rejected downstream, so IO narrowing through the
       same fn is unaffected. *)
    if ty_has_tagged_cap_producer env param_ty then
      tag_cap_producer_result env ret_ty span;
    infer_app env span ret_ty rest (idx + 1)
  | arg :: rest, TVar _ ->
    (* f_ty not yet known — constrain it *)
    let arg_ty = infer_expr env arg in
    let ret_ty = fresh_var env.level in
    unify env ~span
      ~reason:(Some (RBuiltin "A value being applied like a function must have a function type."))
      f_ty (TArrow (arg_ty, ret_ty));
    (* Proof-cap forge taint (same as the TArrow branch): a laundered cap_narrow
       argument taints the call's result so the unify hook still fires downstream. *)
    if ty_has_tagged_cap_producer env arg_ty then
      tag_cap_producer_result env ret_ty span;
    infer_app env span ret_ty rest (idx + 1)
  | _, TError ->
    List.iter (fun a -> ignore (infer_expr env a)) args;
    TError
  | _, other ->
    Err.error env.errors ~span
      (Printf.sprintf
         "This is not a function — it has type `%s`.\n\
          I cannot apply it to arguments." (pp_ty other));
    List.iter (fun a -> ignore (infer_expr env a)) args;
    TError

(** Infer the result type of a match expression. *)
and infer_match env span scrut scrut_ty branches =
  let result_ty = fresh_var env.level in
  List.iter (fun (br : Ast.branch) ->
      let bindings, pat_ty = infer_pattern ~expected:scrut_ty env br.branch_pat in
      unify env ~span ~reason:(Some (RMatchArm span)) scrut_ty pat_ty;
      (* Propagate linearity from scrutinee to pattern-bound variables. *)
      let env' = bind_pattern_bindings scrut bindings env in
      (match br.branch_guard with
       | Some g ->
         check_expr env' g t_bool
           ~reason:(Some (RBuiltin "Match guards must be Bool."))
       | None -> ());
      check_expr env' br.branch_body result_ty
        ~reason:(Some (RMatchArm span))
    ) branches;
  check_exhaustiveness env span scrut_ty branches;
  check_redundant_arms env scrut_ty branches;
  result_ty

(** Compute the type of a `let`-binding RHS, honouring an optional type
    annotation (`let x : T = e`, finding 16).  When [bind_ty] is present the
    annotation becomes a CHECKING context for the RHS (via [check_expr]) — a
    mismatch like `let x : Int = "foo"` is rejected, while a polymorphic RHS
    bound at a more specific instance (`let f : (Int) -> Int = fn x -> x`)
    still typechecks.

    The annotation is resolved into a scratch error context first: if
    [surface_ty] cannot resolve it (e.g. a phantom/typestate tag used in type
    position, `let h : Handle(Open) = …`, which is a data constructor, not a
    type name), we discard the scratch errors and fall back to plain inference
    — exactly the pre-finding-16 behaviour for annotations the type grammar
    can't express, so no legitimate program starts being rejected. *)
and infer_let_annotated env sp bind_ty bind_expr =
  match bind_ty with
  | None -> infer_expr env bind_expr
  | Some ann ->
    let scratch = March_errors.Errors.create () in
    let tvars = ref [] in
    let ann_ty = surface_ty { env with errors = scratch } ~tvars ann in
    if March_errors.Errors.has_errors scratch then
      (* Annotation not expressible as a resolvable type — ignore it (legacy
         behaviour) and infer from the RHS alone. *)
      infer_expr env bind_expr
    else begin
      check_expr env bind_expr ann_ty ~reason:(Some (RAnnotation sp));
      ann_ty
    end

(** Infer types of all expressions in a block, threading [ELet] bindings. *)
and infer_block env exprs =
  match exprs with
  | [] -> t_unit
  | [ e ] -> infer_expr env e
  | Ast.ELet (b, sp) :: rest ->
    (* Use enter_level so the RHS is checked at a fresh level.  This ensures
       that `occurs` lowers any TVars that escape into outer-scope types (e.g.
       the return type of a curried application f(acc) where f is a parameter)
       before generalize is called.  Without the level bump, those intermediate
       TVars share the function-body level and get incorrectly quantified, causing
       `let f1 = f(acc); f1(k)` to instantiate a fresh TVar for f1 rather than
       unifying the original t_r1 that links f's curried return chain. *)
    let env_rhs = enter_level env in
    (* If the binding carries a type annotation (`let x : T = e`), CHECK the
       RHS against the annotated type rather than inferring it bare.  Using
       check_expr (not just a post-hoc unify) gives a legitimately polymorphic
       RHS a checking context, so `let f : (Int) -> Int = fn x -> x` still
       works while `let x : Int = "foo"` is rejected.  The annotated type then
       becomes the binding's type, so the pattern unifies against it. *)
    let rhs_ty = infer_let_annotated env_rhs sp b.bind_ty b.bind_expr in
    let bindings, pat_ty = infer_pattern env_rhs b.bind_pat in
    unify env_rhs ~span:sp ~reason:(Some (RLetBind sp)) rhs_ty pat_ty;
    (* Record the binding type in type_map so LSP hover over `let x = …` shows
       the RHS type rather than the enclosing block's return type. *)
    Hashtbl.replace env.type_map sp (repr rhs_ty);
    (match b.bind_pat with
     | Ast.PatVar name -> Hashtbl.replace env.type_map name.span (repr rhs_ty)
     | _ -> ());
    (* Generalise the binding if it's a simple variable — let-polymorphism.
       Use env.level (not env.level - 1) as the generalization threshold: only
       TVars created inside env_rhs (level env.level+1) that did NOT escape into
       outer types via occurs-check lowering are quantified.  Lambda-bound TVars
       created at env_rhs.level stay at that level (no outer reference lowers
       them) and are correctly quantified; function-call result TVars that are
       linked to outer-scope TVars get lowered to env.level and are not
       quantified. *)
    let gen_binding bnd = match bnd with
      | (name, Mono t) -> (name, generalize env.level t)
      | other          -> other
    in
    let bindings' = match b.bind_pat with
      | Ast.PatVar _ -> List.map gen_binding bindings
      | _            -> bindings
    in
    (* Propagate linearity: if bind_lin is Linear/Affine (written as
       `linear let x = ...` or `affine let x = ...`), override the
       normal binding and register the variable as linear/affine.
       If bind_lin is Unrestricted but the RHS type is an always-linear type
       constructor, auto-promote the binding to Linear.
       Otherwise, propagate linearity from the RHS expression type. *)
    let auto_lin =
      match b.bind_lin with
      | Ast.Unrestricted ->
        let rty = repr rhs_ty in
        (match rty with
         | TCon (name, _) ->
           if List.mem name env.always_linear_types then Ast.Linear else Ast.Unrestricted
         | _ -> Ast.Unrestricted)
      | lin -> lin
    in
    let env' = match auto_lin with
      | Ast.Unrestricted ->
        bind_pattern_bindings b.bind_expr bindings' env
      | lin ->
        (* For linear/affine bindings, extract the underlying type from Poly schemes
           too — phantom type params cause gen_binding to generalize, but the binding
           is still a single concrete value that must be consumed exactly once. *)
        List.fold_left (fun acc_env (bname, sch) ->
            let t = match sch with
              | Mono t | Poly (_, _, t) -> t
            in
            bind_linear bname lin t acc_env
          ) env bindings'
    in
    let result_ty = infer_block env' rest in
    (* After the rest of the block has run, verify that any linear let
       bindings introduced here were consumed (used exactly once). *)
    (match auto_lin with
     | Ast.Unrestricted -> ()
     | _lin ->
       let linear_names = List.map fst bindings' in
       check_linear_all_consumed env' ~scope_span:sp linear_names);
    result_ty
  (* Local named recursive function: fn go(params) : ret_ty do body end *)
  | Ast.ELetFn (name, params, ret_ann, body, sp) :: rest ->
    (* Introduce a fresh type for the function, check recursively *)
    let fn_ty = fresh_var env.level in
    let env_with_self = bind_var name.txt (Mono fn_ty) env in
    let param_tys, env_inner = bind_lam_params env_with_self params in
    (* Record each param's inferred type in the type_map at its name span.
       check_fn does this for top-level DFn params (line ~3706), but ELetFn
       goes through bind_lam_params which uses dummy_span and skips this.
       Without it, lower.ml's ty_of_span(p.param_name.span) returns TVar "_"
       for every ELetFn param, collapsing all params to a single unknown type
       that breaks monomorphization of inner functions (e.g. Map.from_list's
       inner `go` getting TVar "_" instead of TVar "_17776" / "_17775"). *)
    List.iter2 (fun (p : Ast.param) pty ->
        Hashtbl.replace env.type_map p.param_name.span (repr pty)
      ) params param_tys;
    let body_ty = infer_block env_inner [body] in
    (* Track whether the return-annotation unify (below) already reported a
       mismatch, so the later self-type/arrow-type reconciliation does not
       rediscover and DOUBLE-REPORT the identical conflict once it flows
       through the self-reference `fn_ty` (finding 13).  We compare the
       diagnostic count before/after rather than a boolean, so a genuinely
       distinct error from the self-reference (which grows the count on the
       arrow unify but NOT here) is still surfaced. *)
    let errs_before_ret = List.length env.errors.March_errors.Errors.diagnostics in
    let ret_ty  = match ret_ann with
      | None -> body_ty
      | Some ann ->
        let tvars = ref [] in
        let expected = surface_ty env ~tvars ann in
        unify env ~span:sp ~reason:None body_ty expected;
        expected
    in
    let ret_annot_reported =
      List.length env.errors.March_errors.Errors.diagnostics > errs_before_ret
    in
    let arrow_ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
    if ret_annot_reported then
      (* The return-annotation unify already reported this mismatch; run the
         arrow reconciliation for its type-linking side effects only, routing
         any (duplicate) report to a scratch context that we discard. *)
      unify { env with errors = March_errors.Errors.create () }
        ~span:sp ~reason:None fn_ty arrow_ty
    else
      unify env ~span:sp ~reason:None fn_ty arrow_ty;
    let gen_ty = generalize (env.level - 1) arrow_ty in
    let env' = bind_var name.txt gen_ty env in
    infer_block env' rest
  | e :: rest ->
    ignore (infer_expr env e);
    infer_block env rest

(** Bind lambda parameters into the environment, returning (types, env). *)
and bind_lam_params env params =
  List.fold_right
    (fun p (tys, env) ->
       let t = fresh_var env.level in
       let env' = bind_lam_param env Ast.dummy_span p (Some t) in
       (t :: tys, env'))
    params ([], env)

and bind_lam_param env _sp (p : Ast.param) ann_ty =
  let t = match p.param_ty, ann_ty with
    | Some ann, _ ->
      let tvars = ref [] in
      surface_ty env ~tvars ann
    | None, Some t -> t
    | None, None   -> fresh_var env.level
  in
  let effective_lin = match p.param_lin with
    | Ast.Unrestricted ->
      (match repr t with
       | TCon (name, _) when List.mem name env.always_linear_types -> Ast.Linear
       | _ -> Ast.Unrestricted)
    | lin -> lin
  in
  match effective_lin with
  | Ast.Unrestricted ->
    let env1 = bind_var p.param_name.txt (Mono t) env in
    bind_linear_field_sentinels p.param_name.txt t env1
  | lin -> bind_linear p.param_name.txt lin t env

(* =================================================================
   §15  Declaration checking
   ================================================================= *)

(** Collect all free variable names referenced in [e].
    Only [EVar] nodes with no dot (non-qualified names) are collected.
    Re-bindings introduced by [ELet]/[EMatch]/[ELam] are accounted for so
    we never report a variable that is shadowed by an inner binding. *)
let rec free_vars_expr (bound : string list) (e : Ast.expr) : string list =
  match e with
  | Ast.EVar n ->
    (* Keep DOTTED names too (e.g. `App.id`, produced by desugar's
       [qualify_module_refs] for an intra-nested-module reference).  The only two
       callers are [dependency_order_dfn_run]'s [deps_of] — which maps a dotted
       name's suffix to a local fn so a nested-module forward reference is ordered
       helper-first (closing the qualified-prebind type-erasure forward-ref hole)
       — and [warn_unused_params], which only compares against bare param names, so
       a dotted entry is inert there.  A bound name is still dropped. *)
    if List.mem n.txt bound then [] else [n.txt]
  | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> []
  | Ast.EDbg (Some inner, _) -> free_vars_expr bound inner
  | Ast.EApp (f, args, _) ->
    free_vars_expr bound f @ List.concat_map (free_vars_expr bound) args
  | Ast.ECon (_, args, _) -> List.concat_map (free_vars_expr bound) args
  | Ast.ELam (ps, body, _) ->
    let inner_bound = List.filter_map (fun (p : Ast.param) ->
        Some p.param_name.txt) ps @ bound in
    free_vars_expr inner_bound body
  | Ast.EBlock (es, _) -> free_vars_block bound es
  | Ast.ELet (b, _) -> free_vars_expr bound b.Ast.bind_expr
  | Ast.EMatch (scrut, branches, _) ->
    free_vars_expr bound scrut @
    List.concat_map (fun br ->
      let pat_bound = free_vars_pattern br.Ast.branch_pat in
      let inner = pat_bound @ bound in
      Option.fold ~none:[] ~some:(free_vars_expr inner) br.Ast.branch_guard @
      free_vars_expr inner br.Ast.branch_body
    ) branches
  | Ast.ETuple (es, _) -> List.concat_map (free_vars_expr bound) es
  | Ast.ERecord (fields, _) ->
    List.concat_map (fun (_, ex) -> free_vars_expr bound ex) fields
  | Ast.ERecordUpdate (base, fields, _) ->
    free_vars_expr bound base @
    List.concat_map (fun (_, ex) -> free_vars_expr bound ex) fields
  | Ast.EField (ex, _, _) -> free_vars_expr bound ex
  | Ast.EIf (c, t, f, _) ->
    free_vars_expr bound c @ free_vars_expr bound t @ free_vars_expr bound f
  | Ast.ECond (arms, _) ->
    List.concat_map (fun (ce, be) ->
        free_vars_expr bound ce @ free_vars_expr bound be) arms
  | Ast.EAnnot (ex, _, _) -> free_vars_expr bound ex
  | Ast.EAtom (_, args, _) -> List.concat_map (free_vars_expr bound) args
  | Ast.ESend (a, b, _) ->
    free_vars_expr bound a @ free_vars_expr bound b
  | Ast.ESpawn (e, _) -> free_vars_expr bound e
  | Ast.ELetFn (name, params, _, body, _) ->
    let inner_bound = name.txt :: List.map (fun p -> p.Ast.param_name.txt) params @ bound in
    free_vars_expr inner_bound body
  | Ast.ELetQ (p, result, cont, _) ->
    let pat_bound = free_vars_pattern p in
    free_vars_expr bound result @
    free_vars_expr (pat_bound @ bound) cont
  | Ast.EPipe (l, r, _) ->
    free_vars_expr bound l @ free_vars_expr bound r
  | Ast.EAssert (e, _) -> free_vars_expr bound e
  | Ast.ESigil (_, content, _) -> free_vars_expr bound content

and free_vars_block (bound : string list) (es : Ast.expr list) : string list =
  match es with
  | [] -> []
  | Ast.ELet (b, _) :: rest ->
    let used_in_rhs = free_vars_expr bound b.Ast.bind_expr in
    let pat_bound = free_vars_pattern b.Ast.bind_pat in
    used_in_rhs @ free_vars_block (pat_bound @ bound) rest
  | e :: rest ->
    free_vars_expr bound e @ free_vars_block bound rest

and free_vars_pattern (p : Ast.pattern) : string list =
  match p with
  | Ast.PatVar n -> [n.txt]
  | Ast.PatWild _ -> []
  | Ast.PatLit _ -> []
  | Ast.PatCon (_, ps) -> List.concat_map free_vars_pattern ps
  | Ast.PatTuple (ps, _) -> List.concat_map free_vars_pattern ps
  | Ast.PatRecord (fields, _) -> List.concat_map (fun (_, p) -> free_vars_pattern p) fields
  | Ast.PatAs (p, n, _) -> n.txt :: free_vars_pattern p
  | Ast.PatAtom (_, ps, _) -> List.concat_map free_vars_pattern ps

(** Emit unused-variable warnings for fn params not referenced in the body.
    The wildcard [_] and names starting with [_] are silently ignored. *)
let warn_unused_params env (params : Ast.fn_param list) (body : Ast.expr) _fn_span =
  let used = free_vars_expr [] body in
  let check_name name span =
    if name <> "_" && not (String.length name > 0 && name.[0] = '_')
       && not (List.mem name used) then
      Err.warning_with_code_and_fix env.errors ~span ~code:"unused_binding"
        ~fix:(Err.FReplace { span; text = "_" ^ name })
        (Printf.sprintf "Unused variable `%s`.\n\
                         Use `_` to mark intentionally unused params." name)
  in
  List.iter (fun fp ->
    match fp with
    | Ast.FPNamed p -> check_name p.param_name.txt p.param_name.span
    | Ast.FPPat (Ast.PatVar n) -> check_name n.txt n.span
    | Ast.FPPat _ -> ()
    | Ast.FPDefault (p, _) -> check_name p.param_name.txt p.param_name.span
  ) params

(** Check a function definition.

    Strategy:
    1. Enter a fresh generalization level.
    2. Add a monomorphic self-reference (allows recursion).
    3. Bind each parameter into the env.
    4. Infer/check the body.
    5. Leave level and generalize the function type.
    6. Return the scheme so the caller can update the env. *)
let check_fn env (def : Ast.fn_def) fn_span : scheme =
  let env'    = enter_level env in
  (* Self-reference for recursion — a fresh var that will get unified
     with the actual type as the body is checked.
     For default-arg wrappers (multiple DFn with the same name), the full-arity
     version is processed first.  When a wrapper is checked, the function name
     is already bound to a concrete type in the environment.  In that case we
     reuse the existing binding so the wrapper body can call the full function
     at a different arity without a self-type conflict. *)
  let self_ty, env_rec, placeholder =
    match StrMap.find_opt def.fn_name.txt env'.vars with
    | Some (Mono (TVar _ as pv)) ->
      (* Pass-1 forward-reference placeholder.  It is a bare [Mono (TVar _)]:
         either still Unbound, or already Linked because an EARLIER caller in
         this module unified its use site against it.  Either way it is the
         placeholder (a genuine concrete binding — e.g. a default-arg wrapper's
         full-arity sibling — is always [Mono (TArrow ..)] or [Poly _], never a
         bare [Mono (TVar _)]).  Use a fresh self-ref for recursion and keep a
         handle on the placeholder so we can reconcile it with the inferred type
         after generalization (see below). *)
      let sv = fresh_var env'.level in
      (sv, bind_var def.fn_name.txt (Mono sv) env', Some pv)
    | Some existing_sch ->
      (* Already concretely typed (e.g. full-arity default-arg fn) — keep it
         so the wrapper body resolves calls at the full arity correctly.
         Still create a self_ty for the unify at the end of check_fn. *)
      let sv = fresh_var env'.level in
      (sv, bind_var def.fn_name.txt existing_sch env', None)
    | None ->
      let sv = fresh_var env'.level in
      (sv, bind_var def.fn_name.txt (Mono sv) env', None)
  in

  let sch = match def.fn_clauses with
    | [] ->
      Err.error env.errors ~span:fn_span
        (Printf.sprintf "Function `%s` has no clauses." def.fn_name.txt);
      Mono TError

    | [clause] ->
      (* Shared type variable mapping for this function's signature.
         Using a single ref across all param annotations, return type, and
         class constraints ensures that the same type variable name (e.g. `a`)
         in `fn foo(x : a, y : a) : a when Eq(a)` maps to the same
         unification variable everywhere. *)
      let fn_tvars = ref [] in

      (* Pre-register explicit bound type variables from fn_bounds and build
         bound constraints.  Bounds like [s : ConnState] pre-register `s` in
         fn_tvars so that param annotations referencing `s` (e.g.
         Handle(Conn, s)) share the same unification variable. *)
      let bound_constraints =
        List.filter_map (fun ((var_name : Ast.name), bound_surface) ->
            let tv = match List.assoc_opt var_name.txt !fn_tvars with
              | Some t -> t
              | None ->
                let fv = fresh_var env'.level in
                fn_tvars := (var_name.txt, fv) :: !fn_tvars;
                fv
            in
            match bound_surface with
            | Ast.TyNat _ -> Some (CTNatBound tv)
            | Ast.TyCon (n, []) ->
              if n.txt = "Nat" then Some (CTNatBound tv)
              else if StrMap.mem n.txt env.interfaces
              then Some (CInterface (n.txt, tv))
              else begin
                (* Validate that the ADT exists in scope *)
                match lookup_type n.txt env with
                | None ->
                  Err.error env.errors ~span:n.span
                    (Printf.sprintf
                       "Bound `%s` is not a known ADT or interface name."
                       n.txt);
                  None
                | Some _ -> Some (CADTBound (n.txt, tv))
              end
            | _ ->
              Err.error env.errors ~span:var_name.span
                (Printf.sprintf
                   "Bound `%s` on type variable `%s` must be an ADT name, \
                    interface name, or `Nat`."
                   (Ast.show_ty bound_surface) var_name.txt);
              None
          ) def.fn_bounds
      in

      (* Bind parameters *)
      let param_tys, body_env =
        List.fold_right (fun fp (tys, env) ->
            match fp with
            | Ast.FPNamed p ->
              let t = match p.param_ty with
                | Some ann -> surface_ty env' ~tvars:fn_tvars ann
                | None -> fresh_var env'.level
              in
              let effective_lin = match p.param_lin with
                | Ast.Unrestricted ->
                  (match repr t with
                   | TCon (tname, _) when List.mem tname env'.always_linear_types -> Ast.Linear
                   | _ -> Ast.Unrestricted)
                | lin -> lin
              in
              let env' = match effective_lin with
                | Ast.Unrestricted -> bind_var p.param_name.txt (Mono t) env
                | lin              -> bind_linear p.param_name.txt lin t env
              in
              (t :: tys, env')
            | Ast.FPPat (Ast.PatVar name) ->
              (* Single variable pattern — trivially named; bind it directly *)
              let t = fresh_var env'.level in
              let env' = bind_var name.txt (Mono t) env in
              (t :: tys, env')
            | Ast.FPPat pat ->
              (* Complex pattern parameter: should have been desugared into a
                 match, but handle gracefully by binding inferred pattern vars *)
              let t = fresh_var env'.level in
              let pat_bindings, _ = infer_pattern env pat in
              let env' = bind_vars pat_bindings env in
              (t :: tys, env')
            | Ast.FPDefault (p, _) ->
              (* Default should have been expanded by desugar; handle gracefully *)
              let t = match p.param_ty with
                | Some ann -> surface_ty env' ~tvars:fn_tvars ann
                | None -> fresh_var env'.level
              in
              let env' = bind_var p.param_name.txt (Mono t) env in
              (t :: tys, env')
          ) clause.fc_params ([], env_rec)
      in

      (* Proof-cap mint gate context: the body is inside a PUBLIC fn iff fn_vis
         is Public. Set on body_env so the `mint_cap` EApp special-case can
         require declaring-module + public provenance. Lambdas inherit this
         (they don't call check_fn); nested named fns/modules reset it via their
         own check_fn. *)
      let body_env = { body_env with cur_fn_public = (def.fn_vis = Ast.Public) } in

      (* Record each named parameter's type in the type map *)
      List.iter2 (fun fp pty ->
          match fp with
          | Ast.FPNamed p ->
            Hashtbl.replace env.type_map p.param_name.span (repr pty)
          | Ast.FPPat (Ast.PatVar name) ->
            Hashtbl.replace env.type_map name.span (repr pty)
          | Ast.FPPat _ -> ()
          | Ast.FPDefault (p, _) ->
            Hashtbl.replace env.type_map p.param_name.span (repr pty)
        ) clause.fc_params param_tys;

      (* Process the when-clause: distinguish class constraints from guards.
         A class constraint looks like `ECon("Eq", [EVar "a"])` where "Eq"
         is a known interface name.  Such guards are treated as type-class
         constraints added to the function scheme rather than checked as Bool
         expressions. *)
      let class_constraints =
        match clause.fc_guard with
        | None -> []
        | Some (Ast.ECon (iface_name, args, _))
          when StrMap.mem iface_name.txt env.interfaces ->
          (* It's a class constraint: Eq(a), Ord(b), etc. *)
          List.filter_map (fun arg ->
              match arg with
              | Ast.EVar v ->
                let ty = match List.assoc_opt v.txt !fn_tvars with
                  | Some t -> t
                  | None   ->
                    (* Not a signature type-variable name (e.g. the annotation
                       type-var `a` in `fn f(x : a) when Eq(a)`, or a bound
                       `[s : I]`).  In `fn same(a, b) when Eq(a)` the `a` names
                       a VALUE PARAMETER whose type is a fresh var bound in
                       body_env — resolve to THAT type so the constraint rides
                       on the parameter's own type variable and is re-checked at
                       call sites (finding 15).  Only if the name is neither a
                       signature type var nor a bound value do we fall back to a
                       fresh, registered placeholder. *)
                    (match lookup_var v.txt body_env with
                     | Some (Mono t) -> t
                     | Some (Poly (_, _, t)) -> t
                     | None ->
                       let fv = fresh_var env'.level in
                       fn_tvars := (v.txt, fv) :: !fn_tvars;
                       fv)
                in
                Some (CInterface (iface_name.txt, ty))
              | _ -> None
            ) args
        | Some g ->
          (* Normal expression guard: type-check it as Bool *)
          check_expr body_env g t_bool
            ~reason:(Some (RBuiltin "Function guards must be Bool."));
          []
      in

      (* Check or infer the body, sharing fn_tvars with the return annotation *)
      let body_ty = match def.fn_ret_ty with
        | Some ann ->
          let expected = surface_ty env' ~tvars:fn_tvars ann in
          check_expr body_env clause.fc_body expected
            ~reason:(Some (RFnReturn (def.fn_name.txt, fn_span)));
          expected
        | None ->
          infer_expr body_env clause.fc_body
      in

      (* Check linear params were all consumed *)
      let param_names = List.filter_map (function
          | Ast.FPNamed p -> Some p.param_name.txt
          | Ast.FPDefault (p, _) -> Some p.param_name.txt
          | Ast.FPPat _ -> None) clause.fc_params in
      check_linear_all_consumed body_env ~scope_span:fn_span param_names;

      (* Warn about unrestricted params not referenced in the body *)
      warn_unused_params env clause.fc_params clause.fc_body fn_span;

      (* Proof-cap forge value restriction across fn boundaries: if this fn's
         body is (or launders) a [cap_narrow] result (e.g.
         `fn mk(cap) do cap_narrow(cap) end`), its cap-producer return var must
         NOT generalize — otherwise each cross-module call instantiates a fresh,
         untagged copy that escapes the unify hook and can be forged into a proof
         cap.  Demote the return type's vars to level 0 so [generalize] below
         keeps them monomorphic, and re-tag so the shared var is caught when a
         call binds it to a proof cap. *)
      (* Record a cap-narrow-factory fn: its body launders a [cap_narrow] result,
         so a cross-module call to it (which resolves to the prebound scheme,
         invisible to the unify hook's per-var tag) must taint its result at the
         call site — see the [EApp] handling of a factory name. *)
      if ty_has_tagged_cap_producer env body_ty then begin
        Hashtbl.replace env.cap_narrow_factory_fns def.fn_name.txt fn_span;
        if env.current_module <> "" then
          Hashtbl.replace env.cap_narrow_factory_fns
            (env.current_module ^ "." ^ def.fn_name.txt) fn_span
      end;

      let fn_ty =
        List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys body_ty
      in
      (* Record the function's overall type at the function name's span *)
      Hashtbl.replace env.type_map def.fn_name.span (repr fn_ty);
      (* Unify self_ty so recursive calls get the correct type *)
      unify env' ~span:fn_span self_ty fn_ty;

      (* Generalize; attach bound constraints and any when-clause class constraints *)
      let all_constraints = bound_constraints @ class_constraints in
      let base_sch = generalize env.level fn_ty in
      (match all_constraints with
       | [] -> base_sch
       | cs  ->
         match base_sch with
         | Poly (ids, existing_cs, t) -> Poly (ids, cs @ existing_cs, t)
         | Mono t ->
           (* Collect ids of quantified vars referenced in constraints so they
              are properly generalized even when not referenced in the type *)
           let constraint_tv = function
             | CInterface (_, tv) | CADTBound (_, tv) | CTNatBound tv -> Some tv
             | CNum tv | COrd tv -> Some tv
           in
           let extra_ids = List.filter_map (fun c ->
               match constraint_tv c with
               | None -> None
               | Some tv ->
                 (match repr tv with
                  | TVar r ->
                    (match !r with
                     | Unbound (id, l) when l > env.level -> Some id
                     | _ -> None)
                  | _ -> None)
             ) cs in
           Poly (extra_ids, cs, t))

    | _ ->
      (* Multi-clause fn — desugar pass should have eliminated these *)
      Err.error env.errors ~span:fn_span
        (Printf.sprintf
           "Internal error: fn `%s` has multiple clauses after desugaring."
           def.fn_name.txt);
      Mono TError
  in

  (* Reconcile the pass-1 forward-reference placeholder with the inferred type.
     During pass 1 every module function is pre-bound to a single placeholder
     var so forward references resolve.  A caller checked BEFORE this definition
     unified its use site against that placeholder; if we now simply discard it,
     the caller can be left with an unresolved free type var (e.g.
     `List('_NNNN)`).  That miscompiles: a polymorphic list is RC-handled
     differently than its concrete instance, causing a use-after-free.

     We only reconcile when this function's inferred scheme is MONOMORPHIC
     (`Mono _`, no type parameters).  A monomorphic function has exactly one
     type, so unifying every forward use site with it is always sound.  A
     POLYMORPHIC function must keep its per-use instantiation (a caller may use
     it at several types — see the "forward-ref pfn called at two element
     types" test), so we leave the placeholder alone in that case. *)
  (match placeholder, sch with
   | Some pv, Mono t ->
     unify env' ~span:fn_span ~reason:None pv t
   | _ -> ());

  ignore (leave_level env');
  sch

(** [impl_matches_ty impl_ty target_ty] returns true if [target_ty] could be
    satisfied by an implementation typed as [impl_ty].  Free unification
    variables in [impl_ty] (from parameterised impls like [List(a)]) are
    treated as wildcards that match any type. *)
let rec impl_matches_ty impl_ty target_ty =
  match repr impl_ty, repr target_ty with
  | TVar _, _ -> true  (* polymorphic impl var — matches anything *)
  | _, TVar _ -> false (* target still unresolved — cannot confirm *)
  | TCon (n1, as1), TCon (n2, as2)
    when n1 = n2 && List.length as1 = List.length as2 ->
    List.for_all2 impl_matches_ty as1 as2
  | TArrow (a1, b1), TArrow (a2, b2) ->
    impl_matches_ty a1 a2 && impl_matches_ty b1 b2
  | TTuple ts1, TTuple ts2 when List.length ts1 = List.length ts2 ->
    List.for_all2 impl_matches_ty ts1 ts2
  | TRecord f1, TRecord f2
    when List.map fst f1 = List.map fst f2 ->
    List.for_all2 (fun (_, t1) (_, t2) -> impl_matches_ty t1 t2) f1 f2
  | TLin (_, t1), TLin (_, t2) -> impl_matches_ty t1 t2
  | TError, _ | _, TError -> true
  | a, b -> a = b

(** Pre-register an interface implementation's SHAPE (pass 1) so that
    CInterface constraints from modules checked earlier in the unit can be
    discharged against impls declared in modules checked later.  Conversion
    is lenient — [impl_matches_ty] only compares constructor names and
    shapes, so unresolved type names are embedded as-is rather than resolved
    against the (still incomplete) pass-1 environment.  The full registration
    with properly instantiated types still happens in check_decl's DImpl
    case; duplicates are harmless because discharge uses List.exists. *)
let register_impl_shape env (idef : Ast.impl_def) =
  let module M = Map.Make (String) in
  let tvars = ref M.empty in
  let rec lenient_ty (t : Ast.ty) : ty =
    match t with
    | Ast.TyVar n ->
      (match M.find_opt n.txt !tvars with
       | Some v -> v
       | None ->
         let v = fresh_var 1 in
         tvars := M.add n.txt v !tvars;
         v)
    | Ast.TyCon (n, args)  ->
      let args' = List.map lenient_ty args in
      (* Expand a record type name to its structural form, exactly as
         [surface_ty] (and so [check_decl]'s DImpl handler) does. Without this,
         an impl on a record type is registered here under the NOMINAL name
         (`TCon "T"`) while the dispatch site sees the structural record
         (`TRecord [...]`); they don't unify, so `impl Iface(Record)` is invisible
         to a call in a module checked before the impl's own module — which is
         exactly the cross-module / multi-file case. Variant types are unaffected
         (they are not in [env.records] and stay nominal) — except a variant
         whose bare name collides with a record from another module, which
         [name_is_variant] guards against exactly as [surface_ty] does. *)
      (match StrMap.find_opt n.txt env.records with
       | Some (params, field_decls)
         when List.length params = List.length args'
              && not (name_is_variant env n.txt) ->
         let saved = !tvars in
         List.iter2 (fun pname arg -> tvars := M.add pname arg !tvars) params args';
         let flds = List.map (fun (fn, fty) -> (fn, lenient_ty fty)) field_decls in
         tvars := saved;
         TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) flds)
       | _ -> TCon (n.txt, args'))
    | Ast.TyArrow (a, b)   -> TArrow (lenient_ty a, lenient_ty b)
    | Ast.TyTuple ts       -> TTuple (List.map lenient_ty ts)
    | Ast.TyRecord fs      ->
      TRecord (List.map (fun ((n : Ast.name), ft) -> (n.txt, lenient_ty ft)) fs)
    | Ast.TyLinear (l, t') -> TLin (l, lenient_ty t')
    | Ast.TyNat _ | Ast.TyNatOp _ | Ast.TyChan _ -> fresh_var 1
    | Ast.TyRefine (base, _, _) -> lenient_ty base
  in
  let inst_ty = lenient_ty idef.impl_ty in
  { env with impls =
    (let key = idef.impl_iface.txt in
     let lst = Option.value ~default:[] (StrMap.find_opt key env.impls) in
     StrMap.add key (inst_ty :: lst) env.impls) }

(** Pre-register a forward-reference interface declared in [prefix]: its name
    (qualified `Mod.Iface` AND bare `Iface`) plus each method (qualified and
    bare) with an interface-constrained scheme, so a sibling module's `impl` /
    method call resolves even when that module is checked before the interface's
    own module. Shared by the pre-passes of [check_module_core] and
    [check_module_with_env] so the two cannot diverge — a divergence here (the
    incremental pass omitted interfaces entirely) previously hid sibling
    interfaces from the LSP's per-file analysis ("Unknown interface"). *)
let prebind_interface_decl ~prefix (idef : Ast.interface_def) (e : env) : env =
  let iface_qname = prefix ^ "." ^ idef.iface_name.txt in
  let iface_sname = idef.iface_name.txt in
  let e1 = if StrMap.mem iface_qname e.interfaces then e
           else { e with interfaces = StrMap.add iface_qname idef e.interfaces } in
  let e1 = if StrMap.mem iface_sname e1.interfaces then e1
           else { e1 with interfaces = StrMap.add iface_sname idef e1.interfaces } in
  if StrMap.mem (prefix ^ "." ^ idef.iface_name.txt ^ "." ^
                 (match idef.iface_methods with m :: _ -> m.md_name.txt | [] -> ""))
       e.vars
  then e1  (* already bound — skip to avoid duplicate work *)
  else
  List.fold_left (fun e (m : Ast.method_decl) ->
    let full_qualified = prefix ^ "." ^ idef.iface_name.txt ^ "." ^ m.md_name.txt in
    let iface_qualified = idef.iface_name.txt ^ "." ^ m.md_name.txt in
    if StrMap.mem full_qualified e.vars then e
    else begin
      let tmp_errors = Err.create () in
      let tmp_env = { e with errors = tmp_errors } in
      let a = fresh_var 1 in
      let tvars = ref [(idef.iface_param.txt, a)] in
      let ty = surface_ty tmp_env ~tvars m.md_ty in
      let a_id = match a with
        | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
        | _ -> 0
      in
      let base_sch = generalize 0 ty in
      let sch = match base_sch with
        | Poly (ids, cs, t) -> Poly (ids, CInterface (idef.iface_name.txt, a) :: cs, t)
        | Mono t -> Poly ([a_id], [CInterface (idef.iface_name.txt, a)], t)
      in
      let e1 = { e with vars = StrMap.add full_qualified sch e.vars } in
      let e1 = if StrMap.mem iface_qualified e1.vars then e1
               else { e1 with vars = StrMap.add iface_qualified sch e1.vars } in
      if StrMap.mem m.md_name.txt e1.vars then e1
      else { e1 with vars = StrMap.add m.md_name.txt sch e1.vars }
    end
  ) e1 idef.iface_methods

(** Discharge all pending Num/Ord/CInterface constraints accumulated during
    inference.  Called at each declaration boundary (DFn, DLet) to verify
    that constrained type variables were unified with a compatible type. *)
let discharge_constraints env span =
  (* Dedup CInterface constraints: when the same concrete type is constrained
     on the same interface multiple times (e.g., 10 calls to Storage.get on
     the same storage variable), we only need to check the impl once.
     Uses pp_ty on the repr'd type as a canonical string key. *)
  let seen = Hashtbl.create 16 in
  List.iter (fun c ->
      let dominated = match c with
        | CInterface (name, t) ->
          let rt = repr t in
          (match rt with
           | TVar _ -> false  (* polymorphic -- will be skipped anyway *)
           | _ ->
             let key = name ^ ":" ^ pp_ty rt in
             if Hashtbl.mem seen key then true
             else (Hashtbl.add seen key (); false))
        | _ -> false
      in
      if not dominated then
      match c with
      | CNum t | COrd t ->
        let ty   = repr t in
        let kind = match c with CNum _ -> "Num" | COrd _ -> "Ord" | _ -> assert false in
        (match ty with
         | TCon ("Int",   []) | TCon ("Float", []) -> ()   (* Num + Ord *)
         | TCon ("String",[]) ->
           (match c with
            | COrd _ -> ()   (* String is Ord *)
            | _ ->
              Err.error env.errors ~span
                "String does not implement Num (only Int and Float do).")
         | TVar r ->
           (match c with
            | CNum _ -> r := Link (TCon ("Int", []))  (* numeric defaulting: unresolved Num → Int *)
            | _ -> ())  (* COrd unresolved — leave polymorphic *)
         | _ ->
           Err.error env.errors ~span
             (Printf.sprintf "`%s` does not implement %s." (pp_ty ty) kind))
      | CInterface (iface_name, t) ->
        let ty = repr t in
        (match ty with
         | TVar _ -> ()   (* Still polymorphic — cannot check yet *)
         | _ ->
           let satisfied = match StrMap.find_opt iface_name env.impls with
             | None -> false
             | Some impl_tys -> List.exists (fun impl_ty ->
                 impl_matches_ty (repr impl_ty) ty) impl_tys
           in
           if not satisfied then begin
             (* Record field auto-satisfy: discharge a single-method
                accessor-shaped interface against an anonymous TRecord when
                the record has a field whose name and type match the method.
                Eligibility: anonymous TRecord, exactly one interface method,
                method shape `a -> T` (a = iface param), matching field. *)
             let auto_satisfied =
               match ty with
               | TRecord flds ->
                 (match StrMap.find_opt iface_name env.interfaces with
                  | Some iface when List.length iface.iface_methods = 1 ->
                    let m = List.hd iface.iface_methods in
                    (match m.md_ty with
                     | Ast.TyArrow (Ast.TyVar param, ret_surface)
                       when param.txt = iface.iface_param.txt ->
                       let tvars = ref [(iface.iface_param.txt, ty)] in
                       let ret_ty = surface_ty env ~tvars ret_surface in
                       (match List.assoc_opt m.md_name.txt flds with
                        | Some fld_ty -> impl_matches_ty (repr fld_ty) ret_ty
                        | None -> false)
                     | _ -> false)
                  | _ -> false)
               | _ -> false
             in
             if not auto_satisfied then
               Err.error env.errors ~span
                 (Printf.sprintf
                    "`%s` does not implement interface `%s`.\n\
                     Add `impl %s(%s) do ... end` to provide an implementation."
                    (pp_ty ty) iface_name iface_name (pp_ty ty))
           end)
      | CADTBound (adt_name, t) ->
        let ty = repr t in
        (match ty with
         | TVar _ -> ()  (* still polymorphic — cannot check yet *)
         | TCon (ctor_name, []) ->
           (* Check ctor_name is a constructor whose parent type matches adt_name.
              ci_type may be module-qualified (e.g. "Conn.ConnState"), so we accept
              an exact match OR a ".<adt_name>" suffix match. *)
           let matches_adt ci_type =
             ci_type = adt_name ||
             let n = String.length adt_name in
             let len = String.length ci_type in
             len > n && ci_type.[len - n - 1] = '.' &&
             String.sub ci_type (len - n) n = adt_name
           in
           let found = match StrMap.find_opt ctor_name env.ctors with
             | None -> false
             | Some cis -> List.exists (fun ci -> matches_adt ci.ci_type) cis
           in
           if not found then
             Err.error env.errors ~span
               (Printf.sprintf "`%s` is not a variant of `%s`."
                  ctor_name adt_name)
         | _ ->
           Err.error env.errors ~span
             (Printf.sprintf "Expected a variant of `%s`, got `%s`."
                adt_name (pp_ty ty)))
      | CTNatBound t ->
        let ty = repr t in
        (match ty with
         | TVar _            -> ()  (* still polymorphic *)
         | TNat _            -> ()  (* exact TNat — OK *)
         | TNatOp _          -> ()  (* type-level nat arithmetic — OK *)
         | _ ->
           Err.error env.errors ~span
             (Printf.sprintf "Expected a type-level natural number (Nat), got `%s`."
                (pp_ty ty)))
    ) !(env.pending_constraints);
  env.pending_constraints := []

(** Structural equality after repr — works for concrete types; may give
    false-positive wrong-type hints when two distinct unresolved TVars
    happen not to be linked yet (acceptable in actor handler context). *)
let types_equal a b = repr a = repr b

(** Build hint strings explaining why an actor handler body has the wrong type.
    state_ty and inferred_ty should both be repr-ed before calling. *)
let actor_handler_hints state_ty inferred_ty =
  match inferred_ty with
  | TRecord inferred_fields ->
    (match state_ty with
     | TRecord [] ->
       ["the state has no fields — return an empty record {}"]
     | TRecord state_fields ->
       let state_names    = List.map fst state_fields in
       let inferred_names = List.map fst inferred_fields in
       let extra   = List.filter (fun n -> not (List.mem n state_names)) inferred_names in
       let missing = List.filter (fun n -> not (List.mem n inferred_names)) state_names in
       let wrong_type = List.filter_map (fun (fname, st) ->
           match List.assoc_opt fname inferred_fields with
           | Some it when not (types_equal st it) ->
             Some (Printf.sprintf
               "field '%s' has type %s but state declares it as %s"
               fname (pp_ty (repr it)) (pp_ty (repr st)))
           | _ -> None) state_fields in
       List.map (fun n -> Printf.sprintf
         "field '%s' is not part of the actor state \
          — remove it, or add it to the state declaration" n) extra
       @ List.map (fun n -> Printf.sprintf
         "field '%s' is missing from the returned record" n) missing
       @ wrong_type
     | _ -> [])
  | t ->
    [Printf.sprintf "handler must return a record matching the state, not %s" (pp_ty t)]

(** Validate the island module protocol.

    If a module defines types named [State] and [Msg] and at least one of
    [init], [update], or [render], we treat it as an island module and check
    that the required functions are present:

    - [update(State, Msg) -> State]   — required
    - [render(State) -> IOList]        — required
    - [create(Props) -> State]          — recommended (warning if missing)
    - [merge(State, State) -> State]   — optional, no warning *)
let validate_island_protocol (env : env) (mod_name : Ast.name) (decls : Ast.decl list) =
  (* Inspect the module's OWN declarations, not the accumulated environment:
     inner_env inherits every bare type/fn name exported by previously
     checked sibling modules, so once any island module defined State/Msg,
     every later module with a fn named update/render/create was falsely
     flagged as an incomplete island. *)
  let has_type n =
    List.exists (function
      | Ast.DType (_, tn, _, _, _) | Ast.DAlwaysLinearType (_, tn, _, _, _) -> tn.Ast.txt = n
      | _ -> false) decls
  in
  let has_fn n =
    List.exists (function
      | Ast.DFn (def, _) -> def.fn_name.txt = n
      | _ -> false) decls
  in
  if not (has_type "State" && has_type "Msg") then ()
  else begin
    let has_update = has_fn "update" in
    let has_render = has_fn "render" in
    let has_create = has_fn "create" in
    (* Only validate if at least one protocol function exists — avoids
       false positives on modules that coincidentally have State/Msg types. *)
    if has_update || has_render || has_create then begin
      if not has_update then
        Err.error env.errors ~span:mod_name.span
          (Printf.sprintf
             "Island module `%s` is missing required function `update`.\n  \
              Island modules with State and Msg types must define:\n  \
              \  fn update(state : State, msg : Msg) : State"
             mod_name.txt);
      if not has_render then
        Err.error env.errors ~span:mod_name.span
          (Printf.sprintf
             "Island module `%s` is missing required function `render`.\n  \
              Island modules with State and Msg types must define:\n  \
              \  fn render(state : State) : IOList"
             mod_name.txt);
      if not has_create then
        Err.warning env.errors ~span:mod_name.span
          (Printf.sprintf
             "Island module `%s` does not define `create`.\n  \
              Consider adding: fn create(props : Props) : State"
             mod_name.txt)
    end
  end

(** Walk an expression and collect all direct function call names.
    Returns [(fn_name, span)] for every EApp where the callee is a bare
    variable or a qualified module-path field access.  Used by the
    body-scanning pass to detect builtin capability uses. *)
let rec calls_in_expr (acc : (string * Ast.span) list) (e : Ast.expr)
    : (string * Ast.span) list =
  match e with
  | Ast.EApp (Ast.EVar fn_name, args, _) ->
    let acc = (fn_name.txt, fn_name.span) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (Ast.EField (Ast.EVar mod_name, fn_name, _), args, _) ->
    let qname = mod_name.txt ^ "." ^ fn_name.txt in
    let acc = (qname, fn_name.span) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (f, args, _) ->
    List.fold_left calls_in_expr (calls_in_expr acc f) args
  | Ast.EBlock (es, _) ->
    List.fold_left calls_in_expr acc es
  | Ast.ELet (b, _) ->
    calls_in_expr acc b.Ast.bind_expr
  | Ast.EMatch (scrut, arms, _) ->
    let acc = calls_in_expr acc scrut in
    List.fold_left (fun a arm ->
      let a = Option.fold ~none:a ~some:(calls_in_expr a) arm.Ast.branch_guard in
      calls_in_expr a arm.Ast.branch_body) acc arms
  | Ast.EIf (cond, then_, else_, _) ->
    calls_in_expr (calls_in_expr (calls_in_expr acc cond) then_) else_
  | Ast.EField (inner, _, _) -> calls_in_expr acc inner
  | Ast.EPipe (a, b, _) -> calls_in_expr (calls_in_expr acc a) b
  | Ast.ELetFn (_, _, _, body, _) -> calls_in_expr acc body
  | Ast.ELetQ (_, rhs, body, _) ->
    calls_in_expr (calls_in_expr acc rhs) body
  | Ast.ELit _ | Ast.EVar _ -> acc
  | _ -> acc

(** True if [fn_name] ends in the bare "_migrate_state" suffix, regardless of
    which actor it belongs to — the hot-reload state-migration naming
    convention (Phase5C-C.5). This is a local copy of
    [March_tir.Tir_names.is_migrate_fn_name]: [march_typecheck] cannot depend
    on [march_tir] ([march_tir]'s dune already depends on
    [march_typecheck]), so the bare-suffix predicate this module's
    migrate_state IO-free check needs (see below) is duplicated here rather
    than shared. Keep byte-identical to [Tir_names.is_migrate_fn_name] if
    either changes. *)
let is_migrate_fn_name (fn_name : string) : bool =
  let sfx = "_migrate_state" in
  let nl = String.length fn_name and sl = String.length sfx in
  nl >= sl && String.sub fn_name (nl - sl) sl = sfx

(** [check_module_needs env mod_name decls] validates capability declarations for a module:
    1. Every Cap(X) in any function signature must be covered by a [needs] declaration.
    2. Every [needs X] must be used by at least one function.
    3. Hint when Cap(IO) (root) is used — narrower caps may be more appropriate.

    [cap_qname_prefix] is the fully-accumulated dotted path (from
    [env.cap_qual_prefix] extended by [mod_name.txt], or [mod_name.txt] alone
    at the entry module) used ONLY to key [env.cap_closures] so it matches
    TIR's fully-qualified function-name convention (see [lib/tir/lower.ml]'s
    [mod_prefix]). [mod_name] itself continues to be used for all
    diagnostics/messages and the [proof_caps] self-declaration check below,
    unchanged. *)
let check_module_needs (env : env) (mod_name : Ast.name)
    ~(cap_qname_prefix : string) (decls : Ast.decl list) =
  (* [cap_qname_prefix] carries no trailing dot (e.g. "", "Lib", "Lib.Sub").
     Build the fully-qualified cap-closure key for a function/extern name,
     omitting the leading dot when the prefix is empty (top-level function of
     the entry module) — matching TIR's [mod_prefix ^ name] convention where
     [mod_prefix] is "" at the entry level. *)
  let cap_qname (leaf_name : string) : string =
    if cap_qname_prefix = "" then leaf_name
    else cap_qname_prefix ^ "." ^ leaf_name
  in
  let declared_needs = List.concat_map (function
    | Ast.DNeeds (caps, _) -> List.map cap_path_of_names caps
    | _ -> []
  ) decls in
  (* Per-function inferred IO-capability closure (Phase5C-A.2): attributes the
     same cap data the checks below already compute to the owning function and
     records it into [env.cap_closures] for a later hot-deploy
     capability-manifest task. Purely additive bookkeeping — does not affect
     any Check 1/1b/1c/2/3/4/5/6 validation logic or diagnostics below.
     [record_fn_caps] is called as a side effect from within [used_caps],
     [body_cap_uses], and [extern_cap_uses] below (each of which already
     iterates [decls] and already computes sig/body/extern caps per-DFn or
     per-DExtern) rather than via a separate re-traversal, so no function body
     or signature is walked twice. Merge order across the three call sites
     doesn't matter: [record_fn_caps] always merges with whatever is already
     in [env.cap_closures] for that qualified name. *)
  let module_wide_caps : string list =
    (* Caps that apply to every function in this module regardless of which
       function's own signature/body/extern-block produced them: declared
       [needs] (in-scope for the whole module body) and caps propagated in
       from imported modules (Check 4). *)
    let propagated = List.concat_map (function
      | Ast.DUse (ud, _) ->
        let imported = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
        (match List.assoc_opt imported env.module_caps with
         | None -> [] | Some req_caps -> req_caps)
      | _ -> []
    ) decls in
    declared_needs @ propagated
  in
  let record_fn_caps (fn_qname : string) (own_caps : string list) =
    let prior = Option.value ~default:[] (Hashtbl.find_opt env.cap_closures fn_qname) in
    let merged = March_caps.Cap_lattice.normalize (module_wide_caps @ own_caps @ prior) in
    Hashtbl.replace env.cap_closures fn_qname merged;
    (* Parallel own-caps-only projection (Phase5C-C.5 design correction): same
       accumulate-across-call-sites behavior as [cap_closures] above, but
       WITHOUT folding in [module_wide_caps]. This is what the migrate_state
       IO-free check needs — the merged closure would falsely blame a pure
       migrate_state for its module's handler-level [needs]. *)
    let prior_own = Option.value ~default:[] (Hashtbl.find_opt env.own_cap_closures fn_qname) in
    let merged_own = March_caps.Cap_lattice.normalize (own_caps @ prior_own) in
    Hashtbl.replace env.own_cap_closures fn_qname merged_own
  in
  let used_caps : (string * Ast.span) list = List.concat_map (function
    | Ast.DFn (def, sp) ->
      let param_tys = List.filter_map (fun p ->
        match p with
        | Ast.FPNamed { param_ty = Some t; _ } -> Some t
        | _ -> None
      ) (List.concat_map (fun c -> c.Ast.fc_params) def.fn_clauses) in
      let ret_tys = Option.to_list def.fn_ret_ty in
      let sig_caps = List.concat_map cap_paths_in_surface_ty (param_tys @ ret_tys) in
      let qname = cap_qname def.fn_name.txt in
      record_fn_caps qname sig_caps;
      List.map (fun cap -> (cap, sp)) sig_caps
    (* H9 gap fix: also check actor handler signatures for Cap usage.
       Actor handlers can receive Cap(X) values as message arguments; those
       must also be covered by module-level [needs] declarations. *)
    | Ast.DActor (_, name, actor, sp) ->
      (* C1 fix: also record each handler's own per-function cap closure,
         keyed EXACTLY the way TIR names the synthesized handler function
         (see lib/tir/lower.ml's [lower_handler]: [fn_name = name ^ "_" ^
         h.ah_msg.txt], where [name] there is the actor's OWN BARE name —
         never module-prefixed, confirmed empirically: a handler on actor
         [Weeble] nested inside [App.Sub] still lowers to bare
         [Weeble_Zorp], NOT [Sub.Weeble_Zorp], even though sibling [DFn]s in
         the same nested module DO get the "Sub." prefix). So the handler's
         qualified name must use the actor's bare [name.txt] directly — NOT
         [cap_qname name.txt] — while the signature-cap diagnostics above
         and the body-scanned caps below still merge in [module_wide_caps]
         via [record_fn_caps] the same way [DFn] does. *)
      List.iter (fun (h : Ast.actor_handler) ->
          let fn_qname = name.txt ^ "_" ^ h.ah_msg.txt in
          let body_caps = List.filter_map (fun (call_name, _) ->
              List.assoc_opt call_name builtin_cap_table
            ) (calls_in_expr [] h.Ast.ah_body) in
          record_fn_caps fn_qname body_caps
        ) actor.actor_handlers;
      List.concat_map (fun (h : Ast.actor_handler) ->
          let param_tys = List.filter_map (fun (p : Ast.param) -> p.param_ty) h.ah_params in
          List.concat_map (fun t ->
            List.map (fun cap -> (cap, sp)) (cap_paths_in_surface_ty t)
          ) param_tys
        ) actor.actor_handlers
    (* An extern block declares `extern "lib" : Cap(X)` — that Cap(X) is a use
       of the capability, so a module with `needs X` + an extern block must not
       trigger the "declared but not used" warning. *)
    | Ast.DExtern (edef, sp) ->
      List.map (fun cap -> (cap, sp)) (cap_paths_in_surface_ty edef.ext_cap_ty)
    | _ -> []
  ) decls in
  (* Body-scan: collect builtin calls that imply a cap need.
     Deduplicated to one warning per cap (first call-site span). *)
  let body_cap_uses : (string * Ast.span) list =
    let all = List.concat_map (function
      | Ast.DFn (def, _) ->
        let per_clause = List.map (fun clause ->
          List.filter_map (fun (call_name, call_span) ->
            match List.assoc_opt call_name builtin_cap_table with
            | Some cap_name -> Some (cap_name, call_span)
            | None -> None
          ) (calls_in_expr [] clause.Ast.fc_body)
        ) def.fn_clauses in
        let qname = cap_qname def.fn_name.txt in
        record_fn_caps qname (List.concat_map (List.map fst) per_clause);
        List.concat per_clause
      | Ast.DLet (_vis, b, _) ->
        List.filter_map (fun (call_name, call_span) ->
          match List.assoc_opt call_name builtin_cap_table with
          | Some cap_name -> Some (cap_name, call_span)
          | None -> None
        ) (calls_in_expr [] b.Ast.bind_expr)
      (* C1 fix (part 2): fold actor handler bodies into the SAME body-scan
         this branch already performs for DFn/DLet, rather than a second/
         parallel AST walk — a handler doing undeclared IO must trip the
         same "capability not declared in needs" diagnostic (Check 1b,
         below) that a plain function body would. Cap-closure recording for
         handlers already happened above in [used_caps]'s DActor branch (so
         it isn't duplicated here); this only needs to surface the
         (cap, span) pairs for the Check 1b/Check 2 diagnostics. *)
      | Ast.DActor (_, _, actor, _) ->
        List.concat_map (fun (h : Ast.actor_handler) ->
            List.filter_map (fun (call_name, call_span) ->
              match List.assoc_opt call_name builtin_cap_table with
              | Some cap_name -> Some (cap_name, call_span)
              | None -> None
            ) (calls_in_expr [] h.Ast.ah_body)
          ) actor.actor_handlers
      | _ -> []
    ) decls in
    List.fold_left (fun acc (cap_name, sp) ->
      if List.mem_assoc cap_name acc then acc else (cap_name, sp) :: acc
    ) [] all
  in
  (* Extern-implied caps: any DExtern → needs IO.Foreign; any blocking extern fn → needs IO.Foreign.Blocking *)
  let extern_cap_uses : (string * Ast.span) list =
    List.concat_map (function
      | Ast.DExtern (edef, sp) ->
        let base = [("IO.Foreign", sp)] in
        let has_blocking = List.exists (fun ef -> ef.Ast.ef_blocking) edef.ext_fns in
        List.iter (fun (ef : Ast.extern_fn) ->
            let qname = cap_qname ef.ef_name.txt in
            let own = if ef.Ast.ef_blocking then ["IO.Foreign"; "IO.Foreign.Blocking"] else ["IO.Foreign"] in
            record_fn_caps qname own
          ) edef.ext_fns;
        if has_blocking then base @ [("IO.Foreign.Blocking", sp)] else base
      | _ -> []
    ) decls
    |> List.fold_left (fun acc (cap_name, sp) ->
      if List.mem_assoc cap_name acc then acc else (cap_name, sp) :: acc
    ) []
  in
  let cap s = MPCode ("Cap(" ^ s ^ ")") in
  (* Check 1: every Cap(X) must be covered by a declared need.
     Exception: the declaring module of a proof cap implicitly satisfies its own needs —
     `proof cap X` in mod M auto-covers `needs M.X` so the module needn't repeat itself. *)
  List.iter (fun (cap_path, sp) ->
    let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
    let self_declared = match List.assoc_opt cap_path env.proof_caps with
      | Some dm -> dm = mod_name.txt
      | None -> false
    in
    if not covered && not self_declared then begin
      match List.assoc_opt cap_path env.proof_caps with
      | Some declaring_mod ->
        Err.error env.errors ~span:sp
          (render_parts [
            cap cap_path; MPText " is a proof capability declared in module ";
            MPCode declaring_mod; MPText ".";
            MPBreak; MPText "Add "; MPCode ("needs " ^ cap_path);
            MPText " to module "; MPCode mod_name.txt; MPText " to acknowledge this dependency.";
            MPBreak; MPText "Only public functions of "; MPCode declaring_mod;
            MPText " can mint "; cap cap_path; MPText " — callers must receive it as a parameter." ])
      | None ->
        Err.error env.errors ~span:sp
          (render_parts [
            cap cap_path; MPText " used in module "; MPCode mod_name.txt;
            MPText " but "; MPCode cap_path; MPText " is not declared in ";
            MPCode "needs"; MPText ".";
            MPBreak; MPText "help: add "; MPCode ("needs " ^ cap_path);
            MPText " to the module body." ])
    end
  ) used_caps;
  (* Check 1b: body-scanned builtin calls that imply an undeclared cap — warning only *)
  List.iter (fun (cap_path, sp) ->
    let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
    let self_declared = match List.assoc_opt cap_path env.proof_caps with
      | Some dm -> dm = mod_name.txt
      | None -> false
    in
    if not covered && not self_declared then
      Err.warning_with_fix env.errors ~span:sp
        ~fix:(Err.FInsert {
          after_line = mod_name.March_ast.Ast.span.March_ast.Ast.start_line;
          text = "  needs " ^ cap_path })
        (render_parts [
          MPText "function body calls a builtin that requires "; cap cap_path;
          MPText " but "; MPCode mod_name.txt; MPText " does not declare ";
          MPCode ("needs " ^ cap_path); MPText ".";
          MPBreak; MPText "hint: add "; MPCode ("needs " ^ cap_path);
          MPText " to the module body." ])
  ) body_cap_uses;
  (* Check 1c: extern blocks imply IO.Foreign (and IO.Foreign.Blocking for blocking fns) — warning only *)
  List.iter (fun (cap_path, sp) ->
    let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
    if not covered then
      Err.warning_with_fix env.errors ~span:sp
        ~fix:(Err.FInsert {
          after_line = mod_name.March_ast.Ast.span.March_ast.Ast.start_line;
          text = "  needs " ^ cap_path })
        (render_parts [
          MPText "extern block in "; MPCode mod_name.txt;
          MPText " requires "; cap cap_path;
          MPText " but "; MPCode mod_name.txt; MPText " does not declare ";
          MPCode ("needs " ^ cap_path); MPText ".";
          MPBreak; MPText "hint: add "; MPCode ("needs " ^ cap_path);
          MPText " to the module body." ])
  ) extern_cap_uses;
  (* Check 2: every needs declaration must be used *)
  List.iter (fun need ->
    let need_sp =
      let rec find_span = function
        | [] -> mod_name.span
        | Ast.DNeeds (caps, s) :: _
          when List.exists (fun names -> cap_path_of_names names = need) caps -> s
        | _ :: rest -> find_span rest
      in
      find_span decls
    in
    let used = List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) used_caps
              || List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) body_cap_uses
              || List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) extern_cap_uses
              || List.exists (fun (_, req_caps) ->
                   List.exists (fun req_cap -> cap_subsumes need req_cap) req_caps
                 ) env.module_caps in
    if not used then
      Err.warning_with_fix env.errors ~span:need_sp
        ~fix:(Err.FDelete {
          start_line = need_sp.March_ast.Ast.start_line;
          end_line   = need_sp.March_ast.Ast.end_line })
        (render_parts [
          MPText "module "; MPCode mod_name.txt; MPText " declares ";
          MPCode ("needs " ^ need); MPText " but no function requires ";
          cap need; MPText " or a sub-capability.";
          MPBreak; MPText "help: remove the unused capability declaration." ])
  ) declared_needs;
  (* Check 3 (hint): Cap(IO) root — suggest narrowing *)
  List.iter (fun (cap_path, sp) ->
    if cap_path = "IO" then
      Err.hint env.errors ~span:sp
        (render_parts [
          MPText "this function takes "; cap "IO";
          MPText " (the root capability); consider narrowing to e.g. ";
          cap "IO.FileRead"; MPText " or "; cap "IO.Console";
          MPText " for least-privilege." ])
  ) used_caps;
  (* Check 4: transitive — every module we `use` that declares `needs` must be covered *)
  List.iter (function
    | Ast.DUse (ud, sp) ->
      let imported = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
      (match List.assoc_opt imported env.module_caps with
       | None | Some [] -> ()
       | Some req_caps ->
         List.iter (fun req_cap ->
           let covered =
             List.exists (fun need -> cap_subsumes need req_cap) declared_needs
           in
           if not covered then
             Err.error env.errors ~span:sp
               (render_parts [
                 MPText "module "; MPCode mod_name.txt; MPText " imports ";
                 MPCode imported; MPText " which requires "; cap req_cap;
                 MPText ", but "; MPCode req_cap; MPText " is not declared in ";
                 MPCode "needs"; MPText ".";
                 MPBreak; MPText "help: add "; MPCode ("needs " ^ req_cap);
                 MPText " to the module body." ])
         ) req_caps)
    | _ -> ()
  ) decls;
  (* Check 5: extern blocks require the declared capability to be in `needs` *)
  List.iter (function
    | Ast.DExtern (edef, sp) ->
      let cap_paths = cap_paths_in_surface_ty edef.ext_cap_ty in
      List.iter (fun cap_path ->
        let covered =
          List.exists (fun need -> cap_subsumes need cap_path) declared_needs
        in
        if not covered then
          Err.error env.errors ~span:sp
            (render_parts [
              MPText "extern block "; MPCode ("\"" ^ edef.ext_lib_name ^ "\"");
              MPText " uses "; cap cap_path;
              MPText ", but "; MPCode cap_path; MPText " is not declared in ";
              MPCode "needs"; MPText ".";
              MPBreak; MPText "help: add "; MPCode ("needs " ^ cap_path);
              MPText " to the module body." ])
      ) cap_paths
    | _ -> ()
  ) decls;
  (* Check 6: proof cap production enforcement.
     A function cannot return a proof cap unless it received it as a parameter, EXCEPT
     for public (`fn`) functions in the declaring module — those are the minting surface.
     Private (`pfn`) functions in the declaring module face the same restriction as external
     modules: they may pass a cap through but cannot produce one from nothing. *)
  List.iter (function
    | Ast.DFn (def, sp) ->
      let param_caps : string list =
        List.concat_map (fun c ->
          List.concat_map (fun p ->
            match p with
            | Ast.FPNamed { param_ty = Some t; _ } -> cap_paths_in_surface_ty t
            | _ -> []
          ) c.Ast.fc_params
        ) def.fn_clauses
      in
      let ret_tys = Option.to_list def.fn_ret_ty in
      List.iter (fun ret_ty ->
        List.iter (fun cap_path ->
          match List.assoc_opt cap_path env.proof_caps with
          | Some declaring_mod
            when (declaring_mod <> mod_name.txt
                  || def.fn_vis = Ast.Private)
              && not (List.mem cap_path param_caps) ->
            if declaring_mod = mod_name.txt then
              Err.error env.errors ~span:sp
                (render_parts [
                  MPText "private function "; MPCode def.fn_name.txt;
                  MPText " in "; MPCode declaring_mod;
                  MPText " cannot mint "; cap cap_path; MPText ".";
                  MPBreak; MPText "Only public functions of "; MPCode declaring_mod;
                  MPText " can construct "; cap cap_path; MPText ".";
                  MPBreak; MPText "hint: make this function public, or accept ";
                  cap cap_path; MPText " as a parameter and pass it through." ])
            else
              Err.error env.errors ~span:sp
                (render_parts [
                  MPText "function "; MPCode def.fn_name.txt;
                  MPText " returns "; cap cap_path;
                  MPText " but "; cap cap_path; MPText " is a proof capability declared in ";
                  MPCode declaring_mod; MPText ".";
                  MPBreak; MPText "Only public functions of "; MPCode declaring_mod;
                  MPText " can construct "; cap cap_path; MPText ".";
                  MPBreak; MPText "hint: accept "; cap cap_path;
                  MPText " as a parameter and pass it through, or call a factory in ";
                  MPCode declaring_mod; MPText "." ])
          | _ -> ()
        ) (cap_paths_in_surface_ty ret_ty)
      ) ret_tys
    | _ -> ()
  ) decls;
  (* Check 7 — realtime exclusion.
     A function with `Tagged(_, Realtime)` cannot also take `Cap(Alloc)`,
     `Cap(IO)`, or `Cap(Panic)` as parameters — those capabilities are excluded
     from realtime contexts by the narrowing rule in §3/§5. *)
  let is_realtime_tagged = function
    | Ast.TyCon ({txt="Tagged";_}, [_; Ast.TyCon ({txt="Realtime";_}, [])]) -> true
    | _ -> false
  in
  let is_excluded_cap = function
    | Ast.TyCon ({txt="Cap";_}, [Ast.TyCon ({txt=("Alloc"|"IO"|"Panic");_}, [])]) -> true
    | _ -> false
  in
  List.iter (function
    | Ast.DFn (def, sp) ->
      let all_param_tys = List.concat_map (fun c ->
        List.filter_map (fun p ->
          match p with
          | Ast.FPNamed { param_ty = Some t; _ } -> Some t
          | _ -> None
        ) c.Ast.fc_params
      ) def.fn_clauses in
      let has_realtime = List.exists is_realtime_tagged all_param_tys in
      if has_realtime then
        List.iter (fun t ->
          if is_excluded_cap t then begin
            let cap_name = match t with
              | Ast.TyCon (_, [Ast.TyCon ({txt;_}, [])]) -> txt
              | _ -> "?" in
            Err.error env.errors ~span:sp
              (render_parts [
                MPText "function "; MPCode def.fn_name.txt;
                MPText " takes "; MPCode "Tagged(_, Realtime)";
                MPText " but also takes "; MPCode ("Cap(" ^ cap_name ^ ")");
                MPText ".";
                MPBreak; MPText "Realtime functions cannot hold ";
                MPCode ("Cap(" ^ cap_name ^ ")");
                MPText " — allocation, IO, and panic are excluded from realtime contexts.";
                MPBreak; MPText "hint: remove "; MPCode ("Cap(" ^ cap_name ^ ")")
              ])
          end
        ) all_param_tys
    | _ -> ()
  ) decls;
  (* Check 8 - migrate_state must be IO-free, Phase5C-C.5.
     State-migration functions, the actor_lower plus _migrate_state naming
     convention, see is_migrate_fn_name, run during the hot-migration window,
     ahead of any pending user messages; doing IO there is dangerous. Use the
     own-caps projection, env.own_cap_closures / fn_own_capability_closures,
     NOT the merged cap_closures: the merged closure folds in the module
     declared needs, typically present for the module handlers, which
     would falsely flag a migrate_state whose own body or signature touches
     no capability at all. *)
  let check_migrate_fn_io_free (qname : string) (sp : Ast.span) =
    let own_caps =
      Option.value ~default:[] (Hashtbl.find_opt env.own_cap_closures qname)
    in
    if own_caps <> [] then
      Err.error env.errors ~span:sp
        (render_parts [
          MPText "migrate_state must be IO-free"; MPBreak;
          MPCode qname; MPText " calls capabilities that need ";
          MPCode (String.concat ", " own_caps); MPText ".";
          MPBreak; MPText "migrate_state runs during the hot-migration window, before user messages.";
          MPBreak; MPText "hint: move side effects into a normal handler that runs after migration completes." ])
  in
  List.iter (function
    | Ast.DFn (def, sp) when is_migrate_fn_name def.fn_name.txt ->
      check_migrate_fn_io_free (cap_qname def.fn_name.txt) sp
    (* An extern-declared fn following the migrate_state naming convention is
       equally recognized: its own caps were recorded under [ef_name.txt] by
       the extern-implied-caps pass above (any extern block is IO.Foreign,
       [blocking] adds IO.Foreign.Blocking), and that alone must fail the
       IO-free bound just like a body-scanned builtin call would for a DFn. *)
    | Ast.DExtern (edef, sp) ->
      List.iter (fun (ef : Ast.extern_fn) ->
        if is_migrate_fn_name ef.Ast.ef_name.txt then
          check_migrate_fn_io_free (cap_qname ef.Ast.ef_name.txt) sp
      ) edef.ext_fns
    | _ -> ()
  ) decls

(** Post-checking sweep (Part 2): enforce the [mint_cap] gate for every recorded
    site, now that its result type is pinned by later unification.  [mint_cap(x)]
    typechecks iff its pinned result is [Cap(P)] with [P] a proof cap whose
    declaring module equals the site's enclosing module AND the site's enclosing
    fn is public.  A proof cap from another module or a mint in a private/non-
    declaring fn is rejected (unforgeability); a non-proof (IO) target is
    rejected too — attenuating IO caps is [cap_narrow]'s job.  The enclosing
    fn/module context was captured at record time (unavailable now). *)
let check_mint_cap_sites (env : env) : unit =
  List.iter (fun (sp, rty, cur_fn_public, current_module) ->
      match repr rty with
      | TCon ("Cap", [inner]) ->
        (match repr inner with
         | TCon (p, []) ->
           (match List.assoc_opt p env.proof_caps with
            | Some declaring_mod ->
              if not (declaring_mod = current_module && cur_fn_public) then
                Err.error env.errors ~span:sp
                  (render_parts [
                    MPText "mint_cap "; MPCode ("Cap(" ^ p ^ ")");
                    MPText " is only allowed inside a public function of its declaring module ";
                    MPCode declaring_mod; MPText ".";
                    MPBreak;
                    MPText "hint: to obtain "; MPCode ("Cap(" ^ p ^ ")");
                    MPText " elsewhere, receive it as a parameter and pass it through, or call a public factory in ";
                    MPCode declaring_mod; MPText "." ])
            | None ->
              (* mint_cap used to produce a non-proof (IO) cap — disallow; that's
                 cap_narrow's job. *)
              Err.error env.errors ~span:sp
                (render_parts [
                  MPText "mint_cap is only for proof capabilities; use ";
                  MPCode "cap_narrow"; MPText " to attenuate IO capabilities." ]))
         | _ ->
           (* Result is not a concrete cap constructor — an unbound (generalized)
              cap var that never got pinned to a specific proof cap.  This
              happens when the mint is inside a [let]-bound lambda that gets
              generalized to [forall a. _ -> Cap(a)]: such a value is a
              polymorphic cap producer that could mint ANY cap (a forge vector),
              so it is rejected regardless of the enclosing fn.  A mint whose
              target proof cap is fixed at the call site (direct mint, or an
              immediately-applied / type-annotated lambda) pins the result and
              is checked against the declaring-module + public gate above. *)
           Err.error env.errors ~span:sp
             (render_parts [
               MPText "mint_cap here does not have a determinable proof-capability result type.";
               MPBreak;
               MPText "hint: mint_cap must produce a specific ";
               MPCode "Cap(Mod.Name)";
               MPText " fixed at the call site. A mint captured in a generalized (let-bound) lambda is polymorphic in the capability and is rejected — mint directly, or fix the capability type (e.g. annotate the return or apply the lambda in place)." ]))
      | _ -> ()
    ) !(env.mint_cap_sites)

(** [fn_capability_closures env] returns the per-function inferred IO-capability
    closure recorded by [check_module_needs] for every function checked so far
    in [env]'s lineage: [(fully_qualified_fn_name, normalized_cap_paths)] pairs,
    one per function ("Mod.fn" for [DFn]/actor-owning modules, "Mod.extern_fn"
    for FFI functions declared in an [extern] block). The list combines each
    function's own inferred requirements (Cap-typed signature, body-scanned
    builtin calls, extern-implied [IO.Foreign]/[IO.Foreign.Blocking]) with the
    caps that apply to every function in its module (declared [needs] and
    caps propagated in from imported modules per Check 4), normalized via
    [March_caps.Cap_lattice.normalize]. Order is unspecified (backed by a hashtable).
    Consumed by the (future) hot-deploy capability manifest. *)
let fn_capability_closures (env : env) : (string * string list) list =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) env.cap_closures []

(** [fn_own_capability_closures env] returns each function's OWN inferred
    IO-capability closure — [(fully_qualified_fn_name, normalized_cap_paths)]
    pairs — WITHOUT the module-wide [needs]/import-propagated merge that
    [fn_capability_closures] performs. Use this projection, not the merged
    one, for any "is this one function IO-free" question (e.g. the
    migrate_state check): the merged closure attributes a module's
    handler-level [needs] to every function in the module, including a pure
    migrate_state, which would falsely fail such a check. Order is
    unspecified (backed by a hashtable). *)
let fn_own_capability_closures (env : env) : (string * string list) list =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) env.own_cap_closures []

(* =================================================================
   §16a  Session type projection and duality
   ================================================================= *)

(** [project_steps env ~proto_name ~multiparty steps role cont] projects a
    list of protocol steps onto [role], appending [cont] as the continuation.
    When [multiparty] is true (N>2 roles), produces [SMSend]/[SMRecv] with
    explicit role annotations; otherwise produces [SSend]/[SRecv]. *)
let rec project_steps env ~proto_name ~multiparty steps role cont =
  match steps with
  | [] -> cont
  | step :: rest ->
    let rest_ty () = project_steps env ~proto_name ~multiparty rest role cont in
    (match step with
     | Ast.ProtoMsg (sender, receiver, msg_ty) ->
       let tvars = ref [] in
       let t = surface_ty env ~tvars msg_ty in
       if sender.Ast.txt = role then
         (if multiparty then SMSend (receiver.Ast.txt, t, rest_ty ())
          else SSend (t, rest_ty ()))
       else if receiver.Ast.txt = role then
         (if multiparty then SMRecv (sender.Ast.txt, t, rest_ty ())
          else SRecv (t, rest_ty ()))
       else
         rest_ty ()   (* This role doesn't participate in this step *)
     | Ast.ProtoLoop inner_steps ->
       (* Wrap the inner projection in a recursive binder *)
       let rec_var = proto_name ^ "_loop" in
       let inner = project_steps env ~proto_name ~multiparty inner_steps role (SVar rec_var) in
       let after_loop = rest_ty () in
       (match inner with
        | SVar _ ->
          (* Role not involved in the loop at all — skip *)
          after_loop
        | _ ->
          (* Substitute the continuation into the SVar back-reference *)
          let inner_with_cont = subst_svar rec_var after_loop inner in
          SRec (rec_var, inner_with_cont))
     | Ast.ProtoChoice (chooser, branches) ->
       let branch_tys = List.map (fun (lbl, arm_steps) ->
           let arm_ty = project_steps env ~proto_name ~multiparty arm_steps role cont in
           (lbl.Ast.txt, arm_ty)
         ) branches in
       if chooser.Ast.txt = role then
         SChoose branch_tys
       else begin
         (* Mergeability: if all branches project to the same local type for
            this role, merge them into that type (the role need not observe
            the choice at all).  This is the standard MPST merge rule, and it
            only applies to MULTIPARTY protocols (>2 roles), where a bystander
            role genuinely does not observe a choice made between two OTHER
            roles.  In a BINARY (2-role) protocol the non-chooser is the
            chooser's only peer — the offerer — who MUST always observe the
            choice (it runs [Chan.offer]); so we never merge there, even when
            the branches happen to carry identical payload types. *)
         match branch_tys with
         | [] -> SOffer branch_tys
         | (_, first_ty) :: rest ->
           if multiparty && List.for_all (fun (_, ty) -> session_ty_exact_equal ty first_ty) rest then
             first_ty   (* role not involved — merged/transparent *)
           else
             SOffer branch_tys
       end)

(** Substitute occurrences of [SVar x] with [replacement] inside [s]. *)
and subst_svar x replacement s =
  match s with
  | SVar y when y = x -> replacement
  | SSend (t, s')  -> SSend (t, subst_svar x replacement s')
  | SRecv (t, s')  -> SRecv (t, subst_svar x replacement s')
  | SChoose bs     -> SChoose (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
  | SOffer bs      -> SOffer  (List.map (fun (l, s') -> (l, subst_svar x replacement s')) bs)
  | SMSend (r, t, s') -> SMSend (r, t, subst_svar x replacement s')
  | SMRecv (r, t, s') -> SMRecv (r, t, subst_svar x replacement s')
  | SRec (y, s') when y <> x -> SRec (y, subst_svar x replacement s')
  | other -> other

(** Compute the dual of a local session type (what the other endpoint must have).
    Only meaningful for binary protocols; MPST types use SMSend/SMRecv directly. *)
let rec dual_session_ty = function
  | SSend (t, s)  -> SRecv (t, dual_session_ty s)
  | SRecv (t, s)  -> SSend (t, dual_session_ty s)
  | SChoose bs    -> SOffer  (List.map (fun (l, s) -> (l, dual_session_ty s)) bs)
  | SOffer  bs    -> SChoose (List.map (fun (l, s) -> (l, dual_session_ty s)) bs)
  | SEnd          -> SEnd
  | SRec (x, s)   -> SRec (x, dual_session_ty s)
  | SVar x        -> SVar x
  | SError        -> SError
  | SMSend (r, t, s) -> SMSend (r, t, dual_session_ty s)
  | SMRecv (r, t, s) -> SMRecv (r, t, dual_session_ty s)

(** Project a global protocol onto all participating roles.
    Returns [(role, local_ty) list].
    - Binary (2 roles): verifies duality of the two projections.
    - Multiparty (N>2 roles): verifies pairwise send/recv consistency using
      role-annotated SMSend/SMRecv constructors. *)
let project_protocol env ~span ~proto_name (pdef : Ast.protocol_def) =
  (* Collect all roles *)
  let rec roles_of_steps = function
    | [] -> []
    | Ast.ProtoMsg (s, r, _) :: rest ->
      s.Ast.txt :: r.Ast.txt :: roles_of_steps rest
    | Ast.ProtoLoop steps :: rest ->
      roles_of_steps steps @ roles_of_steps rest
    | Ast.ProtoChoice (chooser, branches) :: rest ->
      chooser.Ast.txt ::
      List.concat_map (fun (_, steps) -> roles_of_steps steps) branches @
      roles_of_steps rest
  in
  let roles = List.sort_uniq String.compare (roles_of_steps pdef.proto_steps) in
  let multiparty = List.length roles > 2 in
  (* Project each role *)
  let projections = List.map (fun role ->
      let ty = project_steps env ~proto_name ~multiparty pdef.proto_steps role SEnd in
      (role, ty)
    ) roles in
  (match roles with
   | [a; b] ->
     (* Binary protocol: verify duality *)
     let proj_a = List.assoc a projections in
     let proj_b = List.assoc b projections in
     let dual_a = dual_session_ty proj_a in
     if not (session_ty_equal dual_a proj_b) then
       Err.error env.errors ~span
         (Printf.sprintf
            "Protocol `%s`: the projection onto `%s` and the projection onto \
             `%s` are not duals of each other.\n\
             dual(%s) = %s\nbut %s has: %s"
            proto_name a b
            a (pp_session_ty dual_a)
            b (pp_session_ty proj_b))
   | _ when multiparty ->
     (* Multiparty protocol: verify that every SMSend in role A to role B
        corresponds to an SMRecv in role B from role A with the same type.
        We check this by collecting all (sender, receiver, msg_ty) triples
        from the global steps and comparing against the projections. *)
     let rec gather_msgs acc = function
       | [] -> acc
       | Ast.ProtoMsg (s, r, t) :: rest ->
         let tvars = ref [] in
         let ty = surface_ty env ~tvars t in
         gather_msgs ((s.Ast.txt, r.Ast.txt, ty) :: acc) rest
       | Ast.ProtoLoop inner :: rest ->
         gather_msgs (gather_msgs acc inner) rest
       | Ast.ProtoChoice (_, branches) :: rest ->
         let branch_msgs = List.concat_map (fun (_, steps) ->
             gather_msgs [] steps) branches in
         gather_msgs (branch_msgs @ acc) rest
     in
     let msgs = gather_msgs [] pdef.proto_steps in
     List.iter (fun (sender, receiver, msg_ty) ->
         (* Check sender has SMSend(receiver, msg_ty, ...) somewhere *)
         let rec has_msend s =
           match unfold_srec s with
           | SMSend (r, t, cont) ->
             (r = receiver && session_ty_equal (SSend (t, SEnd)) (SSend (msg_ty, SEnd)))
             || has_msend cont
           | SMRecv (_, _, cont) -> has_msend cont
           | SChoose bs | SOffer bs ->
             List.exists (fun (_, s') -> has_msend s') bs
           | SRec (_, s') -> has_msend s'
           | _ -> false
         in
         let rec has_mrecv s =
           match unfold_srec s with
           | SMRecv (r, t, cont) ->
             (r = sender && session_ty_equal (SSend (t, SEnd)) (SSend (msg_ty, SEnd)))
             || has_mrecv cont
           | SMSend (_, _, cont) -> has_mrecv cont
           | SChoose bs | SOffer bs ->
             List.exists (fun (_, s') -> has_mrecv s') bs
           | SRec (_, s') -> has_mrecv s'
           | _ -> false
         in
         (match List.assoc_opt sender projections with
          | Some proj when not (has_msend proj) ->
            Err.error env.errors ~span
              (Printf.sprintf
                 "Protocol `%s`: role `%s` should send to `%s` but \
                  its projected type does not include MSend(%s, ...)."
                 proto_name sender receiver receiver)
          | _ -> ());
         (match List.assoc_opt receiver projections with
          | Some proj when not (has_mrecv proj) ->
            Err.error env.errors ~span
              (Printf.sprintf
                 "Protocol `%s`: role `%s` should receive from `%s` but \
                  its projected type does not include MRecv(%s, ...)."
                 proto_name receiver sender sender)
          | _ -> ())
       ) msgs
   | _ -> ());  (* 0 or 1 role: already warned in caller *)
  projections

(* Reorder each maximal contiguous run of top-level function declarations so a
   function is checked AFTER the sibling functions it calls (callee-before-caller,
   i.e. dependency order).  This lets a caller observe a callee's fully-inferred,
   generalized type rather than a pass-1 monomorphic placeholder.  Using the
   placeholder leaks an unresolved/over-generalized type variable into the
   caller — and because `generalize` copies the type with fresh refs, a later
   reconciliation can no longer reach it.  The leak miscompiles at runtime: a
   polymorphic list is reference-counted differently than its concrete instance,
   producing a use-after-free.

   Safety: only DFn decls are moved, and only relative to one another within a
   maximal contiguous run, so non-DFn decls (DLet, DType, …) keep their
   positions and any dependency on a module-level value/type is preserved.
   Runs containing duplicate function names (default-argument wrappers, which
   the checker requires to be processed full-arity-first) are left untouched.
   Cycles (mutual recursion) are tolerated by a DFS post-order that keeps SCC
   members grouped and relies on the pass-1 placeholder for the cyclic edges. *)
let dependency_order_dfn_run (run : Ast.decl list) : Ast.decl list =
  let info =
    List.filter_map (function
      | Ast.DFn (d, sp) -> Some (d.Ast.fn_name.txt, (d, sp))
      | _ -> None) run
  in
  let names = List.map fst info in
  let has_dup =
    let seen = ref StringSet.empty and dup = ref false in
    List.iter (fun n ->
        if StringSet.mem n !seen then dup := true else seen := StringSet.add n !seen)
      names;
    !dup
  in
  if has_dup then run
  else begin
    let name_set = List.fold_left (fun s n -> StringSet.add n s) StringSet.empty names in
    let by_name : (string, Ast.fn_def * Ast.span) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (n, ds) -> Hashtbl.replace by_name n ds) info;
    (* Map a body reference to a local fn name.  A BARE name matches directly; a
       DOTTED name (`App.id`, produced by desugar's [qualify_module_refs] for an
       intra-nested-module reference) is mapped by its suffix after the last `.` —
       so a nested-module call to a sibling `id` is recognised as a dependency on
       the local `id`, and [dependency_order_dfn_run] orders the helper BEFORE its
       caller.  Without this, a forward reference (`fn attack() do need_str(id(x))`
       defined ABOVE `fn id`) left `App.id`'s prebind pinned to the caller's
       decoupled use, and the qualified-prebind reconciliation (see the DFn branch
       of [check_decl]) ran too late to un-erase the already-checked caller. *)
    let local_of n =
      if StringSet.mem n name_set then Some n
      else match String.rindex_opt n '.' with
        | Some i ->
          let suffix = String.sub n (i + 1) (String.length n - i - 1) in
          if StringSet.mem suffix name_set then Some suffix else None
        | None -> None
    in
    let deps_of (d : Ast.fn_def) =
      List.concat_map (fun (c : Ast.fn_clause) -> free_vars_expr [] c.Ast.fc_body)
        d.Ast.fn_clauses
      |> List.filter_map local_of
      |> List.filter (fun n -> n <> d.Ast.fn_name.txt)
    in
    let visited : (string, unit) Hashtbl.t = Hashtbl.create 16 in
    let out = ref [] in
    let rec visit name =
      if not (Hashtbl.mem visited name) then begin
        Hashtbl.replace visited name ();
        match Hashtbl.find_opt by_name name with
        | Some (d, sp) -> List.iter visit (deps_of d); out := Ast.DFn (d, sp) :: !out
        | None -> ()
      end
    in
    List.iter (fun n -> visit n) names;
    List.rev !out
  end

(* Collect the set of module-name prefixes referenced (qualified) anywhere in a
   list of declarations: qualified function/value uses ("Mod.f"), qualified
   constructors ("Mod.Ctor") and qualified type names ("Mod.T").  Used to order
   sibling modules so a module is checked AFTER the modules it depends on. *)
let module_refs_in_decls (decls : Ast.decl list) : StringSet.t =
  let acc = ref StringSet.empty in
  let add (s : string) =
    (* Record EVERY dotted prefix, not just the first segment: a sibling
       module can itself have a dotted name (`mod Depot.Schema`), so a
       reference "Depot.Schema.define" depends on "Depot.Schema", not only
       on "Depot" (often an empty namespace container).  The caller
       intersects with the actual sibling-name set, so non-module prefixes
       are dropped.  First-segment-only extraction left dotted siblings
       unordered relative to their callers, and every caller then unified
       against one shared pass-1 Mono placeholder — the first call site
       pinned the parameter types for all the others. *)
    let rec go i =
      match String.index_from_opt s i '.' with
      | Some j when j > 0 ->
        acc := StringSet.add (String.sub s 0 j) !acc;
        go (j + 1)
      | _ -> ()
    in
    go 0
  in
  let rec ty (t : Ast.ty) =
    match t with
    | Ast.TyCon (n, args) -> add n.Ast.txt; List.iter ty args
    | Ast.TyVar _ | Ast.TyNat _ -> ()
    | Ast.TyArrow (a, b) -> ty a; ty b
    | Ast.TyTuple ts -> List.iter ty ts
    | Ast.TyRecord flds -> List.iter (fun (_, t) -> ty t) flds
    | Ast.TyLinear (_, t) -> ty t
    | Ast.TyNatOp (_, a, b) -> ty a; ty b
    | Ast.TyChan (a, b) -> add a.Ast.txt; add b.Ast.txt
    | Ast.TyRefine (base, _, _) -> ty base
  in
  let oty = function Some t -> ty t | None -> () in
  let param (p : Ast.param) = oty p.Ast.param_ty in
  let rec ex (e : Ast.expr) =
    match e with
    | Ast.EVar n -> add n.Ast.txt
    | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> ()
    | Ast.EDbg (Some i, _) -> ex i
    | Ast.EApp (f, args, _) -> ex f; List.iter ex args
    | Ast.ECon (n, args, _) -> add n.Ast.txt; List.iter ex args
    | Ast.ELam (ps, b, _) -> List.iter param ps; ex b
    | Ast.EBlock (es, _) -> List.iter ex es
    | Ast.ELet (b, _) -> ex b.Ast.bind_expr
    | Ast.EMatch (s, brs, _) ->
      ex s;
      List.iter (fun (br : Ast.branch) ->
          (match br.Ast.branch_guard with Some g -> ex g | None -> ());
          ex br.Ast.branch_body) brs
    | Ast.ETuple (es, _) -> List.iter ex es
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> ex e) fs
    | Ast.ERecordUpdate (b, fs, _) -> ex b; List.iter (fun (_, e) -> ex e) fs
    | Ast.EField (e, _, _) -> ex e
    | Ast.EIf (c, t, f, _) -> ex c; ex t; ex f
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> ex c; ex b) arms
    | Ast.EAnnot (e, t, _) -> ex e; ty t
    | Ast.EAtom (_, args, _) -> List.iter ex args
    | Ast.ESend (a, b, _) -> ex a; ex b
    | Ast.ESpawn (e, _) -> ex e
    | Ast.ELetFn (_, ps, rt, b, _) -> List.iter param ps; oty rt; ex b
    | Ast.ELetQ (_, r, c, _) -> ex r; ex c
    | Ast.EPipe (l, r, _) -> ex l; ex r
    | Ast.EAssert (e, _) -> ex e
    | Ast.ESigil (_, c, _) -> ex c
  in
  let fn_param (fp : Ast.fn_param) =
    match fp with
    | Ast.FPNamed p -> oty p.Ast.param_ty
    | Ast.FPDefault (p, _) -> oty p.Ast.param_ty
    | Ast.FPPat _ -> ()
  in
  let decl (d : Ast.decl) =
    match d with
    | Ast.DFn (def, _) ->
      oty def.Ast.fn_ret_ty;
      List.iter (fun (c : Ast.fn_clause) ->
          List.iter fn_param c.Ast.fc_params;
          (match c.Ast.fc_guard with Some g -> ex g | None -> ());
          ex c.Ast.fc_body) def.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> ex b.Ast.bind_expr
    | Ast.DType (_, _, _, td, _)
    | Ast.DAlwaysLinearType (_, _, _, td, _) ->
      (match td with
       | Ast.TDAlias t -> ty t
       | Ast.TDRecord flds -> List.iter (fun (f : Ast.field) -> ty f.Ast.fld_ty) flds
       | Ast.TDVariant vs ->
         List.iter (fun (v : Ast.variant) -> List.iter ty v.Ast.var_args) vs)
    | _ -> ()
  in
  List.iter decl decls;
  !acc

(* Collect the sibling modules a module depends on through UNQUALIFIED type and
   constructor references (`List(Block)`, `Heading(..)`, `match .. Heading(x) ->`).
   [module_refs_in_decls] only sees qualified `Mod.x` references, so a module that
   uses another module's variant type or constructors by their bare name records
   no dependency and may be ordered — and therefore checked — before the defining
   module.  At that point the bare names are not yet exported into the outer
   scope, so the reference fails ("I cannot find `Block`").  Each bare type/ctor
   name is resolved to its owning sibling through the supplied owner maps.  Unlike
   pre-binding the bare names eagerly, fixing the ORDER keeps each constructor's
   resolved type identical to the single-entry (forge test) build, so it cannot
   perturb the constructor tags assigned during lowering. *)
let unqualified_module_deps
    ~(type_owner : (string, string) Hashtbl.t)
    ~(ctor_owner : (string, string) Hashtbl.t)
    (decls : Ast.decl list) : StringSet.t =
  let acc = ref StringSet.empty in
  let bare n = not (String.contains n '.') in
  let add tbl n =
    if bare n then
      match Hashtbl.find_opt tbl n with
      | Some m -> acc := StringSet.add m !acc
      | None -> ()
  in
  let rec ty (t : Ast.ty) =
    match t with
    | Ast.TyCon (n, args) -> add type_owner n.Ast.txt; List.iter ty args
    | Ast.TyArrow (a, b) -> ty a; ty b
    | Ast.TyTuple ts -> List.iter ty ts
    | Ast.TyRecord flds -> List.iter (fun (_, t) -> ty t) flds
    | Ast.TyLinear (_, t) -> ty t
    | Ast.TyNatOp (_, a, b) -> ty a; ty b
    | Ast.TyVar _ | Ast.TyNat _ | Ast.TyChan _ -> ()
    | Ast.TyRefine (base, _, _) -> ty base
  in
  let oty = function Some t -> ty t | None -> () in
  let rec pat (p : Ast.pattern) =
    match p with
    | Ast.PatCon (n, ps) -> add ctor_owner n.Ast.txt; List.iter pat ps
    | Ast.PatAtom (_, ps, _) -> List.iter pat ps
    | Ast.PatTuple (ps, _) -> List.iter pat ps
    | Ast.PatRecord (fs, _) -> List.iter (fun (_, p) -> pat p) fs
    | Ast.PatAs (p, _, _) -> pat p
    | Ast.PatWild _ | Ast.PatVar _ | Ast.PatLit _ -> ()
  in
  let param (p : Ast.param) = oty p.Ast.param_ty in
  let fn_param (fp : Ast.fn_param) =
    match fp with
    | Ast.FPNamed p -> param p
    | Ast.FPDefault (p, _) -> param p
    | Ast.FPPat pp -> pat pp
  in
  let rec ex (e : Ast.expr) =
    match e with
    | Ast.ECon (n, args, _) -> add ctor_owner n.Ast.txt; List.iter ex args
    | Ast.EVar _ | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _
    | Ast.EDbg (None, _) -> ()
    | Ast.EDbg (Some i, _) -> ex i
    | Ast.EApp (f, args, _) -> ex f; List.iter ex args
    | Ast.ELam (ps, b, _) -> List.iter param ps; ex b
    | Ast.EBlock (es, _) -> List.iter ex es
    | Ast.ELet (b, _) -> pat b.Ast.bind_pat; ex b.Ast.bind_expr
    | Ast.EMatch (s, brs, _) ->
      ex s;
      List.iter (fun (br : Ast.branch) ->
          pat br.Ast.branch_pat;
          (match br.Ast.branch_guard with Some g -> ex g | None -> ());
          ex br.Ast.branch_body) brs
    | Ast.ETuple (es, _) -> List.iter ex es
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> ex e) fs
    | Ast.ERecordUpdate (b, fs, _) -> ex b; List.iter (fun (_, e) -> ex e) fs
    | Ast.EField (e, _, _) -> ex e
    | Ast.EIf (c, t, f, _) -> ex c; ex t; ex f
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> ex c; ex b) arms
    | Ast.EAnnot (e, t, _) -> ex e; ty t
    | Ast.EAtom (_, args, _) -> List.iter ex args
    | Ast.ESend (a, b, _) -> ex a; ex b
    | Ast.ESpawn (e, _) -> ex e
    | Ast.ELetFn (_, ps, rt, b, _) -> List.iter param ps; oty rt; ex b
    | Ast.ELetQ (_, r, c, _) -> ex r; ex c
    | Ast.EPipe (l, r, _) -> ex l; ex r
    | Ast.EAssert (e, _) -> ex e
    | Ast.ESigil (_, c, _) -> ex c
  in
  let decl (d : Ast.decl) =
    match d with
    | Ast.DFn (def, _) ->
      oty def.Ast.fn_ret_ty;
      List.iter (fun (c : Ast.fn_clause) ->
          List.iter fn_param c.Ast.fc_params;
          (match c.Ast.fc_guard with Some g -> ex g | None -> ());
          ex c.Ast.fc_body) def.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> pat b.Ast.bind_pat; ex b.Ast.bind_expr
    | Ast.DType (_, _, _, td, _)
    | Ast.DAlwaysLinearType (_, _, _, td, _) ->
      (match td with
       | Ast.TDAlias t -> ty t
       | Ast.TDRecord flds -> List.iter (fun (f : Ast.field) -> ty f.Ast.fld_ty) flds
       | Ast.TDVariant vs ->
         List.iter (fun (v : Ast.variant) -> List.iter ty v.Ast.var_args) vs)
    | _ -> ()
  in
  List.iter decl decls;
  !acc

(* Reorder a maximal run of sibling module declarations so a module is checked
   AFTER the sibling modules it references.  Same rationale as the function-level
   ordering: a caller module that is checked before a callee module sees the
   callee's qualified names as pass-1 placeholders, leaking an unresolved type
   variable that later miscompiles into a use-after-free.  Auto-discovered
   project modules are otherwise ordered by a namespace-depth heuristic that does
   not reflect actual dependencies, so flat (single-segment) module sets end up
   alphabetical. *)
let dependency_order_dmod_run (run : Ast.decl list) : Ast.decl list =
  let info =
    List.filter_map (function
      | Ast.DMod (n, _, decls, _) as dm -> Some (n.Ast.txt, (decls, dm))
      | _ -> None) run
  in
  let names = List.map fst info in
  let has_dup =
    let seen = ref StringSet.empty and dup = ref false in
    List.iter (fun n ->
        if StringSet.mem n !seen then dup := true else seen := StringSet.add n !seen)
      names;
    !dup
  in
  if has_dup then run
  else begin
    let name_set = List.fold_left (fun s n -> StringSet.add n s) StringSet.empty names in
    let by_name : (string, Ast.decl list * Ast.decl) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (n, ds) -> Hashtbl.replace by_name n ds) info;
    (* Map each public type / constructor name to the sibling module that defines
       it, so a module referencing them UNQUALIFIED records a dependency on the
       definer (see [unqualified_module_deps]). *)
    let type_owner : (string, string) Hashtbl.t = Hashtbl.create 64 in
    let ctor_owner : (string, string) Hashtbl.t = Hashtbl.create 64 in
    List.iter (fun (modname, (decls, _)) ->
        List.iter (function
          | Ast.DType (Ast.Public, tname, _, td, _)
          | Ast.DAlwaysLinearType (Ast.Public, tname, _, td, _) ->
            if not (Hashtbl.mem type_owner tname.Ast.txt) then
              Hashtbl.replace type_owner tname.Ast.txt modname;
            (match td with
             | Ast.TDVariant vs ->
               List.iter (fun (v : Ast.variant) ->
                   if v.Ast.var_vis = Ast.Public
                      && not (Hashtbl.mem ctor_owner v.Ast.var_name.Ast.txt) then
                     Hashtbl.replace ctor_owner v.Ast.var_name.Ast.txt modname) vs
             | _ -> ())
          | _ -> ()) decls
      ) info;
    let visited : (string, unit) Hashtbl.t = Hashtbl.create 16 in
    let out = ref [] in
    let rec visit name =
      if not (Hashtbl.mem visited name) then begin
        Hashtbl.replace visited name ();
        match Hashtbl.find_opt by_name name with
        | Some (decls, dm) ->
          let deps =
            StringSet.remove name
              (StringSet.inter name_set
                 (StringSet.union
                    (module_refs_in_decls decls)
                    (unqualified_module_deps ~type_owner ~ctor_owner decls)))
          in
          StringSet.iter visit deps;
          out := dm :: !out
        | None -> ()
      end
    in
    List.iter (fun n -> visit n) names;
    List.rev !out
  end

(* Reorder both function runs (by call dependency) and module runs (by module
   dependency) within [decls], leaving every other declaration in place. *)
let reorder_decls (decls : Ast.decl list) : Ast.decl list =
  let is_dfn = function Ast.DFn _ -> true | _ -> false in
  let is_dmod = function Ast.DMod _ -> true | _ -> false in
  let take pred ds =
    let rec go acc = function
      | x :: xs when pred x -> go (x :: acc) xs
      | rest -> (List.rev acc, rest)
    in
    go [] ds
  in
  let rec go = function
    | [] -> []
    | d :: _ as ds when is_dfn d ->
      let run, rest = take is_dfn ds in
      dependency_order_dfn_run run @ go rest
    | d :: _ as ds when is_dmod d ->
      let run, rest = take is_dmod ds in
      dependency_order_dmod_run run @ go rest
    | d :: rest -> d :: go rest
  in
  go decls

(* ── Panic-surface analysis for `cap no_panic` ────────────────────────── *)

let panic_surface_direct : StringSet.t = StringSet.of_list [
  (* Division/modulo operators are handled by the Z3-backed Division_safety
     pass in march_refinecheck, which can approve them when the divisor has a
     {v | v != 0} (or v > 0) refinement.  Remove them here so the syntactic
     no-panic check does not double-report when refinements prove safety. *)
  "panic"; "panic_"; "todo_"; "unreachable_";
]

let panic_surface_prelude : StringSet.t = StringSet.of_list [
  "unwrap"; "expect"; "head"; "tail"; "last";
]

let panic_surface_stdlib : StringSet.t = StringSet.of_list [
  "List.nth"; "List.hd"; "List.tl"; "List.head"; "List.last";
  "List.min_elt"; "List.max_elt";
  "Option.unwrap"; "Option.expect";
  "Result.unwrap"; "Result.expect"; "Result.unwrap_err";
  "Array.get"; "Array.set";
  "String.slice_bytes"; "String.nth";
  "NativeArray.get"; "NativeArray.set";
]

let panic_surface_all_direct : StringSet.t =
  StringSet.union panic_surface_direct panic_surface_prelude

let panic_surface_suggestion : string -> string = function
  | "List.nth" ->
    "\n\nUse `List.nth_opt` to return `Option(a)` instead of panicking on out-of-bounds."
  | "List.hd" | "List.head" | "head" ->
    "\n\nUse `List.head_opt` (or match on `Cons`/`Nil` directly) to avoid panicking on empty."
  | "List.tl" | "List.tail" | "tail" ->
    "\n\nUse `List.tail_opt` or match on `Nil` to avoid panicking on empty."
  | "unwrap" | "Option.unwrap" ->
    "\n\nUse `unwrap_or(opt, default)` or `match opt do Some(x) -> ... | None -> ... end`."
  | "expect" | "Option.expect" ->
    "\n\nUse `unwrap_or` or an explicit match to handle the `None` case."
  | "Result.unwrap" | "Result.expect" ->
    "\n\nUse `Result.unwrap_or` or match on `Ok`/`Err` to handle the error case."
  | "Array.get" | "Array.set" | "NativeArray.get" | "NativeArray.set" ->
    "\n\nBounds-check the index before access, or use a bounds-checked variant."
  | "String.slice_bytes" | "String.nth" ->
    "\n\nBounds-check the index/range before access."
  | "panic" | "panic_" ->
    "\n\nReturn an error value (`Result`, `Option`) instead of calling `panic`."
  | "todo_" ->
    "\n\nImplement the body instead of using `todo!`, or remove the `cap no_panic` directive."
  | "unreachable_" ->
    "\n\nAdd a proof comment if this branch is truly unreachable, or handle it explicitly."
  | _ -> ""

let rec calls_in_expr (acc : (string * Ast.span) list) (e : Ast.expr)
    : (string * Ast.span) list =
  match e with
  | Ast.EApp (Ast.EVar fn_name, args, _) ->
    let acc = (fn_name.txt, fn_name.span) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (Ast.EField (Ast.EVar mod_name, fn_name, _), args, _) ->
    let qname = mod_name.txt ^ "." ^ fn_name.txt in
    let acc = (qname, fn_name.span) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (f, args, _) ->
    List.fold_left calls_in_expr (calls_in_expr acc f) args
  | Ast.EBlock (es, _) ->
    List.fold_left calls_in_expr acc es
  | Ast.ELet (b, _) ->
    calls_in_expr acc b.Ast.bind_expr
  | Ast.EMatch (scrut, arms, _) ->
    let acc = calls_in_expr acc scrut in
    List.fold_left (fun a arm ->
      let a = Option.fold ~none:a ~some:(calls_in_expr a) arm.Ast.branch_guard in
      calls_in_expr a arm.Ast.branch_body) acc arms
  | Ast.EIf (cond, then_, else_, _) ->
    calls_in_expr (calls_in_expr (calls_in_expr acc cond) then_) else_
  | Ast.EField (inner, _, _) -> calls_in_expr acc inner
  | Ast.EPipe (a, b, _) -> calls_in_expr (calls_in_expr acc a) b
  | Ast.ELetFn (_, _, _, body, _) -> calls_in_expr acc body
  | Ast.ELetQ (_, rhs, body, _) ->
    calls_in_expr (calls_in_expr acc rhs) body
  | Ast.ELit _ | Ast.EVar _ -> acc
  | _ -> acc

(** [span_within inner outer] is true when [inner] is nested inside [outer] by
    source position — same file, and [inner]'s start/end fall within [outer]'s
    line/column bounds.  Used to attribute a recorded non-exhaustive-match span
    to the enclosing `cap no_panic` function whose body it lives in, so a match
    in some UNRELATED (plain) module is never blamed on the no_panic module. *)
let span_within (inner : Ast.span) (outer : Ast.span) : bool =
  inner.Ast.file = outer.Ast.file
  && (inner.Ast.start_line > outer.Ast.start_line
      || (inner.Ast.start_line = outer.Ast.start_line
          && inner.Ast.start_col >= outer.Ast.start_col))
  && (inner.Ast.end_line < outer.Ast.end_line
      || (inner.Ast.end_line = outer.Ast.end_line
          && inner.Ast.end_col <= outer.Ast.end_col))

let check_no_panic_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let fn_entries : (string * (string * Ast.span) list * Ast.span) list =
    List.filter_map (fun d ->
      match d with
      | Ast.DFn (def, fn_span) ->
        let all_calls =
          List.fold_left (fun acc clause ->
            calls_in_expr acc clause.Ast.fc_body
          ) [] def.Ast.fn_clauses
        in
        Some (def.Ast.fn_name.txt, all_calls, fn_span)
      | _ -> None
    ) decls
  in
  let local_fns =
    List.fold_left (fun s (name, _, _) -> StringSet.add name s)
      StringSet.empty fn_entries
  in
  let _no_panic_mod_names = StringSet.of_list env.no_panic_modules in
  let is_direct_panic_site name =
    StringSet.mem name panic_surface_all_direct
    || StringSet.mem name panic_surface_stdlib
  in
  let seed =
    List.fold_left (fun (panicky, site_map) (fn_name, calls, _span) ->
      match List.find_opt (fun (n, _sp) ->
        is_direct_panic_site n
      ) calls with
      | Some (site_name, site_span) ->
        (StringSet.add fn_name panicky,
         StrMap.add fn_name (site_name, site_span, `Direct) site_map)
      | None ->
        (panicky, site_map)
    ) (StringSet.empty, StrMap.empty) fn_entries
  in
  let seed_panicky, seed_site_map = seed in
  let rec fixpoint panicky site_map =
    let (panicky', site_map') =
      List.fold_left (fun (p, sm) (fn_name, calls, _span) ->
        if StringSet.mem fn_name p then (p, sm)
        else
          match List.find_opt (fun (n, _sp) ->
            StringSet.mem n p && StringSet.mem n local_fns
          ) calls with
          | Some (callee_name, callee_span) ->
            (StringSet.add fn_name p,
             StrMap.add fn_name (callee_name, callee_span, `Transitive) sm)
          | None -> (p, sm)
      ) (panicky, site_map) fn_entries
    in
    if StringSet.cardinal panicky' = StringSet.cardinal panicky then
      (panicky', site_map')
    else
      fixpoint panicky' site_map'
  in
  let (all_panicky, site_map) = fixpoint seed_panicky seed_site_map in
  List.iter (fun (fn_name, _calls, fn_span) ->
    if StringSet.mem fn_name all_panicky then begin
      match StrMap.find_opt fn_name site_map with
      | None -> ()
      | Some (site_name, site_span, kind) ->
        let mod_name = env.current_module in
        let msg = match kind with
          | `Direct ->
            let suggestion = panic_surface_suggestion site_name in
            Printf.sprintf
              "`%s` in `mod %s` (declared `cap no_panic`) calls `%s`, which can panic.%s"
              fn_name mod_name site_name suggestion
          | `Transitive ->
            Printf.sprintf
              "`%s` in `mod %s` (declared `cap no_panic`) transitively calls `%s`, \
               which can panic."
              fn_name mod_name site_name
        in
        let _ = fn_span in
        Err.error errors ~span:site_span msg
    end
  ) fn_entries;
  (* A NON-exhaustive `match` lowers to a runtime "no matching clause" panic, so
     it is a panic surface just like `panic`/`unwrap`.  [check_exhaustiveness]
     already found and recorded every non-exhaustive match's span (see
     [env.nonexhaustive_match_spans]); here we reject any that falls inside one
     of THIS `cap no_panic` module's own function bodies.  Span containment
     attributes each match to its enclosing fn, so a non-exhaustive match in an
     unrelated (plain) module is never blamed on this module. *)
  let mod_name = env.current_module in
  let ne_spans = !(env.nonexhaustive_match_spans) in
  List.iter (fun (fn_name, _calls, fn_span) ->
    List.iter (fun (msp : Ast.span) ->
      if span_within msp fn_span then
        Err.error errors ~span:msp
          (Printf.sprintf
             "`%s` in `mod %s` (declared `cap no_panic`) contains a non-exhaustive \
              `match`, which panics at runtime when no clause matches.\n\n\
              A `cap no_panic` module must handle every case, or add a `_ -> ...` \
              catch-all arm."
             fn_name mod_name)
    ) ne_spans
  ) fn_entries

(* ── cap pure: ban side-effectful builtins ───────────────────────────────── *)

(* A cap tag denotes a NONDETERMINISM source (wall-clock or RNG) — the only
   effects a `cap deterministic` module must reject. Ordinary IO
   (file/console/network) is deterministic-ish and stays allowed. *)
let is_nondeterministic_cap (cap : string) : bool =
  cap = "IO.Clock" || cap = "IO.Random"

(* `cap pure` = NO side effect at all → ban every builtin the authoritative
   effect map (`builtin_cap_table`) attributes an IO/effect cap to. Derived
   from the table (not a hand-guessed parallel list) so it stays in lockstep
   with the real builtin surface. `spawn`/`send`/`exit` are impure surface
   names not carried in the table (they route through other mechanisms) —
   union them in as incidental-correct extras. *)
let pure_banned : StringSet.t =
  let from_table = builtin_cap_table |> List.map fst |> StringSet.of_list in
  StringSet.union from_table
    (StringSet.of_list [ "spawn"; "send"; "exit" ])

let pure_suggestion : string =
  "Use pure functions (no IO, spawn, vault, or random ops) in a `cap pure` module."

let check_pure_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let mod_name = env.current_module in
  List.iter (fun d ->
    match d with
    | Ast.DFn (def, _fn_span) ->
      List.iter (fun clause ->
        let calls = calls_in_expr [] clause.Ast.fc_body in
        List.iter (fun (name, site_span) ->
          if StringSet.mem name pure_banned then
            Err.error errors ~span:site_span
              (Printf.sprintf
                 "`%s` in `mod %s` (declared `cap pure`) calls `%s`, which has side effects.\n\n%s"
                 def.Ast.fn_name.txt mod_name name pure_suggestion)
        ) calls
      ) def.Ast.fn_clauses
    | _ -> ()
  ) decls

(* ── cap no_extern: ban FFI extern blocks ────────────────────────────────── *)

let no_extern_suggestion : string =
  "Remove `extern` blocks and `needs IO.Foreign` from `cap no_extern` modules."

let check_no_extern_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let mod_name = env.current_module in
  List.iter (fun d ->
    match d with
    | Ast.DExtern (edef, sp) ->
      Err.error errors ~span:sp
        (Printf.sprintf
           "`mod %s` (declared `cap no_extern`) contains an `extern` block (`%s`).\n\n%s"
           mod_name edef.Ast.ext_lib_name no_extern_suggestion)
    | Ast.DNeeds (caps, sp) ->
      (* Check if any capability path starts with "IO" and contains "Foreign" *)
      let has_foreign = List.exists (fun path ->
        match path with
        | first :: rest ->
          first.Ast.txt = "IO" &&
          List.exists (fun p -> p.Ast.txt = "Foreign") rest
        | [] -> false
      ) caps in
      if has_foreign then
        Err.error errors ~span:sp
          (Printf.sprintf
             "`mod %s` (declared `cap no_extern`) uses `needs IO.Foreign`.\n\n%s"
             mod_name no_extern_suggestion)
    | _ -> ()
  ) decls

(* ── cap deterministic: ban non-deterministic builtins ───────────────────── *)

(* `cap deterministic` = no dependence on wall-clock time or an RNG (a weaker
   claim than `pure` — a deterministic module MAY still do ordinary IO like
   `println` or a `file_read`). Ban only the builtins the effect map attributes
   to `IO.Clock`/`IO.Random`, derived from the same authoritative table. *)
let deterministic_banned : StringSet.t =
  builtin_cap_table
  |> List.filter (fun (_, cap) -> is_nondeterministic_cap cap)
  |> List.map fst
  |> StringSet.of_list

let deterministic_suggestion : string =
  "Use deterministic operations only in a `cap deterministic` module. \
   Avoid random/time builtins."

let check_deterministic_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let mod_name = env.current_module in
  List.iter (fun d ->
    match d with
    | Ast.DFn (def, _fn_span) ->
      List.iter (fun clause ->
        let calls = calls_in_expr [] clause.Ast.fc_body in
        List.iter (fun (name, site_span) ->
          if StringSet.mem name deterministic_banned then
            Err.error errors ~span:site_span
              (Printf.sprintf
                 "`%s` in `mod %s` (declared `cap deterministic`) calls `%s`, \
                  which is non-deterministic.\n\n%s"
                 def.Ast.fn_name.txt mod_name name deterministic_suggestion)
        ) calls
      ) def.Ast.fn_clauses
    | _ -> ()
  ) decls

let rec check_decl env (d : Ast.decl) : env =
  match d with
  | Ast.DFn (def, sp) ->
    let sch = check_fn env def sp in
    discharge_constraints env sp;
    let env = bind_var def.fn_name.txt sch env in
    (* Reconcile the QUALIFIED prebind (`Mod.fn`) with the fn's REAL body-checked
       scheme.  desugar's [qualify_module_refs] (lib/desugar/desugar.ml) rewrites
       every intra-nested-module reference to the qualified form (e.g. `App.id`),
       and [prebind_mod_members] seeds that name with either a fresh
       `Mono (fresh_var 1)` placeholder (UNANNOTATED fn — [prebind_fn_scheme]
       returned None) or a scheme built purely from annotation SYNTAX
       (ANNOTATED fn — never unified against the body, so `fn launder(x:a):b do x`
       keeps a decoupled `a -> b` that erases through every call).  Either way the
       prebind is NOT the validated scheme; a sibling fn resolving the qualified
       name gets a decoupled `?a -> ?b` that ERASES the type of anything laundered
       through it (a general type-soundness hole; the proof-cap forge was one
       exploitation).  Bind the qualified name to [sch] — the scheme [check_fn]
       actually validated against the body — UNCONDITIONALLY (both the placeholder
       and the un-body-validated-annotation cases).  This is codegen-safe: mono/TIR
       key on the per-span [type_map] types, not this env scheme, and the full
       [llvm_ir_validity_gate] (CRDT/distributed fixtures) is clean under it.
       Forward references — where a caller earlier in the module already pinned the
       placeholder to its own decoupled use — are handled UPSTREAM by
       [dependency_order_dfn_run]: its [deps_of]/[local_of] now sees the qualified
       reference (`App.id`) as a dependency on the local `id`, so `id` is checked
       (and this rebind runs) BEFORE any caller.

       [prebind_mod_members] seeds a fn's qualified key under TWO prefixes,
       reconcile BOTH so no qualified key retains a decoupled scheme:
       - [cap_qual_prefix] — the accumulated dotted path of ENCLOSING nested
         modules ("" at the entry module, then the nested names, entry mod
         stripped): matches [prebind_mod_members]'s [prefix] recursion (:8626).
       - [current_module] — the CURRENT module's own name.  At the ENTRY module,
         [check_module_core] seeds the entry's own top-level fns under
         `EntryMod.fn` (`prebind_mod_members m.mod_name.txt`, :8732) while
         [cap_qual_prefix] is still "", so the entry-self-qualified key
         (`Main.id`, or a nested sibling's `T.id` reference to the entry `T`)
         would otherwise never be reconciled — a memory-unsafe erasure when the
         explicit `EntryMod.id` form is written.  (For a nested module both
         prefixes may coincide or nest; deduping by the [<>""] guards + a set
         avoids a redundant rebind, and rebinding the same real [sch] twice is
         harmless anyway.) *)
    let reconcile_qkey env prefix =
      if prefix = "" then env
      else
        let qname = prefix ^ "." ^ def.fn_name.txt in
        (match StrMap.find_opt qname env.vars with
         | Some _ -> bind_var qname sch env
         | None   -> env)
    in
    let env = reconcile_qkey env env.cap_qual_prefix in
    let env =
      if env.current_module <> env.cap_qual_prefix
      then reconcile_qkey env env.current_module else env
    in
    env

  | Ast.DLet (_vis, b, sp) ->
    let env' = enter_level env in
    let rhs_ty = infer_expr env' b.bind_expr in
    Hashtbl.replace env.type_map sp (repr rhs_ty);
    let bindings, pat_ty = infer_pattern env' b.bind_pat in
    unify env' ~span:sp ~reason:(Some (RLetBind sp)) rhs_ty pat_ty;
    discharge_constraints env sp;
    ignore (leave_level env');
    (* Generalise simple variable bindings at module level *)
    let gen_bnd bnd = match bnd with
      | (name, Mono t) -> (name, generalize env.level t)
      | other          -> other
    in
    let bindings' = match b.bind_pat with
      | Ast.PatVar _ -> List.map gen_bnd bindings
      | _            -> bindings
    in
    bind_vars bindings' env

  | Ast.DType (_vis, name, params, typedef, _sp) ->
    let env1 = { env with types = StrMap.add name.txt (List.length params) env.types } in
    (match typedef with
     | Ast.TDVariant variants ->
       let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
       (* Check for duplicate constructor names within this type.
          Track (name, span) pairs so we can point at both occurrences. *)
       let _ = List.fold_left (fun seen (v : Ast.variant) ->
           match List.assoc_opt v.var_name.txt seen with
           | Some first_sp ->
             Err.error env.errors ~span:v.var_name.span
               (Printf.sprintf
                  "type `%s` defines constructor `%s` more than once\n\
                   Constructors are the named cases of a variant type — \
                   each must have a unique name within the type.\n\
                   First defined at %s:%d:%d"
                  name.txt v.var_name.txt
                  first_sp.Ast.file first_sp.Ast.start_line first_sp.Ast.start_col);
             seen
           | None -> (v.var_name.txt, v.var_name.span) :: seen
         ) [] variants in
       List.fold_left (fun e (v : Ast.variant) ->
           let ci = { ci_type    = name.txt
                    ; ci_params  = param_names
                    ; ci_arg_tys = v.var_args
                    ; ci_vis     = v.var_vis } in
           (* Register both bare "CtorName" and qualified "TypeName.CtorName"
              so users can write either form for disambiguation. *)
           let qual_key = name.txt ^ "." ^ v.var_name.txt in
           { e with ctors = add_ctor qual_key ci (add_ctor v.var_name.txt ci e.ctors) }
         ) env1 variants
     | Ast.TDRecord fields ->
       let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
       (* Check for duplicate field names within this record.
          Track (name, span) pairs so we can point at both occurrences. *)
       let _ = List.fold_left (fun seen (f : Ast.field) ->
           match List.assoc_opt f.fld_name.txt seen with
           | Some first_sp ->
             Err.error env.errors ~span:f.fld_name.span
               (Printf.sprintf
                  "record `%s` defines field `%s` more than once\n\
                   First defined at %s:%d:%d"
                  name.txt f.fld_name.txt
                  first_sp.Ast.file first_sp.Ast.start_line first_sp.Ast.start_col);
             seen
           | None -> (f.fld_name.txt, f.fld_name.span) :: seen
         ) [] fields in
       (* Propagate field-level linearity annotations into the surface type so
          that expand_record returns TLin wrappers for linear fields.  This
          enables both the EField check and let-binding linearity propagation
          (bind_vars_with_linearity) to see the linear field constraint. *)
       let field_pairs = List.map (fun (f : Ast.field) ->
           let fty = match f.fld_lin with
             | Ast.Unrestricted -> f.fld_ty
             | lin -> Ast.TyLinear (lin, f.fld_ty)
           in
           (f.fld_name.txt, fty)
         ) fields in
       register_record_name ~name:name.txt (List.map fst field_pairs);
       { env1 with records = StrMap.add name.txt (param_names, field_pairs) env1.records }
     | Ast.TDAlias _ -> env1)

  | Ast.DActor (_vis, name, actor, _sp) ->
    (* Build the state record type from field declarations *)
    let state_ty =
      let tvars = ref [] in
      let flds = List.map (fun (f : Ast.field) ->
          (f.fld_name.txt, surface_ty env ~tvars f.fld_ty)) actor.actor_state in
      TRecord (List.sort (fun (a,_)(b,_) -> String.compare a b) flds)
    in
    (* Check for duplicate handler names — two `on Msg(...)` arms for the
       same message name is always a programmer error. *)
    let _ = List.fold_left (fun seen (h : Ast.actor_handler) ->
        if List.mem h.ah_msg.txt seen then
          Err.error env.errors ~span:h.ah_msg.span
            (Printf.sprintf
               "actor '%s' defines handler '%s' more than once;\
                \nremove the duplicate or rename one of them"
               name.txt h.ah_msg.txt);
        h.ah_msg.txt :: seen
      ) [] actor.actor_handlers in
    (* Register actor name as a zero-arg constructor (so spawn(ActorName) typechecks)
       and message constructors so ECon lookups succeed.
       Include ALL params — annotated and unannotated — so constructor arity
       is always correct.  Unannotated params are given a unique TyVar placeholder
       (named "$p<i>_<Msg>") that resolves to a fresh unification variable during
       instantiation; this ensures `send(pid, Msg(x))` typechecks correctly even
       when the handler omits a type annotation. *)
    let env_with_actor_ctor = { env with ctors =
      add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_vis = Ast.Public }
        env.ctors } in
    let env_with_ctors = List.fold_left (fun acc_env (h : Ast.actor_handler) ->
        let arg_tys = List.mapi (fun i (p : Ast.param) ->
            match p.param_ty with
            | Some ty -> ty
            | None ->
              (* Unique name per (handler, position) so each instantiation
                 gets an independent fresh variable. *)
              Ast.TyVar { txt = Printf.sprintf "$p%d_%s" i h.ah_msg.txt;
                          span = p.param_name.span }
          ) h.ah_params in
        let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                   ci_arg_tys = arg_tys; ci_vis = Ast.Public } in
        { acc_env with ctors = add_ctor h.ah_msg.txt ci acc_env.ctors }
      ) env_with_actor_ctor actor.actor_handlers in
    (* Check init expression — must return the state record type *)
    check_expr env_with_ctors actor.actor_init state_ty
      ~reason:(Some (RBuiltin "actor init must return the initial state record"));
    (* Check handlers with state and message params in scope *)
    List.iter (fun (h : Ast.actor_handler) ->
        let handler_env = bind_var "state" (Mono state_ty) env_with_ctors in
        let handler_env =
          List.fold_left (fun e p ->
              bind_var p.Ast.param_name.txt
                (Mono (match p.param_ty with
                   | Some ann -> let tvars = ref [] in surface_ty env ~tvars ann
                   | None     -> fresh_var env.level))
                e
            ) handler_env h.ah_params
        in
        (* Handler body must return the state record type — emit rich diagnostic *)
        let inferred = infer_expr handler_env h.ah_body in
        let shadow_env = { handler_env with errors = Err.create () } in
        (* Note: pending_constraints and type_map are shared (shallow copy) —
           intentional; only error reporting is isolated. *)
        unify shadow_env ~span:h.ah_msg.span ~reason:None
          (repr inferred) (repr state_ty);
        if Err.has_errors shadow_env.errors then
          Err.report handler_env.errors
            { severity = Error;
              span = h.ah_msg.span;
              message = Printf.sprintf
                "handler '%s' in actor '%s' must return the state type\
                 \n  expected: %s\
                 \n  got:      %s"
                h.ah_msg.txt name.txt
                (pp_ty (repr state_ty)) (pp_ty (repr inferred));
              labels = [];
              notes = actor_handler_hints (repr state_ty) (repr inferred);
              code = None; fix = None }
      ) actor.actor_handlers;
    bind_var name.txt (Mono (TCon ("Pid", [state_ty]))) env_with_ctors

  | Ast.DMod (name, _vis, decls, _sp) ->
    (* Reset local_fns for this module's scope: a nested module's locally
       defined fn names shadow bulk imports inside it (see env.local_fns). *)
    let pre_env = List.fold_left (fun e d ->
        match d with
        | Ast.DFn (def, _) ->
          let arity = match def.fn_clauses with
            | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
          let e = { e with local_fns = StrMap.add def.fn_name.txt () e.local_fns;
                           fn_arities = StrMap.add def.fn_name.txt (arity, def.fn_name.span) e.fn_arities } in
          bind_var def.fn_name.txt (Mono (fresh_var (env.level + 1))) e
        | _ -> e
      ) { env with local_fns = StrMap.empty; current_module = name.txt;
          cap_qual_prefix =
            (if env.cap_qual_prefix = "" then name.txt
             else env.cap_qual_prefix ^ "." ^ name.txt) } decls in
    let inner_env = List.fold_left check_decl pre_env (reorder_decls decls) in
    (* Collect the names that are explicitly public within this module. *)
    let pub_set =
      List.filter_map (function
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public -> Some def.fn_name.txt
        | Ast.DFn _ -> None
        | Ast.DLet (Ast.Public, b, _) ->
          (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
        | Ast.DLet _ -> None
        | Ast.DType (Ast.Public, n, _, _, _) -> Some n.txt
        | Ast.DType _ -> None
        | Ast.DAlwaysLinearType (Ast.Public, n, _, _, _) -> Some n.txt
        | Ast.DAlwaysLinearType _ -> None
        | Ast.DActor (Ast.Public, n, _, _) -> Some n.txt
        | Ast.DActor _ -> None
        | Ast.DMod (n, Ast.Public, _, _) -> Some n.txt
        | Ast.DMod _ -> None
        (* Interface declarations are always public — export interface name so that
           its methods (bound as "IfaceName.method" in inner_env) get exported
           as "ModName.IfaceName.method" into the outer scope. *)
        | Ast.DInterface (idef, _) -> Some idef.iface_name.txt
        | _ -> None
      ) decls
    in
    (* Private value/function members of this module (declared but not exported).
       Recorded in [env.local_mods] under the module's name so a same-file
       qualified reference to one (e.g. `A.secret` where `secret` is a `pfn`)
       is diagnosed as "private to module `A`" instead of the misleading
       "Unknown module `A`" (see [qualified_error_msg]). *)
    let priv_members =
      List.filter_map (function
        | Ast.DFn (def, _) when def.fn_vis = Ast.Private -> Some def.fn_name.txt
        | Ast.DLet (Ast.Private, b, _) ->
          (match b.bind_pat with Ast.PatVar n -> Some n.txt | _ -> None)
        | _ -> None
      ) decls
    in
    (* Check conformance against any matching sig declaration (Phase 2) *)
    let opaque_types =
      match List.assoc_opt name.txt env.sigs with
      | None -> []
      | Some sdef ->
        (* Verify all sig_fns are present with matching types *)
        List.iter (fun ((fname : Ast.name), sig_ty) ->
            match StrMap.find_opt fname.txt inner_env.vars with
            | None ->
              Err.error env.errors ~span:name.span
                (Printf.sprintf
                   "Module `%s` does not implement `%s` required by `sig %s`."
                   name.txt fname.txt name.txt)
            | Some sch ->
              (* Convert sig_ty to internal type and check unification via a
                 temporary error context so we can produce a clean error message. *)
              let tvars = ref [] in
              let expected = surface_ty inner_env ~tvars sig_ty in
              let actual = instantiate env.level inner_env sch in
              let tmp_errors = Err.create () in
              let tmp_env = { inner_env with errors = tmp_errors } in
              unify tmp_env ~span:fname.span expected actual;
              if Err.has_errors tmp_errors then
                Err.error env.errors ~span:fname.span
                  (Printf.sprintf
                     "Module `%s` implements `%s` with wrong type.\n  \
                      Expected: %s  (from sig %s)\n  \
                      Got:      %s"
                     name.txt fname.txt
                     (pp_ty (repr expected)) name.txt
                     (pp_ty (repr actual)))
          ) sdef.sig_fns;
        (* Verify all sig_types are declared in the module *)
        List.iter (fun ((tname : Ast.name), _params) ->
            if not (StrMap.mem tname.txt inner_env.types) then
              Err.error env.errors ~span:name.span
                (Printf.sprintf
                   "Module `%s` does not declare type `%s` required by `sig %s`."
                   name.txt tname.txt name.txt)
          ) sdef.sig_types;
        (* Return the list of opaque type names for constructor hiding below *)
        List.map (fun ((tname : Ast.name), _) -> tname.txt) sdef.sig_types
    in
    (* Validate capability declarations for this module *)
    check_module_needs env name decls
      ~cap_qname_prefix:(if env.cap_qual_prefix = "" then name.txt
                         else env.cap_qual_prefix ^ "." ^ name.txt);
    (* Validate island module protocol if applicable *)
    validate_island_protocol env name decls;
    (* Expose only public names as "ModName.name" in the outer env.
       Also export sub-module keys: if "B" is in pub_set, export "B.f" as "A.B.f". *)
    let is_pub_key k =
      List.exists (fun n ->
        k = n ||
        (String.length k > String.length n + 1 &&
         String.sub k 0 (String.length n + 1) = n ^ ".")
      ) pub_set
    in
    (* Collect exported names from inner_env.vars.
       StrMap guarantees one entry per key so deduplication is not needed. *)
    let new_names = StrMap.fold (fun k sch acc ->
        if is_pub_key k
        then (name.txt ^ "." ^ k, sch) :: acc
        else acc
      ) inner_env.vars [] in
    (* Also export type names and constructors from public DMod into outer scope.
       Types defined in a module (e.g. IOList, Option) are referred to by their
       bare name throughout user code, not prefixed.
       Opaque types listed in the sig have their constructors hidden: only the
       type name is exported, not the constructors (encapsulation). *)
    let proof_cap_type_keys = List.map fst inner_env.proof_caps in
    let new_types = StrMap.filter (fun k _ ->
        List.mem k pub_set || List.mem k proof_cap_type_keys
      ) inner_env.types in
    let new_ctors = StrMap.filter_map (fun _k cis ->
        let filtered = List.filter (fun ci ->
          (* Hide constructors for opaque types declared in the sig *)
          not (List.mem ci.ci_type opaque_types) &&
          (* Export constructor only if its parent type is public AND
             the constructor itself is explicitly marked Public. *)
          List.mem ci.ci_type pub_set && ci.ci_vis = Ast.Public
        ) cis in
        match filtered with [] -> None | _ -> Some filtered
      ) inner_env.ctors in
    (* Also register qualified ctor keys "ModName.CtorName" so that the
       desugared form ECon("ModName.CtorName") can be resolved directly from
       env.ctors without going through Module_registry.  This is critical for
       REPL-defined modules which are never added to the global registry, and
       also makes qualified ctor lookup consistent for all modules. *)
    let qual_ctors = StrMap.fold (fun ctor_name cis acc ->
        StrMap.add (name.txt ^ "." ^ ctor_name) cis acc
      ) new_ctors StrMap.empty in
    (* Collect this module's declared capabilities for transitive enforcement *)
    let inner_needs = List.concat_map (function
        | Ast.DNeeds (caps, _) -> List.map cap_path_of_names caps
        | _ -> []) decls in
    (* Also export record field layouts for public record types so that
       cross-module field access (e.g. conn.fd) works correctly.
       Export both the local name ("JobRow") and the fully-qualified name
       ("Conduit.JobRow") so that type annotations written with the module
       prefix also resolve to a structural TRecord instead of opaque TCon. *)
    let new_records = StrMap.fold (fun k v acc ->
        if List.mem k pub_set then
          StrMap.add (name.txt ^ "." ^ k) v (StrMap.add k v acc)
        else acc
      ) inner_env.records StrMap.empty in
    (* Validate capability invariants for this nested module if declared *)
    if inner_env.no_panic_mod then
      check_no_panic_module env.errors inner_env decls;
    if inner_env.pure_mod then
      check_pure_module env.errors inner_env decls;
    if inner_env.no_extern_mod then
      check_no_extern_module env.errors inner_env decls;
    if inner_env.deterministic_mod then
      check_deterministic_module env.errors inner_env decls;
    let env' = bind_vars new_names env in
    let no_panic_modules' =
      if inner_env.no_panic_mod then name.txt :: env'.no_panic_modules
      else env'.no_panic_modules
    in
    { env' with
      types   = StrMap.union (fun _k v _ -> Some v) new_types env'.types;
      ctors   = (let all_new = StrMap.union (fun _k a _ -> Some a) qual_ctors new_ctors in
                  StrMap.union (fun _k new_cis old_cis ->
                    (* Merge lists; new_cis are more local, so prepend them *)
                    let merged = List.fold_right (fun ci acc ->
                      if List.exists (fun c -> c.ci_type = ci.ci_type) acc then acc
                      else ci :: acc) new_cis old_cis in
                    Some merged) all_new env'.ctors);
      records = StrMap.union (fun _k v _ -> Some v) new_records env'.records;
      module_caps = (name.txt, inner_needs) :: env'.module_caps;
      proof_caps = inner_env.proof_caps;
      always_linear_types = inner_env.always_linear_types;
      no_panic_modules = no_panic_modules';
      local_mods =
        (if priv_members = [] then env'.local_mods
         else StrMap.add name.txt priv_members env'.local_mods) }

  | Ast.DProtocol (name, pdef, sp) ->
    (* Register the protocol and validate structural well-formedness. *)
    if StrMap.mem name.txt env.protocols then
      Err.error env.errors ~span:sp
        (Printf.sprintf "Duplicate protocol definition `%s`." name.txt);
    if pdef.proto_steps = [] then
      Err.warning env.errors ~span:sp
        (Printf.sprintf "Protocol `%s` has no steps — it describes no communication."
           name.txt);
    (* Validate each step for structural correctness. *)
    let rec validate_step = function
      | Ast.ProtoMsg (sender, receiver, msg_ty) ->
        if sender.txt = receiver.txt then
          Err.error env.errors ~span:sender.span
            (Printf.sprintf
               "Protocol `%s`: participant `%s` cannot send a message to itself."
               name.txt sender.txt);
        let tvars = ref [] in
        ignore (surface_ty env ~tvars msg_ty)
      | Ast.ProtoLoop steps ->
        if steps = [] then
          Err.error env.errors ~span:sp
            (Printf.sprintf "Protocol `%s`: a `loop` block must contain at least one step."
               name.txt);
        List.iter validate_step steps
      | Ast.ProtoChoice (participant, branches) ->
        if List.length branches < 2 then
          Err.error env.errors ~span:participant.span
            (Printf.sprintf
               "Protocol `%s`: `choice` by `%s` must have at least 2 branches."
               name.txt participant.txt);
        List.iter (fun (_, steps) -> List.iter validate_step steps) branches
    in
    List.iter validate_step pdef.proto_steps;
    (* Project the protocol onto each role and verify duality. *)
    let projections = project_protocol env ~span:sp ~proto_name:name.txt pdef in
    let participants = List.map fst projections in
    if participants <> [] && List.length participants < 2 then
      Err.warning env.errors ~span:sp
        (Printf.sprintf
           "Protocol `%s` only names one participant (`%s`). \
            A protocol usually involves at least two parties."
           name.txt (List.hd participants));
    (* Hint if participant names are not known actor/type names. *)
    List.iter (fun p ->
        let is_actor = StrMap.exists (fun _ cis -> List.exists (fun ci -> ci.ci_type = p) cis) env.ctors in
        let is_type  = StrMap.mem p env.types in
        if not (is_actor || is_type) then
          Err.hint env.errors ~span:sp
            (Printf.sprintf
               "Protocol `%s`: participant `%s` is not a known actor or type. \
                Did you forget to declare `actor %s ...`?"
               name.txt p p)
      ) participants;
    (* Check against previously-declared protocols for cross-protocol conflicts. *)
    let pi = { pi_def = pdef; pi_projections = projections; pi_span = sp } in
    let new_env = { env with protocols = StrMap.add name.txt pi env.protocols } in
    (if StrMap.cardinal new_env.protocols > 1 then
       StrMap.iter (fun other_name other_pi ->
           if other_name <> name.txt then begin
             let other_parts = List.map fst other_pi.pi_projections in
             if List.length participants >= 2 && List.length other_parts >= 2
             && List.sort compare participants = List.sort compare other_parts then
               Err.hint env.errors ~span:sp
                 (Printf.sprintf
                    "Protocol `%s` involves the same participants as `%s`. \
                     If these are dual protocols (one for each direction), \
                     this is expected. Otherwise, consider merging them."
                    name.txt other_name)
           end
         ) env.protocols);
    new_env

  | Ast.DSig (name, sdef, _sp) ->
    (* Store the signature so DMod can check conformance later. *)
    { env with sigs = (name.txt, sdef) :: env.sigs }

  | Ast.DInterface (idef, _sp) ->
    (* Register the interface definition for impl validation, and register
       each method as a polymorphic function binding in scope.
       Methods get CInterface constraints so call sites verify the type
       satisfies the interface (discharged in discharge_constraints). *)
    let env' = { env with interfaces = StrMap.add idef.iface_name.txt idef env.interfaces } in
    List.fold_left (fun env (m : Ast.method_decl) ->
        (* Use level+1 so the interface type parameter gets quantified by generalize. *)
        let a = fresh_var (env.level + 1) in
        let tvars = ref [(idef.iface_param.txt, a)] in
        let ty = surface_ty env ~tvars m.md_ty in
        let a_id = match a with
          | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
          | _ -> 0
        in
        (* Build scheme: ∀a. [CInterface(iface, a)] => method_ty *)
        let base_sch = generalize env.level ty in
        let sch = match base_sch with
          | Poly (ids, cs, t) ->
            Poly (ids, CInterface (idef.iface_name.txt, a) :: cs, t)
          | Mono t ->
            Poly ([a_id], [CInterface (idef.iface_name.txt, a)], t)
        in
        (* Register both unqualified (eq) and qualified (Eq.eq) names so
           that Eq.eq(x, y) resolves via the EField module-path lookup. *)
        let qualified = idef.iface_name.txt ^ "." ^ m.md_name.txt in
        let env1 = bind_var m.md_name.txt sch env in
        bind_var qualified sch env1
      ) env' idef.iface_methods

  | Ast.DImpl (idef, _sp) ->
    (* Instantiate the impl type, sharing tvars so the 'when' constraints
       can reference the same type variables as the impl type itself. *)
    let tvars = ref [] in
    let inst_ty = surface_ty env ~tvars idef.impl_ty in
    (* Register this implementation so CInterface constraints can be discharged. *)
    let env_with_impl = { env with impls =
      (let key = idef.impl_iface.txt in
       let lst = Option.value ~default:[] (StrMap.find_opt key env.impls) in
       StrMap.add key (inst_ty :: lst) env.impls) } in
    (* Check 'when' constraints: each C(T) must already be implemented. *)
    List.iter (fun ((cname : Ast.name), ctys) ->
        match List.map (surface_ty env ~tvars) ctys with
        | [cty] ->
          let cty = repr cty in
          (match cty with
           | TVar _ -> ()   (* Polymorphic param — checked at use sites *)
           | _ ->
             if not (match StrMap.find_opt cname.txt env.impls with
                 | None -> false
                 | Some tys -> List.exists (fun impl_ty ->
                     impl_matches_ty (repr impl_ty) cty) tys) then
               Err.error env.errors ~span:cname.span
                 (Printf.sprintf
                    "Constraint `%s(%s)` in `when` clause is not satisfied.\n\
                     No `impl %s(%s)` is in scope."
                    cname.txt (pp_ty cty) cname.txt (pp_ty cty)))
        | _ -> ()
      ) idef.impl_constraints;
    (* Validate each method against the interface declaration. *)
    (match StrMap.find_opt idef.impl_iface.txt env.interfaces with
     | None ->
       (* For derive-generated pseudo-interfaces (e.g. JsonTo, JsonFrom),
          skip interface validation but still type-check and bind each method
          as a standalone function in the environment. *)
       let is_json_derive =
         String.length idef.impl_iface.txt >= 4
         && String.sub idef.impl_iface.txt 0 4 = "Json"
       in
       if not is_json_derive then
         Err.error env.errors ~span:idef.impl_iface.span
           (Printf.sprintf "Unknown interface `%s` — is it declared above this impl?"
              idef.impl_iface.txt)
     | Some interface ->
       (* Check superclass constraints: each required superclass must already have an impl *)
       let sc_tvars = ref [(interface.iface_param.txt, inst_ty)] in
       List.iter (fun ((sc_name : Ast.name), sc_tys) ->
           let sc_inst_tys = List.map (surface_ty env ~tvars:sc_tvars) sc_tys in
           (match sc_inst_tys with
            | [sc_inst_ty] ->
              let sc_inst_ty = repr sc_inst_ty in
              (match sc_inst_ty with
               | TVar _ -> ()  (* polymorphic param — checked at use sites *)
               | _ ->
                 if not (match StrMap.find_opt sc_name.txt env.impls with
                     | None -> false
                     | Some tys -> List.exists (fun impl_ty ->
                         impl_matches_ty (repr impl_ty) sc_inst_ty) tys) then
                   Err.error env.errors ~span:idef.impl_iface.span
                     (Printf.sprintf
                        "Cannot implement `%s(%s)`: required superclass `%s(%s)` is not \
                         satisfied.\n\
                         Add `impl %s(%s) do ... end` before this implementation."
                        idef.impl_iface.txt (pp_ty inst_ty)
                        sc_name.txt (pp_ty sc_inst_ty)
                        sc_name.txt (pp_ty sc_inst_ty)))
            | _ -> ()  (* multi-param superclasses not yet supported *)
           )
         ) interface.iface_superclasses;
       (* Check all required methods are provided (error for non-default missing) *)
       List.iter (fun (iface_m : Ast.method_decl) ->
           let provided = List.exists
             (fun ((mname : Ast.name), _) -> mname.txt = iface_m.md_name.txt)
             idef.impl_methods
           in
           if not provided && iface_m.md_default = None then
             Err.error env.errors ~span:idef.impl_iface.span
               (Printf.sprintf
                  "Missing method `%s` in `impl %s(%s)`.\n\
                   Interface `%s` requires this method to be implemented."
                  iface_m.md_name.txt idef.impl_iface.txt (pp_ty inst_ty)
                  idef.impl_iface.txt)
         ) interface.iface_methods;
       List.iter (fun ((mname : Ast.name), (def : Ast.fn_def)) ->
           match List.find_opt
                   (fun (m : Ast.method_decl) -> m.md_name.txt = mname.txt)
                   interface.iface_methods with
           | None ->
             Err.error env.errors ~span:mname.span
               (Printf.sprintf "Interface `%s` does not declare a method `%s`."
                  idef.impl_iface.txt mname.txt)
           | Some iface_method ->
             (* Expected type: substitute interface param → concrete impl type *)
             let expected_ty =
               surface_ty env
                 ~tvars:(ref [(interface.iface_param.txt, inst_ty)])
                 iface_method.md_ty
             in
             (* Infer the method body's actual type.
                For injected default methods (zero params, body = default expr),
                use check_expr directly against the expected type. *)
             (match def.fn_clauses with
              | [{ fc_params = []; fc_body; _ }] when iface_method.md_default <> None ->
                (* Default method injected by desugar — just check the body expr *)
                check_expr env fc_body expected_ty
                  ~reason:(Some (RBuiltin
                    (Printf.sprintf "default `%s` in interface `%s`"
                       mname.txt idef.impl_iface.txt)))
              | _ ->
                let actual_sch = check_fn env def _sp in
                let actual_ty = instantiate env.level env actual_sch in
                unify env ~span:mname.span actual_ty expected_ty
                  ~reason:(Some (RBuiltin
                     (Printf.sprintf "`%s` in `impl %s` must match the interface signature"
                        mname.txt idef.impl_iface.txt))))
         ) idef.impl_methods);
    (* For Json derive pseudo-interfaces, to_json/from_json are already bound
       as polymorphic builtins in the base environment (∀a b. a -> b).
       We still type-check each method body for local correctness, but we do NOT
       re-bind the name — that would shadow the polymorphic builtin with a
       monomorphic version, breaking modules that derive Json for multiple types. *)
    let is_json_derive =
      String.length idef.impl_iface.txt >= 4
      && String.sub idef.impl_iface.txt 0 4 = "Json"
    in
    if is_json_derive then begin
      (* Type-check the method bodies for correctness, but discard the schemes *)
      List.iter (fun ((_mname : Ast.name), (def : Ast.fn_def)) ->
          ignore (check_fn env def _sp)
        ) idef.impl_methods;
      discharge_constraints env_with_impl _sp;
      env_with_impl
    end else begin
      discharge_constraints env_with_impl _sp;
      env_with_impl
    end

  | Ast.DExtern (edef, _sp) ->
    (* Register each foreign function as a monomorphic binding. *)
    List.fold_left (fun env (ef : Ast.extern_fn) ->
        let tvars = ref [] in
        let param_tys = List.map (fun (_, t) -> surface_ty env ~tvars t) ef.ef_params in
        let ret_ty = surface_ty env ~tvars ef.ef_ret_ty in
        let ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
        bind_var ef.ef_name.txt (Mono ty) env
      ) env edef.ext_fns

  | Ast.DUse (ud, sp) ->
    let mod_str = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
    let prefix = mod_str ^ "." in
    (match ud.use_sel with
     | Ast.UseSingle ->
       (* Import the module path as an accessible prefix — no new bindings needed *)
       env
     | Ast.UseAll ->
       (* Find all vars with "Prefix.name" and rebind them as plain "name".
          Skip names the current module defines itself (env.local_fns):
          the local definition shadows the bulk import — rebinding would
          clobber the local fn's pass-1 placeholder and make check_fn unify
          the local definition against the imported fn's type. *)
       let matching = StrMap.fold (fun k sch acc ->
           let plen = String.length prefix in
           if String.length k > plen
              && String.sub k 0 plen = prefix
           then
             let short = String.sub k plen (String.length k - plen) in
             if StrMap.mem short env.local_fns then acc
             else (short, sch) :: acc
           else acc) env.vars [] in
       (* Import interfaces from the module prefix into scope as short names *)
       let env = StrMap.fold (fun k idef e ->
           let plen = String.length prefix in
           if String.length k > plen
              && String.sub k 0 plen = prefix
           then
             let short = String.sub k plen (String.length k - plen) in
             if StrMap.mem short e.interfaces then e
             else { e with interfaces = StrMap.add short idef e.interfaces }
           else e) env.interfaces env in
       (* Track for unused-import warning: warn if nothing from this module is
          used.  A QUALIFIED use (HttpServer.query_string) must count too —
          matching only the rebound short names produced false "unused import"
          warnings on modules that are used exclusively via qualified calls
          (common in wrapper modules whose own fns shadow the short names). *)
       if matching <> [] then begin
         let short_names = List.map fst matching in
         let entry = { ie_span = sp
                     ; ie_desc = Printf.sprintf
                         "Unused import: nothing from `%s` is used.\n\
                          Remove this import or use something from it." mod_str
                     ; ie_matches = (fun name ->
                         List.mem name short_names
                         || name = mod_str
                         || (String.length name > String.length prefix
                             && String.sub name 0 (String.length prefix) = prefix))
                     ; ie_used = ref false } in
         env.import_tracker := entry :: !(env.import_tracker)
       end;
       bind_vars matching env
     | Ast.UseNames names ->
       List.fold_left (fun env n ->
           match StrMap.find_opt (prefix ^ n.Ast.txt) env.vars with
           | Some sch ->
             (* Track for unused-import warning: warn if this specific name is unused. *)
             let entry = { ie_span = n.Ast.span
                         ; ie_desc = Printf.sprintf
                             "Unused import `%s` from `%s`.\n\
                              Remove it from the import list or use it." n.Ast.txt mod_str
                         ; ie_matches = (fun name -> name = n.Ast.txt)
                         ; ie_used = ref false } in
             env.import_tracker := entry :: !(env.import_tracker);
             bind_var n.Ast.txt sch env
           | None ->
             Err.error env.errors ~span:n.Ast.span
               (Printf.sprintf "Module `%s` does not export `%s`."
                  mod_str n.Ast.txt);
             env) env names
     | Ast.UseExcept excluded ->
       let excl_set = List.map (fun n -> n.Ast.txt) excluded in
       let matching = StrMap.fold (fun k sch acc ->
           let plen = String.length prefix in
           if String.length k > plen
              && String.sub k 0 plen = prefix
           then
             let short = String.sub k plen (String.length k - plen) in
             if List.mem short excl_set then acc
             (* Local definitions shadow bulk imports — see UseAll. *)
             else if StrMap.mem short env.local_fns then acc
             else (short, sch) :: acc
           else acc) env.vars [] in
       (* Track for unused-import warning: warn if nothing from this module is
          used.  A QUALIFIED use (HttpServer.query_string) must count too —
          matching only the rebound short names produced false "unused import"
          warnings on modules that are used exclusively via qualified calls
          (common in wrapper modules whose own fns shadow the short names). *)
       if matching <> [] then begin
         let short_names = List.map fst matching in
         let entry = { ie_span = sp
                     ; ie_desc = Printf.sprintf
                         "Unused import: nothing from `%s` is used.\n\
                          Remove this import or use something from it." mod_str
                     ; ie_matches = (fun name ->
                         List.mem name short_names
                         || name = mod_str
                         || (String.length name > String.length prefix
                             && String.sub name 0 (String.length prefix) = prefix))
                     ; ie_used = ref false } in
         env.import_tracker := entry :: !(env.import_tracker)
       end;
       bind_vars matching env)

  | Ast.DAlias (ad, sp) ->
    let orig_prefix = String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) ^ "." in
    let short_name = ad.alias_name.Ast.txt in
    let short_prefix = short_name ^ "." in
    (* Re-export all "Orig.name" as "Short.name" *)
    let new_bindings = StrMap.fold (fun k sch acc ->
        let plen = String.length orig_prefix in
        if String.length k > plen && String.sub k 0 plen = orig_prefix then
          let rest = String.sub k plen (String.length k - plen) in
          (short_prefix ^ rest, sch) :: acc
        else acc) env.vars [] in
    (* Track for unused-alias warning: warn if no "Short.*" name is referenced. *)
    if new_bindings <> [] then begin
      let orig_str = String.concat "." (List.map (fun n -> n.Ast.txt) ad.alias_path) in
      let entry = { ie_span = sp
                  ; ie_desc = Printf.sprintf
                      "Unused alias `%s` for `%s`.\n\
                       Remove this alias or use it to qualify a name." short_name orig_str
                  ; ie_matches = (fun name ->
                      let plen = String.length short_prefix in
                      (String.length name >= plen && String.sub name 0 plen = short_prefix)
                      || name = short_name)
                  ; ie_used = ref false } in
      env.import_tracker := entry :: !(env.import_tracker)
    end;
    bind_vars new_bindings env

  | Ast.DNeeds (caps, _sp) ->
    (* Record declared capability paths in env for DMod validation.
       Each path is a list of names e.g. ["IO"; "Network"] → "IO.Network" *)
    let paths = List.map (fun names ->
        String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names)
      ) caps in
    { env with mod_needs = paths @ env.mod_needs }

  | Ast.DProofCap (name, _sp) ->
    (* Register proof cap: full qualified path → declaring module name.
       Also register the cap name as a 0-arity type so Cap(Mod.Name) is
       valid in type annotations (just like Cap(IO.Network)). *)
    let full_path =
      if env.current_module = "" then name.txt
      else env.current_module ^ "." ^ name.txt
    in
    { env with
      proof_caps = (full_path, env.current_module) :: env.proof_caps;
      types = StrMap.add full_path 0 env.types }

  | Ast.DAlwaysLinearType (vis, name, params, typedef, sp) ->
    (* Process the type definition exactly like DType (registers constructors, records, etc.),
       then register both the bare name and the qualified name in always_linear_types.
       TCon internals use the bare name (e.g. "Handle"), while type annotations after module
       export may use the qualified name (e.g. "Handle.Handle") — store both so List.mem
       matches regardless of which form repr produces at a given call site. *)
    let bare_name = name.txt in
    let qual_name =
      if env.current_module = "" then name.txt
      else env.current_module ^ "." ^ name.txt
    in
    let env1 = check_decl env (Ast.DType (vis, name, params, typedef, sp)) in
    let names = if bare_name = qual_name then [bare_name]
                else [bare_name; qual_name] in
    { env1 with always_linear_types = names @ env1.always_linear_types }

  | Ast.DApp _ ->
    (* DApp is desugared to DFn(__app_init__) before typecheck; reaching here is a bug. *)
    env

  | Ast.DDeriving _ ->
    (* DDeriving is expanded to DImpl blocks by the desugar pass; should not reach here. *)
    env

  | Ast.DTest (tdef, sp) ->
    (* Typecheck the test body; it must be Unit. *)
    check_expr env tdef.test_body t_unit
      ~reason:(Some (RBuiltin (Printf.sprintf "test body of \"%s\" must produce Unit" tdef.test_name)));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DDescribe (_name, decls, sp) ->
    let env' = List.fold_left check_decl env decls in
    Hashtbl.replace env'.type_map sp t_unit;
    env'

  | Ast.DSetup (body, sp) ->
    check_expr env body t_unit ~reason:(Some (RBuiltin "setup body must produce Unit"));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DSetupAll (body, sp) ->
    check_expr env body t_unit ~reason:(Some (RBuiltin "setup_all body must produce Unit"));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DTransitions (handle_ty, arms, sp) ->
    let handle_name = handle_ty.txt in
    (* Extract the last (state) type argument from Handle(args).
       Handles both single-param Handle(s) and two-param Handle(r,s). *)
    let last_arg = function
      | [] -> None
      | args -> Some (repr (List.nth args (List.length args - 1)))
    in
    (* Validate each declared transition arm's via function. *)
    let declared_vias = List.filter_map (fun (a : Ast.transition) ->
        let via_name = a.tr_via.txt in
        let sch_opt =
          match lookup_var via_name env with
          | Some s -> Some s
          | None ->
            let qname = if env.current_module = "" then via_name
                        else env.current_module ^ "." ^ via_name in
            lookup_var qname env
        in
        match sch_opt with
        | None ->
          Err.error env.errors ~span:a.tr_via.span
            (Printf.sprintf
               "Via function `%s` is not defined in this module. \
                Expected: fn %s(h : %s(%s)) : %s(%s) do ... end"
               via_name via_name handle_name a.tr_from.txt
               handle_name a.tr_to.txt);
          None
        | Some sch ->
          let ty = repr (instantiate env.level env sch) in
          (match ty with
           | TArrow (TCon (hn, param_args), ret_t) when hn = handle_name ->
             (match last_arg param_args with
              | Some (TCon (s, []) as from_t) when s <> a.tr_from.txt ->
                Err.error env.errors ~span:a.tr_span
                  (Printf.sprintf
                     "Via function `%s` takes state `%s` but transition declares from-state `%s`."
                     via_name (pp_ty from_t) a.tr_from.txt)
              | _ -> ());
             (match repr ret_t with
              | TCon (hn2, ret_args) when hn2 = handle_name ->
                (match last_arg ret_args with
                 | Some (TCon (s, []) as to_t) when s <> a.tr_to.txt ->
                   Err.error env.errors ~span:a.tr_span
                     (Printf.sprintf
                        "Via function `%s` returns state `%s` but transition declares to-state `%s`."
                        via_name (pp_ty to_t) a.tr_to.txt)
                 | _ -> ())
              | _ ->
                Err.error env.errors ~span:a.tr_span
                  (Printf.sprintf
                     "Via function `%s` has return type `%s`, expected `%s(_, %s)`."
                     via_name (pp_ty ret_t) handle_name a.tr_to.txt))
           | TArrow (param_t, _) ->
             Err.error env.errors ~span:a.tr_via.span
               (Printf.sprintf
                  "Via function `%s` takes `%s`, expected `%s(..., %s)`."
                  via_name (pp_ty param_t) handle_name a.tr_from.txt)
           | _ ->
             Err.error env.errors ~span:a.tr_via.span
               (Printf.sprintf
                  "Via function `%s` has type `%s`, expected `%s(..., %s) -> %s(..., %s)`."
                  via_name (pp_ty ty) handle_name a.tr_from.txt handle_name a.tr_to.txt));
          Some via_name
      ) arms in
    (* Warn about local functions whose type looks like a transition but are
       not declared in this transitions block — suggest adding them. *)
    StrMap.iter (fun fn_name sch ->
        if not (StrMap.mem fn_name env.local_fns) then ()
        else if List.mem fn_name declared_vias then ()
        else begin
          let ty = repr (instantiate env.level env sch) in
          match ty with
          | TArrow (TCon (hn, param_args), TCon (hn2, ret_args))
            when hn = handle_name && hn2 = handle_name ->
            (match last_arg param_args, last_arg ret_args with
             | Some from_t, Some to_t ->
               let from_s = pp_ty from_t in
               let to_s   = pp_ty to_t in
               if from_s <> to_s then
                 Err.warning env.errors ~span:sp
                   (Printf.sprintf
                      "`%s` looks like a transition function (`%s` -> `%s`) \
                       but is not declared in `transitions %s`. \
                       Consider adding:\n    %s: %s -> %s via %s"
                      fn_name from_s to_s handle_name
                      (String.capitalize_ascii from_s) from_s to_s fn_name)
             | _ -> ())
          | _ -> ()
        end
      ) env.vars;
    env

  | Ast.DOpts (opts, _sp) ->
    let env = if List.mem "no_panic"      opts then { env with no_panic_mod      = true } else env in
    let env = if List.mem "pure"          opts then { env with pure_mod          = true } else env in
    let env = if List.mem "no_extern"     opts then { env with no_extern_mod     = true } else env in
    let env = if List.mem "deterministic" opts then { env with deterministic_mod = true } else env in
    env

  | Ast.DSatisfy _ ->
    (* DSatisfy is expanded to DImpl blocks by the desugar pass; nothing to typecheck here. *)
    env

(** Emit warnings for any imports or aliases that were never referenced. *)
let warn_unused_imports env =
  List.iter (fun ie ->
    if not !(ie.ie_used) then
      Err.warning_with_code env.errors ~span:ie.ie_span ~code:"unused_import" ie.ie_desc
  ) !(env.import_tracker)

(* =================================================================
   §16  Tail-call enforcement
   ================================================================= *)

(** Collect all names from [fn_names] that are called directly (not through
    lambdas or local [ELetFn] bodies) in [e].  Used to build the call graph
    for SCC / mutual-recursion detection. *)
let rec collect_direct_fn_calls (fn_names : StringSet.t) (e : Ast.expr) : StringSet.t =
  match e with
  | Ast.EApp (Ast.EVar fn, args, _) ->
    let self = if StringSet.mem fn.txt fn_names then StringSet.singleton fn.txt
               else StringSet.empty in
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) self args
  | Ast.EApp (f, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) (collect_direct_fn_calls fn_names f) args
  | Ast.ECon (_, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) StringSet.empty args
  | Ast.EIf (c, t, f, _) ->
    StringSet.union (collect_direct_fn_calls fn_names c)
      (StringSet.union (collect_direct_fn_calls fn_names t)
                       (collect_direct_fn_calls fn_names f))
  | Ast.ECond (arms, _) ->
    List.fold_left (fun acc (ce, be) ->
      StringSet.union acc
        (StringSet.union (collect_direct_fn_calls fn_names ce)
                         (collect_direct_fn_calls fn_names be))
    ) StringSet.empty arms
  | Ast.EMatch (scrut, branches, _) ->
    List.fold_left (fun acc br ->
      let g = Option.fold ~none:StringSet.empty
                ~some:(collect_direct_fn_calls fn_names) br.Ast.branch_guard in
      StringSet.union acc
        (StringSet.union g (collect_direct_fn_calls fn_names br.Ast.branch_body))
    ) (collect_direct_fn_calls fn_names scrut) branches
  | Ast.EBlock (exprs, _) ->
    List.fold_left (fun acc ex ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) StringSet.empty exprs
  | Ast.ELet (b, _) -> collect_direct_fn_calls fn_names b.Ast.bind_expr
  | Ast.ELetFn (_, _, _, _, _) -> StringSet.empty   (* new scope *)
  | Ast.ELam (_, _, _)         -> StringSet.empty   (* new scope *)
  | Ast.ETuple (es, _) ->
    List.fold_left (fun acc ex ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) StringSet.empty es
  | Ast.ERecord (fields, _) ->
    List.fold_left (fun acc (_, ex) ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) StringSet.empty fields
  | Ast.ERecordUpdate (base, fields, _) ->
    List.fold_left (fun acc (_, ex) ->
      StringSet.union acc (collect_direct_fn_calls fn_names ex)
    ) (collect_direct_fn_calls fn_names base) fields
  | Ast.EField (ex, _, _)  -> collect_direct_fn_calls fn_names ex
  | Ast.EAnnot (ex, _, _)  -> collect_direct_fn_calls fn_names ex
  | Ast.EPipe (l, r, _) ->
    StringSet.union (collect_direct_fn_calls fn_names l)
                    (collect_direct_fn_calls fn_names r)
  | Ast.EAtom (_, args, _) ->
    List.fold_left (fun acc a ->
      StringSet.union acc (collect_direct_fn_calls fn_names a)
    ) StringSet.empty args
  | Ast.ESend (a, b, _) ->
    StringSet.union (collect_direct_fn_calls fn_names a)
                    (collect_direct_fn_calls fn_names b)
  | Ast.ESpawn (ex, _)       -> collect_direct_fn_calls fn_names ex
  | Ast.EDbg (Some ex, _)    -> collect_direct_fn_calls fn_names ex
  | Ast.ELetQ (_, r, c, _) ->
    StringSet.union (collect_direct_fn_calls fn_names r)
                    (collect_direct_fn_calls fn_names c)
  | Ast.EAssert (ex, _) -> collect_direct_fn_calls fn_names ex
  | Ast.ESigil (_, content, _) -> collect_direct_fn_calls fn_names content
  | Ast.ELit _ | Ast.EVar _ | Ast.EHole _ | Ast.EResultRef _
  | Ast.EDbg (None, _)       -> StringSet.empty

(** Tarjan's SCC algorithm.  [adj] is a list of (name, called-names) pairs.
    Returns each SCC as a list; non-recursive singletons are included. *)
let find_sccs (adj : (string * StringSet.t) list) : string list list =
  let idx_ctr   = ref 0 in
  let stk       = ref [] in
  let on_stk    = Hashtbl.create 16 in
  let idx_map   = Hashtbl.create 16 in
  let lowlink   = Hashtbl.create 16 in
  let sccs      = ref [] in
  let rec sc v =
    let vi = !idx_ctr in
    Hashtbl.replace idx_map  v vi;
    Hashtbl.replace lowlink  v vi;
    incr idx_ctr;
    stk := v :: !stk;
    Hashtbl.replace on_stk v true;
    let neighbors = match List.assoc_opt v adj with
      | Some s -> StringSet.elements s | None -> [] in
    List.iter (fun w ->
      if not (Hashtbl.mem idx_map w) then begin
        sc w;
        let lv = Hashtbl.find lowlink v in
        let lw = Hashtbl.find lowlink w in
        Hashtbl.replace lowlink v (min lv lw)
      end else if Hashtbl.mem on_stk w then begin
        let lv = Hashtbl.find lowlink v in
        let iw = Hashtbl.find idx_map  w in
        Hashtbl.replace lowlink v (min lv iw)
      end
    ) neighbors;
    if Hashtbl.find lowlink v = Hashtbl.find idx_map v then begin
      let scc = ref [] in
      let go  = ref true in
      while !go do
        match !stk with
        | [] -> go := false
        | w :: rest ->
          stk := rest;
          Hashtbl.remove on_stk w;
          scc := w :: !scc;
          if w = v then go := false
      done;
      sccs := !scc :: !sccs
    end
  in
  List.iter (fun (v, _) ->
    if not (Hashtbl.mem idx_map v) then sc v
  ) adj;
  !sccs

let is_infix_op name =
  match name with
  | "+" | "-" | "*" | "/" | "%" | "<" | ">" | "<=" | ">="
  | "==" | "!=" | "&&" | "||" | "+." | "-." | "*." | "/." -> true
  | _ -> false

(** Collect all variable names bound by a pattern (used to find structurally
    smaller variables introduced by pattern matching). *)
let rec collect_pattern_vars (pat : Ast.pattern) : StringSet.t =
  match pat with
  | Ast.PatWild _ | Ast.PatLit _ -> StringSet.empty
  | Ast.PatVar v -> StringSet.singleton v.txt
  | Ast.PatCon (_, pats) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatAtom (_, pats, _) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatTuple (pats, _) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats
  | Ast.PatRecord (fields, _) ->
    List.fold_left (fun acc (_, p) -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty fields
  | Ast.PatAs (p, v, _) -> StringSet.add v.txt (collect_pattern_vars p)

(** True if [expr] is provably structurally smaller than some function parameter.
    - [params]: the set of function parameter variable names.
    - [smaller]: variables known to be sub-components of a parameter (from pattern matching).
    Recognises:
      1. A pattern-bound sub-component: [EVar v] where [v ∈ smaller].
      2. Arithmetic reduction: [v - k] or [v / k] where [v ∈ params ∪ smaller].
      3. List element access: [list_nth_safe(xs,i)], [List.nth(xs,i)] where xs is smaller.
      4. Nullary constructor (e.g. HEmpty, Nil): structurally minimal. *)
let rec is_structurally_smaller (params : StringSet.t) (smaller : StringSet.t) (expr : Ast.expr) : bool =
  match expr with
  | Ast.EVar v -> StringSet.mem v.txt smaller
  | Ast.EApp (Ast.EVar op, [lhs; _], _) when op.txt = "-" || op.txt = "/" ->
    (match lhs with
     | Ast.EVar v -> StringSet.mem v.txt params || StringSet.mem v.txt smaller
     | _ -> false)
  (* List element accessor: element is structurally smaller than the list *)
  | Ast.EApp (Ast.EVar fn, arg :: _, _)
    when List.mem fn.txt ["list_nth_safe"; "list_nth"; "List.nth"; "List.hd"; "List.head"] ->
    is_structurally_smaller params smaller arg
  (* Nullary constructor (e.g. HEmpty, Nil): always structurally minimal *)
  | Ast.ECon (_, [], _) -> true
  | _ -> false

(** True if [expr] is a function parameter or a known-smaller variable — meaning
    pattern-bound sub-components of this scrutinee can be treated as smaller. *)
let scrutinee_is_param_or_smaller (params : StringSet.t) (smaller : StringSet.t) (expr : Ast.expr) : bool =
  match expr with
  | Ast.EVar v -> StringSet.mem v.txt params || StringSet.mem v.txt smaller
  | _ -> false

(** Verify that every call to any name in [recursive_names] within [body]
    is either in tail position OR is structurally recursive (guaranteed to
    terminate because every argument is provably smaller than a parameter).
    Emits [Error] diagnostics only for truly unbounded non-tail recursion.
    [fn_name] is the enclosing function (for readable error messages).
    [fn_params] is the set of parameter variable names for [fn_name]. *)
let rec check_tail_position
    (errors : Err.ctx)
    (recursive_names : StringSet.t)
    (fn_name : string)
    (fn_params : StringSet.t)
    (body : Ast.expr) : unit =
  (* [smaller] accumulates variables known to be structurally smaller than a
     function parameter (introduced by pattern-matching on a parameter). *)
  let rec chk in_tail (smaller : StringSet.t) ctx expr =
    match expr with
    (* ── Recursive call ── *)
    | Ast.EApp (Ast.EVar fn, args, sp) when StringSet.mem fn.txt recursive_names ->
      if not in_tail then begin
        (* Allow if at least one argument is provably structurally smaller:
           this covers structural recursion on sub-trees/sub-lists and
           arithmetic reductions like n-1, n-2. *)
        let is_structural =
          List.exists (is_structurally_smaller fn_params smaller) args
        in
        if not is_structural then
          Err.error errors ~span:sp
            (Printf.sprintf
               "Function `%s`: recursive call to `%s` is not in tail position \
                (%s).\n\
                Hint: Consider using an accumulator parameter."
               fn_name fn.txt ctx)
        else begin
          (* Structural recursion: warn but allow — distinguish arithmetic
             reductions (n-1, n-2) from pattern-bound sub-components. *)
          let is_arithmetic = List.exists (fun arg ->
            match arg with
            | Ast.EApp (Ast.EVar op, [lhs; _], _) when op.txt = "-" ->
              (match lhs with
               | Ast.EVar v ->
                 StringSet.mem v.txt fn_params || StringSet.mem v.txt smaller
               | _ -> false)
            | _ -> false
          ) args in
          if is_arithmetic then
            Err.warning errors ~span:sp
              (Printf.sprintf
                 "Warning: function `%s` is structurally recursive but not \
                  tail-recursive. Consider using an accumulator parameter \
                  for O(n) performance."
                 fn_name)
          else
            Err.warning errors ~span:sp
              (Printf.sprintf
                 "Warning: function `%s` is structurally recursive but not \
                  tail-recursive. This is safe for bounded input but uses \
                  O(depth) stack space."
                 fn_name)
        end
      end;
      List.iteri (fun i arg ->
        chk false smaller
          (Printf.sprintf "argument #%d in call to `%s`" (i + 1) fn.txt)
          arg
      ) args
    (* ── Regular application ── *)
    | Ast.EApp (f, args, _) ->
      let arg_ctx = match f with
        | Ast.EVar op when is_infix_op op.txt ->
          Printf.sprintf "wrapped in binary operation `%s`" op.txt
        | Ast.EVar fn_n -> Printf.sprintf "passed as argument to `%s`" fn_n.txt
        | _ -> "passed as argument to a function"
      in
      chk false smaller "function part of application" f;
      List.iter (chk false smaller arg_ctx) args
    (* ── Constructor ── *)
    | Ast.ECon (name, args, _) ->
      let arg_ctx = Printf.sprintf "wrapped in constructor `%s`" name.txt in
      List.iter (chk false smaller arg_ctx) args
    (* ── if/do/else/end: condition not tail; branches inherit ── *)
    | Ast.EIf (cond, then_, else_, _) ->
      chk false smaller "condition of `if`" cond;
      chk in_tail smaller ctx then_;
      chk in_tail smaller ctx else_
    (* ── match do cond_arm* end ── *)
    | Ast.ECond (arms, _) ->
      List.iter (fun (ce, be) ->
        chk false smaller "condition in `match do`" ce;
        chk in_tail smaller ctx be
      ) arms
    (* ── match: scrutinee not tail; if scrutinee is a parameter or smaller
          variable, extend [smaller] with all vars bound in each arm's pattern ── *)
    | Ast.EMatch (scrut, branches, _) ->
      chk false smaller "scrutinee of `match`" scrut;
      let scrut_is_smaller = scrutinee_is_param_or_smaller fn_params smaller scrut in
      List.iter (fun (br : Ast.branch) ->
        let arm_smaller =
          if scrut_is_smaller
          then StringSet.union smaller (collect_pattern_vars br.branch_pat)
          else smaller
        in
        Option.iter (chk false arm_smaller "match guard") br.branch_guard;
        chk in_tail arm_smaller ctx br.branch_body
      ) branches
    (* ── block: only last expression is in tail position.
          Propagate structural smallness: if a let binding assigns a variable
          to a structurally-smaller expression, that variable is also smaller. ── *)
    | Ast.EBlock (exprs, _) ->
      let rec go s = function
        | [] -> ()
        | [last] -> chk in_tail s ctx last
        | hd :: tl ->
          chk false s "non-final expression in block" hd;
          let s' = match hd with
            | Ast.ELet (b, _) ->
              (match b.Ast.bind_pat with
               | Ast.PatVar v
                 when is_structurally_smaller fn_params s b.Ast.bind_expr ->
                 StringSet.add v.txt s
               | _ -> s)
            | _ -> s
          in
          go s' tl
      in
      go smaller exprs
    (* ── let binding: RHS is never tail ── *)
    | Ast.ELet (b, _) ->
      chk false smaller "right-hand side of `let` binding" b.Ast.bind_expr
    (* ── inner named function: check its own self-recursion in its own scope ── *)
    | Ast.ELetFn (iname, iparams, _, ibody, _) ->
      let iparams_set =
        List.fold_left (fun acc (p : Ast.param) -> StringSet.add p.param_name.txt acc)
          StringSet.empty iparams
      in
      check_tail_position errors (StringSet.singleton iname.txt) iname.txt iparams_set ibody
    (* ── lambda: new scope, skip outer recursive-name check ── *)
    | Ast.ELam _ -> ()
    (* ── transparent ── *)
    | Ast.EAnnot (ex, _, _) -> chk in_tail smaller ctx ex
    (* ── non-tail contexts ── *)
    | Ast.ETuple (es, _) ->
      List.iter (chk false smaller "tuple element") es
    | Ast.ERecord (fields, _) ->
      List.iter (fun ((nm : Ast.name), ex) ->
        chk false smaller (Printf.sprintf "value of record field `%s`" nm.txt) ex
      ) fields
    | Ast.ERecordUpdate (base, fields, _) ->
      chk false smaller "base of record update" base;
      List.iter (fun ((nm : Ast.name), ex) ->
        chk false smaller (Printf.sprintf "value of record field `%s`" nm.txt) ex
      ) fields
    | Ast.EField (ex, _, _)  -> chk false smaller "object of field access" ex
    | Ast.EPipe  (l, r, _)   -> chk false smaller "left side of pipe" l;
                                 chk false smaller "right side of pipe" r
    | Ast.EAtom (_, args, _) -> List.iter (chk false smaller "atom argument") args
    | Ast.ESend (cap, msg, _) ->
      chk false smaller "capability in `send`" cap;
      chk false smaller "message in `send`" msg
    | Ast.ESpawn (ex, _)      -> chk false smaller "argument to `spawn`" ex
    | Ast.EDbg (Some ex, _)   -> chk false smaller "argument to `dbg`" ex
    | Ast.ELetQ (_, r, cont, _) ->
      chk false smaller "right-hand side of `let?`" r;
      chk in_tail smaller ctx cont
    | Ast.EAssert (ex, _)     -> chk false smaller "assert expression" ex
    | Ast.ESigil (_, content, _) -> chk false smaller "sigil content" content
    (* ── leaves ── *)
    | Ast.EDbg (None, _) | Ast.ELit _ | Ast.EVar _ | Ast.EHole _
    | Ast.EResultRef _ -> ()
  in
  chk true StringSet.empty "" body

(** Run tail-call enforcement for all [DFn] declarations in [decls]
    (at a single scope level).  Recurses into [DMod] sub-modules. *)
let rec enforce_tail_calls_in_decls (errors : Err.ctx) (decls : Ast.decl list) : unit =
  (* Collect function names at this level *)
  let fn_names =
    List.fold_left (fun acc d ->
      match d with
      | Ast.DFn (def, _) -> StringSet.add def.fn_name.txt acc
      | _ -> acc
    ) StringSet.empty decls
  in
  (* Build call graph *)
  let adj = List.filter_map (function
    | Ast.DFn (def, _) ->
      (match def.fn_clauses with
       | [clause] ->
         Some (def.fn_name.txt,
               collect_direct_fn_calls fn_names clause.Ast.fc_body)
       | _ -> None)
    | _ -> None
  ) decls in
  (* Find SCCs *)
  let sccs = find_sccs adj in
  let scc_of = Hashtbl.create 16 in
  List.iter (fun scc ->
    List.iter (fun nm -> Hashtbl.replace scc_of nm scc) scc
  ) sccs;
  (* Check each function that participates in recursion *)
  List.iter (function
    | Ast.DFn (def, _) ->
      (match def.fn_clauses with
       | [clause] ->
         let scc = try Hashtbl.find scc_of def.fn_name.txt
                   with Not_found -> [def.fn_name.txt] in
         let direct = match List.assoc_opt def.fn_name.txt adj with
           | Some s -> s | None -> StringSet.empty in
         let is_recursive =
           List.length scc > 1 ||
           StringSet.mem def.fn_name.txt direct
         in
         if is_recursive && not (List.mem "no_warn_recursion" def.fn_attrs) then begin
           let rec_set = List.fold_right StringSet.add scc StringSet.empty in
           let fn_params =
             List.fold_left (fun acc p ->
               match p with
               | Ast.FPNamed named -> StringSet.add named.param_name.txt acc
               | Ast.FPDefault (named, _) -> StringSet.add named.param_name.txt acc
               | Ast.FPPat pat -> StringSet.union acc (collect_pattern_vars pat)
             ) StringSet.empty clause.Ast.fc_params
           in
           check_tail_position errors rec_set def.fn_name.txt fn_params clause.Ast.fc_body
         end
       | _ -> ())
    | Ast.DMod (_, _, inner_decls, _) ->
      enforce_tail_calls_in_decls errors inner_decls
    | _ -> ()
  ) decls

(* =================================================================
   §17  Module entry point
   ================================================================= *)

(** Build a function's declared type scheme from its annotations, for pass-1
    forward cross-module reference resolution.  Returns None when the signature
    cannot be built structurally (unannotated/pattern params, no return
    annotation, zero params, multiple clauses, or exotic annotation forms) — the
    caller then falls back to the [fresh_var] placeholder.

    The scheme carries NO class/bound constraints; this is sound because the
    prior placeholder ([Mono (fresh_var _)]) carried none either, and each
    function's own [check_fn] re-derives and enforces its full constrained type.
    The only gain is that a module checked BEFORE this function now sees its real
    argument and RESULT types instead of an unconstrained type variable — which
    is what lets niche-encoded [Option]/ADT results lower with the correct match
    strategy regardless of stdlib check order. *)
let prebind_fn_scheme (def : Ast.fn_def) : scheme option =
  let opt_all xs =
    List.fold_right (fun x acc -> match x, acc with
      | Some v, Some vs -> Some (v :: vs)
      | _ -> None) xs (Some []) in
  let tvars : (string * ty) list ref = ref [] in
  let rec conv (s : Ast.ty) : ty option =
    match s with
    | Ast.TyCon (name, args) ->
      (match opt_all (List.map conv args) with
       | Some args' -> Some (TCon (name.txt, args'))
       | None -> None)
    | Ast.TyVar v ->
      (match List.assoc_opt v.txt !tvars with
       | Some t -> Some t
       | None -> let fv = fresh_var 1 in tvars := (v.txt, fv) :: !tvars; Some fv)
    | Ast.TyArrow (a, b) ->
      (match conv a, conv b with Some a', Some b' -> Some (TArrow (a', b')) | _ -> None)
    | Ast.TyTuple ts ->
      (match opt_all (List.map conv ts) with Some ts' -> Some (TTuple ts') | None -> None)
    | Ast.TyLinear (_, t) -> conv t
    | _ -> None
  in
  match def.fn_clauses with
  | [clause] when clause.fc_params <> [] ->
    let param_ty (fp : Ast.fn_param) : ty option =
      match fp with
      | Ast.FPNamed p | Ast.FPDefault (p, _) ->
        (match p.param_ty with Some t -> conv t | None -> None)
      | Ast.FPPat _ -> None
    in
    (match def.fn_ret_ty with
     | None -> None
     | Some ret ->
       (match conv ret, opt_all (List.map param_ty clause.fc_params) with
        | Some ret_ty, Some param_tys ->
          let arrow = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
          Some (generalize 0 arrow)
        | _ -> None))
  | _ -> None

(** Type-check a whole module.

    Pass 1: collect all top-level function names into the environment
            as monomorphic placeholders.  This allows forward references
            and simple mutual recursion (the placeholder is unified with
            the actual type as the body is inferred).

    Pass 2: check declarations in order, updating the environment.

    Returns the [Err.ctx] containing all diagnostics.

    [seed_env], when given, is used as pass 1's starting environment instead
    of [base_env errors type_map] — its [vars]/[types]/[ctors]/[interfaces]/etc.
    (e.g. an already-typechecked stdlib) are visible to [m]'s own forward-reference
    prebinding and [check_decl] pass with NO other change to pass 1/1b/2's
    structure, so passing [None] is exactly today's behavior. [seed_env]'s own
    [type_map] is reused (shared, mutated in place with [m]'s new span→type
    entries) instead of allocating a fresh one, so a caller who built [seed_env]
    from a separately-checked module can still recover types for BOTH that
    module's spans and [m]'s own via the single returned [type_map]. *)
let check_module_core ?(errors = Err.create ()) ?seed_env (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * env =
  let type_map = match seed_env with
    | Some (se : env) -> se.type_map
    | None -> Hashtbl.create 256
  in
  (* Helper: recursively collect qualified "Mod.fn" names from nested DMod
     declarations so that cross-module forward references are pre-bound in
     pass 1. This mirrors the eval.ml global module_registry approach.
     Only pre-binds public functions to preserve private-access restrictions. *)
  let rec prebind_mod_members prefix env decls =
    List.fold_left (fun e d ->
        match d with
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public ->
          let qname = prefix ^ "." ^ def.fn_name.txt in
          if StrMap.mem qname e.vars then e
          else
            let sch = match prebind_fn_scheme def with
              | Some s -> s
              | None -> Mono (fresh_var 1)
            in
            bind_var qname sch e
        | Ast.DType (vis, name, params, typedef, _)
        | Ast.DAlwaysLinearType (vis, name, params, typedef, _) when vis = Ast.Public ->
          let qname = prefix ^ "." ^ name.txt in
          let e1 = if StrMap.mem qname e.types then e
            else { e with types = StrMap.add qname (List.length params) e.types } in
          (match typedef with
           | Ast.TDVariant variants ->
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             List.fold_left (fun acc (v : Ast.variant) ->
                 let qctor = prefix ^ "." ^ v.var_name.txt in
                 let ci = { ci_type = qname; ci_params = param_names;
                            ci_arg_tys = v.var_args; ci_vis = v.var_vis } in
                 let acc = { acc with ctors = add_ctor qctor ci acc.ctors } in
                 (* Also register the disambiguated module.type.ctor form
                    ("Md.Inline.Text").  A wrapped sibling gets this key from the
                    DMod export step, but the ENTRY module is unwrapped (top
                    level) so Pass 1b is the only place it is registered — a
                    sibling that writes `Md.Inline.Text` to disambiguate a shared
                    constructor name would otherwise fail to resolve it.  The
                    ci_type is the BARE type name, matching the constructor's
                    lowering key, so it cannot perturb codegen. *)
                 if v.var_vis <> Ast.Public then acc
                 else
                   let type_qctor = qname ^ "." ^ v.var_name.txt in
                   let type_ci = { ci_type = name.txt; ci_params = param_names;
                                   ci_arg_tys = v.var_args; ci_vis = v.var_vis } in
                   { acc with ctors = add_ctor type_qctor type_ci acc.ctors }
               ) e1 variants
           | Ast.TDRecord fields ->
             (* Register both local name and fully-qualified name in env.records
                so cross-module type annotations like "Conduit.JobRow" resolve
                to a structural TRecord, not an opaque TCon. *)
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
             register_record_name ~name:name.txt (List.map fst field_pairs);
             register_record_name ~name:qname (List.map fst field_pairs);
             let e2 = { e1 with records = StrMap.add name.txt (param_names, field_pairs) e1.records } in
             { e2 with records = StrMap.add qname (param_names, field_pairs) e2.records }
           | _ -> e1)
        | Ast.DInterface (idef, _) -> prebind_interface_decl ~prefix idef e
        | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
          prebind_mod_members (prefix ^ "." ^ mname.txt) e inner_decls
        | _ -> e
      ) env decls
  in
  (* Pass 1: forward-reference placeholders for functions and type/ctor names *)
  let pre_env = List.fold_left (fun env d ->
      match d with
      | Ast.DFn (def, _) ->
        (* Record the name as locally defined so bulk imports cannot clobber
           its binding (local definitions shadow imports — see env.local_fns). *)
        let arity = match def.fn_clauses with
          | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
        let env = { env with local_fns = StrMap.add def.fn_name.txt () env.local_fns;
                             fn_arities = StrMap.add def.fn_name.txt (arity, def.fn_name.span) env.fn_arities } in
        (* Don't shadow existing bindings (e.g., builtins) with mono forward refs *)
        if StrMap.mem def.fn_name.txt env.vars then env
        else bind_var def.fn_name.txt (Mono (fresh_var 1)) env
      | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
        (* Pre-bind all public qualified names "ModName.fn" so that sibling
           modules that reference each other don't fail during pass 2. *)
        let env = prebind_mod_members mname.txt env inner_decls in
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef
            | _ -> e
          ) env inner_decls
      | Ast.DType (_, name, params, typedef, _)
      | Ast.DAlwaysLinearType (_, name, params, typedef, _) ->
        let env1 = { env with types = StrMap.add name.txt (List.length params) env.types } in
        (match typedef with
         | Ast.TDVariant variants ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           List.fold_left (fun e (v : Ast.variant) ->
               let ci = { ci_type    = name.txt
                        ; ci_params  = param_names
                        ; ci_arg_tys = v.var_args
                        ; ci_vis     = v.var_vis } in
               (* Register the type-qualified key ("TypeName.CtorName") in this
                  forward-reference pass, not just in check_decl: sibling DMods
                  are typechecked before the entry module's own DTypes are
                  reached, so a sibling that imports the entry and
                  disambiguates with `Expr.Col` would otherwise fail to
                  resolve the constructor. *)
               let qual_key = name.txt ^ "." ^ v.var_name.txt in
               { e with ctors = add_ctor qual_key ci (add_ctor v.var_name.txt ci e.ctors) }
             ) env1 variants
         | Ast.TDRecord fields ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
           register_record_name ~name:name.txt (List.map fst field_pairs);
           { env1 with records = StrMap.add name.txt (param_names, field_pairs) env1.records }
         | _ -> env1)
      | Ast.DActor (_, name, actor, _) ->
        (* Register actor name as a zero-arg constructor and message ctors.
           Same arity fix as in check_decl: include unannotated params as
           unique TyVar placeholders so constructor arity is always correct. *)
        let env1 = { env with ctors =
          add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_vis = Ast.Public }
            env.ctors } in
        List.fold_left (fun acc_env (h : Ast.actor_handler) ->
            let arg_tys = List.mapi (fun i (p : Ast.param) ->
                match p.param_ty with
                | Some ty -> ty
                | None ->
                  Ast.TyVar { txt = Printf.sprintf "$p%d_%s" i h.ah_msg.txt;
                              span = p.param_name.span }
              ) h.ah_params in
            let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                       ci_arg_tys = arg_tys; ci_vis = Ast.Public } in
            { acc_env with ctors = add_ctor h.ah_msg.txt ci acc_env.ctors }
          ) env1 actor.actor_handlers
      | Ast.DSig (name, sdef, _) ->
        { env with sigs = (name.txt, sdef) :: env.sigs }
      | Ast.DInterface (idef, _) ->
        { env with interfaces = StrMap.add idef.iface_name.txt idef env.interfaces }
      | Ast.DImpl (idef, _) ->
        register_impl_shape env idef
      | Ast.DMod (_, _, inner_decls, _) ->
        (* Interface implementations declared in sibling modules must be
           visible unit-wide regardless of the order modules are checked in:
           CInterface constraints discharge at declaration boundaries, so an
           impl that is only registered when its defining module is reached
           cannot satisfy constraints from modules checked earlier. *)
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef
            | _ -> e
          ) env inner_decls
      | _ -> env
    ) (match seed_env with
        | Some se -> { se with errors; type_map }
        | None -> base_env errors type_map)
      m.Ast.mod_decls
  in
  (* Pass 1b: the entry module's own declarations live at the TOP LEVEL of the
     combined module (only the imported sibling modules are wrapped in [DMod]).
     They were registered under their BARE names above, but sibling modules
     refer to the entry's types with the entry module's QUALIFIED prefix
     (`Config.Site`).  Without a qualified binding those references fall through
     to the module registry, which has no record-field information and so
     resolves a record type to a NOMINAL `TCon` that will not unify with the
     entry module's own structural use of it.  Pre-bind the entry's top-level
     declarations under its module name exactly as a wrapped sibling would be,
     so qualified and unqualified references resolve to the same type.  Skip
     [DMod]s so imported modules are not double-prefixed. *)
  let pre_env =
    let top_level = List.filter
      (function Ast.DMod _ -> false | _ -> true) m.Ast.mod_decls in
    prebind_mod_members m.Ast.mod_name.txt pre_env top_level
  in
  (* Pass 2: full checking *)
  let pre_env = { pre_env with current_module = m.Ast.mod_name.txt } in
  let final_env = List.fold_left check_decl pre_env (reorder_decls m.Ast.mod_decls) in
  (* Part 1: the cap_narrow proof-cap forge is closed by the [unify] hook
     ([cap_producer_ivars]), which fires at the exact moment a cap_narrow-derived
     inner var is bound to a nominal proof cap — position- and flow-independent
     (direct, let-generalized, or laundered through a polymorphic function).  A
     post-checking recorded-node sweep is NOT used for cap_narrow: a laundered
     value leaves the recorded node unbound, which the sweep cannot distinguish
     from legitimate laundered IO narrowing.
     Part 2: enforce the mint_cap gate on every recorded site (result now pinned;
     enclosing fn/module context captured at record time). Shared ref → one sweep
     at the entry module covers every nested module's sites. *)
  check_mint_cap_sites final_env;
  (* Validate capability declarations for the top-level module *)
  (* The entry module's own name is NOT a prefix segment for cap-closure keys:
     TIR unwraps the entry module (see [lib/tir/lower.ml]'s [mod_prefix]
     accumulation, which starts empty at the entry level), so top-level
     functions are keyed by their bare name and nested DMod functions are
     keyed starting from that nested module's own name (e.g. "Lib.Sub.f"),
     never "EntryName.Lib.Sub.f". *)
  check_module_needs final_env m.Ast.mod_name m.Ast.mod_decls
    ~cap_qname_prefix:"";
  (* Validate cap no_panic invariant if declared *)
  if final_env.no_panic_mod then
    check_no_panic_module errors final_env m.Ast.mod_decls;
  (* Validate cap pure invariant if declared *)
  if final_env.pure_mod then
    check_pure_module errors final_env m.Ast.mod_decls;
  (* Validate cap no_extern invariant if declared *)
  if final_env.no_extern_mod then
    check_no_extern_module errors final_env m.Ast.mod_decls;
  (* Validate cap deterministic invariant if declared *)
  if final_env.deterministic_mod then
    check_deterministic_module errors final_env m.Ast.mod_decls;
  (* Warn about any unused imports or aliases *)
  warn_unused_imports final_env;
  (* Pass 3: tail-call enforcement *)
  enforce_tail_calls_in_decls errors m.Ast.mod_decls;
  (errors, type_map, final_env)

let check_module ?errors (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t =
  let (errs, type_map, _env) = check_module_core ?errors m in
  (errs, type_map)

(** Like [check_module] but starts from a pre-built environment.
    Used by the REPL JIT to typecheck user expressions incrementally
    without re-typechecking stdlib on every input.

    [env] should be the environment produced by loading stdlib
    (via [base_env] + repeated [check_decl] calls).  The [type_map]
    inside [env] is mutated in place with new span→type entries. *)

(* Side channel for [check_module_with_env_full]: the last final env produced
   by [check_module_with_env].  Set at the end of pass 2; read immediately by
   the [_full] wrapper.  Single-threaded use only (LSP analyse / REPL JIT). *)
let last_with_env_final : env ref = ref (make_env (Err.create ()) (Hashtbl.create 0))

let check_module_with_env (env : env) (m : Ast.module_) : Err.ctx * (Ast.span, ty) Hashtbl.t =
  let errors = env.errors in
  let type_map = env.type_map in
  let rec prebind_mod_members_inc prefix e decls =
    List.fold_left (fun e d ->
        match d with
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public ->
          let qname = prefix ^ "." ^ def.fn_name.txt in
          if StrMap.mem qname e.vars then e
          else bind_var qname (Mono (fresh_var 0)) e
        | Ast.DType (vis, name, params, typedef, _)
        | Ast.DAlwaysLinearType (vis, name, params, typedef, _) when vis = Ast.Public ->
          let qname = prefix ^ "." ^ name.txt in
          let e1 = if StrMap.mem qname e.types then e
            else { e with types = StrMap.add qname (List.length params) e.types } in
          (match typedef with
           | Ast.TDVariant variants ->
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             List.fold_left (fun acc (v : Ast.variant) ->
                 let qctor = prefix ^ "." ^ v.var_name.txt in
                 let ci = { ci_type = qname; ci_params = param_names;
                            ci_arg_tys = v.var_args; ci_vis = v.var_vis } in
                 let acc = { acc with ctors = add_ctor qctor ci acc.ctors } in
                 (* Also register the disambiguated module.type.ctor form
                    ("Md.Inline.Text").  A wrapped sibling gets this key from the
                    DMod export step, but the ENTRY module is unwrapped (top
                    level) so Pass 1b is the only place it is registered — a
                    sibling that writes `Md.Inline.Text` to disambiguate a shared
                    constructor name would otherwise fail to resolve it.  The
                    ci_type is the BARE type name, matching the constructor's
                    lowering key, so it cannot perturb codegen. *)
                 if v.var_vis <> Ast.Public then acc
                 else
                   let type_qctor = qname ^ "." ^ v.var_name.txt in
                   let type_ci = { ci_type = name.txt; ci_params = param_names;
                                   ci_arg_tys = v.var_args; ci_vis = v.var_vis } in
                   { acc with ctors = add_ctor type_qctor type_ci acc.ctors }
               ) e1 variants
           | Ast.TDRecord fields ->
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
             register_record_name ~name:name.txt (List.map fst field_pairs);
             register_record_name ~name:qname (List.map fst field_pairs);
             let e2 = { e1 with records = StrMap.add name.txt (param_names, field_pairs) e1.records } in
             { e2 with records = StrMap.add qname (param_names, field_pairs) e2.records }
           | _ -> e1)
        | Ast.DInterface (idef, _) -> prebind_interface_decl ~prefix idef e
        | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
          prebind_mod_members_inc (prefix ^ "." ^ mname.txt) e inner_decls
        | _ -> e
      ) e decls
  in
  (* Pass 1: forward-reference placeholders for new declarations *)
  let pre_env = List.fold_left (fun env d ->
      match d with
      | Ast.DFn (def, _) ->
        if StrMap.mem def.fn_name.txt env.vars then env
        else bind_var def.fn_name.txt (Mono (fresh_var 0)) env
      | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
        (* Register the sibling module's members, then its interface impls — an
           impl declared in a sibling must satisfy constraints unit-wide
           regardless of check order (mirrors check_module_core's pass 1). *)
        let env = prebind_mod_members_inc mname.txt env inner_decls in
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef
            | _ -> e
          ) env inner_decls
      | Ast.DType (_, name, params, typedef, _)
      | Ast.DAlwaysLinearType (_, name, params, typedef, _) ->
        let env1 = { env with types = StrMap.add name.txt (List.length params) env.types } in
        (match typedef with
         | Ast.TDVariant variants ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           List.fold_left (fun e (v : Ast.variant) ->
               let ci = { ci_type    = name.txt
                        ; ci_params  = param_names
                        ; ci_arg_tys = v.var_args
                        ; ci_vis     = v.var_vis } in
               (* Register the type-qualified key ("TypeName.CtorName") in this
                  forward-reference pass, not just in check_decl: sibling DMods
                  are typechecked before the entry module's own DTypes are
                  reached, so a sibling that imports the entry and
                  disambiguates with `Expr.Col` would otherwise fail to
                  resolve the constructor. *)
               let qual_key = name.txt ^ "." ^ v.var_name.txt in
               { e with ctors = add_ctor qual_key ci (add_ctor v.var_name.txt ci e.ctors) }
             ) env1 variants
         | Ast.TDRecord fields ->
           let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
           let field_pairs = List.map (fun (f : Ast.field) -> (f.fld_name.txt, f.fld_ty)) fields in
           register_record_name ~name:name.txt (List.map fst field_pairs);
           { env1 with records = StrMap.add name.txt (param_names, field_pairs) env1.records }
         | _ -> env1)
      | Ast.DActor (_, name, actor, _) ->
        let env1 = { env with ctors =
          add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_vis = Ast.Public }
            env.ctors } in
        List.fold_left (fun acc_env (h : Ast.actor_handler) ->
            let arg_tys = List.mapi (fun i (p : Ast.param) ->
                match p.param_ty with
                | Some ty -> ty
                | None ->
                  Ast.TyVar { txt = Printf.sprintf "$p%d_%s" i h.ah_msg.txt;
                              span = p.param_name.span }
              ) h.ah_params in
            let ci = { ci_type = name.txt ^ "_Msg"; ci_params = [];
                       ci_arg_tys = arg_tys; ci_vis = Ast.Public } in
            { acc_env with ctors = add_ctor h.ah_msg.txt ci acc_env.ctors }
          ) env1 actor.actor_handlers
      | Ast.DSig (name, sdef, _) ->
        { env with sigs = (name.txt, sdef) :: env.sigs }
      | Ast.DInterface (idef, _) ->
        { env with interfaces = StrMap.add idef.iface_name.txt idef env.interfaces }
      | _ -> env
    ) env m.Ast.mod_decls
  in
  (* Pass 2: full checking of new declarations *)
  let final_env = List.fold_left check_decl pre_env (reorder_decls m.Ast.mod_decls) in
  last_with_env_final := final_env;
  (* Pass 3: tail-call enforcement *)
  enforce_tail_calls_in_decls errors m.Ast.mod_decls;
  (errors, type_map)

(** Like [check_module_with_env] but also returns the final typing env.
    The LSP needs the env (ctors/vars/types/interfaces/impls) for completion
    and constructor enumeration; the non-[_full] form discards it. *)
let check_module_with_env_full (env : env) (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * env =
  let (errs, tm) = check_module_with_env env m in
  (errs, tm, !last_with_env_final)

(** Like [check_module] but also returns the final typing environment.
    Used by the LSP for hover/completion.  Delegates to [check_module_core]
    so editor diagnostics run the EXACT same passes as `march --check` —
    a reduced duplicate here previously skipped the pass-1 type/ctor/record
    prebinding, so qualified type annotations (Bastion.Channel.ChannelConn)
    failed to resolve only in the LSP. *)
let check_module_full ?(errors = Err.create ()) ?seed_env (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * env =
  check_module_core ~errors ?seed_env m

let check_letq_repl (env : env) (p : Ast.pattern) (e : Ast.expr) : env =
  let env' = enter_level env in
  let result_ty = infer_expr env' e in
  let t_ok  = fresh_var env'.level in
  let t_err = fresh_var env'.level in
  let sp = span_of_expr e in
  unify env' ~span:sp
    ~reason:(Some (RBuiltin "The right-hand side of `let?` must be a Result value."))
    result_ty (t_result t_ok t_err);
  let bindings, pat_ty = infer_pattern env' p in
  unify env' ~span:sp ~reason:(Some (RLetBind sp)) t_ok pat_ty;
  ignore (leave_level env');
  bind_vars bindings env
