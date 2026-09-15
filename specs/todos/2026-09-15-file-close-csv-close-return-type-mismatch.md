# `file_close` and `csv_close` return three different things

**Filed:** 2026-09-15, found while auditing the C cell builders for
`specs/progress/2026-09-12-compiled-to-string-module-declared-type.md`.
Pre-existing; not introduced by that work.

## The mismatch

| | `file_close` | `csv_close` |
|---|---|---|
| typechecker (`lib/typecheck/typecheck_builtins.ml`) | `Int -> Unit` | `Int -> Atom` |
| interpreter (`lib/eval/`) | `:ok` | `:ok` |
| compiled C (`runtime/march_runtime.c`) | heap `Ok(())` cell via `mk_ok_unit()` | heap `Ok(())` cell via `mk_ok_unit()` |
| compiled `ret_ty` (`lib/tir/llvm_builtins.ml`) | `TPtr TUnit` | `TPtr TUnit` |

A compiled program that uses the value — `csv_close(h) == :ok`, or rendering it
— compares or prints a heap pointer where the types promise an Atom or Unit.
`stdlib/csv.march` calls `csv_close(handle)` four times and discards the result,
which is why nothing has noticed.

Separately, both C bodies read `MARCH_FIELD(handle_ptr, 0)`, treating the
handle as a pointer to a cell, while the declared parameter is `Int`. Worth
checking against how `file_open` / `csv_open` build the handle before changing
either side.

## Interaction with header type ids

Since the C builders are stamped, that `Ok(())` cell carries `Result`'s header
type id, so reaching an ERASED render prints `Ok(())` where it printed
`#<tag:0>`. Neither is the interpreter's `:ok`. The stamp is truthful about the
cell; the declaration is what is wrong.

## Acceptance

Pick one contract per builtin and make all three agree: most likely `Atom`
(`:ok`) to match the interpreter and `csv_close`'s declaration, which means the
C side returns the `ok` atom rather than a `Result` cell and `file_close`'s
declaration moves from `Unit`. A compiled/interpreted parity test for each.
