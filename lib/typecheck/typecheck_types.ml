(** March's internal type language, and how it is printed.

    [reason] provenance chains, [ty] / [session_ty] / [tvar] / [scheme], fresh
    variable generation, [repr] / [occurs], the tvar and record display tables,
    [pp_ty] and friends, and the Elm-style [message_part] / [render_parts]
    renderer.  Lifted verbatim out of [Typecheck] (§1–§6) on 2026-08-26;
    measured with the decomposition plan's [dep.py], the band has **zero**
    dependencies on anything else in that file.

    This is the module the 2026-08-23 review named as the blocker for
    extracting anything else: [pp_ty] and [builtin_bindings] are coupled to
    [ty], so nothing above them could move until [ty] had a home.  It is also
    the cheapest extraction in the file.

    It carries the three module aliases [Typecheck] used to declare itself
    ([Ast], [Err], [StringSet]); [Typecheck] regains them, along with
    everything else here, through [include Typecheck_types].

    **The mutable cells are aliased, not copied.**  [_counter], [_tvar_names]
    and [_record_names] are [ref]s and [Hashtbl]s, and [include] re-exports the
    same physical cells — which matters because [bin/main.ml] marshals
    [March_typecheck.Typecheck._counter] and [._record_names] into the stdlib
    typecheck-env cache.  A duplicated cell there reproduces the cross-run
    nondeterminism fixed in
    specs/progress/2026-08-24-interp-perf-phase-3-startup-tcenv-cache.md.

    See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 6,
    Task 6.3). *)

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

(** Reset the tvar → display-name cache. Display names are purely
    presentational (unlike [_counter], the actual fresh-id source, which
    must stay monotonic for unification correctness and is intentionally
    never reset — see the file header). A one-shot CLI run never needs this:
    the process exits after one [check_module]. A long-lived process that
    calls [check_module] repeatedly against an unchanging id space — the
    LSP, re-typechecking on every edit — does: left alone, [_tvar_ctr] climbs
    for the process's entire lifetime, so an unresolved type variable in a
    20-line file can print as `y55` instead of `a`. Call this once per
    analysis pass, before rendering its diagnostics, so each pass's fresh
    variables again start naming from "a". *)
let reset_tvar_display_names () =
  Hashtbl.reset _tvar_names;
  _tvar_ctr := 0

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

(* ─────────────────────────────────────────────────────────────────
   [span_of_expr] was §14's first definition in typecheck.ml.  It is a pure
   AST accessor with zero dependencies, and the pattern-exhaustiveness band
   (Typecheck_exhaustive) — which sits ABOVE inference and therefore above
   §14 — needs it.  Moved here rather than into Typecheck_exhaustive because
   typecheck.ml itself still has seven call sites for it and it is declared in
   typecheck.mli.  This is a REORDER, not a prefix cut: verified that nothing
   between its old and new positions references it (Typecheck_types,
   Typecheck_env and Typecheck_builtins all contain zero occurrences).
   ───────────────────────────────────────────────────────────────── *)

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
  | Ast.ELetStar (_, _, _, sp) -> sp
  | Ast.EAssert (_, sp)         -> sp
  | Ast.ESigil (_, _, sp)       -> sp

(* ─────────────────────────────────────────────────────────────────
   [free_vars_expr] / [free_vars_block] / [free_vars_pattern] were §15's first
   definitions in typecheck.ml.  Like [span_of_expr] above they are pure AST
   walkers with zero dependencies ([dep.py] → 0), and the capability / [needs]
   band (Typecheck_caps) needs them.

   The decomposition plan proposed carrying them INTO Typecheck_caps in the
   same commit.  That does not work and the plan did not check it:
   [warn_unused_params] sits between these definitions and the capability
   band and calls [free_vars_expr], so moving them down past it would leave
   that call unresolved.  They go here instead — a module included at the TOP
   of typecheck.ml — which serves every caller on both sides of the caps
   band.  Verified: the only definitions between their old and new positions
   are in Typecheck_types, Typecheck_env, Typecheck_builtins,
   Typecheck_exhaustive and Typecheck_tailcall, none of which references them.
   ───────────────────────────────────────────────────────────────── *)

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
  | Ast.ELetQ (p, result, cont, _) | Ast.ELetStar (p, result, cont, _) ->
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
