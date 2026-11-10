`[P2]` `--target js` Float literals round-trip to the same double (#1169)

**Done:** 2026-11-09. GitHub issue #1169; there was no `specs/todos/` file.

`js_emit.ml`'s `emit_literal` printed `LitFloat` with `string_of_float`, which is
`%.12g`. Every literal with more than 12 significant digits became a different
double in the JS program: source literals, `Math.pi()` / `Math.tau()` / `Math.e()`
(their bodies are literals that inlining brings to the call site), and anything
`opt.fold` computed. For a non-finite value `string_of_float` gives `inf` / `-inf` /
`nan`, the emitter appended `.0`, and node refused the module (`SyntaxError:
missing ) after argument list`). Overflow reaches that without any division by
zero: `<1 followed by 308 zeros>.0 *. 10.0`, or a literal of 1 followed by 309
zeros, which is already infinite when lexed.

What landed:

- `lib/tir/js_emit.ml`: `js_float_lit`. Finite values use `%.<p>g` for the first
  `p` from 12 to 17 whose text parses back to the same 64 bits (17 always does),
  so a literal that already fit in 12 digits prints the same digits as before;
  `-0.0` keeps its sign; non-finite values are `Infinity`, `(-Infinity)` (in
  parentheses so it stays one operand beside a binary `-`) and `NaN`.
- `literal_tag_js` (float `match` patterns) used `%.17g`, which was exact but gave
  `inf` for an infinite pattern literal; it now calls `js_float_lit` too.

The runtime's `march_float_to_string` keeps its 12 digits on purpose: it matches
the native `%.12g` printer. It is not a constant.

Test: `test_js_float_literal_bits` in `test/test_codegen.ml` prints each value's
bits (sign, 53-bit mantissa, exponent, found by exact halving and doubling; -0 told
from +0 by `atan2`) rather than its printed form, under the interpreter, a native
build and node: long literals, `Math.pi/tau/e`, folded `1.0 /. 240.0` and
`0.1 +. 0.2`, folded `+inf` / `-inf` / `nan` by overflow, a literal infinity,
literal and folded `-0.0`, folded `+0.0`, and a float pattern match on pi and on
infinity. Before the fix node failed to load the module.

## opt.fold no longer folds `/.` by zero

Found with the same issue. `fold_float_op` (`lib/tir/fold.ml`) folded `/.` with no
divisor test, while `fold_int_op` refuses a zero divisor. `1.0 /. 0.0` is specified to
stop with "division by zero" (`specs/lang/core-march.md`, δ-Div-0F), and does in the
interpreter and in a `--disable-pass opt.fold` native build (`march_checked_fdiv`), but
a default `--compile` build printed `inf` and exited 0. A divisor of `0.0` or `-0.0` is
now left unfolded, so the run-time check sees it.

Tests: `test_fold_float_div_by_zero` (the TIR is unchanged for `1.0 /. 0.0` and
`1.0 /. -0.0`; `1.0 /. 240.0` still folds) and `test_compiled_float_div_zero_literal`
(interpreter and a default native build both stop, exit 1). Both fail without the fix.

Not fixed here: the JS run-time `/.` does not check its divisor
(`todos/2026-11-09-js-float-div-by-zero.md`), so `--target js` now prints `inf` for
this program instead of failing to load.
