`[P2]` Diagnose the `solver-undecided` bucket (filed 2026-09-01)

32 of 34 skipped refinement obligations over a six-stdlib-module sample land in
one undifferentiated `solver-undecided` bucket whose user-facing text says
nothing about the call in front of the reader.  Split it into four diagnosed
causes (unconstrained subject / partial conjunct / non-linear goal / opaque
application), keeping `Solver_undecided` as the honest residual, and promote the
sub-case that can be *proven* a real failure by executing the enclosing function
from its entry under the existing fuel limit and effect veto.

Design: `specs/2026-09-01-refinement-error-diagnosis-design.md`.

Does **not** close the underlying precision gaps (let-bound constants are still
not propagated into the path context; match-arm exclusions are still not
derived) — those are a separate item, and this one is sized to be independent
of them.

Soundness constraint, do not skip: `Witness.confirm_precond` validates against
the *recorded* path facts, so wiring it into the undecided branch as-is reports
confirmed failures in provably correct code — `stdlib/list.march:128`
(`List.last`'s recursive call) is the worked counterexample.  The negative
fixture asserting silence there is the most important test in the item.
