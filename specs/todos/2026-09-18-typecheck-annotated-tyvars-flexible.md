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

## Decision (repo owner, 2026-09-22)

Option **(b) now, moving to (a) later**: warn when an annotated type variable
is unified with a concrete type, and later make annotation type variables
rigid. **Measurement first**: before the warning lands, count the sites in
`stdlib/`, `specs/lang/types/accept`, `test/stdlib`, and `test/native` whose
signature type variables the body fixes (to a concrete type, or to another
annotation variable of the same function). That count sizes (b)'s noise and
(a)'s breakage. (c), documenting the flexible semantics as intended, is
rejected.
