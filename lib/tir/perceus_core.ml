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

(* ── Owned-call clones (owned-call drop fusion, 2026-10-07) ────────────────

   A call [let r = f(x) in drop x; k] -- [x] passed at a BORROWED position of
   [f] and dead after the call -- walks [x] twice: once in [f], then again in
   the deep drop that follows.  When this table is present (the driver's
   optimised native pipeline only), Perceus instead redirects such a call to
   an OWNED clone [f$own<i>] of [f] in which those positions are owned, and
   emits no drop: the clone consumes [x], so a destructuring match on it
   releases each cell as the walk passes it ([Llvm_case]'s leading-dec arm
   frees a unique cell shallowly and dups the fields of a shared one).

   Clones are made lazily, only for a (callee, positions) pair some call site
   actually redirected to, from the callee's pre-RC body; Perceus then runs
   on the clone like on any other function, which may request further clones.
   See specs/progress/2026-10-07-owned-call-drop-fusion.md. *)
type owned_calls = {
  oc_fns : (string, Tir.fn_def) Hashtbl.t;
      (** Functions that may be cloned, by name, as handed to [insert_rc]. *)
  oc_clones : (string, string * int list) Hashtbl.t;
      (** Every clone requested so far: clone name -> (original, positions). *)
  oc_pending : (string * string * int list) Queue.t;
      (** Requested clones whose bodies have not been built yet. *)
  oc_alloc_bound : StringSet.t ref;
      (** For the function being processed: names bound directly by
          [let v = EAlloc ...].  Never redirected: [Escape] may promote such
          a cell to the stack through a borrowing callee, which an owning
          one would forbid. *)
  oc_useful : (string * int, unit) Hashtbl.t;
      (** (function, borrowed position) pairs worth an owned clone: the
          parameter is destructured by an [ECase] in the body, or handed on at
          a useful position of another clone-eligible function.  A call in an
          ORIGINAL function is redirected only when one of its handed
          positions is useful: owning anything else only moves the caller's
          drop into the callee, a copy of the function for nothing. *)
}

let owned_clone_name (orig : string) (positions : int list) : string =
  orig ^ "$own" ^ String.concat "_" (List.map string_of_int positions)

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
  k_table : Kind.table;   (* the per-type table; see specs/2026-09-10-type-kinds-design.md *)
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
  field_owner : string StringMap.t;
      (** For each [borrowed_field_vars] binding made by a projection, the
          variable it points into ([let t = d.f] maps [t] to [d]; an alias or
          a nested chain [let t = (let a = d.x in a.y)] maps to the same
          root).  A projection keeps its owner alive: the cross-branch release
          of an owner dead in one arm must not run at the arm's head while a
          projection of it is still read there.
          specs/progress/2026-10-08-perceus-parent-released-before-field-use.md. *)
  cons_live : StringSet.t;
      (** Variables that are in [live_after] only CONSERVATIVELY: an
          [ECase] arm's pattern-bound fields, re-added to the arm's live set
          because the scrutinee is mentioned somewhere in the arm
          ([scrutinee_borrowed]'s [name_free_in] disjunct) or is a tuple/record
          — NOT because the scrutinee provably outlives the arm.

          A nested [ECase] over one of these must not conclude that its
          scrutinee outlives it, and so must not mark its own fields as
          borrowed: that is precisely the premise [scrutinee_live_across_case]
          documents it will not take from [scrutinee_borrowed] ("ownership then
          transfers into the body, which may consume the scrutinee part-way
          through and free it while a projected field is still being read").
          Without this set the premise leaked in one level down, through
          [live_after], and did exactly that: a list-of-pairs insert released
          the list cell on one sub-path ahead of dup'ing a field it had borrowed
          from inside it
          (specs/2026-09-18-perceus-releases-a-parent-before-its-borrowed-child.md). *)
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
  owned_calls : owned_calls option;
      (** Module-scoped: the owned-call clone table, or [None] (the default:
          REPL, JS, hot reload, unoptimised builds, MARCH_NO_OWNED_CALLS=1)
          to never redirect.  See [owned_calls]. *)
}

(** The env used before any module has been processed / after [perceus]
    finishes with a function — mirrors the old refs' initial values
    ([Borrow.empty], [[]], [StringMap.empty], [StringSet.empty], ...). *)
let empty_env : env = {
  borrow_map = Borrow.empty;
  type_defs = [];
  collision_set = Hashtbl.create 0;
  k_table = Kind.empty;
  extern_names = StringSet.empty;
  current_fn_name = "";
  closure_fvs = StringSet.empty;
  actor_sent = StringSet.empty;
  moved_vars = StringSet.empty;
  borrowed_field_vars = StringSet.empty;
  field_owner = StringMap.empty;
  cons_live = StringSet.empty;
  var_ctx = StringMap.empty;
  owned_calls = None;
}

(** True when a value of type [ty] shares its heap object with the payload of
    its single relevant constructor — i.e. newtype- (S(x)≡x) or niche-
    (Some(x)≡x, None≡0) represented.  For such types a pattern match does NOT
    project a child out of a distinct container cell: the bound branch variable
    IS the scrutinee object.  Freeing the scrutinee separately would therefore
    double-free the object the branch variable now owns — the cause of the
    Toml get_str / nested-Option RC underflow. *)
let scrutinee_shares_payload_storage (env : env) (ty : Tir.ty) : bool =
  match Kind.repr_of env.k_table ty with
  | Kind.Newtype _ | Kind.Niche _ -> true
  (* Unboxed (Milestone 3): there is no container cell, so there is nothing to
     free separately and nothing for FBIP to reuse.  Answering true is what
     keeps [add_scrutinee_free_for] and the reuse-token search away from a
     value that never reached the heap. *)
  | Kind.Unboxed _ -> true
  | Kind.Boxed ->
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
            && Kind.is_niche_shaped env.k_table name -> true
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
let needs_rc (env : env) (ty : Tir.ty) : bool = Kind.needs_rc_of env.k_table ty

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
let is_aggregate_ty (env : env) : Tir.ty -> bool = function
  | Tir.TTuple _ | Tir.TRecord _ -> true
  (* A NOMINAL record ([type St = { n : Int }], an actor's [Name_State]) is
     the same aggregate under a [TCon] name.  Matching only the structural
     forms left every such value with no drop site at all: a record built,
     read through its fields and then dropped leaked its cell and every heap
     value it owned, and an actor handler that returned a new state leaked
     one record per message
     (specs/progress/2026-10-01-compiled-actor-and-nominal-record-leaks.md). *)
  | Tir.TCon (n, _) ->
    Kind.is_record_type env.k_table n
    (* ... or named by its short name ([Ops] for [Session.Ops]): without this
       a [d : Ops] read only through its fields was neither an aggregate (no
       scope-end drop) nor released at its last use, and every Session
       operation leaked a reference to the session's Ops
       (specs/progress/2026-10-06-session-ops-leak.md). *)
    || Kind.record_fields_short env.k_table n <> None
  | _ -> false

(** Result type of a primitive operator application whose callee variable
    carries no [TFn] type ([+], [<], ...).  Arithmetic takes its operands' type
    only when every operand is known to be [Int], or every one [Float];
    comparisons and boolean connectives are [Bool].  Anything else is [None],
    the same refusal [tir_expr_ty] makes for any unknown type. *)
let builtin_op_result_ty (name : string) (args : Tir.atom list) : Tir.ty option =
  let atom_ty = function
    | Tir.AVar w -> Some w.Tir.v_ty
    | Tir.ALit (March_ast.Ast.LitInt _) -> Some Tir.TInt
    | Tir.ALit (March_ast.Ast.LitFloat _) -> Some Tir.TFloat
    | _ -> None
  in
  let all_are ty = args <> [] && List.for_all (fun a -> atom_ty a = Some ty) args in
  match name with
  | "+" | "-" | "*" | "/" | "%" ->
    if all_are Tir.TInt then Some Tir.TInt
    else if all_are Tir.TFloat then Some Tir.TFloat
    else None
  | "==" | "!=" | "<" | "<=" | ">" | ">=" | "&&" | "||" | "not" -> Some Tir.TBool
  | _ -> None

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
  | Tir.EApp (f, args) ->
    (match f.Tir.v_ty with
     | Tir.TFn (_, r) -> Some r
     | _ -> builtin_op_result_ty f.Tir.v_name args)
  (* The arms of a case agree on their type, so any one that can be typed
     types the whole thing.  A scope whose value is a [match]/[if] (the usual
     way a function ends) was otherwise "type unknown", and the scope-end drop
     of every tuple destructured in it was refused: `let (front, tail) = split(..)`
     followed by an `if` leaked the pair and what it owned. *)
  | Tir.ECase (_, brs, def) ->
    let first_typed =
      List.find_map (fun (br : Tir.branch) ->
          match tir_expr_ty br.Tir.br_body with
          | Some (Tir.TVar _) | None -> None
          | some -> some) brs
    in
    (match first_typed with
     | Some _ as r -> r
     | None ->
       (match def with
        | Some d ->
          (match tir_expr_ty d with Some (Tir.TVar _) | None -> None | r -> r)
        | None -> None))
  | Tir.EField (Tir.AVar src, f) ->
    (match src.Tir.v_ty with
     | Tir.TRecord fs -> List.assoc_opt f fs
     | Tir.TTuple ts when Tir_names.is_fv_field f ->
       List.nth_opt ts (Tir_names.fv_field_index f)
     | _ -> None)
  | Tir.EAlloc (ty, _) | Tir.EStackAlloc (ty, _) -> Some ty
  (* A tuple literal is typed by its elements.  Every atom must be typed, or
     the whole is unknown. *)
  | Tir.ETuple atoms ->
    let tys = List.filter_map (function
        | Tir.AVar w -> Some w.Tir.v_ty
        | Tir.ALit (March_ast.Ast.LitInt _) -> Some Tir.TInt
        | Tir.ALit (March_ast.Ast.LitBool _) -> Some Tir.TBool
        | Tir.ALit (March_ast.Ast.LitFloat _) -> Some Tir.TFloat
        | Tir.ALit (March_ast.Ast.LitString _) -> Some Tir.TString
        | _ -> None) atoms in
    if List.length tys = List.length atoms then Some (Tir.TTuple tys) else None
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

(** [Some ty] when [e]'s value is the owned result of a call (an [EApp] at
    the end of its [ELet]/[ESeq] chain) of a type that needs RC, so that
    discarding [e] as a statement would leak it; [None] otherwise, including
    whenever the type cannot be determined.  See [insert_rc_expr]'s [ESeq]
    case. *)
let discarded_call_result_ty (env : env) (e : Tir.expr) : Tir.ty option =
  let rec tail = function
    | Tir.ELet (_, _, body) | Tir.ESeq (_, body) -> tail body
    | x -> x
  in
  match tail e with
  | Tir.EApp _ ->
    (match tir_expr_ty e with
     (* Unit is sometimes typed as the empty tuple, which [needs_rc] counts as
        an aggregate; a unit-returning statement ([println(s)]) has nothing to
        release. *)
     | Some (Tir.TTuple [] | Tir.TUnit) -> None
     | Some ty when needs_rc env ty -> Some ty
     | _ -> None)
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
let rec used_only_as_field_source ?(releases_ok = false) (name : string) (e : Tir.expr) : bool =
  let recur = used_only_as_field_source ~releases_ok in
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
  (* [~releases_ok]: a release of [name] is not a use.  Only for a caller
     that tracks releases itself, per path ([insert_owned_aggregate_param_drops]). *)
  | Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _ when releases_ok -> true
  | Tir.EIncRC a | Tir.EDecRC a | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a
  | Tir.EFree a -> not (atom_hits a)
  (* A pure ALIAS binding [let v = p] moves ownership to [v] rather than
     consuming the aggregate at some other owner's behest.  Tuple destructuring
     lowers to exactly this ([let linear $p = t in let n = $p.$fv0 in ..]), so
     refusing it outright left a tuple parameter with no drop site at all.
     Follow the alias: the aggregate is still "only read" as long as the ALIAS
     is only read.  Releasing the original then releases the one shared cell
     once, which is what the alias made it. *)
  | Tir.ELet (v, Tir.EAtom (Tir.AVar w), e2)
    when String.equal w.Tir.v_name name ->
    (* Through an alias, a release is a use again: [~releases_ok]'s caller
       tracks releases of [name] only, and the alias's own scope-end drop
       ([let $p = pair in .. dec_rc $p], a destructured tuple parameter)
       would be a second release of the one cell. *)
    used_only_as_field_source ~releases_ok:false v.Tir.v_name e2
  | Tir.ELet (_, e1, e2) ->
    recur name e1 && recur name e2
  | Tir.ESeq (e1, e2) ->
    recur name e1 && recur name e2
  | Tir.ECase (a, branches, default) ->
    (* A case SCRUTINEE is consumed (add_scrutinee_free_for may free it). *)
    not (atom_hits a)
    && List.for_all (fun br -> recur name br.Tir.br_body)
         branches
    && (match default with
        | Some d -> recur name d
        | None -> true)
  | Tir.ELetRec (fns, body) ->
    List.for_all (fun fn -> recur name fn.Tir.fn_body) fns
    && recur name body

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

(** True when, on EVERY path through [e], each consuming use of [name] (a call
    or constructor argument, a returned atom, ...) is matched by an [inc_rc]
    of it on the same path.  Perceus dups a variable before each consuming use
    that is not its last, so then every consumer took a dup and the original
    reference is still owned when the path ends: a record that is passed to a
    function and then used as an update base ([let p = f(st) in { st with ..
    }]) still has to be released, and the "consumed, so not ours to drop"
    verdict leaked it (ClusterNode.core_register_ok's [identity_of(st, ..)]
    beside [{ st with reg: .. }]: the old state, every registration).  A
    last-use transfer has no inc, so it still counts as taken.  [None]-like
    answers (an alias of [name], a match on it, a capture, too many paths)
    are [false]: the conservative verdict, a leak, never a double release. *)
let path_counts (name : string) (e : Tir.expr) : (int * int) list option =
  let exception Unknown in
  let hits = function Tir.AVar w -> String.equal w.Tir.v_name name | _ -> false in
  let count atoms = List.length (List.filter hits atoms) in
  let cap = 256 in
  let product xs ys =
    let r = List.concat_map (fun (c1, i1) -> List.map (fun (c2, i2) -> (c1 + c2, i1 + i2)) ys) xs in
    let r = List.sort_uniq compare r in
    if List.length r > cap then raise Unknown else r in
  let rec go (e : Tir.expr) : (int * int) list =
    match e with
    | Tir.EIncRC a | Tir.EAtomicIncRC a -> [ (0, if hits a then 1 else 0) ]
    | Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _ -> [ (0, 0) ]
    | Tir.EField _ -> [ (0, 0) ]
    | Tir.EUpdate (_, fields) -> [ (count (List.map snd fields), 0) ]
    | Tir.EAtom a -> [ (count [ a ], 0) ]
    | Tir.EApp (_, args) -> [ (count args, 0) ]
    | Tir.ECallPtr (a, args) -> [ (count (a :: args), 0) ]
    | Tir.ETuple atoms | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) -> [ (count atoms, 0) ]
    | Tir.ERecord fields -> [ (count (List.map snd fields), 0) ]
    | Tir.EReuse (a, _, args) -> [ (count (a :: args), 0) ]
    | Tir.EAllocHole (tok, _, args, _) ->
      [ (count (match tok with Some a -> a :: args | None -> args), 0) ]
    | Tir.ESetField (a, _, b) -> [ (count [ a; b ], 0) ]
    | Tir.ELet (_, Tir.EAtom a, _) when hits a -> raise Unknown
    | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> product (go e1) (go e2)
    | Tir.ECase (a, brs, d) ->
      if hits a then raise Unknown;
      let r = List.concat_map (fun (b : Tir.branch) -> go b.Tir.br_body) brs
              @ (match d with Some d -> go d | None -> []) in
      List.sort_uniq compare r
    | Tir.ELetRec (fns, body) ->
      if List.exists (fun (f : Tir.fn_def) -> Perceus_liveness.name_free_in name f.Tir.fn_body) fns
      then raise Unknown;
      go body
  in
  match go e with
  | paths -> Some paths
  | exception Unknown -> None

(** [path_counts]: for each path through [e], the number of consuming uses of
    [name] and of [inc_rc]s of it, or [None] when [e] aliases, matches on or
    captures [name] (or has too many paths to list). *)
let covered_by_incs (name : string) (e : Tir.expr) : bool =
  match path_counts name e with
  | Some paths -> List.exists (fun (c, _) -> c > 0) paths
                  && List.for_all (fun (c, i) -> c <= i) paths
  | None -> false

(** True when EVERY tail of [e] is [name] itself: the scope hands the
    aggregate to its caller on every path, so there is nothing left to drop.
    The aggregate scope-end drop used to ask whether ANY tail was it, which
    skipped the drop on every path as soon as one branch returned the value,
    and the branches that only read it leaked it:
      let st = .. in if settled(st) do { .. st.failed .. } else st end
    leaked [st] on the [then] branch (SessionNode.Endpoint's LinkEnded, one
    state record and everything it held per session party;
    specs/progress/2026-10-07-mixed-tail-aggregate-leak.md).  A path that
    returns the value is left alone by [drop_agg_at_tails] (its balance is
    negative), so the drop now goes exactly on the other paths. *)
let rec every_tail_is_var (name : string) (e : Tir.expr) : bool =
  match e with
  | Tir.EAtom (Tir.AVar w) -> String.equal w.Tir.v_name name
  | Tir.ELet (_, _, body) -> every_tail_is_var name body
  | Tir.ESeq (_, body) -> every_tail_is_var name body
  | Tir.ECase (_, branches, default) ->
    List.for_all (fun br -> every_tail_is_var name br.Tir.br_body) branches
    && (match default with
        | Some d -> every_tail_is_var name d
        | None -> true)
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
    && needs_rc env v.Tir.v_ty
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

(* TRMC's destination-passing helpers take their parent cell as their final
   argument and write through it without consuming it.  After Defun the helper
   can be a closure, so the indirect-call branch must preserve this protocol
   too. *)
let dps_consumed_args callee args =
  let marker = "$dps" in
  let has_marker name =
    let rec go i =
      i + String.length marker <= String.length name
      && (String.sub name i (String.length marker) = marker || go (i + 1))
    in
    go 0
  in
  match callee, List.rev args with
  | Tir.AVar f, _ :: rev_args when has_marker f.Tir.v_name -> List.rev rev_args
  | _ -> args

(** Dup every TAIL-position projection of [name] in [e]: the value the scope
    returns.  Used by the aggregate scope-end drop in [insert_rc_expr]'s ELet
    case, which releases the aggregate AFTER its scope's result is computed
    ([let tmp = e2 in dec_rc v; tmp]).  A field that escapes [e2] through a
    binding or an argument has already been dup'd by the borrowed-field
    logic, but a field that IS the result ([let m = .. in m.addr]) is an
    [EField] in tail position, which borrows ([EField] never dups an aggregate
    source): the release then freed a String the caller went on to own.
    Seen as a use-after-free in two-node's cluster_fd_release
    (ClusterNode.core_link_closed: [match core_member(..) do Some(m) ->
    m.addr ..] passed to [Map.remove]), masked on main by a leak in
    Msgpack.decode_one's tuple matches until
    specs/progress/2026-09-30-compiled-tuple-destructure-leaks-moved-fields.md
    removed it.  An unknown type is treated as heap-carrying; the dup of a
    tagged scalar is a no-op at run time. *)
let rec dup_tail_projections (env : env) (name : string) (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.EField (Tir.AVar w, _) when String.equal w.Tir.v_name name ->
    let ty = match tir_expr_ty e with Some t -> t | None -> Tir.TVar "_" in
    if needs_rc env ty then begin
      let t = fresh_rc_var ty in
      Tir.ELet (t, e, Tir.ESeq (incrc_for env w (Tir.AVar t), Tir.EAtom (Tir.AVar t)))
    end else e
  | Tir.ELet (x, e1, body) -> Tir.ELet (x, e1, dup_tail_projections env name body)
  | Tir.ESeq (a, body) -> Tir.ESeq (a, dup_tail_projections env name body)
  | Tir.ECase (a, brs, d) ->
    Tir.ECase (a,
      List.map (fun br -> { br with Tir.br_body = dup_tail_projections env name br.Tir.br_body }) brs,
      Option.map (dup_tail_projections env name) d)
  | _ -> e

(** Release the owned aggregate [v] at every TAIL of its scope [e], or [None]
    when some tail cannot be handled.

    A tail that is a CALL keeps being a call: the release goes in FRONT of it
    ([dec_rc v; f(..)]), so a tail-recursive loop that destructures a tuple on
    each iteration is still a loop.  Wrapping it ([let tmp = f(..) in dec_rc v;
    tmp]) pushes the call out of tail position and a loop over millions of
    items overflows the stack.  Releasing first is sound when nothing the call
    still reads is owned only by [v]: a field passed at an OWNED position was
    dup'd by the borrowed-field logic, and a field passed at a BORROWED
    parameter position of a known callee has no such dup and is read for the
    whole call, so that case stays a post-call release.  Any other tail is
    bound first ([let tmp = tail in dec_rc v; tmp]), which needs its type. *)
(* Whether [e] can hold more than one path to a tail, so a release inside it
   says nothing about every path: a case, or a let/seq leading to one. *)
let rec is_branching (e : Tir.expr) : bool =
  match e with
  | Tir.ECase _ -> true
  | Tir.ELet (_, _, body) | Tir.ESeq (_, body) -> is_branching body
  | _ -> false

let drop_agg_at_tails (env : env) (v : Tir.var) (e : Tir.expr) : Tir.expr option =
  let name = v.Tir.v_name in
  (* [v] and its pure aliases, then the variables projected out of them. *)
  let owners = Hashtbl.create 4 in
  Hashtbl.replace owners name ();
  let projected = Hashtbl.create 8 in
  (* A value still pointing INTO [v] without its own reference: a field
     projection of [v] or of such a value, an alias of one, or a pattern
     variable bound by matching one.  Only direct projections of [v] used to
     count, so in
       match e.to do Cons(a, _) -> check(a.address, ..) end
     [a] and [a.address] were missed, [e] was released in front of the call,
     and [check] read a freed String (forgepm's Mail.Email tests). *)
  let points_into (src : Tir.var) =
    Hashtbl.mem owners src.Tir.v_name || Hashtbl.mem projected src.Tir.v_name in
  let rec scan (x : Tir.expr) : unit =
    match x with
    | Tir.ELet (w, Tir.EAtom (Tir.AVar src), body) when Hashtbl.mem owners src.Tir.v_name ->
      Hashtbl.replace owners w.Tir.v_name (); scan body
    | Tir.ELet (w, Tir.EAtom (Tir.AVar src), body) when Hashtbl.mem projected src.Tir.v_name ->
      Hashtbl.replace projected w.Tir.v_name (); scan body
    | Tir.ELet (w, Tir.EField (Tir.AVar src, _), body) when points_into src ->
      Hashtbl.replace projected w.Tir.v_name (); scan body
    | Tir.ELet (_, e1, body) -> scan e1; scan body
    | Tir.ESeq (a, body) -> scan a; scan body
    | Tir.ELetRec (_, body) -> scan body
    | Tir.ECase (a, brs, d) ->
      let scrut_points_into = match a with
        | Tir.AVar w -> points_into w
        | _ -> false in
      List.iter (fun (br : Tir.branch) ->
          if scrut_points_into then
            List.iter (fun (bv : Tir.var) ->
                Hashtbl.replace projected bv.Tir.v_name ()) br.Tir.br_vars;
          scan br.Tir.br_body) brs;
      Option.iter scan d
    | _ -> ()
  in
  scan e;
  let reads_borrowed_projection (callee : string) (args : Tir.atom list) =
    List.exists (fun (i, a) ->
        match a with
        | Tir.AVar w ->
          Hashtbl.mem projected w.Tir.v_name
          && needs_rc env w.Tir.v_ty
          && Borrow.is_borrowed env.borrow_map callee i
        | _ -> false)
      (List.mapi (fun i a -> (i, a)) args)
  in
  let call_is_safe (tail : Tir.expr) : bool =
    match tail with
    | Tir.EApp (f, args) ->
      not (String.equal f.Tir.v_name name)
      && not (reads_borrowed_projection f.Tir.v_name args)
    | Tir.ECallPtr (Tir.AVar f, args) ->
      (* Indirect calls consume their arguments, except an extern, whose
         parameter ownership comes from the borrow map. *)
      not (StringSet.mem f.Tir.v_name env.extern_names)
      || not (reads_borrowed_projection f.Tir.v_name args)
    | Tir.ECallPtr _ -> false
    | _ -> false
  in
  let ok = ref true in
  (* A path that already releases [v] (a dead-at-entry [dec_rc v] Perceus put
     at the head of a branch that does not use it, or any release on the way
     to the tail) is left as it is; only the paths that reach a tail still
     owning [v] get the drop.  Before, a release on ONE branch suppressed the
     drop on all of them: in
       match o do Some(e) -> if e.present do Some({ e with .. }) else None end
     the [else] branch released [e] and the [then] branch leaked it, with the
     field the update replaced (GlobalRegistry.unregister_own, every session). *)
  (* [bal]: the [inc_rc]s of [v] minus its consuming uses so far on this path.
     Perceus dups [v] before every consuming use that is not its last, so
     [bal >= 0] at a tail means every consumer took a dup and [v]'s own
     reference is still here to release; [bal < 0] means the path handed it
     over (returned it, stored it, passed it on last).  A non-tail piece whose
     paths disagree, or that aliases or captures [v], leaves the rest of the
     path alone: a leak at worst. *)
  let delta (x : Tir.expr) : int option =
    match path_counts name x with
    | Some ((c, i) :: rest) when List.for_all (fun (c', i') -> i' - c' = i - c) rest -> Some (i - c)
    | Some [] -> Some 0
    | _ -> None
  in
  let rec go bal (x : Tir.expr) : Tir.expr =
    match x with
    | _ when releases_var name x && not (is_branching x) -> x
    | Tir.ELet (_, e1, _) when releases_var name e1 -> x
    | Tir.ESeq (a, _) when releases_var name a -> x
    | Tir.ELet (w, e1, body) ->
      (match delta e1 with
       | Some d -> Tir.ELet (w, e1, go (bal + d) body)
       (* The paths of [e1] disagree (one hands [v] over, another only reads
          it), and [v] is dead in [body]: its lifetime ends inside [e1], so
          the per-path drop belongs at [e1]'s tails, each path's value bound
          before the release. Left alone, a handler's
            let $result = if settled(state) do state else { .. } end in ..
          leaked [state] on the [else] path, with every heap field it held
          (SessionNode.Endpoint's AwaitOutcome, once per session party;
          specs/progress/2026-10-07-mixed-tail-aggregate-leak.md). *)
       | None when is_branching e1 && not (Perceus_liveness.name_free_in name body) ->
         Tir.ELet (w, go bal e1, body)
       | None -> x)
    | Tir.ESeq (a, body) ->
      (match delta a with
       | Some d -> Tir.ESeq (a, go (bal + d) body)
       | None -> x)
    | Tir.ECase (Tir.AVar w, _, _) when String.equal w.Tir.v_name name -> x
    | Tir.ECase (a, brs, d) ->
      Tir.ECase (a,
        List.map (fun (br : Tir.branch) ->
            { br with Tir.br_body = go bal br.Tir.br_body }) brs,
        Option.map (go bal) d)
    | Tir.ELetRec (fns, _)
      when List.exists (fun (f : Tir.fn_def) -> Perceus_liveness.name_free_in name f.Tir.fn_body) fns -> x
    | tail when (match delta tail with Some d -> bal + d < 0 | None -> true) -> tail
    (* A literal reads nothing, so the release goes in front of it (the
       actor handler's trailing `:unit`; a literal has no type to bind). *)
    | Tir.EAtom (Tir.ALit _) as tail -> Tir.ESeq (decrc_for env v (Tir.AVar v), tail)
    | (Tir.EApp _ | Tir.ECallPtr _) as tail when call_is_safe tail ->
      Tir.ESeq (decrc_for env v (Tir.AVar v), tail)
    | tail ->
      (match tir_expr_ty tail with
       | Some ty ->
         let tmp = fresh_rc_var ty in
         Tir.ELet (tmp, dup_tail_projections env name tail,
                   Tir.ESeq (decrc_for env v (Tir.AVar v), Tir.EAtom (Tir.AVar tmp)))
       | None -> ok := false; tail)
  in
  let r = go 0 e in
  if !ok then Some r else None

(** True for the source of an actor handler's state load: the handler's
    linear [$actor] struct, or (under [--hot-reload]) the separate state
    record [$f_state_v] loaded out of it.

    [Lower_actor] lowers every handler as

      let $sf_f = $actor.f in ..                 -- load each state field
      let state = { f = $sf_f, .. } in           -- hand them to the body
      let $result = <body> in
      reuse $actor as Name_Actor(.., $result.f, ..)   -- write the new state back

    so the loads MOVE each field out of the struct, and the [EReuse] write-back
    overwrites the slot without releasing what was there.  Classified as a
    borrowed projection (the record-field rule below), each heap field was
    dup'd into [state] instead, and that extra reference was never released:
    every message to a compiled actor leaked one reference per heap state
    field -- the cell holding the old value, for good.  depot's Pool actor
    leaked its idle list's cons cell (and the connection in it) on every
    checkout, a steady leak in an idle conduit worker.  An owned binding takes
    the field over instead: [state] consumes it once, the write-back stores the
    new value, nothing is left over. *)
let is_actor_move_source (src : Tir.var) : bool =
  (String.equal src.Tir.v_name Tir_names.actor_param && src.Tir.v_lin = Tir.Lin)
  || String.equal src.Tir.v_name Tir_names.actor_state_ptr_var

(** The variable a projection reads from: [src] for [src.f], and the root
    of a nested chain, [d] for [let a = d.x in a.y] (a three-deep read
    [st.a.b.c] lowers to exactly such a chain). *)
let rec projection_root (e : Tir.expr) : Tir.var option =
  match e with
  | Tir.EField (Tir.AVar s, _) -> Some s
  | Tir.ELet (iv, rhs, body) ->
    (match projection_root body with
     | Some s when String.equal s.Tir.v_name iv.Tir.v_name -> projection_root rhs
     | r -> r)
  | _ -> None

(** [name] and every variable it points into through [field_owner]. *)
let owner_chain (env : env) (name : string) : string list =
  let rec go seen n =
    match StringMap.find_opt n env.field_owner with
    | Some o when not (List.mem o seen) -> go (o :: seen) o
    | _ -> seen
  in
  go [] name

(** Owned-call drop fusion: decide whether the known call [f(args)] can go to
    an owned clone of [f] instead of being followed by caller-side drops of
    [post_dec_vars] (the arguments at [f]'s borrowed positions whose last use
    is this call, which the caller owns; one entry per variable).  Returns
    the clone's var, the post-call drops that remain, and the extra
    [EIncRC]s to emit before the call (one entry per reference).

    A variable at one borrowed position is handed to that position.  Inside
    a clone, a variable at k > 1 borrowed positions is handed to all k, and
    the caller dups it k - 1 times before the call: its one reference
    becomes one per position, so no release is left after the call.  In an
    ORIGINAL function such a variable keeps its post-call drop, the base
    pipeline's shape there, so nothing the original did is lost.  In a
    clone the variable may be owned where the original only borrowed it,
    and a drop kept after a clone's tail call turned a loop of the original
    into real recursion (specs/progress/2026-10-07-owned-call-dup-arg.md).
    A variable bound by an [EAlloc] in this function is never handed
    ([owned_calls.oc_alloc_bound]).  A variable that also sits at an OWNED
    position never reaches here (the caller's dual-position accounting):
    borrow inference makes such a variable owned in the original as well (a
    parameter at an owned position is owned, and so is a scrutinee whose
    matched field reaches one), so the original keeps the same post-call
    drop and the clone's call has the original's shape.

    When a call is redirected, EVERY handable variable is handed over, not
    only the profitable ones, so the redirected call keeps no post-call drop
    at all and stays a tail call if it was one.  (A clone parameter its body
    never mentions is released at the clone's entry,
    [Perceus.perceus_owned].)

    Loops: inside [f] itself a recursive call to [f] is never redirected (its
    [Llvm_tco] back edge stays where it was).  Inside a clone, a call to [f]
    goes to the clone for ITS positions -- the clone itself when they match
    (a self loop), else a sibling clone, with which it forms a clean
    tail-call cycle that [Llvm_tco]'s mutual-TCO groups flatten like any
    other. *)
let owned_call_redirect (env : env) (oc : owned_calls) (f : Tir.var)
    (args : Tir.atom list) (post_dec_vars : Tir.var list)
    : (Tir.var * Tir.var list * Tir.var list) option =
  let callee = f.Tir.v_name in
  match Hashtbl.find_opt oc.oc_fns callee with
  | None -> None
  | Some _ ->
    let cur = env.current_fn_name in
    let in_clone = Hashtbl.mem oc.oc_clones cur in
    let positions_of name =
      List.concat (List.mapi (fun i a -> match a with
          | Tir.AVar v when String.equal v.Tir.v_name name -> [i]
          | _ -> []) args)
    in
    let handed =
      List.filter_map (fun (v : Tir.var) ->
          let ps = positions_of v.Tir.v_name in
          if ps = [] || StringSet.mem v.Tir.v_name !(oc.oc_alloc_bound)
             || (List.length ps > 1 && not in_clone) then None
          else Some (v, ps))
        post_dec_vars
    in
    (* Profitability gate, for originals only: some handed position must be
       one the clone destructures ([oc_useful]).  Inside a clone there is no
       gate: its variables that were BORROWED in the original (its owned
       parameters, and the fields it matches out of them) are owned there,
       and a call that kept a drop of one after it would no longer be a tail
       call where the original's was -- a self or mutual loop of the
       original would become real recursion in the clone. *)
    let gate =
      in_clone
      || List.exists (fun (_, ps) ->
          List.exists (fun i -> Hashtbl.mem oc.oc_useful (callee, i)) ps)
        handed
    in
    (* Inside [f] itself a recursive call to [f] keeps its existing shape
       (and its [Llvm_tco] back edge). *)
    if handed = [] || not gate || String.equal callee cur then None
    else begin
      let positions = List.sort compare (List.concat_map snd handed) in
      let name = owned_clone_name callee positions in
      if not (Hashtbl.mem oc.oc_clones name) then begin
        Hashtbl.replace oc.oc_clones name (callee, positions);
        Queue.push (name, callee, positions) oc.oc_pending
      end;
      let handed_names =
        List.fold_left (fun s ((v : Tir.var), _) -> StringSet.add v.Tir.v_name s)
          StringSet.empty handed in
      let rest = List.filter (fun (v : Tir.var) ->
          not (StringSet.mem v.Tir.v_name handed_names)) post_dec_vars in
      (* One reference owned, [List.length ps] consumers: dup the rest. *)
      let extra_incs =
        List.concat_map (fun (v, ps) ->
            List.init (List.length ps - 1) (fun _ -> v)) handed in
      Some ({ f with Tir.v_name = name }, rest, extra_incs)
    end

(** Insert RC operations into an expression.
    Returns [(expr', live_before)] where expr' has RC ops inserted and
    live_before is the set of variables live before this expression. *)
let rec insert_rc_expr (env : env) (e : Tir.expr) (live_after : live_set)
    : Tir.expr * live_set =
  match e with
  | Tir.EAtom (Tir.AVar v) ->
    let lb = StringSet.add v.Tir.v_name live_after in
    if v.Tir.v_lin = Tir.Unr && needs_rc env v.Tir.v_ty
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
               && needs_rc env v.Tir.v_ty
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
    (* Owned-call drop fusion: hand dying borrowed arguments to an owned
       clone instead of dropping them after the call (inside a clone, with
       one dup per extra position a variable occupies; see
       [owned_call_redirect]).  Never when a variable also sits at an owned
       position (the dual-position accounting above stays exactly as it
       was).  The self-call test is re-taken against the final callee: a
       redirect can turn a call into a clone's self call. *)
    let e, f, post_dec_vars, inc_vars, is_self_call =
      match env.owned_calls with
      | Some oc when dual_pos_vars = [] && post_dec_vars <> [] ->
        (match owned_call_redirect env oc f args post_dec_vars with
         | Some (f', rest, extra_incs) ->
           (Tir.EApp (f', args), f', rest, inc_vars @ extra_incs,
            String.equal f'.Tir.v_name env.current_fn_name)
         | None -> (e, f, post_dec_vars, inc_vars, is_self_call))
      | _ -> (e, f, post_dec_vars, inc_vars, is_self_call)
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
               && needs_rc env v.Tir.v_ty
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
    (* A closure call consumes its arguments (see [Clo_flags] for the whole
       convention).  For args still live after the call, [find_inc_vars]
       inserts an EIncRC so the callee's consumed reference is balanced
       against the caller's retained one.  For dead-after args, no IncRC is
       emitted — the caller's reference transfers to the callee.  The callee
       side is what makes that true: [Borrow.infer_module] pins every apply-fn
       parameter owned, and a [$clo_wrap] releases what its target borrows.
       Before both, a read-only parameter stayed borrowed and a fresh argument
       leaked once per call. *)
    let all_atoms = a :: dps_consumed_args a args in
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
      (* No arm for [to_string(x)] / [Show$String.show(x)] any more: both lower
         to march_value_to_string, which returns its OWN reference (+1, a
         [march_incrc] on a String argument), not an alias of a borrowed [x].
         Treating the result as borrowed skipped its release, one leaked string
         per call: Show$Option.show's ["Some(" ++ show(x) ++ ")"] over an erased
         payload (specs/progress/2026-10-06-record-get-erased-option-drop.md). *)
      | Tir.ELet (iv, Tir.EField (Tir.AVar src, _), ibody)
        when needs_rc env iv.Tir.v_ty
             && (StringSet.mem src.Tir.v_name bfv || field_src_is_borrowed src) ->
        (* [iv] is a borrowed field var inside this sub-scope; check the body
           with that knowledge. *)
        result_is_borrowed_field (StringSet.add iv.Tir.v_name bfv) ibody
      | Tir.ELet (iv, rhs, ibody)
        when needs_rc env iv.Tir.v_ty && result_is_borrowed_field bfv rhs ->
        (* [iv] is bound to a nested projection chain that is itself a
           borrowed field reference -- a three-deep read [st.a.b.c] lowers to
           [let t2 = (let t1 = (let t0 = st.a in t0.b) in t1.c)], so the
           middle binding's RHS is an ELet, not an EField, and the arm above
           never fired. Falling through to the arm below dropped [iv] from
           [bfv], the chain's last projection then looked owned, and a
           consuming call on it got no dup: the record's drop freed the field
           a second time (RC underflow; cluster_node's
           [st.driver.swim.members]). The binding's own classification (its
           ELet processed below) already treats [iv] as borrowed; this keeps
           the lookahead consistent with it. *)
        result_is_borrowed_field (StringSet.add iv.Tir.v_name bfv) ibody
      | Tir.ELet (_, _, ibody) -> result_is_borrowed_field bfv ibody
      | Tir.EField (Tir.AVar src, _)
        when (match src.Tir.v_ty with Tir.TPtr _ -> false | _ -> true)
             && (StringSet.mem src.Tir.v_name bfv || field_src_is_borrowed src) ->
        (* The chain ends in a projection out of a borrowed record — the
           nested-record read [h.identity.name] lowers to exactly this,
           [let r = h.identity in r.name].  The result aliases a field the
           record owner still holds, the same as the one-level [h.nonce] case
           the EField arm below handles.  Without this arm the binding was
           classified as owned, so a constructor capture took it without a
           dup and that constructor's drop released the owner's string
           (node_discovery: Handshake.encode_hello freed my_id.node_id). *)
        true
      | _ -> false
    in
    let is_borrowed_field =
      match e1 with
      | Tir.EField (Tir.AVar src, _) when is_actor_move_source src ->
        (* A handler's state load MOVES the field out of the actor struct (see
           [is_actor_move_source]); the binding owns it. *)
        false
      | _ when needs_rc env v.Tir.v_ty
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
        when needs_rc env v.Tir.v_ty
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
        when needs_rc env v.Tir.v_ty
             && StringSet.mem src.Tir.v_name env.borrowed_field_vars ->
        (* Alias of a borrowed field var — propagate the borrowed status. *)
        true
      | Tir.EAtom (Tir.AVar src)
        when needs_rc env v.Tir.v_ty
             && src.Tir.v_name = Tir_names.actor_param ->
        (* An actor handler's `self`: an alias of the handler's [$actor]
           parameter.  [$actor] is Lin, so no RC op touches it; the reference
           it carries belongs to the scheduler that dispatched this handler.
           Classified owned, `self` was dropped at scope exit (a net -1 on the
           actor record for every handler that names `self`) and passed to a
           consuming callee without a dup.  Borrowed, a consuming use dups it
           and scope exit leaves it alone. *)
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
    (* The owner must OUTLIVE a borrowed field.  Conditions 3 and 4 above
       classify [let v = src.f] as borrowed because [src] is still in scope or
       used again in [e2] -- but that later use may CONSUME [src] (hand it to
       a call, or be its last use, after which it is released) while [v] is
       still to be read.  [let x = r.a; let n = take(r); x ++ ...] then read a
       string [take]'s drop of [r] had freed: a compiled-only use-after-free
       (the interpreter has no RC), found as a scripted session peer printing
       another string's bytes for a received order's field.
       specs/progress/2026-09-28-borrowed-field-outlives-owner.md.

       So when [src] is owned here (not live after this scope, not itself a
       borrowed field) and [e2] uses it other than as a projection source,
       [v] is not borrowed: it takes its own reference ([inc_rc] right after
       the projection) and is released as an ordinary owned binding.  A [src]
       that is only ever projected keeps the borrowed classification: nothing
       in [e2] releases it before the binding's scope ends. *)
    let dup_owned_field =
      is_borrowed_field
      (* A nested chain [let t = (let a = o.x in a.y)] has the same hazard as
         [let t = o.y]: [e2] consuming [o] frees what [t] reads.  Only the
         direct projection used to qualify, so [o.ap.fingerprint] followed by
         [active(o)] read a freed string (Topology's offer and drain lines). *)
      && (match (match e1 with
                 | Tir.EField (Tir.AVar src, _) -> Some src
                 | Tir.ELet _ -> projection_root e1
                 | _ -> None) with
          | Some src ->
            (match src.Tir.v_ty with Tir.TPtr _ -> false | _ -> true)
            && src.Tir.v_lin = Tir.Unr
            && v.Tir.v_lin = Tir.Unr
            && needs_rc env src.Tir.v_ty
            && not (StringSet.mem src.Tir.v_name live_after)
            && not (StringSet.mem src.Tir.v_name env.borrowed_field_vars)
            && not (StringSet.mem src.Tir.v_name env.closure_fvs)
            && not (String.equal src.Tir.v_name v.Tir.v_name)
            && not (used_only_as_field_source src.Tir.v_name e2)
          | _ -> false)
    in
    let is_borrowed_field = is_borrowed_field && not dup_owned_field in
    let owner =
      if not is_borrowed_field then None
      else match e1 with
        | Tir.EAtom (Tir.AVar src) ->
          (match StringMap.find_opt src.Tir.v_name env.field_owner with
           | Some o -> Some o
           | None -> Some src.Tir.v_name)
        | _ -> Option.map (fun (s : Tir.var) -> s.Tir.v_name) (projection_root e1)
    in
    let env_for_e2 =
      { env with
        var_ctx = StringMap.add v.Tir.v_name v env.var_ctx;
        borrowed_field_vars =
          if is_borrowed_field
          then StringSet.add v.Tir.v_name env.borrowed_field_vars
          else env.borrowed_field_vars;
        field_owner =
          (match owner with
           | Some o when not (String.equal o v.Tir.v_name) ->
             StringMap.add v.Tir.v_name o env.field_owner
           | _ -> StringMap.remove v.Tir.v_name env.field_owner) }
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
        if v.Tir.v_lin = Tir.Unr && needs_rc env v.Tir.v_ty then
          Tir.ESeq (decrc_for env v (Tir.AVar v), e2')
        else if v.Tir.v_lin = Tir.Lin || v.Tir.v_lin = Tir.Aff then
          if needs_rc env v.Tir.v_ty then
            Tir.ESeq (Tir.EFree (Tir.AVar v), e2')
          else
            e2'
        else
          e2'
      else if is_aggregate_ty env v.Tir.v_ty
              && v.Tir.v_lin = Tir.Unr
              && StringSet.mem v.Tir.v_name live_into_e2
              && not (StringSet.mem v.Tir.v_name live_after)
              && not (StringSet.mem v.Tir.v_name env.closure_fvs)
              && not (StringSet.mem v.Tir.v_name env.moved_vars)
              && not is_borrowed_field
              && not (every_tail_is_var v.Tir.v_name e2')
              (* A release on some paths no longer blocks the drop: it goes
                 on the paths that do not release ([drop_agg_at_tails]). *)
              (* Whether [v] is still owned is decided per path by
                 [drop_agg_at_tails]; the paths that hand it over keep it. *)
              && drop_agg_at_tails env v e2' <> None then
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

           [every_tail_is_var] excludes the aggregate being the scope's own
           result ([let b = {..} in b]), where the EAtom arm has already handed
           ownership to the caller and this dec would be a double-free.
           [moved_vars] excludes the aggregate being stored into another
           structure on any path. *)
        (match drop_agg_at_tails env v e2' with
         | Some dropped -> dropped
         | None -> e2')
      else
        e2'
    in
    (* [dup_owned_field]: the projection's own reference, taken before [e2]
       can release the owner. *)
    let e2'' = if dup_owned_field then Tir.ESeq (Tir.EIncRC (Tir.AVar v), e2'') else e2'' in
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
      | Tir.AVar v when needs_rc env v.Tir.v_ty
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
          || (needs_rc env v.Tir.v_ty
              && name_free_in v.Tir.v_name br.Tir.br_body)
          (* Tuples and records used to be forced "borrowed" here
             unconditionally, on the premise that they were [needs_rc = false]
             and Perceus never freed them.  That premise is gone: an aggregate
             owns its fields and is dropped like a variant ([needs_rc_of]), so
             a tuple scrutinee that is dead after the arm IS freed by
             [add_scrutinee_free_for], and [Llvm_case] hands each field to the
             arm as an OWNED reference (moved when the cell was unique, dup'd
             when it was shared).  Treating those fields as borrowed made every
             pattern variable that escaped take a SECOND reference nothing
             released, and skipped the drop of a dead field — a leak per moved
             field per call (specs/progress/2026-09-30-compiled-tuple-
             destructure-leaks-moved-fields.md).  A tuple that is NOT consumed
             here (live after the case, or still used in the arm) is already
             covered by the two disjuncts above, so a borrowed-derived tuple
             (an element of a borrowed list) keeps its borrowed fields. *)
        | _ -> false
      in
      (* The arm OWNS the scrutinee (dead after the case) but its body still
         mentions it, so no release is emitted at the arm head and the
         scrutinee dies somewhere inside the body: a cross-branch release in
         a nested arm, a move into a closure environment, a consuming call.
         Every one of those is now a DEEP release (lib/tir/drop.ml), so a
         field the pattern bound and the body still reads must not be left
         as a raw borrow from the scrutinee — the old "keep every br_var
         conservatively live" approximation did exactly that and, once the
         match compiler's single-site join points were inlined in place
         (lib/tir/lower_match.ml [bind_jp]), the nested-pattern shape

           case parents of Cons($f1, $f2) ->
             case $f2 of
               Nil -> dec_rc parents; let root = $f1 in …   -- read after free
               _   -> … parents …

         read freed memory (RC underflow abort in test/native goldens; a
         SIGSEGV when the scrutinee had moved into the fall-through
         closure).  Instead each field the body USES takes its own reference
         at the arm head ([scrutinee_field_dups] below) and is owned from
         there on — released at its last use like any local, by the ordinary
         rules — while a field the body never reads stays the scrutinee's,
         released by whatever releases the scrutinee.  One inc/dec pair per
         used field is the price; the approximation it replaces leaked every
         such field outright. *)
      let scrutinee_deferred = match a with
        | Tir.AVar v ->
          not (StringSet.mem v.Tir.v_name live_after)
          && needs_rc env v.Tir.v_ty
          && name_free_in v.Tir.v_name br.Tir.br_body
        | _ -> false
      in
      let scrutinee_field_dups =
        if scrutinee_deferred then
          List.filter (fun (bv : Tir.var) ->
              needs_rc env bv.Tir.v_ty
              && name_free_in bv.Tir.v_name br.Tir.br_body) br.Tir.br_vars
        else []
      in
      let la = if scrutinee_borrowed && not scrutinee_deferred then
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
      (* A field projected out of a scrutinee that is PROVABLY live across the
         whole case is a borrowed reference, exactly like [let f = rec.field]
         on a borrowed record parameter (the ELet [is_borrowed_field] case
         above, condition 1).  Mark such br_vars as borrowed field vars so the
         normal borrowed-field discipline applies to them:

           - a use at a BORROWED argument position emits neither a dup nor a
             post-call EDecRC (the [borrowed_field_vars] exclusions in the
             EApp/ECallPtr [post_dec_vars] filters, and the alias-binding arm
             of ELet which skips RC processing of [let a = <br_var>]);
           - a CONSUMING use (owned argument position, constructor capture,
             tail return) still gets its EIncRC dup, because the br_vars were
             re-added to [la] above and are therefore live at every such use.

         Without this, the accessor shape

           fn get(c : Chunk, i : Int) : Int do
             match c do Chunk(a) -> NativeArray.get_u8(a, i) end
           end

         emitted [inc_rc]/[dec_rc] around a read that never escapes the arm.
         Under the scheduler every RC op is atomic, so a read-only projection
         out of shared data became a contended cache line — measurably
         negative scaling (see specs/progress for the G73 measurements).

         SAFETY: the premise is "the parent outlives the arm", so this is
         gated on [live_after] membership ALONE, not on the full
         [scrutinee_borrowed] disjunction.  [scrutinee_borrowed]'s other two
         disjuncts are deliberately excluded:

           - [name_free_in v br_body] (the path-insensitive conservatism, §6
             of specs/perceus-invariants.md) only says the scrutinee is
             mentioned SOMEWHERE in the arm.  Ownership then transfers into
             the body, which may consume the scrutinee part-way through and
             free it while a projected field is still being read.  Today that
             field holds its own +1 and survives; eliding the dup there would
             turn a bounded leak into a use-after-free — the wrong direction.
           - TTuple/TRecord scrutinees are [needs_rc = false]: Perceus never
             sees the aggregate's lifetime at all, so "the parent outlives the
             arm" is not a premise it can discharge.

         Missing those cases only leaves an elidable pair on the table, which
         is the acceptable direction to be wrong in. *)
      let scrutinee_live_across_case = match a with
        | Tir.AVar v ->
          StringSet.mem v.Tir.v_name live_after
          (* ...and live for a reason that is a real guarantee. A scrutinee
             that is only CONSERVATIVELY live (see [env.cons_live]) was put in
             [live_after] by an enclosing arm's [scrutinee_borrowed], whose
             premise this binding has already declined to take. *)
          && not (StringSet.mem v.Tir.v_name env.cons_live)
        | _ -> false
      in
      let env_for_br =
        { env with
          var_ctx =
            List.fold_left (fun ctx (v : Tir.var) ->
              StringMap.add v.Tir.v_name v ctx
            ) env.var_ctx br.Tir.br_vars;
          borrowed_field_vars =
            if scrutinee_live_across_case then
              List.fold_left (fun s (v : Tir.var) ->
                if needs_rc env v.Tir.v_ty then StringSet.add v.Tir.v_name s else s
              ) env.borrowed_field_vars br.Tir.br_vars
            else env.borrowed_field_vars;
          (* Fields kept live only by [scrutinee_borrowed]'s conservatism, and
             not by the scrutinee genuinely outliving the arm, are recorded as
             such so a nested case over one of them does not mistake that for a
             guarantee. *)
          cons_live =
            if scrutinee_borrowed && not scrutinee_live_across_case
               && not scrutinee_deferred then
              List.fold_left (fun s (v : Tir.var) -> StringSet.add v.Tir.v_name s)
                env.cons_live br.Tir.br_vars
            else env.cons_live }
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
        if needs_rc env v.Tir.v_ty
           && not (StringSet.mem v.Tir.v_name live_before_br)
           && not (StringSet.mem v.Tir.v_name env.closure_fvs)
           && not (StringSet.mem v.Tir.v_name env.moved_vars)
           && not (StringSet.mem v.Tir.v_name env.borrowed_field_vars)
           (* A field the body never reads is still the deferred
              scrutinee's: it goes when the scrutinee goes. *)
           && not scrutinee_deferred then
          Tir.ESeq (decrc_for env v (Tir.AVar v), body_acc)
        else
          body_acc
      ) br.Tir.br_vars body'
      in
      let body'' = List.fold_right (fun (v : Tir.var) body_acc ->
          Tir.ESeq (incrc_for env v (Tir.AVar v), body_acc))
          scrutinee_field_dups body''
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
    (* The default arm is processed HERE, before the union, because its live
       set is part of the "live elsewhere" half of "dead here, live
       elsewhere".  Leaving it out made the union a union over the TAGGED
       branches only, so a variable live ONLY in the default arm was invisible
       to every other arm's [dead_here] and was never released there.  That is
       exactly the shape an `if` lowers to — one tagged branch plus a default —
       so `if k <= 0 do Nil else Cons(s, Nil) end` leaked [s] on the `Nil`
       side, on EVERY path through an if/else whose two sides disagree about a
       heap value.  A `match` over a variant, whose arms are all tagged, was
       always flat; that asymmetry is what made this survive so long.
       The [insert_rc_expr] calls still run branches-then-default, so the
       fresh-name counter sees the same order it always did. *)
    let default_processed = Option.map (fun d ->
      let (d_rc, d_lb) = insert_rc_expr env d live_after in
      (* Default branch: no constructor tag known, use original type.
         Only free the scrutinee if the branch body does NOT use it directly —
         if the body uses it, ownership transfers into the body. *)
      let d_rc' = (match a with
       | Tir.AVar v when needs_rc env v.Tir.v_ty
                      && not (StringSet.mem v.Tir.v_name live_after)
                      && not (name_free_in v.Tir.v_name d) ->
         Tir.ESeq (decrc_for env v (Tir.AVar v), d_rc)
       | _ -> d_rc)
      in
      (d_rc', d_lb)
    ) default in
    let union_live_br =
      let from_branches =
        List.fold_left (fun acc (_, _, lb, _) -> StringSet.union acc lb)
          StringSet.empty branches_processed in
      match default_processed with
      | Some (_, d_lb) -> StringSet.union from_branches d_lb
      | None -> from_branches
    in
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
        (* An owner whose borrowed projection this arm still reads is not
           released at the arm's head: [match d.tag do "k" -> .. d ..; other
           -> "unknown " ++ other end] freed [d], and the string [other]
           points into, before the concatenation.  Its release goes to the
           arm's tails instead, through the passes that place drops behind
           the last read of a projection: the owned-aggregate parameter drop
           and the scope-end aggregate drop.  Either may give up (a leak),
           never release early. *)
        |> (fun s ->
            StringSet.fold (fun live acc ->
                if StringSet.mem live env.borrowed_field_vars then
                  List.fold_left (fun acc o -> StringSet.remove o acc) acc
                    (owner_chain env live)
                else acc)
              live_before_br s)
      in
      let prepend body =
        StringSet.fold (fun name body_acc ->
          match StringMap.find_opt name env.var_ctx with
          | Some v when v.Tir.v_lin = Tir.Unr && needs_rc env v.Tir.v_ty ->
            Tir.ESeq (decrc_for env v (Tir.AVar v), body_acc)
          | _ -> body_acc
        ) dead_here body
      in
      (* Keep the scrutinee's destructuring release ([add_scrutinee_free_for])
         at the HEAD of the arm, with these releases after it.  Codegen
         recognises it only at the head of a run of releases
         ([Llvm_case.strip_scrut_decrc]); behind anything else it compiles as a
         plain release with no shared-path dups of the extracted fields.  A
         bare [dec_rc] in front was tolerated, but [Drop] later turns these
         into [__drop$T(..)] calls and the optimiser may inline those, so in
         front of the scrutinee's release they hid it: depot's
         Pool.handle_checkout moved [conn]/[rest] out of a still-shared idle
         list behind a dead [cfg]'s drop, and the connection was freed while
         being handed to the caller.  The order is otherwise immaterial: the
         releases are of distinct, dead values. *)
      match body with
      | Tir.ESeq ((Tir.EDecRC (Tir.AVar sv) | Tir.EAtomicDecRC (Tir.AVar sv)
                   as scrut_dec), rest)
        when (match scrutinee_name with
              | Some n -> String.equal sv.Tir.v_name n
              | None -> false) ->
        Tir.ESeq (scrut_dec, prepend rest)
      | _ -> prepend body
    in
    let branches' = List.map (fun (br, body', live_before_br, bound) ->
      let br_arity = List.length br.Tir.br_vars in
      let body_with_scrut = add_scrutinee_free_for br.Tir.br_tag br_arity body' in
      let body_with_cross = add_cross_decrcs live_before_br bound body_with_scrut in
      { br with Tir.br_body = body_with_cross }
    ) branches_processed in
    let default' = Option.map (fun (d_rc', d_lb) ->
      (* Cross-branch EDecRC for the default arm too *)
      add_cross_decrcs d_lb StringSet.empty d_rc'
    ) default_processed in
    (* Compute live_before from the original liveness *)
    let lb = live_before e live_after in
    (Tir.ECase (a, branches', default'), lb)

  | Tir.ESeq (e1, e2) ->
    (match discarded_call_result_ty env e1 with
     | Some ty ->
       (* A statement [f(x)] whose call returns an owned heap value lowers to
          [ESeq (f(x), rest)], which drops the value on the floor: nothing
          ever released it.  A PURE call never showed this (the optimiser
          deletes it), but an impure one does: every [send(p, m)] written as
          a statement leaked the [Some(())] it returns.  Rebinding the value
          to a fresh, unused [let] hands it to the dead-binding branch above,
          the same release [let _ = send(p, m)] already got. *)
       insert_rc_expr env (Tir.ELet (fresh_rc_var ty, e1, e2)) live_after
     | None ->
       let (e2', l2) = insert_rc_expr env e2 live_after in
       let (e1', l1) = insert_rc_expr env e1 l2 in
       (Tir.ESeq (e1', e2'), l1))

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

       An AGGREGATE source is excluded from [find_inc_vars] outright.  That
       function documents its atoms as sitting at CONSUMING positions, and a
       projection is not one: it emitted an inc whenever the source was live
       after the read, which is ALWAYS true of a borrowed parameter, and
       nothing ever undid it.  A record passed to a field-reading helper
       therefore never reached refcount zero -- 2001 live objects over a
       1000-iteration loop, against 1 when the same field is read inline.

       This exclusion was tried once before and reverted, because it made
       test/native/record_pattern.march die with a nondeterministic
       SIGBUS/RC-underflow.  That was NOT this rule's bug: those incs were
       masking a genuine double release in [Drop.droppable_ctors], which
       synthesized a deep drop for a NON-GENERIC Option-shaped type that
       codegen encodes as a niche -- releasing the one cell twice, once as the
       box and once as the payload.  With that fixed (see the concrete-niche
       check there) the exclusion is sound, and record_pattern.march passes
       repeatedly. *)
    (* A closure ENVIRONMENT ([$clo : TPtr], an apply fn's first param) is a
       projection source for the same reason.  Every capture read of a
       live-after [$clo] dup'd it, and the one release Perceus splices after
       the capture-read prefix ([Perceus.insert_apply_fn_clo_drop]) only undid
       that dup, so the reference the caller transferred into the apply fn was
       never released: the environment, and with it every capture, lived
       forever.  Measured on `fn mk(a, b) = fn x -> length(a) + length(b) + x`
       called once per iteration: 6 objects per call (the environment and five
       list cells).  This change and the widened gate in
       [Drop.owning_apply_fns] land together: the spliced release now frees the
       environment, and the drop pass must release the captures of exactly
       the closures whose environment owns them.
       See specs/progress/2026-09-13-closure-environment-released.md. *)
    let a_is_aggregate = match a with
      | Tir.AVar v -> (match v.Tir.v_ty with
                       | Tir.TPtr _ -> true
                       (* nominal records included: see [is_aggregate_ty] *)
                       | t -> is_aggregate_ty env t)
      | _ -> false
    in
    let inc_vars =
      if a_is_aggregate then []
      else find_inc_vars ~include_borrowed_fields:false env [a] live_after in
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
