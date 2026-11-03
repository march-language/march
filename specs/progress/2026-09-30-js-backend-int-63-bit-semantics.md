# JS backend does not implement 63-bit `Int` semantics

`specs/lang/type-system.md` ("Int width and overflow") fixes `Int` as 63-bit,
wrapping modulo 2^63, and the interpreter and native backend now agree on it
(`specs/progress/2026-09-30-int-63-bit-overflow-parity.md`). `--target js`
(`lib/tir/js_emit.ml`) still represents `Int` as a JS number: arithmetic past
2^53 loses precision instead of wrapping, `int_max_value()` and the bitwise
builtins (32-bit in JS) differ, and `int_shr`/`int_popcount` follow JS rules.

Options: BigInt with `BigInt.asIntN(63, …)` after each op (correct, slow), or
document the JS target as a 53-bit/32-bit-bitwise subset and make the
interpreter-vs-JS parity tests skip overflow edges. Decide, then add a parity
case beside `test_compiled_int_overflow_parity`.

## 2026-10-11: decided, the JS target is a documented subset

**Decision (owner, 2026-10-11).** No `BigInt` emulation. `Int` on
`--target js` is a JS number, exact within ±(2^53 - 1), and that is the
documented contract. It is written into `specs/lang/type-system.md` ("Int on
the JavaScript target", under "Int width and overflow"; `docs/types.md`
regenerated) and the JS section of `docs/tooling.md`.

What the docs say, as measured on node 26: inside the range every Int
operation matches the interpreter. Past it, `+ - *` and `int_pow` round to the
nearest double (`9007199254740991 + 2` is `9007199254740992`), the checked
`int_*` builtins in `runtime/march_runtime.mjs` throw a `RangeError`, and
`int_max_value()`/`int_min_value()` are a compile error (they already were).
`/` and `%` by zero give `NaN` instead of panicking.

The "bitwise builtins are 32-bit in JS" line above was stale. The runtime's
`march_int_and`/`or`/`xor`/`not`/`shl` already worked on all 53 bits, with a
`RangeError` beyond, so the docs say 53 bits, not 32.

**Fixed on the way, inside the subset.** These made in-range answers differ
from the interpreter, which a subset must not do:

- Int `/` was a plain JS `/`, so `7 / 2` printed `3.5`. The symbolic `"/"`
  matched `inline_binop` first, which left `js_emit`'s typed `/` arm dead. It
  now emits `((a - a % b) / b)` when either operand is `Int`. That form is
  exact in range, where `Math.trunc(a / b)` can round up near 2^53.
- `march_int_shr` was the interpreter's OLD logical shift, so
  `int_shr(-8, 1)` threw a `RangeError` (the logical result is about 2^62).
  It is now arithmetic (`Math.floor(a / 2^n)`) and returns `-4`.
- `march_int_popcount` flipped the sign bit off first, so
  `int_popcount(-1)` was 62. It now counts the 63-bit pattern and returns
  `63`.

**Parity tests.** No interpreter-vs-JS test compared an overflow edge. The
dune `js_*` rules diff `test/native/*.expected` programs that stay in range,
so nothing needed a skip. The new case `test_js_int_subset_parity`
(`test/test_codegen.ml`, beside `test_compiled_int_overflow_parity`) asserts
that JS matches the interpreter line for line on in-range values. It pins the
JS-only tail (rounding past 2^53, the `int_shl` `RangeError`) separately,
with a comment pointing here. When `node` is not on PATH it prints a skip
message and passes.
