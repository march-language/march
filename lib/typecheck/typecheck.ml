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
  le_first_use : Ast.span option ref;
  (** Span of the use that consumed this value, recorded when [le_used] is
      first set. A double-use error is about a RELATIONSHIP between two sites,
      and reporting only the second one leaves the reader to find the first by
      hand — so the diagnostic points at both. Kept in step with [le_used]
      everywhere that flag is saved and restored (see [iter_arms_linear]). *)
}

(** Constructor info — populated from [DType] declarations.
    Describes one variant of a sum type so we can give [ECon] and
    [PatCon] real types instead of fresh variables. *)
type ctor_info = {
  ci_type    : string;           (** Parent type name, e.g. "Result" *)
  ci_params  : string list;      (** Type param names in declaration order *)
  ci_arg_tys : Ast.ty list;      (** Surface arg types of this constructor *)
  ci_vis     : Ast.visibility;   (** Constructor visibility (Public/Private) *)
  ci_module  : string;
  (** Declaring module of this constructor's parent type (empty at top level /
      prelude).  Additive metadata: [ci_type] is the BARE parent-type name and
      is deliberately kept bare for cross-module unification (see
      [prebind_mod_members]'s reverted qualified-ci_type experiment), so two
      same-named types' constructors are indistinguishable by [ci_type] alone.
      [ci_module] disambiguates them for [ctors_for_type]'s exhaustiveness
      universe, which otherwise merges a user `Handle`'s ctors with stdlib's
      same-named `Handle` (linear-L4 ctor cross-talk), AND — since the FQN
      dispatch-identity plan's Task 1 — is part of [add_ctor]'s structural
      dedup key, so two DIFFERENT modules' identically-shaped ctors (e.g. both
      a nullary `Shared`) are kept as distinct candidates instead of the
      second collapsing onto the first. It still feeds NO codegen/mangling/
      dispatch, so this is byte-identical at the backend for any program that
      does not hit this exact double-collision shape.  First metadata slice of
      the module-qualified ctor identity in
      specs/plans/2026-07-17-fqn-type-ctor-identity.md (Stage 4). *)
  ci_is_actor_msg : bool;
  (** True iff this constructor is an actor message handler's auto-registered
      ctor (an `on Msg(...)` arm), i.e. [ci_type] is some `<Actor>_Msg`.  Set
      at the three DActor registration sites; [false] everywhere else INCLUDING
      the actor's own zero-arg name ctor (used by `spawn`, not a message).
      The [ECon] typing arm reads this to decide whether to run
      [check_sendable] over the constructor's instantiated argument types —
      message payloads may not carry a mutable-buffer type (RingBuf,
      NativeIntArr, NativeFloatArr); ordinary user ADTs are unrestricted.
      Exactly one site (the cross-module [ExCtor] reconstruction, which only
      has an exported name+arity to work from, not the original record) can't
      set this from a known-true/false fact and instead derives it from the
      same "_Msg" suffix [Tir_names.is_actor_msg_name] uses post-lowering —
      justified there and ONLY there, because the export bridge is the one
      place this record is rebuilt from strictly less information than it
      started with. *)
}

(** One entry in the import tracker — records an imported name or alias and
    whether it was referenced at least once during typechecking. *)
type import_entry = {
  ie_span    : Ast.span;
  ie_desc    : string;              (** human-readable warning message *)
  ie_matches : string -> bool;      (** does looking up [name] count as "using" this? *)
  ie_used    : bool ref;
  ie_used_names : (string, unit) Hashtbl.t;
  (** WHICH of this import's names were actually referenced.  [record_use]
      already computes this -- the index hit tells us precisely which imported
      name a reference resolved to -- and until now it was collapsed to
      [ie_used] and discarded.  Demand-driven capability propagation (Check 4)
      consumes it: an importer inherits only the capabilities of the functions
      it actually references, not the imported module's whole set.

      Bare names for the exact-name index (a rebound short name from
      `import M`), FULL DOTTED names for the prefix index (a qualified
      `M.foo` reference under `use M`).  Both spellings are resolved against
      the closure table by [check_module_needs]. *)
}

(* Index bookkeeping for [record_use]'s import-tracker lookup.  [record_use]
   runs once per EVar in the WHOLE combined program (stdlib + every
   auto-discovered file), so it must not re-scan the full [import_tracker]
   list (whose length is O(total use/import/alias decls across the whole
   program)) on every call -- that pairing is O(var-refs * imports), which
   is quadratic-and-then-some on a multi-hundred-file project.  Instead each
   entry is also indexed by every literal name it can EXACT-match (module
   short names / aliased names) into [ie_exact_index], and by its
   qualification prefix (the module/alias name before the dot) into
   [ie_prefix_index], so [record_use] does two O(1)-average Hashtbl lookups
   instead of an O(n) scan.  This mirrors -- but does not replace -- each
   entry's original [ie_matches] closure, which remains the source of truth
   used at entry-creation time to populate the index (no behavior change,
   just no longer scanning the flat list at lookup time). *)
type import_index = {
  ie_exact_index  : (string, import_entry list) Hashtbl.t;
  (** name -> entries that match it via an EXACT name (short_names / n.txt /
      short_name), populated with the same names the closures compare against. *)
  ie_prefix_index : (string, import_entry list) Hashtbl.t;
  (** prefix root (mod_str for Use*, alias short_name for DAlias) -> entries
      that also accept a qualified reference under that prefix.  [record_use]
      only consults this when the looked-up name contains a '.'. *)
}

let make_import_index () =
  { ie_exact_index = Hashtbl.create 64; ie_prefix_index = Hashtbl.create 16 }

let import_index_add_exact idx key entry =
  let prev = try Hashtbl.find idx.ie_exact_index key with Not_found -> [] in
  Hashtbl.replace idx.ie_exact_index key (entry :: prev)

let import_index_add_prefix idx key entry =
  let prev = try Hashtbl.find idx.ie_prefix_index key with Not_found -> [] in
  Hashtbl.replace idx.ie_prefix_index key (entry :: prev)

(** Computed session-type information for a declared [protocol].
    Stored in [env.protocols] after [DProtocol] is checked. *)
type proto_info = {
  pi_def         : Ast.protocol_def;
  pi_projections : (string * session_ty) list;  (** role → local session type *)
  pi_span        : Ast.span;
}

module StrMap = Map.Make(String)

(** A resolved reference recorded during typechecking: [callee] used a
    declaration that [caller] (both fully-qualified "Mod.name") owns, at
    [ref_file]:[ref_line]. Populated only where resolution already succeeds —
    never a textual guess. *)
type ref_record = {
  callee   : string;
  caller   : string;
  ref_kind : [ `Call | `Ctor | `TypeRef ];
  ref_file : string;
  ref_line : int;
}

(** Qualify [name] with [modname] the one way every [ref_record] site should:
    ["Mod.name"], or bare [name] when [modname] is empty. An empty module
    name shows up for prelude constructors ([Cons]/[Nil]/[Some]/[None]/[Ok]/
    [Err], whose [ci_module] is "") and for the bare-module case generally —
    without this, ad-hoc `modname ^ "." ^ name` concatenation at each
    recording site produces a callee/caller literally starting with "." for
    those references, which [Search.search_callers]'s query-side lookup can
    never match (its own [qualified_of] already treats an empty module name
    this way). Shared by the [EVar]/[ECon]/[TyCon] reference-recording hooks
    so the convention can't drift between them. *)
let qualify_ref_name (modname : string) (name : string) : string =
  if modname = "" then name else modname ^ "." ^ name

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
  refs : ref_record list ref;
  (** Resolved call/ctor/type references accumulated during checking, for
      `forge search --callers`. Shared (mutable) across all env copies
      derived from the same root, same as [import_tracker]. *)
  current_decl : string ref;
  (** Fully-qualified name ("Mod.fn") of the top-level fn/impl-method whose
      body is currently being checked. Set by [check_fn]; read wherever a
      [ref_record] is recorded so it knows its caller. Empty string before
      the first fn is entered. *)
  scheme_witnesses : (int list, constraint_ list * ty) Hashtbl.t;
  (** A1 (--emit-core-ast v2): every HM scheme instantiated during checking,
      deduped by its quantified-id list -> (constraints, body). Populated at
      the single [instantiate] chokepoint (Poly branch) so user, builtin, and
      stdlib schemes are all uniformly captured. Read by the emitter to
      serialize which schemes were generalized. *)
  inst_witnesses : (Ast.span, int list * ty list) Hashtbl.t;
  (** A1 (--emit-core-ast v2): for every polymorphic use site that supplied a
      [~use_span] to [instantiate] (EVar/EField inference), the scheme's
      quantified-id list paired positionally with the freshly-substituted
      (post-solve, [repr]-resolvable) type-argument vector. Keyed by the
      use-site span so the emitter can look up "how did THIS occurrence
      instantiate its scheme." *)
  interfaces : Ast.interface_def StrMap.t; (** Registered interfaces *)
  sigs       : (string * Ast.sig_def) list;       (** Registered module signatures *)
  mod_needs  : string list;
  (** Capabilities declared via [needs] in the current module scope, as dot-joined paths *)
  mod_need_scopes : (string * string option) list;
  (** Those same declarations paired with their optional PATH SCOPE, from
      [needs IO.FileRead("/etc/app")].  Parallel to [mod_needs], which keeps
      the bare paths every existing consumer reads, so nothing that treats a
      capability as a plain string is disturbed.  [None] means unscoped.
      A capability declared twice contributes one entry per scope, so
      [needs IO.FileRead("/a"), IO.FileRead("/b")] permits both subtrees. *)
  module_caps : (string * string list) list;
  (** Capabilities required by checked sub-modules: module name → list of cap paths.
      Populated when a [DMod] is fully checked; used for transitive enforcement.
      Each module contributes an entry under its fully-qualified path (matching
      TIR attribution, which the --cap-strict ceiling joins against) and, when
      that differs, a second one under its bare name (matching `use` paths as
      written, which Check 4 looks up).  Entries from modules nested inside a
      [DMod] propagate outward through it. *)
  protocols  : proto_info StrMap.t; (** Registered session-type protocols *)
  impls      : (ty * Ast.span * string option) list StrMap.t;
  (** iface_name → (bare impl head type, decl span, resolved declaring-module of
      the head type — None when unresolved). Head type stays BARE so
      [discharge_constraints] is unaffected; the module is used ONLY by the
      coherence overlap test. *)
  import_tracker : import_entry list ref;
  (** Accumulated import/alias entries for unused-import warning detection.
      Shared (mutable) across all env copies derived from the same root. *)
  import_idx : import_index;
  (** O(1)-average-lookup index mirroring [import_tracker] -- see
      [import_index] for why [record_use] must not scan [import_tracker]
      directly.  Shared (mutable) across all env copies derived from the
      same root, same as [import_tracker]. *)
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
  qual_fn_names : unit StrMap.t;
  (** Qualified ("Mod.name") keys in [vars] that denote a genuine top-level
      function — i.e. a [DFn], an interface method, or a registry [ExFn]
      export — never a [DLet] value/constant. Populated at three sites: the
      [Ast.DMod] export step (mirrors [new_names], restricted to keys
      already known to be functions via [local_fns]/[qual_fn_names] of the
      inner env — so it composes correctly across nested modules),
      [load_module_into_env]'s [ExFn] arm (registry-loaded modules), and
      [prebind_interface_decl] (interface methods, bound as both
      "Iface.method" and "Mod.Iface.method" — a call-syntax reference to
      these bypasses both other sources entirely). Consulted by the
      [Ast.EVar] reference-recording hook so a qualified value reference
      (`Mod.SOME_CONST`) is never recorded as a `` `Call `` reference, while
      a qualified function/interface-method call still is — see [local_fns]
      for the bare-name analogue of this same distinction. *)
  plain_let_names : StringSet.t;
  (** Names most recently bound by a simple, unrestricted `let name = expr`
      (single-variable pattern — see the [Ast.ELet] case of [infer_block]).
      Used ONLY by the [Ast.EApp] handler's zero-arg "calling a non-function
      local value" check (`zf()` where `let zf = answer` — see the
      [noncallable_error] comment there) as a POSITIVE, narrowly-scoped
      signal, deliberately not reusing [fn_arities]'s absence: unlike
      [fn_arities] (name-keyed and cleared by [bind_var] on every rebind,
      including a bulk `import Mod`'s re-binding of an imported function
      under its short name — see [bind_var]'s comment), this field is only
      ever ADDED to at one site, so it can't be accidentally emptied by an
      unrelated rebinding elsewhere in the same threaded env. *)
  proof_caps : (string * string) list;
  (** Proof cap registry: full cap path → declaring module name.
      Populated by [DProofCap] during check_decl; checked by check_module_needs. *)
  always_linear_types : string list;
  (** Set of type constructor names declared with [always_linear type].
      Any binding whose inferred type is [TCon(name, _)] with [name] in this list
      is automatically tracked as linear — no per-site [linear] annotation needed. *)
  current_module : string;
  (** Name of the module currently being typechecked, empty string at top level. *)
  root_cap_allowed : bool;
  (** True where naming [root_cap] is still permitted (R2, 2026-08-05).

      [root_cap] used to be an ordinary global of type [Cap(IO)] in scope in
      every module, which is no-authority-from-nothing violated at the source:
      a module declaring no [needs] at all could hold the root and narrow it to
      any descendant, legitimately, because [cap_narrow] demands exactly the
      parent it now had.  The root is now granted to [main] instead (see
      [Desugar.check_main_signature]; the runtime already passed it).

      Two contexts keep it, both deliberate and both scoped by ENCLOSING
      CONTEXT rather than by the checker declining to look — the distinction
      matters, because "we never checked here" and "we decided not to check
      here" are indistinguishable from the passing test:

      - [test]/[describe]/[setup] bodies, which have no [main] to be granted
        from.  Without this, capability behaviour would not be testable from
        March at all.  It is ambient authority, in a context that cannot reach
        production code: a dependency's test blocks do not run in a consumer's
        build.
      - the REPL, which likewise has no entry point.  Carried by
        [check_module_with_env], whose only caller is [lib/jit/repl_jit.ml]. *)
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
  enclosing_package : string;
  (** Top-level module name of the file being checked, set ONCE and never
      overwritten as nested modules are entered.  [current_module] is only the
      bare name inside a nested `mod Sub`, and [cap_qual_prefix] is "" at the
      entry module, so neither answers "which package does this code belong
      to" — which bare-constructor ambiguity needs, so that a package's own
      constructor is not reported ambiguous against an unimported stdlib type. *)
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
  cap_narrow_sites : (Ast.span * ty) list ref;
  (** Every [cap_narrow] application site, as (span, the INSTANTIATED arrow).
      Swept by [check_cap_narrow_sites] to enforce that the source capability
      SUBSUMES the target — R4a's replacement for the monotonicity the old
      [Cap(IO) -> Cap(a)] argument type enforced through unification.

      Deferred for the same reason as [mint_cap_sites] and [json_cap_sites]:
      the result type is a bare var at the application site and is pinned by
      LATER unification.  See
      [specs/lang/types/reject/t155_cap_narrow_widen_deferred.march], which
      exists to fail if this is ever made eager. *)
  json_cap_sites : (Ast.span * ty * string) list ref;
  (** Every [to_json] / [from_json] / [from_json_events] application site,
      recorded as (span, the INSTANTIATED arrow type of the builtin, builtin
      name).  Swept after checking by [check_json_cap_sites], which rejects a
      capability in the encoded argument or the decoded result — capability
      unforgeability, R3.

      These three are the only builtins typed [poly2 (fun a b -> TArrow (a,
      b))] (see the binding block below), i.e. the only ones whose type places
      no constraint whatsoever on what they produce.  Nothing in [from_json]'s
      signature stops it returning [Cap(IO)].

      Why the arrow and not just the result: [to_json] is checked on its
      ARGUMENT (encoding a capability manufactures the wire value a decoder
      would consume) while the [from_json] family is checked on its RESULT.
      Recording the instantiated arrow captures both in one value, and its two
      vars are unified in place by [infer_app], so the arrow read at sweep
      time carries the solved argument and result.

      Why a deferred sweep rather than an inline check — this is the whole
      reason the mechanism exists: the result var is routinely NOT pinned at
      the application site.  In [let x = from_json(s)] followed by
      [cap_narrow(x)], it is the LATER [cap_narrow] that unifies [x] with
      [Cap(IO)].  An inline check reads an unsolved [TVar], reports nothing,
      and still passes every test that writes the annotation inline.  Same
      trap as [mint_cap_sites] above; see
      [specs/lang/types/reject/t143_cap_from_json_deferred_zonk.march], which
      exists specifically to fail if this is ever made eager. *)
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
  fn_refs : (string, string list) Hashtbl.t;
  (** Per-function REFERENCE edges: fully-qualified function name ("Mod.fn",
      or the BARE name for a top-level function of the entry module — the same
      key convention as [cap_closures]) -> every name its body references.

      Collected with [free_vars_expr], NOT with [March_ast.Calls]: a function
      passed as a VALUE ([map(xs, helper)]) is a real capability edge and a
      calls-only walk misses it entirely, which is fail-open. Mutated in place
      like [cap_closures], so it survives the per-declaration env folds.

      Recorded at exactly the [record_fn_caps] call sites, so a key here is a
      key there. Consumed only by [fn_transitive_capability_closures]. *)
  local_mods : string list StrMap.t;
  (** In-file nested modules → their PRIVATE value/function member names.
      Populated by the [Ast.DMod] export step.  A same-file qualified reference
      to a private member (e.g. `A.secret` where `secret` is a [pfn]) never gets
      an "A.secret" key in [vars] (only public members are exported), so the
      registry-based [qualified_error_msg] would misreport "Unknown module `A`"
      for a module that plainly exists in this file.  This lets that path
      recognize the member is merely private and emit the accurate
      "Function `secret` is private to module `A`." instead. *)
  offer_conts : (session_ty ref * (string * session_ty) list) list ref;
  (** Session-type OFFER continuation registry (F5 path-dependent refinement).
      Every [Chan.offer(ch)] registers the (physical) session ref it hands back
      alongside that offer's full label→continuation map.  Because the returned
      channel and the returned label atom come from the SAME offer, a later
      `match <label> do :L -> ... end` can refine the channel — whose session
      ref is registered here — to [branches[L]] for the duration of the `:L`
      arm, instead of always typing it at the FIRST branch's continuation (the
      old conservative-but-unsound-for-multi-branch approximation).  A shared
      mutable ref (like [nonexhaustive_match_spans]) so the registration made
      deep inside [infer_expr]'s [Chan.offer] arm is visible to [infer_block]'s
      let-destructuring, which builds the label→ref linkage in [offer_labels]. *)
  offer_labels : (string * (session_ty ref * (string * session_ty) list)) list;
  (** Label-variable → (offer channel's session ref, branches) linkage.
      Populated by [infer_block] when a `let (lbl, ch) = Chan.offer(...)`
      destructures an offer result: [ch]'s session ref is looked up in
      [offer_conts] and bound here under [lbl]'s name.  Read by the `match`
      typing ([infer_match] / the [check_expr] EMatch arm): when the scrutinee
      is such a [lbl] and an arm matches label `:L`, the shared ref is
      transiently set to [branches[L]] while that arm body is checked. *)
  offer_unrefined : session_ty ref list ref;
  (** Offer continuations awaiting per-arm refinement (F5 residual, 2026-07-24).
      [Chan.offer] registers the session ref it hands back here IFF the offer's
      branch continuations are not all identical — in that case the returned
      channel's real state depends on which label the peer chose at runtime, so
      operating on it before a `match` on the paired label refines it would type
      the channel at the FIRST branch (silent type confusion: compiled, a
      String payload gets read as an Int).  [with_offer_refinement] transiently
      removes the ref while checking a refined arm; the [Chan.*] operation arms
      reject any channel still listed here.  A shared mutable ref for the same
      reason [offer_conts] is one. *)
}

let make_env errors type_map = {
  vars = StrMap.empty; types = StrMap.empty; ctors = StrMap.empty; records = StrMap.empty;
  level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
  refs = ref []; current_decl = ref "";
  scheme_witnesses = Hashtbl.create 64;
  inst_witnesses = Hashtbl.create 256;
  interfaces = StrMap.empty; sigs = [];
  mod_needs = []; mod_need_scopes = []; module_caps = []; protocols = StrMap.empty; impls = StrMap.empty;
  import_tracker = ref [];
  import_idx = make_import_index ();
  local_fns = StrMap.empty;
  fn_arities = StrMap.empty;
  qual_fn_names = StrMap.empty;
  plain_let_names = StringSet.empty;
  proof_caps = [];
  always_linear_types = [];
  current_module = "";
  root_cap_allowed = false;
  cur_fn_public = false;
  cap_qual_prefix = "";
  enclosing_package = "";
  no_panic_mod = false;
  no_panic_modules = [];
  nonexhaustive_match_spans = ref [];
  cap_producer_ivars = Hashtbl.create 16;
  cap_narrow_factory_fns = Hashtbl.create 16;
  mint_cap_sites = ref [];
  cap_narrow_sites = ref [];
  json_cap_sites = ref [];
  pure_mod = false;
  no_extern_mod = false;
  deterministic_mod = false;
  cap_closures = Hashtbl.create 64;
  own_cap_closures = Hashtbl.create 64;
  fn_refs = Hashtbl.create 64;
  local_mods = StrMap.empty;
  offer_conts = ref [];
  offer_labels = [];
  offer_unrefined = ref [];
}

let enter_level env = { env with level = env.level + 1 }
let leave_level env = { env with level = env.level - 1 }

(** Run [f] with [env.current_decl] temporarily blanked to "" — for
    [surface_ty] calls that check a type with NO enclosing function (an
    interface method signature, an impl header/when-constraint type): without
    this, [env.current_decl] is left over from whatever [DFn] happened to be
    checked immediately before in module order (it is set only by [check_fn]
    and never reset — see [current_decl]'s doc comment), so a qualified
    `TyCon` reference recorded there would be silently misattributed to an
    unrelated function.  The [`TyCon] hook in [surface_ty] skips recording
    entirely when [caller = ""], so blanking here means "don't record a
    reference for this callerless type position" rather than emitting a
    deliberately-empty [caller].  [current_decl] is a mutable ref shared
    across all [env] copies (like [import_tracker]), so this must restore the
    prior value afterward — including when [f] raises — rather than leaving
    it blanked for whatever is checked next. *)
let with_no_caller (env : env) (f : unit -> 'a) : 'a =
  let saved = !(env.current_decl) in
  env.current_decl := "";
  Fun.protect ~finally:(fun () -> env.current_decl := saved) f

(** Is [r] an [offer] continuation still awaiting per-arm refinement?
    Physical identity on purpose: [env.offer_unrefined] tracks the exact ref
    [Chan.offer] minted, and the ref cell IS the channel's identity for the
    duration of the session (every [Chan.*] op mints a FRESH ref for its
    continuation, so a marked ref can never be confused with a later state of
    the same channel). *)
let offer_ref_unrefined env (r : session_ty ref) =
  List.exists (fun r' -> r' == r) !(env.offer_unrefined)

(** Depth of enclosing `match` arms that are a CATCH-ALL over an offer label
    (`_ ->` / a variable pattern, where [with_offer_refinement] cannot refine
    because the arm names no label).  Non-zero means the user did write a
    `match`, so the bare "match the label first" advice would read as wrong —
    the diagnostic appends the real explanation instead (a catch-all does not
    identify WHICH branch the peer chose).  A global counter rather than an
    [env] field because [env] is copied by every binding construct while this
    must track dynamic nesting of the checking recursion. *)
let offer_catchall_depth = ref 0

(** The shared body of the "unrefined `Chan.offer` continuation" diagnostic.
    [lead] names what is being attempted ("Chan.recv", "This channel"). *)
let offer_unrefined_message lead =
  Printf.sprintf
    "%s came from `Chan.offer`, and the protocol's branches \
     continue differently, so I don't know which one the peer chose.\n\
     Match on the label first — `match lbl do :ok -> ... :err -> ... end` — \
     and use the channel inside each arm.%s"
    lead
    (if !offer_catchall_depth > 0 then
       "\nA `_` catch-all arm is not enough: it does not identify which branch \
        the peer chose, so every label needs its own arm."
     else "")

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
    concrete cap, tagging is a no-op.

    RECURSES into container shapes (tuples, records, and other [TCon] type
    arguments) so the tag reaches a cap-producer var wrapped by a factory
    function's return type — e.g. [(Cap(a), Int)] or [Option(Cap(a))] — not
    just a bare top-level [Cap(a)]/[TVar].  Mirrors
    [ty_has_tagged_cap_producer]'s traversal exactly: that detector already
    walks containers to decide WHETHER to propagate the taint into a call's
    result (see its call sites below); before this fix, the tagging half of
    that pairing silently no-opped on any container shape it found (`| _ -> ()`),
    so a container-wrapped cap-producer var reaching a truly fresh (never
    independently tagged) result var never got marked.  (In practice this was
    not independently exploitable on this tree — the ORIGINAL cap_narrow-tagged
    var is forced monomorphic by [demote_to_monomorphic] and so is never
    re-instantiated by generalization, and [unify]'s hook propagates the tag to
    any var it gets bound to, including through element-wise tuple/record
    unification — but the asymmetry left the detector/tagger pairing at the
    call-propagation sites below inert for container-shaped results, which is
    latent risk independent of that protection.) *)
let rec tag_cap_producer_result (env : env) (rty : ty) (sp : Ast.span) : unit =
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
  | TCon (_, args)       -> List.iter (fun t -> tag_cap_producer_result env t sp) args
  | TArrow (a, b)        -> tag_cap_producer_result env a sp; tag_cap_producer_result env b sp
  | TTuple ts            -> List.iter (fun t -> tag_cap_producer_result env t sp) ts
  | TRecord flds         -> List.iter (fun (_, t) -> tag_cap_producer_result env t sp) flds
  | TLin (_, t)          -> tag_cap_producer_result env t sp
  | TNatOp (_, a, b)     -> tag_cap_producer_result env a sp; tag_cap_producer_result env b sp
  | TRefine (base, _, _) -> tag_cap_producer_result env base sp
  | TChan _ | TNat _ | TError -> ()

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

(** True iff the bare type name [name] resolves to an `always_linear` type *here*
    — i.e. it is registered always_linear AND the current module does NOT declare
    its OWN same-named type (which shadows the imported/stdlib one).  Bridges the
    L4 gap (a user `type Handle` was silently infected by stdlib's `always_linear
    Handle` because promotion matched the bare name globally) using the current
    module's declaration as the shadow signal — the same current-module
    preference [lookup_ctor_in_type]/the ctor system already use.  This is a
    stopgap: the principled fix is module-qualified type identity
    (specs/plans/2026-07-17-fqn-type-ctor-identity.md), which subsumes it. *)
let resolves_always_linear name env =
  (* If the current module declares its OWN same-named type, that declaration
     shadows any imported one, so promotion follows *its* linearity: promote iff
     the current module's own qualified type is always_linear (both bare and
     qualified names are registered by DAlwaysLinearType).  Otherwise there is no
     local shadow and the bare/imported linearity applies. *)
  if env.current_module <> ""
     && StrMap.mem (env.current_module ^ "." ^ name) env.types
  then List.mem (env.current_module ^ "." ^ name) env.always_linear_types
  else List.mem name env.always_linear_types

(** Resolve a bare constructor name to a candidate [ctor_info].  When several
    candidates share the bare name (e.g. two DIFFERENT modules each declaring
    their own `Shared`, kept distinct by [add_ctor] since Task 1 of the FQN
    dispatch-identity plan), prefer the candidate whose [ci_module] matches
    the reference's own LEXICAL current module — a bare `Shared` written
    inside `DcA`'s own code should mean `DcA`'s own `Shared`, not whichever
    candidate happens to be first in the internal list (order- and
    module-arrangement-dependent, and meaningless now that multiple genuinely
    different candidates can survive under one key). Falls back to the first
    candidate when the current module owns none of them (the caller is
    responsible for flagging that fallback as ambiguous when appropriate —
    see the `ECon`/`PatCon` cross-module hard-error check). *)
let lookup_ctor name env =
  match StrMap.find_opt name env.ctors with
  | None -> None
  | Some [] -> None
  | Some (first :: _ as cis) ->
    (match List.find_opt (fun ci -> ci.ci_module = env.current_module) cis with
     | Some _ as preferred -> preferred
     | None -> Some first)

(** Same-module precedence for an UNQUALIFIED constructor reference.

    When two sibling modules in the same package define distinct types that
    share a constructor name (e.g. `IslandSocket.Registry(List(IslandHandler))`
    and `Islands.Registry(List(Descriptor))`), the bare-name entry in
    [env.ctors] holds BOTH candidates and [lookup_ctor] returns whichever was
    registered last — a single global winner shared by every module, regardless
    of which module's body is being checked.  Since March keys nominal types by
    bare name, both `Registry`s look identical at the type level; only the
    constructors' argument types differ, so the wrong candidate silently unifies
    the sibling's element type in (the observed "expected Descriptor but got
    IslandHandler").

    A module's own top-level definition must outrank a same-named one from a
    module it does not even import.  [prebind_mod_members] seeds a
    module-qualified key `Module.Ctor` (bare [ci_type]) for every module's
    public constructors, keyed by the ACCUMULATED, entry-unwrapped module path
    (e.g. a sibling `Islands` seeds `Islands.Registry`; a nested `mod Outer do
    mod Inner` under the unwrapped entry seeds `Inner.Registry`; a nested
    module under a non-entry `Outer` seeds `Outer.Inner.Registry`).  We look the
    bare name up under the current module's own such key first.

    The key must exactly match prebind's accumulated path.  [cap_qual_prefix]
    tracks precisely that path (accumulated across enclosing [DMod]s, empty at
    the TIR-unwrapped entry level — see its field doc).  At the unwrapped entry
    level [cap_qual_prefix] is "" while prebind still seeds under the entry
    module name, which [current_module] holds — so use [cap_qual_prefix] when
    set and fall back to [current_module] at the entry level.  This makes
    same-module precedence work for top-level siblings, dotted single-decl
    module names, AND arbitrarily nested modules.

    If the current module does not define [name] the key is absent and we fall
    through to the existing resolution — preserving imported names and
    d95fe942's order-independence for genuinely cross-module bare references,
    whose module path does not match the definer's.

    Ambiguity guard: the `Module.Ctor` key shares its STRING namespace with the
    `Type.Ctor` disambiguation form prebind also seeds (see the `bare_type_qctor`
    site).  When a module's leaf name coincides with a DIFFERENT package's TYPE
    name (real case: bastion `mod Gate` with an opaque `type Gate`, vs depot's
    `mod Depot.Gate` whose regular `type Gate` seeds the disambiguation key
    `Gate.Gate`), the `Gate.Gate` bucket holds BOTH ctors and the head is
    order-dependent — exactly the pollution same-module precedence is meant to
    avoid.  So only trust this key when it resolves UNAMBIGUOUSLY to one ctor;
    otherwise return None and let the caller fall through.  For an opaque type
    the module's own bare-`Ctor` key wins the head during its Pass-2 check (its
    private ctor is never prebind-seeded into the bare key, so nothing displaces
    it), making the bare fallback correct there. *)
let lookup_ctor_same_module name env =
  let self = if env.cap_qual_prefix <> "" then env.cap_qual_prefix
             else env.current_module in
  if self = "" || String.contains name '.' then None
  else match StrMap.find_opt (self ^ "." ^ name) env.ctors with
    | Some [ci] -> Some ci
    | _ -> None

(** Find the constructor [name] that belongs to [type_name] among the candidates
    registered under that bare name.  A bare constructor name can be shared by
    several ADTs (e.g. `Text` in both `Inline` and `XmlNode`); when more than
    one candidate matches [type_name] (the same-short-name cross-module
    collision case), prefer the one whose [ci_module] matches the reference's
    own lexical current module, same as [lookup_ctor] above. When the
    expected/scrutinee type is known, this lets us pick the candidate that
    actually matches it. *)
let lookup_ctor_in_type name type_name env =
  match StrMap.find_opt name env.ctors with
  | None -> None
  | Some cis ->
    let matching = List.filter (fun (ci : ctor_info) -> ci.ci_type = type_name) cis in
    (match List.find_opt (fun ci -> ci.ci_module = env.current_module) matching with
     | Some _ as preferred -> preferred
     | None -> (match matching with [] -> None | first :: _ -> Some first))

(** Like [lookup_ctor_in_type] but returns a candidate ONLY when it is the sole
    one whose parent type matches [type_name].  When two DISTINCT types in the
    same package share a constructor name (e.g. `IslandSocket.Registry` and
    `Islands.Registry`, both with bare [ci_type] "Registry"), an expected type
    of `Registry` matches BOTH candidates — [lookup_ctor_in_type] would return
    the order-dependent head, silently defeating same-module precedence.  This
    variant reports no match in that ambiguous case so the caller falls through
    to same-module resolution, while a KNOWN scrutinee type whose name is unique
    among the candidates (the Finding-1 case: local `Local = Reg(Int)` vs
    imported `Remote = Reg(String)`) still wins outright. *)
let lookup_ctor_in_type_unique name type_name env =
  match StrMap.find_opt name env.ctors with
  | Some cis ->
    (match List.filter (fun (ci : ctor_info) -> ci.ci_type = type_name) cis with
     | [ci] -> Some ci
     | _ -> None)
  | None -> None

(** Add [ci] under [key] in [ctors], keeping all infos for the same name.
    Deduplicates STRUCTURALLY (same ci_type, ci_module, ci_params, and
    ci_arg_tys) — but by MOVING the existing entry to the FRONT rather than
    no-op'ing.  Two types with the same short name but different arity (e.g.
    stdlib's `Tree(a)` and a user's `Tree`) are kept as distinct candidates.
    So are two DIFFERENT modules' identically-shaped ctors (e.g. both a
    nullary `Shared` on a type named `Thing`) — [ci_module] is part of the
    comparison (FQN dispatch-identity plan, Task 1) precisely so this case
    is no longer treated as "the same ctor" and does not collapse the
    second registration onto the first.

    Why move-to-front matters (sibling-ctor shadowing regression,
    2026-07-10): Pass-1 prebind seeds every nested module's bare ctor keys
    for order-independent cross-module resolution (d95fe942), in module
    declaration order — so a later sibling `mod B`'s `Mk` sits AHEAD of
    `mod A`'s same-named `Mk`.  Pass-2 then re-registers each module's own
    ctors (check_decl DType) right before checking that module's bodies —
    but the re-registration is structurally identical to the Pass-1 seed
    (SAME ci_module both times, since a module always re-registers its OWN
    ctors), so a no-op dedup left B's candidate at the head and A's OWN body
    resolved `Mk(1)` against B's `Mk(String)` ("expected String but got
    Int" pointing inside A).  Moving the re-registered entry to the front
    restores the declaring module's recency for its own body check (the
    pre-d95fe942 semantics) while keeping the Pass-1 seeds — and therefore
    the cross-module order-independence — intact.  A singleton list is
    unaffected; only genuinely shared names reorder.  Adding [ci_module] to
    the comparison does not disturb this: same-module re-registration always
    has matching [ci_module] on both sides, so it is unaffected; only
    cross-module identically-shaped ctors (previously wrongly deduped) now
    stay distinct. *)
let add_ctor (key : string) (ci : ctor_info) (ctors : ctor_info list StrMap.t) =
  let lst = Option.value ~default:[] (StrMap.find_opt key ctors) in
  let same c =
    c.ci_type = ci.ci_type
    && c.ci_module = ci.ci_module
    && c.ci_params = ci.ci_params
    && c.ci_arg_tys = ci.ci_arg_tys
  in
  if List.exists same lst then
    (match lst with
     | first :: _ when same first -> ctors   (* already at the front *)
     | _ -> StrMap.add key (ci :: List.filter (fun c -> not (same c)) lst) ctors)
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
    Returns None if the name contains no dot.

    Splits at the LAST dot, not the first: [member] is always a single
    trailing identifier (a function/type/ctor name, never itself dotted), so
    everything before it is the module path — correct for both flat stdlib
    names ("List.map") and dotted ones ("Js.Canvas.draw_node", where the
    module is "Js.Canvas" and rindex is needed to avoid mis-splitting into
    module "Js" + member "Canvas.draw_node", which no stdlib file can ever
    satisfy). App-local multi-component paths like "Conduit.Storage.foo"
    (interface methods registered under a shorter suffix) are unaffected:
    [Module_registry.ensure_loaded] on "Conduit.Storage" misses exactly as
    it did on "Conduit" before, since neither is a real stdlib module, so
    every caller's existing miss-and-fall-through behavior is unchanged —
    this only adds resolution for module paths that genuinely exist. *)
let split_qualified (name : string) : (string * string) option =
  match String.rindex_opt name '.' with
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
         modules (e.g. `ConsistentHash.HashRing(String)` on a param) while
         only its CONSTRUCTOR is hidden — enforced by the [ExCtor] gate below.
         [ExFn] additionally seeds [qual_fn_names] so the [EVar] reference-
         recording hook can tell a genuine function export (`ExFn`) apart
         from a plain value/constant export (`ExValue`) — see
         [qual_fn_names]'s doc comment. *)
      if not entry.ex_public then env
      else if StrMap.mem qname env.vars then env
      else
        let env = { env with vars = StrMap.add qname (Mono (fresh_var 0)) env.vars } in
        (match entry.ex_kind with
         | ExFn -> { env with qual_fn_names = StrMap.add qname () env.qual_fn_names }
         | _ -> env)
    | ExType arity ->
      (* Register the qualified name AND the BARE type name.  March uses a single
         global type namespace (see [surface_ty]'s [canon_name]): a type's bare
         name is its canonical identity, and a sibling module resolves a peer
         type UNQUALIFIED (`scope : UniqueScope`, no `use`/`import`).  When the
         defining module is PREBOUND FROM SOURCE, [prebind_mod_members] (:8931)
         seeds the bare name; when it is loaded from the compiled Module_registry
         instead (e.g. a dependency in the `--compile`/`--test` unit), only the
         qualified key was seeded — so expanding a registry-loaded RECORD whose
         field references a bare sibling type failed with a bogus "I cannot find
         `UniqueScope`" pointing at the definer's field span.  Seed the bare name
         too, first-wins (don't clobber a name a source module already bound),
         mirroring the source-prebind path. *)
      let env = if StrMap.mem qname env.types then env
                else { env with types = StrMap.add qname arity env.types } in
      if StrMap.mem entry.ex_name env.types then env
      else { env with types = StrMap.add entry.ex_name arity env.types }
    | ExRecord (arity, field_decls) ->
      let param_names = List.init arity (fun i -> Printf.sprintf "$t%d" i) in
      let env1 = if StrMap.mem qname env.types then env
                 else { env with types = StrMap.add qname arity env.types } in
      (* Bare type name too — see the [ExType] arm's rationale. *)
      let env1 = if StrMap.mem entry.ex_name env1.types then env1
                 else { env1 with types = StrMap.add entry.ex_name arity env1.types } in
      (* Register the record's fields under BOTH the qualified and bare keys so a
         bare cross-module reference (or a peer module's bare field type) expands
         structurally instead of staying an opaque TCon. *)
      let env1 = { env1 with records = StrMap.add qname (param_names, field_decls) env1.records } in
      if StrMap.mem entry.ex_name env1.records then env1
      else { env1 with records = StrMap.add entry.ex_name (param_names, field_decls) env1.records }
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
          ci_module = mod_name;
          ci_vis = if entry.ex_public then Ast.Public else Ast.Private;
          (* Only a name + arity crosses the export bridge, not the original
             ctor_info record — this is the one place ci_is_actor_msg can't be
             read off a known fact, so it's derived the same way
             Tir_names.is_actor_msg_name does post-lowering (see that
             function's doc comment for why the "_Msg"-suffix collision risk
             is accepted there); see this field's own doc comment above. *)
          ci_is_actor_msg =
            (let sfx = "_Msg" in
             let nl = String.length parent_type and sl = String.length sfx in
             nl > sl && String.sub parent_type (nl - sl) sl = sfx);
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

(** True if [name] is a dotted qualified reference (`Mod.member`) whose
    `member` is CONFIRMED private — either an in-file nested module's `pfn` /
    private `let` (via [env.local_mods]) or a private export of a module
    reachable through the registry.  Used to stop [EVar]'s progressive
    dot-suffix fallback (see its use site) from silently resolving a privacy
    violation to an unrelated same-named global (e.g. a bare interface
    method or builtin) instead of reporting the violation. *)
let is_confirmed_private_qualified (name : string) (env : env) : bool =
  match split_qualified name with
  | None -> false
  | Some (mod_name, member) ->
    (match StrMap.find_opt mod_name env.local_mods with
     | Some priv when List.mem member priv -> true
     | _ ->
       match March_modules.Module_registry.ensure_loaded mod_name with
       | None -> false
       | Some exports ->
         let open March_modules.Module_registry in
         List.exists (fun e -> e.ex_name = member && not e.ex_public) exports.me_entries)

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

(** Like [all_ctors_named], but returns (type_name, declaring_module) pairs
    without deduping by type_name alone — so two DIFFERENT modules' same-
    short-name colliding types (which share [ci_type]) are counted as
    distinct candidates. Used only by the genuinely-ambiguous-reference
    hard-error check below; [all_ctors_named]'s existing bare-type-name
    callers are untouched. *)
let all_ctor_candidates_named (name : string) (env : env) : (string * string) list =
  match StrMap.find_opt name env.ctors with
  | None -> []
  | Some cis ->
    let seen = Hashtbl.create 4 in
    List.filter_map (fun ci ->
        let key = (ci.ci_type, ci.ci_module) in
        if Hashtbl.mem seen key then None
        else begin Hashtbl.add seen key (); Some key end
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

(* Binding a value name SHADOWS any same-named module fn for the direct-call
   arity check ([fn_arities], consulted at the EApp rule): a param/let/pattern
   binding named e.g. `f` must not have calls `f(x, y)` checked against a
   TOP-LEVEL `fn f`'s declared arity.  [fn_arities] is name-keyed and
   accumulates across modules, so without this removal a stdlib param like
   fold_left's `f : b -> a -> b` collides with ANY user/other-module `fn f`
   of a different arity — the false arity error is reported at the STDLIB
   span (silently filtered by bin/main.ml's is_user_file), the call is
   "recovered" as a PARTIAL application (peel), the enclosing fn's recursive
   call then hits an occurs failure (acc := elem -> acc), the type var is
   linked to TError, and the poisoned type_map lowers fold_left with a
   function-typed accumulator temp — the runaway "Monomorphization limit
   reached: List.fold_left > 512 specializations" ICE, plus TError-typed
   ('_err) stdlib values misclassified by codegen.  The env is functional,
   so the removal scopes exactly like the shadowing binding itself.  The few
   TOP-LEVEL fn (re)binding sites re-add the entry immediately after
   (module prebinds, check_decl's DFn rebind, check_fn's self-bind).
   Regression note: this fix (commit c6599af9) was lost in the PR #27/#38
   merge-conflict resolution and restored here. *)
(* [offer_labels] shadowing discipline (F5 residual, 2026-07-24 review fix):
   [offer_labels] links a NAME (e.g. `lbl` in `let (lbl, ch) = Chan.offer(...)`)
   to a session ref, keyed on the string alone — the same name-keying hazard
   [fn_arities] above is already guarded against.  `bind_var`/`bind_linear` are
   the two chokepoints EVERY binding construct funnels through (plain `let`,
   lambda/`fn` params, `match` pattern bindings all eventually call one of
   these) so rebinding a name here retires any stale [offer_labels] entry for
   it — otherwise `let lbl = :ok` after `let (lbl, ch) = Chan.offer(...)`
   would leave the OLD entry reachable by `List.assoc_opt "lbl"`, and
   `with_offer_refinement` would refine (and un-mark) an unrelated channel
   based on a label the peer never actually returned: the exact `Chan.offer`
   soundness hole this file's [offer_unrefined] field exists to close, just
   reached through a shadowed name instead of a bare missing `match`. *)
(* [local_fns] shadowing discipline (mirrors the [fn_arities]/[plain_let_names]
   removals above): [local_fns] marks a name as "genuinely the current
   module's own top-level fn" and the [EVar] Call-ref-recording hook
   (`forge search --callers`) trusts that membership check alone to decide
   whether a bare-name use is a real call to that top-level fn. Without
   retiring the entry here, a parameter or local `let` that shadows a
   top-level fn name (e.g. `fn wrapper(helper) do helper() end` when `helper`
   is also a top-level fn) would have its LOCAL variable's use misrecorded as
   a call to the shadowed top-level fn — a textual name match masquerading as
   a resolution-based one. *)
let bind_var name sch env =
  { env with vars = StrMap.add name sch env.vars;
             fn_arities = StrMap.remove name env.fn_arities;
             plain_let_names = StringSet.remove name env.plain_let_names;
             local_fns = StrMap.remove name env.local_fns;
             offer_labels = List.filter (fun (n, _) -> n <> name) env.offer_labels }

let bind_vars bindings env =
  List.fold_left (fun e (n, s) -> bind_var n s e) env bindings

(** Extend env with a new linear/affine variable. *)
let bind_linear name lin ty env =
  let le = { le_name = name; le_lin = lin; le_used = ref false; le_first_use = ref None } in
  { env with
    vars = StrMap.add name (Mono ty) env.vars;
    fn_arities = StrMap.remove name env.fn_arities;
    plain_let_names = StringSet.remove name env.plain_let_names;
    lin  = le :: env.lin;
    offer_labels = List.filter (fun (n, _) -> n <> name) env.offer_labels }

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
let instantiate ?use_span level env = function
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
    (* A1 witnesses: record the scheme (deduped by ids) and, if this call
       site supplied a span, the instantiation's type-argument vector. The
       fresh vars in `subst` are ordinary unification vars; they resolve
       through repr after the module solves, so store them as-is and let the
       emitter deep-repr them at serialization time. *)
    Hashtbl.replace env.scheme_witnesses ids (cs, ty);
    (match use_span with
     | Some sp -> Hashtbl.replace env.inst_witnesses sp (ids, List.map snd subst)
     | None -> ());
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

(** Source files loaded as the standard library, set by the driver.

    [prelude.march] is deliberately unwrapped into GLOBAL scope, so its
    declarations are prepended to the ENTRY module's decl list and are
    indistinguishable from the user's own by shape alone. Check 1b dedups its
    body-scan to one (capability, span) pair and keeps the FIRST, so a
    capability prelude also uses got a prelude span — which the driver's
    [is_user_file] filter then discarded, silently.

    Measured: [println] in a plain function body produced NO Check 1b warning
    while [file_exists] in the same module did, purely because prelude calls
    [println] three times and never calls [file_exists]. The diagnostic was
    generated and thrown away. That suppressed Check 1b for every capability
    the standard library happens to use, not just IO.Console.

    Mirrors [Refine_check.stdlib_source_files], which exists for the same
    "whose declaration is this really?" question. *)
let stdlib_source_files : string list ref = ref []

let span_is_stdlib (sp : Ast.span) : bool =
  List.mem sp.Ast.file !stdlib_source_files

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
  (* IO.WebSocket — a least-privilege sub-cap of IO.NetConnect; a module that
     only speaks WebSocket can declare `needs IO.WebSocket` instead of the
     broader `needs IO.NetConnect`, mirroring IO.NetConnect.TLS. *)
  ("ws_recv",               "IO.WebSocket");
  ("ws_send",               "IO.WebSocket");
  ("ws_select",             "IO.WebSocket");
  (* IO.Network *)
  ("dns_resolve",           "IO.Network");
  (* IO.NetListen *)
  ("tcp_listen",            "IO.NetListen");
  ("tcp_accept",            "IO.NetListen");
  ("tcp_local_port",        "IO.NetListen");
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
  (* IO.Signal *)
  ("signal_watch",          "IO.Signal");
  ("signal_unwatch",        "IO.Signal");
  ("signal_raise_self",     "IO.Signal");
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

(** The names a module DECLARES directly (bare [DFn]s and top-level [DLet]
    [PatVar]s) — exactly the set that wins real name resolution over a global
    builtin of the same bare name at this module's scope (verified:
    interpreted and compiled, a module-level `fn`/`let` of the same name is
    what actually runs, never the builtin).

    Every capability-inference pass below is a raw SYNTACTIC scan
    ([March_ast.Calls.names_and_name_spans]) matching a call's NAME against
    [builtin_cap_table]/a derived banned-set, with no resolution awareness.
    Before this existed, EVERY one of them treated an ordinary function named
    `file_read`, `random_bytes`, `dns_resolve`, … — or a `cap pure`/
    `cap deterministic` module's own same-named helper — as a call to the
    capability-bearing builtin of that name, and (since Check 1b's severity
    flip, 2026-08-06) that is a hard, default-on compile ERROR demanding a
    capability the program never uses (specs/2026-08-09-cap-loose-ends-plan.md,
    Tier 0).

    Deliberately NOT extended to nested-module names (already immune — a
    nested module's qualified TIR/AST name, e.g. "Lib.file_read", never
    string-matches a bare table key) or to a parameter/local `let` shadowing
    a builtin WITHIN a function body (a real, rarer residual gap needing
    actual scope-aware resolution these AST-level passes don't have — filed
    as a follow-up, not blocking this fix).

    ONE shared implementation rather than one per call site: this codebase
    has repeatedly been bitten by near-duplicate capability walks drifting
    apart (the "two-tables-drift" pattern) — [check_module_needs],
    [check_pure_module] and [check_deterministic_module] all consult this,
    rather than each re-deriving its own notion of "locally declared". *)
let locally_declared_names_of (decls : Ast.decl list) : (string, unit) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter (function
      (* STDLIB-SPAN declarations must NOT count as "locally declared":
         prelude is unwrapped into the ENTRY module's OWN flat [decls] list
         (see [check_module_needs]'s dedup-first-span comment, and
         [own_caps_of_this_module]'s identical trap), so without this filter
         prelude's `println`/`print`/etc. — sitting in the SAME [decls] this
         function scans for the entry module — were themselves treated as
         "locally declared", shadowing every entry-module call to `println`.
         Measured: a program with NO `needs` at all calling bare `println`
         WRONGLY TYPECHECKED (a corpus regression,
         reject/t40_migrate_state_does_io.march, caught by the corpus sweep
         after the naive first version of this function shipped — the OCaml
         unit tests for the shadowing fix all used the bare, no-stdlib
         [typecheck] helper and could not have caught it). *)
      | Ast.DFn (def, sp) when not (span_is_stdlib sp) ->
        Hashtbl.replace tbl def.Ast.fn_name.Ast.txt ()
      | Ast.DLet (_, b, sp) when not (span_is_stdlib sp) ->
        (match b.Ast.bind_pat with
         | Ast.PatVar n -> Hashtbl.replace tbl n.Ast.txt ()
         | _ -> ())
      | _ -> ())
    decls;
  tbl

(** [cap_subsumes parent child] — true if [parent] is an ancestor of (or equal to) [child].
    E.g., cap_subsumes "IO" "IO.FileRead" = true.
    See [March_caps.Cap_lattice.cap_subsumes]. *)
let cap_subsumes = March_caps.Cap_lattice.cap_subsumes

(** [same_package_namespace a b] — do two module paths belong to the same
    top-level namespace?  ["Conduit.RateLimiter"] and ["Conduit"] do; neither
    shares one with ["Compress.Gzip"].

    Used to decide whether a bare constructor reference is genuinely ambiguous.
    Exact current-module equality is too strict: a package that declares a type
    in `mod Pkg` and matches on its constructors from `mod Pkg.Sub` owns both
    sides, but the two module paths differ, so an unrelated stdlib type sharing
    the constructor name made the package's own code ambiguous against a type
    it never imported.  Measured on conduit, whose `RateLimiterBackend.Custom`
    collided with `Compress.Gzip.Level.Custom`. *)
(* Every module path that could carry the current code's package namespace.
   All three are consulted rather than the first non-empty, because which one
   holds it depends on how the code was reached:
     - a dotted top-level `mod Pkg.Sub` puts the whole path in current_module;
     - a nested `mod Sub` leaves only the bare name there, and the package name
       is in enclosing_package;
     - the multi-file check path wraps everything in a synthetic "LibCheck"
       module, which makes enclosing_package useless but leaves current_module
       correct.
   Consulting only one of them misses whichever shape it does not cover. *)
let local_module_paths env =
  List.filter (fun s -> s <> "")
    [ env.current_module; env.cap_qual_prefix; env.enclosing_package ]

let same_package_namespace (a : string) (b : string) : bool =
  let root p = match String.index_opt p '.' with
    | None -> p
    | Some i -> String.sub p 0 i
  in
  a <> "" && b <> "" && root a = root b

(** [cap_path_of_names names] joins AST name list to dot-string. *)
let cap_path_of_names names =
  String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names)

(** [cap_paths_in_surface_ty ty] returns all Cap(X) paths referenced in [ty].

    Delegates to [Cap_surface_ty.caps_in_ty], which the desugarer's [derive
    Json] rejection uses too.  This was a private copy here until 2026-08-05;
    it now shares one exhaustive implementation, because a capability walk
    maintained in two places drifts, and a drifted capability walk is a silent
    hole rather than a visible bug.

    One behaviour change came with the move: the old copy skipped
    [Tagged(_, _)]'s arguments outright, to avoid mistaking the marker
    argument for a capability.  The shared walk recurses instead.  The marker
    is a nullary constructor whose name is not "Cap", so it still extracts
    nothing — while [Tagged(R, Cap(IO))], which the old copy could not see at
    all, is now found. *)
let cap_paths_in_surface_ty (ty : Ast.ty) : string list =
  March_caps.Cap_surface_ty.caps_in_ty ty

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
    ("string_to_codepoints",  Mono (TArrow (t_string, t_list t_int)));
    ("string_from_codepoint", Mono (TArrow (t_int, t_option t_string)));
    ("string_concat",  Mono (TArrow (t_string, TArrow (t_string, t_string))));
    ("read_line",      Mono (TArrow (t_unit,   t_string)));
    ("read_byte",      Mono (TArrow (t_unit,   t_int)));
    (* Signal.watch(code, handler): register a deferred handler for an OS
       signal; signal_unwatch(code) removes it. See stdlib/signal.march. *)
    ("signal_watch",   Mono (TArrow (t_int, TArrow (TArrow (t_unit, t_unit), t_unit))));
    ("signal_unwatch", Mono (TArrow (t_int, t_unit)));
    ("signal_raise_self", Mono (TArrow (t_int, t_unit)));
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
    (* from_json_events: same rationale as from_json above (Task 7 / Phase
       B) -- a second, event-consuming decoder derived per record type,
       bound as a plain (non-impl_tbl-dispatched) name per derive so
       multiple types deriving Json in one module can each define it
       without colliding with the polymorphic scheme registered here. *)
    ("from_json_events", poly2 (fun a b -> TArrow (a, b)));
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
    ("string_index_of_from", Mono (TArrow (t_string, TArrow (t_string, TArrow (t_int, t_option t_int)))));
    ("string_replace",      Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_replace_all",  Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
    ("string_split",        Mono (TArrow (t_string, TArrow (t_string, t_list t_string))));
    ("string_concat3",      Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string, t_string)))));
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
    ("string_byte_at",      Mono (TArrow (t_string, TArrow (t_int, t_int))));
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
    (* Capability builtins.  root_cap is a bare value (use `root_cap`, never
       `root_cap()`) — see [noncallable_builtin_values]. *)
    ("root_cap",   Mono (TCon ("Cap", [TCon ("IO", [])])));
    (* R4a (2026-08-06): source is [Cap(a)], not [Cap(IO)], so attenuation can
       CHAIN — a holder of [Cap(IO.FileSystem)] can hand out
       [Cap(IO.FileRead)].  Before this, the argument was literally the root,
       so only [main] could attenuate and least-privilege threading was
       unwritable past the first hop.
       The monotonicity that the old argument type enforced structurally (a
       widen simply failed to unify) now lives in [check_cap_narrow_sites].
       That is weaker IN KIND — an application site the sweep does not record
       is a silently permitted widen — which is why every site is recorded at
       one place below and why reject/t153-t155 are the load-bearing witnesses
       rather than decorative ones. *)
    ("cap_narrow", poly2 (fun a b -> TArrow (TCon ("Cap", [a]), TCon ("Cap", [b]))));
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
    (* [ActorCap], NOT [Cap] (2026-08-06).  These are process capabilities —
       a revocable, epoch-checked reference to a live actor, represented at run
       time as [VCap (pid, epoch)] and consumed by [send_checked] /
       [revoke_cap] / [is_cap_valid].  An IO capability is a different thing
       entirely: [VUnit], fully erased, governed by [needs] and the lattice.

       They shared the [Cap] constructor until 2026-08-06 and therefore
       UNIFIED, which meant [get_cap]'s unconstrained [a] could bind to [IO]
       and hand a module the root capability it was never granted — defeating
       R2 in two lines with no actor declared.  See the R8 audit
       (specs/2026-08-06-r8-runtime-hatch-audit.md) and reject/t158.

       Splitting the constructor rather than sweeping [get_cap]'s sites is
       deliberate: a sweep patches one symptom, while the conflation would keep
       producing them for every future builtin returning [Cap(a)].

       A consequence worth naming: [ActorCap] is invisible to [needs], because
       [Cap_surface_ty.caps_in_ty] matches [Cap].  That is correct — a process
       capability is not IO authority and never should have required a
       declaration. *)
    ("get_cap",      poly1 (fun a -> TArrow (TCon ("Pid", [a]), TCon ("Option", [TCon ("ActorCap", [a])]))));
    (* [ActorCap]'s parameter is the actor's STATE type (it flows from
       get_cap : Pid(a) -> Option(ActorCap(a)) and, since spawn returns
       Pid[state], is the concrete state record); the MESSAGE argument is an
       unrelated constructor type — a distinct variable.  Tying both to `a`
       only ever typechecked while spawn yielded Pid[<fresh>]. *)
    ("send_checked", poly2 (fun a b -> TArrow (TCon ("ActorCap", [a]), TArrow (b, t_atom))));
    ("revoke_cap",   poly1 (fun a -> TArrow (TCon ("ActorCap", [a]), t_atom)));
    ("is_cap_valid", poly1 (fun a -> TArrow (TCon ("ActorCap", [a]), t_bool)));
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
    (* File I/O builtins.
       All of these fail with a concrete `File.FileError` value at runtime
       (see eval.ml's file_error_of_unix/file_error_of_sys) — never an
       arbitrary caller-chosen type — so the error type is Mono, not a
       polymorphic `e`.  Registering it as poly1 previously let a caller
       declare an incompatible Result(_, T) and typecheck with zero errors,
       then panic the moment the bound error value was used as T. *)
    ("file_exists",     Mono (TArrow (t_string, t_bool)));
    ("file_read",       Mono (TArrow (t_string, t_result t_string (TCon ("FileError", [])))));
    ("file_write",      Mono (TArrow (t_string, TArrow (t_string, t_result t_unit (TCon ("FileError", []))))));
    ("file_append",     Mono (TArrow (t_string, TArrow (t_string, t_result t_unit (TCon ("FileError", []))))));
    ("file_delete",     Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    ("file_copy",       Mono (TArrow (t_string, TArrow (t_string, t_result t_unit (TCon ("FileError", []))))));
    ("file_rename",     Mono (TArrow (t_string, TArrow (t_string, t_result t_unit (TCon ("FileError", []))))));
    ("file_stat",       Mono (TArrow (t_string, t_result (TCon ("FileStat", [])) (TCon ("FileError", [])))));
    ("file_open",       Mono (TArrow (t_string, t_result t_int (TCon ("FileError", [])))));
    ("file_read_line",  Mono (TArrow (t_int, t_option t_string)));
    ("file_read_chunk", Mono (TArrow (t_int, TArrow (t_int, t_option t_string))));
    ("file_close",      Mono (TArrow (t_int, t_unit)));
    (* Structured cleanup: try_finally(action: () -> a, cleanup: () -> b) : a *)
    ("try_finally",
      poly2 (fun a b -> TArrow (TArrow (t_int, a),
                                TArrow (TArrow (t_int, b), a))));
    (* CSV builtins — csv_next_row returns CsvRow (declared in csv.march).
       The TIR registers user ptypes under their module-qualified name
       ("Csv.CsvRow"), so this MUST match that qualification: a bare
       "CsvRow" here makes Repr.niche_repr_of_concrete's find_variant miss
       the type definition and silently fall back to Boxed, even though
       CsvRow is niche-shaped (CsvEof nullary + Row single-payload). Under
       Boxed the compiled match reads a heap object's tag byte, but the C
       runtime returns raw NULL for EOF (a Niche-only convention) — so every
       row is misread against an uninitialized tag. *)
    (* csv_open's error is always a concrete Csv.CsvError value at runtime
       (see eval.ml's csv_open_impl) — Mono, not a polymorphic `e`. CsvError
       isn't niche-shaped (both variants carry a payload) so, unlike CsvRow
       above, the bare name is fine here. *)
    ("csv_open",     Mono (TArrow (t_string, TArrow (t_string, TArrow (t_atom, t_result t_int (TCon ("CsvError", [])))))));
    ("csv_next_row", Mono (TArrow (t_int, TCon ("Csv.CsvRow", []))));
    ("csv_close",    Mono (TArrow (t_int, t_atom)));
    (* TCP/HTTP transport builtins *)
    (* tcp_listen(port): binds+listens on port, returns Ok(listen_fd) or Err(reason) *)
    ("tcp_listen",              Mono (TArrow (t_int, t_result t_int t_string)));
    (* tcp_accept(listen_fd): blocks until a client connects, returns Ok(client_fd) or Err *)
    ("tcp_accept",              Mono (TArrow (t_int, t_result t_int t_string)));
    (* tcp_local_port(fd): the local (bound) port of a socket — the OS-assigned
       one when listened on port 0. Returns Ok(port) or Err(reason). *)
    ("tcp_local_port",          Mono (TArrow (t_int, t_result t_int t_string)));
    (* tcp_connect/send_all/recv_all always fail with a String reason (see
       eval.ml and runtime/march_http.c) — Mono, matching tcp_listen/tcp_accept
       above rather than leaving the error type unconstrained. *)
    ("tcp_connect",             Mono (TArrow (t_string, TArrow (t_int, t_result t_int t_string))));
    ("tcp_send_all",            Mono (TArrow (t_int, TArrow (t_string, t_result t_unit t_string))));
    ("tcp_recv_all",            Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, t_result t_string t_string)))));
    ("tcp_close",               Mono (TArrow (t_int, t_unit)));
    (* tcp_peer_addr(fd): numeric IP of the connected peer; "" when unavailable *)
    ("tcp_peer_addr",           Mono (TArrow (t_int, t_string)));
    ("dns_resolve",             Mono (TArrow (t_string, t_result (t_list t_string) t_string)));
    (* tcp_recv_exact(fd, n): reads exactly n bytes, returns Result(Bytes, String) *)
    ("tcp_recv_exact",          Mono (TArrow (t_int, TArrow (t_int, t_result (TCon ("Bytes", [])) t_string))));
    (* md5(s): returns 32-char lowercase hex digest *)
    ("md5",                     Mono (TArrow (t_string, t_string)));
    ("tcp_recv_http",           Mono (TArrow (t_int, TArrow (t_int, t_result t_string t_string))));
    ("tcp_recv_http_headers",   Mono (TArrow (t_int, t_result (TTuple [t_string; t_int; t_bool]) t_string)));
    ("tcp_recv_chunk",          Mono (TArrow (t_int, TArrow (t_int, t_result t_string t_string))));
    ("tcp_recv_chunked_frame",  Mono (TArrow (t_int, t_result t_string t_string)));
    (* http_serialize_request(method, host, path, query_opt, headers, body) -> String *)
    ("http_serialize_request",  Mono (TArrow (t_string, TArrow (t_string, TArrow (t_string,
        TArrow (t_option t_string, TArrow (t_list (TCon ("Header", [])), TArrow (t_string, t_string))))))));
    ("http_parse_response",     Mono (TArrow (t_string,
        t_result (TTuple [t_int; t_list (TCon ("Header", [])); t_string]) t_string)));
    (* http_fetch / http_fetch_available: JS-only fetch path used by
       HttpTransport.request (stdlib/http_transport.march).  On native builds
       http_fetch_available() always returns false (see runtime/march_http.c),
       so http_fetch itself is never actually invoked — the tcp_* socket path
       handles the request instead.  Both are registered here (Bool / a
       concrete Result(String,String)) so the call sites get a real static
       type instead of falling through llvm_emit's generic erased-type path,
       which expects a different (boxed) representation than a raw Bool. *)
    ("http_fetch_available",    Mono t_bool);
    ("http_fetch",              Mono (TArrow (t_string, TArrow (t_string,
        TArrow (t_string, TArrow (t_string, t_result t_string t_string))))));
    (* http_server_listen(port, max_conns, idle_timeout, pipeline_fn) *)
    ("http_server_listen",      poly1 (fun a -> TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (TArrow (a, a), t_unit))))));
    (* http_server_spawn_n(port, n, max_conns, idle_timeout, pipeline_fn) -> Int (pid) *)
    ("http_server_spawn_n",     poly1 (fun a -> TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (t_int, TArrow (TArrow (a, a), t_int)))))));
    ("http_server_wait",        Mono (TArrow (t_int, t_unit)));
    (* WebSocket builtins — WsFrame and SelectResult declared in websocket.march *)
    ("ws_recv",   Mono (TArrow (t_int, TCon ("WsFrame", []))));
    ("ws_send",   Mono (TArrow (t_int, TArrow (TCon ("WsFrame", []), t_unit))));
    ("ws_select", Mono (TArrow (t_int, TArrow (t_int, TArrow (t_int, TCon ("SelectResult", []))))));
    (* Dir I/O builtins — same FileError-vs-poly1 gap as the File builtins
       above (see eval.ml's dir_list/dir_mkdir/dir_mkdir_p/dir_rmdir/dir_rm_rf). *)
    ("dir_exists",      Mono (TArrow (t_string, t_bool)));
    ("dir_list",        Mono (TArrow (t_string, t_result (t_list t_string) (TCon ("FileError", [])))));
    ("dir_mkdir",       Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    ("dir_mkdir_p",     Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    ("dir_rmdir",       Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
    ("dir_rm_rf",       Mono (TArrow (t_string, t_result t_unit (TCon ("FileError", [])))));
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
    (* process_spawn_sync/lines/async always fail with a String reason (see
       eval.ml and runtime/march_runtime.c) — the error type is Mono, not a
       polymorphic `e`.  process_spawn_lines keeps its Seq element type `a`
       polymorphic since that's a generic Seq, unrelated to the error slot. *)
    ("process_spawn_sync", Mono
        (TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("ProcessResult", [])) t_string))));
    ("process_spawn_lines", poly1 (fun a ->
        TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("Seq", [a])) t_string))));
    (* Async (non-blocking) process spawn *)
    ("process_spawn_async", Mono
        (TArrow (t_string, TArrow (t_list t_string,
          t_result (TCon ("LiveProcess", [])) t_string))));
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
    ("native_int_arr_min",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_max",
       Mono (TArrow (TCon ("NativeIntArr", []), t_int)));
    ("native_int_arr_sumsq_dev",
       Mono (TArrow (TCon ("NativeIntArr", []), TArrow (t_float, t_float))));
    ("native_int_arr_map",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (TArrow (t_int, t_int), TCon ("NativeIntArr", [])))));
    ("native_int_arr_map2",
       Mono (TArrow (TCon ("NativeIntArr", []),
             TArrow (TCon ("NativeIntArr", []),
             TArrow (TArrow (t_int, TArrow (t_int, t_int)), TCon ("NativeIntArr", []))))));
    ("native_int_arr_to_float_arr",
       Mono (TArrow (TCon ("NativeIntArr", []), TCon ("NativeFloatArr", []))));
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
    ("native_float_arr_min",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_float)));
    ("native_float_arr_max",
       Mono (TArrow (TCon ("NativeFloatArr", []), t_float)));
    ("native_float_arr_sumsq_dev",
       Mono (TArrow (TCon ("NativeFloatArr", []), TArrow (t_float, t_float))));
    ("native_float_arr_map",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (TArrow (t_float, t_float), TCon ("NativeFloatArr", [])))));
    ("native_float_arr_map2",
       Mono (TArrow (TCon ("NativeFloatArr", []),
             TArrow (TCon ("NativeFloatArr", []),
             TArrow (TArrow (t_float, TArrow (t_float, t_float)), TCon ("NativeFloatArr", []))))));
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
    (* TLS builtins — tls_client_ctx, tls_server_ctx, etc.  All fail with a
       String reason (see runtime/march_tls.c's make_err) — Mono, not a
       polymorphic `e`. *)
    ("tls_client_ctx",       Mono
        (TArrow (t_string, TArrow (t_list t_string, TArrow (t_int, TArrow (t_int,
          t_result t_int t_string))))));
    ("tls_server_ctx",       Mono
        (TArrow (t_string, TArrow (t_string, TArrow (t_string, TArrow (t_list t_string,
          TArrow (t_int, t_result t_int t_string)))))));
    ("tls_connect",          Mono
        (TArrow (t_int, TArrow (t_int, TArrow (t_string, t_result t_int t_string)))));
    ("tls_accept",           Mono
        (TArrow (t_int, TArrow (t_int, t_result t_int t_string))));
    ("tls_read",             Mono
        (TArrow (t_int, TArrow (t_int, t_result t_string t_string))));
    ("tls_write",            Mono
        (TArrow (t_int, TArrow (t_string, t_result t_int t_string))));
    ("tls_close",            Mono (TArrow (t_int, t_unit)));
    ("tls_ctx_free",         Mono (TArrow (t_int, t_unit)));
    ("tls_negotiated_alpn",  Mono (TArrow (t_int, t_option t_string)));
    ("tls_peer_cn",          Mono (TArrow (t_int, t_option t_string)));
    (* HTML template builtins — generated by ~H sigil desugar *)
    (* html_auto_escape: ∀a. a -> String
       Accepts any value: Html.Safe, IOList, String, or other (escaped).
       The desugar emits html_auto_escape(x) for each ${x} in ~H sigils. *)
    ("html_auto_escape",   poly1 (fun a -> TArrow (a, t_string)));
    (* html_escape_ctx: ∀a. Int -> a -> String
       The escaper id is chosen at COMPILE time from the parse context
       (lib/ctxesc/automaton.ml) and arrives as a literal. The value stays
       polymorphic so the desugarer need not know the hole's type, but
       llvm_emit normalises it to a String before the call — the runtime must
       never dispatch on a heap tag. See the "Carried over from Task 0" note in
       specs/plans/2026-08-05-contextual-autoescaping.md. *)
    ("html_escape_ctx",    poly1 (fun a -> TArrow (t_int, TArrow (a, t_string))));
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

(** Builtins declared with a bare (non-[TArrow]) scheme that must NOT be
    called with [()] — unlike [pmap_threshold], [get_work_pool],
    [task_cancel_token_new], the [logger_*]/[process_*] readers, [self], and
    [remote_count] (all genuinely invoked as [name()], exactly like a
    zero-param user [fn] — see the [pmap_threshold] comment above), [root_cap]
    is a plain ambient value: reference it bare ([let c = root_cap]).
    [infer_app]'s [| [], t -> t] base case cannot tell these apart from its
    types alone (both look like "call site with 0 args, callee type is
    non-arrow"), so [Ast.EApp]'s handler special-cases names in this set. *)
let noncallable_builtin_values = StringSet.of_list [ "root_cap" ]

let builtin_types : (string * int) list =
  [ ("Int",    0); ("Float",  0); ("Bool",  0); ("String", 0);
    ("Char",   0); ("Byte",   0); ("Atom",  0); ("Unit",   0);
    ("List",   1); ("Option", 1); ("Array", 1); ("Set",    1); ("Seq",    1);
    ("TypedArray", 1);
    ("Result", 2); ("Map",    2);
    ("Pid",    1); ("Cap",    1); ("Future",1); ("Stream", 1);
    ("ActorCap", 1);
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
    ("IO.Signal",     0);
    ("IO.Spawn",      0); ("IO.Mut",        0); ("IO.Telemetry",  0);
    ("IO.Foreign",    0); ("IO.Foreign.Blocking", 0); ("IO.NetConnect.TLS", 0);
    ("IO.WebSocket",  0);
    (* RingBuf — mutable fixed-capacity circular buffer (non-sendable) *)
    ("RingBuf",       1);
    (* NativeArray opaque types — flat numeric arrays (P10) *)
    ("NativeIntArr",   0); ("NativeFloatArr", 0); ]

(** Built-in constructor table for Option, Result, and List, which are
    pre-registered types.  User-declared types are added via [DType].
    Each constructor is registered under both its bare name ("Some") and its
    type-qualified name ("Option.Some") so that users can write either form. *)
let builtin_ctors : (string * ctor_info) list =
  let mk_var s = Ast.TyVar { txt = s; span = Ast.dummy_span } in
  let mk_list_ty s = Ast.TyCon ({ txt = "List"; span = Ast.dummy_span }, [mk_var s]) in
  let some_ci  = { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = [mk_var "a"]; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let none_ci  = { ci_type = "Option"; ci_params = ["a"];      ci_arg_tys = []; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let ok_ci    = { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "a"]; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let err_ci   = { ci_type = "Result"; ci_params = ["a"; "e"]; ci_arg_tys = [mk_var "e"]; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let nil_ci   = { ci_type = "List";   ci_params = ["a"];      ci_arg_tys = []; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
  let cons_ci  = { ci_type = "List";   ci_params = ["a"];
                   ci_arg_tys = [mk_var "a"; mk_list_ty "a"]; ci_module = ""; ci_vis = Ast.Public; ci_is_actor_msg = false } in
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
                   (* Built-ins carry [dummy_span]; the coherence check reads it
                      to phrase a user-impl-over-builtin conflict specially. *)
                   StrMap.add k ((v, Ast.dummy_span, None) :: lst) m) StrMap.empty builtin_impls;
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
    | TRecord provided_flds, TRecord required_flds ->
      (* Per the convention above, [expected] holds what was PROVIDED and
         [found] holds what was REQUIRED — hence the local names.  Getting
         this backwards is why an extra field used to be reported as a
         missing one ("present in the expected type but missing in the found
         type" for a field that was in the provided value and absent from the
         required type).  Report both directions, surplus first, and name the
         two sides in words rather than reusing the overloaded
         "expected"/"found" pair. *)
      let surplus = List.filter_map (fun (name, t1) ->
        match List.assoc_opt name required_flds with
        | Some t2 when pp_ty t1 <> pp_ty t2 ->
          Some (Printf.sprintf "Field `%s` mismatches: expected `%s` but got `%s`."
            name (pp_ty t2) (pp_ty t1))
        | None ->
          Some (Printf.sprintf
                  "Field `%s` is present in the value provided, but the \
                   expected type has no such field." name)
        | _ -> None) provided_flds
      in
      let absent = List.filter_map (fun (name, _) ->
        if List.mem_assoc name provided_flds then None
        else
          Some (Printf.sprintf
                  "Field `%s` is required by the expected type, but the value \
                   provided has no such field." name)) required_flds
      in
      (match surplus @ absent with n :: _ -> [n] | [] -> [])
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
    (* LAUNDERING GUARD (F5 residual, 2026-07-27).  The [Chan.*] operation arms
       reject an unrefined `offer` continuation by PHYSICAL identity against
       [env.offer_unrefined] — but unification does not alias refs, it only
       compares states.  So any construct that mints a fresh [TChan] ref and
       unifies it with the marked one (a `Chan(R, P)` type annotation, an
       `if`/`match` join with another channel, a record field, an annotated
       function parameter at a CALL SITE) would hand back a different, unmarked
       ref carrying the same state — and the physical-identity guard would never
       fire again.  Every such route goes through THIS arm, so reject here: an
       unrefined offer continuation may not be unified with any other channel
       type at all, only refined by a `match` on its paired label.  (Reporting
       rather than propagating the mark is deliberate — propagation cannot help
       across a function boundary, where the callee's body was already checked
       against its own ref.) *)
    if (not (r1 == r2))
       && (offer_ref_unrefined env r1 || offer_ref_unrefined env r2) then
      Err.error env.errors ~span (offer_unrefined_message "This channel")
    else if not (session_ty_equal !r1 !r2) then
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
    (* Skip when [caller = ""]: either no fn has been entered yet, or (since
       Fix round 1) a callerless surface_ty call site — interface method
       signature, impl header/when-constraint — deliberately blanked
       [current_decl] via [with_no_caller] to suppress recording rather than
       misattribute to an unrelated function. Either way, an empty caller was
       never a meaningful attribution for `forge search --callers`. *)
    (if String.contains name.Ast.txt '.' && !(env.current_decl) <> "" then
       env.refs := { callee = name.Ast.txt;
                     caller = !(env.current_decl);
                     ref_kind = `TypeRef;
                     ref_file = name.Ast.span.Ast.file;
                     ref_line = name.Ast.span.Ast.start_line } :: !(env.refs));
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
    let env_loaded, arity = match lookup_type name.txt env with
      | Some a -> env, a
      | None   ->
        (* Try qualified module resolution: "Mod.Type" *)
        match resolve_qualified_type name.txt env with
        | env', Some a -> env', a
        | _ ->
          Err.error env.errors ~span:name.span
            (qualified_error_msg name.txt env);
          env, 0
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
         name); everything before is the module path.  Uses its own rindex
         here rather than calling [split_qualified] (same rindex convention
         as of this writing, but this call's purpose — extracting the bare
         type-name suffix — is independent of module-load resolution, so it
         stays deliberately decoupled from that function's behavior.
         Look up the bare suffix in [env_loaded] (not the pre-resolution
         [env]): when [name.txt] needed [resolve_qualified_type] to lazily
         load its module, [load_module_into_env]'s [ExType]/[ExRecord] arms
         seed the BARE name too (first-wins — see their doc comment), so an
         opaque `ptype` seen for the first time via qualification (e.g.
         `RRB.Vec`, never promoted to the outer bare namespace since it's
         never `Public`) still canonicalizes correctly.  Looking this up in
         the original [env] would always miss for such a type, silently
         skipping canonicalization and leaving a real value (whose actual
         type uses the bare `TCon`) unable to unify against the qualified
         annotation. *)
      match String.rindex_opt name.txt '.' with
      | Some i ->
        let bare = String.sub name.txt (i + 1) (String.length name.txt - i - 1) in
        (match lookup_type bare env_loaded with Some a when a = arity -> bare | _ -> name.txt)
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
                     (* Thread an env enriched with the DEFINING module's exports
                        so the record's field types — stored as UNRESOLVED surface
                        types that name sibling types by their BARE name (`scope :
                        UniqueScope`) — resolve against those siblings' bare names.
                        Without this the fields would be expanded in the referrer's
                        env, which has only the qualified sibling names, failing
                        with a bogus "I cannot find `UniqueScope`" pointing at the
                        definer's field span.  [load_module_into_env] seeds both
                        the qualified and bare forms (first-wins), so this cannot
                        clobber a name the referrer already bound. *)
                     let fenv = load_module_into_env mod_name exports env in
                     Some (params, fields, fenv)
                   | _ -> None)
              ) None exports.me_entries)
       in
       (match registry_record with
        | Some (params, field_decls, fenv)
          when List.length params = List.length args'
               && not (name_is_variant env name.txt) ->
          let saved = !tvars in
          List.iter2 (fun pname arg -> tvars := (pname, arg) :: !tvars) params args';
          let flds = List.map (fun (fn, fty) -> (fn, surface_ty fenv ~tvars fty)) field_decls in
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
          (* No enclosing function checks a cross-module interface's own
             method signature — see [with_no_caller]. *)
          let ty = with_no_caller env (fun () -> surface_ty env ~tvars m.md_ty) in
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
          let le = { le_name = key; le_lin = lin; le_used = ref false; le_first_use = ref None } in
          { acc_env with lin = le :: acc_env.lin }
        | _ -> acc_env
      ) env flds
  | _ -> env

(* =================================================================
   §12  Linearity tracking
   ================================================================= *)

(** Record a use of variable [name].  Errors if a linear var is used
    more than once. *)
(* Linear-field sentinels are tracked under the internal name
   "varname#fieldname" (see bind_linear_field_sentinels).  Diagnostics must
   not leak that internal spelling (slice-7 finding L5) — render it as the
   user-facing field-access form instead. *)
let lin_display_name n =
  match String.index_opt n '#' with
  | Some i ->
    Printf.sprintf "%s.%s"
      (String.sub n 0 i) (String.sub n (i + 1) (String.length n - i - 1))
  | None -> n

let record_use name span env =
  (* Mark any import entry that matches this name as used.
     [import_tracker] can hold one entry per use/import/alias declaration
     across the WHOLE combined program (stdlib + every file pulled in via
     MARCH_LIB_PATH auto-discovery) and [record_use] runs once per EVar in
     that same combined program, so a linear scan here is O(var-refs *
     imports) -- quadratic in project size and the dominant cost on any
     multi-hundred-file project (confirmed via `sample` showing
     List.mem/compare_val as the hot path during `march check`).  Use the
     Hashtbl-backed [import_idx] instead: an exact-name lookup for the
     common (unqualified) case, plus a prefix-root lookup only when [name]
     is qualified (contains a '.').  Both indices were populated from the
     exact same names/prefixes each entry's [ie_matches] closure compares
     against, so this is behavior-preserving, just no longer O(n) per call. *)
  (* [ie_used_names] is recorded alongside [ie_used] at both index hits: the
     index that matched already tells us exactly WHICH imported name this
     reference resolved to, which is the demand side of demand-driven
     capability propagation (see [ie_used_names]).  The exact index records the
     bare name; the prefix index records the FULL dotted name, since that is
     what identifies the member under a qualified `M.foo` reference. *)
  (match Hashtbl.find_opt env.import_idx.ie_exact_index name with
   | None -> ()
   | Some entries ->
     List.iter (fun ie ->
         ie.ie_used := true;
         Hashtbl.replace ie.ie_used_names name ()) entries);
  (match String.index_opt name '.' with
   | None -> ()
   | Some dot ->
     let prefix_root = String.sub name 0 dot in
     match Hashtbl.find_opt env.import_idx.ie_prefix_index prefix_root with
     | None -> ()
     | Some entries ->
       List.iter (fun ie ->
           if ie.ie_matches name then begin
             ie.ie_used := true;
             Hashtbl.replace ie.ie_used_names name ()
           end) entries);
  match List.find_opt (fun e -> e.le_name = name) env.lin with
  | None -> ()   (* unrestricted — no tracking needed *)
  | Some le ->
    (* A double-use is a relationship between two sites. Point at the earlier
       one as well: without it the reader knows only that the value was already
       gone, not what took it — which on a long function is the whole search. *)
    let consumed_label () =
      match !(le.le_first_use) with
      | None -> []
      | Some first ->
        [{ Err.lbl_span = first;
           Err.lbl_message =
             Printf.sprintf "`%s` was already consumed here"
               (lin_display_name name) }]
    in
    (match le.le_lin with
     | Ast.Linear when !(le.le_used) ->
       Err.report env.errors
         { Err.severity = Err.Error; span;
           message = Printf.sprintf
             "The linear value `%s` is used more than once here.\n\
              Linear values must be consumed exactly once — they cannot \
              be copied or ignored." (lin_display_name name);
           labels = consumed_label (); notes = []; code = None; fix = None }
     | Ast.Affine when !(le.le_used) ->
       Err.report env.errors
         { Err.severity = Err.Error; span;
           message = Printf.sprintf
             "The affine value `%s` is used more than once here.\n\
              Affine values may be used at most once." (lin_display_name name);
           labels = consumed_label (); notes = []; code = None; fix = None }
     | (Ast.Linear | Ast.Affine) ->
       le.le_used := true;
       if !(le.le_first_use) = None then le.le_first_use := Some span
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
  (* A binding whose resolved type names an `always_linear type` must be
     tracked as Linear even when it carries no [TLin] wrapper and the
     scrutinee isn't itself a pre-tracked linear variable to inherit from —
     e.g. `let? sock = connect(addr)` or `with Ok(sock) <- connect(addr)`
     bind `sock` straight from a fresh call's result type, with no prior
     linear tracking to propagate. Mirrors the auto-promotion that [ELet]'s
     `auto_lin` and [bind_lam_param]'s `effective_lin` already perform for
     plain lets and function params — without it, `sock` is bound as an
     ordinary variable and its uses are never checked for double-consumption. *)
  let always_linear_of t =
    match repr t with
    | TCon (name, _) when List.mem name env.always_linear_types -> Some Ast.Linear
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
              (match always_linear_of t' with
               | Some lin -> bind_linear name lin t' acc_env
               | None ->
                 let env1 = bind_var name (Mono t') acc_env in
                 bind_linear_field_sentinels name t' env1)))
      | Poly (_, _, t) ->
        (match always_linear_of t with
         | Some lin -> bind_linear name lin t acc_env
         | None ->
           (* Generalised binding: bind normally but also add field sentinels for
              any linear fields in the underlying type. *)
           let env1 = bind_var name sch acc_env in
           bind_linear_field_sentinels name (repr t) env1)
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
              mean to pass it somewhere?" (lin_display_name le.le_name))
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
  | Ast.PatWild sp ->
    let t = fresh_var env.level in
    (* Record in type_map so lower_match.ml's pattern-matrix compiler can look
       up the resolved (possibly-still-polymorphic) type via ty_of_span for
       constructor-field sub-patterns it discards — e.g. `Cons(_, t) -> ...`.
       Without this, a discarded field's synthetic TIR var never resolves to
       a concrete type through monomorphization (unlike a NAMED field, which
       gets fixed up the same way) and Perceus conservatively treats it as
       RC-managed, corrupting compiled programs when the concrete type is
       actually an unboxed scalar (e.g. Float) — see lower_match.ml. *)
    Hashtbl.replace env.type_map sp t;
    [], t

  | Ast.PatVar name ->
    let t = fresh_var env.level in
    (* Record in type_map so lower.ml can look up the resolved type via ty_of_span.
       Unification happens after infer_pattern returns; repr t follows the link. *)
    Hashtbl.replace env.type_map name.span t;
    [(name.txt, Mono t)], t

  | Ast.PatLit (lit, _) ->
    [], ty_of_lit lit

  | Ast.PatTuple (ps, _) ->
    (* Thread per-element expected types so a nested record pattern inside a
       tuple pattern — which is what desugar builds for multi-param fns —
       still gets an expected type to open its field list against. *)
    let elem_expected =
      match expected with
      | Some t -> (match repr t with TTuple ts -> ts | _ -> [])
      | None -> []
    in
    let bs_tys =
      List.mapi (fun i p ->
        match List.nth_opt elem_expected i with
        | Some et -> infer_pattern ~expected:et env p
        | None    -> infer_pattern env p) ps
    in
    let bindings = List.concat_map fst bs_tys in
    let tys      = List.map snd bs_tys in
    bindings, TTuple tys

  | Ast.PatCon (name, ps) ->
    (* When the bare constructor name is ambiguous and the scrutinee type is
       known (threaded in from [infer_match] / nested constructor arguments),
       prefer the candidate whose parent type matches, instead of relying on
       [lookup_ctor]'s order-dependent "most recently registered wins". *)
    (let ci_opt =
       (* Resolution precedence for a bare (unqualified) pattern constructor:
          1. A KNOWN scrutinee type that UNIQUELY identifies the constructor
             wins first — matching a value of an imported type
             `N.Remote = Reg(String)` via bare `Reg(s)` must resolve to
             `N.Remote`'s ctor even when the current module locally defines a
             same-named `Reg` on a different type (Finding-1).
          2. Otherwise same-module precedence: a module's own constructor
             outranks a same-named sibling's.  This is what wins when the
             expected type name is itself shared by several candidates (two
             sibling `Registry` types) so step 1 is ambiguous.
          3. Then the order-dependent expected-type head (legacy behaviour for
             a genuinely ambiguous cross-module name with no same-module match).
          4. Then the raw head / qualified resolution. *)
       let expected_tn =
         if String.contains name.txt '.' then None
         else match expected with
           | Some t -> (match repr t with TCon (tn, _) -> Some tn | _ -> None)
           | None -> None
       in
       let by_expected_unique = match expected_tn with
         | Some tn -> lookup_ctor_in_type_unique name.txt tn env
         | None -> None
       in
       match by_expected_unique with
       | Some _ as r -> r
       | None ->
       match lookup_ctor_same_module name.txt env with
       | Some _ as r -> r
       | None ->
       let by_expected = match expected_tn with
         | Some tn -> lookup_ctor_in_type name.txt tn env
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
       (* A bare, unqualified reference whose candidates span more than one
          DECLARING MODULE (not just more than one bare type name — two
          candidates from the SAME module sharing a ctor name across
          unrelated types is the pre-existing, harmless case below) is
          genuinely ambiguous when the current module owns none of them.

          BUT a KNOWN scrutinee/expected type that UNIQUELY identifies the
          constructor is not ambiguous at all — step 1 of the resolution
          precedence above already picked the right candidate by type. The
          diagnostic must mirror that: matching a value of type `Defs.Thing`
          via bare `Bar(_)` is unambiguous even when stdlib's `Plot.SeriesKind`
          also declares a `Bar`, so gate the whole ambiguity report on the
          expected type NOT having resolved it (same `lookup_ctor_in_type_unique`
          predicate `by_expected_unique` uses). *)
       let resolved_by_expected_unique =
         (not (String.contains name.txt '.'))
         && (match expected with
             | Some t ->
               (match repr t with
                | TCon (tn, _) -> lookup_ctor_in_type_unique name.txt tn env <> None
                | _ -> false)
             | None -> false)
       in
       (if not (String.contains name.txt '.')
           && not resolved_by_expected_unique then begin
         let candidates = all_ctor_candidates_named name.txt env in
         let distinct_modules = List.sort_uniq compare (List.map snd candidates) in
         let local_owns_one =
           List.exists
             (fun (_, m) ->
                m = env.current_module
                || List.exists (same_package_namespace m)
                     (local_module_paths env))
             candidates in
         if List.length distinct_modules > 1 && not local_owns_one then begin
           let lines = List.map (fun (t, m) ->
               Printf.sprintf "  • `%s.%s` — from type `%s` in module `%s`"
                 m name.txt t m) candidates in
           Err.error env.errors ~span:name.span
             (Printf.sprintf
                "Constructor `%s` is ambiguous between multiple modules:\n%s\n\
                 Use a qualified form to disambiguate."
                name.txt (String.concat "\n" lines))
         end else begin
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
         end
       end);
       let arg_tys, result_ty = instantiate_ctor env ci in
       (* Record in type_map so lower_match.ml's pattern-matrix compiler can look
          up the resolved type via ty_of_span for a NESTED constructor
          sub-pattern (e.g. `Cons(Row(fp), rest)`'s `Row(fp)`) — without this the
          destructured field var stays TVar "_" forever, and if the ctor's short
          name collides with another type's ctor (Collision_set), codegen's
          ambiguous by-arity ctor_entry fallback can pick the WRONG type's tag. *)
       Hashtbl.replace env.type_map name.span result_ty;
       (* Resolve the constructor's own type against the expected type BEFORE
          walking its arguments.  [instantiate_ctor] hands back fresh vars for
          the parent type's parameters, so `Some`'s argument is still an
          unbound var here and is only linked to the scrutinee's payload by the
          caller's unify, AFTER the arguments have been inferred.  A sub-pattern
          that needs a CONCRETE expected type — a record pattern, which uses it
          to open its field list — would see that bare var and fall back to
          closed synthesis, so `Some({ status: s })` against
          `Option({status, body})` failed while the full
          `Some({ status: s, body: b })` happened to unify anyway.  Binding the
          parameter first makes [arg_tys] repr to real types. *)
       (match expected with
        | Some exp_ty ->
          unify env ~span:name.span
            ~reason:(Some (RBuiltin
              (Printf.sprintf "I'm checking the pattern for constructor `%s`."
                 name.txt)))
            result_ty exp_ty
        | None -> ());
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

  | Ast.PatRecord (flds, sp) ->
    (* Record patterns have OPEN field lists: `{ x }` matches any record with
       at least an `x`.  Since [unify] requires exact field-set equality
       (no width subtyping, no row variables), we cannot synthesize the
       pattern's type from the mentioned fields and unify — that rejects every
       partial pattern.  Drive the sub-patterns from the EXPECTED type
       instead, and return the expected type unchanged so the caller's unify
       is a no-op.

       With no expected type available (an unannotated scrutinee whose type is
       still a fresh var), fall back to the old closed-record synthesis: it is
       the only thing that can constrain the scrutinee at all, and it matches
       the pre-existing behaviour for full destructures. *)
    let expected_rec =
      match expected with
      | Some t -> expand_record env (repr t)
      | None -> None
    in
    (match expected_rec with
     | Some (TRecord expected_flds) ->
       let bindings = ref [] in
       List.iter (fun ((name : Ast.name), pat) ->
         match List.assoc_opt name.Ast.txt expected_flds with
         | Some fty ->
           let bs, pty = infer_pattern ~expected:fty env pat in
           unify env ~span:name.Ast.span ~reason:(Some (RMatchArm sp)) fty pty;
           bindings := bs @ !bindings
         | None ->
           Err.report env.errors
             { Err.severity = Error; span = name.Ast.span;
               message =
                 Printf.sprintf "This record has no field `%s`." name.Ast.txt;
               labels = [];
               notes  =
                 [Printf.sprintf "Available fields: %s"
                    (String.concat ", " (List.map fst expected_flds))];
               code = Some "unknown_record_field";
               fix  = None }
       ) flds;
       (* Record the PATTERN's own type under its span.  lower_match's
          [expand_record_column] emits [EField] on the column's scrutinee, and
          llvm_emit can only compute a static GEP when that scrutinee's TIR
          type is the record's — otherwise it falls back to the by-name
          dynamic accessor and decodes the result with the FIELD's type, which
          dereferences an inline unboxed Float as a pointer (SIGSEGV).  A
          NESTED record column (a record inside a constructor payload) has a
          synthetic sub-var deliberately left at the lowering placeholder, so
          this span is the only place the record type can be recovered from. *)
       Hashtbl.replace env.type_map sp (TRecord expected_flds);
       !bindings, TRecord expected_flds
     | _ ->
       let bindings = ref [] in
       let fld_tys = List.map (fun ((name : Ast.name), pat) ->
           let bs, t = infer_pattern env pat in
           bindings := bs @ !bindings;
           (name.Ast.txt, t)
         ) flds
       in
       let sorted =
         List.sort (fun (a, _) (b, _) -> String.compare a b) fld_tys in
       (* Same reason as the expected-driven branch above. *)
       Hashtbl.replace env.type_map sp (TRecord sorted);
       !bindings, TRecord sorted)

  | Ast.PatOr (alts, sp) ->
    (* Every alternative must have the same type, AND must bind the same names
       at the same types.  Lowering splits the row into one per alternative but
       shares a single lowered body, reached through a join point whose
       parameters are the arm's binders ([pat_binder_vars] in lower_match.ml) —
       so a name only some alternatives supply would be unbound on the paths
       that don't, and a name supplied at two different types has no single
       parameter type.  Both are rejected here rather than miscompiled.

       [span_of_pat] isn't defined until later in this file (it's used by
       exhaustiveness checking, which runs after inference), so diagnostics
       point at the whole or-pattern's span [sp] rather than at the specific
       offending alternative. *)
    let results = List.map (fun p -> infer_pattern ?expected env p) alts in
    (match results with
     | [] -> [], fresh_var env.level
     | (_, t0) :: rest ->
       List.iter (fun (_, t) ->
         unify env ~span:sp ~reason:(Some (RMatchArm sp)) t0 t) rest;
       let bs0 = match results with (bs, _) :: _ -> bs | [] -> [] in
       let ty_of_scheme = function Mono t -> t | Poly (_, _, t) -> t in
       let names bs = List.sort_uniq String.compare (List.map fst bs) in
       let n0 = names bs0 in
       let report_names_differ missing extra =
         let describe label ns =
           Printf.sprintf "%s: %s" label
             (String.concat ", " (List.map (fun n -> "`" ^ n ^ "`") ns))
         in
         let detail =
           String.concat "; "
             ((if missing = [] then []
               else [describe "bound by an earlier alternative only" missing])
              @ (if extra = [] then []
                 else [describe "bound by a later alternative only" extra]))
         in
         Err.report env.errors
           { Err.severity = Error; span = sp;
             message = "Or-pattern alternatives must bind the same variables.";
             labels = [];
             notes  =
               [detail;
                "Every alternative of `p1 | p2` shares one arm body, so a name \
                 bound by only some alternatives would be undefined when the \
                 others match.";
                "Bind the same names in every alternative, split this into \
                 separate arms, or match the common shape and test the \
                 difference in a `when` guard."];
             code = Some "or_pattern_binding";
             fix  = None }
       in
       List.iter (fun (bs, _) ->
         let ni = names bs in
         if ni <> n0 then
           report_names_differ
             (List.filter (fun n -> not (List.mem n ni)) n0)
             (List.filter (fun n -> not (List.mem n n0)) ni)
         else
           (* Same names: each must carry the same type in every alternative,
              since the join point gives it exactly one parameter. *)
           List.iter (fun (n, sch) ->
             match List.assoc_opt n bs0 with
             | Some sch0 ->
               unify env ~span:sp
                 ~reason:(Some (RBuiltin
                   (Printf.sprintf
                      "`%s` is bound by more than one alternative of this \
                       or-pattern, so every alternative must bind it at the \
                       same type." n)))
                 (ty_of_scheme sch0) (ty_of_scheme sch)
             | None -> ()) bs
       ) rest;
       bs0, t0)

  | Ast.PatAs (inner, name, _) ->
    (* Thread [expected] into the aliased pattern, exactly as [PatTuple] and
       constructor arguments do.  Dropping it sent a record pattern under an
       alias (`{ code: 404 } as w`) down the CLOSED-synthesis branch, so `w`
       got the narrow `{ code : Int }` instead of the scrutinee's own type —
       two misleading errors (`expected { code : Int } but got
       { code : Int, msg : String }` and `this record does not have a field
       called msg`), neither pointing at the real cause. *)
    let bindings, t = infer_pattern ?expected env inner in
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
  | SPRec  of (string * spat) list
      (** Record: { x: p, … }, sorted by field name.  Field lists are OPEN, so
          this may name a SUBSET of the record's fields — an absent field is
          an implicit wildcard.  [spec_rec_mc] fills them in against the field
          list taken from the scrutinee's TYPE, which is what lets two arms
          naming different subsets line up in the same matrix column. *)

(** Qualified constructor patterns ("MarchType.TBool", "Ast.Query") carry
    their full dotted text; exhaustiveness compares against the scrutinee
    type's BARE ctor names, so keep only the last segment. *)
let bare_ctor_name (txt : string) : string =
  match String.rindex_opt txt '.' with
  | Some i -> String.sub txt (i + 1) (String.length txt - i - 1)
  | None -> txt

(** Normalize an AST pattern to a SINGLE [spat], widening anything [spat]
    cannot represent to [SPWild].

    Only used as the fallback for a pattern whose or-expansion exceeds
    [or_expansion_cap]; [norm_pat_rows] is the entry point everything else
    goes through.  Note that [SPWild] in a coverage matrix means "matches
    everything", i.e. it OVER-reports what the arm covers: safe for
    exhaustiveness (it can only suppress a warning), wrong for redundancy
    (the next arm looks subsumed), which is why the callers that use this
    fallback also skip redundancy checking for the arm. *)
let rec norm_pat (p : Ast.pattern) : spat =
  match p with
  | Ast.PatWild _            -> SPWild
  | Ast.PatVar  _            -> SPWild
  | Ast.PatAs  (p', _, _)    -> norm_pat p'
  | Ast.PatRecord (fs, _)    ->
    SPRec (List.sort (fun (a, _) (b, _) -> String.compare a b)
             (List.map (fun ((n : Ast.name), sub) -> (n.txt, norm_pat sub)) fs))
  | Ast.PatOr _              -> SPWild   (* conservative: see norm_pat_rows *)
  | Ast.PatCon  (n, args)    -> SPCon (bare_ctor_name n.txt, List.map norm_pat args)
  | Ast.PatAtom (n, args, _) -> SPCon (":" ^ n, List.map norm_pat args)
  | Ast.PatTuple (ps, _)     -> SPTup (List.map norm_pat ps)
  | Ast.PatLit  (l, _)       -> SPLit l

(** Upper bound on the number of [spat] rows one arm may expand to.  Nested
    or-patterns multiply — `C(1 | 2, 3 | 4)` denotes four concrete shapes —
    so the cross-product is capped and a pattern beyond it falls back to the
    widening [norm_pat]. *)
let or_expansion_cap = 256

(** How many [spat] rows [p] expands to, saturating at [or_expansion_cap + 1]
    so a pathological pattern is rejected by the cap instead of overflowing
    (or building the list to find out). *)
let rec or_expansion_size (p : Ast.pattern) : int =
  let sat n = min n (or_expansion_cap + 1) in
  match p with
  | Ast.PatOr (alts, _) ->
    sat (List.fold_left (fun acc a -> sat (acc + or_expansion_size a)) 0 alts)
  | Ast.PatAs (p', _, _) -> or_expansion_size p'
  | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) | Ast.PatTuple (ps, _) ->
    sat (List.fold_left (fun acc p -> sat (acc * or_expansion_size p)) 1 ps)
  (* A record's field sub-patterns multiply exactly like a tuple's elements —
     `{ a: 1 | 2, b: 3 | 4 }` denotes four shapes. *)
  | Ast.PatRecord (fs, _) ->
    sat (List.fold_left (fun acc (_, p) -> sat (acc * or_expansion_size p)) 1 fs)
  | Ast.PatWild _ | Ast.PatVar _ | Ast.PatLit _ -> 1

(** Every [spat] row [p] covers, distributing or-patterns at ANY depth into
    the cross-product of their alternatives. *)
let rec norm_pat_all (p : Ast.pattern) : spat list =
  match p with
  | Ast.PatWild _ | Ast.PatVar _ -> [SPWild]
  | Ast.PatAs (p', _, _)         -> norm_pat_all p'
  | Ast.PatRecord (fs, _)        ->
    let sorted =
      List.sort (fun ((a : Ast.name), _) ((b : Ast.name), _) ->
          String.compare a.txt b.txt) fs in
    let names = List.map (fun ((n : Ast.name), _) -> n.txt) sorted in
    List.map (fun row -> SPRec (List.combine names row))
      (norm_pat_args (List.map snd sorted))
  | Ast.PatOr (alts, _)          -> List.concat_map norm_pat_all alts
  | Ast.PatCon (n, args)         ->
    List.map (fun a -> SPCon (bare_ctor_name n.txt, a)) (norm_pat_args args)
  | Ast.PatAtom (n, args, _)     ->
    List.map (fun a -> SPCon (":" ^ n, a)) (norm_pat_args args)
  | Ast.PatTuple (ps, _)         -> List.map (fun a -> SPTup a) (norm_pat_args ps)
  | Ast.PatLit (l, _)            -> [SPLit l]

and norm_pat_args (ps : Ast.pattern list) : spat list list =
  List.fold_right (fun p acc ->
      let heads = norm_pat_all p in
      List.concat_map (fun h -> List.map (fun t -> h :: t) acc) heads)
    ps [[]]

(** True when [p]'s or-expansion is too large to enumerate, so [norm_pat_rows]
    falls back to the widening [norm_pat].  Redundancy checking must skip such
    an arm — see [check_redundant_arms]. *)
let pat_or_expansion_capped (p : Ast.pattern) : bool =
  or_expansion_size p > or_expansion_cap

(** Expand a pattern into the set of [spat] rows it covers.  Or-patterns are
    expanded at EVERY depth, not just the top level: nesting one inside a
    constructor argument or tuple element used to normalise it to [SPWild],
    which in a coverage matrix means "matches everything" — so `Some(1 | 2)`
    silently claimed to cover all of `Some(_)`, suppressing a real
    non-exhaustiveness warning AND reporting the following arm unreachable.
    (The old comment here claimed the widening was conservative; [SPWild] is
    an over-report, not an under-report, in both consumers.)

    Beyond [or_expansion_cap] rows the enumeration is abandoned and the
    widening [norm_pat] is used instead — see [pat_or_expansion_capped]. *)
let norm_pat_rows (p : Ast.pattern) : spat list =
  if pat_or_expansion_capped p then [norm_pat p] else norm_pat_all p

(** All [(ctor_name, arity)] pairs for a type name, in declaration order.
    Qualified aliases (keys containing '.') are skipped so that exhaustiveness
    analysis only sees each constructor once under its bare name. *)
let ctors_for_type (env : env) type_name =
  (* Gather (ctor_key, ci) for every bare-keyed constructor whose parent type's
     BARE name is [type_name].  Because [ci_type] is bare (kept so for
     cross-module unification), two same-named types from DIFFERENT modules both
     match here — the linear-L4 ctor cross-talk, where a user `type Handle =
     H(Int)` and stdlib's `type Handle = Handle(Int)` merge into one expected
     universe so `match … H(n)` spuriously reports `missing case: Handle(_)`.
     Disambiguate with [ci_module]: if the CURRENT module declares its OWN type
     of this name (a matched ctor carries ci_module = current_module) AND a
     foreign same-named type is also present, the local declaration shadows the
     import, so restrict the universe to the current module's own constructors.
     A single declaration (no cross-module clash) is left exactly as before, so
     this is behavior-preserving except on the collision it fixes; and it feeds
     only this exhaustiveness diagnostic, never codegen. *)
  let matches =
    StrMap.fold (fun k cis acc ->
      if String.contains k '.' then acc
      else
        match List.find_opt (fun (ci : ctor_info) -> ci.ci_type = type_name) cis with
        | Some ci -> (k, ci) :: acc
        | None -> acc
    ) env.ctors []
  in
  let local_shadow =
    env.current_module <> ""
    && List.exists (fun (_, ci) -> ci.ci_module = env.current_module) matches
    && List.exists (fun (_, ci) -> ci.ci_module <> env.current_module) matches
  in
  let matches =
    if local_shadow
    then List.filter (fun (_, ci) -> ci.ci_module = env.current_module) matches
    else matches
  in
  List.map (fun (k, (ci : ctor_info)) -> (k, List.length ci.ci_arg_tys)) matches

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
      | SPCon _ | SPLit _ | SPTup _ | SPRec _ -> None
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

(** Specialize the pattern matrix for a record with exactly [fields] (sorted
    field names, taken from the scrutinee's TYPE, not from any one pattern).

    A record is irrefutable at the top level — one shape, no tag — so this is
    the tuple case with names instead of positions, plus one twist: field
    lists are OPEN, so a row may name only some of [fields].  Absent fields
    become wildcards, which is what lets `{ code: 404 }` and `{ msg: m }`
    occupy the same column. *)
let spec_rec_mc (fields : string list) (matrix : spat list list)
    : spat list list =
  let wilds = List.map (fun _ -> SPWild) fields in
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild        -> Some (wilds @ rest)
      | SPRec assoc   ->
        Some (List.map (fun f ->
                match List.assoc_opt f assoc with
                | Some sp -> sp
                | None    -> SPWild) fields
              @ rest)
      | SPCon _ | SPLit _ | SPTup _ -> None
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
  | TRecord fs          ->
    "{ " ^ String.concat ", "
             (List.map (fun (n, t) -> n ^ ": " ^ example_of t) fs) ^ " }"
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
    | TRecord [] -> None   (* the empty record has one value — always covered *)
    | TRecord field_tys ->
      (* A record is single-shape, so this mirrors the tuple case: specialize
         into one column per field and recurse.  The field list comes from the
         TYPE (every field, sorted), not from any one pattern — patterns name
         open subsets and [spec_rec_mc] fills the gaps with wildcards. *)
      let fields    = List.map fst field_tys in
      let inner_tys = List.map snd field_tys in
      let arity     = List.length fields in
      let any_rec =
        List.exists
          (fun row -> match row with SPRec _ :: _ -> true | _ -> false)
          matrix
      in
      if any_rec then begin
        let sub      = spec_rec_mc fields matrix in
        let full_tys = inner_tys @ rest_tys in
        match find_missing_mc env full_tys sub with
        | None -> None
        | Some exs ->
          let fld_exs, rest_exs = split_at arity exs in
          let rec_str =
            Printf.sprintf "{ %s }"
              (String.concat ", " (List.map2 (fun f e -> f ^ ": " ^ e)
                                     fields fld_exs))
          in
          Some (rec_str :: rest_exs)
      end else begin
        (* No record patterns and no wildcards: entirely missing. *)
        let def = default_mc matrix in
        match find_missing_mc env rest_tys def with
        | None -> None
        | Some rest_exs -> Some (example_of (TRecord field_tys) :: rest_exs)
      end
    | TArrow _ | TChan _ | TLin _ | TNat _ | TNatOp _ ->
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
  | Ast.PatOr   (_, sp)     -> sp

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
        | TRecord field_tys when field_tys <> [] ->
          (* Single-shape like a tuple: always expand, never take the default
             path.  A record has no "other constructor" for the default path
             to stand for, so expanding is both safe and strictly sharper. *)
          let fields = List.map fst field_tys in
          let sub_m = spec_rec_mc fields matrix in
          let wild_args = List.map (fun _ -> SPWild) fields in
          is_useful env (List.map snd field_tys @ rest_tys) sub_m
            (wild_args @ row_rest)
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
     | SPRec assoc ->
       (* Expand against the TYPE's field list, not this pattern's — the row
          being tested may name a different subset than the matrix rows do,
          and both must land in the same columns. *)
       let field_tys = match ty with
         | TRecord fs -> fs
         | _ -> List.map (fun (n, _) -> (n, TError)) assoc
       in
       let fields = List.map fst field_tys in
       let sub_m  = spec_rec_mc fields matrix in
       let row_args =
         List.map (fun f ->
             match List.assoc_opt f assoc with
             | Some sp -> sp
             | None    -> SPWild) fields
       in
       is_useful env (List.map snd field_tys @ rest_tys) sub_m
         (row_args @ row_rest)
     | SPLit lit ->
       let sub_m = spec_lit_mc lit matrix in
       is_useful env rest_tys sub_m row_rest)

(** Emit Warnings for redundant (unreachable) arms.
    Guarded arms are never flagged, and their patterns are excluded from the
    prefix so that subsequent arms aren't mistakenly flagged as subsumed.
    Arms whose or-expansion exceeded [or_expansion_cap] get the same treatment,
    since those fall back to the widening [norm_pat] and would mis-subsume the
    following arm.

    Record arms used to be excluded here too: [spat] had no record shape, so
    [norm_pat] collapsed them to [SPWild] ("matches everything") and the arm
    after a record arm was reported unreachable on code that plainly runs it.
    [SPRec] removed the cause rather than the symptom — record arms are now
    analysed like any other, so a genuinely unreachable one is finally
    caught. *)
let check_redundant_arms (env : env) (scrut_ty : ty)
    (branches : Ast.branch list) =
  let prefix = ref [] in
  List.iter (fun (br : Ast.branch) ->
    (* An or-pattern contributes one row per alternative (at every depth); the
       arm is redundant only if EVERY alternative is already subsumed by the
       prefix — a single live alternative keeps the whole arm reachable. *)
    let arm_rows = List.map (fun r -> [r]) (norm_pat_rows br.branch_pat) in
    if br.branch_guard = None
       && not (pat_or_expansion_capped br.branch_pat) then begin
      if not (List.exists (fun row -> is_useful env [scrut_ty] !prefix row) arm_rows) then begin
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
      prefix := !prefix @ arm_rows
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
      List.concat_map
        (fun (br : Ast.branch) ->
          match br.branch_guard with
          | None   -> List.map (fun r -> [r]) (norm_pat_rows br.branch_pat)
          | Some _ -> [])
        branches
    in
    match find_missing_mc env [scrut_ty] guardless_matrix with
    | None -> ()
    | Some _ ->
      env.nonexhaustive_match_spans := span :: !(env.nonexhaustive_match_spans)
  end
  else begin
    let matrix =
      List.concat_map
        (fun (br : Ast.branch) ->
          List.map (fun r -> [r]) (norm_pat_rows br.branch_pat))
        branches
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

(** Reject a [Chan.*] operation on a channel whose session ref came from an
    [offer] with differing branch continuations and has not been refined by a
    `match` on the paired label (F5 residual). *)
let offer_unrefined_error env span (r : session_ty ref) op =
  if offer_ref_unrefined env r then begin
    Err.error env.errors ~span
      (offer_unrefined_message (Printf.sprintf "%s: this channel" op));
    true
  end else false

(** Type constructor names that cannot appear in actor message payloads.
    These types carry mutable state that must remain owned by a single actor.
    NativeIntArr/NativeFloatArr are NativeArray's real backing types -- the
    NativeArray stdlib module (stdlib/native_array.march) is a function
    namespace over these two opaque 0-arity constructors, not a type of its
    own, so "NativeArray" itself would be a silent no-op entry here (see
    where native_int_arr_make/native_float_arr_make are registered, this
    file, around the NativeArray builtins section). *)
let non_sendable_types = ["RingBuf"; "NativeIntArr"; "NativeFloatArr"]

(** [check_sendable errors span ty] walks [ty] and emits an error for every
    non-sendable type constructor it finds. Called from the [ECon] arm on
    an actor message constructor's instantiated argument types (guarded by
    [ci_is_actor_msg]) -- at message-CONSTRUCTION time, not at each place a
    message value is later sent. *)
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
      (* R2: the root capability is granted at the boundary, not taken.  The
         name stays BOUND (so this reports a capability error rather than
         "I cannot find `root_cap`", and so the inferred type below stays
         [Cap(IO)] and no cascade of unification failures follows a single
         mistake) — only naming it is refused. *)
      if name.txt = "root_cap" && not env.root_cap_allowed then
        Err.error env.errors ~span:name.span
          (render_parts [
            MPCode "root_cap";
            MPText " cannot be referenced — the root capability is granted to ";
            MPCode "main"; MPText ", not taken.";
            MPBreak;
            MPText "help: declare "; MPCode "fn main(cap : Cap(IO))";
            MPText " and pass the capability down to whatever needs it, narrowing with ";
            MPCode "cap_narrow"; MPText " along the way." ]);
      (match lookup_var name.txt env with
       | Some sch ->
         (if StrMap.mem name.txt env.local_fns && !(env.current_decl) <> "" then
            env.refs := { callee = qualify_ref_name env.current_module name.txt;
                          caller = !(env.current_decl);
                          ref_kind = `Call;
                          ref_file = name.span.Ast.file;
                          ref_line = name.span.Ast.start_line } :: !(env.refs)
          else if String.contains name.txt '.' && StrMap.mem name.txt env.qual_fn_names
                  && !(env.current_decl) <> "" then
            (* Already-qualified "Mod.name" resolved directly out of env.vars —
               this is how same-compilation cross-module DMod exports work (see
               the [Ast.DMod] branch of [check_decl], which binds "Mod.member"
               straight into the outer env.vars rather than routing through
               [resolve_qualified_var]/[Module_registry]). The [qual_fn_names]
               membership check excludes a qualified reference to a public
               top-level [DLet] constant/value — [DMod]'s export step binds
               those into [env.vars] the exact same way it binds a [DFn], so a
               bare dotted-name check alone cannot tell them apart; only
               [qual_fn_names] (populated exclusively from [DFn]s, see its doc
               comment) can. *)
            env.refs := { callee = name.txt;
                          caller = !(env.current_decl);
                          ref_kind = `Call;
                          ref_file = name.span.Ast.file;
                          ref_line = name.span.Ast.start_line } :: !(env.refs));
         instantiate ~use_span:name.span env.level env sch
       | None     ->
         (* Try qualified module resolution: "Mod.func" *)
         match resolve_qualified_var name.txt env with
         | env', Some sch ->
           (* [env'] is the env AFTER [load_module_into_env] merged the
              resolved module's exports — [qual_fn_names] is only populated
              there for the ExFn case, so this correctly excludes a qualified
              reference to a registry-loaded module's public [DLet]
              value/constant (ExValue). See [qual_fn_names]'s doc comment. *)
           (if StrMap.mem name.txt env'.qual_fn_names && !(env.current_decl) <> "" then
              env.refs := { callee = name.txt;
                            caller = !(env.current_decl);
                            ref_kind = `Call;
                            ref_file = name.span.Ast.file;
                            ref_line = name.span.Ast.start_line } :: !(env.refs));
           instantiate ~use_span:name.span env.level env sch
         | _ when is_confirmed_private_qualified name.txt env ->
           (* A confirmed privacy violation (`Mod.priv_fn`) must be reported
              as such — falling through to the dot-suffix fallback below would
              let it silently resolve to an unrelated global of the same bare
              name (e.g. `Auth.hash` matching the builtin `hash` from the
              `Hash` interface), bypassing the visibility check entirely. *)
           Err.error env.errors ~span:name.span (qualified_error_msg name.txt env);
           TError
         | _ when (match split_qualified name.txt with
                   | Some (mod_name, _) -> March_modules.Module_registry.ensure_loaded mod_name <> None
                   | None -> false) ->
           (* The qualifier's first component IS a genuinely known module (a
              real, loaded stdlib module — [ensure_loaded] succeeded) and
              [resolve_qualified_var] just confirmed it does not export this
              member. That is decisive: fall straight through to the
              dot-suffix fallback below would let e.g. `String.length` (no
              such export; the real API is `byte_size`/`codepoint_count`)
              silently resolve to the unrelated `List.length` bare binding,
              producing a baffling `expected List(u2) but got String` instead
              of "Module `String` does not export `length`". The dot-suffix
              fallback exists for a DIFFERENT case — multi-component paths
              like "Conduit.Storage.workflow_load" whose first component
              ("Conduit") is a local/app module never registered in
              [Module_registry] (only the REPL calls [register]; compiled
              builds only lazily populate the registry with real stdlib
              modules) — so this guard cannot misfire on that case. *)
           Err.error env.errors ~span:name.span (qualified_error_msg name.txt env);
           TError
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
            | Some sch -> instantiate ~use_span:name.span env.level env sch
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
             | projs ->
               Err.error env.errors ~span:sp
                 (Printf.sprintf
                    "Chan.new: protocol `%s` has %d roles but Chan.new needs \
                     exactly 2. Use MPST.new for multi-party protocols."
                    pname (List.length projs));
               TError)))

    (* Chan.send(ch, value) → linear Chan at continuation session state.
       Pre-condition: ch must be at SSend(T, S). Post: ch is consumed; returns Chan at S. *)
    | Ast.EApp (Ast.EVar { txt = "Chan.send"; _ }, [ch_expr; val_expr], sp) ->
      let ch_ty = repr (infer_expr env ch_expr) in
      let inner_chan_ty = match ch_ty with
        | TLin (_, t) -> repr t
        | t -> t
      in
      (match inner_chan_ty with
       | TChan r when offer_unrefined_error env sp r "Chan.send" -> TError
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
       | TChan r when offer_unrefined_error env sp r "Chan.recv" -> TError
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
       | TChan r when offer_unrefined_error env sp r "Chan.close" -> TError
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
       | TChan r when offer_unrefined_error env sp r "Chan.choose" -> TError
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
       | TChan r when offer_unrefined_error env sp r "Chan.offer" -> TError
       | TChan r ->
         (match unfold_srec !r with
          | SOffer branches ->
            (match branches with
             | (_, sty) :: _ ->
               (* Hand back a channel at the FIRST branch's continuation as the
                  default (keeps the previously-accepted programs that offer then
                  drive without matching the label — the approximation is exact
                  when the peer chose the first branch).  But ALSO register this
                  fresh session ref against the full branch map so that a later
                  `match <label>` can refine it PER ARM to the branch actually
                  taken (F5 path-dependent refinement). *)
               let cont_ref = ref sty in
               env.offer_conts := (cont_ref, branches) :: !(env.offer_conts);
               (* If the branches continue differently, the first-branch type is
                  a GUESS — mark the ref as needing a `match`-driven refinement
                  before any operation may use it. *)
               (match branches with
                | (_, first) :: rest
                  when not (List.for_all (fun (_, s) -> session_ty_exact_equal s first) rest) ->
                  env.offer_unrefined := cont_ref :: !(env.offer_unrefined)
                | _ -> ());
               TTuple [t_atom; TLin (Ast.Linear, TChan cont_ref)]
             | [] ->
               TTuple [t_atom; TError])
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

    (* Any other `MPST.*` / `Chan.*` spelling reaching this point either (a) is
       one of the six real `Chan.*` ops called with the wrong shape (the
       arity-specific arms above only match the CORRECT arg count, so falling
       through to here with one of these six exact names, still bound to the
       compiler's OWN untouched placeholder, means the call is malformed) or
       (b) does not resolve as an ordinary bound name at all (a misspelling,
       an unimplemented `MPST.choose`/`MPST.offer`, etc). Both are treated as
       a session-op diagnostic rather than a library-lookup failure — falling
       through to the generic qualified-name path would otherwise produce a
       misleading "Unknown module `MPST`".

       The distinction between "still the compiler's placeholder" and "a user
       module shadowed this name" is made STRUCTURALLY, not by a hand-kept
       name list: `builtin_bindings` (the table a few hundred lines above
       that seeds `Chan.new`/`send`/`recv`/`close`/`choose`/`offer` into
       `base_env` as generic curried placeholders — see the comment there,
       "these entries just put the names in scope; the real typing is done in
       the Chan.* EApp branches") is evaluated exactly once at program
       startup, so each entry's `scheme` is a single fixed heap object. A
       fresh top-level `env` starts with that EXACT object bound under each
       name (`bind_vars` calls `StrMap.add`, which stores the value, not a
       copy). If a user later writes `mod Chan do fn recv(a, b) do ... end
       end`, module-export folding REBINDS "Chan.recv" in `env.vars` to a
       brand-new scheme built while typechecking that function — a different
       heap object. So `sch == placeholder_sch` (physical equality) is true
       iff the name was never shadowed: exactly the "still a bare, unshadowed
       compiler builtin, and we already fell through its arity-specific arm"
       case this branch needs to catch, with no risk of a false positive on a
       real user binding and no separate list to keep in sync with the table.
       MPST has no placeholder table entries at all, so `MPST.*` names always
       take the `None`-from-`lookup_var` branch below (mirroring the two
       resolution steps the ordinary `EVar` fallthrough, above, tries first)
       — a genuinely-defined `MPST.helper` (a user module actually named
       `MPST`) is left alone and reaches that path unharmed; only names that
       would ALSO fail there get the session-op message. *)
    | Ast.EApp (Ast.EVar ({ txt = op; _ } as n), _, sp)
      when ((String.length op > 5 && String.sub op 0 5 = "MPST.")
         || (String.length op > 5 && String.sub op 0 5 = "Chan."))
        && (match lookup_var op env with
            | None -> (match resolve_qualified_var op env with (_, Some _) -> false | (_, None) -> true)
            | Some sch ->
              (match List.assoc_opt op builtin_bindings with
               | Some placeholder_sch -> sch == placeholder_sch
               | None -> false)) ->
      Err.error env.errors ~span:sp
        (Printf.sprintf
           "`%s` is not a session-channel operation I know, or it was called \
            with the wrong number of arguments.\n\
            Binary channels: Chan.new/send/recv/close/choose/offer. \
            Multi-party: MPST.new/send/recv/close — multi-party `choose`/`offer` \
            are not implemented yet."
           n.txt);
      TError

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
      (* R4a: record the INSTANTIATED arrow so the sweep can read BOTH the
         source and the target once unification has pinned them. *)
      env.cap_narrow_sites := (sp, f_ty) :: !(env.cap_narrow_sites);
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

    (* Capability unforgeability (R3): record the three unconstrained JSON
       builtins for the post-checking sweep.  [f_ty] is the FRESHLY
       INSTANTIATED [a -> b]; [infer_app] unifies [a] with the argument and
       [b] with the result in place, so the arrow recorded here reads back
       solved at sweep time.  No [demote_to_monomorphic] here — see
       [check_json_cap_sites] for why an unsolved var is handled by the sweep
       rather than forced at the call site. *)
    | Ast.EApp ((Ast.EVar { txt = ("to_json" | "from_json" | "from_json_events"); _ }) as fv,
                [arg], sp) ->
      let jname = (match fv with Ast.EVar n -> n.txt | _ -> assert false) in
      let f_ty = infer_expr env fv in
      let rty = infer_app env sp f_ty [arg] 0 in
      (* Value restriction, for exactly the reason spelled out at
         [demote_to_monomorphic]: without it, [let x = from_json(s)]
         generalizes [x] to [∀b. b], every use instantiates a FRESH var pinned
         to that use's type, and the single node recorded here stays an
         unbound quantified var forever.  The sweep then reads [TVar], reports
         nothing, and the forge is reopened in precisely the let-flow position
         reject/t143 exercises.
         Consequence, and it is a real one: a single [from_json] application
         can no longer be used at two DIFFERENT result types. Decoding one
         string as two unrelated types is already meaningless at run time —
         [from_json] dispatches on a single determinable target type — so this
         costs nothing that worked. *)
      demote_to_monomorphic f_ty;
      env.json_cap_sites := (sp, f_ty, jname) :: !(env.json_cap_sites);
      rty

    | Ast.EApp (f, args, sp) ->
      (* Default-arg call resolution.  [expand_defaults_decl] emits a default-arg
         fn as mangled `foo$R`..`foo$N` decls (one per supplied arity) with NO
         bare `foo` decl; the interpreter (VMultiarity) and TIR
         (_default_dispatch) reconstruct the base-name dispatch downstream, but
         the typechecker runs BETWEEN desugar and both consumers and binds only
         the mangled names — so a source-level call `foo(args)` to a default-arg
         fn otherwise fails with "I cannot find `foo`".  Redirect a call of an
         UNBOUND bare/qualified name to its `name$<n_args>` arity variant when
         that variant is in scope (the codegen/eval paths lower the ORIGINAL
         `foo(args)` independently, so this rewrite is typing-only). *)
      let f =
        match f with
        | Ast.EVar name when lookup_var name.txt env = None ->
          let mangled = Printf.sprintf "%s$%d" name.txt (List.length args) in
          (match lookup_var mangled env with
           | Some _ -> Ast.EVar { name with txt = mangled }
           | None -> f)
        | _ -> f
      in
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
      (* Reject a zero-arg call of a plain, non-function VALUE — e.g.
         `root_cap()`, or `let x = 5; x()`, or `let zf = answer; zf()`
         aliasing a genuine zero-arg fn.  infer_app's `| [], t -> t` base
         case exists so a zero-param user `fn` (whose type collapses to its
         bare return type — see the [pmap_threshold] comment) can still be
         invoked as `f()`; without this check it also silently accepts
         calling any non-function value with `()`, since a plain value and a
         "disguised" zero-arg function are indistinguishable by type alone
         once no arguments remain to unify against.

         Two cases:
          - a hardcoded denylist of builtin ambient values ([root_cap]);
          - the general case: a name in [env.plain_let_names] — i.e. one
            most recently bound by a simple `let name = expr` (see the
            [Ast.ELet] case of [infer_block]) — whose resolved type is a
            *concrete* non-arrow (excluding [TVar], which means "not yet
            known" — e.g. mid-inference of a self-recursive call — and
            [TError], already reported elsewhere).  Deliberately does NOT
            use "not in [env.fn_arities]" as the discriminator: that field
            is cleared by [bind_var] on ANY rebinding of the same name
            (correct for its own arity-check purpose — see its comment —
            but a bulk `import Mod` rebinds every imported name via
            [bind_var] too), so at multi-file program scale one importing
            module's `import Shared` would wipe [fn_arities]'s "helper" entry
            for every OTHER module checked afterward in the same threaded
            env, and a plain, unaliased `helper()` call would be misflagged.
            [plain_let_names] avoids that: it is only ever ADDED to at one
            site, so it can't be emptied by an unrelated binding elsewhere. *)
      let noncallable_error =
        match f, args with
        | Ast.EVar name, [] when StringSet.mem name.txt noncallable_builtin_values ->
          Some name
        | Ast.EVar name, [] when StringSet.mem name.txt env.plain_let_names ->
          (match repr f_ty with
           | TArrow _ | TVar _ | TError -> None
           | _ -> Some name)
        | _ -> None
      in
      (match arity_error, noncallable_error with
       | Some (name, arity, n_args, def_span), _ ->
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
       | None, Some name ->
         Err.error env.errors ~span:sp
           (Printf.sprintf
              "`%s` is not a function — it has type `%s`.\n\
               Remove the `()` and use `%s` directly."
              name.txt (pp_ty (repr f_ty)) name.txt);
         TError
       | None, None ->
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
      (let ci_opt = match lookup_ctor_same_module name.txt env with
         | Some _ as r -> r
         | None ->
         match lookup_ctor name.txt env with
         | Some _ as r -> r
         | None ->
           (* Try qualified module resolution: "Mod.Ctor" *)
           let _, resolved = resolve_qualified_ctor name.txt env in
           resolved
       in
       (match ci_opt with
        | Some ci when !(env.current_decl) <> "" ->
          env.refs := { callee = qualify_ref_name ci.ci_module
                          (if String.contains name.txt '.'
                           then (let i = String.rindex name.txt '.' in
                                 String.sub name.txt (i + 1) (String.length name.txt - i - 1))
                           else name.txt);
                        caller = !(env.current_decl);
                        ref_kind = `Ctor;
                        ref_file = sp.Ast.file;
                        ref_line = sp.Ast.start_line } :: !(env.refs)
        | Some _ | None -> ());
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
         (* A bare, unqualified reference whose candidates span more than one
            DECLARING MODULE (not just more than one bare type name — two
            candidates from the SAME module sharing a ctor name across
            unrelated types is the pre-existing, harmless case below) is
            genuinely ambiguous when the current module owns none of them. *)
         (if not (String.contains name.txt '.') then begin
           let candidates = all_ctor_candidates_named name.txt env in
           let distinct_modules = List.sort_uniq compare (List.map snd candidates) in
           let local_owns_one =
             List.exists
               (fun (_, m) ->
                  m = env.current_module
                  || List.exists (same_package_namespace m)
                       (local_module_paths env))
               candidates in
           if List.length distinct_modules > 1 && not local_owns_one then begin
             let lines = List.map (fun (t, m) ->
                 Printf.sprintf "  • `%s.%s` — from type `%s` in module `%s`"
                   m name.txt t m) candidates in
             Err.error env.errors ~span:name.span
               (Printf.sprintf
                  "Constructor `%s` is ambiguous between multiple modules:\n%s\n\
                   Use a qualified form to disambiguate."
                  name.txt (String.concat "\n" lines))
           end else begin
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
           end
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
           (* Message-payload sendability. The overall constructor RESULT
              type (e.g. TCon("Worker_Msg", [])) can never carry this
              information -- actor message sum types are registered with
              ci_params = [] (see ci_is_actor_msg's doc comment), so their
              type never varies with payload. The instantiated ARGUMENT
              types (arg_tys, already solved by the check_expr loop above)
              are the only place a RingBuf/NativeIntArr/NativeFloatArr
              hidden in a message payload is actually visible. Runs once,
              here, at message-construction time -- covers every current
              and future way to move the resulting value (send,
              send_checked, Actor.cast, Actor.call, or just storing it in a
              variable first), not just the builtin used at THIS callsite. *)
           if ci.ci_is_actor_msg then
             List.iter (check_sendable env.errors sp) arg_tys;
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
      let bindings, pat_ty = infer_pattern ~expected:rhs_ty env b.bind_pat in
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
           | Some sch -> Some (instantiate ~use_span:sp env.level env sch)
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
                  | Some sch -> Some (instantiate ~use_span:sp env.level env sch)
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
    | Ast.ESend (cap, msg, _sp) ->
      ignore (infer_expr env cap);
      (* Message-payload sendability (RingBuf/NativeIntArr/NativeFloatArr)
         is checked once, at message-CONSTRUCTION time, in the ECon arm
         (guarded by ci_is_actor_msg) -- not here. The overall type of `msg`
         (a bare TCon("<Actor>_Msg", []), since actor message sum types are
         registered with ci_params = []) never varies with payload and so
         could never see a mutable-buffer type nested in it; checking it
         here was a no-op regardless of what check_sendable's argument was. *)
      let _msg_ty = infer_expr env msg in
      (* send() returns Option(Unit): Some(()) when the message was enqueued,
         None when the target actor is dead/unknown (fire-and-forget drop).
         This is the ACTUAL contract of both backends — the interpreter's ESend
         only ever produces `Some(VUnit)` / `None` (sends are async; the
         handler result never flows back), and the compiled runtime's
         march_send returns the equivalent boxed Option(Unit).  The previous
         `fresh_var` typing ("returns the handler's result — unconstrained")
         was stale AND actively harmful compiled: the erased Option('a) at a
         `match send(...)` scrutinee made emit_case's abstract-arg niche
         recovery guess the NICHE decode for march_send's BOXED values, so
         `send(dead_pid, M)` decoded as Some while the interpreter said None. *)
      TCon ("Option", [t_unit])

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
      (* Return Pid[state] rather than Pid[fresh]: [DActor] binds the actor
         NAME to `Pid[state_ty]` in [env.vars], but the nullary-constructor
         registration (needed so `spawn(Counter)` parses/checks as a name)
         shadows that binding at every ECon occurrence — so the state type
         never reached an observable Pid and every spawn site got an
         unconstrained variable that unified opportunistically (finding 18,
         core-march-types.md §2.6.3).  Reach the vars binding directly by
         name here.  Unknown names (error recovery) keep the fresh var. *)
      let actor_name = match actor with
        | Ast.ECon (n, [], _) -> Some n.txt
        | Ast.EVar n          -> Some n.txt
        | _ -> None in
      (match actor_name with
       | Some n ->
         (match StrMap.find_opt n env.vars with
          | Some sch ->
            (match instantiate env.level env sch with
             | TCon ("Pid", _) as pid_ty -> pid_ty
             | _ -> TCon ("Pid", [fresh_var env.level]))
          | None -> TCon ("Pid", [fresh_var env.level]))
       | None -> TCon ("Pid", [fresh_var env.level]))

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
         (* [t_ok] is no longer a bare fresh var — the unify above bound it to
            the RHS's Ok payload — so it is a usable expected type here, and a
            record pattern needs it to open its field list. *)
         let bindings, pat_ty = infer_pattern ~expected:t_ok env p in
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
      | [], TArrow (param_ty, ret_ty)
        when (match repr param_ty with TTuple [] -> true | _ -> false) ->
        (* A 0-arg lambda `fn -> body` (or the equivalent `fn () -> body`,
           which parses identically to [ELam ([], ...)]) checked against a
           declared `Unit -> T` is accepted as a unit-consuming thunk: there is
           no surface parameter to bind (the unit domain is implicit), so we
           simply check the body against the arrow's result type.  This lets
           `fn -> body` satisfy a `Unit -> Unit` callback param — the natural
           spelling — without forcing the `fn _ -> body` (1-arg discard) idiom.
           The symmetric call side (`cb()`) is handled in [infer_app]. *)
        check_expr env body ret_ty ~reason
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
    iter_arms_linear env branches (fun (br : Ast.branch) ->
        let bindings, pat_ty = infer_pattern ~expected:scrut_ty env br.branch_pat in
        unify env ~span:msp ~reason:(Some (RMatchArm msp)) scrut_ty pat_ty;
        (* Propagate linearity from scrutinee to pattern-bound variables. *)
        let env' = bind_pattern_bindings scrut bindings env in
        (match br.branch_guard with
         | Some g ->
           check_expr env' g t_bool
             ~reason:(Some (RBuiltin "Match guards must be Bool."))
         | None -> ());
        with_offer_refinement env scrut br (fun () ->
          check_expr env' br.branch_body expected ~reason)
      );
    if not (check_offer_label_exhaustiveness env msp scrut branches) then
      check_exhaustiveness env msp scrut_ty branches;
    check_redundant_arms env scrut_ty branches

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
  | [], t ->
    (* A call written with empty parens — `f()`, i.e. zero surface arguments
       at [idx = 0] — against a `Unit -> T` value applies the implicit unit
       argument and yields `T`.  This mirrors March's 0-arg convention: a
       0-arg function is typed as its return type, and a 0-arg lambda
       `fn -> body` checks against `Unit -> T` (see the [ELam] arm in
       [check_expr]).  The [idx = 0] guard keeps a partial application that
       merely leaves a trailing `Unit -> T` (e.g. `g(x)` with
       `g : Int -> Unit -> T`) returning the arrow — only the literal
       empty-parens call form applies the implicit unit. *)
    (match idx, t with
     | 0, TArrow (param_ty, ret_ty)
       when (match repr param_ty with TTuple [] -> true | _ -> false) ->
       ret_ty
     | _ -> t)
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

(** Extract the branch label an atom arm selects (nullary `:L`), if any. *)
and offer_arm_label (br : Ast.branch) =
  match br.branch_pat with
  | Ast.PatAtom (l, [], _)          -> Some l
  | Ast.PatLit (Ast.LitAtom l, _)   -> Some l
  | _                               -> None

(** Exhaustiveness for a `match` whose scrutinee is an OFFER LABEL variable.
    The label's universe is the protocol's branch set — closed — not the open
    `Atom` universe the generic checker assumes.  Returns [true] when this
    specialised check ran (so the caller skips the generic one). *)
and check_offer_label_exhaustiveness env span scrut (branches : Ast.branch list) =
  match scrut with
  | Ast.EVar name ->
    (match List.assoc_opt name.txt env.offer_labels with
     | None -> false
     | Some (_r, proto_branches) ->
       let has_catch_all =
         List.exists (fun (br : Ast.branch) ->
             match br.branch_pat with
             | Ast.PatWild _ | Ast.PatVar _ -> br.branch_guard = None
             | _ -> false) branches
       in
       let handled =
         List.filter_map (fun (br : Ast.branch) ->
             if br.branch_guard = None then offer_arm_label br else None) branches
       in
       let missing =
         List.filter (fun (lbl, _) -> not (List.mem lbl handled)) proto_branches
       in
       (* An arm naming a label the protocol does not offer can never be taken —
          almost always a typo (`:okk` for `:ok`).  A warning, not an error: a
          redundant arm is dead code, not a soundness problem. *)
       List.iter (fun (br : Ast.branch) ->
           match offer_arm_label br with
           | Some lbl when not (List.mem_assoc lbl proto_branches) ->
             Err.warning env.errors ~span
               (Printf.sprintf
                  "This `match` has an arm for `:%s`, which is not one of the \
                   protocol's `offer` branches — it can never be taken.\n\
                   The branches are: %s."
                  lbl
                  (String.concat ", " (List.map (fun (l, _) -> ":" ^ l) proto_branches)))
           | _ -> ()) branches;
       (if not has_catch_all && missing <> [] then
          Err.error env.errors ~span
            (Printf.sprintf
               "This `match` doesn't handle every branch the peer can choose — \
                missing: %s.\n\
                The protocol's `offer` branches are: %s."
               (String.concat ", " (List.map (fun (l, _) -> ":" ^ l) missing))
               (String.concat ", " (List.map (fun (l, _) -> ":" ^ l) proto_branches))));
       true)
  | _ -> false

(** Run [f] with the offer channel's session ref transiently refined to the
    branch [br] selects (F5).  When [scrut] is an offer label variable (linked
    in [env.offer_labels]) and [br]'s pattern names a known branch label, point
    the shared session ref at that branch's continuation for the duration of
    [f], then restore it — so the channel bound alongside the label types at the
    branch the peer ACTUALLY chose inside each arm, not always the first. *)
and with_offer_refinement env scrut (br : Ast.branch) (f : unit -> unit) =
  let applied =
    match scrut with
    | Ast.EVar name ->
      (match List.assoc_opt name.txt env.offer_labels, offer_arm_label br with
       | Some (r, branches), Some lbl ->
         (match List.assoc_opt lbl branches with
          | Some cont -> let saved = !r in r := cont; Some (r, saved)
          | None -> None)
       | _ -> None)
    | _ -> None
  in
  match applied with
  | Some (r, saved) ->
    (* Snapshot-and-restore the WHOLE list rather than re-adding [r] on the way
       out: safe because [Chan.offer] only ever PREPENDS, so anything registered
       while [f] runs is a strictly newer, unrelated ref whose own scope ended
       with [f] — restoring the snapshot cannot resurrect a stale mark or drop a
       live one for a ref still reachable after this arm. *)
    let saved_unrefined = !(env.offer_unrefined) in
    env.offer_unrefined := List.filter (fun r' -> not (r' == r)) saved_unrefined;
    Fun.protect
      ~finally:(fun () -> r := saved; env.offer_unrefined := saved_unrefined)
      f
  | None ->
    (* No refinement applied.  If the scrutinee IS an offer label but this arm
       names no branch (a `_`/variable catch-all), the user demonstrably DID
       write a `match` — record that so any unrefined-channel diagnostic raised
       inside the arm explains why the catch-all does not count (F7). *)
    let is_offer_catchall =
      match scrut with
      | Ast.EVar name ->
        List.mem_assoc name.txt env.offer_labels
        && (match br.branch_pat with
            | Ast.PatWild _ | Ast.PatVar _ -> true
            | _ -> false)
      | _ -> false
    in
    if is_offer_catchall then begin
      incr offer_catchall_depth;
      Fun.protect ~finally:(fun () -> decr offer_catchall_depth) f
    end else f ()

(** Check each match arm as a mutually-exclusive path with respect to
    linear-value use.  Because at most one arm runs on any execution path, a
    linear value bound OUTSIDE the match may be consumed once in EACH arm
    without violating "use exactly once".  Snapshot the outer linear-use flags,
    reset them before every arm, and union afterwards (a var used in any arm is
    marked consumed) — eliminating the spurious "used more than once" a shared
    mutable flag would otherwise raise across arms, while still catching a
    genuine double-use WITHIN a single arm. *)
and iter_arms_linear env (branches : Ast.branch list) (f : Ast.branch -> unit) : unit =
  (* For each outer linear entry track (entry, pre-match flag, union accumulator). *)
  (* [le_first_use] is saved and restored alongside [le_used]. If it were not,
     the first arm to consume a value would leave its span behind, and a genuine
     double-use in a LATER arm would point at a line in a sibling arm that never
     ran on the same path — a confidently wrong "already consumed here". *)
  let snapshot =
    List.map (fun le ->
        (le, !(le.le_used), ref !(le.le_used),
             !(le.le_first_use), ref !(le.le_first_use)))
      env.lin
  in
  List.iter (fun br ->
      (* Reset each entry to its pre-match state so this arm sees a fresh path. *)
      List.iter (fun (le, was, _acc, was_span, _acc_span) ->
          le.le_used := was; le.le_first_use := was_span) snapshot;
      f br;
      (* Fold whatever this arm consumed into the union accumulator. *)
      List.iter (fun (le, _was, acc, _was_span, acc_span) ->
          if !(le.le_used) then begin
            acc := true;
            if !acc_span = None then acc_span := !(le.le_first_use)
          end) snapshot
    ) branches;
  (* Final: consumed iff consumed before the match OR in some arm. *)
  List.iter (fun (le, _was, acc, _was_span, acc_span) ->
      le.le_used := !acc; le.le_first_use := !acc_span) snapshot

(** Infer the result type of a match expression. *)
and infer_match env span scrut scrut_ty branches =
  let result_ty = fresh_var env.level in
  iter_arms_linear env branches (fun (br : Ast.branch) ->
      let bindings, pat_ty = infer_pattern ~expected:scrut_ty env br.branch_pat in
      unify env ~span ~reason:(Some (RMatchArm span)) scrut_ty pat_ty;
      (* Propagate linearity from scrutinee to pattern-bound variables. *)
      let env' = bind_pattern_bindings scrut bindings env in
      (match br.branch_guard with
       | Some g ->
         check_expr env' g t_bool
           ~reason:(Some (RBuiltin "Match guards must be Bool."))
       | None -> ());
      with_offer_refinement env scrut br (fun () ->
        check_expr env' br.branch_body result_ty
          ~reason:(Some (RMatchArm span)))
    );
  if not (check_offer_label_exhaustiveness env span scrut branches) then
    check_exhaustiveness env span scrut_ty branches;
  check_redundant_arms env scrut_ty branches;
  result_ty

(** Whether every diagnostic in [scratch] stems from a data constructor used
    in type position — a phantom/typestate tag like `Handle(Open)`, where
    `Open` is a constructor of some ADT rather than a type name, which
    [surface_ty] legitimately cannot resolve (it emits [qualified_error_msg]'s
    unqualified-name form, "I cannot find `Open`.", for the ctor name).
    Recognised by checking that the unresolved name IS a known constructor
    ([env.ctors]) — genuinely bogus names (typo'd/renamed types, unknown
    modules) are never registered there, so this returns [false] for those
    and the caller must surface the error instead of discarding it. *)
and annotation_errors_are_phantom_tags_only env (scratch : March_errors.Errors.ctx) =
  let prefix = "I cannot find `" in
  let plen = String.length prefix in
  List.for_all (fun (d : March_errors.Errors.diagnostic) ->
    let msg = d.March_errors.Errors.message in
    String.length msg >= plen + 2
    && String.sub msg 0 plen = prefix
    && String.sub msg (String.length msg - 2) 2 = "`."
    && StrMap.mem (String.sub msg plen (String.length msg - plen - 2)) env.ctors
  ) scratch.March_errors.Errors.diagnostics

(** Compute the type of a `let`-binding RHS, honouring an optional type
    annotation (`let x : T = e`, finding 16).  When [bind_ty] is present the
    annotation becomes a CHECKING context for the RHS (via [check_expr]) — a
    mismatch like `let x : Int = "foo"` is rejected, while a polymorphic RHS
    bound at a more specific instance (`let f : (Int) -> Int = fn x -> x`)
    still typechecks.

    The annotation is resolved into a scratch error context first.  If
    [surface_ty] fails ONLY because of a phantom/typestate tag used in type
    position (`let h : Handle(Open) = …`), we discard the scratch errors and
    fall back to plain inference — the pre-finding-16 behaviour for
    annotations the type grammar can't express.  But if any failure is a
    genuinely unresolvable name (unknown module, typo'd/renamed type — see
    the `RRB`/`Vec(Int) = "not a vec"` soundness hole), the annotation is
    real and broken: surface the scratch diagnostics as real errors instead
    of silently ignoring the annotation. *)
and infer_let_annotated env sp bind_ty bind_expr =
  match bind_ty with
  | None -> infer_expr env bind_expr
  | Some ann ->
    let scratch = March_errors.Errors.create () in
    let tvars = ref [] in
    let ann_ty = surface_ty { env with errors = scratch } ~tvars ann in
    if March_errors.Errors.has_errors scratch then begin
      if not (annotation_errors_are_phantom_tags_only env scratch) then
        List.iter (fun (d : March_errors.Errors.diagnostic) ->
          March_errors.Errors.error env.errors ~span:d.March_errors.Errors.span
            d.March_errors.Errors.message
        ) scratch.March_errors.Errors.diagnostics;
      (* Annotation not (fully) expressible as a resolvable type — infer from
         the RHS alone; any genuine error was already surfaced above. *)
      infer_expr env bind_expr
    end else begin
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
    (* Drive the pattern from the RHS type, exactly as the match path drives
       arms from the scrutinee type.  A record pattern needs this to know the
       record's full field list — without it, it synthesizes a CLOSED record
       from just the fields it names and `let { code: c } = p` fails to unify
       against a wider `p`.  The [unify] below is then a no-op for records and
       unchanged for every other pattern shape. *)
    let bindings, pat_ty = infer_pattern ~expected:rhs_ty env_rhs b.bind_pat in
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
         (* L8: a `linear`/`affine` RHS type — e.g. a call to
            `fn mk() : linear Res` — propagates its linearity to the plain
            `let h = mk()` binding, so the return-position qualifier is not
            merely decorative.  EXCLUDE channels: a `TLin`-wrapped `TChan`
            (session endpoint) has its own tracking (offer_conts / affine param
            / End-drop create-and-drop leniency) and was Unrestricted here
            before — promoting it to strict-linear would regress that. *)
         | TLin (lin, inner) when lin <> Ast.Unrestricted
             && (match repr inner with TChan _ -> false | _ -> true) -> lin
         | TCon (name, _) ->
           if resolves_always_linear name env then Ast.Linear else Ast.Unrestricted
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
    (* Mark a simple, unrestricted `let name = expr` binding as a genuine
       plain VALUE (see [plain_let_names]) — this is the ONLY site that adds
       to it, so it's a precise, narrow, positively-identified signal (as
       opposed to [fn_arities]'s broader "not a known function" absence,
       which the [Ast.EApp] handler's zero-arg noncallable check used to
       lean on for this and proved unsafe: a bulk `import Mod` re-binds
       every imported name via [bind_var] too, which — by design (see the
       comment above [bind_var]) — clears any [fn_arities] entry for that
       name as part of ordinary shadow discipline, so a large multi-file
       program whose modules cross-import a same-module zero-arg fn made
       EVERY later reference to it look "not a known function").  Only a
       true `let x = e` (single-variable pattern, non-linear) is marked —
       destructuring patterns, lambda/fn params, and match arms are left
       alone (narrower scope, no false positives there either way).

       Critically, ALSO exclude an RHS that is itself a lambda literal
       (`Ast.ELam`, i.e. `let g = fn ... -> body`).  A ZERO-param lambda
       checked under plain inference (no expected-type context — see the
       [Ast.ELam] arm of [infer_expr]) collapses to its body's result type
       exactly like a top-level zero-arg `fn`, via the identical
       [List.fold_right ... [] body_ty = body_ty] convention — it only
       gets a real `Unit -> T` [TArrow] when CHECKED against one (the
       [Ast.ELam] arm of [check_expr]).  So `let g = fn -> println("b")`
       then `g()` (test/native/unit_callback_zero_arg.march) is completely
       legitimate, ordinary code whose RHS produces the very same
       "collapsed non-arrow type" shape as the bug this check targets —
       type alone truly cannot tell them apart here, but the AST shape of
       the RHS can: a fresh lambda LITERAL is never a "disguised alias of
       something else", it always means exactly what it says. *)
    let env' =
      match b.bind_pat, auto_lin, b.bind_expr with
      | Ast.PatVar _, Ast.Unrestricted, Ast.ELam _ ->
        env'
      | Ast.PatVar name, Ast.Unrestricted, _ ->
        { env' with plain_let_names = StringSet.add name.txt env'.plain_let_names }
      | _ -> env'
    in
    (* F5 path-dependent OFFER refinement: if this let destructures a
       `Chan.offer` result — a 2-tuple whose 2nd component is a channel whose
       session ref was registered in [offer_conts] — link the label variable
       (1st tuple component) to that channel's ref + branch map, so a later
       `match <label>` can refine the channel per arm.  Detected purely from
       the (repr'd) RHS type + the tuple-of-vars pattern shape, so it fires for
       both the `Chan.offer(x)` and `Mod.offer`-normalized call spellings. *)
    let env' =
      match b.bind_pat, repr rhs_ty with
      | Ast.PatTuple ([Ast.PatVar lbl; Ast.PatVar _chan], _),
        TTuple [_; chan_ty] ->
        (match repr chan_ty with
         | TLin (_, TChan r) | TChan r ->
           (match List.find_opt (fun (r', _) -> r' == r) !(env.offer_conts) with
            | Some (r', branches) ->
              { env' with offer_labels = (lbl.txt, (r', branches)) :: env'.offer_labels }
            | None -> env')
         | _ -> env')
      | _ -> env'
    in
    let result_ty = infer_block env' rest in
    (* After the rest of the block has run, verify that any linear let
       bindings introduced here were consumed (used exactly once). *)
    (match auto_lin with
     | Ast.Unrestricted -> ()
     | _lin ->
       let linear_names = List.map fst bindings' in
       check_linear_all_consumed env' ~scope_span:sp linear_names);
    (* Session-specific must-close accounting (F7 hole a): a channel binding
       whose session state is `End` MUST be closed — dropping it leaks the
       endpoint.  This is NARROWER than full linear consumption on purpose: a
       freshly-created channel still at a Send/Recv/Choose/Offer state that is
       never driven stays legal (the accept corpus deliberately creates-and-
       drops such endpoints, e.g. t42/t44), matching the documented scope
       (mid-protocol drop is the out-of-scope F6, only `End`-drop is caught).
       A channel that reaches `End` and IS passed to `Chan.close` counts as
       used (its EVar fires [record_use]); only a dropped `End` channel — never
       referenced after the binding — is flagged. *)
    List.iter (fun (n, sch) ->
        let bty = match sch with Mono t -> t | Poly (_, _, t) -> t in
        let at_end = match repr bty with
          | TLin (_, TChan r) | TChan r ->
            (match unfold_srec !r with SEnd -> true | _ -> false)
          | _ -> false
        in
        if at_end then
          match List.find_opt (fun le -> le.le_name = n) env'.lin with
          | Some le when not !(le.le_used) ->
            Err.error env.errors ~span:sp
              (Printf.sprintf
                 "Session channel `%s` reached `End` but was never closed.\n\
                  A channel at `End` must be passed to `Chan.close` — dropping \
                  it leaks the endpoint." n)
          | _ -> ()
      ) bindings';
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
    (* Register this local fn's arity in [fn_arities] (mirrors the top-level
       `DFn` registration — see the [env_rec] comment above [check_fn]) so
       the [arity_error] wrong-arg-count check in [Ast.EApp]'s handler also
       covers direct calls of a local `fn ... end` binding, not just a
       top-level `fn` decl — e.g. `fn helper(a, b) do ... end; helper(1)`
       inside a block now reports the same "expects 2 arguments" diagnostic
       a top-level `helper` would.  (This is NOT needed for the zero-arg
       "calling a non-function value" check just above — that one uses
       [plain_let_names], which a local `fn ... end` binding never enters,
       so `helper()`/a sibling local fn calling `helper()` already
       typechecks regardless of this registration.)  [bind_var] just above
       already cleared any stale entry under this name (shadow semantics),
       so this is a plain (re-)add, not a merge. *)
    let env' =
      { env' with fn_arities =
          StrMap.add name.txt (List.length params, name.span) env'.fn_arities } in
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
    | Some ann, expected ->
      let tvars = ref [] in
      let ann_t = surface_ty env ~tvars ann in
      (* RECONCILE the annotation with the type the caller expects this
         parameter to have (F5 residual, 2026-07-27).  [bind_lam_params] mints a
         fresh var per parameter, builds the lambda's ARROW type from those vars
         and passes each one here; [check_expr]'s lambda-peel passes the arrow
         component of the expected type.  Before this unify, an ANNOTATED
         parameter simply ignored that type: the body was checked against the
         annotation while the arrow — and therefore every call site — kept the
         unrelated variable.  So a lambda (or a named `fn` nested in a function
         body, which routes here too) had its parameter annotations checked
         against NOTHING, and an argument flowing into an annotated parameter
         reached neither the [Chan.*] operation arms nor [unify]'s `TChan`
         laundering guard — letting an unrefined `Chan.offer` continuation be
         washed clean by `fn (c : Chan(R, P)) -> ...`.  The top-level [check_fn]
         `FPNamed` loop never had this gap, which is why only the inner forms
         leaked. *)
      (match expected with
       | Some t0 ->
         unify env ~span:p.param_name.Ast.span
           ~reason:(Some (RAnnotation p.param_name.Ast.span)) t0 ann_t
       | None -> ());
      ann_t
    | None, Some t -> t
    | None, None   -> fresh_var env.level
  in
  let effective_lin = match p.param_lin with
    | Ast.Unrestricted ->
      (match repr t with
       | TCon (name, _) when resolves_always_linear name env -> Ast.Linear
       (* A parameter whose resolved type is a linear/affine wrapper — e.g. a
          session channel `ch : Chan(Client, Echo)` resolving to
          `TLin(Linear, TChan …)` — is tracked as AFFINE so a re-read of the
          endpoint is caught (F7 hole b) while a never-driven endpoint stays
          legal (create-and-drop leniency; see the matching note in [check_fn]'s
          parameter loop).  The old code only recognized `always_linear` [TCon]s
          here, so such a parameter slipped past the use-tracker entirely; a
          let-bound channel was already tracked via [bind_pattern_bindings]. *)
       | TLin (lin, _) when lin <> Ast.Unrestricted -> Ast.Affine
       | _ -> Ast.Unrestricted)
    | lin -> lin
  in
  (* Track the linear parameter at its INNER (unwrapped) type, matching how
     [bind_pattern_bindings] registers linear let-bindings. *)
  let bind_ty = match repr t with TLin (_, inner) -> inner | _ -> t in
  match effective_lin with
  | Ast.Unrestricted ->
    let env1 = bind_var p.param_name.txt (Mono t) env in
    bind_linear_field_sentinels p.param_name.txt t env1
  | lin -> bind_linear p.param_name.txt lin bind_ty env

(* =================================================================
   §15  Declaration checking
   ================================================================= *)

(** Collect all free variable names referenced in [e].
    Every [EVar] node is collected, QUALIFIED (dotted) names included.
    Re-bindings introduced by [ELet]/[EMatch]/[ELam] are accounted for so
    we never report a variable that is shadowed by an inner binding. *)
let rec free_vars_expr (bound : string list) (e : Ast.expr) : string list =
  match e with
  | Ast.EVar n ->
    (* Keep DOTTED names too (e.g. `App.id`, produced by desugar's
       [qualify_module_refs] for an intra-nested-module reference).  Do NOT
       "clean this up" to bare names — dotted entries are LOAD-BEARING for one
       of the three callers:
       - [dependency_order_dfn_run]'s [deps_of] maps a dotted name's suffix to a
         local fn so a nested-module forward reference is ordered helper-first
         (closing the qualified-prebind type-erasure forward-ref hole);
       - [warn_unused_params] only compares against bare param names;
       - [record_fn_refs] feeds the per-function transitive CAPABILITY closure,
         where a dropped dotted name silently truncates the closure of every
         nested-module reference (pinned by
         [test_transitive_cap_nested_module_dotted_refs]).
       A bound name is still dropped. *)
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
  | Ast.PatOr (ps, _) -> List.concat_map free_vars_pattern ps

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
  (* [current_decl] is a single shared ref, not a stack — save/restore around
     the whole body so it never leaks into whatever gets checked next once
     this fn's body is done (nested fns, a later top-level decl, etc.). This
     mirrors [with_no_caller]'s save/restore pattern but restores the PREVIOUS
     caller rather than blanking to "", since [check_fn] can itself be nested
     (a closure body containing a locally-defined named fn). *)
  let saved_caller = !(env.current_decl) in
  env.current_decl := qualify_ref_name env.current_module def.fn_name.txt;
  Fun.protect ~finally:(fun () -> env.current_decl := saved_caller) (fun () ->
  let env'    = enter_level env in
  (* Captured BEFORE the self-bind below (which unconditionally clears any
     [local_fns] entry for this name, per [bind_var]'s shadowing discipline)
     so we know whether to restore it afterward — this fn is only a genuine
     top-level Call-recording target if it already was one; an impl method
     (checked via [check_fn] too, but never registered in [local_fns] to
     begin with) must not spuriously become one. *)
  let was_local_fn = StrMap.mem def.fn_name.txt env'.local_fns in
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
  (* The self-bind above cleared any fn_arities/local_fns entry for this name
     (shadow semantics — correct when a NESTED fn shadows a top-level fn of
     different arity).  Re-register the CURRENT def's own arity so recursive
     calls in the body are still arity-checked, against the right arity
     either way — and re-register [local_fns] so a recursive call to this
     same top-level fn is still recorded as a genuine Call reference (see
     [bind_var]'s [local_fns] shadowing-discipline comment; [check_fn] is
     only ever called for actual top-level/impl-method fns, never a nested
     local `fn`, so it is always correct to restore this membership here). *)
  let env_rec =
    let arity = match def.fn_clauses with
      | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
    { env_rec with fn_arities =
        StrMap.add def.fn_name.txt (arity, def.fn_name.span) env_rec.fn_arities;
      local_fns =
        if was_local_fn then StrMap.add def.fn_name.txt () env_rec.local_fns
        else env_rec.local_fns } in

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
                   | TCon (tname, _) when resolves_always_linear tname env' -> Ast.Linear
                   (* A session-channel parameter (`ch : Chan(Role, Proto)`)
                      resolves to a [TLin] wrapper.  Track it as AFFINE so a
                      RE-READ of the endpoint inside the body is caught (F7 hole
                      b) while a channel parameter merely declared and never
                      driven stays legal — the create-and-drop leniency the
                      session corpus already relies on for endpoints (a param at
                      a mid-protocol state is not required to be consumed; only
                      the `End`-drop of a LET-bound channel is an error, handled
                      in [infer_block]).  Full linear consumption of endpoints is
                      the stricter F6 direction, deliberately out of scope. *)
                   | TLin (lin, _) when lin <> Ast.Unrestricted -> Ast.Affine
                   | _ -> Ast.Unrestricted)
                | lin -> lin
              in
              (* Track the linear param at its inner (unwrapped) type. *)
              let bind_ty = match repr t with TLin (_, inner) -> inner | _ -> t in
              let env' = match effective_lin with
                | Ast.Unrestricted ->
                  (* Register per-field linear sentinels for a record-typed param
                     with `linear`/`affine` fields (L3): mirrors [bind_lam_param]
                     so a top-level `fn f(p : Rec)` tracks `p.field` double-use as
                     an ERROR, not a warning — previously only let-bound and lambda
                     params registered these, so fn-param field linearity was
                     silently warning-only. *)
                  let env1 = bind_var p.param_name.txt (Mono t) env in
                  bind_linear_field_sentinels p.param_name.txt t env1
                | lin              -> bind_linear p.param_name.txt lin bind_ty env
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
  sch)

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
(* Do two impl HEAD types OVERLAP — i.e. is there a substitution of their free
   type variables making them equal?  This is the coherence-overlap test
   (T-ImplCoherent), covering BOTH Stage 1 (exact / alpha-equal heads: two
   `impl Speak(Dog)`, or `impl Show(List(a))` × 2) AND Stage 2 (parametric:
   `impl Show(List(a))` vs `impl Show(List(Int))` overlap with `a ↦ Int`).
   Non-overlapping: `Dog`/`Cat`, `List(a)`/`Option(a)` (different head ctor),
   `Pair(a,a)`/`Pair(Int,Bool)` (`a` can't be both).

   PURE and non-mutating: it never touches the stored heads' [TVar] refs — a
   local id-keyed substitution stands in for unification, so a var bound once
   must match consistently on every later occurrence (that is what rejects the
   `Pair(a,a)` row).  Both heads carry DISTINCT fresh var ids (from
   [lenient_ty]/[surface_ty]), so their bindings never collide. *)
let types_overlap (a0 : ty) (b0 : ty) : bool =
  let subst : (int, ty) Hashtbl.t = Hashtbl.create 8 in
  let rec go t1 t2 =
    let t1 = repr t1 and t2 = repr t2 in
    match t1, t2 with
    | TVar r1, _ ->
      (match !r1 with
       | Unbound (id, _) ->
         (match Hashtbl.find_opt subst id with
          | Some bound -> go bound t2
          | None -> Hashtbl.replace subst id t2; true)
       | Link _ -> go t1 t2)
    | _, TVar r2 ->
      (match !r2 with
       | Unbound (id, _) ->
         (match Hashtbl.find_opt subst id with
          | Some bound -> go t1 bound
          | None -> Hashtbl.replace subst id t1; true)
       | Link _ -> go t1 t2)
    | TCon (n1, a1), TCon (n2, a2) ->
      n1 = n2 && List.length a1 = List.length a2 && List.for_all2 go a1 a2
    | TTuple l1, TTuple l2 ->
      List.length l1 = List.length l2 && List.for_all2 go l1 l2
    | TRecord f1, TRecord f2 ->
      List.length f1 = List.length f2
      && List.for_all2 (fun (n1, x1) (n2, x2) -> n1 = n2 && go x1 x2) f1 f2
    | TArrow (p1, r1), TArrow (p2, r2) -> go p1 p2 && go r1 r2
    | TLin (_, x1), TLin (_, x2) -> go x1 x2
    | TLin (_, x1), _ -> go x1 t2
    | _, TLin (_, x2) -> go t1 x2
    | TNat n1, TNat n2 -> n1 = n2
    | TError, _ | _, TError -> false
    | _ -> t1 = t2
  in go a0 b0

let register_impl_shape ?(decl_module="") env (idef : Ast.impl_def) =
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
  let key = idef.impl_iface.txt in
  let sp  = idef.impl_iface.span in
  let lst = Option.value ~default:[] (StrMap.find_opt key env.impls) in
  (* Resolve the head type's DECLARING MODULE (verified 2026-07-20):
     - qualified head "Mod.T" → the "Mod" prefix (the type's real module,
       regardless of where the impl is written — keeps orphan impls colliding);
     - bare head "T" declared locally by the impl's own module → decl_module
       ([decl_module ^ ".T"] is registered in env.types by the pass-1 prebind);
     - otherwise None → conservative (treated as overlapping, no false negative,
       e.g. two modules both implementing the SAME imported type). *)
  let head_type_module =
    match idef.impl_ty with
    | Ast.TyCon (n, _) ->
      let name = n.txt in
      (match String.rindex_opt name '.' with
       | Some i -> Some (String.sub name 0 i)
       | None ->
         if decl_module <> ""
            && StrMap.mem (decl_module ^ "." ^ name) env.types
         then Some decl_module
         else None)
    | _ -> None
  in
  let modules_distinct m1 m2 =
    match m1, m2 with Some a, Some b -> a <> b | _ -> false in
  (* Declaring-module coherence relaxation (FQN dispatch, all stages landed):
     two same-short-name types declared in DIFFERENT modules are genuinely
     distinct, so each may implement the SAME interface without overlapping.
     This is sound for EVERY interface — not just the type-dispatched built-ins
     Eq/Ord/Show/Hash — because Stage 3 taught the native backend to give each
     colliding type a globally-unique runtime tag, force uniform Boxed repr,
     mangle each impl to a module-qualified symbol, and route ambiguous call
     sites through a generated runtime tag-switch dispatch fn; the interpreter
     qualifies iface_method_tbl the same way. A general interface therefore
     dispatches on the value's real type in BOTH backends (verified
     `from-A`/`from-B` — accept/t89, test/imports/speak_collision_native).

     This relaxation is now UNCONDITIONAL — no residual ctor-sharing carve-out.
     Even when the two colliding types ALSO share a constructor NAME (a "double
     collision", e.g. both `type Thing = Shared | …`), the constructor module-
     qualified identity plan resolves ctor identity upstream: native
     ECon/pattern-match qualify a colliding type's ctor key with its declaring
     module, and the interpreter qualifies the VCon tag the same way, so the
     backends and interpreter route each module's `Shared` to its OWN impl body
     (was the interim Task-6b `ctor_sets_disjoint` stopgap, removed at this
     plan's flag-day; verified accept/t90,
     test/imports/speak_double_collision_native). See
     specs/plans/2026-07-20-fqn-impl-dispatch-identity.md. *)
  (* Coherence (T-ImplCoherent), Stage 1 exact overlap: at most ONE impl per
     (interface, type-head).  A second impl whose head is alpha-equal to an
     already-registered one is a compile error — this is what makes the two
     backends agree by construction (interp's last-write-wins `impl_tbl` vs the
     monomorphizer's list order would otherwise run DIFFERENT method bodies).
     [register_impl_shape] runs per-impl across the Pass-1 folds and may see the
     SAME impl twice (nested/entry re-registration), so distinguish by SPAN:
     same span = re-registration (no-op); different span = genuine duplicate. *)
  (* A DIFFERENT-span USER entry whose head OVERLAPS this one is a coherence
     violation (exact duplicate OR parametric overlap); our own entry (same
     span, from a Pass-1 re-registration) is not.  Built-in impls live in
     [env.impls] too (seeded with [dummy_span] by [base_env]) but are SKIPPED
     here: a user impl on a primitive (`impl Eq(Int)`) coexisting with the
     built-in is the pre-existing behavior and is heavily used by the interface-
     machinery test fixtures — rejecting it (DECIDE-1) is deferred as a follow-on
     so this ships without that disruptive change. *)
  match List.find_opt
          (fun (t, s, m_old) ->
             s <> sp && s <> Ast.dummy_span
             && types_overlap t inst_ty
             && not (modules_distinct m_old head_type_module))
          lst with
  | Some (_, prev_sp, _) ->
    Err.error env.errors ~span:sp
      (Printf.sprintf
         "Overlapping implementation: `impl %s(%s)` conflicts with the \
          implementation at %s:%d:%d — their heads overlap.\n\
          A type may implement an interface at most once (coherence). If you \
          meant a different behavior, wrap the type in a newtype and implement \
          the interface on that."
         key (pp_ty inst_ty)
         prev_sp.Ast.file prev_sp.Ast.start_line prev_sp.Ast.start_col);
    env   (* keep the first impl — deterministic *)
  | None ->
    (* No conflict. Register (unless our own same-span entry is already present
       from a Pass-1 re-registration, in which case this is a no-op). *)
    if List.exists (fun (t, s, _) -> s = sp && types_overlap t inst_ty) lst
    then env
    else { env with impls =
             StrMap.add key ((inst_ty, sp, head_type_module) :: lst) env.impls }

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
      (* Prebinding an interface method's own signature has no enclosing
         function either — see [with_no_caller]. [tmp_env] shares [refs] and
         [current_decl] with [e] (record-copy, not clone of the ref cells),
         so blanking through [tmp_env] is equally visible to the [TyCon]
         hook. *)
      let ty = with_no_caller tmp_env (fun () -> surface_ty tmp_env ~tvars m.md_ty) in
      let a_id = match a with
        | TVar r -> (match !r with Unbound (id, _) -> id | _ -> 0)
        | _ -> 0
      in
      let base_sch = generalize 0 ty in
      let sch = match base_sch with
        | Poly (ids, cs, t) -> Poly (ids, CInterface (idef.iface_name.txt, a) :: cs, t)
        | Mono t -> Poly ([a_id], [CInterface (idef.iface_name.txt, a)], t)
      in
      (* Both dotted keys bound here ([full_qualified] = "Mod.Iface.method",
         [iface_qualified] = "Iface.method") are genuine function bindings —
         an interface method, never a [DLet] value — so both are also
         registered in [qual_fn_names]. This is a THIRD source of qualified
         function names (alongside [Ast.DMod] exports and registry [ExFn]
         entries): call syntax like `Show.show(x)` normalizes to
         [Ast.EVar "Show.show"] (the [Ast.EApp (Ast.EField (Ast.ECon ...))]
         rule) and resolves straight out of [env.vars] here, bypassing both
         of the other two sources entirely — so without this, the [EVar]
         reference-recording hook's [qual_fn_names] gate would wrongly treat
         every qualified interface-method call as non-function-backed and
         silently drop it. See [qual_fn_names]'s doc comment. *)
      let e1 = { e with vars = StrMap.add full_qualified sch e.vars;
                        qual_fn_names = StrMap.add full_qualified () e.qual_fn_names } in
      let e1 = if StrMap.mem iface_qualified e1.vars then e1
               else { e1 with vars = StrMap.add iface_qualified sch e1.vars;
                              qual_fn_names = StrMap.add iface_qualified () e1.qual_fn_names } in
      if StrMap.mem m.md_name.txt e1.vars then e1
      else { e1 with vars = StrMap.add m.md_name.txt sch e1.vars }
    end
  ) e1 idef.iface_methods

(** Discharge all pending Num/Ord/CInterface constraints accumulated during
    inference.  Called at each declaration boundary (DFn, DLet) to verify
    that constrained type variables were unified with a compatible type. *)
let discharge_constraints env span =
  (* Linearity is transparent to constraint discharge: `linear T` satisfies
     exactly the constraints `T` satisfies.  impl_matches_ty already strips
     TLin (its TLin/TLin arm) and unification coerces TLin transparently —
     but the discharge arms below match on the repr'd type directly, so
     without this strip an expression-position `linear Int` (a linear
     record-field access, or a `linear Int`-returning call, used in
     arithmetic) falls to the catch-all and rejects with "`linear Int` does
     not implement Num" before the linearity tracker ever runs (slice-7
     finding L2). *)
  let rec strip_lin t = match repr t with
    | TLin (_, inner) -> strip_lin inner
    | t' -> t'
  in
  (* Dedup CInterface constraints: when the same concrete type is constrained
     on the same interface multiple times (e.g., 10 calls to Storage.get on
     the same storage variable), we only need to check the impl once.
     Uses pp_ty on the repr'd type as a canonical string key. *)
  let seen = Hashtbl.create 16 in
  List.iter (fun c ->
      let dominated = match c with
        | CInterface (name, t) ->
          let rt = strip_lin t in
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
        let ty   = strip_lin t in
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
        let ty = strip_lin t in
        (match ty with
         | TVar _ -> ()   (* Still polymorphic — cannot check yet *)
         | _ ->
           let satisfied = match StrMap.find_opt iface_name env.impls with
             | None -> false
             | Some impl_tys -> List.exists (fun (impl_ty, _, _) ->
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

(** [cap_annots_in_expr acc e] collects every capability named by a type
    ANNOTATION inside an expression: a [let] binding's [bind_ty], a lambda or
    local-function parameter type, a local function's return type, and
    [EAnnot].

    Check 1 historically read function SIGNATURES only, so a capability named
    inside a body escaped [needs] entirely.  That is reachable: [root_cap] is
    ambient, so a module declaring only [IO.Console] could narrow the root to
    [Cap(IO.FileWrite)] and bind it without ever putting a capability in a
    signature.  See [specs/lang/types/reject/t151_cap_let_annotation_undeclared.march].

    On [EAnnot]: the parser never produces one — desugar synthesizes the only
    instance, a hardcoded [SupervisorSpec] on an [app] block's spec field — so
    no source program can route a capability through it and there is no
    reject-witness for it in the corpus.  It is walked anyway because it costs
    one line and because the next construct desugared into an [EAnnot] should
    inherit the coverage rather than quietly reopen the gap.

    Exhaustive over [Ast.expr] with no wildcard arm, mirroring
    [March_ast.Calls.calls_in_expr]; a new expression form must break this
    build. *)
let rec cap_annots_in_expr (acc : (string * Ast.span) list) (e : Ast.expr)
  : (string * Ast.span) list =
  let of_ty acc (sp : Ast.span) (t : Ast.ty) =
    List.fold_left (fun a cap -> (cap, sp) :: a) acc (cap_paths_in_surface_ty t)
  in
  let of_ty_opt acc sp = function None -> acc | Some t -> of_ty acc sp t in
  let of_params acc sp ps =
    List.fold_left (fun a (p : Ast.param) -> of_ty_opt a sp p.param_ty) acc ps
  in
  match e with
  | Ast.ELet (b, sp) ->
    let acc = of_ty_opt acc sp b.Ast.bind_ty in
    cap_annots_in_expr acc b.Ast.bind_expr
  | Ast.EAnnot (ex, t, sp) -> cap_annots_in_expr (of_ty acc sp t) ex
  | Ast.ELam (ps, body, sp) -> cap_annots_in_expr (of_params acc sp ps) body
  | Ast.ELetFn (_, ps, ret, body, sp) ->
    let acc = of_ty_opt (of_params acc sp ps) sp ret in
    cap_annots_in_expr acc body
  | Ast.ELetQ (_, rhs, body, _) ->
    cap_annots_in_expr (cap_annots_in_expr acc rhs) body
  | Ast.EApp (f, args, _) ->
    List.fold_left cap_annots_in_expr (cap_annots_in_expr acc f) args
  | Ast.ECon (_, args, _) -> List.fold_left cap_annots_in_expr acc args
  | Ast.EBlock (es, _) -> List.fold_left cap_annots_in_expr acc es
  | Ast.EMatch (scrut, arms, _) ->
    let acc = cap_annots_in_expr acc scrut in
    List.fold_left (fun a arm ->
        let a = Option.fold ~none:a ~some:(cap_annots_in_expr a) arm.Ast.branch_guard in
        cap_annots_in_expr a arm.Ast.branch_body) acc arms
  | Ast.ETuple (es, _) -> List.fold_left cap_annots_in_expr acc es
  | Ast.ERecord (fields, _) ->
    List.fold_left (fun a (_, ex) -> cap_annots_in_expr a ex) acc fields
  | Ast.ERecordUpdate (base, fields, _) ->
    let acc = cap_annots_in_expr acc base in
    List.fold_left (fun a (_, ex) -> cap_annots_in_expr a ex) acc fields
  | Ast.EField (inner, _, _) -> cap_annots_in_expr acc inner
  | Ast.EIf (cond, then_, else_, _) ->
    cap_annots_in_expr (cap_annots_in_expr (cap_annots_in_expr acc cond) then_) else_
  | Ast.ECond (arms, _) ->
    List.fold_left (fun a (ce, be) ->
        cap_annots_in_expr (cap_annots_in_expr a ce) be) acc arms
  | Ast.EPipe (a, b, _) -> cap_annots_in_expr (cap_annots_in_expr acc a) b
  | Ast.EAtom (_, args, _) -> List.fold_left cap_annots_in_expr acc args
  | Ast.ESend (a, b, _) -> cap_annots_in_expr (cap_annots_in_expr acc a) b
  | Ast.ESpawn (ex, _) -> cap_annots_in_expr acc ex
  | Ast.EDbg (Some inner, _) -> cap_annots_in_expr acc inner
  | Ast.EAssert (ex, _) -> cap_annots_in_expr acc ex
  | Ast.ESigil (_, content, _) -> cap_annots_in_expr acc content
  | Ast.EDbg (None, _) -> acc
  | Ast.EHole _ -> acc
  | Ast.EResultRef _ -> acc
  | Ast.ELit _ | Ast.EVar _ -> acc   (* carry no type annotation *)

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

(** [fn_transitive_capability_closures_tbl env] is each function's capability set
    including everything it reaches through the reference graph:

      caps(f) = own(f) ∪ ⋃ { caps(g) | g ∈ refs(f) }

    computed to fixpoint. Sets only grow and the capability lattice is finite,
    so this terminates; mutual recursion is handled by ITERATING rather than by
    descending, so no cycle detection is needed.

    Built on [own_cap_closures] and NOT [cap_closures], deliberately: the
    latter folds in [module_wide_caps], which itself contains
    module-granularly-propagated import caps, so deriving this from it would be
    circular — and would reintroduce exactly the over-approximation this exists
    to remove (importing [List] to call [map] would inherit [pmap]'s
    [IO.Spawn]).

    Edges come from [free_vars_expr] (see [env.fn_refs]), never from a
    calls-only walk. A reference that does not resolve to a known function — a
    local binding, a parameter, a constructor, an unloaded module's member —
    contributes nothing: it has no entry, so the lookup yields [].

    This table IS load-bearing for enforcement as of 2026-08-06 —
    [check_module_needs]'s Check 4 consults it (see [import_required_caps]).

    [record_fn_caps] covers every declaration form that can hold an expression:
    [DFn] signatures/bodies/guards, default-argument expressions, actor
    handlers, [DExtern]s, module-level [DLet] bodies, [DInterface] default
    method bodies and [DImpl] method bodies. The last four were added
    2026-08-06 (see
    [specs/progress/2026-08-06-record-fn-caps-misses-dlet-and-methods.md]);
    until then they had no entry, so an edge pointing at one contributed
    nothing and the closure of anything that REACHED one was silently
    truncated — dropping a capability the pre-demand-driven Check 4 required.
    Keep this list in step with the walks in [check_module_needs]: a form with
    no entry is a fail-open hole, not merely a missing analysis.

    Returns the raw table so an in-pass consumer ([check_module_needs]'s
    demand-driven import propagation) gets O(1) lookups;
    [fn_transitive_capability_closures] is the sorted-assoc-list public view.

    Defined ABOVE [check_module_needs] because that function consumes it —
    Check 4 asks what the functions an importer actually references require,
    rather than what the imported module as a whole requires. *)
let fn_transitive_capability_closures_tbl (env : env)
  : (string, string list) Hashtbl.t =
  let current : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  Hashtbl.iter (fun k v -> Hashtbl.replace current k v) env.own_cap_closures;
  (* Resolve a reference name to a function key.

     Observed key shapes (verified against the existing cap-closure tests and
     [bin/main.ml]'s [own_caps_of_this_module]): a top-level function of the
     ENTRY module is keyed BARE ("public_reader") because [check_module_core]
     passes ~cap_qname_prefix:"" for it, mirroring TIR's unwrapping of the
     entry module; a nested [DMod]'s function is keyed by its dotted path
     relative to the entry ("Lib.Sub.f").

     Reference names arrive already DESUGARED: desugar's [qualify_module_refs]
     rewrites a bare intra-module reference inside a nested [DMod] to the
     dotted form ("Lib.touch"), and its [EField] arm flattens `A.B.c` into a
     single dotted [EVar] — while the entry module's own top-level bodies keep
     bare names. So both spellings occur, and both must resolve: try the
     owner-module-prefixed form first (bare reference from a nested module),
     then the raw name (an already-dotted reference, or an entry-level bare
     one). *)
  let resolve (owner : string) (r : string) : string option =
    let qualified =
      match String.rindex_opt owner '.' with
      | Some i -> String.sub owner 0 i ^ "." ^ r
      | None -> r
    in
    if Hashtbl.mem current qualified then Some qualified
    else if Hashtbl.mem current r then Some r
    else None
  in
  let changed = ref true in
  while !changed do
    changed := false;
    Hashtbl.iter (fun fn_qname refs ->
        let own = Option.value ~default:[] (Hashtbl.find_opt current fn_qname) in
        let from_refs =
          List.concat_map (fun r ->
              match resolve fn_qname r with
              | None -> []
              | Some key -> Option.value ~default:[] (Hashtbl.find_opt current key))
            refs
        in
        (* [List.sort_uniq] BEFORE normalize is load-bearing, not tidiness:
           [Cap_lattice.normalize] drops caps SUBSUMED by another, but its
           filter skips the [other <> c] case, so it does NOT drop an exact
           DUPLICATE. Without the dedup, [own @ from_refs] grows by one copy of
           each already-held cap on every sweep, the value never compares equal
           to the previous one, and the fixpoint spins forever. Observed as a
           hang on the very first test case before this was added. *)
        let merged =
          March_caps.Cap_lattice.normalize (List.sort_uniq compare (own @ from_refs))
        in
        if List.sort compare merged <> List.sort compare own then begin
          Hashtbl.replace current fn_qname merged;
          changed := true
        end)
      env.fn_refs
  done;
  current

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
(* ── Path-scoped capability checking ──────────────────────────────────

   Which builtins take a FILESYSTEM PATH, and at which argument.  Verified
   against the signature table: the read/write builtins take the path at
   argument 0, [file_rename] and [file_copy] take two paths, and
   [file_read_line] / [file_read_chunk] / [csv_next_row] take an INT HANDLE
   rather than a path — those need no check, because a handle cannot be
   obtained except through an opening builtin, which is checked.  That is what
   makes this sound without dataflow analysis. *)
let path_arg_builtins : (string * int list) list = [
  ("file_read", [0]); ("file_open", [0]); ("file_exists", [0]);
  ("file_stat", [0]); ("dir_list", [0]); ("dir_exists", [0]);
  ("file_write", [0]); ("file_append", [0]); ("file_delete", [0]);
  ("dir_mkdir", [0]); ("dir_mkdir_p", [0]); ("dir_rmdir", [0]);
  ("dir_rm_rf", [0]);
  (* Both arguments are paths. *)
  ("file_rename", [0; 1]); ("file_copy", [0; 1]);
]

(* Literal path arguments at capability-builtin call sites.
   Deliberately only LITERALS: a computed path is left to runtime enforcement
   rather than guessed at.  Reporting only definite violations matches the
   refinement checker's existing stance, and keeps this out of Z3's string
   theory, which refine_check.ml explicitly stays clear of. *)
let rec literal_path_uses (acc : (string * string * Ast.span) list)
    (e : Ast.expr) : (string * string * Ast.span) list =
  let acc =
    match e with
    | Ast.EApp (Ast.EVar fn, args, _) ->
      (match List.assoc_opt fn.Ast.txt path_arg_builtins with
       | None -> acc
       | Some idxs ->
         List.fold_left (fun a i ->
             match List.nth_opt args i with
             | Some (Ast.ELit (Ast.LitString path, sp)) ->
               (fn.Ast.txt, path, sp) :: a
             | _ -> a)
           acc idxs)
    | _ -> acc
  in
  match e with
  | Ast.EApp (f, args, _) ->
    List.fold_left literal_path_uses (literal_path_uses acc f) args
  | Ast.ELet (b, _) -> literal_path_uses acc b.Ast.bind_expr
  | Ast.EBlock (es, _) -> List.fold_left literal_path_uses acc es
  | Ast.EMatch (sc, brs, _) ->
    let acc = literal_path_uses acc sc in
    List.fold_left (fun a br -> literal_path_uses a br.Ast.branch_body) acc brs
  | Ast.EIf (c, t, f, _) ->
    literal_path_uses (literal_path_uses (literal_path_uses acc c) t) f
  | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) ->
    literal_path_uses (literal_path_uses acc x) y
  | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
    List.fold_left literal_path_uses acc es
  | Ast.ERecord (fs, _) ->
    List.fold_left (fun a (_, e) -> literal_path_uses a e) acc fs
  | Ast.ERecordUpdate (e, fs, _) ->
    List.fold_left (fun a (_, e) -> literal_path_uses a e) (literal_path_uses acc e) fs
  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
  | Ast.ESpawn (e, _) | Ast.EAssert (e, _) -> literal_path_uses acc e
  | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> literal_path_uses acc b
  | _ -> acc

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
    | Ast.DNeeds (caps, _) -> List.map (fun (p, _) -> cap_path_of_names p) caps
    | _ -> []
  ) decls in
  (* See [locally_declared_names_of] for why a raw call-name match against
     [builtin_cap_table] must first check for module-local shadowing. *)
  let locally_declared_names = locally_declared_names_of decls in
  let cap_of_builtin_call (name : string) : string option =
    if Hashtbl.mem locally_declared_names name then None
    else List.assoc_opt name builtin_cap_table
  in
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
  (* ── Demand-driven import propagation ──────────────────────────────────
     What an `import M` / `use M` costs this module.

     It used to be M's WHOLE capability set: importing [List] to call [map]
     inherited [pmap]'s [IO.Spawn].  Now it is the union of the transitive
     capability closures of the functions this module actually REFERENCES from
     M — [record_use] recorded exactly those into [ie_used_names] as it
     resolved each [EVar].  This can only ever require LESS than before, so no
     module that compiles today can start failing.

     [trans_closures] is [lazy] because it runs a fixpoint over the whole
     program's reference graph: this must not be paid by the (many) modules
     that import nothing, and both consumers below share the one computation.

     FALLBACK: a referenced name with no closure entry falls back to
     [env.module_caps], i.e. exactly the pre-demand-driven module-granular
     answer, because reading "no entry" as "no capabilities" would silently
     drop enforcement.  Since 2026-08-06 [record_fn_caps] covers every
     declaration form that can hold an expression (see
     [fn_transitive_capability_closures_tbl]), so this branch is a DEFENSIVE
     backstop for a key-shape miss rather than a routinely exercised path —
     measured: with it instrumented it fires zero times across the whole
     run_compiler suite and across a --check sweep of stdlib/*.march,
     test/native/*.march and bench/*.march.  Do not read its survival as
     coverage for an uncovered declaration form; add the form instead.  The
     separate [[] -> mod_caps] early exit above still carries the live cases:
     an import that produced no tracker entry, and a cyclic module group whose
     importee has not been analyzed yet.

     The fallback is deliberately scoped to names in [ie_used_names] — names
     the index proved came from THIS import.  Applying it to every unresolved
     reference would catch every local and parameter and degenerate straight
     back to module granularity. *)
  let trans_closures = lazy (fn_transitive_capability_closures_tbl env) in
  let module_level_caps (imported : string) : string list =
    match List.assoc_opt imported env.module_caps with
    | None -> [] | Some req_caps -> req_caps
  in
  let import_required_caps (ud : Ast.use_decl) (sp : Ast.span) (imported : string)
    : string list =
    match module_level_caps imported with
    | [] ->
      (* The import required nothing before, so it requires nothing now.  The
         early exit is also what keeps this affordable: the fixpoint is never
         forced for the overwhelming majority of imports, whose target declares
         no [needs] at all. *)
      []
    | mod_caps ->
      (* [UseSingle]/[UseAll]/[UseExcept] file one entry at the decl's own span;
         [UseNames] files one per listed name, at that name's span. *)
      let spans = sp :: (match ud.Ast.use_sel with
        | Ast.UseNames names -> List.map (fun (n : Ast.name) -> n.Ast.span) names
        | Ast.UseAll | Ast.UseSingle | Ast.UseExcept _ -> []) in
      (match List.filter (fun ie -> List.mem ie.ie_span spans) !(env.import_tracker) with
       | [] -> mod_caps   (* no tracker entry to read demand from: as before *)
       | entries ->
         let used =
           List.concat_map
             (fun ie -> Hashtbl.fold (fun k () acc -> k :: acc) ie.ie_used_names [])
             entries
         in
         let tbl = Lazy.force trans_closures in
         let caps_of_name (n : string) : string list =
           (* A recorded name is either bare ("pure_double", rebound by
              `import M`) or fully dotted ("M.pure_double" / "Sub.pure_double",
              matched by the prefix index).  Closure keys are "Mod.fn" for a
              nested module and BARE for the entry module's own top-level
              functions, so try, in order: the imported module's own
              qualification of a bare name; the name verbatim; and — for
              `use A.B` re-exporting under the short "B.f" spelling — the
              imported path plus the name's tail. *)
           let candidates =
             (imported ^ "." ^ n) :: n ::
             (match String.index_opt n '.' with
              | Some i ->
                [ imported ^ "." ^ String.sub n (i + 1) (String.length n - i - 1) ]
              | None -> [])
           in
           match List.find_map (fun k -> Hashtbl.find_opt tbl k) candidates with
           | Some caps -> caps
           | None -> mod_caps
         in
         let demanded = List.concat_map caps_of_name used in
         (* FILTER [mod_caps] rather than return [demanded] directly.  The
            result is a SUBSET of what this import required before, by
            construction — which is the whole safety property: this change may
            only ever require less, so nothing that compiles today can start
            failing.  Returning [demanded] itself would not have that property:
            a referenced function's closure can contain a capability the
            imported module never declared (Check 1b only WARNS about a
            capability builtin called directly in a body), and propagating that
            outward would be a brand-new error on code that compiles today.

            A declared cap is kept when some referenced function demands
            something related to it in either direction: [cap_subsumes c d] for
            an umbrella declaration ([needs IO] kept by a demanded IO.Console),
            [cap_subsumes d c] for the exact/narrower case. *)
         List.filter
           (fun c -> List.exists
               (fun d -> cap_subsumes c d || cap_subsumes d c) demanded)
           mod_caps)
  in
  let module_wide_caps : string list =
    (* Caps that apply to every function in this module regardless of which
       function's own signature/body/extern-block produced them: declared
       [needs] (in-scope for the whole module body) and caps propagated in
       from imported modules (Check 4). *)
    let propagated = List.concat_map (function
      | Ast.DUse (ud, sp) ->
        let imported = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
        import_required_caps ud sp imported
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
  (* Reference edges for the per-function TRANSITIVE capability closure
     ([fn_transitive_capability_closures]). Purely additive bookkeeping — no
     Check 1/1b/1c/2/3/4/5/6 diagnostic reads [env.fn_refs].

     [free_vars_expr] rather than [March_ast.Calls]: the call-walker collects
     only [EApp] callees, so a function passed as a VALUE — [apply(xs, noisy)]
     — would contribute no edge and its capabilities would silently vanish
     from the caller's closure. That is the fail-open direction. The
     free-variable walk collects every [EVar], bare and dotted, and respects
     shadowing, so an inner binding that happens to share a top-level
     function's name does not manufacture a spurious edge.

     Each body is paired with the names ITS OWN PARAMETERS bind, and those seed
     [free_vars_expr]'s [bound] list. This is load-bearing, not hygiene:
     [free_vars_expr] binds lambda / [let] / match-arm / [let?] binders
     internally, but it has no visibility into a clause's parameter list, so
     passing [] would let

       pfn helper(p) do file_read(p) end
       fn wrap(helper) do helper(1) end

     record an edge from [wrap] to the SIBLING [helper] — [wrap] would inherit
     [IO.FileRead] while being pure. That is a false positive, which this
     subsystem treats as its cardinal sin. (Note [dependency_order_dfn_run]'s
     [deps_of] does pass []; there an over-approximation only perturbs
     dependency ORDERING, which is harmless. Here it fabricates a capability.)

     Merged with any prior entry, matching [record_fn_caps]'s
     accumulate-across-call-sites behavior. *)
  let record_fn_refs (fn_qname : string) (bodies : (string list * Ast.expr) list) =
    let refs = List.concat_map (fun (bound, e) -> free_vars_expr bound e) bodies in
    let prior = Option.value ~default:[] (Hashtbl.find_opt env.fn_refs fn_qname) in
    Hashtbl.replace env.fn_refs fn_qname (List.sort_uniq compare (refs @ prior))
  in
  (* Names bound by a clause's parameter list. [FPPat] goes through
     [free_vars_pattern] so a destructuring head ([fn f((a, b))]) binds its
     components too, not just a bare [PatVar]. *)
  let fn_clause_param_names (c : Ast.fn_clause) : string list =
    List.concat_map (function
      | Ast.FPNamed p | Ast.FPDefault (p, _) -> [ p.Ast.param_name.txt ]
      | Ast.FPPat pat -> free_vars_pattern pat)
      c.Ast.fc_params
  in
  (* ── Coverage-gap closure, 2026-08-06 ────────────────────────────────
     [record_fn_caps]/[record_fn_refs] used to fire for [DFn]s, actor handlers
     and [DExtern]s only.  Module-level [DLet] bodies, interface default-method
     bodies, impl-method bodies and default-argument expressions got NO
     own(...) entry, so an edge pointing at one contributed nothing and the
     transitive closure of anything that REACHED one came back silently
     truncated — dropping a capability Check 4 required before demand-driven
     propagation landed (see
     specs/progress/2026-08-06-record-fn-caps-misses-dlet-and-methods.md).

     Unlike the [DFn] scan, none of this feeds the Check 1b/Check 2
     DIAGNOSTIC lists ([body_cap_uses] / [used_caps]): it only populates the
     closure tables.  Keeping the diagnostic surface byte-identical is
     deliberate — this change exists to restore ENFORCEMENT that the closure
     lost, not to start warning about forms that never warned. *)
  let builtin_caps_of_expr (e : Ast.expr) : string list =
    List.filter_map
      (fun (call_name, _) -> cap_of_builtin_call call_name)
      (March_ast.Calls.names_and_name_spans e)
  in
  let default_param_exprs (c : Ast.fn_clause) : Ast.expr list =
    List.filter_map (function Ast.FPDefault (_, e) -> Some e | _ -> None)
      c.Ast.fc_params
  in
  (* Record one non-[DFn] expression owner: its own builtin-implied caps and
     its reference edges, with [bound] seeding [free_vars_expr] exactly the way
     [record_fn_refs] does for a clause's parameters. *)
  let record_expr_owner (qname : string) (bound : string list)
      (es : Ast.expr list) =
    record_fn_caps qname (List.concat_map builtin_caps_of_expr es);
    record_fn_refs qname (List.map (fun e -> (bound, e)) es)
  in
  (* An [impl]'s target type, keyed the way lib/tir/lower.ml keys it when it
     builds the [Iface$Ty.method] mangled symbol — same four cases, same
     arity-keyed tuple spelling.

     NOT a full mirror, deliberately: lower.ml additionally applies a
     COLLISION-CONDITIONAL module qualification (lower.ml:1299-1301) when a
     short type name is declared more than once in the program, so two impls of
     a general interface for same-short-named types get distinct symbols. This
     key does not reproduce that, so two such impls in ONE module would share a
     cap-closure key and their capabilities would merge. Harmless today —
     nothing cross-references the TIR symbol from here, and the merge is a
     union within a single module's own impls — but it is the one place where
     these two manglings can disagree. *)
  let impl_ty_key (t : Ast.ty) : string =
    match t with
    | Ast.TyCon (n, _) -> n.Ast.txt
    | Ast.TyTuple tys -> Printf.sprintf "$Tuple%d" (List.length tys)
    | Ast.TyRecord _ -> "$Record"
    | _ -> "$Unknown"
  in
  (* [DFn]s declared directly in this module — the guard that keeps the impl
     DISPATCH node below from ever claiming a plain function's key. *)
  let module_fn_names =
    List.filter_map (function
        | Ast.DFn (def, _) -> Some def.Ast.fn_name.Ast.txt
        | _ -> None)
      decls
  in
  (* Append a single reference edge without a body walk. Used only for the
     impl dispatch node, which owns no expression of its own. *)
  let record_dispatch_edge (dispatch_qname : string) (target : string) =
    let prior =
      Option.value ~default:[] (Hashtbl.find_opt env.fn_refs dispatch_qname)
    in
    Hashtbl.replace env.fn_refs dispatch_qname
      (List.sort_uniq compare (target :: prior))
  in
  (* Desugar's [expand_defaults_decl] rewrites [fn f(x \\ d)] into arity-
     mangled [f$0]/[f$1] declarations with [d] moved into [f$0]'s BODY, and it
     runs before the typechecker (bin/main.ml, and [parse_and_desugar] in the
     tests).  It does NOT rewrite call sites — those still say [f] — and it
     emits no dispatcher [DFn], so the base name had no closure entry at all
     and every caller's closure was truncated.  Recording each variant's caps
     and edges under the base name too is what makes a reference to [f]
     resolve.  A user cannot write ['$'] in an identifier, so this can only
     ever fire on a desugar-generated name. *)
  let arity_mangled_base (n : string) : string option =
    match String.rindex_opt n '$' with
    | None -> None
    | Some i ->
      let suffix = String.sub n (i + 1) (String.length n - i - 1) in
      if i > 0 && suffix <> ""
         && String.for_all (fun c -> c >= '0' && c <= '9') suffix
      then Some (String.sub n 0 i)
      else None
  in
  List.iter (fun (d : Ast.decl) ->
      match d with
      (* A module-level binding is an ordinary value name: key it exactly the
         way a [DFn] of that name would be keyed, so a reference to it
         resolves.  A destructuring binding attributes the body to EVERY name
         it binds — any of them can be the route a caller takes. *)
      | Ast.DLet (_, b, _) ->
        List.iter
          (fun n -> record_expr_owner (cap_qname n) [] [ b.Ast.bind_expr ])
          (free_vars_pattern b.Ast.bind_pat)
      (* An interface DEFAULT body is keyed by a mangled name for exactly the
         reason an impl method is, and the bare name is only a dispatch edge.

         The first version of this change wrote the default body's caps
         DIRECTLY onto [cap_qname md_name] with no mangling and no guard, on
         the assumption that a module could not declare both an interface
         method and a plain [fn] of that name.  That assumption is false —

           mod Inner do
             interface Greeter(a) do
               fn greet : a -> Unit
               fn greet_loud : a -> Unit do fn (x) -> print("loud") end
             end
             fn greet_loud(n : Int) : Int do n + 1 end
           end

         typechecks with exit 0, and [record_fn_caps] MERGES, so the pure
         [greet_loud] silently absorbed [IO.Console].  That is a false
         positive, and it was observable on the hot-deploy manifest, which
         reads [fn_own_capability_closures] unfiltered — no Check-4
         [mod_caps] filter stands between it and a deploy capability gate.
         Pinned by [test_interface_default_does_not_capture_a_same_named_fn]. *)
      | Ast.DInterface (idef, _) ->
        List.iter (fun (m : Ast.method_decl) ->
            match m.Ast.md_default with
            | None -> ()
            | Some e ->
              let mangled =
                cap_qname
                  (idef.Ast.iface_name.Ast.txt ^ "$default." ^ m.Ast.md_name.Ast.txt)
              in
              record_expr_owner mangled [] [ e ];
              if not (List.mem m.Ast.md_name.Ast.txt module_fn_names) then
                record_dispatch_edge (cap_qname m.Ast.md_name.Ast.txt) mangled)
          idef.Ast.iface_methods
      (* An impl method is keyed by TIR's [Iface$Ty.method] mangling.  This is
         collision-free in both directions that matter: an ordinary qualified
         name never contains ['$'] (see [Tir_names.is_iface_mangled]), so a
         [DFn] of the same short name can never share the key and have its
         capabilities silently merged; and two impls of the same method for
         DIFFERENT types get distinct keys, so a caller cannot inherit a
         sibling impl's capabilities.

         A reference site says the BARE method name, though, so the mangled key
         alone would leave every caller truncated.  The bare name therefore
         becomes a DISPATCH node whose only content is an edge to each impl —
         the union over impls, which is the sound reading of a name whose
         target is chosen by type.  It is emitted only when this module
         declares no [DFn] of that name, so the dispatch node can never absorb
         a plain function's identity. *)
      | Ast.DImpl (idef, _) ->
        let ty_key = impl_ty_key idef.Ast.impl_ty in
        List.iter (fun ((mn : Ast.name), (def : Ast.fn_def)) ->
            let mangled =
              cap_qname
                (idef.Ast.impl_iface.Ast.txt ^ "$" ^ ty_key ^ "." ^ mn.Ast.txt)
            in
            List.iter (fun (c : Ast.fn_clause) ->
                record_expr_owner mangled (fn_clause_param_names c)
                  (c.Ast.fc_body :: Option.to_list c.Ast.fc_guard
                   @ default_param_exprs c))
              def.Ast.fn_clauses;
            if not (List.mem mn.Ast.txt module_fn_names) then
              record_dispatch_edge (cap_qname mn.Ast.txt) mangled)
          idef.Ast.impl_methods
      | _ -> ())
    decls;
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
      (* Annotations INSIDE the body are uses too, and were invisible here
         until 2026-08-05 — see [cap_annots_in_expr].

         Deliberately NOT passed to [record_fn_caps]: signature caps propagate
         to callers because they are the function's interface, while a local
         annotation is not, and folding it into the propagated closure would
         widen every caller's ceiling on the strength of a binding they cannot
         see.  So a body annotation is reported against this module's [needs]
         and stops there. *)
      let body_annot_caps =
        List.concat_map (fun (c : Ast.fn_clause) -> cap_annots_in_expr [] c.Ast.fc_body)
          def.fn_clauses
      in
      List.map (fun cap -> (cap, sp)) sig_caps @ body_annot_caps
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
              cap_of_builtin_call call_name
            ) (March_ast.Calls.names_and_name_spans h.Ast.ah_body) in
          record_fn_caps fn_qname body_caps;
          record_fn_refs fn_qname
            [ (List.map (fun (p : Ast.param) -> p.param_name.txt) h.Ast.ah_params,
               h.Ast.ah_body) ]
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

    (* A capability named in a TYPE DECLARATION — a record field, a variant
       constructor argument, or an alias right-hand side — is a use of that
       capability.  Declaring the field does not let the module OBTAIN the
       capability, but it lets it hold one and pass one, which is exactly what
       the ceiling exists to make visible, and it is already how the identical
       capability is treated in a function signature.

       These arms were covered by the `| _ -> []` wildcard that used to end
       this match, so `type Handle = { tok : Cap(IO.FileWrite) }` under
       `needs IO.Console` typechecked clean with `--cap-strict`.  See
       reject/t148-t150. *)
    | Ast.DType (_, _, _, td, sp)
    | Ast.DAlwaysLinearType (_, _, _, td, sp) ->
      List.map (fun cap -> (cap, sp)) (March_caps.Cap_surface_ty.caps_in_type_def td)

    (* ── Everything below names no capability position ──────────────────
       Enumerated rather than wildcarded, deliberately.  Five separate bugs in
       this codebase have come from a capability walk ending in `| _ -> ()`
       that was inert until a declaration form grew a type position; the point
       of naming every constructor is that adding a 25th one breaks this build
       instead of silently opening a hole.  Do NOT collapse these back into a
       wildcard. *)
    | Ast.DMod _ ->
      (* Nested modules are checked by their own [check_module_needs] pass,
         which attributes diagnostics to the INNER module — verified: a `Cap`
         in a nested module's signature reports against the inner name.
         Recursing here would double-report against the outer module and
         against the wrong `needs`. *)
      []
    | Ast.DLet _ ->
      (* A top-level binding's annotation is a type position, but the value
         restriction means a top-level cap binding cannot be produced without
         a call whose signature is already walked above. Left uncovered
         deliberately; revisit if a witness appears. *)
      []
    (* An INTERFACE method signature is a signature, and Check 1 treats every
       other signature — plain [fn], actor handler, [extern] — as a use.  A
       default method body is a body, and its annotations are uses too.

       These were enumerated under "names no capability position" when this
       match was made exhaustive on 2026-08-05.  That was an explicit decision
       and it was wrong; found by the R8 audit (reject/t156).  The enumeration
       is why it was a reviewable mistake rather than a silent hole. *)
    | Ast.DInterface (idef, sp) ->
      let sig_caps =
        List.concat_map (fun (md : Ast.method_decl) -> cap_paths_in_surface_ty md.md_ty)
          idef.iface_methods
      in
      let body_caps =
        List.concat_map (fun (md : Ast.method_decl) ->
            match md.md_default with
            | None -> []
            | Some body -> cap_annots_in_expr [] body)
          idef.iface_methods
      in
      List.map (fun cap -> (cap, sp)) sig_caps @ body_caps

    (* An IMPL method is a function: its signature and its body annotations are
       uses, exactly as a top-level [DFn]'s are.  Measured before this arm
       existed: the IDENTICAL annotation errored in a plain [fn] body and
       produced NOTHING in an [impl] method body — impl bodies were darker than
       ordinary functions, which is backwards, since an [impl] is where a
       dependency's capability use is least visible to a reader
       (reject/t157). *)
    | Ast.DImpl (idef, sp) ->
      let of_fn (fd : Ast.fn_def) =
        let param_tys =
          List.filter_map (function
              | Ast.FPNamed { param_ty = Some t; _ } -> Some t
              | _ -> None)
            (List.concat_map (fun c -> c.Ast.fc_params) fd.fn_clauses)
        in
        let sig_caps =
          List.concat_map cap_paths_in_surface_ty (param_tys @ Option.to_list fd.fn_ret_ty)
        in
        let body_caps =
          List.concat_map (fun (c : Ast.fn_clause) -> cap_annots_in_expr [] c.Ast.fc_body)
            fd.fn_clauses
        in
        List.map (fun cap -> (cap, sp)) sig_caps @ body_caps
      in
      (* [impl_ty] itself can name a capability: `impl Grantor(Cap(IO))`. *)
      List.map (fun cap -> (cap, sp)) (cap_paths_in_surface_ty idef.impl_ty)
      @ List.concat_map (fun (_, fd) -> of_fn fd) idef.impl_methods

    | Ast.DProtocol _ | Ast.DSig _
    | Ast.DUse _ | Ast.DAlias _ | Ast.DNeeds _ | Ast.DProofCap _
    | Ast.DOpts _ | Ast.DTransitions _ | Ast.DApp _ | Ast.DDeriving _
    | Ast.DSatisfy _ | Ast.DTest _ | Ast.DDescribe _ | Ast.DSetup _
    | Ast.DSetupAll _ -> []
  ) decls in
  (* Body-scan: collect builtin calls that imply a cap need.
     Deduplicated to one warning per cap (first call-site span). *)
  (* ── Path-scope violations ──────────────────────────────────────────
     A literal path outside every scope declared for its capability is a
     DEFINITE violation and an error.  Three conditions keep this quiet
     otherwise, each deliberate:
       - no declaration for the capability at all -> silent; the existing
         needs checks already cover an undeclared capability, and reporting
         it twice would be noise;
       - at least one UNSCOPED declaration -> silent; unscoped means any path,
         so nothing is out of scope;
       - a computed path -> not collected at all, so nothing to say. *)
  List.iter (fun (d : Ast.decl) ->
      let bodies = match d with
        | Ast.DFn (def, _) -> List.map (fun c -> c.Ast.fc_body) def.fn_clauses
        | Ast.DLet (_, b, _) -> [ b.Ast.bind_expr ]
        | _ -> []
      in
      List.iter (fun body ->
          List.iter (fun (builtin, path, sp) ->
              match cap_of_builtin_call builtin with
              | None -> ()
              | Some cap ->
                (* Scopes declared for this capability, or for anything that
                   subsumes it: needs IO.FileSystem("/srv") also scopes
                   IO.FileRead. *)
                let relevant =
                  List.filter (fun (declared, _) -> cap_subsumes declared cap)
                    env.mod_need_scopes
                in
                if relevant <> [] then begin
                  let unscoped = List.exists (fun (_, sc) -> sc = None) relevant in
                  let permitted =
                    List.exists (fun (_, sc) -> match sc with
                        | None -> true
                        | Some scope -> March_caps.Cap_scope.within ~scope path)
                      relevant
                  in
                  if (not unscoped) && not permitted then begin
                    let scopes =
                      List.filter_map (fun (_, sc) -> sc) relevant
                      |> List.sort_uniq String.compare
                    in
                    Err.error env.errors ~span:sp
                      (Printf.sprintf
                         "`%s` is scoped to %s, but this reads `%s`, which is \
                          outside it.\n\
                          hint: widen the scope in `needs`, or use a path \
                          within it."
                         cap
                         (String.concat " and "
                            (List.map (fun s -> "`" ^ s ^ "`") scopes))
                         path)
                  end
                end)
            (literal_path_uses [] body))
        bodies)
    decls;

  let body_cap_uses : (string * Ast.span) list =
    let all = List.concat_map (function
      | Ast.DFn (def, _) ->
        let per_clause = List.map (fun clause ->
          List.filter_map (fun (call_name, call_span) ->
            match cap_of_builtin_call call_name with
            | Some cap_name -> Some (cap_name, call_span)
            | None -> None
          ) (March_ast.Calls.names_and_name_spans clause.Ast.fc_body)
        ) def.fn_clauses in
        let qname = cap_qname def.fn_name.txt in
        (* Default-argument expressions count as this function's own: the
           default is evaluated at every call site that omits the parameter.
           This arm only sees them when the typechecker runs on an UNdesugared
           module (the LSP's analysis route); the production pipeline desugars
           first, and there the default has already moved into an arity-mangled
           [f$N] body, which the base-name alias below re-attaches to [f].
           Both routes are covered so neither can silently truncate. *)
        let own_caps =
          List.concat_map (List.map fst) per_clause
          @ List.concat_map
              (fun (c : Ast.fn_clause) ->
                 List.concat_map builtin_caps_of_expr (default_param_exprs c))
              def.fn_clauses
        in
        (* Guards are part of the function too: a guard calling an impure
           helper is as much a reference as the body is. *)
        let own_refs =
          List.concat_map (fun (c : Ast.fn_clause) ->
              let bound = fn_clause_param_names c in
              List.map (fun e -> (bound, e))
                (c.Ast.fc_body :: Option.to_list c.Ast.fc_guard
                 @ default_param_exprs c))
            def.fn_clauses
        in
        record_fn_caps qname own_caps;
        record_fn_refs qname own_refs;
        (match arity_mangled_base def.fn_name.txt with
         | None -> ()
         | Some base ->
           let base_qname = cap_qname base in
           record_fn_caps base_qname own_caps;
           record_fn_refs base_qname own_refs);
        List.concat per_clause
      | Ast.DLet (_vis, b, _) ->
        List.filter_map (fun (call_name, call_span) ->
          match cap_of_builtin_call call_name with
          | Some cap_name -> Some (cap_name, call_span)
          | None -> None
        ) (March_ast.Calls.names_and_name_spans b.Ast.bind_expr)
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
              match cap_of_builtin_call call_name with
              | Some cap_name -> Some (cap_name, call_span)
              | None -> None
            ) (March_ast.Calls.names_and_name_spans h.Ast.ah_body)
          ) actor.actor_handlers
      | _ -> []
    ) decls in
    (* Drop capability uses that belong to the standard library rather than to
       this module.  Without this, prelude's own calls (it is unwrapped into
       global scope, so its decls ride in the entry module's list AHEAD of the
       user's) win the dedup below and carry a stdlib span, which the driver
       then filters out — generating the warning and discarding it.  See
       [stdlib_source_files]. *)
    let all = List.filter (fun (_, sp) -> not (span_is_stdlib sp)) all in
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
  (* Check 1b: a body-scanned builtin call implying an undeclared capability.
     ERROR since 2026-08-06 (was warning-only).  `needs` was a hard floor for
     capability-PASSING code and merely advisory for a direct builtin call —
     which is the code most likely to abuse it.  Per-function transitive
     closure (#209) made the ceiling precise enough to enforce without
     collapsing every module to `needs IO`.

     Scope, stated because it is easy to over-read: this catches a DIRECT
     builtin call in a module body.  A stdlib-MEDIATED call (`File.read`
     rather than `file_read`) is invisible here and is caught by
     --cap-strict's ceiling over emitted TIR instead.  Check 1c below
     (extern -> IO.Foreign) is deliberately NOT flipped. *)
  List.iter (fun (cap_path, sp) ->
    let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
    let self_declared = match List.assoc_opt cap_path env.proof_caps with
      | Some dm -> dm = mod_name.txt
      | None -> false
    in
    if not covered && not self_declared then
      Err.error_with_fix env.errors ~span:sp
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
  (* The capabilities this module's OWN functions reach TRANSITIVELY —
     including through a stdlib wrapper, which none of the source-level lists
     below can see (the stdlib deliberately declares no `needs`, so
     [env.module_caps] never carries its uses either).  Without this, the
     ceiling and Check 2 contradicted each other on the same line: a
     stdlib-mediated `pmap` REQUIRES `needs IO.Spawn` at the ceiling, and
     Check 2 then said "no function requires Cap(IO.Spawn) — help: remove",
     whose autofix re-breaks the build.  First hit minutes after the ceiling
     became the default (golden g43); filed as
     specs/todos/2026-08-08-unused-cap-warning-contradicts-ceiling.md.

     Same closure table Check 4 uses for imports, and it is [lazy] for the
     same reason: only a module that both declares a `needs` and fails every
     cheaper test below pays for the fixpoint.  Keyed by this module's
     DECLARED function names ([cap_qname], skipping stdlib-span decls) — not
     by key shape: at the entry module the prefix is empty, so prelude
     functions are keyed bare exactly like the user's own, and selecting by
     shape would fold the prelude's IO.Console into every module (the same
     trap [own_caps_of_this_module] documents). *)
  let own_transitive_caps : string list Lazy.t = lazy (
    let tbl = Lazy.force trans_closures in
    List.concat_map (fun (d : Ast.decl) ->
        match d with
        | Ast.DFn (fd, sp) when not (span_is_stdlib sp) ->
          (match Hashtbl.find_opt tbl (cap_qname fd.Ast.fn_name.txt) with
           | Some caps -> caps | None -> [])
        | _ -> [])
      decls
    |> List.sort_uniq String.compare)
  in
  List.iter (fun need ->
    let need_sp =
      let rec find_span = function
        | [] -> mod_name.span
        | Ast.DNeeds (caps, s) :: _
          when List.exists (fun (names, _) -> cap_path_of_names names = need) caps -> s
        | _ :: rest -> find_span rest
      in
      find_span decls
    in
    let used = List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) used_caps
              || List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) body_cap_uses
              || List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) extern_cap_uses
              || List.exists (fun (_, req_caps) ->
                   List.exists (fun req_cap -> cap_subsumes need req_cap) req_caps
                 ) env.module_caps
              || List.exists (fun cap_path -> cap_subsumes need cap_path)
                   (Lazy.force own_transitive_caps) in
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
      (* Demand-driven (see [import_required_caps]): only what the functions
         this module actually references from [imported] require, not the
         imported module's whole set.  The per-cap [covered] loop, the
         diagnostic text and its span are unchanged — only the SET of required
         capabilities narrowed. *)
      (match (match import_required_caps ud sp imported with
              | [] -> None | caps -> Some caps) with
       | None -> ()
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

(** [cap_in_solved_ty t] returns the RENDERED capability type — ["Cap(IO)"],
    ["ActorCap(_)"] — of the first capability found anywhere in the SOLVED
    type [t], or [None].  Callers print it verbatim; it is a whole type, not a
    bare path, because two constructors can appear here.

    Companion to [Cap_surface_ty.caps_in_ty], which walks the surface syntax a
    programmer wrote.  This one walks the internal, post-unification [ty] and
    so must [repr] through every node: a capability that arrives by
    unification rather than by annotation is precisely the case Check A exists
    to catch, and it is invisible without the deref.

    Exhaustive over [ty]'s constructors with no wildcard arm, for the reason
    given at the top of [Cap_surface_ty]. *)
let rec cap_in_solved_ty (t : ty) : string option =
  let first = List.fold_left
      (fun acc x -> match acc with Some _ -> acc | None -> cap_in_solved_ty x) None in
  match repr t with
  (* [ActorCap] is here as well as [Cap] (2026-08-06).  Forging a
     [VCap (pid, epoch)] out of JSON fabricates a live, send-capable reference
     to an ARBITRARY actor at an arbitrary epoch — the same class of hole as
     forging [Cap(IO)], and not covered by the IO lattice. *)
  | TCon (("Cap" | "ActorCap") as con, [inner]) ->
    (* Render the argument for the diagnostic.  An unsolved or structured
       argument renders as `_`: the position is still a capability position
       and still rejected — an un-pinned capability is not a safe capability —
       we simply cannot name it. *)
    Some (con ^ "(" ^ (match repr inner with TCon (p, []) -> p | _ -> "_") ^ ")")
  | TCon (_, args) -> first args
  | TArrow (a, b) -> first [a; b]
  | TTuple ts -> first ts
  | TRecord flds -> first (List.map snd flds)
  | TLin (_, t) -> cap_in_solved_ty t
  | TNatOp (_, a, b) -> first [a; b]
  | TRefine (base, _, _) -> cap_in_solved_ty base
  | TVar _ -> None      (* unsolved: nothing to name, nothing to report *)
  | TNat _ -> None      (* type-level natural *)
  | TChan _ -> None     (* session_ty carries no capability *)
  | TError -> None      (* already-reported error sentinel; stay quiet *)

(** R4a: attenuation must move DOWN the lattice, or stay level.

    This is what stops [cap_narrow] widening now that its argument type is
    [Cap(a)] rather than [Cap(IO)].  Before R4a the argument type did the work
    through unification and there was nothing to bypass; this sweep is weaker
    in kind, so its coverage is the whole guarantee.

    Deferred, not eager, for the same reason as every other capability sweep
    here: the result var is pinned by LATER unification (reject/t155).

    Enforced only when BOTH sides resolve to concrete IO-lattice capabilities:

    - A PROOF cap on either side is left alone.  Proof capabilities are not in
      the IO lattice, and they have their own discipline ([mint_cap]'s gate and
      Check 6).  [cap_narrow(root) : Cap(Db.Migrated)] typechecks today and is
      governed by Check 6 on the way out; making subsumption reject it here
      would silently change proof-cap semantics under cover of an IO change.
    - An UNPINNED side is silent.  A [cap_narrow] whose result never gets
      pinned to a concrete capability is a result never USED as one, so no
      authority is exercised and there is nothing to widen into.  (I proposed
      failing closed here and was wrong: the R3 argument for silence on an
      unresolved [from_json] result applies unchanged, and failing closed would
      reject ordinary code that narrows into a polymorphic position.) *)
let check_cap_narrow_sites (env : env) : unit =
  let concrete t = match repr t with
    | TCon ("Cap", [inner]) ->
      (match repr inner with TCon (p, []) -> Some p | _ -> None)
    | _ -> None
  in
  let is_proof p = List.mem_assoc p env.proof_caps in
  List.iter (fun (sp, f_ty) ->
      match repr f_ty with
      | TArrow (src_ty, dst_ty) ->
        (match concrete src_ty, concrete dst_ty with
         | Some src, Some dst
           when not (is_proof src) && not (is_proof dst)
             && not (March_caps.Cap_lattice.cap_subsumes src dst) ->
           Err.error env.errors ~span:sp
             (render_parts [
               MPCode ("Cap(" ^ src ^ ")");
               MPText " cannot be widened to "; MPCode ("Cap(" ^ dst ^ ")");
               MPText " — "; MPCode "cap_narrow";
               MPText " only attenuates, so the source capability must subsume the target.";
               MPBreak;
               MPText "help: "; MPCode ("Cap(" ^ dst ^ ")");
               MPText " is not below "; MPCode ("Cap(" ^ src ^ ")");
               MPText " in the capability lattice. Receive it from a caller that holds an ancestor of it." ])
         | _ -> ())
      | _ -> ()
    ) !(env.cap_narrow_sites)

(** Capability unforgeability (R3), the call-site half.  [to_json] is checked
    on its argument, the [from_json] family on its result; see
    [env.json_cap_sites] for why this runs deferred and why it inspects the
    instantiated arrow.

    An application whose relevant position never got pinned leaves a [TVar],
    which [cap_in_solved_ty] reports as [None] — silence.  That is deliberate:
    an unpinned result is a program that never used the decoded value as a
    capability, and rejecting it would break ordinary polymorphic JSON code.
    The forge only becomes a forge once something pins the type, and pinning
    is exactly what this sweep waits for. *)
let check_json_cap_sites (env : env) : unit =
  List.iter (fun (sp, f_ty, jname) ->
      let encoding = (jname = "to_json") in
      let inspected =
        match repr f_ty with
        | TArrow (a, b) -> if encoding then a else b
        (* Not an arrow: the builtin was referenced in a shape this recording
           did not anticipate.  Inspect the whole thing rather than skip it —
           silently ignoring an unrecognised shape is how a capability walk
           becomes a hole. *)
        | other -> other
      in
      match cap_in_solved_ty inspected with
      | None -> ()
      | Some cap_rendered ->
        let verb = if encoding then "serialized" else "deserialized" in
        Err.error env.errors ~span:sp
          (render_parts [
            (* Already rendered as `Cap(X)` or `ActorCap(X)` by
               [cap_in_solved_ty] — do not wrap it again. *)
            MPCode cap_rendered;
            MPText (" cannot be " ^ verb ^ " — a capability may only be received, never constructed.");
            MPBreak;
            MPText "hint: "; MPCode jname;
            MPText " places no constraint on the type it produces, so it would fabricate authority from data. Receive the capability as a parameter and pass it through instead." ])
    ) !(env.json_cap_sites)

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
  (* Sort by key: [Hashtbl.fold] iteration order is unspecified, so sorting
     gives downstream consumers (and any diagnostics derived from this list)
     a deterministic, run-to-run-stable order. *)
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) env.cap_closures []
  |> List.sort (fun (a, _) (b, _) -> compare a b)

(** [fn_own_capability_closures env] returns each function's OWN inferred
    IO-capability closure — [(fully_qualified_fn_name, normalized_cap_paths)]
    pairs — WITHOUT the module-wide [needs]/import-propagated merge that
    [fn_capability_closures] performs. Use this projection, not the merged
    one, for any "is this one function IO-free" question (e.g. the
    migrate_state check): the merged closure attributes a module's
    handler-level [needs] to every function in the module, including a pure
    migrate_state, which would falsely fail such a check. Order is
    unspecified (backed by a hashtable). *)
(* [declared_cap_scopes env] — every [needs] declaration's capability paired
    with its optional path scope, as written in source.

    Used by [--cap-sandbox] to emit a SCOPED sandbox profile: an unscoped
    grant becomes a blanket allow, a scoped one becomes a subpath allow.
    Declarations rather than inferred use, because the scope is a policy the
    author states — inference can tell you a module reads files, not which
    directory it is permitted to read. *)

let declared_cap_scopes (env : env) : (string * string option) list =
  List.sort_uniq compare env.mod_need_scopes

let fn_own_capability_closures (env : env) : (string * string list) list =
  (* Sort by key for the same determinism reason as [fn_capability_closures]. *)
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) env.own_cap_closures []
  |> List.sort (fun (a, _) (b, _) -> compare a b)

(** Sorted-by-key public view of [fn_transitive_capability_closures_tbl] (the
    sort is for determinism, like [fn_capability_closures]). *)
let fn_transitive_capability_closures (env : env) : (string * string list) list =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc)
    (fn_transitive_capability_closures_tbl env) []
  |> List.sort (fun (a, _) (b, _) -> compare a b)

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
       (* `loop do S end` is the µ-type `Rec X. S[X]` — the body's continuation
          IS the binder's back-reference, so the loop repeats indefinitely.
          (Substituting the post-loop continuation into the back-reference, as
          this arm used to do, produced a vacuous SRec with no SVar in it: one
          unrolled iteration.  Steps after a `loop` are unreachable and are
          rejected at protocol-declaration time.) *)
       let rec_var = proto_name ^ "_loop" in
       let inner = project_steps env ~proto_name ~multiparty inner_steps role (SVar rec_var) in
       (match inner with
        | SVar _ ->
          (* Role not involved in the loop at all — skip the binder entirely. *)
          rest_ty ()
        | _ -> SRec (rec_var, inner))
     | Ast.ProtoChoice (chooser, branches) ->
       (* Every branch rejoins the protocol tail, so each arm is projected with
          the steps that FOLLOW this choice block as its continuation — not the
          outer [cont], which at top level is just SEnd and silently truncates
          the protocol. *)
       let after_choice = rest_ty () in
       let branch_tys = List.map (fun (lbl, arm_steps) ->
           let arm_ty = project_steps env ~proto_name ~multiparty arm_steps role after_choice in
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
       end
     | Ast.ProtoStop _ ->
       (* `stop` exits the enclosing `loop` for every role: it projects to
          `SEnd` unconditionally, discarding both the surrounding [cont] and
          any steps that follow it (those are rejected as unreachable at
          protocol-declaration time — see [check_unreachable_after_loop]). *)
       SEnd)

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
    | Ast.ProtoStop _ :: rest -> roles_of_steps rest
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
       | Ast.ProtoStop _ :: rest -> gather_msgs acc rest
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
    | Ast.PatOr (ps, _) -> List.iter pat ps
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
  if has_dup then begin
    if Sys.getenv_opt "MARCH_DEBUG_ORDER" <> None then
      Printf.eprintf "[order] has_dup=true, skipping reorder of %d-mod run: %s\n%!"
        (List.length names) (String.concat "," names);
    run
  end
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
    (* [hard_deps] (unqualified bare ctor/type refs) are a correctness
       requirement: a bare name is only visible in [env] once the defining
       sibling's DMod has actually been processed by [check_decl] (its ctors
       are exported at that point — see the [new_ctors]/[qual_ctors] merge in
       the [DMod] case of [check_decl]).  There is no pass-1 placeholder for
       bare ctor names the way there is for qualified "Mod.fn" names, so
       violating a hard dependency is a hard failure ("I cannot find
       `Ctor`"), not just an imprecise type.
       [module_refs_in_decls] (qualified "Mod.fn"/"Mod.Ctor" refs) is only a
       precision nicety: those names ARE pre-bound as pass-1 placeholders
       regardless of order (see [prebind_mod_members]), so ordering by them
       just avoids callers unifying against a still-generalizing Mono
       placeholder — never required for resolution to succeed.
       Sibling modules commonly form real reference cycles through qualified
       calls (e.g. a facade module delegating to an internal one, which in
       turn bare-pattern-matches a type owned by the facade's module). A
       single DFS over the union of both kinds of edges lets a soft
       (qualified) cycle silently reorder a hard (bare) dependency the wrong
       way — whichever edge the traversal happens to reach the ancestor
       through "wins", independent of which one is actually load-bearing.
       So: compute the preferred order via the existing combined-edge DFS
       (unchanged — this is what every existing case, including cycle-free
       ones, already relies on for precision), then verify it against the
       hard edges ALONE.  If it already satisfies every hard edge (the
       common case: no hard/soft cycle exists) return it unchanged.  Only
       when a hard edge is actually violated do we recompute a corrected
       order via Kahn's algorithm restricted to hard edges, using the
       preferred order purely as a tie-break — this guarantees every hard
       dependency is satisfied while still respecting the soft-edge
       preference everywhere it doesn't conflict. *)
    let hard_deps_of decls = unqualified_module_deps ~type_owner ~ctor_owner decls in
    let visited : (string, unit) Hashtbl.t = Hashtbl.create 16 in
    let out = ref [] in
    let dbg = Sys.getenv_opt "MARCH_DEBUG_ORDER" <> None in
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
                    (hard_deps_of decls)))
          in
          if dbg then
            Printf.eprintf "[order] visit %s deps=[%s]\n%!" name
              (String.concat "," (StringSet.elements deps));
          StringSet.iter visit deps;
          out := dm :: !out
        | None -> ()
      end
    in
    List.iter (fun n -> visit n) names;
    let preferred = List.rev !out in
    (* Hard-dependency graph, restricted to sibling names, self-edges removed. *)
    let hard_graph : (string, StringSet.t) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (modname, (decls, _)) ->
        let deps = StringSet.remove modname (StringSet.inter name_set (hard_deps_of decls)) in
        Hashtbl.replace hard_graph modname deps)
      info;
    let pos : (string, int) Hashtbl.t = Hashtbl.create 16 in
    List.iteri (fun i d -> match d with
        | Ast.DMod (n, _, _, _) -> Hashtbl.replace pos n.Ast.txt i
        | _ -> ())
      preferred;
    let satisfies_hard_deps order =
      let p = Hashtbl.create 16 in
      List.iteri (fun i n -> Hashtbl.replace p n i) order;
      List.for_all (fun n ->
          let deps = Option.value ~default:StringSet.empty (Hashtbl.find_opt hard_graph n) in
          StringSet.for_all (fun d ->
              match Hashtbl.find_opt p d, Hashtbl.find_opt p n with
              | Some pd, Some pn -> pd < pn
              | _ -> true)
            deps)
        names
    in
    let preferred_names =
      List.filter_map (function Ast.DMod (n, _, _, _) -> Some n.Ast.txt | _ -> None) preferred
    in
    let final =
      if satisfies_hard_deps preferred_names then preferred
      else begin
        if dbg then
          Printf.eprintf
            "[order] hard-dependency violation in combined order — falling back to \
             hard-edge Kahn's-algorithm order for: %s\n%!"
            (String.concat "," preferred_names);
        (* Kahn's algorithm over [hard_graph], breaking ties by [pos]
           (the combined-edge DFS's preferred order) so behavior stays as
           close to the previous output as the hard constraints allow. *)
        let in_degree : (string, int) Hashtbl.t = Hashtbl.create 16 in
        let enables : (string, string list) Hashtbl.t = Hashtbl.create 16 in
        List.iter (fun n ->
            let deps = Option.value ~default:StringSet.empty (Hashtbl.find_opt hard_graph n) in
            Hashtbl.replace in_degree n (StringSet.cardinal deps);
            StringSet.iter (fun d ->
                Hashtbl.replace enables d (n :: Option.value ~default:[] (Hashtbl.find_opt enables d)))
              deps)
          names;
        let ready = ref (List.filter (fun n -> Hashtbl.find in_degree n = 0) names) in
        let by_pos a b =
          compare (Option.value ~default:max_int (Hashtbl.find_opt pos a))
                  (Option.value ~default:max_int (Hashtbl.find_opt pos b))
        in
        let corrected = ref [] in
        let remaining = ref (List.length names) in
        while !remaining > 0 do
          match List.sort by_pos !ready with
          | [] ->
            (* Genuine hard cycle: no way to satisfy every constraint.
               Emit whatever is left in preferred order (best effort,
               matches the previous behavior for irreducible cycles). *)
            List.iter (fun n ->
                if not (List.mem n !corrected) then corrected := n :: !corrected)
              preferred_names;
            remaining := 0
          | n :: _ ->
            ready := List.filter (fun x -> x <> n) !ready;
            corrected := n :: !corrected;
            decr remaining;
            List.iter (fun dependent ->
                let d = Hashtbl.find in_degree dependent - 1 in
                Hashtbl.replace in_degree dependent d;
                if d = 0 then ready := dependent :: !ready)
              (Option.value ~default:[] (Hashtbl.find_opt enables n))
        done;
        (* [corrected] was built by prepending as each node finished, so its
           head is the LAST node processed — reverse to restore the actual
           topological (processing) order before mapping back to decls. *)
        List.map (fun n -> snd (Hashtbl.find by_name n)) (List.rev !corrected)
      end
    in
    if dbg then
      Printf.eprintf "[order] final order (%d mods): %s\n%!"
        (List.length final)
        (String.concat ","
           (List.filter_map (function Ast.DMod (n, _, _, _) -> Some n.Ast.txt | _ -> None) final));
    final
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

(* EMPTY since 2026-08-05 (Task 3, specs/progress/2026-08-05-no-panic-proof-based-ban.md).
   Every prelude name that used to live here — `unwrap`, `expect`, `head`,
   `tail`, `last` — carries a real refinement precondition, so it is no longer
   banned by NAME: [Panic_surface_by_proof] (lib/refinecheck) checks each call
   site against its actual verdict instead, admitting the ones that are
   provably safe.  The binding stays (rather than being deleted along with
   [panic_surface_all_direct]) because it is the seam where a future prelude
   name with NO possible contract would go. *)
let panic_surface_prelude : StringSet.t = StringSet.empty

(* What remains SYNTACTICALLY banned among qualified stdlib names: only the
   ones with no refinement contract to consult.  `Array.get`/`Array.set`/
   `Array.pop` are Group B — they panic (out of bounds, and on an empty vector
   respectively) and no contract exists for them, so an unconditional ban is
   still the only sound answer.

   And it is the only answer AVAILABLE for them, not merely the one nobody got
   to yet: the 2026-08-05 feasibility gate established that a contract on these
   three cannot currently be discharged at all.  `Array.length` is a scalar
   CONSTRUCTOR FIELD read (`PVec(n,_,_,_) -> n`), and call-site reflection
   erases every non-datatype constructor field to a fresh unconstrained
   constant, so the measure is inert — see
   `specs/todos/2026-08-05-measure-over-scalar-ctor-field.md`.  Do not move
   these into [panic_surface_contracted] until that todo is closed: the
   proof-based pass is fail-closed on `Skipped`, so an inert contract would
   reject every call while advertising the name as proof-checked.

   Everything else that used to be here now carries a refinement contract and
   lives in [panic_surface_contracted] below.  Ban-list audit 2026-08-05
   (specs/progress/2026-08-05-no-panic-ban-list-audit.md) is what established
   which names carry a real contract. *)
let panic_surface_stdlib : StringSet.t = StringSet.of_list [
  "Array.get"; "Array.set"; "Array.pop";
]

(* ── The CONTRACTED panic surface ─────────────────────────────────────────
   Names that panic exactly when a declared refinement precondition fails, so
   a call to one CAN be proved safe.  This is the single source of truth for
   the set: [Panic_surface_by_proof.covered] (lib/refinecheck) aliases this
   binding rather than repeating it, which is what makes "disjoint from the
   syntactic ban lists" a structural property instead of a hand-checked one.

   Whether these are banned by NAME here depends on
   [proof_based_panic_surface] below. *)
let panic_surface_contracted : StringSet.t = StringSet.of_list [
  (* prelude spellings (prelude is unwrapped into global scope) *)
  "head"; "tail"; "last"; "unwrap"; "expect";
  (* qualified stdlib spellings *)
  "List.nth"; "List.head"; "List.last"; "List.tail";
  "List.maximum_int"; "List.minimum_int";
  "Option.unwrap"; "Option.expect";
  "Result.unwrap"; "Result.expect"; "Result.unwrap_err";
  "Random.normal"; "Random.exponential"; "Random.bernoulli"; "Random.choice";
  "Random.choice_weighted";
  "DateTime.fixed_zone"; "DateTime.fixed_zone_hm";
  "Stats.mean"; "Stats.min_val"; "Stats.max_val";
  "Stats.percentile"; "Stats.quantile"; "Stats.quantiles";
  "Stats.five_number_summary"; "Stats.variance"; "Stats.mode";
  "Stats.covariance"; "Stats.correlation"; "Stats.linear_regression";
]

(** Set by a pipeline that ALSO runs [Panic_surface_by_proof] (lib/refinecheck)
    after [Refine_check.check_module].  When true, this syntactic check leaves
    [panic_surface_contracted] alone and the proof-based pass decides those
    call sites from their actual verdicts.

    Default FALSE, and the default is the whole point.  March has three
    separate check pipelines and only two of them run refinecheck at all:

      - `bin/main.ml`'s compile/`--check` path and its `run_test_cmd` copy DO
        (they set this to true);
      - `bin/main.ml`'s [run_check_cmd] (`march check`, `march caps`) does NOT
        — it is a package-level, typecheck-only path seeded from a cached
        stdlib env, deliberately skipping the solver;
      - the LSP (`lsp/lib`) does NOT — it does not even link march_refinecheck.

    Without a verdict index there is nothing to consult, and `cap no_panic` is
    a guarantee, so "cannot prove" must mean "reject".  Leaving the flag false
    in those two pipelines therefore keeps the OLD unconditional ban (including
    its transitive fixpoint) exactly as it was before 2026-08-05 — conservative,
    no regression, just no proof-based widening there.  Getting this default
    backwards would silently let genuinely panicky code pass `march check` and
    make editor squiggles disappear, which is the failure direction the plan's
    Global Constraints call as serious as a false positive. *)
let proof_based_panic_surface : bool ref = ref false

let panic_surface_all_direct : StringSet.t =
  StringSet.union panic_surface_direct panic_surface_prelude

let panic_surface_suggestion : string -> string = function
  | "List.nth" ->
    "\n\nUse `List.nth_opt` to return `Option(a)` instead of panicking on out-of-bounds."
  | "List.head" | "head" ->
    "\n\nUse `List.head_opt` (or match on `Cons`/`Nil` directly) to avoid panicking on empty."
  | "List.tail" | "tail" ->
    "\n\nUse `List.tail_opt` or match on `Nil` to avoid panicking on empty."
  | "List.maximum_int" | "List.minimum_int" ->
    "\n\nCheck `List.length(xs) > 0` before calling, or use a `List.length` guard \
     followed by a total fold instead."
  | "unwrap" | "Option.unwrap" ->
    "\n\nUse `unwrap_or(opt, default)` or `match opt do Some(x) -> ... | None -> ... end`."
  | "expect" | "Option.expect" ->
    "\n\nUse `unwrap_or` or an explicit match to handle the `None` case."
  | "Result.unwrap" | "Result.expect" ->
    "\n\nUse `Result.unwrap_or` or match on `Ok`/`Err` to handle the error case."
  | "Array.get" | "Array.set" ->
    "\n\nBounds-check the index before access, or use a bounds-checked variant."
  | "Array.pop" ->
    "\n\nCheck `Array.length(v) > 0` before calling."
  | "Random.normal" | "Random.exponential" | "Random.bernoulli" ->
    "\n\nGuard the parameter before the call (e.g. clamp `sigma`/`lambda`/`p` to its \
     valid range) so the refinement precondition provably holds."
  | "Random.choice" ->
    "\n\nCheck `List.length(xs) > 0` before calling."
  | "DateTime.fixed_zone" ->
    "\n\nGuard `offset_seconds` to the range `-50400..=50400` before calling."
  | "DateTime.fixed_zone_hm" ->
    "\n\nGuard `minutes` to the range `0..<60` before calling."
  | "Stats.mean" | "Stats.min_val" | "Stats.max_val" ->
    "\n\nCheck `List.length(xs) > 0` before calling."
  | "panic" | "panic_" ->
    "\n\nReturn an error value (`Result`, `Option`) instead of calling `panic`."
  | "todo_" ->
    "\n\nImplement the body instead of using `todo!`, or remove the `cap no_panic` directive."
  | "unreachable_" ->
    "\n\nAdd a proof comment if this branch is truly unreachable, or handle it explicitly."
  | _ -> ""

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
            March_ast.Calls.calls_in_expr acc clause.Ast.fc_body
          ) [] def.Ast.fn_clauses
          |> List.map (fun (n, name_span, _app_span) -> (n, name_span))
        in
        Some (def.Ast.fn_name.txt, all_calls, fn_span)
      | _ -> None
    ) decls
  in
  (* Which local functions can carry TRANSITIVE blame to their callers.
     A [panic_surface_contracted] name is excluded, and that exclusion is
     load-bearing rather than cosmetic: `bin/main.ml` unwraps prelude into the
     ENTRY module's own decl list, so prelude's `fn tail`/`head`/`last`/
     `unwrap`/`expect` are literally `DFn`s of the `cap no_panic` module being
     checked.  Their bodies call `panic`, so the fixpoint seeded them and then
     blamed every caller "transitively calls `tail`" — which reintroduced the
     chain-blaming this task removed, and (worse) rejected a call the proof
     pass had just PROVED safe, since a transitive verdict never consults one.
     A guarded bare `tail(xs)` was still an error for exactly this reason.

     Excluding them is sound in both pipeline modes: when
     [proof_based_panic_surface] is false these names are back in
     [is_direct_panic_site] below, so a caller is rejected DIRECTLY and never
     needs the transitive path; when it is true, the proof pass owns the
     decision. A user-defined function that happens to be named `tail` is
     likewise decided by the proof pass, which fail-closes when it carries no
     contract. *)
  let local_fns =
    List.fold_left (fun s (name, _, _) ->
      if StringSet.mem name panic_surface_contracted then s
      else StringSet.add name s)
      StringSet.empty fn_entries
  in
  let _no_panic_mod_names = StringSet.of_list env.no_panic_modules in
  let is_direct_panic_site name =
    StringSet.mem name panic_surface_all_direct
    || StringSet.mem name panic_surface_stdlib
    (* Only when no proof-based pass will run — see [proof_based_panic_surface]. *)
    || ((not !proof_based_panic_surface)
        && StringSet.mem name panic_surface_contracted)
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
   union them in as incidental-correct extras. `read_byte` (raw stdin read,
   like `read_line`) is another such stdin-effect surface name not in the
   table, so union it in too. *)
let pure_banned : StringSet.t =
  let from_table = builtin_cap_table |> List.map fst |> StringSet.of_list in
  StringSet.union from_table
    (StringSet.of_list [ "spawn"; "send"; "exit"; "read_byte" ])

let pure_suggestion : string =
  "Use pure functions (no IO, spawn, vault, or random ops) in a `cap pure` module."

let check_pure_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let mod_name = env.current_module in
  (* See [locally_declared_names_of]: a `cap pure` module's own function
     sharing a builtin's name (e.g. its own `random_bytes`) is not a call to
     that builtin. *)
  let locally_declared_names = locally_declared_names_of decls in
  List.iter (fun d ->
    match d with
    | Ast.DFn (def, _fn_span) ->
      List.iter (fun clause ->
        let calls = March_ast.Calls.names_and_name_spans clause.Ast.fc_body in
        List.iter (fun (name, site_span) ->
          if StringSet.mem name pure_banned
             && not (Hashtbl.mem locally_declared_names name) then
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
      let has_foreign = List.exists (fun (path, _scope) ->
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
  (* See [locally_declared_names_of]: same shadowing guard as
     [check_pure_module]. *)
  let locally_declared_names = locally_declared_names_of decls in
  List.iter (fun d ->
    match d with
    | Ast.DFn (def, _fn_span) ->
      List.iter (fun clause ->
        let calls = March_ast.Calls.names_and_name_spans clause.Ast.fc_body in
        List.iter (fun (name, site_span) ->
          if StringSet.mem name deterministic_banned
             && not (Hashtbl.mem locally_declared_names name) then
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
    let was_local_fn = StrMap.mem def.fn_name.txt env.local_fns in
    let env = bind_var def.fn_name.txt sch env in
    (* bind_var cleared this fn's own fn_arities/local_fns entries (shadow
       semantics); restore them so later same-module calls keep the
       direct-call arity check AND keep being recorded as genuine Call
       references (see [bind_var]'s [local_fns] shadowing-discipline
       comment — this is [check_fn]'s post-hoc mirror site: the module's
       pass-1 prebind put this fn's name in [local_fns] before [check_fn]
       ran; without restoring it here, EVERY same-module call to a fn
       checked later than its own definition would silently stop being
       recorded, since [bind_var]'s unconditional removal has nothing left
       to re-add it). *)
    let env =
      let arity = match def.fn_clauses with
        | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
      { env with fn_arities =
          StrMap.add def.fn_name.txt (arity, def.fn_name.span) env.fn_arities;
        local_fns =
          if was_local_fn then StrMap.add def.fn_name.txt () env.local_fns
          else env.local_fns } in
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
    (* A top-level `let` binding's RHS has no enclosing function — see
       [with_no_caller]. Without this, any Call/Ctor reference in the RHS
       gets misattributed to whatever [DFn] [check_decl] happened to check
       last in module order (or a stale caller from an earlier file in a
       multi-file compilation). *)
    let rhs_ty = with_no_caller env' (fun () -> infer_expr env' b.bind_expr) in
    Hashtbl.replace env.type_map sp (repr rhs_ty);
    let bindings, pat_ty = infer_pattern ~expected:rhs_ty env' b.bind_pat in
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
                    ; ci_module  = env.current_module
                    ; ci_vis     = v.var_vis
                    ; ci_is_actor_msg = false } in
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
      add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_module = env.current_module; ci_vis = Ast.Public;
                          ci_is_actor_msg = false }
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
                   ci_arg_tys = arg_tys; ci_module = env.current_module; ci_vis = Ast.Public;
                   ci_is_actor_msg = true } in
        { acc_env with ctors = add_ctor h.ah_msg.txt ci acc_env.ctors }
      ) env_with_actor_ctor actor.actor_handlers in
    (* Check init expression — must return the state record type.  Neither
       the init expr nor any handler body below is checked via [check_fn], so
       there is no enclosing function — see [with_no_caller]. *)
    with_no_caller env_with_ctors (fun () ->
      check_expr env_with_ctors actor.actor_init state_ty
        ~reason:(Some (RBuiltin "actor init must return the initial state record")));
    (* Check handlers with state and message params in scope *)
    List.iter (fun (h : Ast.actor_handler) ->
        let handler_env = bind_var "state" (Mono state_ty) env_with_ctors in
        (* Shadow the global `self` builtin (registered as plain Int — see
           its definition above) with this actor's own Pid[state_ty], the
           same type `spawn(name)` produces for this actor elsewhere.  Only
           valid inside a handler body, exactly like `state` above. *)
        let handler_env =
          bind_var "self" (Mono (TCon ("Pid", [state_ty]))) handler_env in
        let handler_env =
          List.fold_left (fun e p ->
              bind_var p.Ast.param_name.txt
                (Mono (match p.param_ty with
                   | Some ann -> let tvars = ref [] in surface_ty env ~tvars ann
                   | None     -> fresh_var env.level))
                e
            ) handler_env h.ah_params
        in
        (* Handler body must return the state record type — emit rich
           diagnostic. No enclosing function — see [with_no_caller]. *)
        let inferred = with_no_caller handler_env (fun () -> infer_expr handler_env h.ah_body) in
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
          (* bind_var FIRST (it clears any shadowed fn_arities entry), then
             register this fn's own arity so the entry survives — see the
             fn_arities shadow-semantics comment on bind_var. *)
          let e = bind_var def.fn_name.txt (Mono (fresh_var (env.level + 1))) e in
          { e with local_fns = StrMap.add def.fn_name.txt () e.local_fns;
                   fn_arities = StrMap.add def.fn_name.txt (arity, def.fn_name.span) e.fn_arities }
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
    (* Of the newly-exported qualified names, which denote a genuine function
       (as opposed to a plain [DLet] value/constant)?  A key [k] is
       function-backed either because it's one of THIS module's own [DFn]s
       (tracked bare in [inner_env.local_fns]) or because it is itself an
       already-qualified key re-exported from a nested public [DMod] (tracked
       in [inner_env.qual_fn_names], populated by that nested module's own
       pass through this same branch) — see [qual_fn_names]'s doc comment. *)
    let new_fn_quals = StrMap.fold (fun k _sch acc ->
        if is_pub_key k &&
           (StrMap.mem k inner_env.local_fns || StrMap.mem k inner_env.qual_fn_names)
        then StrMap.add (name.txt ^ "." ^ k) () acc
        else acc
      ) inner_env.vars StrMap.empty in
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
        | Ast.DNeeds (caps, _) -> List.map (fun (p, _) -> cap_path_of_names p) caps
        | _ -> []) decls in
    (* Key those needs by the FULLY-QUALIFIED module path, the same one
       [check_module_needs] is given as [~cap_qname_prefix] just above and the
       same convention TIR attribution uses (lower.ml's [mod_prefix]) — the
       --cap-strict ceiling in bin/main.ml matches [module_caps] against that
       attribution by owner name.  Keying by the BARE name made every module
       nested two or more deep read as "uses X but does not declare needs X"
       even when it declared exactly X, because attribution named it
       `Outer.Inner` while this list said `Inner`.  At depth 1 the two spellings
       coincide (the entry module is unwrapped, so [cap_qual_prefix] is "" in
       its body), which is why the bug only showed from depth 2.

       The bare key is kept alongside it: Check 4 and [module_wide_caps] look
       up `use` paths AS WRITTEN, so a sibling imported by its short name must
       still resolve.  And [inner_env.module_caps] — not the outer env's — is
       carried outward, or entries recorded by modules nested inside this one
       (which is exactly where the mis-keyed ones lived) are dropped at this
       boundary and never reach the ceiling check at all. *)
    let cap_qname =
      if env.cap_qual_prefix = "" then name.txt
      else env.cap_qual_prefix ^ "." ^ name.txt
    in
    let module_caps' =
      let with_qual = (cap_qname, inner_needs) :: inner_env.module_caps in
      if cap_qname = name.txt then with_qual
      else (name.txt, inner_needs) :: with_qual
    in
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
      qual_fn_names = StrMap.union (fun _k a _ -> Some a) new_fn_quals env'.qual_fn_names;
      module_caps = module_caps';
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
    (* Validate each step for structural correctness. [in_loop] tracks
       whether we're nested (directly, or via a `choose` branch) inside a
       `loop` block — `stop` is only meaningful there. *)
    let rec validate_step ~in_loop = function
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
        List.iter (validate_step ~in_loop:true) steps
      | Ast.ProtoChoice (participant, branches) ->
        if List.length branches < 2 then
          Err.error env.errors ~span:participant.span
            (Printf.sprintf
               "Protocol `%s`: `choice` by `%s` must have at least 2 branches."
               name.txt participant.txt);
        List.iter (fun (_, steps) -> List.iter (validate_step ~in_loop) steps) branches
      | Ast.ProtoStop stop_sp ->
        if not in_loop then
          Err.error env.errors ~span:stop_sp
            (Printf.sprintf
               "Protocol `%s`: `stop` outside of a `loop` has no effect — the \
                protocol already ends here if you just write nothing."
               name.txt)
    in
    List.iter (validate_step ~in_loop:false) pdef.proto_steps;
    (* A `loop` never exits (its projection is `Rec X. S[X]`), so any step that
       follows one at the same nesting level is unreachable. *)
    (* [tail] is what follows at every ENCLOSING level.  A `choose` branch's
       real continuation is its own steps FOLLOWED BY the post-`choose` tail
       (`project_steps`' `ProtoChoice` arm projects `rest_ty ()` into every
       branch), so a branch ending in a `loop` makes that projected tail
       unreachable just as surely as a written-out step would — walking each
       branch with `rest = []` and no tail missed exactly that case. *)
    let rec check_unreachable_after_loop ~tail steps =
      match steps with
      | Ast.ProtoLoop inner :: rest ->
        check_unreachable_after_loop ~tail:[] inner;
        if rest <> [] then
          Err.error env.errors ~span:sp
            (Printf.sprintf
               "Protocol `%s`: the steps after this `loop` can never run — \
                a `loop` block repeats forever, so it must be the last step."
               name.txt)
        else if tail <> [] then
          Err.error env.errors ~span:sp
            (Printf.sprintf
               "Protocol `%s`: this `choose` branch ends in a `loop`, but the \
                protocol continues after the `choose` — those following steps \
                are projected into EVERY branch, so they can never run in this \
                one. Move them inside the branches that can reach them."
               name.txt)
      | Ast.ProtoStop stop_sp :: rest ->
        (* `stop` projects to `SEnd` unconditionally (see [project_steps]),
           discarding both [rest] here and the enclosing [tail] — same
           unreachability shape as `loop`, just via early exit instead of
           looping forever. *)
        if rest <> [] then
          Err.error env.errors ~span:stop_sp
            (Printf.sprintf
               "Protocol `%s`: the steps after `stop` can never run — `stop` \
                exits the loop immediately, so it must be the last step."
               name.txt)
        else if tail <> [] then
          Err.error env.errors ~span:stop_sp
            (Printf.sprintf
               "Protocol `%s`: this `choose` branch ends in `stop`, but the \
                protocol continues after the `choose` — those following steps \
                are projected into EVERY branch, so they can never run in this \
                one. Move them inside the branches that can reach them."
               name.txt)
      | Ast.ProtoChoice (_, branches) :: rest ->
        List.iter (fun (_, arm) ->
            check_unreachable_after_loop ~tail:(rest @ tail) arm) branches;
        check_unreachable_after_loop ~tail rest
      | _ :: rest -> check_unreachable_after_loop ~tail rest
      | [] -> ()
    in
    check_unreachable_after_loop ~tail:[] pdef.proto_steps;
    (* Project the protocol onto each role and verify duality. *)
    let projections = project_protocol env ~span:sp ~proto_name:name.txt pdef in
    let participants = List.map fst projections in
    if participants <> [] && List.length participants < 2 then
      Err.warning env.errors ~span:sp
        (Printf.sprintf
           "Protocol `%s` only names one participant (`%s`). \
            A protocol usually involves at least two parties."
           name.txt (List.hd participants));
    (* Protocol roles are their own namespace — they are NOT type or actor
       names, so no "unknown participant" hint is emitted (F8, removed
       2026-07-24: it fired on every ordinary protocol, including the
       reference chapter's own Echo example). *)
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
        (* An interface method signature has no enclosing function — see
           [with_no_caller]. *)
        let ty = with_no_caller env (fun () -> surface_ty env ~tvars m.md_ty) in
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
    (* The impl header's own type (`impl Iface(T)`) has no enclosing
       function — see [with_no_caller]. *)
    let inst_ty = with_no_caller env (fun () -> surface_ty env ~tvars idef.impl_ty) in
    (* Register this implementation so CInterface constraints can be discharged. *)
    let env_with_impl = { env with impls =
      (let key = idef.impl_iface.txt in
       let lst = Option.value ~default:[] (StrMap.find_opt key env.impls) in
       (* Pass-2 re-registration for constraint discharge; coherence is enforced
          in [register_impl_shape] (Pass 1). Carry the span for the new shape. *)
       StrMap.add key ((inst_ty, idef.impl_iface.span, None) :: lst) env.impls) } in
    (* Check 'when' constraints: each C(T) must already be implemented. *)
    List.iter (fun ((cname : Ast.name), ctys) ->
        (* A `when C(T)` constraint type is also part of the impl header,
           with no enclosing function — see [with_no_caller]. *)
        match with_no_caller env (fun () -> List.map (surface_ty env ~tvars) ctys) with
        | [cty] ->
          let cty = repr cty in
          (match cty with
           | TVar _ -> ()   (* Polymorphic param — checked at use sites *)
           | _ ->
             if not (match StrMap.find_opt cname.txt env.impls with
                 | None -> false
                 | Some tys -> List.exists (fun (impl_ty, _, _) ->
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
                     | Some tys -> List.exists (fun (impl_ty, _, _) ->
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
                (* Default method injected by desugar — just check the body
                   expr. This bypasses [check_fn], so there is no enclosing
                   function — see [with_no_caller]. *)
                with_no_caller env (fun () ->
                  check_expr env fc_body expected_ty
                    ~reason:(Some (RBuiltin
                      (Printf.sprintf "default `%s` in interface `%s`"
                         mname.txt idef.impl_iface.txt))))
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
    (* Register each foreign function as a monomorphic binding. An extern
       fn's own signature has no enclosing function — see [with_no_caller]. *)
    List.fold_left (fun env (ef : Ast.extern_fn) ->
        let tvars = ref [] in
        let param_tys, ret_ty = with_no_caller env (fun () ->
            let param_tys = List.map (fun (_, t) -> surface_ty env ~tvars t) ef.ef_params in
            let ret_ty = surface_ty env ~tvars ef.ef_ret_ty in
            (param_tys, ret_ty)) in
        let ty = List.fold_right (fun pt acc -> TArrow (pt, acc)) param_tys ret_ty in
        bind_var ef.ef_name.txt (Mono ty) env
      ) env edef.ext_fns

  | Ast.DUse (ud, sp) ->
    let mod_str = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
    let prefix = mod_str ^ "." in
    (match ud.use_sel with
     | Ast.UseSingle ->
       (* A single-segment `use Foo` needs no new bindings: bare references
          like `Foo.bar` already match the qualified key "Foo.bar" directly.
          A DOTTED `use A.B` is different — the module's members are bound
          under the FULL qualified key "A.B.bar", which a bare "B.bar"
          reference (the natural way to use the last, most-specific segment
          after importing it) does not match. Re-export every "A.B.name" as
          "B.name" — identical in spirit to how `alias A.B as C` re-exports
          under the chosen short name — so `use A.B` then `B.bar(...)` works
          the same way `alias A.B as B` would. A single-segment path makes
          [last_seg] equal [mod_str], so the rebind is a same-key no-op and
          this subsumes the old behavior exactly. *)
       let last_seg = match List.rev ud.use_path with
         | last :: _ -> last.Ast.txt
         | [] -> mod_str
       in
       let short_prefix = last_seg ^ "." in
       let new_bindings = StrMap.fold (fun k sch acc ->
           let plen = String.length prefix in
           if String.length k > plen && String.sub k 0 plen = prefix then
             let rest = String.sub k plen (String.length k - plen) in
             let short_key = short_prefix ^ rest in
             if StrMap.mem short_key env.vars then acc
             else (short_key, sch) :: acc
           else acc) env.vars [] in
       (* The entry is registered UNCONDITIONALLY, but pre-marked used when it
          rebound nothing.  A single-segment `use Foo` rebinds nothing (every
          "Foo.bar" short key is already the qualified key), so it used to file
          no entry at all and therefore tracked no references — which left
          demand-driven capability propagation (see [import_required_caps])
          with nothing to go on and forced it back to the module-granular
          answer for exactly the qualified-reference form `use` exists to
          serve.  Seeding [ie_used] with [new_bindings = []] keeps the
          unused-import warning byte-identical to before (a rebind-nothing
          `use` never warned, because it had no entry); the entry now exists
          purely so [record_use] can record WHICH members were referenced. *)
       let entry = { ie_span = sp
                   ; ie_desc = Printf.sprintf
                       "Unused import: nothing from `%s` is used.\n\
                        Remove this import or use something from it." mod_str
                   ; ie_matches = (fun name ->
                       name = mod_str
                       || (String.length name > String.length short_prefix
                           && String.sub name 0 (String.length short_prefix) = short_prefix)
                       || (String.length name > String.length prefix
                           && String.sub name 0 (String.length prefix) = prefix))
                   ; ie_used = ref (new_bindings = [])
                   ; ie_used_names = Hashtbl.create 8 } in
       env.import_tracker := entry :: !(env.import_tracker);
       import_index_add_exact env.import_idx mod_str entry;
       import_index_add_prefix env.import_idx last_seg entry;
       let prefix_root = match String.index_opt mod_str '.' with
         | Some i -> String.sub mod_str 0 i | None -> mod_str in
       import_index_add_prefix env.import_idx prefix_root entry;
       bind_vars new_bindings env
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
                     ; ie_used = ref false
                     ; ie_used_names = Hashtbl.create 8 } in
         env.import_tracker := entry :: !(env.import_tracker);
         (* Index for O(1) [record_use] lookup: every rebound short name is an
            exact-match key, as is the bare module name itself (ie_matches's
            "name = mod_str" clause -- an EVar referencing the module path
            literally); the module's first path segment is the prefix-index
            key a qualified reference (e.g. "Depot.Gate.foo") hashes to (see
            [record_use] -- it looks up by its own first-dot split, which is
            independent of [split_qualified]'s rindex/module-load convention
            elsewhere in this file: unused-import tracking only ever needs
            the declared import's own root segment, never a full module-load
            resolution). *)
         List.iter (fun n -> import_index_add_exact env.import_idx n entry) short_names;
         import_index_add_exact env.import_idx mod_str entry;
         let prefix_root = match String.index_opt mod_str '.' with
           | Some i -> String.sub mod_str 0 i | None -> mod_str in
         import_index_add_prefix env.import_idx prefix_root entry
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
                         ; ie_used = ref false
                         ; ie_used_names = Hashtbl.create 8 } in
             env.import_tracker := entry :: !(env.import_tracker);
             import_index_add_exact env.import_idx n.Ast.txt entry;
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
                     ; ie_used = ref false
                     ; ie_used_names = Hashtbl.create 8 } in
         env.import_tracker := entry :: !(env.import_tracker);
         List.iter (fun n -> import_index_add_exact env.import_idx n entry) short_names;
         import_index_add_exact env.import_idx mod_str entry;
         let prefix_root = match String.index_opt mod_str '.' with
           | Some i -> String.sub mod_str 0 i | None -> mod_str in
         import_index_add_prefix env.import_idx prefix_root entry
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
                  ; ie_used = ref false
                  ; ie_used_names = Hashtbl.create 8 } in
      env.import_tracker := entry :: !(env.import_tracker);
      (* [short_name] has no dots, so it is both the exact-match key (bare
         alias reference) and the prefix-index key (qualified reference
         "FB.baz" first-dot-splits to exactly "FB" = short_name). *)
      import_index_add_exact env.import_idx short_name entry;
      import_index_add_prefix env.import_idx short_name entry
    end;
    bind_vars new_bindings env

  | Ast.DNeeds (caps, _sp) ->
    (* Record declared capability paths in env for DMod validation.
       Each path is a list of names e.g. ["IO"; "Network"] → "IO.Network" *)
    let scoped = List.map (fun (names, scope) ->
        (String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names), scope)
      ) caps in
    let paths = List.map fst scoped in
    { env with mod_needs = paths @ env.mod_needs;
               mod_need_scopes = scoped @ env.mod_need_scopes }

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
    (* Typecheck the test body; it must be Unit. No enclosing function — see
       [with_no_caller]. *)
    (* R2 exemption: a test body has no [main] to be granted the root from, so
       [root_cap] stays nameable here (see [env.root_cap_allowed]). *)
    let env = { env with root_cap_allowed = true } in
    with_no_caller env (fun () ->
      check_expr env tdef.test_body t_unit
        ~reason:(Some (RBuiltin (Printf.sprintf "test body of \"%s\" must produce Unit" tdef.test_name))));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DDescribe (_name, decls, sp) ->
    let env' = List.fold_left check_decl env decls in
    Hashtbl.replace env'.type_map sp t_unit;
    env'

  | Ast.DSetup (body, sp) ->
    (* No enclosing function — see [with_no_caller]. *)
    (* R2 exemption, same rationale as [DTest]. *)
    let env = { env with root_cap_allowed = true } in
    with_no_caller env (fun () ->
      check_expr env body t_unit ~reason:(Some (RBuiltin "setup body must produce Unit")));
    Hashtbl.replace env.type_map sp t_unit;
    env

  | Ast.DSetupAll (body, sp) ->
    (* No enclosing function — see [with_no_caller]. *)
    (* R2 exemption, same rationale as [DTest]. *)
    let env = { env with root_cap_allowed = true } in
    with_no_caller env (fun () ->
      check_expr env body t_unit ~reason:(Some (RBuiltin "setup_all body must produce Unit")));
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

(** Collect all variable names bound by a pattern (used to find structurally
    smaller variables introduced by pattern matching, and to retire shadowed
    names from the call-graph name set). *)
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
  | Ast.PatOr (pats, _) ->
    List.fold_left (fun acc p -> StringSet.union acc (collect_pattern_vars p))
      StringSet.empty pats

(** Collect all names from [fn_names] that are called directly (not through
    lambdas or local [ELetFn] bodies) in [e].  Used to build the call graph
    for SCC / mutual-recursion detection.

    [fn_names] is a SCOPE, not a flat name list: a local binder (an inner
    [ELetFn], or a [let] whose pattern binds the name) retires that name for
    the rest of the enclosing block.  Without this, a local helper whose name
    collides with a top-level function forges a call-graph edge and invents an
    SCC that does not exist — e.g. prelude's [length] uses a local [fn go], so
    any program with its own top-level [go] was told its calls were "recursive
    calls not in tail position". *)
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
      (* Arm-bound names shadow same-named top-level functions inside the arm. *)
      let names =
        StringSet.diff fn_names (collect_pattern_vars br.Ast.branch_pat) in
      let g = Option.fold ~none:StringSet.empty
                ~some:(collect_direct_fn_calls names) br.Ast.branch_guard in
      StringSet.union acc
        (StringSet.union g (collect_direct_fn_calls names br.Ast.branch_body))
    ) (collect_direct_fn_calls fn_names scrut) branches
  (* A block is the one place where a binder's scope extends to SIBLING
     expressions: [ELetFn]/[ELet] carry no continuation of their own, so the
     shadowing has to be applied here, to the rest of the block. *)
  | Ast.EBlock (exprs, _) ->
    let (acc, _) =
      List.fold_left (fun (acc, names) ex ->
        let acc' = StringSet.union acc (collect_direct_fn_calls names ex) in
        let names' = match ex with
          | Ast.ELetFn (iname, _, _, _, _) -> StringSet.remove iname.txt names
          | Ast.ELet (b, _) -> StringSet.diff names (collect_pattern_vars b.Ast.bind_pat)
          | _ -> names
        in
        (acc', names')
      ) (StringSet.empty, fn_names) exprs
    in
    acc
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
  | Ast.ELetQ (pat, r, c, _) ->
    StringSet.union (collect_direct_fn_calls fn_names r)
      (collect_direct_fn_calls
         (StringSet.diff fn_names (collect_pattern_vars pat)) c)
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
    [fn_params] is the set of parameter variable names for [fn_name].

    [recursive_names] is a SCOPE, threaded through [chk] as [names]: a local
    binder (inner [fn], [let], [let?], a match arm's pattern) retires that name
    for its extent, so a call to a shadowing local is not misattributed to the
    same-named recursive function. *)
let rec check_tail_position
    (errors : Err.ctx)
    (recursive_names : StringSet.t)
    (fn_name : string)
    (fn_params : StringSet.t)
    (body : Ast.expr) : unit =
  (* [smaller] accumulates variables known to be structurally smaller than a
     function parameter (introduced by pattern-matching on a parameter). *)
  let rec chk in_tail (names : StringSet.t) (smaller : StringSet.t) ctx expr =
    match expr with
    (* ── Recursive call ── *)
    | Ast.EApp (Ast.EVar fn, args, sp) when StringSet.mem fn.txt names ->
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
        chk false names smaller
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
      chk false names smaller "function part of application" f;
      List.iter (chk false names smaller arg_ctx) args
    (* ── Constructor ── *)
    | Ast.ECon (name, args, _) ->
      let arg_ctx = Printf.sprintf "wrapped in constructor `%s`" name.txt in
      List.iter (chk false names smaller arg_ctx) args
    (* ── if/do/else/end: condition not tail; branches inherit ── *)
    | Ast.EIf (cond, then_, else_, _) ->
      chk false names smaller "condition of `if`" cond;
      chk in_tail names smaller ctx then_;
      chk in_tail names smaller ctx else_
    (* ── match do cond_arm* end ── *)
    | Ast.ECond (arms, _) ->
      List.iter (fun (ce, be) ->
        chk false names smaller "condition in `match do`" ce;
        chk in_tail names smaller ctx be
      ) arms
    (* ── match: scrutinee not tail; if scrutinee is a parameter or smaller
          variable, extend [smaller] with all vars bound in each arm's pattern ── *)
    | Ast.EMatch (scrut, branches, _) ->
      chk false names smaller "scrutinee of `match`" scrut;
      let scrut_is_smaller = scrutinee_is_param_or_smaller fn_params smaller scrut in
      List.iter (fun (br : Ast.branch) ->
        let arm_pat_vars = collect_pattern_vars br.branch_pat in
        let arm_smaller =
          if scrut_is_smaller then StringSet.union smaller arm_pat_vars else smaller
        in
        (* Arm-bound names shadow the recursive names inside the arm. *)
        let arm_names = StringSet.diff names arm_pat_vars in
        Option.iter (chk false arm_names arm_smaller "match guard") br.branch_guard;
        chk in_tail arm_names arm_smaller ctx br.branch_body
      ) branches
    (* ── block: only last expression is in tail position.
          Propagate structural smallness: if a let binding assigns a variable
          to a structurally-smaller expression, that variable is also smaller. ── *)
    | Ast.EBlock (exprs, _) ->
      let rec go ns s = function
        | [] -> ()
        | [last] -> chk in_tail ns s ctx last
        | hd :: tl ->
          chk false ns s "non-final expression in block" hd;
          let s' = match hd with
            | Ast.ELet (b, _) ->
              (match b.Ast.bind_pat with
               | Ast.PatVar v
                 when is_structurally_smaller fn_params s b.Ast.bind_expr ->
                 StringSet.add v.txt s
               | _ -> s)
            | _ -> s
          in
          (* A local binder shadows a same-named recursive function for the
             rest of the block — calls to it are not recursive calls. *)
          let ns' = match hd with
            | Ast.ELetFn (iname, _, _, _, _) -> StringSet.remove iname.txt ns
            | Ast.ELet (b, _) -> StringSet.diff ns (collect_pattern_vars b.Ast.bind_pat)
            | _ -> ns
          in
          go ns' s' tl
      in
      go names smaller exprs
    (* ── let binding: RHS is never tail ── *)
    | Ast.ELet (b, _) ->
      chk false names smaller "right-hand side of `let` binding" b.Ast.bind_expr
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
    | Ast.EAnnot (ex, _, _) -> chk in_tail names smaller ctx ex
    (* ── non-tail contexts ── *)
    | Ast.ETuple (es, _) ->
      List.iter (chk false names smaller "tuple element") es
    | Ast.ERecord (fields, _) ->
      List.iter (fun ((nm : Ast.name), ex) ->
        chk false names smaller (Printf.sprintf "value of record field `%s`" nm.txt) ex
      ) fields
    | Ast.ERecordUpdate (base, fields, _) ->
      chk false names smaller "base of record update" base;
      List.iter (fun ((nm : Ast.name), ex) ->
        chk false names smaller (Printf.sprintf "value of record field `%s`" nm.txt) ex
      ) fields
    | Ast.EField (ex, _, _)  -> chk false names smaller "object of field access" ex
    | Ast.EPipe  (l, r, _)   -> chk false names smaller "left side of pipe" l;
                                 chk false names smaller "right side of pipe" r
    | Ast.EAtom (_, args, _) -> List.iter (chk false names smaller "atom argument") args
    | Ast.ESend (cap, msg, _) ->
      chk false names smaller "capability in `send`" cap;
      chk false names smaller "message in `send`" msg
    | Ast.ESpawn (ex, _)      -> chk false names smaller "argument to `spawn`" ex
    | Ast.EDbg (Some ex, _)   -> chk false names smaller "argument to `dbg`" ex
    | Ast.ELetQ (pat, r, cont, _) ->
      chk false names smaller "right-hand side of `let?`" r;
      chk in_tail (StringSet.diff names (collect_pattern_vars pat))
        smaller ctx cont
    | Ast.EAssert (ex, _)     -> chk false names smaller "assert expression" ex
    | Ast.ESigil (_, content, _) -> chk false names smaller "sigil content" content
    (* ── leaves ── *)
    | Ast.EDbg (None, _) | Ast.ELit _ | Ast.EVar _ | Ast.EHole _
    | Ast.EResultRef _ -> ()
  in
  chk true recursive_names StringSet.empty "" body

(** Run tail-call enforcement for all [DFn] declarations in [decls]
    (at a single scope level).  Recurses into [DMod] sub-modules. *)
let rec enforce_tail_calls_in_decls (errors : Err.ctx) (decls : Ast.decl list) : unit =
  (* Names declared in an [extern] block at this level.  An extern has no
     body, so it can never recurse; a bare call to one must not be resolved
     against a same-named ordinary function (the entry module's decls include
     the injected prelude, so e.g. an extern `length` sat next to prelude's
     `fn length`). *)
  let extern_names =
    List.fold_left (fun acc d ->
      match d with
      | Ast.DExtern (ext, _) ->
        List.fold_left (fun acc ef -> StringSet.add ef.Ast.ef_name.txt acc)
          acc ext.Ast.ext_fns
      | _ -> acc
    ) StringSet.empty decls
  in
  (* Collect function names at this level *)
  let fn_names =
    List.fold_left (fun acc d ->
      match d with
      | Ast.DFn (def, _) -> StringSet.add def.fn_name.txt acc
      | _ -> acc
    ) StringSet.empty decls
  in
  let fn_names = StringSet.diff fn_names extern_names in
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
      (* Decline to build a scheme from a QUALIFIED type name.  This prebind
         pass has no env, so it cannot reproduce [surface_ty]'s type resolution:
         [surface_ty] canonicalizes a qualified variant to its bare nominal
         (`Conduit.ConduitError` -> `ConduitError`) AND expands a qualified
         record to a structural [TRecord].  Emitting a verbatim qualified nominal
         `TCon("Mod.T")` here made a prebind fn scheme — used at a call site
         checked BEFORE the callee's Pass-2 re-derivation — mismatch the bare
         (or structural) type the caller's argument carries, an order-dependent
         "expected Mod.T but got T".  Guessing bare unconditionally instead
         wrongly conflates two same-suffixed types (`Conduit.Config` vs stdlib
         `Config`).  Returning None falls back to the [fresh_var] placeholder,
         which unifies with anything and imposes no false constraint; the
         callee's own [check_fn] still derives and enforces its real type. *)
      if String.contains name.txt '.' then None
      else
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
(* ── R1 stages A+B: the grant check ──────────────────────────────────────
   specs/2026-08-08-r1-no-ambient-io-design.md.

   `main`'s capability parameter IS the program's grant, and the program's
   transitive capability closure from `main` must sit under it.  This is the
   first check in the capability system that says NO rather than "declare
   it": every earlier check (1b, the ceiling, R3, R2) verifies that the
   MANIFEST is truthful, and a hostile module with a truthful manifest passes
   them all.  Here, `fn main(cap : Cap(IO.Console))` makes "this program
   reaches nothing beyond the console" a compile-time property no `needs`
   line can override.

   Adoption contract (each clause pinned in test_compiler's cap_grant group):
   - no capability parameter → NO gate.  Ambient, exactly today's behavior;
     stage A/B breaks no existing program.
   - `Cap(IO)` → the full grant; every IO-lattice point sits under it.
   - `Cap(IO.X)` → narrow grant, enforced transitively through helpers and
     the stdlib alike.
   - `IO.Foreign` under a narrow grant is REFUSED with its own message: what
     linked C does is not modellable, so certifying a bound over it would be
     a lie (ladder doc, "interactions to design for").

   Design constraints inherited from a week of capability bugs:
   - Judged on the TYPECHECK-side closure ([fn_transitive_capability_
     closures_tbl]), which both the interpreter and compile paths share — the
     unused-warning contradiction came from gating one path on an analysis
     the other path does not run.
   - Reachability-based: caps(main), not the file's union.  Dead code costs
     nothing, matching the ceiling's post-#225 semantics.
   - Non-IO capability roots (FFI caps like `Ffi`/`LibC`) are OUTSIDE the IO
     lattice and outside this check — they are governed by the extern checks;
     holding them under an IO grant would reject every FFI program with a
     message about a lattice they are not in.  Their IO shadow (`IO.Foreign`)
     is what the Foreign clause above bounds.
   - The check runs at the end of [check_module_core] only — never on the
     REPL's [check_module_with_env] path, which has no entry point to be
     granted from (the same exemption R2 gives it). *)
let check_main_grant (env : env) (decls : Ast.decl list) : unit =
  let main_grant : (string * Ast.span) option =
    List.find_map
      (function
        | Ast.DFn (def, _) when def.Ast.fn_name.txt = "main" ->
          (match def.Ast.fn_clauses with
           | clause :: _ ->
             (match clause.Ast.fc_params with
              | [ Ast.FPNamed p ] | [ Ast.FPDefault (p, _) ] ->
                (match p.Ast.param_ty with
                 | Some ty ->
                   (match March_caps.Cap_surface_ty.caps_in_ty ty with
                    | g :: _ -> Some (g, clause.Ast.fc_span)
                    | [] -> None)
                 | None -> None)
              | _ -> None)
           | [] -> None)
        | _ -> None)
      decls
  in
  match main_grant with
  | None -> ()
  | Some (grant, span) ->
    let closure =
      match
        Hashtbl.find_opt (fn_transitive_capability_closures_tbl env) "main"
      with
      | Some caps -> caps
      | None -> []
    in
    (* One function that holds [c] directly AND is reachable from main, for
       the diagnostic.  Restricting to the reachable set matters: the first
       version picked any holder from [own_cap_closures] — the whole env,
       linked stdlib included — and named `Logger.with_span` for an IO.Clock
       reached through `Random.int`, sending the user to a function their
       program never calls.

       The BFS resolves a reference the same two ways the closure fixpoint's
       resolver tries first (the name as-is, then qualified by the refering
       key's module prefix); the remaining resolver shapes are rare enough
       that a miss only shrinks the candidate set — the fallback below then
       names an arbitrary holder rather than dropping the hint, which is
       still where the capability lives even if reachability was not
       re-proven here. *)
    let reachable_from_main =
      let visited = Hashtbl.create 64 in
      let queue = Queue.create () in
      Queue.push "main" queue;
      while not (Queue.is_empty queue) do
        let k = Queue.pop queue in
        if not (Hashtbl.mem visited k) then begin
          Hashtbl.replace visited k ();
          let prefix =
            match String.rindex_opt k '.' with
            | Some i -> String.sub k 0 (i + 1)
            | None -> ""
          in
          List.iter
            (fun r ->
               if Hashtbl.mem env.own_cap_closures r
                  || Hashtbl.mem env.fn_refs r
               then Queue.push r queue;
               let q = prefix ^ r in
               if q <> r
                  && (Hashtbl.mem env.own_cap_closures q
                      || Hashtbl.mem env.fn_refs q)
               then Queue.push q queue)
            (Option.value ~default:[] (Hashtbl.find_opt env.fn_refs k))
        end
      done;
      visited
    in
    let reached_in c =
      let holders =
        Hashtbl.fold
          (fun k own acc -> if List.mem c own then k :: acc else acc)
          env.own_cap_closures []
      in
      let non_main = List.filter (fun k -> k <> "main") holders in
      match List.filter (Hashtbl.mem reachable_from_main) non_main with
      | k :: _ -> Some k
      | [] ->
        (match non_main with
         | k :: _ -> Some k
         | [] -> (match holders with k :: _ -> Some k | [] -> None))
    in
    List.iter
      (fun c ->
         if not (cap_subsumes "IO" c) then ()  (* FFI root; not this lattice *)
         else if cap_subsumes "IO.Foreign" c && grant <> "IO" then
           Err.error env.errors ~span
             (Printf.sprintf
                "`main` is granted `Cap(%s)`, but the program reaches `%s` — \
                 linked C code, whose behavior the capability lattice cannot \
                 bound. A narrow grant cannot be certified over an `extern` \
                 block.\n\
                 help: grant `Cap(IO)` instead, or remove the extern \
                 dependency from everything `main` reaches."
                grant c)
         else if not (cap_subsumes grant c) then
           Err.error env.errors ~span
             (Printf.sprintf
                "`main` is granted `Cap(%s)`, but the program reaches `%s`%s. \
                 The grant is a ceiling on the WHOLE program — declaring \
                 `needs %s` does not raise it.\n\
                 help: widen the grant (e.g. `Cap(IO)`), or remove the use."
                grant c
                (match reached_in c with
                 | Some f -> Printf.sprintf " (reached in `%s`)" f
                 | None -> "")
                c))
      (List.sort_uniq String.compare closure)

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
  let rec prebind_mod_members ?(opaque = StringSet.empty) prefix env decls =
    (* Opaque type names per submodule, taken from a sibling `sig <Mod>`
       declaration.  A type a signature exports opaquely (`type Stack a`, no
       constructors) must keep its constructors HIDDEN outside the module — so
       the bare-constructor seeding below is suppressed for them, matching the
       Pass-2 export filter (:7467) and preserving order-independence (hidden
       ctors stay unreferenceable cross-module by design). *)
    let sub_opaque =
      List.fold_left (fun m d -> match d with
        | Ast.DSig (sname, sdef, _) ->
          let ts = List.fold_left (fun s ((tn : Ast.name), _) -> StringSet.add tn.Ast.txt s)
                     StringSet.empty sdef.Ast.sig_types in
          StrMap.add sname.Ast.txt ts m
        | _ -> m) StrMap.empty decls in
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
          let e1 =
            let e = if StrMap.mem qname e.types then e
              else { e with types = StrMap.add qname (List.length params) e.types } in
            (* Register the BARE type name too, not just the module-qualified
               one.  A submodule of a cyclically-dependent module set (e.g.
               `Conduit.WorkflowContext` referencing `WorkflowError`, defined in
               parent `Conduit`) has no `use`/`import` and resolves the parent's
               types by bare name.  With only the qualified key seeded in Pass 1,
               the bare form was registered lazily during the definer's Pass-2
               check — so a referrer checked BEFORE the definer failed, making
               resolution depend on check order (which a cyclic module graph
               cannot make deterministic).  Top-level types (:8929) and records
               (below) already seed the bare name here; this closes the gap for
               nested-module types.  Don't clobber a bare name already bound by a
               top-level/entry definition. *)
            if StrMap.mem name.txt e.types then e
            else { e with types = StrMap.add name.txt (List.length params) e.types } in
          (match typedef with
           | Ast.TDVariant variants ->
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             List.fold_left (fun acc (v : Ast.variant) ->
                 let qctor = prefix ^ "." ^ v.var_name.txt in
                 (* [ci_type] is the BARE type name, matching check_decl (:7217)
                    and the top-level Pass-1 path (:8929).  Using the qualified
                    [qname] here was the sole site producing a qualified nominal
                    type for a constructor: a cross-module fully-qualified
                    reference (`Conduit.Telemetry.JobEnqueued`) resolved through
                    this prebind entry BEFORE the definer's Pass-2 check yielded
                    `TCon("Conduit.Telemetry.ConduitTelemetryEvent")`, which does
                    not unify with the bare `ConduitTelemetryEvent` that every
                    signature uses ("expected X but got Mod.X").  The type side
                    already canonicalizes qualified->bare (see [canon_name]); the
                    constructor side must agree by carrying the bare type. *)
                 let ci = { ci_type = name.txt; ci_params = param_names;
                            ci_arg_tys = v.var_args; ci_module = prefix; ci_vis = v.var_vis;
                            ci_is_actor_msg = false } in
                 (* Only seed the bare module-qualified ctor key (`Mod.Ctor`)
                    for PUBLIC constructors.  A private constructor — notably an
                    `opaque type`'s, whose variants the parser marks Private
                    while keeping the type Public — must stay unreferenceable
                    from a sibling module, or `Mod.Ctor(...)` from outside would
                    typecheck clean and bypass the opacity boundary.  The
                    disambiguated `Mod.Type.Ctor` key below is already gated the
                    same way; the Pass-2 DMod export step also keeps only public
                    ctors, but it StrMap.unions over this Pass-1 entry, so an
                    ungated bare key here would survive and defeat that filter. *)
                 let acc =
                   if v.var_vis = Ast.Public
                   then { acc with ctors = add_ctor qctor ci acc.ctors }
                   else acc in
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
                                   ci_arg_tys = v.var_args; ci_module = prefix; ci_vis = v.var_vis;
                                   ci_is_actor_msg = false } in
                   let acc = { acc with ctors = add_ctor type_qctor type_ci acc.ctors } in
                   (* A type exported opaquely by a sibling `sig` keeps its
                      constructors hidden: don't seed the short (bare / bare-type)
                      forms that would let a cross-module reference reach them. *)
                   if StringSet.mem name.txt opaque then acc
                   else
                     (* The disambiguation form written in code uses the BARE type
                        name (`WorkflowError.Failed`), not the module-qualified
                        type (`Conduit.WorkflowError.Failed`).  The top-level path
                        (:8929 `qual_key`) seeds this bare-type key; nested-module
                        types need it too, else a cross-module `Type.Ctor`
                        reference stays order-dependent even after the bare-ctor
                        key is seeded. *)
                     let bare_type_qctor = name.txt ^ "." ^ v.var_name.txt in
                     let acc = { acc with ctors = add_ctor bare_type_qctor type_ci acc.ctors } in
                     (* Seed the BARE constructor key with the same [ci_type =
                        name.txt] the top-level path (:8929) and check_decl use, so
                        a cross-module bare reference (e.g. `StorageError` from a
                        sibling of the defining `Conduit` module) resolves
                        regardless of check order.  add_ctor dedups by ci_type, so
                        this is a no-op once the definer's Pass-2 check registers
                        the same bare key — it does not manufacture a spurious
                        "defined by multiple types" ambiguity. *)
                     { acc with ctors = add_ctor v.var_name.txt type_ci acc.ctors }
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
          let child_opaque = Option.value ~default:StringSet.empty
              (StrMap.find_opt mname.Ast.txt sub_opaque) in
          prebind_mod_members ~opaque:child_opaque (prefix ^ "." ^ mname.txt) e inner_decls
        | _ -> e
      ) env decls
  in
  (* Pass 1: forward-reference placeholders for functions and type/ctor names *)
  (* Opaque type names per top-level module, from sibling `sig <Mod>` decls: the
     entry module is unwrapped so its `sig`/`mod` pairs are siblings here, not
     inside [prebind_mod_members] (see the same map built there). *)
  let top_sub_opaque =
    List.fold_left (fun m d -> match d with
      | Ast.DSig (sname, sdef, _) ->
        let ts = List.fold_left (fun s ((tn : Ast.name), _) -> StringSet.add tn.Ast.txt s)
                   StringSet.empty sdef.Ast.sig_types in
        StrMap.add sname.Ast.txt ts m
      | _ -> m) StrMap.empty m.Ast.mod_decls in
  let pre_env = List.fold_left (fun env d ->
      match d with
      | Ast.DFn (def, _) ->
        (* Record the name as locally defined so bulk imports cannot clobber
           its binding (local definitions shadow imports — see env.local_fns). *)
        let arity = match def.fn_clauses with
          | c :: _ -> List.length c.Ast.fc_params | [] -> 0 in
        (* Don't shadow existing bindings (e.g., builtins) with mono forward refs.
           bind_var FIRST (it clears any shadowed fn_arities entry), then register
           this fn's own arity so the entry survives — see bind_var's comment. *)
        let env =
          if StrMap.mem def.fn_name.txt env.vars then env
          else bind_var def.fn_name.txt (Mono (fresh_var 1)) env in
        { env with local_fns = StrMap.add def.fn_name.txt () env.local_fns;
                   fn_arities = StrMap.add def.fn_name.txt (arity, def.fn_name.span) env.fn_arities }
      | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
        (* Pre-bind all public qualified names "ModName.fn" so that sibling
           modules that reference each other don't fail during pass 2. *)
        let child_opaque = Option.value ~default:StringSet.empty
            (StrMap.find_opt mname.Ast.txt top_sub_opaque) in
        let env = prebind_mod_members ~opaque:child_opaque mname.txt env inner_decls in
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
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
                        ; ci_module  = m.Ast.mod_name.txt
                        ; ci_vis     = v.var_vis
                        ; ci_is_actor_msg = false } in
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
          add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_module = m.Ast.mod_name.txt; ci_vis = Ast.Public;
                              ci_is_actor_msg = false }
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
                       ci_arg_tys = arg_tys; ci_module = m.Ast.mod_name.txt; ci_vis = Ast.Public;
                       ci_is_actor_msg = true } in
            { acc_env with ctors = add_ctor h.ah_msg.txt ci acc_env.ctors }
          ) env1 actor.actor_handlers
      | Ast.DSig (name, sdef, _) ->
        { env with sigs = (name.txt, sdef) :: env.sigs }
      | Ast.DInterface (idef, _) ->
        { env with interfaces = StrMap.add idef.iface_name.txt idef env.interfaces }
      | Ast.DImpl (idef, _) ->
        register_impl_shape env idef ~decl_module:m.Ast.mod_name.txt
      | Ast.DMod (mname, _, inner_decls, _) ->
        (* Interface implementations declared in sibling modules must be
           visible unit-wide regardless of the order modules are checked in:
           CInterface constraints discharge at declaration boundaries, so an
           impl that is only registered when its defining module is reached
           cannot satisfy constraints from modules checked earlier. *)
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
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
  let pre_env =
    { pre_env with
      current_module = m.Ast.mod_name.txt;
      enclosing_package =
        (if pre_env.enclosing_package = "" then m.Ast.mod_name.txt
         else pre_env.enclosing_package) } in
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
  check_json_cap_sites final_env;
  check_cap_narrow_sites final_env;
  (* Validate capability declarations for the top-level module *)
  (* The entry module's own name is NOT a prefix segment for cap-closure keys:
     TIR unwraps the entry module (see [lib/tir/lower.ml]'s [mod_prefix]
     accumulation, which starts empty at the entry level), so top-level
     functions are keyed by their bare name and nested DMod functions are
     keyed starting from that nested module's own name (e.g. "Lib.Sub.f"),
     never "EntryName.Lib.Sub.f". *)
  check_module_needs final_env m.Ast.mod_name m.Ast.mod_decls
    ~cap_qname_prefix:"";
  (* R1: hold the program's capability closure under main's grant. *)
  check_main_grant final_env m.Ast.mod_decls;
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

(** Like [check_module], but also returns every resolved call/ctor/type
    reference recorded during checking — used by [forge search --callers].
    Order is call-order, most-recent-first is reversed back to source order. *)
let check_module_with_refs ?errors (m : Ast.module_)
    : Err.ctx * (Ast.span, ty) Hashtbl.t * ref_record list =
  let (errs, type_map, final_env) = check_module_core ?errors m in
  (errs, type_map, List.rev !(final_env.refs))

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
  (* R2: the REPL has no entry point to be granted the root capability from, so
     [root_cap] stays nameable there.  This entry point is the REPL's — its
     only caller is [lib/jit/repl_jit.ml] — which is what makes it the right
     place to carry the exemption rather than a flag threaded from the CLI. *)
  let env = { env with root_cap_allowed = true } in
  let errors = env.errors in
  let type_map = env.type_map in
  let rec prebind_mod_members_inc ?(opaque = StringSet.empty) prefix e decls =
    (* See [prebind_mod_members]: suppress bare-constructor seeding for types a
       sibling `sig` exports opaquely. *)
    let sub_opaque =
      List.fold_left (fun m d -> match d with
        | Ast.DSig (sname, sdef, _) ->
          let ts = List.fold_left (fun s ((tn : Ast.name), _) -> StringSet.add tn.Ast.txt s)
                     StringSet.empty sdef.Ast.sig_types in
          StrMap.add sname.Ast.txt ts m
        | _ -> m) StrMap.empty decls in
    List.fold_left (fun e d ->
        match d with
        | Ast.DFn (def, _) when def.fn_vis = Ast.Public ->
          let qname = prefix ^ "." ^ def.fn_name.txt in
          if StrMap.mem qname e.vars then e
          else bind_var qname (Mono (fresh_var 0)) e
        | Ast.DType (vis, name, params, typedef, _)
        | Ast.DAlwaysLinearType (vis, name, params, typedef, _) when vis = Ast.Public ->
          let qname = prefix ^ "." ^ name.txt in
          let e1 =
            let e = if StrMap.mem qname e.types then e
              else { e with types = StrMap.add qname (List.length params) e.types } in
            (* Register the BARE type name too, not just the module-qualified
               one.  A submodule of a cyclically-dependent module set (e.g.
               `Conduit.WorkflowContext` referencing `WorkflowError`, defined in
               parent `Conduit`) has no `use`/`import` and resolves the parent's
               types by bare name.  With only the qualified key seeded in Pass 1,
               the bare form was registered lazily during the definer's Pass-2
               check — so a referrer checked BEFORE the definer failed, making
               resolution depend on check order (which a cyclic module graph
               cannot make deterministic).  Top-level types (:8929) and records
               (below) already seed the bare name here; this closes the gap for
               nested-module types.  Don't clobber a bare name already bound by a
               top-level/entry definition. *)
            if StrMap.mem name.txt e.types then e
            else { e with types = StrMap.add name.txt (List.length params) e.types } in
          (match typedef with
           | Ast.TDVariant variants ->
             let param_names = List.map (fun (p : Ast.name) -> p.txt) params in
             List.fold_left (fun acc (v : Ast.variant) ->
                 let qctor = prefix ^ "." ^ v.var_name.txt in
                 (* [ci_type] is the BARE type name, matching check_decl (:7217)
                    and the top-level Pass-1 path (:8929).  Using the qualified
                    [qname] here was the sole site producing a qualified nominal
                    type for a constructor: a cross-module fully-qualified
                    reference (`Conduit.Telemetry.JobEnqueued`) resolved through
                    this prebind entry BEFORE the definer's Pass-2 check yielded
                    `TCon("Conduit.Telemetry.ConduitTelemetryEvent")`, which does
                    not unify with the bare `ConduitTelemetryEvent` that every
                    signature uses ("expected X but got Mod.X").  The type side
                    already canonicalizes qualified->bare (see [canon_name]); the
                    constructor side must agree by carrying the bare type. *)
                 let ci = { ci_type = name.txt; ci_params = param_names;
                            ci_arg_tys = v.var_args; ci_module = prefix; ci_vis = v.var_vis;
                            ci_is_actor_msg = false } in
                 (* Only seed the bare module-qualified ctor key (`Mod.Ctor`)
                    for PUBLIC constructors.  A private constructor — notably an
                    `opaque type`'s, whose variants the parser marks Private
                    while keeping the type Public — must stay unreferenceable
                    from a sibling module, or `Mod.Ctor(...)` from outside would
                    typecheck clean and bypass the opacity boundary.  The
                    disambiguated `Mod.Type.Ctor` key below is already gated the
                    same way; the Pass-2 DMod export step also keeps only public
                    ctors, but it StrMap.unions over this Pass-1 entry, so an
                    ungated bare key here would survive and defeat that filter. *)
                 let acc =
                   if v.var_vis = Ast.Public
                   then { acc with ctors = add_ctor qctor ci acc.ctors }
                   else acc in
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
                                   ci_arg_tys = v.var_args; ci_module = prefix; ci_vis = v.var_vis;
                                   ci_is_actor_msg = false } in
                   let acc = { acc with ctors = add_ctor type_qctor type_ci acc.ctors } in
                   (* A type exported opaquely by a sibling `sig` keeps its
                      constructors hidden: don't seed the short (bare / bare-type)
                      forms that would let a cross-module reference reach them. *)
                   if StringSet.mem name.txt opaque then acc
                   else
                     (* The disambiguation form written in code uses the BARE type
                        name (`WorkflowError.Failed`), not the module-qualified
                        type (`Conduit.WorkflowError.Failed`).  The top-level path
                        (:8929 `qual_key`) seeds this bare-type key; nested-module
                        types need it too, else a cross-module `Type.Ctor`
                        reference stays order-dependent even after the bare-ctor
                        key is seeded. *)
                     let bare_type_qctor = name.txt ^ "." ^ v.var_name.txt in
                     let acc = { acc with ctors = add_ctor bare_type_qctor type_ci acc.ctors } in
                     (* Seed the BARE constructor key with the same [ci_type =
                        name.txt] the top-level path (:8929) and check_decl use, so
                        a cross-module bare reference (e.g. `StorageError` from a
                        sibling of the defining `Conduit` module) resolves
                        regardless of check order.  add_ctor dedups by ci_type, so
                        this is a no-op once the definer's Pass-2 check registers
                        the same bare key — it does not manufacture a spurious
                        "defined by multiple types" ambiguity. *)
                     { acc with ctors = add_ctor v.var_name.txt type_ci acc.ctors }
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
          let child_opaque = Option.value ~default:StringSet.empty
              (StrMap.find_opt mname.Ast.txt sub_opaque) in
          prebind_mod_members_inc ~opaque:child_opaque (prefix ^ "." ^ mname.txt) e inner_decls
        | _ -> e
      ) e decls
  in
  (* Pass 1: forward-reference placeholders for new declarations *)
  let top_sub_opaque =
    List.fold_left (fun m d -> match d with
      | Ast.DSig (sname, sdef, _) ->
        let ts = List.fold_left (fun s ((tn : Ast.name), _) -> StringSet.add tn.Ast.txt s)
                   StringSet.empty sdef.Ast.sig_types in
        StrMap.add sname.Ast.txt ts m
      | _ -> m) StrMap.empty m.Ast.mod_decls in
  let pre_env = List.fold_left (fun env d ->
      match d with
      | Ast.DFn (def, _) ->
        if StrMap.mem def.fn_name.txt env.vars then env
        else bind_var def.fn_name.txt (Mono (fresh_var 0)) env
      | Ast.DMod (mname, Ast.Public, inner_decls, _) ->
        (* Register the sibling module's members, then its interface impls — an
           impl declared in a sibling must satisfy constraints unit-wide
           regardless of check order (mirrors check_module_core's pass 1). *)
        let child_opaque = Option.value ~default:StringSet.empty
            (StrMap.find_opt mname.Ast.txt top_sub_opaque) in
        let env = prebind_mod_members_inc ~opaque:child_opaque mname.txt env inner_decls in
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
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
                        ; ci_module  = m.Ast.mod_name.txt
                        ; ci_vis     = v.var_vis
                        ; ci_is_actor_msg = false } in
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
          add_ctor name.txt { ci_type = name.txt; ci_params = []; ci_arg_tys = []; ci_module = m.Ast.mod_name.txt; ci_vis = Ast.Public;
                              ci_is_actor_msg = false }
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
                       ci_arg_tys = arg_tys; ci_module = m.Ast.mod_name.txt; ci_vis = Ast.Public;
                       ci_is_actor_msg = true } in
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
  let bindings, pat_ty = infer_pattern ~expected:t_ok env' p in
  unify env' ~span:sp ~reason:(Some (RLetBind sp)) t_ok pat_ty;
  ignore (leave_level env');
  bind_vars bindings env
