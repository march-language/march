# Math: Float contracts and laws, using the IEEE encoding (2026-11-15)

Landed 2026-11-15 on `claude/stdlib-float-laws` (built on `claude/refine-floats`, PR #1270, and
`claude/stdlib-laws-pass`).

## What

- **Return types** (callers get them with no call): `Math.min_float` and `Math.max_float`
  are bounded by both arguments and equal to one of them, and `Math.clamp_float` is within
  `[low, high]`, each unless an argument is NaN (or `high < low` for clamp).
- **Lemmas**, proved and in `stdlib/lemmas.verified` (105): `min_float_comm`,
  `max_float_comm` (non-NaN arguments), `clamp_float_within`, `abs_idem`, `abs_nonneg`,
  `sqrt_neg_nan`.
- **Checker:** `float_abs` and `math_sqrt` reflect, as `fp.abs` and `fp.sqrt RNE`
  (`Reflect_state.float_ops` `fabs`/`fsqrt`), so `Math.abs` and `Math.sqrt` are reflected.
- **WASM runtime fix:** `march_float_abs` was `f < 0 ? -f : f`, which returns `-0.0` for
  `-0.0`; it is now `__builtin_fabs`, as native `fabs`, OCaml `abs_float` and JS `Math.abs`
  already were. Modelling `float_abs` as `fp.abs` would otherwise have been wrong on WASM.

`Math` law coverage: 3 of 13 pure functions before this, 8 of 15 after (`abs` and `sqrt` count
as pure now that they reflect). `stdlib/math.march` (`cap verified`) checks with 25 proved, 0
skipped, 0 unenforced.

## Tests

`test/test_refine_stdlib_list.ml`, group `reflect-stdlib-float-laws` (5): `min_float` of two
non-negatives is non-negative from the return type; clamping a non-NaN into `[0, 1]` lands in
`[0, 1]`, and a possibly-NaN input does not; `abs` of a non-NaN is non-negative; `sqrt` of a
negative is NaN.

## Not done

- `abs` and `sqrt` as return types: a builtin call as the return expression does not translate
  (checker-gaps todo, item 9), so their facts are lemmas.
- `sqrt_nonneg`: z3 returns `unknown` for `fp.sqrt` beside an uninterpreted function (item 10).
- `lerp`, `floor`/`ceil`/`round`/`truncate` (Int conversion builtins are not reflected), and
  the transcendental functions.
