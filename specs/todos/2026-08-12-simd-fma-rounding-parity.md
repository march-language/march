# `Simd.fma_f32x4`: interpreter double-rounds, compiled single-rounds

**Filed:** 2026-08-12 (final whole-branch review of the SIMD vector types feature)
**Status:** open — no observed divergence, formally unproven

## The asymmetry

`fma_f32x4` is lowered differently on the two backends:

- **Interpreted** (`lib/eval/eval.ml`, the `simd_f32x4_fma` builtin):
  `f32_round (Float.fma a b c)` — a *binary64* fused multiply-add, whose
  binary64 result is then rounded to binary32. Two roundings.
- **Compiled** (`lib/tir/llvm_emit.ml`, the SIMD `"fma"` arm):
  `llvm.fma.v4f32` — one *binary32* fused multiply-add. One rounding.

`fma_f64x2` has no such asymmetry: `Float.fma` and `llvm.fma.v2f64` are both
binary64-fused, the same operation.

Both sides are individually correct implementations of "a fused multiply-add
producing a binary32 lane"; they are simply not the *same* function, so
equality is a claim that has to be earned rather than assumed. Neither
`docs/simd-vectorization.md` nor the SIMD docstrings may state parity as a
guarantee until this is closed (the doc now states the empirical claim only).

## Empirical status

No divergence has been observed on any input exercised by the SIMD parity
fixtures (`test/native/simd_vector_core.march` and the `simd_vector`
interpreter suite in `test/test_stdlib_suite.ml`), nor by
`bench/simd_kernels.march`'s parity leg. That is a witness of absence, not
absence — none of those corpora search for a double-rounding boundary case.

## Closure conditions (either one closes this)

1. **Prove equivalence for binary32.** Double rounding
   `round_b32(fma_b64(a,b,c))` is known to be exact for binary32 operands
   when the intermediate format is wide enough (binary64 has 53 bits of
   significand vs. the 2*24+1 = 49 bits a binary32 product plus addend can
   need). If a clean argument covering subnormals, overflow to infinity, and
   the ties-to-even boundary holds, write it up here, state it in
   `docs/simd-vectorization.md` as a guarantee again, and close.
2. **Align the interpreter to a true binary32 fused multiply-add**, so the
   two paths run the same operation by construction, and add a fixture over
   a rounding-boundary triple.

Whichever route, add a targeted fixture (a triple chosen to sit on a
rounding boundary, asserted interpreted == compiled) rather than relying on
the general parity leg, which does not probe this.

## Pointers

- `lib/eval/eval.ml` — `simd_f32x4_fma` arm (comment points back here)
- `lib/tir/llvm_emit.ml` — SIMD `"fma"` arm (comment points back here)
- `docs/simd-vectorization.md` — "Known limits" fma bullet
