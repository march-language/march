(** Perceus — Phase 3: RC elision (cancel pairs) (Wave 3 Task 5 file split).
    Moved verbatim from [perceus.ml]; the only edit is qualifying
    [name_free_in] as [Perceus_liveness.name_free_in] (self-contained
    liveness group — see that module).

    Remove adjacent EIncRC/EDecRC cancel pairs.

    Also elide pairs that span an ELet binding whose RHS does not reference
    the cancelled variable (audit L5).  Perceus's [fix_tail_value]
    restructuring frequently wraps tail-position cleanup in an ELet, which
    otherwise prevents the simple adjacent-cancel detection from firing
    even though the Inc/Dec are semantically a no-op pair.

    Atomicity strictness (audit P4): a cancel pair is only elided when BOTH
    halves have the same atomicity.  Mixed (atomic↔non-atomic) pairs are
    left in place.  Rationale: [incrc_for] and [decrc_for] pick atomicity
    from [env.actor_sent] per function, so same-variable ops should always
    match in correct code.  If a future pass ever produces a mismatch
    (e.g. inliner copying code across actor-send boundaries), eliding would
    silently drop the atomic op and introduce a data race.  Being strict
    lets that class of bug surface via still-present RC operations rather
    than turning into a memory-ordering heisenbug.  The dedicated test
    [tir/perceus/p4_mixed_atomicity_preserved] pins the invariant. *)
let rec elide_expr (e : Tir.expr) : Tir.expr =
  let inc_dec_match v1 v2 = String.equal v1.Tir.v_name v2.Tir.v_name in
  match e with
  (* Cancel pair, matching atomicity *)
  | Tir.ESeq (Tir.EIncRC (Tir.AVar v1),
              Tir.ESeq (Tir.EDecRC (Tir.AVar v2), rest))
    when inc_dec_match v1 v2 -> elide_expr rest
  | Tir.ESeq (Tir.EAtomicIncRC (Tir.AVar v1),
              Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v2), rest))
    when inc_dec_match v1 v2 -> elide_expr rest
  | Tir.ESeq (Tir.EDecRC (Tir.AVar v1),
              Tir.ESeq (Tir.EIncRC (Tir.AVar v2), rest))
    when inc_dec_match v1 v2 -> elide_expr rest
  | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v1),
              Tir.ESeq (Tir.EAtomicIncRC (Tir.AVar v2), rest))
    when inc_dec_match v1 v2 -> elide_expr rest
  (* L5: cancel pair that spans an ELet whose RHS does not reference the
     RC'd variable.  Same atomicity-strictness rule as above. *)
  | Tir.ESeq (Tir.EIncRC (Tir.AVar v1),
              Tir.ELet (x, rhs,
                Tir.ESeq (Tir.EDecRC (Tir.AVar v2), rest)))
    when inc_dec_match v1 v2 && not (Perceus_liveness.name_free_in v1.Tir.v_name rhs) ->
    elide_expr (Tir.ELet (x, rhs, rest))
  | Tir.ESeq (Tir.EAtomicIncRC (Tir.AVar v1),
              Tir.ELet (x, rhs,
                Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v2), rest)))
    when inc_dec_match v1 v2 && not (Perceus_liveness.name_free_in v1.Tir.v_name rhs) ->
    elide_expr (Tir.ELet (x, rhs, rest))
  | Tir.ESeq (Tir.EDecRC (Tir.AVar v1),
              Tir.ELet (x, rhs,
                Tir.ESeq (Tir.EIncRC (Tir.AVar v2), rest)))
    when inc_dec_match v1 v2 && not (Perceus_liveness.name_free_in v1.Tir.v_name rhs) ->
    elide_expr (Tir.ELet (x, rhs, rest))
  | Tir.ESeq (Tir.EAtomicDecRC (Tir.AVar v1),
              Tir.ELet (x, rhs,
                Tir.ESeq (Tir.EAtomicIncRC (Tir.AVar v2), rest)))
    when inc_dec_match v1 v2 && not (Perceus_liveness.name_free_in v1.Tir.v_name rhs) ->
    elide_expr (Tir.ELet (x, rhs, rest))
  (* Recurse into all sub-expressions *)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (elide_expr e1, elide_expr e2)
  | Tir.ELet (v, e1, e2) ->
    Tir.ELet (v, elide_expr e1, elide_expr e2)
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fn ->
      { fn with Tir.fn_body = elide_expr fn.Tir.fn_body }
    ) fns in
    Tir.ELetRec (fns', elide_expr body)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun br ->
      { br with Tir.br_body = elide_expr br.Tir.br_body }
    ) branches in
    let default' = Option.map elide_expr default in
    Tir.ECase (a, branches', default')
  (* Leaf forms — no sub-expressions to recurse into *)
  | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _
  | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
  | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EFree _ | Tir.EIncRC _ | Tir.EDecRC _
  | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ | Tir.EReuse _ ->
    e

(** Elide cancel pairs in a function definition. *)
let elide_cancel_pairs (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_body = elide_expr fn.Tir.fn_body }
