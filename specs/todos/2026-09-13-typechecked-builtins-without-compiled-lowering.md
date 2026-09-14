# Builtins the typechecker accepts that a compiled program cannot link

Found 2026-09-13 while fixing `compare_string`
(`specs/progress/2026-09-13-compare-builtins-link-and-agree.md`). These run
interpreted and typecheck, but `--compile` fails at the link step with an
undefined symbol named after the builtin. No compiled lowering exists: no
`in_is_builtin` row in `lib/tir/llvm_builtins.ml`, no special case in the
emitter, and no C function in `runtime/`.

Each was confirmed by compiling a one-line call on `main` at `16e27ab1`:

| builtin | interpreted | compiled |
|---|---|---|
| `float_nan()` | `nan` | `_float_nan` undefined |
| `float_infinity()` | `inf` | `_float_infinity` undefined |
| `float_neg_infinity()` | `-inf` | `_float_neg_infinity` undefined |
| `float_epsilon()` | `2.22044604925e-16` | `_float_epsilon` undefined |
| `float_is_nan(x)` | works | `_float_is_nan` undefined |
| `float_is_infinite(x)` | works | `_float_is_infinite` undefined |
| `typed_array_slice(a, i, n)` | works | `_typed_array_slice` undefined |

The four constants and two predicates want inline LLVM (`0x7FF8000000000000`,
`fcmp uno`, and so on) or tiny C helpers. `typed_array_slice` wants a C
implementation. Mind element ownership, per
`specs/progress/2026-09-13-builtin-borrow-classification.md`: a slice that
shares elements must take a reference on each.

## The class, and the guard it needs

A static scan found 173 typechecker builtin names with none of: a compiled
row, a string literal naming them anywhere in `lib/tir`, or a stdlib `fn`. The
scan is noisy. SIMD builtins dispatch by name prefix, and network builtins may
be target-gated. So the list above is only what was **confirmed**.

The durable fix is a test in the shape of `test_cap_symbols.ml`. Every
`typecheck_builtins` entry must resolve through exactly one of: an
`in_is_builtin` row, a listed special lowering, or an explicit "interpreter
only" list that the driver rejects with a proper diagnostic instead of a
linker error. Candidates to triage first: the `logger_*` family,
`http_fetch`, `dns_resolve`, `ws_*`, `tap`, `to_json`, `try_finally`,
`uuid_v7`.
