# `[P3]` Refinement: an argument using non-linear arithmetic is never translated

Filed 2026-09-18, found while landing the demand-driven element rule
(`specs/progress/2026-09-18-refine-demand-driven-element-instantiation.md`).

```march
fn need_pos(n : {Int | _ > 0}) : Int do n end
fn t(y : Int) : Int do need_pos(y * y + 1) end    -- skip: unreflectable-subject
```

The 2026-09-16 widening (`specs/progress/2026-09-16-refine-nonlinear-multiplication.md`)
admitted a product of two non-literal terms in a PREDICATE (`smt_of`), not in
an ARGUMENT: the call-site reflector still refuses it, so the obligation has no
subject at all. A postcondition over the same expression proves (a lambda
`fn y -> y * y + 1` against a declared `(Int) -> {Int | _ > 0}` codomain is
proved through `check_fn_post_verdict`), so the two translators disagree.

Consequence: `List.map(ys, fn y -> y * y + 1)` cannot meet a positive-element
demand (the design's row l). Admit `Smt.Mul` in the argument reflector with the
same `nonlinear-goal` skip reason for a goal the solver cannot settle, and make
sure `Witness.eval_operand` evaluates it (it handles `*` already).
