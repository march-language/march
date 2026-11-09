`[P3]` Structural termination certificate: tuple scrutinees

Filed 2026-10-27 by phase 1 of `specs/2026-10-26-termination-checking-design.md`
(`specs/progress/2026-10-27-termination-phase1.md`).

The phase 1 sweep compared the syntactic class A (466 stdlib units, 74 native) with the
certificate. 435 stdlib and 67 native A units are certified structural. The other 31 stdlib
and 7 native units fall into two groups:

- **`unproved:not-same-family`, 23 stdlib units: FIXED 2026-11-08**
  (`specs/progress/2026-11-08-nested-set-measures.md`). A mutual cycle may now hold different
  types at its positions, as long as every edge passes a strict component.
- **`unproved:no-structural-arg`, 8 stdlib and 7 native units.** Most match a TUPLE of
  parameters, as a merged multi-argument multi-head function does: `match (xs, ys) do
  (Cons(a, ar), Cons(b, br)) -> f(ar, br)` (`Msgpack.list_int_eq`, `Plot.zip_pts/go`).
  `structural_subvars` (`lib/refinecheck/refine_encode.ml`) only follows a `match` whose
  scrutinee is a variable. Extending it changes Tier 2's and the element-return
  hypotheses' verdicts too (F6), so it needs a refine-oracle diff with every line explained.
  A few others rebind a component name (the `copy(xs, ys)` rule working as intended).

Neither gap matters to a verdict until phase 3 gates the induction hypothesis on the
certificate. Phase 2's Int metrics can also cover some of these units.
