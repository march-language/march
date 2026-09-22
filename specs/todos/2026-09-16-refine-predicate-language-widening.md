# `[P3]` Refinement predicates: general truncating `/` and `%`

Filed 2026-09-16. Three parts of this item have landed: non-linear `*`
(`specs/progress/2026-09-16-refine-nonlinear-multiplication.md`), the
empty-string length fact (`specs/progress/2026-09-16-refine-empty-string-length.md`),
and increment 1 of division, the truncation-safe fragment
(`specs/progress/2026-09-22-refine-predicate-division-fragment.md`): `/` and
`%` reflect to `Smt.DivLit`/`Smt.ModLit` when the divisor is a non-zero
integer literal and the dividend is known non-negative
(`Refine_scope.known_nonneg`). What remains is increment 2.

**General truncation.** Outside that fragment (a possibly-negative dividend,
or a non-literal divisor) a predicate using `/`/`%` is still an
`unreflectable-predicate` skip, pinned by `test/test_refinecheck.ml`'s UP2
(`_ / 2 > 0`) and the "division outside the fragment" cases, which any
implementation must rewrite.

March's `/` and `%` truncate toward zero (`specs/lang/core-march.md:1040-1058`);
SMT-LIB's `div`/`mod` are Euclidean, so `(-7) / 2` is `-3` in March and `-4`
in the logic. The general encoding is
`ite(a >= 0, div a b, -(div (-a) b))` (and the matching remainder), which
needs:

- an `Ite` constructor that `lib/refine/smt.ml` does not have, plus arms in
  every exhaustive term walk (the `DivLit`/`ModLit` arms added by increment 1
  mark each site) and a case in `formula_wellsorted`'s Bool-vs-Int structure;
- for a non-literal divisor, a side condition that it is non-zero (a zero
  divisor panics at run time; the predicate has no value there), which
  `Division_safety.syntactic_nonzero` can serve for the easy shapes;
- the SMT-side non-negativity question could then replace the syntactic
  `known_nonneg` context entirely, or be kept as the fast path that keeps
  queries free of `ite`.

`witness.ml`'s `eval_operand` already evaluates truncating `/`/`%` (returning
`None` on a zero divisor), so refutations under the general encoding will be
confirmable without further work there.
