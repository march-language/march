# Int is 63-bit on both backends (overflow parity)

Found 2026-09-30: two `NativeArray.get_int` reads of `4611686018427387903` summed
printed `-2` interpreted and `9223372036854775806` compiled.

## Decision

`Int` is **63-bit two's complement, wrapping modulo 2^63**: range [-2^62, 2^62-1].
Canonical text: `specs/lang/type-system.md`, "Int width and overflow" (the primitive
table there used to say "64-bit", which no backend actually did end to end).

63 rather than 64 because everything except the compiled register path was already
63-bit: the lexer's literal limit (and its "March integers are 63-bit" error),
`march_string_to_int` (MARCH_INT_MAX), the hash builtins (masked to 62 bits for
cross-backend equality), TIR constant folding (OCaml `int`), the interpreter, and,
above all, the uniform tagged word `(n<<1)|1` every polymorphic slot (List cell,
tuple/record field, closure arg via `$clo_wrap`, actor message) stores an Int in.
64-bit would have meant boxing out-of-range Ints in every one of those slots.

## Compiled-backend changes

- `Llvm_ctx.emit_wrap_int63` (`shl 1` + `ashr exact 1`) after `+ - * /`
  (`llvm_emit_arith.ml`), unary negate, `int_shl`, `int_div`, `int_div_euclid`,
  `int_abs`, `int_pow` (`llvm_emit.ml`). `%`/`int_mod`/`int_mod_euclid`,
  and/or/xor/not, and `ashr` keep an in-range input in range and are not wrapped.
- This also removes real UB: `emit_tag_scalar` tags with `shl nsw`, so tagging an
  out-of-range value was LLVM *poison*, not merely a dropped bit. With every Int
  in range, the `nsw` is now true.
- `int_max_value`/`int_min_value` emit 2^62-1 / -2^62 (were 2^63-1 / -2^63).
- `int_popcount` masks bit 63 (only bit 62's sign extension) before `ctpop`.
- `int_shl`/`int_shr` with a non-literal count call new runtime helpers
  `march_checked_shl`/`march_checked_shr` (panic outside [0, 62], the interpreter's
  messages); a literal in-range count stays an inline instruction.
- `march_int_pow` computes in `uint64_t` (signed overflow was C UB) and panics on a
  negative exponent like the interpreter (it returned 0).

## Interpreter change

`int_shr` was `lsr` (logical) in `Eval_builtins`; compiled was always `ashr`. A
logical shift of a negative Int depends on the word width, so it is now `asr` on
both. Non-negative inputs are unaffected (stdlib hamt/array/json callers shift
non-negative values).

## Tests

`test/test_codegen.ml`: `test_compiled_int_overflow_parity` (wrap edges for every
op above, list/closure round trips, comparisons on wrapped values, interpreter
output asserted literally) and `test_compiled_int_shift_range_panics`. Verified
RED with `emit_wrap_int63` stubbed to the identity.

## Performance

Same-box A/B, wrap stubbed vs. on, `--opt 2`: list_ops and tree_transform within
noise; **bench/fib ~450 -> ~540 ms**, because the wrap before `ret` blocks LLVM's
accumulator TRE. Follow-up: `specs/todos/2026-10-01-int63-wrap-blocks-accumulator-tre.md`.

## Not covered

The JS backend: `specs/todos/2026-09-30-js-backend-int-63-bit-semantics.md`.
