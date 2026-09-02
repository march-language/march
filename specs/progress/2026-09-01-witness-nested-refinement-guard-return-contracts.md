`[P3]` Return-contract witnesses decline parameters with a nested refinement (filed 2026-09-01, landed 2026-09-01)

`Witness.confirm_post` and `Witness.confirm_enumerative` (the return-contract
counterexample paths from `specs/progress/2026-08-30-counterexample-surfacing.md`)
ran `annotated_params → decode_model → admissible`, and `admissible` only
inspects a single top-level `A.TyRefine` per parameter. A refinement nested
in a record field, a type argument, or under a `TyLinear` wrapper was
unchecked, so a zero-filled decoded witness could violate it:

```march
mod P9 do
  type Box = { v : {Int | _ > 0} }
  fn f(b : Box) : {Int | _ >= 5} do b.v end
end
```

reported `but f({ v: 0 }) returns 0.` with `v = 0` violating the field's
own refinement.

Fix: both functions now run the same `witness_safe_param` gate that
`confirm_precond_reachable` (Task 5 of
`specs/plans/2026-09-01-refinement-error-diagnosis-plan.md`) already used.
The walk (`refinement_free` / `named_refinement_free`) moved from §8b to §6
next to `admissible` so all three callers share one definition; it follows
registered ADT/record definitions with a visited set, consults
`type_ctors` / `record_fields` BEFORE the builtin-name allowlist, and treats
an unregistered type name as unsafe. A declined witness leaves the
obligation `Skipped Solver_undecided`, which is silent outside
`cap verified`.

Not a live false positive today: nested refinements are not enforced at
construction anywhere, so `f({ v: 0 })` is accepted from a caller. This is
defence-in-depth that becomes load-bearing the day they are; the coupling is
recorded in `specs/todos/2026-09-01-nested-refinement-enforcement.md`.

Tests (`test/test_refinecheck.ml`): two gated end-to-end declines (record
field, type argument) plus a gated positive control (`but gpos(1) returns
1.`), and a solver-free `post-nested-unit` suite driving
`confirm_enumerative` directly with hand-built types (record field, type
argument, `TyLinear`) plus a control asserting the minimal witness `f(1)`.
RED control run: with the guard reverted, all five decline cases fail and
both controls still pass.
