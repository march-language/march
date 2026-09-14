# `compare_int` / `compare_float` / `compare_string` link compiled and agree on both backends

**Landed 2026-09-13.** Filed the same day as
`specs/todos/2026-09-13-compare-string-does-not-link.md`, which named only
`compare_string`. All three were broken, and on the interpreter as well.

## The defect

The typechecker offers all three as `(T, T) -> Int`
(`lib/typecheck/typecheck_builtins.ml`). Neither backend matched that:

| backend | before |
|---|---|
| compiled | **did not link**: `"_compare_int"` / `_compare_float` / `_compare_string` undefined |
| interpreted | returned a `Less` / `Equal` / `Greater` constructor, so `int_to_string(compare_int(3, 5))` failed with `int_to_string: expected int` |

On the compiled side, `lib/tir/llvm_builtins.ml` had only the
`march_compare_*` rows, marked `in_is_builtin = false`: they are the helpers
`llvm_emit_arith` calls for string ordering. A source-level call therefore
lowered to the bare name. The C helpers return −1/0/1, the same contract as
the `Ord` method `compare`, which already worked on both backends.

## What landed

- **`lib/tir/llvm_builtins.ml`**: `in_is_builtin` rows `compare_int`,
  `compare_float`, `compare_string`, pointing at the existing C helpers.
- **`lib/eval/eval_builtins.ml`**: the three return `VInt` −1/0/1.
  `compare_float` on NaN returns 0, as `march_compare_float`'s
  `(x > y) - (x < y)` does.
- **`lib/tir/borrow.ml`**: `compare_string` borrows both operands, since
  `march_compare_string` only reads. The classification guard from
  `2026-09-13-builtin-borrow-classification.md` would have required an entry
  either way.

## Tests

- `test/native/compare_builtins.march` (+ `.expected`, `test/dune`) checks
  each builtin's three orderings and prints a `live_allocs` line for 10,000
  `compare_string` calls on fresh strings. The compiled output is identical
  to the interpreter's.
- Red control: with the borrow entry moved to `extern_owned_builtins`, the
  leak line reads `flat: false`.
- `test_compiler.ml` "compare builtins return Int": interpreter.

## Found alongside, filed

Writing the golden's NaN case hit `float_nan` not linking either. A sweep
confirmed six float builtins and `typed_array_slice` with no compiled lowering
at all: `specs/todos/2026-09-13-typechecked-builtins-without-compiled-lowering.md`.
