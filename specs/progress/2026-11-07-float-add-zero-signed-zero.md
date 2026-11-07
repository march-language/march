# Float `+. 0.0` identity dropped the sign of zero (2026-11-07)

GitHub #1185. `lib/tir/simplify.ml` rewrote `x +. 0.0` and `0.0 +. x` to `x`.
That identity is false for `x = -0.0`: IEEE 754 gives `-0.0 +. 0.0 = +0.0`. The
interpreter computes it at run time and printed `+0`; native and `--target js`
(Simplify runs for both, independent of `opt.fold`) printed `-0`.

## Fix

- `+.`: simplify only when the literal is `-0.0`, the true additive identity
  (`x +. -0.0 = x` for every `x`, including `-0.0`).
- `-.`: simplify `x -. 0.0` only when the literal is `+0.0`; `x -. -0.0` is
  `x +. 0.0` and keeps its sign behaviour.
- OCaml float patterns compare with `=`, under which `0.0 = -0.0`, so the old
  `LitFloat 0.0` pattern also matched a `-0.0` literal. The guards test
  `Float.sign_bit` explicitly.

## Tests

`test/test_codegen.ml` `simplify/float_add_zero` (it used to pin `x +. 0.0 = x`)
now checks all six cases: `x +. 0.0` and `0.0 +. x` kept, `x +. -0.0` and
`-0.0 +. x` folded, `x -. 0.0` folded, `x -. -0.0` kept. RED on the old
simplify.ml, GREEN on the fix. The issue's repro now prints `+0` for both sums on
the interpreter, native and JS.
