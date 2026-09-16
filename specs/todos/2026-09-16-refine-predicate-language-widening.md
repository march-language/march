# `[P3]` Refinement checker: predicate language is narrower than the solver

Filed 2026-09-16. **Plan:** `specs/plans/2026-09-16-refinement-precision-plan.md` (Part B).

Three bounded widenings of what a refinement predicate may say:

1. **Non-linear `*`.** `smt_of_r_marked` admits only a literal coefficient
   (`lib/refinecheck/refine_scope.ml:209-213`), yet `Smt.Mul` already exists and
   `division_safety.ml:83-93` already emits it, with a note that refusing
   general products "was a REGRESSION source, not a safety measure". The
   `Nonlinear_goal` skip reason was written and cut as out of scope
   (`obligation.ml:71-81`); revive it. Cheapest of the three.
2. **`/` and `%`, restricted.** March truncates toward zero
   (`specs/lang/core-march.md:1040-1058`); SMT-LIB's `div`/`mod` are Euclidean,
   so a naive rendering is unsound in the false-positive direction. Adopt the
   `@[measure]` gate's existing rule (non-zero literal divisor,
   `refine_encode.ml:3410`) plus a provably non-negative dividend.
   `witness.ml:350` needs matching truncating arms or a refuted obligation
   reports nothing.
3. **Strings: do NOT swap to z3's string theory.** Zero stdlib string
   refinements exist; all test demand is length comparison and empty-literal
   equality, which `$Str`/`$strlen` already covers. The one documented gap
   (`s == ""` manufactures no length fact) is closable with one ground axiom.
