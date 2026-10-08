(** Perceus RC Analysis — Pass 4.

    Inserts reference-counting operations (EIncRC / EDecRC) into the TIR,
    exploiting static last-use information to elide as many RC ops as
    possible.  Linear and affine values get EFree instead of RC.
    Adjacent Inc/Dec cancel pairs are removed, and FBIP reuse is detected.

    Atomic RC (EAtomicIncRC / EAtomicDecRC) is emitted for values that are
    passed as message arguments to [send()].  These values may cross actor
    thread boundaries and require C11-atomic RC to avoid data races.
    All other values use fast non-atomic RC (march_incrc_local / march_decrc_local).

    Borrow Inference integration (Pass 4.0, via Borrow.infer_module):
    Before inserting RC ops, the pass analyses every function to determine
    which parameters are "borrowed" — only read (via pattern match / field
    access), never stored, returned, or passed to an owning position.
    For borrowed parameters:
    - In the callee: no EDecRC is emitted (the parameter is added to the
      [borrowed] live-at-exit set, suppressing last-use ownership transfer).
    - At call sites: no EIncRC is emitted for arguments at borrowed positions
      that are still live after the call.
    - At call sites where the borrowed arg IS the caller's last use (ownership
      would normally transfer): the caller instead emits EDecRC after the call,
      since the callee will not decrement the value.

    ── File split (Wave 3 Task 5) ───────────────────────────────────────────

    This file is the pass ORCHESTRATOR: it keeps the [env] type, the Phase 2
    (RC insertion) core [insert_rc_expr]/[insert_rc], and the public entry
    point [perceus].  Four phases that were self-contained enough to not
    need [env] (or only consume it as a caller, never as a parameter of
    their own recursion) were split into focused modules, moved VERBATIM
    (cut-paste; only cross-module qualification changed — no behavior
    edits):

    - [Perceus_liveness]: Phase 1 backwards liveness ([live_before]),
      [name_free_in] (shared by Phase 2's core and Phases 3/4), and the
      [vars_of_atom]/[vars_of_atoms] atom helpers.  Pure [Tir.expr] ->
      [StringSet.t] analyses, never took an [env] before or after Task 4.
    - [Perceus_elide]: Phase 3, [elide_cancel_pairs] (adjacent EIncRC/EDecRC
      cancel-pair removal).  Depends on [Perceus_liveness.name_free_in].
    - [Perceus_fbip]: Phase 4, [insert_fbip] (FBIP FreeIn-Place reuse
      detection) plus [same_arity] and the [fbip_arity_marker] constant
      it decodes.  Depends only on [Perceus_liveness.name_free_in] — the
      marker moved here TOO (not just its consumer) because [Perceus]
      already depends on [Perceus_fbip] (the orchestrator calls
      [insert_fbip]), so the marker constant must not create a dependency
      back the other way; see [fbip_arity_marker]'s re-export below and
      [Perceus_fbip]'s header comment for the full rationale.
    - [Perceus_scrut]: Phase 0.5, [preprocess_fn] (whole-scrutinee-escape
      rewrite, runs BEFORE RC insertion).  Depends on [Perceus_liveness]
      and on [Rc_types.needs_rc] DIRECTLY — not [Perceus.needs_rc] (see
      below).

    [Perceus] (this file) calls INTO all four via the [perceus] orchestrator
    ([Perceus_scrut.preprocess_fn], [Perceus_elide.elide_cancel_pairs],
    [Perceus_fbip.insert_fbip], plus [Perceus_liveness] used pervasively by
    the Phase 2 core) — so none of the four may have a compile-time
    dependency back on [Perceus], or dune rejects the build as a cycle.
    This bit in practice: [Perceus.needs_rc] is ITSELF just a re-export of
    [Rc_types.needs_rc] (below), and [Perceus_scrut]'s Phase-0.5 rewrite
    needs the same predicate — routing that call through [Perceus.needs_rc]
    would make [Perceus_scrut] depend on [Perceus], which (combined with
    [Perceus] calling [Perceus_scrut.preprocess_fn]) is exactly a cycle.
    The fix is for [Perceus_scrut] to call [Rc_types.needs_rc] directly,
    skipping the re-export — the two spellings are the identical function,
    so this is not a behavior change, only a dependency-direction choice.
    [is_apply_fn] and [needs_rc] stay re-exported here (not moved) because
    Phase 2's core logic still uses the unqualified names throughout.

    A handful of symbols are re-exported at their historical
    [Perceus.<name>] path — [same_arity], [elide_expr], [fbip_expr] — purely
    for external-caller compatibility (test/test_codegen.ml,
    test/test_eval.ml reach into these directly; see the alias definitions
    near the bottom of this file for the full list and rationale).  New code
    should prefer the [Perceus_fbip]/[Perceus_elide] qualified names
    directly.

    ── Pass-ordering contract ───────────────────────────────────────────────

    Within [perceus] (the entry point at the bottom of this file):
      Phase 0.5 [Perceus_scrut.preprocess_fn] (scrut-escape rewrite)
        -> Phase 2 [insert_rc] (borrow-aware RC insertion; internally runs
           Phase 1 [Perceus_liveness.live_before] per subtree)
        -> Phase 3 [Perceus_elide.elide_cancel_pairs] (adjacent-pair elision)
        -> Phase 4 [Perceus_fbip.insert_fbip] (FBIP reuse detection).

    In the whole compiler pipeline (verified against bin/main.ml's
    Phase-3/4 sequencing, ~line 1606–1638): [Known_call.run] and
    [Join_points.run_pre] and [Simplify.run ~pre_perceus:true] all run
    BEFORE [Perceus.perceus] (Known_call's ECallPtr->EApp closure-apply
    rewrite must land first so its $clo-consuming ABI is visible to
    Perceus's borrow-aware EApp case — see [is_apply_fn]'s doc below); and
    [Escape.escape_analysis] runs immediately AFTER [Perceus.perceus] (RC
    ops must exist in the TIR before escape analysis can reason about heap
    vs. stack placement). This ordering is unchanged by the Task 5 file
    split — [perceus] is still the single entry point bin/main.ml and
    lib/jit/repl_jit.ml call. *)

(* ── Phase 2 core moved to [Perceus_core] ─────────────────────────────────
   [env], [_rc_fresh_ctr]/[fresh_rc_var], the env-consuming helpers and
   [insert_rc_expr] moved VERBATIM into [Perceus_core].  Re-included (not
   aliased) so that perceus.mli's concrete [env] record and ~18 exported
   values are unchanged, and so the counter reset below still refers to the
   same ref cell. *)
include Perceus_core


(* Insert RC ops into a function definition.
   [borrowed] names are treated as still-live at the function's exit,
   preventing Perceus from treating their last use as an ownership transfer.
   Used for REPL globals that persist across compilation units.
   Pre-computes the actor-sent variable set so that values sent across actor
   thread boundaries use atomic RC operations. *)
(** Rename ELet/ECase-bound variables whose names collide with [borrowed]
    parameters.  When [let s = f(s, …)] appears in a function whose parameter
    [s] is borrowed, Perceus's backward liveness analysis removes "s" from
    live_after when computing the live set for the RHS.  This causes
    post_dec_var to fire for the borrowed parameter — a spurious dec_rc.
    By renaming only the offending bindings, we break the aliasing without
    disturbing unrelated variable names (which preserves test expectations). *)
let rename_borrowed_shadows (borrowed : StringSet.t) (body : Tir.expr) : Tir.expr =
  if StringSet.is_empty borrowed then body
  else
  let ctr = ref 0 in
  let fresh n = incr ctr; Printf.sprintf "%s_b%d" n !ctr in
  (* subst: maps old_name → new_name only for bindings we have renamed *)
  let atom subst a = match a with
    | Tir.AVar v -> (match StringMap.find_opt v.Tir.v_name subst with
        | Some n -> Tir.AVar { v with Tir.v_name = n }
        | None -> a)
    | _ -> a
  in
  let var subst v = match StringMap.find_opt v.Tir.v_name subst with
    | Some n -> { v with Tir.v_name = n }
    | None -> v
  in
  let bind subst v =
    (* Rename if this binding's name is a borrowed param OR is currently
       being substituted (to prevent chained aliasing). *)
    if StringSet.mem v.Tir.v_name borrowed || StringMap.mem v.Tir.v_name subst then
      let n = fresh v.Tir.v_name in
      ({ v with Tir.v_name = n }, StringMap.add v.Tir.v_name n subst)
    else
      (* Clear any outer substitution for this name: a fresh binding shadows it *)
      (v, StringMap.remove v.Tir.v_name subst)
  in
  let rec go subst e =
    match e with
    | Tir.EAtom a -> Tir.EAtom (atom subst a)
    | Tir.EApp (f, args) -> Tir.EApp (var subst f, List.map (atom subst) args)
    | Tir.ECallPtr (fn_a, args) ->
      Tir.ECallPtr (atom subst fn_a, List.map (atom subst) args)
    | Tir.ELet (v, rhs, bdy) ->
      let rhs' = go subst rhs in   (* rhs sees old subst — references the param, not the binding *)
      let (v', subst') = bind subst v in
      Tir.ELet (v', rhs', go subst' bdy)
    | Tir.ELetRec (fns, bdy) ->
      (* Freshen any fn names that collide with borrowed params *)
      let (fns1, subst1) = List.fold_left (fun (fs, s) fd ->
        let tmp = { Tir.v_name = fd.Tir.fn_name; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
        let (tmp', s') = bind s tmp in
        ({ fd with Tir.fn_name = tmp'.Tir.v_name } :: fs, s')
      ) ([], subst) fns in
      let fns2 = List.rev_map (fun fd ->
        { fd with Tir.fn_body = go subst1 fd.Tir.fn_body }) fns1 in
      Tir.ELetRec (fns2, go subst1 bdy)
    | Tir.ECase (a, branches, default) ->
      let a' = atom subst a in
      let branches' = List.map (fun br ->
        let (br_vars', subst') = List.fold_left (fun (vs, s) bv ->
          let (bv', s') = bind s bv in (vs @ [bv'], s')
        ) ([], subst) br.Tir.br_vars in
        { br with Tir.br_vars = br_vars'; Tir.br_body = go subst' br.Tir.br_body }
      ) branches in
      let default' = Option.map (go subst) default in
      Tir.ECase (a', branches', default')
    | Tir.ESeq (e1, e2) -> Tir.ESeq (go subst e1, go subst e2)
    | Tir.ETuple atoms -> Tir.ETuple (List.map (atom subst) atoms)
    | Tir.ERecord fields ->
      Tir.ERecord (List.map (fun (k, a) -> (k, atom subst a)) fields)
    | Tir.EField (a, f) -> Tir.EField (atom subst a, f)
    | Tir.EUpdate (a, fs) ->
      Tir.EUpdate (atom subst a, List.map (fun (k, v) -> (k, atom subst v)) fs)
    | Tir.EAlloc (ty, args) -> Tir.EAlloc (ty, List.map (atom subst) args)
    | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (ty, List.map (atom subst) args)
    | Tir.EFree a -> Tir.EFree (atom subst a)
    | Tir.EIncRC a -> Tir.EIncRC (atom subst a)
    | Tir.EDecRC a -> Tir.EDecRC (atom subst a)
    | Tir.EAtomicIncRC a -> Tir.EAtomicIncRC (atom subst a)
    | Tir.EAtomicDecRC a -> Tir.EAtomicDecRC (atom subst a)
    | Tir.EReuse (a, ty, args) ->
      Tir.EReuse (atom subst a, ty, List.map (atom subst) args)
    | Tir.EAllocHole (tok, ty, args, hole) ->
      Tir.EAllocHole (tok, ty, List.map (atom subst) args, hole)
    | Tir.ESetField (o, i, v) ->
      Tir.ESetField (atom subst o, i, atom subst v)
  in
  go StringMap.empty body

(* Normalize result-position bare field projections [src.f] into
   [let $rc_N = src.f in $rc_N] before RC insertion.  A bare EField as a
   function (or branch) RESULT escapes the record's scope: the caller receives
   the field value believing it owns it.  Let-binding the projection routes it
   through the ELet borrowed-field machinery, which marks the binding borrowed
   and emits the dup-on-escape EIncRC at the tail return (see the ELet and
   EAtom cases of [insert_rc_expr]).  Without this, single-expression
   accessors like [fn entry_date(e) do e.date end] hand out an un-dup'd alias;
   the caller's consume frees the field the record still owns (use-after-free
   observed in sitemap/feed entry rendering and tags-list reuse).
   Only projections whose field type [needs_rc] are rewritten. *)
let rec dup_field_results (k_table : Kind.table) (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.EField (Tir.AVar src, f) ->
    (match src.Tir.v_ty with
     | Tir.TRecord fields ->
       (match List.assoc_opt f fields with
        | Some fty when Kind.needs_rc_of k_table fty ->
          let tmp = fresh_rc_var fty in
          Tir.ELet (tmp, e, Tir.EAtom (Tir.AVar tmp))
        | _ -> e)
     | _ -> e)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, dup_field_values k_table e1, dup_field_results k_table e2)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (e1, dup_field_results k_table e2)
  | Tir.ECase (a, brs, dflt) ->
    Tir.ECase (a,
      List.map (fun b -> { b with Tir.br_body = dup_field_results k_table b.Tir.br_body }) brs,
      Option.map (dup_field_results k_table) dflt)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (
      List.map (fun fd -> { fd with Tir.fn_body = dup_field_results k_table fd.Tir.fn_body }) fns,
      dup_field_results k_table body)
  | other -> other

(* A let's bound value.  A bare [src.f] there is the ELet rule's own
   borrowed-field case and stays as it is, but the arms of a case on the
   value's tail are result positions whose projection escapes into the
   binding just as a function result escapes to the caller: [let t = if c do "-" else
   r.f end] made [t] an owned String aliasing [r.f] with no dup, so [t]'s
   drop freed the field [r] still held (Control.serialize's sig line, dd step
   12b; specs/progress/2026-10-01-compiled-record-with-projection-sigsegv.md). *)
and dup_field_values (k_table : Kind.table) (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.ECase _ -> dup_field_results k_table e
  (* A projection chain ([st.a.b] is [let t = st.a in t.b]) ends in a bare
     projection too, and the ELet rule already borrows it as a chain; only a
     case found along the value's tail is normalised. *)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, dup_field_values k_table e1, dup_field_values k_table e2)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (e1, dup_field_values k_table e2)
  | _ -> e

(** Emit the callee-side ownership drop of [$clo] for an apply function whose
    closure parameter is ALREADY owned per the borrow map.

    Background — the capturing-closure leak.  An apply function's closure
    struct was never released by anyone: the caller side defers to the callee
    (see the [EApp] case's [callee_is_apply] exclusion), and the callee never
    dropped it, so every closure materialization leaked one allocation
    (measured: 4M-iteration loop = 4,000,000 allocations / ~125 MB peak RSS,
    versus 0 / ~2.9 MB for the capture-free control, which [llvm_emit]'s
    static-closure optimization already routes through one immortal global).

    THIS DROP IS ONLY SOUND BECAUSE OF THE PIN IN [Borrow.infer_module]'s
    [init].  There are TWO independent notions of "$clo is borrowed" and they
    must agree: the borrow map (what CALLERS consult, at the [EApp] case
    above) and the per-function [borrowed] set (what suppresses the callee's
    own drop).  Adding this drop WITHOUT the pin makes the caller filter $clo
    out of [non_borrowed_args] — emitting no [EIncRC] even when the closure is
    live after the call — while the callee decrements, so the callee releases
    the caller's only reference.  A prior attempt did exactly that and
    produced 3 double-frees plus 8 stdlib crashes.  The clean witness is a
    closure invoked three times in one iteration: pre-pin its post-Perceus
    TIR is one [alloc $Clo_], three [EApp]s and ZERO RC ops on the closure
    (caller owns 1 reference, increments 0, so the second call is a
    use-after-free); post-pin the first two calls each carry an [inc_rc] and
    the third transfers, which balances exactly.

    Do not reintroduce a [Borrow.is_borrowed] gate here as a way to narrow
    this pass — the pin makes that predicate uniformly false for apply
    functions, so such a gate is vacuous, and a version of this fix scoped
    that way was measured to be completely inert: every drop it emitted
    either cancelled against a self-binding's [inc_rc] or landed on a
    capture-free closure that [llvm_emit] had already made immortal.  RSS was
    byte-identical to the control on every shape.

    Perceus's ordinary dead-variable machinery cannot discover this drop on
    its own: it emits one only for an [ELet]-bound local that goes dead or
    for an [ECase] scrutinee, and a plain PARAMETER whose only uses are
    borrowing [EField] reads is never flagged dead by either mechanism.

    The dead-alias gap this pass used to work around — a self-recursive
    capturing apply function leaking one reference per materialization,
    because its self-binding [let f = inc_rc $clo; $clo] was consumed only on
    the recursive path and nothing dropped [f] on the base-case branch — was
    fixed at its source on 2026-09-16
    (specs/progress/2026-09-16-if-else-drops-the-dead-side.md): the [ECase]
    cross-branch pass left the DEFAULT arm out of its "live elsewhere" union,
    so a base case that is the tagged branch of an `if` never saw the alias as
    dead-here-live-elsewhere.  [insert_dec_on_dead_paths] below now finds the
    alias already released at the head of such an arm — its [Dce.free_vars]
    test sees the new [dec_rc f] and steps aside — so the two mechanisms emit
    one release between them, not two.  It is kept because it still covers the
    shapes the cross-branch pass excludes (a [moved_vars] or [closure_fvs]
    alias, an arm the walk reaches through an [ELet] RHS).

    PLACEMENT.  [Defun.lift_lambda] guarantees the bare [$clo] atom is
    referenced only by a leading, uninterrupted prefix of [ELet] bindings —
    an optional self-binding [let fn_name = $clo] (recursive lambdas only)
    followed by zero or more free-variable extractions [let fv_i = $clo.$fvN]
    — and nowhere else.  Splicing the drop immediately after that prefix,
    rather than at the end of the body, is what makes this safe for a
    self-recursive apply function: a drop placed after a self-recursive tail
    call becomes dead code once codegen's TCO rewrites it into a back-edge,
    silently never running and reproducing the per-level leak.  Landing it
    before any branch point means it runs on every path out, strictly after
    $clo's last real use.

    This runs as a POST-pass on [insert_rc_expr]'s output, not as a
    source-level rewrite fed back into it.  Splicing [ESeq (EDecRC $clo, ..)]
    into the ORIGINAL body lets [EDecRC]'s own live-before computation add
    $clo back to the live set (it must — the object has to be alive to be
    decremented), which makes the last real read of $clo look like a non-last
    use to [find_inc_vars] and triggers a defensive [inc_rc $clo] that nets
    the drop to zero, reproducing the leak.  Splicing into the
    ALREADY-RC-INSERTED body sidesteps that the same way the [ELet] case's
    dead-binding cleanup does.  One wrinkle: a prefix binding's RHS may be
    wrapped in a protective [EIncRC]/[EAtomicIncRC], so [is_clo_source] must
    see through that wrap. *)
let insert_apply_fn_clo_drop ~(repl : bool) (body : Tir.expr) : Tir.expr =
  let clo = Tir_names.clo_param_name in
  let clo_var =
    { Tir.v_name = clo; Tir.v_ty = Tir.TPtr Tir.TUnit; Tir.v_lin = Tir.Unr }
  in
  let rec is_clo_source (e : Tir.expr) : bool =
    match e with
    | Tir.EAtom (Tir.AVar src) -> String.equal src.Tir.v_name clo
    | Tir.EField (Tir.AVar src, _) -> String.equal src.Tir.v_name clo
    | Tir.ESeq ((Tir.EIncRC (Tir.AVar src) | Tir.EAtomicIncRC (Tir.AVar src)), inner)
      when String.equal src.Tir.v_name clo -> is_clo_source inner
    | _ -> false
  in
  (* A SELF-BINDING is a prefix let whose RHS resolves to plain [$clo] (via
     [is_clo_source]'s EAtom/ESeq-unwrap arms) rather than an [EField]
     projection — i.e. [lift_lambda]'s `let fn_name = $clo` alias for a
     recursive lambda's own name, not a captured-variable extraction.
     Distinguishing it from an fv-extraction is what lets [insert_dec_
     on_dead_paths] below single out the one case that needs path-sensitive
     handling instead of the unconditional drop. *)
  let rec is_self_binding_source (e : Tir.expr) : bool =
    match e with
    | Tir.EAtom (Tir.AVar src) -> String.equal src.Tir.v_name clo
    | Tir.EField (Tir.AVar _, _) -> false
    | Tir.ESeq ((Tir.EIncRC (Tir.AVar src) | Tir.EAtomicIncRC (Tir.AVar src)), inner)
      when String.equal src.Tir.v_name clo -> is_self_binding_source inner
    | _ -> false
  in
  (* For a SELF-RECURSIVE capturing closure, the unconditional early drop
     below is not enough: the self-binding alias (e.g. `let helper = $clo`)
     is genuinely live on the recursive path (its reference flows onward,
     unincremented, into the tail [ECallPtr helper(...)] call — ordinary
     dead-after-argument semantics) but genuinely DEAD on any base-case path
     that never uses it. A single drop placed before the branch either
     double-frees the recursive path or (as the unconditional early-drop
     version did) never fires a SECOND drop on the dead path, leaking one
     reference per top-level materialization of the closure — confirmed:
     an `outer(k, n)` that materializes a self-recursive capturing `helper`
     and calls it once, looped 20,000 times, reported exactly `LEAKED
     20000` with the unconditional drop, `BOUNDED` with this fix.

     Walks the body looking for points where [self_name] is no longer free
     (via [Dce.free_vars], already correctly capture-aware for ELet/ECase
     shadowing) and inserts a drop exactly there, leaving live paths
     untouched so the existing dead-after-argument transfer keeps working.
     Falls back to leaving an expression alone wherever [self_name] occurs
     in a shape not explicitly walked into (e.g. inside an [ELetRec]) --
     conservative in the sense that it cannot introduce a NEW double-free,
     only fail to plug a leak in some exotic future shape. *)
  let rec insert_dec_on_dead_paths (self_name : string) (e : Tir.expr) : Tir.expr =
    if not (StringSet.mem self_name (Dce.free_vars e)) then
      Tir.ESeq (Tir.EDecRC (Tir.AVar clo_var), e)
    else
      match e with
      | Tir.ECase (scrut, branches, default) ->
        Tir.ECase
          ( scrut,
            List.map
              (fun br ->
                 if List.exists (fun v -> String.equal v.Tir.v_name self_name) br.Tir.br_vars
                 then br  (* shadowed in this branch: leave alone, safe fallback *)
                 else { br with Tir.br_body = insert_dec_on_dead_paths self_name br.Tir.br_body })
              branches,
            Option.map (insert_dec_on_dead_paths self_name) default )
      | Tir.ELet (v, e1, e2) when not (String.equal v.Tir.v_name self_name) ->
        (* [self_name] occurs somewhere in [e] (checked above), but which
           half depends on where: e.g. the recursive call itself lives in
           the RHS here (`let $t = ... call_ptr helper(...) in +($t, k)`),
           not the tail. Recursing into the tail unconditionally — the
           first version of this fix did exactly that — inserts a SECOND,
           WRONG drop on a live path once the RHS's own consuming call has
           already accounted for [self_name]'s lifetime: confirmed via TIR,
           `_ -> let $t = ...call_ptr helper($t2) in dec_rc $clo; +($t, k)`,
           a double-free waiting to happen the moment rc actually reaches 0
           on that path. Recurse into whichever half actually contains the
           occurrence and leave the other COMPLETELY alone — it plays no
           part in [self_name]'s consumption either way. *)
        if StringSet.mem self_name (Dce.free_vars e1) then
          Tir.ELet (v, insert_dec_on_dead_paths self_name e1, e2)
        else
          Tir.ELet (v, e1, insert_dec_on_dead_paths self_name e2)
      | Tir.ESeq (e1, e2) ->
        if StringSet.mem self_name (Dce.free_vars e1) then
          Tir.ESeq (insert_dec_on_dead_paths self_name e1, e2)
        else
          Tir.ESeq (e1, insert_dec_on_dead_paths self_name e2)
      | _ -> e
  in
  let rec splice (self_name : string option) (e : Tir.expr) : Tir.expr =
    match e with
    | Tir.ELet (v, e1, rest) when is_self_binding_source e1 ->
      Tir.ELet (v, e1, splice (Some v.Tir.v_name) rest)
    | Tir.ELet (v, e1, rest) when is_clo_source e1 ->
      Tir.ELet (v, e1, splice self_name rest)
    | _ ->
      (* The unconditional early drop ALWAYS fires here, self-binding or
         not — it is what cancels the self-binding's own protective
         [inc_rc $clo] (a transient bump-then-unbump around the fv-extraction
         reads, net zero) and is already sufficient on its own for the
         non-recursive case, where nothing else ever touches $clo again.
         For a self-recursive closure this is NOT a substitute for the extra
         per-dead-path drop below, only a prerequisite for it — dropping the
         `insert_dec_on_dead_paths` walk in favour of this alone (an earlier
         version of this fix) leaves the protective inc canceled but the
         ACTUAL transferred reference never released at the dead end;
         dropping THIS unconditional drop in favour of only the walk (a
         different earlier, also-broken version) leaves the protective inc
         permanently uncanceled on every live (recursive) path instead. Both
         are required, in this order. *)
      let dropped = Tir.ESeq (Tir.EDecRC (Tir.AVar clo_var), e) in
      (match self_name with
       | Some name -> insert_dec_on_dead_paths name dropped
       | None -> dropped)
  in
  (* Splice ONLY when the prefix actually extracts a capture ($clo.$fvN).
     Two independent reasons, and the second is a hard correctness constraint:

     1. A genuinely capture-free, non-recursive lambda's apply fn never
        mentions $clo at all ([lift_lambda]'s wrapped_body is exactly
        [fn.fn_body], with no self-binding and no fv-extraction lets).
        [llvm_emit]'s static-closure optimization keys off that exact fact to
        route such a lambda through one immortal global instead of a
        per-materialization [march_alloc] — and it regresses to a real
        per-iteration allocation if this pass introduces a $clo reference
        (verified: `fn x -> x + 1` in a 100,000-iteration loop went from
        obj_allocs 0 to obj_allocs 100000 without a guard here).

     2. A capture-FREE apply fn that DOES mention $clo — a self-recursive one,
        whose only $clo use is [lift_lambda]'s `let go = $clo` self-binding —
        must NOT get a drop here, and this is a hard correctness constraint,
        not a conservatism.  Ordinary RC insertion already releases that
        reference through the alias: the self-binding is an ordinary owned
        local, so [insert_rc_expr] emits `dec_rc go` on every path where the
        alias is dead and transfers it into the recursive `call_ptr go(..)` on
        the paths where it is live.  Confirmed in the emitted TIR for
        List.length's inner `go`:

          fn go$apply($clo, lst, acc) =
            let go = $clo in
            case lst of
              Nil()          -> dec_rc go; dec_rc lst; acc
              Cons($f, $t)   -> ... call_ptr go(t, $t2)

        Adding an unconditional drop on top of that is a SECOND release of the
        same reference: rc reaches 0 on the first call, the closure is freed,
        and the recursive dispatch reads a zeroed apply-fn slot.  That is the
        exact crash two prior attempts at this hit — EXC_BAD_ACCESS at address
        0x0, frame #0 = 0x0, in run_codegen's "stdlib List.length via
        precompile", whose stack is `List.length$List_Int -> go$apply$218 ->
        0x0` (a jump through a null code pointer, NOT a data use-after-free).
        Native stayed green throughout because [static_closure_ok] routes the
        native build to the immortal global, where the over-release is a no-op
        by construction; only the JIT (where it is a real [march_alloc] with
        rc = 1) exposes it.

     3. A capture-free apply fn that mentions $clo NOWHERE — a non-recursive
        capture-free lambda, the case in (1) — is the one that genuinely
        leaks, and only under the REPL/JIT.  Nothing in its body ever names
        $clo, so ordinary RC insertion has nothing to release, while the
        apply-fn param-0 pin in [Borrow.infer_module] means every caller
        transfers a reference in.  Natively that is fine (the immortal global
        absorbs it); under [ctx.repl] it is a fresh [march_alloc] per
        materialization that nobody frees — one leaked allocation per use,
        measured at exactly 2,000 over a 2,000-iteration REPL fragment.  Hence
        the [repl]-gated arm at the bottom of this function: it fires for
        exactly this shape, which is also why it cannot regress (1) — a body
        that never mentions $clo cannot acquire a $clo reference that would
        defeat the static-closure optimization, and the arm is off natively
        regardless. *)
  (* Mirrors [is_clo_source]'s unwrapping: a prefix binding's RHS may be
     wrapped in a protective EIncRC, so a bare [EField] match would miss it
     and misclassify a capturing apply fn as capture-free. *)
  let rec is_fv_extraction (e : Tir.expr) : bool =
    match e with
    | Tir.EField (Tir.AVar src, _) ->
      String.equal src.Tir.v_name clo
    | Tir.ESeq ((Tir.EIncRC (Tir.AVar src) | Tir.EAtomicIncRC (Tir.AVar src)), inner)
      when String.equal src.Tir.v_name clo -> is_fv_extraction inner
    | _ -> false
  in
  let rec prefix_has_fv_extraction (e : Tir.expr) : bool =
    match e with
    | Tir.ELet (_, e1, rest) when is_clo_source e1 ->
      is_fv_extraction e1 || prefix_has_fv_extraction rest
    | _ -> false
  in
  match body with
  | Tir.ELet (_, e1, _) when is_clo_source e1 && prefix_has_fv_extraction body ->
    splice None body
  | _ ->
    (* Case (3) above: only where capture-free lambdas are heap closures (the
       REPL/JIT, and any --hot-reload build, where [Llvm_emit] turns static
       lambdas off for the whole module; [repl] carries both, see [perceus]'s
       [?heap_lambdas]), and only for an apply fn whose body never mentions
       $clo at all.  The [not (mem clo ..)] test is what
       separates this from case (2): a self-recursive capture-free apply fn
       DOES mention $clo (its self-binding alias) and already releases the
       reference through that alias, so it must fall through untouched. *)
    if repl && not (StringSet.mem clo (Dce.free_vars body)) then
      Tir.ESeq (Tir.EDecRC (Tir.AVar clo_var), body)
    else body

(** Drop owned aggregate PARAMETERS that the body never releases.

    A variant reaching its last use inside a match is freed by
    [add_scrutinee_free_for]; a let-bound aggregate is freed by the scope-end
    drop in [insert_rc_expr]'s ELet case.  A PARAMETER has neither — there is no
    binding site to hang a drop on — so an owned aggregate parameter was never
    released at all.

    The drops are pushed down to every TAIL position rather than wrapped around
    the body.  Wrapping ([let tmp = body in dec_rc p; tmp]) puts an operation
    after the body, so a self tail call inside it stops being a tail call,
    llvm_tco stops firing, and a loop that ran in constant space recurses
    instead: measured correct and leak-free to ~5,000 iterations, then SIGBUS
    from stack exhaustion by 20,000.  Dropping just BEFORE each tail expression
    keeps the tail call in tail position AND gives the loop constant space — at
    the back-edge the parameter holds THIS iteration's aggregate, exactly the
    cell that should be released, while the next iteration runs on the newly
    built one already passed as the argument.

    A tail expression that still READS the parameter (a base case like [b.n]) is
    rebound first so the read happens before the release.  Its type is the
    function's return type by definition of tail position, so no inference is
    needed.

    Guards mirror the ELet scope-end drop, but are applied PER PATH.
    [used_only_as_field_source] is what keeps this from double-freeing: at any
    consuming position ownership has already transferred.  [releases_var]
    stands the drop down where the body already decs the parameter.  Both
    used to be asked of the WHOLE body, so a parameter consumed or released
    on ONE arm was never dropped on the arms that merely read it:

      fn take(st) = match st.items do
                    Cons(x, rest) -> { conn: Some(x), new_state: { st with items: rest } }
                    Nil           -> { conn: None, new_state: st }   -- moves st
                    end

    leaked [st] on every [Cons] path.  That is the shape of depot's
    [Pool.handle_checkout], so every pooled checkout leaked the actor's state
    record and a list cell -- the last steady leak in an idle conduit worker.
    The same whole-body test leaked a read-only parameter whenever Perceus's
    cross-branch pass had already released it on some other arm.

    Now the walk to each tail tracks which candidates the path has already
    consumed or released (in a binding's RHS, a statement, a closure capture,
    or as a case scrutinee), and only the rest are dropped before that tail.
    Anything ambiguous along the path counts as consumed: leak, never
    double-free. *)
let insert_owned_aggregate_param_drops (env : env) (borrowed : StringSet.t)
    (fn : Tir.fn_def) (body : Tir.expr) : Tir.expr =
  let candidates =
    List.filter (fun p ->
        is_aggregate_ty env p.Tir.v_ty
        && p.Tir.v_lin = Tir.Unr
        && not (StringSet.mem p.Tir.v_name borrowed)
        && not (StringSet.mem p.Tir.v_name env.closure_fvs)
        && not (StringSet.mem p.Tir.v_name env.moved_vars))
      fn.Tir.fn_params
  in
  match candidates with
  | [] -> body
  | _ ->
    let drop_ops live tail_expr =
      List.fold_left
        (fun acc p -> Tir.ESeq (decrc_for env p (Tir.AVar p), acc))
        tail_expr live
    in
    (* [live]: the candidates the current path has not yet consumed or
       released.  A consuming use ([used_only_as_field_source] fails: a call
       argument, a constructor field, the tail value) or a release already on
       the path (the ECase cross-branch drop of a parameter dead in one arm, a
       post-call dec) takes that candidate out for the rest of the path only.
       Both guards used to be asked of the whole body, so a consume or release
       in ONE arm stood the drop down in every arm: [if r.f == "" do "-" else
       r.f end] released [r] in the first arm and leaked it in the second, and
       depot's [Pool.handle_checkout] moved its state on the [Nil] path and
       leaked it on every [Cons] checkout.  A consume or release found inside a
       non-tail subexpression ([e1] of a let or seq, possibly under a case)
       still counts for the whole rest of the path: conservative, a leak on
       the paths that did not take it, never a double release. *)
    let not_taken_in e live =
      List.filter (fun p ->
          not (releases_var p.Tir.v_name e
               || not (used_only_as_field_source ~releases_ok:true p.Tir.v_name e
                       (* consumed only through dups: still ours *)
                       || covered_by_incs p.Tir.v_name e)))
        live
    in
    (* [aliases] holds the heap values on the current path that still point
       INTO a candidate without owning a reference of their own: a borrowed
       field projection ([let t = s.tree]), an alias of one, a projection out
       of one, or a pattern variable bound by matching one.  Releasing the
       candidate frees the cell those point into, so a tail that still mentions
       one must run before the drop, exactly like a tail that reads the
       candidate itself.  Missing this, [fn size(s) do tree_size(s.tree) end]
       became [let t = s.tree in dec_rc s; tree_size(t)]: tree_size BORROWS
       its argument, so nothing dup'd [t], and a uniquely-held set's tree was
       freed before it was walked (compiled-only "non-exhaustive pattern
       match").  An alias Perceus has dup'd on this path ([inc_rc t]) is
       independently owned again (the consuming uses in [member]/[to_list])
       and leaves the set, which is what keeps the drop ahead of those tail
       calls. *)
    let is_candidate_or_alias aliases (w : Tir.var) =
      StringSet.mem w.Tir.v_name aliases
      || List.exists (fun p -> String.equal p.Tir.v_name w.Tir.v_name)
           candidates
    in
    let rec rhs_aliases aliases (e1 : Tir.expr) =
      match e1 with
      | Tir.EField (Tir.AVar src, _) -> is_candidate_or_alias aliases src
      | Tir.EAtom (Tir.AVar src) -> StringSet.mem src.Tir.v_name aliases
      | Tir.ELet (iv, ie1, ibody) ->
        let aliases' =
          if needs_rc env iv.Tir.v_ty && rhs_aliases aliases ie1
          then StringSet.add iv.Tir.v_name aliases else aliases in
        rhs_aliases aliases' ibody
      | Tir.ESeq (_, e2) -> rhs_aliases aliases e2
      | _ -> false
    in
    let uses_candidate live aliases e =
      List.exists
        (fun p -> Perceus_liveness.name_free_in p.Tir.v_name e) live
      || StringSet.exists
           (fun a -> Perceus_liveness.name_free_in a e) aliases
    in
    (* [ty]: the type of [e]'s value, for rebinding a tail that still reads a
       candidate: the function's return type, or a let's bound type when the
       drops go into its right-hand side. *)
    let rec push ty live aliases (e : Tir.expr) : Tir.expr =
      let push_same = push ty in
      match e with
      | Tir.ELet (v, e1, e2) ->
        let aliases' =
          if needs_rc env v.Tir.v_ty && rhs_aliases aliases e1
          then StringSet.add v.Tir.v_name aliases
          else StringSet.remove v.Tir.v_name aliases in
        let live_e2 = not_taken_in e1 live in
        if List.length live_e2 < List.length live
           && not (uses_candidate live aliases' e2) then
          (* [e1] consumes or releases a candidate on some path and nothing
             after it mentions any candidate: drop inside [e1], whose paths
             each know what they took.  Carrying the "taken somewhere in e1"
             verdict past it instead stood the drop down on every path: [let
             t = if r.f == "" do "-" else r.f end in "sig " ++ t] dropped [r]
             in the first arm and leaked it in the second. *)
          Tir.ELet (v, push v.Tir.v_ty live aliases e1, e2)
        else
          Tir.ELet (v, e1, push_same live_e2 aliases' e2)
      | Tir.ESeq ((Tir.EIncRC (Tir.AVar w) | Tir.EAtomicIncRC (Tir.AVar w)
                   as e1), e2) ->
        Tir.ESeq (e1, push_same live (StringSet.remove w.Tir.v_name aliases) e2)
      | Tir.ESeq (e1, e2) -> Tir.ESeq (e1, push_same (not_taken_in e1 live) aliases e2)
      | Tir.ECase (a, branches, default) ->
        let scrut_aliased = match a with
          | Tir.AVar w -> is_candidate_or_alias aliases w
          | _ -> false in
        (* Matching ON a candidate hands it to the case's scrutinee drop. *)
        let live = match a with
          | Tir.AVar w ->
            List.filter (fun p -> not (String.equal p.Tir.v_name w.Tir.v_name)) live
          | _ -> live in
        let branch_aliases br =
          List.fold_left (fun acc bv ->
              if scrut_aliased && needs_rc env bv.Tir.v_ty
              then StringSet.add bv.Tir.v_name acc
              else StringSet.remove bv.Tir.v_name acc)
            aliases br.Tir.br_vars in
        Tir.ECase (a,
          List.map (fun br ->
              { br with Tir.br_body = push_same live (branch_aliases br) br.Tir.br_body })
            branches,
          Option.map (push_same live aliases) default)
      | Tir.ELetRec (fns, inner) ->
        (* A local function that mentions a candidate captures it. *)
        let live =
          List.filter (fun p ->
              not (List.exists (fun f ->
                  Perceus_liveness.name_free_in p.Tir.v_name f.Tir.fn_body) fns))
            live in
        Tir.ELetRec (fns, push_same live aliases inner)
      | tail ->
        (match not_taken_in tail live with
         | [] -> tail
         | live when uses_candidate live aliases tail ->
           let tmp = fresh_rc_var ty in
           Tir.ELet (tmp, tail, drop_ops live (Tir.EAtom (Tir.AVar tmp)))
         | live -> drop_ops live tail)
    in
    push fn.Tir.fn_ret_ty candidates StringSet.empty body

(** Release the user parameters of an apply fn that its body never mentions.

    [Borrow.infer_module] pins every apply-fn parameter owned, because every
    caller of a closure (an [ECallPtr], the direct [EApp] [Known_call] rewrites
    it into, and the C runtime's fold/map helpers) hands the callee a
    reference.  RC insertion releases a parameter at its last use, but a
    parameter with no use at all ([fn _ -> 0], [fn (acc, _) -> acc]) has no
    last use to hang the release on, so without this the reference leaked once
    per call.  The drop goes at entry: nothing reads the value, and a drop in
    front of the body leaves every tail call in tail position.

    [$clo] (param 0) is excluded: its release is [insert_apply_fn_clo_drop]'s,
    and a capture-free native apply fn is called with an immortal static
    closure. *)
let insert_dead_apply_param_drops (env : env) (borrowed : StringSet.t)
    (fn : Tir.fn_def) (body : Tir.expr) : Tir.expr =
  if not (Tir_names.is_apply_fn fn.Tir.fn_name) then body
  else
    let user_params = match fn.Tir.fn_params with _ :: ps -> ps | [] -> [] in
    let free = Dce.free_vars body in
    List.fold_left (fun acc p ->
        if (needs_rc env p.Tir.v_ty || is_aggregate_ty env p.Tir.v_ty)
           && not (StringSet.mem p.Tir.v_name borrowed)
           && not (StringSet.mem p.Tir.v_name env.closure_fvs)
           && not (StringSet.mem p.Tir.v_name free)
        then Tir.ESeq (decrc_for env p (Tir.AVar p), acc)
        else acc)
      body user_params

(** [insert_rc ~module_env ~borrowed fn] runs Phase 2 (RC insertion) over one
    function.  [module_env] carries the module-scoped fields (borrow_map,
    type_defs, extern_names) set once per [perceus] run; this
    function fills in the function-scoped fields (current_fn_name,
    closure_fvs, actor_sent) and the initial subtree-scoped fields (var_ctx
    seeded with params, borrowed_field_vars reset to empty) — exactly what
    the old code did by mutating the refs before calling [insert_rc_expr] and
    restoring them after.  Since each top-level function gets a FRESH [env]
    value here (rather than mutating shared refs), no restore step is needed
    afterward: the caller ([perceus]'s [List.map]) never sees this function's
    env — it only sees the returned [fn_def]. *)
let insert_rc ~(module_env : env) ?(repl = false) ?(borrowed = StringSet.empty)
    (fn : Tir.fn_def) : Tir.fn_def =
  (* Rename ELet/ECase-bound variables that shadow borrowed parameters before
     RC insertion.  See [rename_borrowed_shadows] for the full rationale. *)
  let body_renamed = rename_borrowed_shadows borrowed fn.Tir.fn_body in
  let body_normed = dup_field_results module_env.k_table body_renamed in
  let fn' = { fn with Tir.fn_body = body_normed } in
  let closure_fvs = collect_closure_fvs fn' in
  (* Closure FVs are owned by the closure struct, not by the apply function.
     The apply function merely borrows them for the duration of one call.
     Adding them to the borrowed set makes Perceus treat them as always-live:
     find_inc_vars then inserts EIncRC before any consuming (last-use) call,
     so the closure's reference to each FV survives even when the closure
     itself has RC > 1 and the apply function is invoked multiple times.
     Without this, a single-use FV (e.g. the inner Generator in Gen.map) is
     silently transferred to the callee on the first call, freed when the
     callee's pattern-match decrements its RC to 0, and becomes a dangling
     pointer on the second call → SIGSEGV. *)
  let borrowed' = StringSet.union borrowed closure_fvs in
  (* Seed the variable context with function parameters so that the ECase
     cross-branch dead-variable pass can emit correctly-typed EDecRC ops
     for parameters that are live in some arms but unused in others. *)
  let fn_env_for must_dup =
    { module_env with
      current_fn_name = fn'.Tir.fn_name;
      closure_fvs;
      actor_sent = collect_actor_sent_vars fn'.Tir.fn_body;
      moved_vars = collect_moved_vars fn';
      borrowed_field_vars = StringSet.empty;
      field_roots = Hashtbl.create 8;
      must_dup_fields = must_dup;
      var_ctx =
        List.fold_left (fun ctx v -> StringMap.add v.Tir.v_name v ctx)
          module_env.var_ctx fn'.Tir.fn_params }
  in
  let run fn_env =
    let (body', _) = insert_rc_expr fn_env fn'.Tir.fn_body borrowed' in
    (* Give the callee its explicit ownership drop of $clo AFTER RC insertion has
       already run — see [insert_apply_fn_clo_drop] for the post-pass rationale
       and for why this is sound only alongside the $clo pin in
       [Borrow.infer_module]'s [init].

       The [is_borrowed] conjunct is an ASSERTION of that coupling, not a
       narrowing: the pin makes it uniformly true for apply functions today.  It
       is kept so that narrowing the pin later (e.g. exempting one apply-fn
       class) automatically withdraws the matching drop instead of silently
       leaving caller and callee disagreeing — the exact split that caused the
       double-free wave. *)
    let body_clo =
      if Tir_names.is_apply_fn fn.Tir.fn_name
         && not (Borrow.is_borrowed module_env.borrow_map fn.Tir.fn_name 0)
      then insert_apply_fn_clo_drop ~repl body'
      else body'
    in
    let body_agg =
      insert_owned_aggregate_param_drops fn_env borrowed' fn' body_clo in
    insert_dead_apply_param_drops fn_env borrowed' fn' body_agg
  in
  (* A field projection is kept as a borrow of its record whenever the record
     is still in scope, but the record may be released (at its last use, or
     at the start of a case arm where it is dead) while the projection is
     still to be read.  Check the finished body for such a read and redo the
     function with those projections taking their own reference.  Each round
     only adds origins, so this terminates; in practice one rerun at most.
     specs/progress/2026-10-07-perceus-releases-parent-before-field-use.md *)
  (* A rerun reuses the fresh names the discarded run took, so a redone
     function does not shift the [$rc_N] names of every later function. *)
  let ctr0 = !Perceus_core._rc_fresh_ctr in
  let rec settle must_dup rounds =
    Perceus_core._rc_fresh_ctr := ctr0;
    let fn_env = fn_env_for must_dup in
    let body = run fn_env in
    (* [Hashtbl.fold] visits every binding of a name bound more than once. *)
    let fresh =
      Hashtbl.fold (fun v (root, origin) acc ->
          if not (StringSet.mem origin must_dup)
             && Perceus_core.read_after_owner_dies ~root ~v body
          then StringSet.add origin acc else acc)
        fn_env.field_roots StringSet.empty
    in
    if StringSet.is_empty fresh || rounds = 0 then body
    else settle (StringSet.union must_dup fresh) (rounds - 1)
  in
  { fn' with Tir.fn_body = settle StringSet.empty 4 }

(* ── Phase 3: RC Elision (cancel pairs) ──────────────────────────────────── *)

(** Moved to [Perceus_elide] (Wave 3 Task 5).  Re-exported at the historical
    [Perceus.elide_expr] path because test/test_eval.ml calls it directly. *)
let elide_expr = Perceus_elide.elide_expr

(** Elide cancel pairs in a function definition.  Moved to
    [Perceus_elide.elide_cancel_pairs] (Wave 3 Task 5); called from the
    [perceus] orchestrator below. *)
let elide_cancel_pairs = Perceus_elide.elide_cancel_pairs

(* ── Phase 4: FBIP Reuse Detection ──────────────────────────────────────── *)

(** Moved to [Perceus_fbip] (Wave 3 Task 5).  Re-exported at the historical
    [Perceus.fbip_expr] path because test/test_codegen.ml calls it directly. *)
let fbip_expr = Perceus_fbip.fbip_expr

(** Apply FBIP reuse to a function definition.  Moved to
    [Perceus_fbip.insert_fbip] (Wave 3 Task 5); called from the [perceus]
    orchestrator below. *)
let insert_fbip = Perceus_fbip.insert_fbip

(* ── Phase 0.5: whole-scrutinee-escape rewrite ───────────────────────────────
   Moved to [Perceus_scrut] (Wave 3 Task 5) — see that module for the full
   rationale (rewriting tail-position scrutinee escapes into constructor
   reconstructions so Phase 2 + FBIP can free-and-reuse the original cell).
   [preprocess_fn] is called from the [perceus] orchestrator below, as
   Phase 0.5 (before Phase 2's RC insertion). *)
let preprocess_fn = Perceus_scrut.preprocess_fn

(* ── Debug stats ──────────────────────────────────────────────────────────── *)

let _perceus_debug : bool Lazy.t =
  lazy (Sys.getenv_opt "MARCH_DEBUG_PERCEUS" <> None)

type rc_counts = {
  inc_rc      : int;
  dec_rc      : int;
  atomic_inc  : int;
  atomic_dec  : int;
  free        : int;
  reuse       : int;
}

let zero_counts = { inc_rc = 0; dec_rc = 0; atomic_inc = 0; atomic_dec = 0; free = 0; reuse = 0 }

let add_counts a b = {
  inc_rc     = a.inc_rc     + b.inc_rc;
  dec_rc     = a.dec_rc     + b.dec_rc;
  atomic_inc = a.atomic_inc + b.atomic_inc;
  atomic_dec = a.atomic_dec + b.atomic_dec;
  free       = a.free       + b.free;
  reuse      = a.reuse      + b.reuse;
}

let rec count_rc_ops_expr (e : Tir.expr) : rc_counts =
  let recurse_fn fn = count_rc_ops_expr fn.Tir.fn_body in
  match e with
  | Tir.EIncRC _                                -> { zero_counts with inc_rc = 1 }
  | Tir.EDecRC _                                -> { zero_counts with dec_rc = 1 }
  | Tir.EAtomicIncRC _                          -> { zero_counts with atomic_inc = 1 }
  | Tir.EAtomicDecRC _                          -> { zero_counts with atomic_dec = 1 }
  | Tir.EFree _                                 -> { zero_counts with free = 1 }
  | Tir.EReuse _                                -> { zero_counts with reuse = 1 }
  | Tir.ELet (_, e1, e2)                        -> add_counts (count_rc_ops_expr e1) (count_rc_ops_expr e2)
  | Tir.ELetRec (fns, body)                     ->
    List.fold_left (fun acc fn -> add_counts acc (recurse_fn fn))
      (count_rc_ops_expr body) fns
  | Tir.ESeq (e1, e2)                           -> add_counts (count_rc_ops_expr e1) (count_rc_ops_expr e2)
  | Tir.ECase (_, branches, default)            ->
    let from_branches = List.fold_left (fun acc br ->
      add_counts acc (count_rc_ops_expr br.Tir.br_body)) zero_counts branches in
    let from_default = Option.fold ~none:zero_counts ~some:count_rc_ops_expr default in
    add_counts from_branches from_default
  | _ -> zero_counts

let count_rc_ops_module (fns : Tir.fn_def list) : rc_counts =
  List.fold_left (fun acc fn ->
    add_counts acc (count_rc_ops_expr fn.Tir.fn_body)) zero_counts fns

let print_perceus_stats ~(label : string) ~(before : rc_counts) ~(after : rc_counts) () =
  let cancelled_inc = before.inc_rc     - after.inc_rc in
  let cancelled_dec = before.dec_rc     - after.dec_rc in
  let cancelled_a_inc = before.atomic_inc - after.atomic_inc in
  let cancelled_a_dec = before.atomic_dec - after.atomic_dec in
  Printf.eprintf "[perceus] %s\n" label;
  Printf.eprintf "  inserted:  inc=%d dec=%d atomic_inc=%d atomic_dec=%d free=%d reuse=%d\n"
    before.inc_rc before.dec_rc before.atomic_inc before.atomic_dec before.free before.reuse;
  Printf.eprintf "  after elision+fbip: inc=%d dec=%d atomic_inc=%d atomic_dec=%d free=%d reuse=%d\n"
    after.inc_rc after.dec_rc after.atomic_inc after.atomic_dec after.free after.reuse;
  Printf.eprintf "  cancelled: inc=%d dec=%d atomic_inc=%d atomic_dec=%d\n"
    cancelled_inc cancelled_dec cancelled_a_inc cancelled_a_dec;
  Printf.eprintf "%!"

(* ── Owned-call clones (see [Perceus_core.owned_calls]) ────────────────────── *)

(** May [fn] get an owned clone (owned-call drop fusion)?  An ordinary or
    fusion-synthesised function with at least one borrowed parameter.  Never
    a function whose identity or calling convention something outside March
    code depends on: apply functions (closure ABI, every parameter already
    owned), actor glue the runtime calls by name, hot-reload migration entry
    points, deep-drop helpers, RPC stubs and [main].  A clone is an extra
    function; the original is untouched and stays what those callers see. *)
let owned_clone_eligible (bm : Borrow.borrow_map) (fn : Tir.fn_def) : bool =
  let n = fn.Tir.fn_name in
  (match fn.Tir.fn_kind with Tir.FnNormal | Tir.FnFused -> true | _ -> false)
  && not (Tir_names.is_apply_fn n)
  && not (Tir_names.is_actor_dispatch_fn n)
  && not (Tir_names.is_actor_on_stop_fn n)
  && not (Tir_names.is_actor_inspect_fn n)
  && not (Tir_names.is_migrate_fn_name n)
  && not (Tir_names.is_drop_fn n)
  && not (Tir_names.has_suffix "__rpc_stub" n)
  && not (String.equal n "main")
  && List.exists (fun i -> Borrow.is_borrowed bm n i)
    (List.mapi (fun i _ -> i) fn.Tir.fn_params)

(** Names bound directly to a heap allocation ([let v = EAlloc ...]) — the
    only shape [Escape] stack-promotes, so the only arguments whose redirect
    to an owning clone could cost a promotion. *)
let collect_alloc_bound (e : Tir.expr) : StringSet.t =
  let rec go acc = function
    | Tir.ELet (v, (Tir.EAlloc _ as rhs), body) ->
      go (go (StringSet.add v.Tir.v_name acc) rhs) body
    | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> go (go acc e1) e2
    | Tir.ECase (_, brs, def) ->
      let acc = List.fold_left (fun a br -> go a br.Tir.br_body) acc brs in
      (match def with Some d -> go acc d | None -> acc)
    | Tir.ELetRec (fns, body) ->
      go (List.fold_left (fun a fn -> go a fn.Tir.fn_body) acc fns) body
    | _ -> acc
  in
  go StringSet.empty e

(** Fill [oc.oc_useful]: the (function, borrowed position) pairs whose owned
    clone does something the caller's drop could not — the parameter is an
    [ECase] scrutinee in the body (destructuring an owned cell releases it in
    the same walk), or is passed on at a useful borrowed position of another
    eligible function (a wrapper around such a walker).  A least fixpoint over
    the eligible functions.  Purely a profitability filter: a shadowed
    parameter name can only make it answer wrongly in the direction of a
    useless clone or a missed one, never an unsound redirect. *)
let compute_useful_positions (bm : Borrow.borrow_map) (oc : owned_calls) : unit =
  let rec used name e =
    match e with
    | Tir.ECase (Tir.AVar v, brs, def) ->
      String.equal v.Tir.v_name name
      || List.exists (fun br -> used name br.Tir.br_body) brs
      || (match def with Some d -> used name d | None -> false)
    | Tir.ECase (_, brs, def) ->
      List.exists (fun br -> used name br.Tir.br_body) brs
      || (match def with Some d -> used name d | None -> false)
    | Tir.EApp (g, args) ->
      List.exists (fun (j, a) -> match a with
          | Tir.AVar v ->
            String.equal v.Tir.v_name name
            && Hashtbl.mem oc.oc_useful (g.Tir.v_name, j)
          | _ -> false)
        (List.mapi (fun j a -> (j, a)) args)
    | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> used name e1 || used name e2
    | Tir.ELetRec (fns, body) ->
      List.exists (fun fn -> used name fn.Tir.fn_body) fns || used name body
    | _ -> false
  in
  let changed = ref true in
  while !changed do
    changed := false;
    Hashtbl.iter (fun fname (fn : Tir.fn_def) ->
        List.iteri (fun i (p : Tir.var) ->
            if Borrow.is_borrowed bm fname i
            && not (Hashtbl.mem oc.oc_useful (fname, i))
            && used p.Tir.v_name fn.Tir.fn_body then begin
              Hashtbl.replace oc.oc_useful (fname, i) ();
              changed := true
            end) fn.Tir.fn_params)
      oc.oc_fns
  done

(* ── Entry point ──────────────────────────────────────────────────────────── *)

(** Run all four Perceus phases over every function in the module.
    [repl_vars] is a list of bare variable names that correspond to REPL
    globals bridged into the current compilation unit.  They are injected
    into the borrowed set of the [main] function so Perceus never treats
    their last use as an ownership transfer, preventing RC underflow when
    the same global is passed to multiple successive REPL lines.

    Borrow inference (Phase 0) runs first: it analyses the whole module to
    determine which function parameters are borrowed, then passes that
    information into the RC insertion phase so that:
    - Callee: borrowed params are added to the live-at-exit set, suppressing
      EDecRC / scrutinee-free on those params.
    - Caller: EIncRC is skipped for args at borrowed positions that are still
      live after the call; a post-call EDecRC is emitted instead when the arg
      is the caller's last use.

    Never redirects to owned clones: see [perceus_owned]. *)
let rec perceus ?(repl : bool = false) ?(repl_vars : string list = [])
    ?(heap_lambdas : bool = false)
    ?(borrow_map : Borrow.borrow_map option) ?(k_table : Kind.table option)
    (m : Tir.tir_module) : Tir.tir_module =
  fst (perceus_owned ~owned_calls:false ~repl ~repl_vars ~heap_lambdas
         ?borrow_map ?k_table m)

(** [perceus] with owned-call drop fusion selectable ([~owned_calls]).  Also
    returns the borrow map extended with every clone's parameter modes: the
    passes after Perceus that consult the map ([Drop], [Escape]) must see a
    clone's owned positions as owned. *)
and perceus_owned ~(owned_calls : bool) ?(repl : bool = false)
    ?(repl_vars : string list = [])
    ?(heap_lambdas : bool = false)
    ?(borrow_map : Borrow.borrow_map option) ?(k_table : Kind.table option)
    (m : Tir.tir_module) : Tir.tir_module * Borrow.borrow_map =
  (* [heap_lambdas]: capture-free lambdas are materialised as heap closures
     rather than one immortal global, as under --hot-reload (Llvm_emit's
     static-lambda arm is off whenever [hr_config] is set).  Their apply fns
     then need the REPL's case-(3) [$clo] drop, or every call leaks the
     closure it was handed: one 24-byte object per [show] of a List under
     --hot-reload, found by LeakSanitizer during observe R4b. *)
  let clo_drop = repl || heap_lambdas in
  let k_table = match k_table with Some t -> t | None -> Kind.of_module m in
  (* Reset the fresh-name counter per module so that compiling the same module
     twice produces identical IR.  A monotonic counter that survives across
     modules makes IR diffs unstable and causes spurious churn in test
     baselines.  This counter is an accumulator, not env-shaped state: it is
     mutated (never restored) throughout the whole module's traversal, so it
     remains a ref rather than becoming an [env] field (Wave 3 Task 4 — see
     the plan's guidance on accumulator- vs scope-shaped refs). *)
  _rc_fresh_ctr := 0;
  (* Phase 0: borrow inference.  [?borrow_map] lets the driver compute this
     ONCE and hand the same answer to [Escape], whose stack-promotion verdict
     must be taken against the map this pass placed its RC ops against — see
     [Escape]'s module doc.  Omitted, it is computed here exactly as before. *)
  let borrow_map = match borrow_map with
    | Some bm -> bm
    | None -> Borrow.infer_module m in
  (* Phase 0b: publish every function's parameter borrow modes, for the
     [$clo_wrap] trampolines [Llvm_emit] synthesises: a closure call consumes
     its arguments, so a trampoline whose target borrows one must release it
     after forwarding.  See [Clo_flags].  Reset first: the table is
     process-global and the REPL / test drivers compile many modules in one
     process. *)
  Clo_flags.reset ();
  List.iter (fun fn ->
    Clo_flags.register fn.Tir.fn_name
      (List.mapi (fun i _ -> Borrow.is_borrowed borrow_map fn.Tir.fn_name i)
         fn.Tir.fn_params)
  ) m.Tir.tm_fns;
  (* A user extern passed as a value gets a [$clo_wrap] too, forwarding to
     its C symbol: publish its seeded modes (heap params borrowed unless
     `consume`), so the trampoline releases what the C callee only borrows. *)
  List.iter (fun (ed : Tir.extern_decl) ->
    let name = ed.Tir.ed_march_name in
    if Clo_flags.borrowed_params name = None then
      Clo_flags.register name
        (List.mapi (fun i _ -> Borrow.is_borrowed borrow_map name i)
           ed.Tir.ed_params)
  ) m.Tir.tm_externs;
  let extern_names =
    List.fold_left (fun s (ed : Tir.extern_decl) ->
      StringSet.add ed.Tir.ed_march_name s) StringSet.empty m.Tir.tm_externs
  in
  (* Module-scoped env fields: constant for every function processed below. *)
  let module_cs = Collision_set.compute m.Tir.tm_types in
  let module_env =
    { empty_env with
      borrow_map;
      type_defs = m.Tir.tm_types;
      collision_set = module_cs;
      k_table;
      extern_names }
  in
  let repl_set =
    List.fold_left (fun s n -> StringSet.add n s) StringSet.empty repl_vars
  in
  let preprocessed = List.map (preprocess_fn ~k_table) m.Tir.tm_fns in
  (* Owned-call drop fusion (see [Perceus_core.owned_calls]).  The table is
     filled with the clone-eligible functions' PRE-RC bodies, exactly what
     [insert_rc] receives for the original, so a clone is the original
     processed under a different ownership signature. *)
  let oc =
    if not owned_calls || repl then None
    else begin
      let oc = { oc_fns = Hashtbl.create 64; oc_clones = Hashtbl.create 16;
                 oc_pending = Queue.create ();
                 oc_alloc_bound = ref StringSet.empty;
                 oc_useful = Hashtbl.create 64 } in
      List.iter (fun fn ->
          if owned_clone_eligible borrow_map fn then
            Hashtbl.replace oc.oc_fns fn.Tir.fn_name fn) preprocessed;
      compute_useful_positions borrow_map oc;
      Some oc
    end
  in
  let module_env = { module_env with owned_calls = oc } in
  let rc_one ~(modes : int -> bool) (fn : Tir.fn_def) =
    let base =
      if fn.Tir.fn_name = "main" then repl_set else StringSet.empty
    in
    let borrowed =
      List.fold_left (fun s (i, p) ->
        if modes i then StringSet.add p.Tir.v_name s else s
      ) base (List.mapi (fun i p -> (i, p)) fn.Tir.fn_params)
    in
    (match oc with
     | Some oc -> oc.oc_alloc_bound := collect_alloc_bound fn.Tir.fn_body
     | None -> ());
    insert_rc ~module_env ~repl:clo_drop ~borrowed fn
  in
  let originals_after_insert =
    List.map (fun fn ->
        rc_one ~modes:(Borrow.is_borrowed borrow_map fn.Tir.fn_name) fn)
      preprocessed
  in
  (* Build every requested clone; a clone's own calls may request more.
     Clones are appended after all originals so the originals' fresh [$rc_N]
     names (and with them the TIR snapshots) do not depend on the feature. *)
  let clones_after_insert, borrow_map =
    match oc with
    | None -> ([], borrow_map)
    | Some oc ->
      let rec drain acc bm =
        match Queue.take_opt oc.oc_pending with
        | None -> (List.rev acc, bm)
        | Some (name, orig, positions) ->
          let src = Hashtbl.find oc.oc_fns orig in
          let modes i =
            Borrow.is_borrowed borrow_map orig i && not (List.mem i positions) in
          let clone = { src with Tir.fn_name = name } in
          let fn' = rc_one ~modes clone in
          (* An owned parameter the body never mentions: Perceus has no use
             to release it at (borrow inference never makes such a parameter
             owned in an original), so the clone releases it on entry. *)
          let fn' =
            List.fold_left (fun (fn' : Tir.fn_def) i ->
                match List.nth_opt fn'.Tir.fn_params i with
                | Some p when needs_rc module_env p.Tir.v_ty
                           && not (name_free_in p.Tir.v_name src.Tir.fn_body) ->
                  { fn' with Tir.fn_body =
                               Tir.ESeq (decrc_for module_env p (Tir.AVar p),
                                         fn'.Tir.fn_body) }
                | _ -> fn')
              fn' positions
          in
          let bm =
            Borrow.StringMap.add name
              (Array.of_list (List.mapi (fun i _ -> modes i) src.Tir.fn_params))
              bm in
          Clo_flags.register name
            (List.mapi (fun i _ -> modes i) src.Tir.fn_params);
          drain (fn' :: acc) bm
      in
      drain [] borrow_map
  in
  let fns_after_insert = originals_after_insert @ clones_after_insert in
  let fns' =
    fns_after_insert
    |> List.map elide_cancel_pairs
    |> List.map insert_fbip
  in
  if Lazy.force _perceus_debug then begin
    let before = count_rc_ops_module fns_after_insert in
    let after  = count_rc_ops_module fns' in
    print_perceus_stats ~label:m.Tir.tm_name ~before ~after ()
  end;
  ({ m with Tir.tm_fns = fns' }, borrow_map)
