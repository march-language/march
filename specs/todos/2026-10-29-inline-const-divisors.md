`[P3]` Inline nonzero-literal Int divisors for `/ % int_div int_mod int_div_euclid int_mod_euclid`.

Phase 1 of `specs/2026-10-29-floor-division-and-const-divisors-design.md`. The floor builtins
(`int_div_floor` / `int_mod_floor`) already do this; see
`specs/progress/2026-10-29-int-div-floor-builtins.md`. What is left is the other six ops.

- Today they are out-of-line `march_checked_*` calls, so LLVM never strength-reduces `x / 86400`.
  Checked 2026-10-29: the literal divisor does reach the emitter (`/(x, 86400)` survives to
  `tir-defun`, and `tir-opt-1-cprop` forwards a `let`-bound literal), so the change is confined to
  `emit_checked_int_div` in `lib/tir/llvm_emit.ml` and the `/` `%` arm in `llvm_emit_arith.ml`.
- Emit inline `sdiv`/`srem` for a literal other than 0 or -1; the Euclid pair adds the same
  one-compare fix-up the floor ops use.
- Negative literals arrive as `negate(2)`, not an `ALit`. Decide whether to fold that in the emitter.
- New `bench/int_div_const.march` must be registered in `test/test_bench_gate.ml`. The IR oracle will
  legitimately change for every program with a literal divisor; prove it goes red on a perturbation first.
