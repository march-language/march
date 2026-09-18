# `[P3]` Typecheck: a type variable in a signature can be silently fixed by the body

Filed 2026-09-18, found while designing `specs/2026-09-18-parametric-element-flow-design.md` §1.

`fn bad(xs : List(a)) : List(a) do [0 - 5] end` typechecks: `a` is an
ordinary unification variable, fixed to `Int` by the body. Callers see
`List(Int) -> List(Int)` (`bad(["x"])` is "expected String but got Int",
pointing at the call rather than the definition). OCaml does the same; most
readers take `a` to mean "for all a".

Decide: (a) make annotation type variables rigid (an error at the definition,
breaking for any code relying on this), (b) warn when an annotated variable is
unified with a concrete type, or (c) document the current semantics in
`specs/lang/types.md`. The refinement checker does not depend on the choice:
its Phase 0 fix reads the inferred type (`2026-09-18-refine-parametric-rule-trusts-flexible-tyvars.md`).
Before choosing (a), measure how much of the stdlib and ecosystem relies on it.
