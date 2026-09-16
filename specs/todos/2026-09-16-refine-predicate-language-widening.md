# `[P3]` Refinement predicates: `/` and `%` are outside the fragment

Filed 2026-09-16. Two of this item's three original parts have landed:
non-linear `*` (`specs/progress/2026-09-16-refine-nonlinear-multiplication.md`)
and the empty-string length fact
(`specs/progress/2026-09-16-refine-empty-string-length.md`). What remains:

`smt_of_r_marked` (`lib/refinecheck/refine_scope.ml`) has no `/` or `%` arm, so
a predicate using either is an `unreflectable-predicate` skip
(pinned at `test/test_refinecheck.ml`'s `_ / 2` fixture, which any
implementation must rewrite).

**The semantics, not the plumbing, are the work.** March's `/` and `%`
truncate toward zero (`specs/lang/core-march.md:1040-1058`, implemented by
OCaml's native operators in `lib/eval/eval_builtins.ml:30-42` and mirrored in
`runtime/march_runtime.mjs:326-340`); SMT-LIB's `div`/`mod` are Euclidean, so
`(-7) / 2` is `-3` in March and `-4` in the logic. Rendering one as the other
is unsound in the false-positive direction — it would make the checker certify
code that can fail.

Direction, in two increments:

1. **Restricted fragment.** Admit `/` and `%` only with a non-zero integer
   literal divisor and a provably non-negative dividend, where truncating and
   Euclidean agree. The `@[measure]` totality gate
   (`lib/refinecheck/refine_encode.ml`, the `/`/`%` arm) already implements the
   literal-divisor half and is a tested precedent; `Division_safety`'s
   `syntactic_nonzero` is directly reusable for the divisor side.
2. **General truncation**, as `ite(a >= 0, div a b, -(div (-a) b))`. Needs an
   `Ite` constructor that `lib/refine/smt.ml` does not have, plus an arm in
   `formula_wellsorted`'s Bool-vs-Int structure. Separate PR.

**The trap that makes this silent if missed:** `witness.ml`'s `eval_operand`
is a hand-written evaluator, not the interpreter, and its integer arithmetic
arm handles only `+ - *`. Without matching arms implementing OCaml's
*truncating* semantics (and returning `None` on a zero divisor rather than
raising), a refuted obligation becomes unconfirmable and the checker reports
nothing at all.
