# `[P3]` Refinement checker: a generic set-valued measure has no concrete-element instances

Filed 2026-09-15 while building Phase 4 of the set refinements strengthening
(`specs/plans/set-refinements-strengthening-plan.md`).

A `@[measure]` returning `Set(a)` over `Tree(a)` is declared with an opaque
`Elem` element. Applied to a `Tree(Int)` term, `resolve_sorts` would rename it
to a `Tree(Int)` instance whose result is still `Set(Elem)`, which z3 rejects.
Since 2026-09-15 that query is a sort-conflict skip instead
(`resolve_sorts_exact`, the `raise Exit` arm).

Direction: record which type parameter a set measure's element is, and use it
everywhere a measure's result sort is read at an instance: the instance
`declare-fun` (`instance_measure_text`), the arm pin and body-sort check
(`arm_axiom`), and `resolve_sorts`'s inference for the application. A fixture
with `tree_elts` over `Tree(Int)` and an `Int` literal in the predicate should
go from skipped to proved.
