(** Perceus Phase 2 core — the [env] threaded through RC insertion, the
    fresh-RC-variable counter, the small env-consuming helpers, and
    [insert_rc_expr] itself.

    Moved VERBATIM out of [Perceus] (finding 3 of
    [specs/2026-08-25-file-decomposition-analysis.md]).  [Perceus] pulls it
    back in with a single [include Perceus_core], so [perceus.mli] — which
    exports [env] as a CONCRETE record plus ~18 values — is unchanged and no
    caller moved.  [include] rather than the alias idiom the [Lower_*] family
    uses, precisely because the .mli exports these names: aliasing would have
    meant repeating the 123-line [env] record in a second place.

    ── Why this band could move, when Wave 3 Task 5 stopped here ────────────

    Task 5 split out the four phases that did NOT need [env]
    ([Perceus_liveness], [Perceus_elide], [Perceus_fbip], [Perceus_scrut]),
    and deliberately left [env] + Phase 2 behind.  This module takes the
    remaining step by moving [env] ITSELF, which is what lets the Phase 2
    core follow it.  The direction of every existing dependency is unchanged:
    none of the four Task 5 modules gains a dependency on this one, and this
    one does not depend on [Perceus] — dune would reject either as a cycle.

    [_rc_fresh_ctr] moved here with [fresh_rc_var], its only producer.  Its
    reset (`_rc_fresh_ctr := 0`) still lives in [Perceus.perceus]; through
    the [include] that is the SAME ref cell, so per-run determinism of the
    `$rc_N` names — which the TIR golden snapshots depend on — is unchanged. *)

module StringSet = Set.Make (String)
module StringMap = Map.Make (String)

(* ── Fresh variable counter for RC restructuring ─────────────────────────── *)

let _rc_fresh_ctr = ref 0

let fresh_rc_var (ty : Tir.ty) : Tir.var =
  incr _rc_fresh_ctr;
  { Tir.v_name = Printf.sprintf "$rc_%d" !_rc_fresh_ctr;
    v_ty = ty; v_lin = Tir.Unr }

(* ── Env — immutable state threaded through insert_rc_expr (Wave 3 Task 4) ──

   Replaces the module-level mutable refs that a prior version of this file
   used.  Each field below documents the ref it replaces and that ref's
   scoping discipline, which the corresponding field preserves EXACTLY:

   - Module-scoped fields ([borrow_map], [type_defs], [extern_names]): set
     once per [perceus] run, read-only for the whole traversal.  No
     save/restore needed — every [insert_rc_expr] call for every function in
     the module sees the identical value.
   - Function-scoped fields ([current_fn_name], [closure_fvs], [actor_sent]):
     set once per top-level [insert_rc] call, constant across that function's
     entire [insert_rc_expr] traversal (nested [ELetRec] closures reuse the
     SAME env — they are not separately entered via [insert_rc], matching the
     old refs' behavior of never being reset mid-traversal for nested fns).
   - Subtree-scoped fields ([borrowed_field_vars], [var_ctx]): change as the
     traversal descends into [ELet] bindings / [ECase] branches.  Each
     recursive call receives an [env] with the field already updated
     (`{ env with field = ... }`), which is exactly the save/restore dance the
     old code performed by hand — the "restore" is implicit because the
     caller's own [env] value is never touched; only the callee's copy
     differs. *)
type env = {
  (* Module-scoped: constant for the whole [perceus] run. *)
  borrow_map : Borrow.borrow_map;
      (** The current module's borrow map (was [_borrow_map]). *)
  type_defs : Tir.type_def list;
      (** Module type definitions, used to query whether a matched
          scrutinee's constructor shares its heap object with the bound
          payload (newtype/niche representations).  Was [_type_defs]. *)
  collision_set : (string, string list) Hashtbl.t;
      (** Same-short-name type collision set (Task 2, [Collision_set.compute]),
          derived from [type_defs] once per [perceus] run (mirrors
          [Llvm_ctx.make_ctx]'s derivation).  Threaded into
          [Repr.repr_of_ty]/[Repr.is_niche_shaped] so
          [scrutinee_shares_payload_storage] agrees with codegen's
          Boxed/Niche/Newtype classification for a colliding type — an
          agreement gap here would double-free or leak the scrutinee's heap
          object (see that function's doc comment). *)
  extern_names : StringSet.t;
      (** Names of user-defined extern (FFI) functions.  These are called via
          [ECallPtr] (not [EApp]) but, unlike opaque closures, their
          parameter ownership is known from the borrow map (seeded in
          [Borrow.infer_module]).  Used in the [ECallPtr] case to apply
          borrow-aware RC — borrowed args are not consumed by the callee, so
          the caller frees dead-after args.  Was [_extern_names]. *)
  (* Function-scoped: constant across one function's traversal. *)
  current_fn_name : string;
      (** Name of the function currently being processed by [insert_rc].
          Used in the EApp case to detect self-recursive calls, so that
          ESeq(EApp(self,...), EDecRC(arg)) is left intact for TCO to handle
          (the EDecRC becomes dead code after the back-edge is emitted).
          Was [_current_fn_name]. *)
  closure_fvs : StringSet.t;
      (** Closure free-variable names for the function currently being
          processed.  Variables in this set are bound by [let fv =
          $clo.$fvN] in apply functions.  They are OWNED by the closure, not
          by the apply function body.  The closure's RC keeps them alive for
          the duration of every call, so:
          - They must NOT be decreffed at last use (suppresses
            post_dec_vars).
          - They must NOT be increffed when passed as arguments (suppresses
            find_inc_vars).
          - A dead binding of such a variable must NOT emit EDecRC / EFree.
          Removing these RC ops also eliminates the data race between the
          non-atomic [march_decrc_local] in the generated apply function and
          the atomic [march_incrc] in the C HTTP runtime's per-request
          incref loop.  Was [_closure_fvs]. *)
  actor_sent : StringSet.t;
      (** Variables that appear as message arguments to [send()] in the
          current function.  Values in this set use atomic RC operations.
          Was [_actor_sent]. *)
  moved_vars : StringSet.t;
      (** Variables whose ownership has been MOVED into a heap object by an
          [ESetField] anywhere in the current function (the TRMC hole-fill).

          The store transfers the reference: the object's field now holds it,
          and the object's own lifetime releases it.  The mover must therefore
          never drop the value again — not at a dead binding, not at a branch
          end, and in particular not as a post-call [EDecRC] when the value is
          subsequently passed at a borrowed parameter position.

          That last case is the one that bites.  In a TRMC loop the freshly
          allocated cell is stored into the parent's hole and then handed to
          the recursive call as its destination; borrow inference correctly
          marks the destination parameter borrowed, so the caller-side
          "borrowed arg at its last use" rule fires and emits a drop after the
          call.  That drop releases a cell the parent now owns through its
          field, AND it knocks the recursive call out of tail position so
          [Llvm_tco] can no longer form a loop — which is the entire point of
          the transformation.

          Function-scoped and computed once by [collect_moved_vars]: a
          conservative whole-body set is correct here because a value may be
          moved on one path and dropped on another, and suppressing the drop
          on every path is the safe direction (the object owns it either way). *)
  (* Subtree-scoped: updated on descent into ELet bindings / ECase branches. *)
  borrowed_field_vars : StringSet.t;
      (** Variables that were extracted from a borrowed record/tuple
          parameter via EField and are therefore themselves borrowed
          references.  Perceus must not emit EDecRC, EIncRC, or post-call
          EDecRC for these variables:
          - The record owner is responsible for the fields' RC — the callee
            only reads them.
          - Emitting post_dec_vars for such a variable would underflow the
            field string's RC after every call inside a loop that re-uses
            the same record (the "process + use_cfg" RC underflow pattern).
          - Emitting EIncRC at non-last-use (the EAtom non-last-use path)
            would inflate the RC without a matching decrement, leaking the
            value.

          Populated dynamically in [insert_rc_expr]'s ELet case when the
          binding is of the form [let v = src.field] where [src] is itself
          in [live_after] (the record outlives this binding) or [src] is
          already in [borrowed_field_vars] (alias chain propagation: [let v
          = borrowed_field]).  Each ELet scope descends with its own updated
          copy of this field so inner bindings do not contaminate the
          caller's [env] (was: saved/restored via [_borrowed_field_vars]). *)
  var_ctx : Tir.var StringMap.t;
      (** Variable context: maps each in-scope variable name to its
          [Tir.var] record, giving the type needed to emit correct
          EDecRC/EIncRC ops.
          - Populated in [insert_rc] with the current function's parameters.
          - Extended in [insert_rc_expr]'s ELet case for each let-bound
            variable (descending with an updated copy to handle shadowing
            correctly).
          Used by the ECase cross-branch dead-variable EDecRC pass:
          variables that are in scope at a case expression and live in
          *some* branches but dead in *others* need EDecRC in the dead
          branches.  Without this, owned parameters whose last use is
          inside an ECase arm do not get decremented in arms where they are
          unused — causing both reference leaks and (via RC imbalance in
          complex HOF call chains) use-after-free crashes.

          Example: [Map.node_fold(..., f)] where [f : TFn] is unused in the
          HEmpty arm.  Without cross-branch EDecRC, [f] leaks in every
          HEmpty arm visit.  In deep HAMTs this accumulates enough
          misbalance to produce a use-after-free when the go-closure's
          function-pointer slot is misread as a Bytes payload pointer,
          triggering the observed march_decrc crash.  Was [_var_ctx]. *)
}

(** The env used before any module has been processed / after [perceus]
    finishes with a function — mirrors the old refs' initial values
    ([Borrow.empty], [[]], [StringMap.empty], [StringSet.empty], ...). *)
let empty_env : env = {
  borrow_map = Borrow.empty;
  type_defs = [];
  collision_set = Hashtbl.create 0;
  extern_names = StringSet.empty;
  current_fn_name = "";
  closure_fvs = StringSet.empty;
  actor_sent = StringSet.empty;
  moved_vars = StringSet.empty;
  borrowed_field_vars = StringSet.empty;
  var_ctx = StringMap.empty;
}

(** True when a value of type [ty] shares its heap object with the payload of
    its single relevant constructor — i.e. newtype- (S(x)≡x) or niche-
    (Some(x)≡x, None≡0) represented.  For such types a pattern match does NOT
    project a child out of a distinct container cell: the bound branch variable
    IS the scrutinee object.  Freeing the scrutinee separately would therefore
    double-free the object the branch variable now owns — the cause of the
    Toml get_str / nested-Option RC underflow. *)
let scrutinee_shares_payload_storage (env : env) (ty : Tir.ty) : bool =
  match Repr.repr_of_ty ~collision_set:env.collision_set env.type_defs ty with
  | Repr.Newtype _ | Repr.Niche _ -> true
  | Repr.Boxed ->
    (* Erased-niche recovery — must mirror [llvm_case.ml]'s [effective_repr]
       abstract-arg path.  [repr_of_ty] conservatively returns [Boxed] for a
       niche-shaped type applied to abstract (TVar) arguments — e.g.
       [TCon("Option", [TVar "_35129"])], produced when a value crosses a
       fully-polymorphic boundary such as [actor_call]'s reply — because
       [niche_payload_ok(TVar)] is false.  But codegen recovers [Niche] for
       exactly this shape (the ctor layout is fixed by the type NAME), so the
       runtime value shares storage with its payload (Some(x) ≡ x).  Perceus
       must agree, or [add_scrutinee_free_for] would treat the value as a
       distinct boxed cell and hand it to FBIP for whole-cell reuse — writing
       the payload (which aliases the scrutinee) into its own reused cell: a
       self-referential object → RC underflow / use-after-free.  See
       docs/value-representation.md §7 (erased Option payloads stay NICHE at
       every commitment site). *)
    (match ty with
     | Tir.TCon (name, args)
       when args <> []
            && List.exists (function Tir.TVar _ -> true | _ -> false) args
            && Repr.is_niche_shaped ~collision_set:env.collision_set env.type_defs name -> true
     | _ -> false)

(** Collect the names of variables loaded directly from the closure parameter
    [$clo] via EField.  Only apply functions have [$clo] as first param. *)
let collect_closure_fvs (fn : Tir.fn_def) : StringSet.t =
  match fn.Tir.fn_params with
  | p :: _ when String.equal p.Tir.v_name Tir_names.clo_param_name ->
    let clo_name = p.Tir.v_name in
    let rec scan e acc =
      match e with
      | Tir.ELet (v, Tir.EField (Tir.AVar src, _), rest)
        when String.equal src.Tir.v_name clo_name ->
        scan rest (StringSet.add v.Tir.v_name acc)
      | Tir.ELet (_, e1, e2) ->
        scan e2 (scan e1 acc)
      | Tir.ELetRec (fns, body) ->
        let from_fns = List.fold_left (fun a fd -> scan fd.Tir.fn_body a) acc fns in
        scan body from_fns
      | Tir.ESeq (e1, e2) ->
        scan e2 (scan e1 acc)
      | Tir.ECase (_, branches, default) ->
        let from_branches =
          List.fold_left (fun a br -> scan br.Tir.br_body a) acc branches
        in
        (match default with Some d -> scan d from_branches | None -> from_branches)
      | _ -> acc
    in
    scan fn.Tir.fn_body StringSet.empty
  | _ -> StringSet.empty

(** Collect the variables moved into a heap object by an [ESetField].  See
    [env.moved_vars] for why every such variable must be exempt from drops. *)
let collect_moved_vars (fn : Tir.fn_def) : StringSet.t =
  let acc = ref StringSet.empty in
  let rec go e =
    match e with
    | Tir.ESetField (_, _, Tir.AVar v) -> acc := StringSet.add v.Tir.v_name !acc
    | Tir.ESetField _ -> ()
    | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> go e1; go e2
    | Tir.ELetRec (fns, body) ->
      List.iter (fun (fd : Tir.fn_def) -> go fd.Tir.fn_body) fns; go body
    | Tir.ECase (_, branches, default) ->
      List.iter (fun (br : Tir.branch) -> go br.Tir.br_body) branches;
      Option.iter go default
    | _ -> ()
  in
  go fn.Tir.fn_body;
  !acc

(* ── Actor-send analysis ─────────────────────────────────────────────────── *)

(** Collect the set of variable names passed as messages to [send()].
    [send(actor, msg)] — msg is the 2nd argument. *)
let rec collect_actor_sent_vars (e : Tir.expr) : StringSet.t =
  match e with
  | Tir.EApp (f, [_; Tir.AVar msg])
    when String.equal f.Tir.v_name "send" ->
    StringSet.singleton msg.Tir.v_name
  | Tir.EApp _ -> StringSet.empty
  | Tir.EAtom _ | Tir.ECallPtr _ -> StringSet.empty
  | Tir.ELet (_, e1, e2) ->
    StringSet.union (collect_actor_sent_vars e1) (collect_actor_sent_vars e2)
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun acc fn ->
      StringSet.union acc (collect_actor_sent_vars fn.Tir.fn_body)
    ) (collect_actor_sent_vars body) fns
  | Tir.ECase (_, branches, default) ->
    let from_branches = List.fold_left (fun acc br ->
      StringSet.union acc (collect_actor_sent_vars br.Tir.br_body)
    ) StringSet.empty branches in
    let from_default = match default with
      | Some d -> collect_actor_sent_vars d
      | None -> StringSet.empty
    in
    StringSet.union from_branches from_default
  | Tir.ESeq (e1, e2) ->
    StringSet.union (collect_actor_sent_vars e1) (collect_actor_sent_vars e2)
  | _ -> StringSet.empty

(** Choose the appropriate IncRC variant for [v].
    Actor-sent vars use atomic; all others use local (non-atomic). *)
let incrc_for (env : env) (v : Tir.var) (a : Tir.atom) : Tir.expr =
  if StringSet.mem v.Tir.v_name env.actor_sent
  then Tir.EAtomicIncRC a
  else Tir.EIncRC a

(** Choose the appropriate DecRC variant for [v]. *)
let decrc_for (env : env) (v : Tir.var) (a : Tir.atom) : Tir.expr =
  if StringSet.mem v.Tir.v_name env.actor_sent
  then Tir.EAtomicDecRC a
  else Tir.EDecRC a

(* ── Helpers ─────────────────────────────────────────────────────────────── *)

(** Returns true if this type needs reference counting (heap-allocated).
    Canonical definition: [Rc_types.needs_rc] (Wave 3 Task 2). It
    deliberately diverges from [Rc_types.borrow_eligible] on
    TFn / bare TVar (true here) and TTuple / TRecord (false here) — see
    Rc_types's module doc for the full contract and fix history before
    changing any arm. *)
let needs_rc = Rc_types.needs_rc

(** True for a defunctionalized closure apply wrapper ("<fn>$apply$<uid>").
    An apply function's first parameter is the closure struct ([$clo]); the
    closure-apply ABI used by both [ECallPtr] dispatch and the [EApp] form
    that [Known_call] rewrites it into CONSUMES that closure argument
    (ownership transfers to the callee).  This must override any borrow-map
    classification of the [$clo] slot — see the EApp [post_dec_vars]
    computation.  Defined in [Tir_names] (Wave 3 Task 1 — was a byte-identical
    duplicate of [Llvm_emit.is_apply_fn] before this move; see
    [Tir_names.is_apply_fn] for the diff verdict). *)
let is_apply_fn = Tir_names.is_apply_fn

(** Returns the set of variable names referenced by an atom.
    Moved to [Perceus_liveness.vars_of_atom] (Wave 3 Task 5) — re-exported
    here for the many call sites in this file's Phase 2 core. *)
let vars_of_atom = Perceus_liveness.vars_of_atom

(** Union of all variable sets from a list of atoms.
    Moved to [Perceus_liveness.vars_of_atoms] (Wave 3 Task 5). *)
let vars_of_atoms = Perceus_liveness.vars_of_atoms

(** Marker prefix for the FBIP arity encoding minted below by
    [add_scrutinee_free_for] (this file's [insert_rc_expr], ECase case) and
    decoded by [Perceus_fbip.same_arity].  Moved to [Perceus_fbip] (Wave 3
    Task 5) — NOT kept here as originally planned: see that module's header
    comment for why the marker + its decoder [is_fbip_encoded] both live
    there while the PRODUCER (below, in this file's [insert_rc_expr]) reaches
    across to [Perceus_fbip.fbip_arity_marker] rather than the reverse
    (which would cycle, since [Perceus] already calls INTO [Perceus_fbip]
    for [insert_fbip]). Re-exported here so this file's existing producer
    code and doc comments can keep referring to the unqualified name. *)
let fbip_arity_marker = Perceus_fbip.fbip_arity_marker

(** Arity check for FBIP reuse — P8 extension.  Moved to
    [Perceus_fbip.same_arity] (Wave 3 Task 5); re-exported at this
    historical path because test/test_codegen.ml calls
    [March_tir.Perceus.same_arity] directly. *)
let same_arity = Perceus_fbip.same_arity

(* ── Phase 1: Backwards Liveness Analysis ────────────────────────────────── *)

(** Moved to [Perceus_liveness] (Wave 3 Task 5): [live_set], [live_before],
    [name_free_in] were already [env]-free before the Task 4 env-threading
    and needed no changes beyond module qualification to relocate.
    Re-exported here (types/values used throughout this file's Phase 2
    core, which retains the "Phase N" section comments below for
    continuity with the original single-file layout). *)
type live_set = Perceus_liveness.live_set

let live_before = Perceus_liveness.live_before

(* ── name_free_in (shared by Phase 2 and Phase 4) ─────────────────────────── *)

let name_free_in = Perceus_liveness.name_free_in

(* ── Phase 2: RC Insertion ────────────────────────────────────────────────── *)

(** Wrap [inner] with IncRC (atomic if actor-sent) for each variable in [incs]. *)
let wrap_incrcs (env : env) (incs : Tir.var list) (inner : Tir.expr) : Tir.expr =
  List.fold_right (fun v acc ->
    Tir.ESeq (incrc_for env v (Tir.AVar v), acc)
  ) incs inner

(** True for the heap aggregates that own their fields: records and tuples.
    Both are read only through [EField] (tuple destructuring lowers to
    [EField] with [$fv]N names, not to an ECase), so both need the scope-end
    drop in [insert_rc_expr]'s ELet case. *)
let is_aggregate_ty : Tir.ty -> bool = function
  | Tir.TTuple _ | Tir.TRecord _ -> true
  | _ -> false

(** Best-effort type of a TIR expression's value.  [None] means "could not
    determine", and every caller must treat that as a refusal to transform
    rather than a guess: the only consumer is the aggregate scope-end drop,
    which needs a correctly-typed temporary to rebind the scope's value, and a
    wrong type there is a miscompile (an i64 result stored through a ptr
    slot).  Refusing merely leaves that aggregate undropped. *)
let rec tir_expr_ty (e : Tir.expr) : Tir.ty option =
  match e with
  | Tir.EAtom (Tir.AVar w) -> Some w.Tir.v_ty
  | Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt _)) -> Some Tir.TInt
  | Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool _)) -> Some Tir.TBool
  | Tir.EAtom (Tir.ALit (March_ast.Ast.LitFloat _)) -> Some Tir.TFloat
  | Tir.EAtom (Tir.ALit (March_ast.Ast.LitString _)) -> Some Tir.TString
  | Tir.ELet (_, _, body) | Tir.ESeq (_, body) -> tir_expr_ty body
  | Tir.EApp (f, _) ->
    (match f.Tir.v_ty with Tir.TFn (_, r) -> Some r | _ -> None)
  | Tir.EField (Tir.AVar src, f) ->
    (match src.Tir.v_ty with
     | Tir.TRecord fs -> List.assoc_opt f fs
     | Tir.TTuple ts when Tir_names.is_fv_field f ->
       List.nth_opt ts (Tir_names.fv_field_index f)
     | _ -> None)
  | Tir.EAlloc (ty, _) | Tir.EStackAlloc (ty, _) -> Some ty
  | Tir.ERecord fs ->
    (* TRecord is sorted by field name; preserve that invariant. *)
    let named = List.filter_map (fun (n, a) ->
      match a with
      | Tir.AVar w -> Some (n, w.Tir.v_ty)
      | _ -> None) fs in
    if List.length named = List.length fs
    then Some (Tir.TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) named))
    else None
  | Tir.EUpdate (Tir.AVar src, _) -> Some src.Tir.v_ty
  | _ -> None

(** True when every occurrence of [name] in [e] is as the SOURCE of an
    [EField] projection — i.e. the aggregate is only ever read, never handed
    off.  This is the precondition for the scope-end drop: at any CONSUMING
    position (call argument, constructor / tuple / record capture, an atom in
    tail position) ownership transfers to the consumer, which becomes
    responsible for the release, and dropping here as well frees a cell the
    consumer still holds.

    [env.moved_vars] does not cover this: it did not stop the scope-end drop
    from firing on a record captured by an [EAlloc]
    (`alloc Box.Box(n, r); dec_rc r`), which freed the constructor's own field
    and crashed with SIGBUS. Rather than widen that set and change what it
    means for the rest of the pass, this predicate states the requirement
    directly and conservatively: anything that is not an EField source
    disqualifies the drop. *)
let rec used_only_as_field_source (name : string) (e : Tir.expr) : bool =
  let atom_hits = function
    | Tir.AVar w -> String.equal w.Tir.v_name name
    | _ -> false
  in
  let atoms_ok atoms = not (List.exists atom_hits atoms) in
  match e with
  (* The one permitted occurrence. *)
  | Tir.EField (Tir.AVar w, _) when String.equal w.Tir.v_name name -> true
  | Tir.EField (a, _) -> not (atom_hits a)
  | Tir.EAtom a -> not (atom_hits a)
  | Tir.EApp (f, args) -> not (String.equal f.Tir.v_name name) && atoms_ok args
  | Tir.ECallPtr (a, args) -> atoms_ok (a :: args)
  | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    atoms_ok atoms
  | Tir.ERecord fields -> atoms_ok (List.map snd fields)
  (* An EUpdate BASE is a read, like an EField source: emit_update copies the
     base's fields into a fresh cell and leaves the base intact, so ownership
     does not transfer and the base still needs its own drop.  The update
     VALUES are stored into the new cell and are consuming. *)
  | Tir.EUpdate (Tir.AVar w, fields) when String.equal w.Tir.v_name name ->
    atoms_ok (List.map snd fields)
  | Tir.EUpdate (a, fields) -> atoms_ok (a :: List.map snd fields)
  | Tir.EReuse (a, _, args) -> atoms_ok (a :: args)
  | Tir.EAllocHole (tok, _, filled, _) ->
    atoms_ok (match tok with Some a -> a :: filled | None -> filled)
  | Tir.ESetField (a, _, b) -> atoms_ok [a; b]
  | Tir.EIncRC a | Tir.EDecRC a | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a
  | Tir.EFree a -> not (atom_hits a)
  | Tir.ELet (_, e1, e2) ->
    used_only_as_field_source name e1 && used_only_as_field_source name e2
  | Tir.ESeq (e1, e2) ->
    used_only_as_field_source name e1 && used_only_as_field_source name e2
  | Tir.ECase (a, branches, default) ->
    (* A case SCRUTINEE is consumed (add_scrutinee_free_for may free it). *)
    not (atom_hits a)
    && List.for_all (fun br -> used_only_as_field_source name br.Tir.br_body)
         branches
    && (match default with
        | Some d -> used_only_as_field_source name d
        | None -> true)
  | Tir.ELetRec (fns, body) ->
    List.for_all (fun fn -> used_only_as_field_source name fn.Tir.fn_body) fns
    && used_only_as_field_source name body

(** True when [e] already contains a release of [name] on some path.  The
    aggregate scope-end drop must stand down in that case: [post_dec_vars]
    already emits a post-call dec for an aggregate passed to a borrowed
    parameter position, and adding a second one underflows the refcount (the
    runtime aborts on it).  Conservative in the safe direction — a dec on ONE
    branch suppresses the scope-end drop on all of them, which can leave the
    aggregate undropped on the others, never double-freed. *)
let rec releases_var (name : string) (e : Tir.expr) : bool =
  let atom_is = function
    | Tir.AVar w -> String.equal w.Tir.v_name name
    | _ -> false
  in
  match e with
  | Tir.EDecRC a | Tir.EAtomicDecRC a | Tir.EFree a -> atom_is a
  | Tir.ELet (_, e1, e2) -> releases_var name e1 || releases_var name e2
  | Tir.ESeq (e1, e2) -> releases_var name e1 || releases_var name e2
  | Tir.ECase (_, branches, default) ->
    List.exists (fun br -> releases_var name br.Tir.br_body) branches
    || (match default with Some d -> releases_var name d | None -> false)
  | Tir.ELetRec (fns, body) ->
    List.exists (fun fn -> releases_var name fn.Tir.fn_body) fns
    || releases_var name body
  | _ -> false

(** True when [name] is the value the expression evaluates to, i.e. it sits in
    tail position as a bare atom.  Used to suppress the aggregate scope-end
    drop for [let b = {..} in b], where ownership has already been transferred
    out by the tail EAtom and a dec here would double-free. *)
let rec tail_value_is_var (name : string) (e : Tir.expr) : bool =
  match e with
  | Tir.EAtom (Tir.AVar w) -> String.equal w.Tir.v_name name
  | Tir.ELet (_, _, body) -> tail_value_is_var name body
  | Tir.ESeq (_, body) -> tail_value_is_var name body
  | Tir.ECase (_, branches, default) ->
    List.exists (fun br -> tail_value_is_var name br.Tir.br_body) branches
    || (match default with
        | Some d -> tail_value_is_var name d
        | None -> false)
  | _ -> false

(** Determine which AVar atoms in a list need EIncRC because they are
    Unr, needs_rc, and still live after this use.
    Closure FVs are handled via the [borrowed] set in [insert_rc]: they are
    added to [borrowed] so they are always considered live, which causes this
    function to emit an EIncRC before any consuming (last-use) call.  That
    keeps the closure's reference alive regardless of how many times the apply
    function is invoked (i.e., when the closure's own RC > 1). *)
let find_inc_vars ?(include_borrowed_fields = true)
    (env : env) (atoms : Tir.atom list) (live_after : live_set) : Tir.var list =
  (* Every atom here is at a CONSUMING position (call arg, constructor / tuple /
     record capture, return).  The caller holds exactly ONE reference to an
     owned variable (its binding), but a variable may appear at [count]
     consuming positions in this single node — each takes ownership — and one
     reference must survive if it is still [live_after].  So the caller must
     emit  count - 1 + (live_after ? 1 : 0)  EIncRC ops for it.

     The previous version emitted one Inc per occurrence only when the variable
     was live_after, and none otherwise.  That under-dup'd a variable passed to
     SEVERAL consuming positions at once while dead afterwards — e.g. [f(x, x)],
     [Cons(x, x)], [(x, x)] — so each extra position DecRC'd a reference the
     caller never owned → RC underflow / double-free.  (Single-occurrence cases
     are unchanged: count-1+1 = 1 when live, count-1 = 0 when dead.)

     Borrowed field vars: the record owner holds their reference.  At a
     consuming position they must still be dup'd so the consumer's free does not
     invalidate the owner's reference.  At pure BORROW reads (EField projection)
     the caller passes ~include_borrowed_fields:false to keep that suppression. *)
  let eligible (v : Tir.var) : bool =
    v.Tir.v_lin = Tir.Unr
    && needs_rc v.Tir.v_ty
    && (include_borrowed_fields
        || not (StringSet.mem v.Tir.v_name env.borrowed_field_vars))
  in
  let counts : (string, int) Hashtbl.t = Hashtbl.create 8 in
  let vrec   : (string, Tir.var) Hashtbl.t = Hashtbl.create 8 in
  let order  = ref [] in
  List.iter (function
    | Tir.AVar v when eligible v ->
      (match Hashtbl.find_opt counts v.Tir.v_name with
       | Some n -> Hashtbl.replace counts v.Tir.v_name (n + 1)
       | None ->
         order := v.Tir.v_name :: !order;
         Hashtbl.replace counts v.Tir.v_name 1;
         Hashtbl.replace vrec v.Tir.v_name v)
    | _ -> ()
  ) atoms;
  List.rev !order
  |> List.concat_map (fun name ->
       let v = Hashtbl.find vrec name in
       let count = Hashtbl.find counts name in
       let n = count - 1 + (if StringSet.mem name live_after then 1 else 0) in
       List.init n (fun _ -> v))

(** Insert RC operations into an expression.
    Returns [(expr', live_before)] where expr' has RC ops inserted and
    live_before is the set of variables live before this expression. *)
let rec insert_rc_expr (env : env) (e : Tir.expr) (live_after : live_set)
    : Tir.expr * live_set =
  match e with
  | Tir.EAtom (Tir.AVar v) ->
    let lb = StringSet.add v.Tir.v_name live_after in
    if v.Tir.v_lin = Tir.Unr && needs_rc v.Tir.v_ty
       && StringSet.mem v.Tir.v_name live_after then
      (* Non-last use of Unr heap value: inc before use.
         Borrowed field vars are NOT exempt here: a borrowed field is kept in
         the live set for its whole scope (see the ELet case), so when it is
         the result value (tail return / branch result) this inc is the
         dup-on-escape that hands the caller an owned reference while the
         record owner keeps its own.  Returning it un-inc'd hands the caller
         an alias it believes it owns — the caller's consume frees the field
         the record still references (use-after-free in sitemap/feed and
         entry_tags reuse). *)
      (Tir.ESeq (incrc_for env v (Tir.AVar v), e), lb)
    else
      (e, lb)

  | Tir.EAtom (Tir.ADefRef _) ->
    (e, live_after)  (* global ref — no RC, no liveness change *)

  | Tir.EAtom (Tir.ALit _) ->
    (e, live_after)

  | Tir.EApp (f, args) ->
    (* Borrow-aware Inc insertion for direct (known) calls.
       For each argument at position [i]:
         - Standard (owned) parameter: insert EIncRC if Unr+needs_rc+live_after.
         - Borrowed parameter (per env.borrow_map):
             • Arg still live after call → skip EIncRC (callee will not Dec).
             • Arg NOT live after call  → no EIncRC (same as before), but emit
               EDecRC *after* the call because the callee will not Dec it. *)
    let indexed_args = List.mapi (fun i a -> (i, a)) args in
    (* 1. Args that go to owned parameters — standard Inc logic. *)
    let non_borrowed_args =
      List.filter_map (fun (i, a) ->
        if Borrow.is_borrowed env.borrow_map f.Tir.v_name i then None
        else Some a
      ) indexed_args
    in
    (* Don't include (AVar f) in find_inc_vars: after defun, the EApp callee
       is always a top-level function symbol (code address), never a
       heap-allocated closure.  Only ECallPtr dispatch involves owned closure
       pointers.  Including f here was harmless when needs_rc (TFn _) = false
       but after 831e315 causes spurious EIncRC for operator names like &&, ||
       whose llvm_name maps to @__ — an undefined symbol that fails to link. *)
    let inc_vars = find_inc_vars env non_borrowed_args live_after in
    (* 2. Borrowed args whose last use is this call: caller is responsible for Dec.
          Closure FVs are exempt: the closure owns them and keeps them alive.
          Dedup by v_name: when the same variable is passed at multiple
          borrowed positions (e.g. [f(x, x)] both borrowed, [x] dead after),
          the caller still owns exactly one reference and must emit exactly
          one DecRC.  Without dedup we would underflow the RC. *)
    let callee_is_apply = is_apply_fn f.Tir.v_name in
    let post_dec_vars =
      let seen = ref StringSet.empty in
      List.filter_map (fun (i, a) ->
        match a with
        | Tir.AVar v
          when v.Tir.v_lin = Tir.Unr
               && needs_rc v.Tir.v_ty
               && not (StringSet.mem v.Tir.v_name live_after)
               && Borrow.is_borrowed env.borrow_map f.Tir.v_name i
               (* The closure slot (arg 0) of an apply function follows the
                  closure-apply ABI: the callee consumes the closure regardless
                  of the borrow map.  Emitting a caller-side post-call EDecRC
                  here (as Known_call's ECallPtr->EApp rewrite would otherwise
                  trigger when $clo is borrow-classified) double-frees the
                  closure — the heap corruption behind the List.sort_by crash.

                  NOW VACUOUS, kept deliberately.  [Borrow.infer_module]'s
                  [init] pins apply-fn param 0 to owned, so [is_borrowed]
                  above is already false for every apply function and this
                  conjunct can no longer fire.  It stays as a second line of
                  defence: if that pin is ever narrowed, this is what keeps
                  the caller from re-acquiring the double-free. *)
               && not (i = 0 && callee_is_apply)
               && not (StringSet.mem v.Tir.v_name env.closure_fvs)
               && not (StringSet.mem v.Tir.v_name env.moved_vars)
               && not (StringSet.mem v.Tir.v_name env.borrowed_field_vars)
               && not (StringSet.mem v.Tir.v_name !seen) ->
          (* Borrowed field vars (extracted from a borrowed record parameter)
             are exempt from post-call EDecRC: ownership stays with the record
             owner; the function is only reading the field. *)
          seen := StringSet.add v.Tir.v_name !seen;
          Some v
        | _ -> None
      ) indexed_args
    in
    (* Dual-position args: a var passed at BOTH an owned and a borrowed
       position of the same call, dead afterwards, gets 0 dups from
       find_inc_vars (it only sees the owned occurrences: count-1 = 0) AND a
       borrowed-position post-call EDecRC above — two consumptions of the one
       reference the caller owns (the owned position already transfers it),
       i.e. RC underflow / use-after-free.  For a normal call, keep the
       post-dec and add ONE balancing EIncRC: this also keeps the value alive
       across the whole call even if the callee consumes its owned parameter
       before the last read of the borrowed alias.  For a SELF call, drop the
       post-dec instead: TCO rewrites the trailing ESeq'd EDecRC into dead
       code, so a balancing inc would leak one reference per iteration. *)
    let is_self_call = String.equal f.Tir.v_name env.current_fn_name in
    let owned_pos_names =
      List.fold_left (fun s (i, a) ->
        match a with
        | Tir.AVar v when not (Borrow.is_borrowed env.borrow_map f.Tir.v_name i) ->
          StringSet.add v.Tir.v_name s
        | _ -> s)
        StringSet.empty indexed_args
    in
    let dual_pos_vars, post_dec_vars =
      List.partition
        (fun (v : Tir.var) -> StringSet.mem v.Tir.v_name owned_pos_names)
        post_dec_vars
    in
    let inc_vars, post_dec_vars =
      if is_self_call then (inc_vars, post_dec_vars)
      else (inc_vars @ dual_pos_vars, post_dec_vars @ dual_pos_vars)
    in
    let e' = wrap_incrcs env inc_vars e in
    (* Wrap with post-call Decs.
       When there are post-call decrefs and the call has a non-unit return
       type, ESeq would discard the call result (ESeq returns its LAST
       expression's value).  Instead, bind the result to a fresh temp, run
       the decrefs, then return the temp.
       For unit-returning calls ESeq is fine — the result is not used.
       EXCEPTION: self-recursive tail calls keep the old ESeq form.
       has_self_tail_call in llvm_emit.ml explicitly handles
       ESeq(EApp(self,...), EDecRC(arg)) — after TCO emits the back-edge,
       the EDecRC is dead code and everything is correct.  Wrapping with
       ELet would hide the self-call from has_self_tail_call and kill TCO. *)
    let e'' =
      match post_dec_vars with
      | [] -> e'
      | _ when is_self_call ->
        (* Self-tail-call: keep ESeq so TCO detection finds the call *)
        List.fold_left (fun acc v ->
          Tir.ESeq (acc, decrc_for env v (Tir.AVar v))
        ) e' post_dec_vars
      | _ ->
        let call_ret_ty = match f.Tir.v_ty with
          | Tir.TFn (_, r) -> r
          | _ -> Tir.TVar "_"
        in
        (match call_ret_ty with
         | Tir.TUnit ->
           (* Unit return: plain ESeq is fine *)
           List.fold_left (fun acc v ->
             Tir.ESeq (acc, decrc_for env v (Tir.AVar v))
           ) e' post_dec_vars
         | _ ->
           (* Non-unit return: bind result, run decrefs, return result.
              Build ESeq(EDecRC(v1), ESeq(EDecRC(v2), ..., EAtom($rc)))
              so that ESeq returns the last expression ($rc), not the
              last DecRC.  Use fold_right so decrefs wrap the atom. *)
           let tmp = fresh_rc_var call_ret_ty in
           let decrcs =
             List.fold_right (fun v acc ->
               Tir.ESeq (decrc_for env v (Tir.AVar v), acc)
             ) post_dec_vars (Tir.EAtom (Tir.AVar tmp))
           in
           Tir.ELet (tmp, e', decrcs))
    in
    let lb =
      live_after
      (* f.v_name is a top-level function symbol — not a heap variable.
         Adding it to lb would propagate fake liveness for operators like
         && / || into upstream live sets, potentially triggering spurious
         cross-branch EDecRC for names that have no alloca slot. *)
      |> StringSet.union (vars_of_atoms args)
    in
    (e'', lb)

  | Tir.ECallPtr (Tir.AVar fv, args)
    when StringSet.mem fv.Tir.v_name env.extern_names ->
    (* Known user extern (FFI): the callee is a C symbol with a known borrow
       map (seeded in Borrow.infer_module), so apply EApp-style borrow-aware
       RC.  Borrowed args are NOT consumed by the C callee, so the caller keeps
       ownership and must EDecRC any borrowed arg whose last use is this call.
       Externs are never apply functions and take no closure slot, so the
       apply/closure exemptions in the EApp case do not apply here. *)
    let fname = fv.Tir.v_name in
    let indexed_args = List.mapi (fun i a -> (i, a)) args in
    let non_borrowed_args =
      List.filter_map (fun (i, a) ->
        if Borrow.is_borrowed env.borrow_map fname i then None else Some a
      ) indexed_args
    in
    (* The callee symbol fv is a code address, not a heap closure — never inc it. *)
    let inc_vars = find_inc_vars env non_borrowed_args live_after in
    let post_dec_vars =
      let seen = ref StringSet.empty in
      List.filter_map (fun (i, a) ->
        match a with
        | Tir.AVar v
          when v.Tir.v_lin = Tir.Unr
               && needs_rc v.Tir.v_ty
               && not (StringSet.mem v.Tir.v_name live_after)
               && Borrow.is_borrowed env.borrow_map fname i
               && not (StringSet.mem v.Tir.v_name env.closure_fvs)
               && not (StringSet.mem v.Tir.v_name env.moved_vars)
               && not (StringSet.mem v.Tir.v_name env.borrowed_field_vars)
               && not (StringSet.mem v.Tir.v_name !seen) ->
          seen := StringSet.add v.Tir.v_name !seen;
          Some v
        | _ -> None
      ) indexed_args
    in
    (* Dual-position args — same accounting bug as the EApp case above: a var
       at both an owned and a borrowed position, dead after the call, would be
       consumed twice (owned transfer + post-call dec) against the caller's
       single reference.  Externs are never self calls, so unconditionally add
       one balancing EIncRC per such var and keep the post-dec: the extra ref
       also protects the borrowed alias for the C call's whole duration. *)
    let owned_pos_names =
      List.fold_left (fun s (i, a) ->
        match a with
        | Tir.AVar v when not (Borrow.is_borrowed env.borrow_map fname i) ->
          StringSet.add v.Tir.v_name s
        | _ -> s)
        StringSet.empty indexed_args
    in
    let inc_vars =
      inc_vars
      @ List.filter
          (fun (v : Tir.var) -> StringSet.mem v.Tir.v_name owned_pos_names)
          post_dec_vars
    in
    let e' = wrap_incrcs env inc_vars e in
    let e'' =
      match post_dec_vars with
      | [] -> e'
      | _ ->
        let ret_ty = match fv.Tir.v_ty with
          | Tir.TFn (_, r) -> r
          | _ -> Tir.TVar "_"
        in
        (match ret_ty with
         | Tir.TUnit ->
           List.fold_left (fun acc v ->
             Tir.ESeq (acc, decrc_for env v (Tir.AVar v))
           ) e' post_dec_vars
         | _ ->
           let tmp = fresh_rc_var ret_ty in
           let decrcs =
             List.fold_right (fun v acc ->
               Tir.ESeq (decrc_for env v (Tir.AVar v), acc)
             ) post_dec_vars (Tir.EAtom (Tir.AVar tmp))
           in
           Tir.ELet (tmp, e', decrcs))
    in
    let lb =
      live_after |> StringSet.union (vars_of_atoms args)
    in
    (e'', lb)

  | Tir.ECallPtr (a, args) ->
    (* Conservative borrow treatment (audit P5): we have no borrow map for
       the indirect callee, so every arg is treated as owning.  For args
       still live after the call, [find_inc_vars] inserts an EIncRC so the
       callee's consumed reference is balanced against the caller's retained
       one.  For dead-after args, no IncRC is emitted — the caller's
       reference transfers to the callee, which is expected to decrement it
       (the closure-apply ABI used for ECallPtr always consumes args).
       The perf cost is extra Inc/Dec pairs around higher-order calls whose
       underlying apply function actually borrows.  A full fix would require
       attaching per-call-site borrow modes to closures at EAlloc time and
       plumbing them through the call dispatch — a sizeable architectural
       change deferred beyond this audit pass. *)
    let all_atoms = a :: args in
    let inc_vars = find_inc_vars env all_atoms live_after in
    let e' = wrap_incrcs env inc_vars e in
    let lb =
      live_after
      |> StringSet.union (vars_of_atom a)
      |> StringSet.union (vars_of_atoms args)
    in
    (e', lb)

  | Tir.ELet (v, e1, e2) ->
    (* Detect borrowed-field bindings BEFORE processing e2.
       When the RHS is a field access from a variable that is already live
       (either because the record is a borrowed param present in live_after,
       or because the source is already a borrowed field var), the bound
       variable inherits the "borrowed" status: the record owner is responsible
       for its RC and the borrowing function must not emit any RC ops for it.

       We also propagate through simple aliases (let v = bfv_src):
       if bfv_src is a borrowed field var, v is too.

       Save/restore around e2 processing so inner bindings don't contaminate
       outer scopes. *)
    (* Does extracting a field from [src] yield a borrowed reference (i.e. the
       record owner, not this binding, is responsible for the field's RC)?
       Mirrors the four conditions documented on the EField case below. *)
    let field_src_is_borrowed (src : Tir.var) : bool =
      (match src.Tir.v_ty with Tir.TPtr _ -> false | _ -> true)
      && (StringSet.mem src.Tir.v_name live_after
          || StringSet.mem src.Tir.v_name env.borrowed_field_vars
          || StringSet.mem src.Tir.v_name (live_before e2 live_after)
          || StringMap.mem src.Tir.v_name env.var_ctx)
    in
    (* Look through [to_string(_)] (identity for String, see llvm_emit.ml) and
       nested ELet chains that bind a borrowed field then convert it, e.g.
       [let v = (let f = src.field in to_string(f))].  Returns true when the
       result of [e] aliases a borrowed field reference.
       [bfv] is a purely-local, read-then-extended view of the borrowed-field
       set for this lookahead only — it mirrors the old code's hand-rolled
       save/restore around this same recursion (always restored before
       returning, on every branch, so a plain immutable parameter is exactly
       equivalent: the caller's [env.borrowed_field_vars] is never touched). *)
    let rec result_is_borrowed_field (bfv : StringSet.t) (e : Tir.expr) : bool =
      match e with
      | Tir.EApp (f, [Tir.AVar a])
        when (f.Tir.v_name = "to_string" || f.Tir.v_name = "Show$String.show")
             && a.Tir.v_ty = Tir.TString ->
        (* `to_string` on a String now lowers to the identity `Show$String.show`
           (the Show-dispatch reroute that fixes `to_string(container)`), so this
           borrowed-field optimization must recognize BOTH names or it would treat
           a borrowed field string as owned and drop it — an RC underflow. *)
        StringSet.mem a.Tir.v_name bfv
      | Tir.ELet (iv, Tir.EField (Tir.AVar src, _), ibody)
        when needs_rc iv.Tir.v_ty && field_src_is_borrowed src ->
        (* [iv] is a borrowed field var inside this sub-scope; check the body
           with that knowledge. *)
        result_is_borrowed_field (StringSet.add iv.Tir.v_name bfv) ibody
      | Tir.ELet (_, _, ibody) -> result_is_borrowed_field bfv ibody
      | _ -> false
    in
    let is_borrowed_field =
      match e1 with
      | _ when needs_rc v.Tir.v_ty
               && (match e1 with
                   | Tir.EField _ | Tir.EAtom _ -> false  (* handled below *)
                   | _ -> result_is_borrowed_field env.borrowed_field_vars e1) ->
        (* RHS evaluates to a borrowed field reference (possibly via the
           identity [to_string] and intervening field-extraction lets).  The
           record owner manages its RC; emitting an EDecRC here would free a
           string the owner still references — a use-after-free observed when
           the result is compared to a literal with [==]. *)
        true
      | Tir.EField (Tir.AVar src, _)
        when needs_rc v.Tir.v_ty
             (* TPtr sources are closure structs ($clo).  Their fields are
                closure FVs managed by the borrowed' set (d2cf09e): Perceus
                emits EIncRC before any consuming call so the closure's own
                reference survives repeated invocations.  Marking a closure FV
                as is_borrowed_field would add it to borrowed_field_vars and
                suppress that EIncRC, causing RC underflow on the 2nd call.
                This check must precede all four conditions below because
                conditions 1–3 fire whenever $clo is in live_after (which
                happens whenever $clo is a borrowed param and therefore in
                borrowed'), and condition 4 already has this TPtr guard. *)
             && (match src.Tir.v_ty with Tir.TPtr _ -> false | _ -> true)
             && (StringSet.mem src.Tir.v_name live_after
                 || StringSet.mem src.Tir.v_name env.borrowed_field_vars
                 || StringSet.mem src.Tir.v_name (live_before e2 live_after)
                 || (StringMap.mem src.Tir.v_name env.var_ctx
                     && (match src.Tir.v_ty with
                         | Tir.TPtr _ -> false
                         | _ -> true))) ->
        (* The record owner is responsible for the field's RC.
           Four cases where the field must NOT be treated as independently owned:
           1. src in live_after: record is a borrowed parameter (present in the
              initial live-at-exit borrowed set) — the caller outlives this binding.
           2. src in borrowed_field_vars: src was itself extracted from a borrowed
              record (alias chain).
           3. src in live_before(e2): the record is used again in the body after
              this extraction (sequential multi-field access pattern).
           4. src in var_ctx and src is a heap record (not TPtr): the record is
              a locally-owned variable still in scope (e.g. returned by a
              cross-module function call).  TPtr sources (like the closure struct
              $clo: TPtr TUnit) are excluded — their fields (closure FVs) are
              managed by the borrowed' set and must receive EIncRC before
              consuming calls, which borrowed_field_vars would suppress. *)
        true
      | Tir.EAtom (Tir.AVar src)
        when needs_rc v.Tir.v_ty
             && StringSet.mem src.Tir.v_name env.borrowed_field_vars ->
        (* Alias of a borrowed field var — propagate the borrowed status. *)
        true
      | _ -> false
    in
    (* Process e2 first to discover what's live going into it.
       Extend var_ctx with [v] so that nested ECase cross-branch EDecRC
       insertion can look up [v]'s type when [v] is live in some arms and
       dead in others.  Descending with an updated [env] copy handles
       shadowing correctly (the caller's own [env] is untouched, matching the
       old code's save/restore).

       A borrowed-field binding is additionally added to e2's live-at-exit
       set.  This makes Perceus treat it exactly like a borrowed parameter /
       closure FV for the whole scope: every CONSUMING use (call argument,
       constructor capture, tail return) sees it live and emits an EIncRC
       dup, so the consumer frees its own reference and the record owner's
       reference stays valid; and it is never EDecRC'd locally (the owner
       decrements it when the record dies).  Without the dup, a borrowed
       field that ESCAPES (returned from an accessor like
       [fn entry_date(e) do e.date end], or passed to a consuming callee
       like [List.flat_map]) transfers a reference the function never owned
       — the consumer's free leaves the record with a dangling field
       (observed: sitemap_items freeing entry dates that feed_items then
       read; flat_map freeing tags lists that a later filter re-read). *)
    let env_for_e2 =
      { env with
        var_ctx = StringMap.add v.Tir.v_name v env.var_ctx;
        borrowed_field_vars =
          if is_borrowed_field
          then StringSet.add v.Tir.v_name env.borrowed_field_vars
          else env.borrowed_field_vars }
    in
    let live_after_e2 =
      if is_borrowed_field then StringSet.add v.Tir.v_name live_after
      else live_after
    in
    let (e2', live_into_e2) = insert_rc_expr env_for_e2 e2 live_after_e2 in
    (* Check if v is dead in e2 *)
    let e2'' =
      if not (StringSet.mem v.Tir.v_name live_into_e2)
         && not (StringSet.mem v.Tir.v_name env.closure_fvs)
         && not (StringSet.mem v.Tir.v_name env.moved_vars)
         && not is_borrowed_field then
        (* Dead binding — insert cleanup at start of e2.
           Use atomic DecRC for actor-sent values (may be concurrently accessed).
           Closure FVs are exempt: the closure holds the reference; the apply
           function must not decrement values it does not own.
           Borrowed field vars are exempt: the record owner manages their RC. *)
        if v.Tir.v_lin = Tir.Unr && needs_rc v.Tir.v_ty then
          Tir.ESeq (decrc_for env v (Tir.AVar v), e2')
        else if v.Tir.v_lin = Tir.Lin || v.Tir.v_lin = Tir.Aff then
          if needs_rc v.Tir.v_ty then
            Tir.ESeq (Tir.EFree (Tir.AVar v), e2')
          else
            e2'
        else
          e2'
      else if is_aggregate_ty v.Tir.v_ty
              && v.Tir.v_lin = Tir.Unr
              && StringSet.mem v.Tir.v_name live_into_e2
              && not (StringSet.mem v.Tir.v_name live_after)
              && not (StringSet.mem v.Tir.v_name env.closure_fvs)
              && not (StringSet.mem v.Tir.v_name env.moved_vars)
              && not is_borrowed_field
              && not (tail_value_is_var v.Tir.v_name e2')
              && not (releases_var v.Tir.v_name e2')
              && used_only_as_field_source v.Tir.v_name e2'
              && tir_expr_ty e2' <> None then
        (* Scope-end drop for an owned aggregate (Wave: aggregate RC).
           Records and tuples are read exclusively through [EField]; unlike a
           variant, which is destructured by an ECase and freed there by
           [add_scrutinee_free_for], an aggregate has NO drop site on its read
           path.  So an aggregate that is USED in [e2] (and therefore skips the
           dead-binding branch above) but does not outlive this scope was never
           dropped at all: every record and tuple cell leaked, together with
           every heap value it owned.

           The drop goes at the END of the scope rather than at the last field
           read.  That is the conservative direction and it is what makes it
           safe: a field that ESCAPES [e2] has already been dup'd by the
           borrowed-field logic above ([inc_rc] before the field leaves), so by
           the time the aggregate is released every reference taken out of it is
           independently owned.  Dropping at last use instead would require
           proving that no borrowed field outlives the projection.

           [tail_value_is_var] excludes the aggregate being the scope's own
           result ([let b = {..} in b]), where the EAtom arm has already handed
           ownership to the caller and this dec would be a double-free.
           [moved_vars] excludes the aggregate being stored into another
           structure on any path. *)
        let body_ty = match tir_expr_ty e2' with
          | Some t -> t
          | None -> assert false (* guarded above *) in
        let tmp = fresh_rc_var body_ty in
        Tir.ELet (tmp, e2',
                  Tir.ESeq (decrc_for env v (Tir.AVar v),
                            Tir.EAtom (Tir.AVar tmp)))
      else
        e2'
    in
    let live_for_e1 = StringSet.remove v.Tir.v_name live_into_e2 in
    let (e1', live_before_e1) =
      match e1 with
      | Tir.EAtom (Tir.AVar src)
        when is_borrowed_field
             && StringSet.mem src.Tir.v_name env.borrowed_field_vars ->
        (* Borrowed-alias binding [let w = v] where v is itself a borrowed
           field: w inherits borrowed status (marked above) and will receive
           its own dup at any consuming use.  Skip RC processing of the RHS
           atom — the generic EAtom rule would see v in the (artificially
           extended) live set and emit a second EIncRC for the same logical
           reference, which nothing ever decrements (a leak). *)
        (e1, StringSet.add src.Tir.v_name live_for_e1)
      | _ -> insert_rc_expr env e1 live_for_e1
    in
    (* Fix value-discarding ESeq patterns in the processed RHS.
       Borrow inference may produce ESeq(call, DecRC(arg)) at tail positions
       of the RHS expression (including inside nested ELet chains).  ESeq
       returns the LAST expr's value, so the call result is discarded.
       We restructure by introducing a fresh let binding to capture the value:
         ESeq(value, cleanup)  →  ELet($rc_N, value, ESeq(cleanup, $rc_N))
       This preserves the value while still running the cleanup.
       The restructuring follows ELet chains to find tail ESeqs. *)
    let rec fix_tail_value (expr : Tir.expr) : Tir.expr =
      match expr with
      | Tir.ESeq (value_expr, ((Tir.EDecRC _ | Tir.EAtomicDecRC _
                                | Tir.EFree _) as cleanup)) ->
        let fixed = fix_tail_value value_expr in
        let tmp = fresh_rc_var v.Tir.v_ty in
        Tir.ELet (tmp, fixed, Tir.ESeq (cleanup, Tir.EAtom (Tir.AVar tmp)))
      | Tir.ELet (iv, ie1, ibody) ->
        Tir.ELet (iv, ie1, fix_tail_value ibody)
      | _ -> expr
    in
    let e1_fixed = fix_tail_value e1' in
    (Tir.ELet (v, e1_fixed, e2''), live_before_e1)

  | Tir.ELetRec (fns, body) ->
    let (body', live_body) = insert_rc_expr env body live_after in
    let fns' = List.map (fun fn ->
      let (fb, _) = insert_rc_expr env fn.Tir.fn_body StringSet.empty in
      { fn with Tir.fn_body = fb }
    ) fns in
    let fn_names =
      List.fold_left (fun s fn -> StringSet.add fn.Tir.fn_name s)
        StringSet.empty fns
    in
    let lb = StringSet.diff live_body fn_names in
    (Tir.ELetRec (fns', body'), lb)

  | Tir.ECase (a, branches, default) ->
    (* When the scrutinee is a heap value not live after the case, it is
       consumed by the match.  Free its header in every branch.  Branch-bound
       variables (br_vars) take over ownership of the children, so we only
       need to free the allocation header — EDecRC handles both the unique
       case (RC→0 → free) and the shared case (RC>1 → just decrement).
       We tag the DecRC var with the CONCRETE constructor type (br.br_tag)
       so that the FBIP pass can match it against EAllocs of compatible arity.
       The arity (number of branch-bound variables = number of fields) is
       encoded as dummy TUnit type args so that [same_arity] can compare it
       against the new EAlloc's arg count without needing type definitions. *)
    let add_scrutinee_free_for ctor_tag arity body =
      match a with
      | Tir.AVar v when needs_rc v.Tir.v_ty
                     && not (StringSet.mem v.Tir.v_name live_after)
                     && not (name_free_in v.Tir.v_name body)
                     (* Newtype/niche scrutinees share storage with their payload
                        branch variable (S(x)≡x, Some(x)≡x); the variable's own
                        RC lifecycle frees the shared object, so emitting a
                        separate scrutinee free here would double-free it. *)
                     && not (scrutinee_shares_payload_storage env v.Tir.v_ty) ->
        (* Use the concrete ctor type so FBIP can recognise the tag.
           Do not dec_rc if the branch body still uses the scrutinee (e.g.,
           when the scrutinee is passed through as an argument after inspection
           of one of its fields via a nested match).
           Encode the freed constructor's [arity] (= its field count, known
           exactly here from the branch's bound vars) as dummy TUnit args
           behind the [fbip_arity_marker] prefix; [same_arity] accepts ONLY
           this marked encoding, so a raw declared type (whose TCon args are
           type PARAMETERS, not fields) can never be mistaken for an arity.
           The qualified "Type.Ctor" tail is kept for TIR-dump readability.
           IMPORTANT: qualify the ctor_tag with the scrutinee's type name so it
           matches the key format used by EAlloc (see lower.ml ECon case:
           ctor_key = type_name ^ "." ^ tag).  Without this, the FBIP pass
           compares e.g. "Leaf" vs "Tree.Leaf" and always returns false.
           When the scrutinee's type is unknown (TVar — typical for
           closure-internal helpers whose params are erased to TVar "_"), we
           leave the type untouched so [same_arity] returns false,
           suppressing FBIP conservatively. *)
        let ctor_v = match v.Tir.v_ty with
          | Tir.TCon (type_name, _) ->
            let encoded_tag =
              fbip_arity_marker ^ type_name ^ "." ^ ctor_tag in
            let dummy_args = List.init arity (fun _ -> Tir.TUnit) in
            { v with Tir.v_ty = Tir.TCon (encoded_tag, dummy_args) }
          | _ -> v
        in
        Tir.ESeq (decrc_for env v (Tir.AVar ctor_v), body)
      | _ -> body
    in
    let branches_processed = List.map (fun br ->
      let bound =
        List.fold_left (fun s v -> StringSet.add v.Tir.v_name s)
          StringSet.empty br.Tir.br_vars
      in
      let la = StringSet.diff live_after bound in
      (* When the scrutinee is borrowed (not freed in this branch), its branch
         variables are borrowed references extracted from it.  They must not be
         freed at their last use; re-add them to live_after so post_dec_var
         does not fire for them after borrowed calls inside the branch body.

         The scrutinee is borrowed in two cases:
           1. It lives in live_after (used after the entire case).
           2. It appears free in this branch's body (used in a different sub-path
              within the branch, e.g. the else side of an if inside the branch).

         Case 2 was previously unhandled, causing br_vars to be passed to owning
         positions without IncRC — an RC-underflow when a branch var extracted
         from a borrowed scrutinee is passed to an owning position on a sub-path
         where the scrutinee is still live (commit 9930ce5).  See
         specs/perceus-invariants.md §6 for the governing account.

         KNOWN LIMITATION — conservative approximation (memory-safe, minor leak):
         [name_free_in] returns true if the scrutinee appears on ANY path in the
         body, including just one branch of a nested if-else.  When the scrutinee
         appears on only SOME paths, the branch variables are conservatively kept
         live everywhere, preventing them from being freed on paths where the
         scrutinee is NOT used — a bounded memory leak.

         Using a path-sensitive "name_free_on_every_path" check instead would
         reintroduce a use-after-free for the genuine single-sub-path case: when a
         borrowed scrutinee appears in one arm/sub-path but not another (e.g. the
         Cons arm but not the Nil arm of a list fold's inner match),
         name_free_on_every_path returns false, scrutinee_borrowed becomes false,
         br_vars are freed, and a subsequent pass-to-owning-position on the path
         where the scrutinee IS used reads freed memory.  (Historically this was
         mis-attributed to List.sort_by; sort_by was later exonerated —
         .superpowers/sdd/sortby-diagnosis.md, real bug fixed in ffe6fba8 — but
         the path-insensitive-conservatism invariant it motivated is correct and
         independent of any one caller.)

         The correct fix requires path-sensitive analysis within the branch body —
         adding br_vars to la only on the sub-paths where the scrutinee actually
         escapes, and emitting EDecRC on sub-paths where it does not.  This is a
         significant refactor of the insert_rc_expr traversal.  Until then, the
         conservative direction (leak-not-crash) is intentional. *)
      let scrutinee_borrowed = match a with
        | Tir.AVar v ->
          StringSet.mem v.Tir.v_name live_after
          || (needs_rc v.Tir.v_ty
              && name_free_in v.Tir.v_name br.Tir.br_body)
          (* Tuples/records are [needs_rc = false]: Perceus never emits a
             DecRC/free for the aggregate itself, so its extracted fields are
             effectively borrowed from a value whose lifetime the match does
             not control (e.g. a tuple element of a BORROWED list).  Treat the
             aggregate as a borrowed scrutinee so escaping fields get an EIncRC
             and dead fields are NOT decremented — decrementing a field of a
             borrowed-derived tuple corrupts the structure the caller reuses
             (Toml table_get's discarded value / returned element). *)
          || (match v.Tir.v_ty with
              | Tir.TTuple _ | Tir.TRecord _ -> true
              | _ -> false)
        | _ -> false
      in
      let la = if scrutinee_borrowed then
        List.fold_left (fun s bv -> StringSet.add bv.Tir.v_name s)
          la br.Tir.br_vars
      else la
      in
      (* Add br_vars to var_ctx so nested cross-branch EDecRC can find their
         types.  Branch-bound constructor fields are not ELet-bound and would
         otherwise be invisible to the cross-branch dead-variable pass inside
         the branch body (e.g. [root] of [PVec(n,shift,root,tail)] in the
         tail-access sub-path of Array.get where root is dead).
         Descending with an updated [env] copy handles shadowing correctly
         (the caller's [env] for sibling branches is untouched, matching the
         old code's save/restore). *)
      let env_for_br =
        { env with
          var_ctx =
            List.fold_left (fun ctx (v : Tir.var) ->
              StringMap.add v.Tir.v_name v ctx
            ) env.var_ctx br.Tir.br_vars }
      in
      let (body', live_before_br) = insert_rc_expr env_for_br br.Tir.br_body la in
      (* Emit EDecRC for br_vars that are heap-typed but dead in this branch body.
         These fields were bound by the pattern but not used anywhere in the arm
         (e.g. [root] and [tail] in [PVec(n,_,_,_) -> n]).
         In the shared (RC > 1) case llvm_emit increments their RC on the
         shared path, so without a matching decrement they leak permanently.
         In the unique (FBIP) case they were moved from the freed constructor
         and must be released here to avoid memory leaks.
         When scrutinee_borrowed = true, all br_vars are re-added to [la]
         above, so they appear in [live_before_br] and the check below
         correctly suppresses EDecRC for borrowed fields. *)
      let body'' = List.fold_right (fun (v : Tir.var) body_acc ->
        if needs_rc v.Tir.v_ty
           && not (StringSet.mem v.Tir.v_name live_before_br)
           && not (StringSet.mem v.Tir.v_name env.closure_fvs)
           && not (StringSet.mem v.Tir.v_name env.moved_vars)
           && not (StringSet.mem v.Tir.v_name env.borrowed_field_vars) then
          Tir.ESeq (decrc_for env v (Tir.AVar v), body_acc)
        else
          body_acc
      ) br.Tir.br_vars body'
      in
      (br, body'', live_before_br, bound)
    ) branches in
    (* Cross-branch dead-variable EDecRC.
       A variable may be live in some arms (used) but dead in others (not
       used).  For variables that are NOT function parameters Perceus relies
       on the ELet dead-binding detection, which only fires when the variable
       is dead in the *entire* continuation — not just in one arm.  For
       parameters (and ELet-bound vars that the ELet check missed because
       they are live in at least one arm), we must emit EDecRC at the head
       of each arm where the variable is dead.

       Algorithm:
         1. Compute union of live_before_br across all arms.
         2. For each arm, the set of "dead here, live elsewhere" vars is
            (union \ live_before_br_i) \ {arm-bound vars} \ live_after
                                       \ env.closure_fvs.
         3. For each such var that has a type record in env.var_ctx, emit
            EDecRC at the head of that arm's body.

       Exclusions:
         - live_after: var is expected to survive the whole case.
         - arm-bound vars: the arm's pattern bind these, so they are locally
           new values, not the outer var.
         - env.closure_fvs: owned by the closure struct; the apply function
           must not decrement them.
         - the scrutinee's own variable (scrutinee_name below): its lifecycle
           is entirely owned by [add_scrutinee_free_for], which independently
           decides — PER ARM — whether that arm's body still uses the
           scrutinee (in which case ownership transfers into the body and no
           free is emitted) or not (in which case exactly one free is
           emitted).  Without this exclusion, a sibling arm whose body
           re-matches the SAME scrutinee atom on a sub-path (the
           "scrutinee-borrowed conservatism" re-add, ~line 1076 above) makes
           the scrutinee appear "live" in that arm's [live_before_br], which
           lands it in [union_live_br] — so every OTHER arm where the
           scrutinee is dead sees it as "dead here, live elsewhere" and gets
           a cross-branch EDecRC on top of the per-arm scrutinee free
           [add_scrutinee_free_for] already inserts there.  That is a literal
           double dec_rc on the identical reference: RC-underflow abort at
           runtime (see specs/todos.md P0, fixed here). The scrutinee is not
           a "cross-branch liveness" variable in the ordinary sense — every
           arm consumes (or doesn't) the SAME single reference the match
           itself is scrutinizing, so its fate can never legitimately depend
           on what a sibling arm's body did with it. *)
    let scrutinee_name = match a with
      | Tir.AVar v -> Some v.Tir.v_name
      | _ -> None
    in
    let union_live_br = List.fold_left (fun acc (_, _, lb, _) ->
      StringSet.union acc lb
    ) StringSet.empty branches_processed in
    let add_cross_decrcs (live_before_br : live_set) (bound : StringSet.t)
                         (body : Tir.expr) : Tir.expr =
      let dead_here =
        union_live_br
        |> (fun s -> StringSet.diff s live_before_br)
        |> (fun s -> StringSet.diff s bound)
        |> (fun s -> StringSet.diff s live_after)
        |> (fun s -> StringSet.diff s env.closure_fvs)
        |> (fun s -> StringSet.diff s env.moved_vars)
        |> (fun s -> StringSet.diff s env.borrowed_field_vars)
        |> (fun s -> match scrutinee_name with
            | Some n -> StringSet.remove n s
            | None -> s)
      in
      StringSet.fold (fun name body_acc ->
        match StringMap.find_opt name env.var_ctx with
        | Some v when v.Tir.v_lin = Tir.Unr && needs_rc v.Tir.v_ty ->
          Tir.ESeq (decrc_for env v (Tir.AVar v), body_acc)
        | _ -> body_acc
      ) dead_here body
    in
    let branches' = List.map (fun (br, body', live_before_br, bound) ->
      let br_arity = List.length br.Tir.br_vars in
      let body_with_scrut = add_scrutinee_free_for br.Tir.br_tag br_arity body' in
      let body_with_cross = add_cross_decrcs live_before_br bound body_with_scrut in
      { br with Tir.br_body = body_with_cross }
    ) branches_processed in
    let default' = Option.map (fun d ->
      let (d_rc, d_lb) = insert_rc_expr env d live_after in
      (* Default branch: no constructor tag known, use original type.
         Only free the scrutinee if the branch body does NOT use it directly —
         if the body uses it, ownership transfers into the body. *)
      let d_rc' = (match a with
       | Tir.AVar v when needs_rc v.Tir.v_ty
                      && not (StringSet.mem v.Tir.v_name live_after)
                      && not (name_free_in v.Tir.v_name d) ->
         Tir.ESeq (decrc_for env v (Tir.AVar v), d_rc)
       | _ -> d_rc)
      in
      (* Cross-branch EDecRC for the default arm too *)
      add_cross_decrcs d_lb StringSet.empty d_rc'
    ) default in
    (* Compute live_before from the original liveness *)
    let lb = live_before e live_after in
    (Tir.ECase (a, branches', default'), lb)

  | Tir.ESeq (e1, e2) ->
    let (e2', l2) = insert_rc_expr env e2 live_after in
    let (e1', l1) = insert_rc_expr env e1 l2 in
    (Tir.ESeq (e1', e2'), l1)

  | Tir.ETuple atoms ->
    let inc_vars = find_inc_vars env atoms live_after in
    let e' = wrap_incrcs env inc_vars e in
    let lb = StringSet.union live_after (vars_of_atoms atoms) in
    (e', lb)

  | Tir.ERecord fields ->
    let atoms = List.map snd fields in
    let inc_vars = find_inc_vars env atoms live_after in
    let e' = wrap_incrcs env inc_vars e in
    let lb = StringSet.union live_after (vars_of_atoms atoms) in
    (e', lb)

  | Tir.EField (a, f) ->
    (* Field projection BORROWS the record: no ownership changes hands, so a
       borrowed-field record var must not be dup'd here (it would leak).

       NOTE: an aggregate source is deliberately NOT excluded here, even though
       [find_inc_vars] documents its atoms as consuming positions and a
       projection is not one.  Excluding it (tried, reverted) removed incs that
       are load-bearing for niche-represented payloads, where the scrutinee and
       its payload share one cell: test/native/record_pattern.march
       (`Wrap = W({rate : Float, code : Int}) | Z`, matched twice) then died
       with a nondeterministic SIGBUS/RC-underflow on the second call.  The inc
       is largely inert anyway -- [find_inc_vars] only emits one when the source
       is live after the projection, in which case a later dec balances it -- so
       excluding it bought nothing measurable: the leak fixtures and
       simple-record leak counts were identical either way.  See
       specs/todos/2026-09-03-aggregate-field-read-inc-masks-imbalance.md. *)
    let inc_vars = find_inc_vars ~include_borrowed_fields:false env [a] live_after in
    let e' = wrap_incrcs env inc_vars (Tir.EField (a, f)) in
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e', lb)

  | Tir.EUpdate (a, fields) ->
    (* The BASE is borrowed, not consumed: [Llvm_emit_data.emit_update] reads
       its fields into a fresh cell and leaves it intact.  Running it through
       [find_inc_vars] emitted an inc with no matching dec (visible in
       test/snapshots/perceus/record_update.expected as `inc_rc p` inside
       move_right against a single `dec_rc p` in the caller), which pinned the
       base's refcount above zero forever.

       That stray inc was also masking a double-free: emit_update copies the
       base's field POINTERS raw, so base and result both reference the same
       children, and with aggregates now deep-dropped both would release them.
       The inc kept the base's RC from reaching zero, so its drop skipped the
       children and only the result released them.  The copied fields are inc'd
       properly in emit_update now, so the mask is neither needed nor wanted.

       The UPDATE VALUES are genuinely consumed -- they are stored into the new
       cell -- so they keep their [find_inc_vars] treatment. *)
    let atoms = List.map snd fields in
    let inc_vars = find_inc_vars env atoms live_after in
    let e' = wrap_incrcs env inc_vars e in
    let lb =
      live_after
      |> StringSet.union (vars_of_atom a)
      |> StringSet.union (vars_of_atoms (List.map snd fields))
    in
    (e', lb)

  | Tir.EAlloc (ty, atoms) ->
    let inc_vars = find_inc_vars env atoms live_after in
    let e' = wrap_incrcs env inc_vars (Tir.EAlloc (ty, atoms)) in
    let lb = StringSet.union live_after (vars_of_atoms atoms) in
    (e', lb)

  | Tir.EStackAlloc (ty, atoms) ->
    let inc_vars = find_inc_vars env atoms live_after in
    let e' = wrap_incrcs env inc_vars (Tir.EStackAlloc (ty, atoms)) in
    let lb = StringSet.union live_after (vars_of_atoms atoms) in
    (e', lb)

  | Tir.EFree a ->
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e, lb)

  | Tir.EIncRC a | Tir.EAtomicIncRC a ->
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e, lb)

  | Tir.EDecRC a | Tir.EAtomicDecRC a ->
    let lb = StringSet.union live_after (vars_of_atom a) in
    (e, lb)

  | Tir.EReuse (a, ty, atoms) ->
    let all_atoms = a :: atoms in
    let inc_vars = find_inc_vars env all_atoms live_after in
    let e' = wrap_incrcs env inc_vars (Tir.EReuse (a, ty, atoms)) in
    let lb =
      live_after
      |> StringSet.union (vars_of_atom a)
      |> StringSet.union (vars_of_atoms atoms)
    in
    (e', lb)

  (* TRMC.  EAllocHole stores its operands into a fresh cell exactly as
     EAlloc does, so it takes the same ownership treatment: an operand still
     live afterwards needs an IncRC. *)
  | Tir.EAllocHole (tok, ty, atoms, hole) ->
    let inc_vars = find_inc_vars env atoms live_after in
    let e' = wrap_incrcs env inc_vars (Tir.EAllocHole (tok, ty, atoms, hole)) in
    let lb =
      live_after
      |> StringSet.union
           (match tok with Some a -> vars_of_atom a | None -> StringSet.empty)
      |> StringSet.union (vars_of_atoms atoms)
    in
    (e', lb)

  (* ESetField MOVES [v] into [o]: the object takes over the reference, so no
     IncRC is emitted for [v] and no drop may be emitted for it afterwards.
     [o] is only mutated, never consumed.  Adding [v] to the live-before set
     (rather than treating this as its last use) is what keeps Phase 2's
     ownership-transfer hazard from becoming a double-free: the value is
     reachable from [o] from here on, and [o]'s own lifetime releases it. *)
  | Tir.ESetField (o, i, v) ->
    let lb =
      live_after
      |> StringSet.union (vars_of_atom o)
      |> StringSet.union (vars_of_atom v)
    in
    (Tir.ESetField (o, i, v), lb)
