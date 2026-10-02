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
