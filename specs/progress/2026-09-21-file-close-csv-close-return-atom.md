# `file_close` / `csv_close` now return `:ok` on every layer

**Done:** 2026-09-21. Moved from `specs/todos/2026-09-15-file-close-csv-close-return-type-mismatch.md`
(original text kept below).

## What changed

One contract for both builtins, `Int -> Atom`, returning `:ok`:

| | before | after |
|---|---|---|
| typechecker `file_close` | `Int -> Unit` | `Int -> Atom` |
| typechecker `csv_close` | `Int -> Atom` | unchanged |
| interpreter | `:ok` | unchanged |
| C (`runtime/march_runtime.c`) | `void *`, heap `Ok(())` via `mk_ok_unit()` | `int64_t`, `march_atom_of_name("ok")` |
| `ret_ty` / declare (`lib/tir/llvm_builtins.ml`) | `TPtr TUnit`, `declare ptr` | `TCon "Atom"`, `declare i64` |

The model is `revoke_cap`, which already returned a runtime-hashed atom this way.
`march_file_close` also now zeroes the handle's `FILE*` field after closing, as
`march_csv_close` always did, so a second close is a no-op instead of a double
`fclose`.

## The handle question the todo raised

Both C closers read `MARCH_FIELD(handle_ptr, 0)` while the declared parameter
is `Int`. That is consistent, not a bug: `march_file_open` / `march_csv_open`
return `Ok(<heap cell>)` whose field 0 is the `FILE*` (csv adds the delimiter
and mode in fields 1-2). The March-level `Int` is an opaque pointer; nothing
does arithmetic on it, and `llvm_emit_call.ml` deliberately passes it to the
`ptr` parameter un-coerced (see the comment there). The interpreter uses a
different handle (an `in_channel` magic'd to `Int` for files, a table id for
csv), which is equally opaque. Left as is.

## Verification

- `test/native/close_returns_ok_atom.march` uses both results (`== :ok` and
  `to_string`) and runs through two dune rules against ONE `.expected`:
  compiled (`native_close_returns_ok_atom`) and interpreted
  (`native_close_returns_ok_atom.interp.out`).
- Red before the fix: the fixture was a type error (`expected () but got
  Atom` at the `file_close` use); a csv-only copy compiled and printed
  `csv_close == :ok: false` / `csv_close renders: :<atom>` while the
  interpreter printed `true` / `:ok`.
- Red after the fix, with only the C `csv_close` body reverted to return the
  `Ok(())` cell: the compiled rule printed `false` / `:<atom>` again; restoring
  it went green.
- `test/test_codegen.ml` preamble golden updated for the two `declare i64`
  lines. Public API: `file_close`'s result type moves from `Unit` to `Atom`;
  every stdlib caller (`file.march`, `seq.march`) uses it in statement
  position, so none changes.

---

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
