`[P2]` - [x] **Compiled Csv open failure returns an error that is not a `FileError`** (logged 2026-11-11, fixed 2026-11-22)

When the file cannot be opened, the interpreter returns `Err(FileError("<path>: <reason>"))` as
documented. A compiled binary returned an `Err` whose payload printed as the bare reason, without
the constructor and without the path, and a `match` arm on `Csv.FileError(m)` did not match it.
Code that handles the documented error worked interpreted and fell through to its wildcard arm
when compiled. Side finding of the 2026-11-11 re-verification of the 2026-10-18 doc sweep.

## Root cause

`march_csv_open` (runtime/march_runtime.c) returned `mk_err_errno()` on a failed `fopen`, i.e.
`Err(<strerror string>)`. `csv_open` is typed `Result(Int, CsvError)`
(lib/typecheck/typecheck_builtins.ml), and the interpreter's `csv_open_impl`
(lib/eval/eval_net.ml) builds `Err(FileError(msg))` from OCaml's `Sys_error`, whose message is
`"<path>: <reason>"`. The compiled program therefore read a `march_string` where a `CsvError`
cell belonged: `to_string` printed the string, and the `FileError` arm's tag test failed. This is
the same defect the `file_*` / `dir_*` builtins had
(specs/progress/2026-08-08-file-open-fileerror-representation-fix.md,
specs/progress/2026-09-08-file-dir-builtins-fileerror-representation-fix.md); `csv_open` was
missed by that sweep.

The stdlib side was fine: `Csv.read_all`, `read_csv`, `each_row` and `each_row_with_header`
(stdlib/csv.march) all pass `csv_open`'s `Err(e)` through unchanged, and no other stdlib module
calls `csv_open`. The JS runtime has no `csv_open`.

## Fix

`march_csv_open` now builds the error with `mk_err_csv_file_error(path)`: a real `CsvError`
cell, tag 0 (`FileError`, stdlib/csv.march's ptype declaration order), payload
`"<path>: <strerror(errno)>"`, its header stamped with `Csv.CsvError`'s type id (as
`File.FileError` cells are) so compiled `to_string` prints the constructor name. The `EMFILE`
path (handle table full) uses the same helper.

## Test

test/test_stdlib_suite.ml `test_compiled_csv_open_err_is_fileerror` (adversarial-regressions,
`Slow`): every Csv entry point on a missing path, rendered with `to_string` and matched on
`Csv.FileError(m)`; the interpreter's output is pinned to the documented text and the compiled
binary must equal it byte for byte. Seen failing before the fix (`Ok(Err(No such file or
directory))` / `other CsvError`).

## Not fixed (seen while here)

`march_csv_open` ignores its `mode` argument and always parses RFC 4180 (`(void)mode_ptr;`
"we always use rfc4180 for now"), while the interpreter honours `:simple`. A quoted field in a
`:simple` file parses differently compiled and interpreted. Filed as
specs/todos/2026-11-22-csv-simple-mode-ignored-compiled.md.
