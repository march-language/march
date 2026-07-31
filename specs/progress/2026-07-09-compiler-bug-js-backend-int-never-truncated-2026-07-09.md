# Compiler bug — JS backend Int `/` never truncated (2026-07-09)


- ✅ **`lib/tir/js_emit.ml`'s `inline_binop` shadowed the type-aware Int-division
  guard for the `/` operator.** `inline_binop("/")` matched first (a fast-path
  table for symbolic operators) and unconditionally emitted raw `(a / b)` —
  JS's true division — for EVERY `/` call, Int or Float. The correct,
  type-aware logic a few lines below (`"/", [a; b] when atom_ty a = TInt ->
  Math.trunc(a / b)`) was dead code, unreachable for the symbolic `"/"` name
  since `inline_binop` always won first. Reproduced minimally:
  `fn half(n: Int): Int do n / 10 end; half(15)` printed `1.5` under
  `--target js` (correct answer: `1`, and correct natively/interpreted).
  Found while wiring `TetrisLogic.level_for_lines`/`drop_interval_ms` into
  the Tetris playground demo's tick loop (`total_lines / 10` was silently
  producing fractional levels, e.g. "Level: 1.5").
- **Fix:** removed `"/"` from `inline_binop`'s combined `"/" | "/." -> Some "/"`
  arm (kept `"/."` — float division needs no truncation and was never
  ambiguous), forcing all Int `/` through the existing type-aware match arm.
  One-line-plus-comment fix in `lib/tir/js_emit.ml`.
- **Verified:** full suite green (805 tests, exit 0) including the existing
  `adversarial-regressions` int/float-division-by-zero cases; minimal repro
  now prints `1`; Tetris playground's level display and drop-speed ramp both
  correct in the browser (level text, and measured tick-interval deltas
  matching `drop_interval_ms(level)` exactly for level 0 and level 1).
- **Likely impact:** any `--target js` program dividing two `Int`s via the
  bare `/` operator (not the `div_int`-named builtin, nor `Int.div`-style
  helpers) got a fractional JS result instead of a truncated one — silent,
  no compiler warning, no type error (JS has no static Int/Float
  distinction at runtime). Plausibly present since `/`'s Int-truncation
  guard was added; not otherwise caught because the browser playground demo
  is the first `--target js` consumer in this repo to exercise Int
  division on a value that wasn't already a multiple of the divisor.
