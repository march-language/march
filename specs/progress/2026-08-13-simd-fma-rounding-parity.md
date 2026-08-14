# `Simd.fma_f32x4`: interpreter now single-rounds, matching the compiled path

**Filed:** 2026-08-12 (final whole-branch review of the SIMD vector types feature)
**Closed:** 2026-08-13 via closure condition **2** (align the interpreter to a
true binary32 fused multiply-add). Condition 1 — prove double rounding
innocuous — is **false**: divergent triples exist and are now regression tests.

## The asymmetry (as filed)

- **Interpreted** (`lib/eval/eval.ml`, `simd_f32x4_fma`):
  `f32_round (Float.fma a b c)` — a binary64 fused multiply-add narrowed to
  binary32. Two roundings.
- **Compiled** (`lib/tir/llvm_emit.ml`, SIMD `"fma"` arm): `llvm.fma.v4f32` —
  one binary32-fused rounding.

`fma_f64x2` never had the asymmetry (`Float.fma` IS binary64-fused).

## The premise was real: divergent triples exist

The filed status was "no observed divergence, formally unproven". Both halves
turned out to be findable:

1. **Random search.** An LCG over binary32 bit patterns, comparing hardware
   `fmaf` (the same operation as `llvm.fma.f32`) against
   `(float)fma((double)a,(double)b,(double)c)` (the old eval formula), found
   **1 divergence in 19,765,878 finite triples**:
   `a = 0x6be58000`, `b = 0x3a123b00`, `c = 0x117d0e3e` →
   single-rounded `0x668317e5`, double-rounded `0x668317e4`.
2. **Targeted construction.** Pick `a*b` to be *exactly* a binary32 midpoint —
   a 25-bit odd significand — and `c` small enough that the binary64 add
   swallows it: `24929 * 673 = 2^24 + 1` exactly (both factors are exact
   binary32 integers), with any `c` down to the smallest subnormal 2^-149. The
   exact value is then strictly above the midpoint, so the single rounding goes
   up to `2^24 + 2`, while the binary64 intermediate lands back on the midpoint
   and ties-to-even sends the double rounding down to `2^24`. Divergence is
   *systematic* in this family, not a needle: with `c > 0` it happens every
   time.

Confirmed on the real backends, not just in C: the same triples through
`Simd.fma_f32x4` printed `16777216.` / `3.09535356751e+23` interpreted and
`16777218.` / `3.09535392779e+23` compiled.

Why the old "53 ≥ 2·24+1" argument in the filed note does not save it: 48 bits
suffice for the *product*, but the *sum* `a*b + c` can need far more when the
exponents are far apart, and the binary64 add is where the first rounding
happens.

## The fix

`fma32_single_round : float -> float -> float -> float` beside `f32_round` in
`lib/eval/eval.ml`: round-to-odd emulation (Boldo–Melquiond). `a *. b` is exact
in binary64 (24+24 = 48 ≤ 53 significand bits) because SIMD f32 lanes are always
binary32-representable — every lane store goes through `f32_round`. TwoSum
recovers the add's exact residual; when the binary64 sum is inexact with an even
significand, it is stepped one ulp toward the residual, which is round-to-odd of
the exact value, and rounding an odd binary64 to nearest binary32 equals a single
rounding of the exact value (53 ≥ 24+2). NaN/infinite sums short-circuit to
`f32_round`.

## Subnormals

The classic trap for round-to-odd emulation, checked explicitly rather than
argued: a 50M-triple sweep with operand exponents confined to the tiny end
produced **3,845,825 subnormal-or-zero binary32 results** with **zero**
mismatches against `fmaf` — and, notably, zero mismatches for the OLD formula
either. Double rounding cannot bite in that zone: for a subnormal result all
three operands are tiny, so the exponent spread stays far inside binary64's 53
bits and the binary64 add is exact. No scaled fallback is needed. Overall the
emulation was validated over >100M triples (full range, subnormal operands,
overflow-to-infinity zone, near-1 exponents, 20.9M midpoint-product
constructions, and all 1000 triples over {NaN, ±inf, ±0, ±1, FLT_MAX,
±min-subnormal}) with zero mismatches.

## Coverage added

- `test/test_stdlib_suite.ml`, `simd_vector` **t15** — the four boundary lanes
  above (constructed midpoint; midpoint with `c` = 2^-149; the randomly found
  triple; `c = 0` as an agreeing control), asserting the values *printed by the
  compiled binary*, plus infinity propagation and exact cancellation. Fails
  against the old formula.
- `test/native/simd_fma_fuzz.march` (+ `test/dune` rule) — 100k deterministic
  LCG iterations × 4 lanes, half drawn from the midpoint family, folded into an
  integer checksum scaled so one binary32 ulp is ≥ 256 checksum units.
  `.expected` is interpreter-produced and the compiled binary must match
  byte-for-byte. Non-vacuity: the pre-fix compiler prints `7748989859602766`
  against the fixture's `7748989891677518` — 125,292 of 400,000 lanes round
  differently. (The first draft of this fixture WAS vacuous: the mode selector
  read the LCG's low bit, which strictly alternates, and each iteration consumes
  a fixed four draws, so the boundary branch never ran and the checksum matched
  even under the old formula. The selector now reads bit 16.)
- `bench/simd_kernels.march`'s parity leg is now per-lane (four distinct triples
  per iteration, all four result lanes folded) instead of lane-0-only; its
  interpreted and compiled checksums agree (`-807.411332439` over 20k
  iterations).

## Pointers

- `lib/eval/eval.ml` — `fma32_single_round` (technique + witness in its comment)
- `lib/tir/llvm_emit.ml` — SIMD `"fma"` arm comment (now states parity)
- `docs/simd-vectorization.md` — "Known limits" fma bullet (caveat retired)
