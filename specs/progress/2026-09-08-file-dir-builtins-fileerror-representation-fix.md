# All remaining file_*/dir_* builtins now build a real FileError cell (2026-09-08)

Completes `specs/progress/2026-08-08-file-open-fileerror-representation-fix.md`,
which fixed only `march_file_open` and filed the rest as a todo.

Every `file_*`/`dir_*` builtin is typed `Result(_, FileError)` by the
typechecker (`lib/typecheck/typecheck_builtins.ml:880-977`), and the
interpreter builds a real `FileError` ADT value on failure. But the C
runtime's remaining sites returned `mk_err_errno()`, which builds
`Err(<bare march_string>)` — a raw string pointer, not a boxed `FileError`
constructor cell. A natively compiled program destructuring the `Err`
payload read a `march_string` header's bytes as if they were a `FileError`
cell's tag and fields.

## The substance: the mapping is per-builtin, not shared

The interpreter does **not** use one errno mapping for every builtin.
`lib/eval/eval_net.ml` defines `file_error_of_unix` / `file_error_of_sys`,
but only the read/write/append/delete family uses them; every other builtin
in `lib/eval/eval_builtins.ml` classifies the errnos its own syscall can
actually produce and falls back to `IoError`. Routing all thirteen sites
through one helper would have fixed the representation crash and still
reported the wrong error *kind* — a worse bug than the original, because it
looks correct. So the runtime now mirrors the split one-for-one:

| builtin(s) | helper | mapping |
|---|---|---|
| `file_read`, `file_write`, `file_append`, `file_delete` | `mk_err_errno_file_rw` | `ENOENT`→NotFound, `EACCES`/`EPERM`→Permission, `EISDIR`→IsDirectory, `ENOTEMPTY`→NotEmpty, else IoError(`"<path>: <strerror>"`) |
| `file_open` (unchanged) | `mk_err_errno_file` | `ENOENT`→NotFound, `EACCES`→Permission, else IoError |
| `file_copy`, `file_rename` | `mk_err_errno_io_path` | always IoError(`"<path>: <strerror>"`) |
| `file_stat` | `mk_err_errno_stat` | `ENOENT`→NotFound, else IoError |
| `dir_list` | `mk_err_errno_dir_list` | `ENOENT`→NotFound, `EACCES`→Permission, `ENOTDIR`→IsDirectory, else IoError |
| `dir_rmdir` | `mk_err_errno_rmdir` | `ENOTEMPTY`→NotEmpty, `ENOENT`→NotFound, else IoError |
| `dir_mkdir`, `dir_mkdir_p`, `dir_rm_rf` | `mk_err_errno_io` | always IoError(`strerror`) |

Note `dir_list` maps `ENOTDIR` (not `EISDIR`) to `IsDirectory`; that is what
the interpreter's `dir_list` arms do, and it is exactly the kind of detail a
copy-paste sweep loses.

The four non-errno bare-string sites in the same functions
(`"ftell failed"`, `"out of memory"`, and `"write failed"` in both
`file_write` and `file_append`) had the identical representation defect and
now build `IoError` cells via a new `mk_err_file_cstr`.

`march_file_copy` also classified the destination failure *after*
`fclose(in)`, which may clobber `errno`; it now classifies first.

`lib/tir/llvm_builtins.ml`: the twelve rows declared `ret_ty`'s error side as
`TString`, disagreeing with the typechecker. They now read
`TCon("FileError", [])`. Documentation-level only — both lower to LLVM `ptr`.

## Test

`test_compiled_file_dir_err_are_real_fileerrors` in
`test/test_stdlib_suite.ml` (adversarial-regressions group, `Slow`). One
March program exercises thirteen failure scenarios, so the whole table costs
a single compile. Interpreted output is the oracle for the expected
constructor; the compiled line must be either that same text or
`#<tag:N>` for that constructor's tag under `stdlib/file.march`'s
declaration order. Pre-fix the compiled line was the raw errno string
leaking through a misread `march_string`, which matches neither. The table
deliberately includes the mappings a uniform sweep would get wrong:
`file_write` onto a directory (`IsDirectory`, tag 2), `dir_rmdir` on a
non-empty directory (`NotEmpty`, tag 3), and the always-`IoError` builtins.

Covered: `file_read`, `file_write` (two scenarios), `file_append`,
`file_delete`, `file_copy`, `file_rename`, `file_stat`, `dir_list`,
`dir_mkdir`, `dir_mkdir_p`, `dir_rmdir` (two scenarios).

## Left open

- **`dir_rm_rf` has no test case.** Its compiled and interpreted behaviour
  already diverge on the obvious scenario: the interpreter's `rm_rf` treats
  a missing path as success (`Ok`), while the C `rm_rf` returns `-1`. That
  is a pre-existing semantic difference, not a representation bug, and
  fixing it is out of scope here. Its `Err` path is routed through
  `mk_err_errno_io` like its siblings.
- **`Permission` (`EACCES`) is untested.** Provoking it needs a `chmod` that
  a root CI runner would silently defeat.
- **`dir_mkdir` on `EEXIST`.** Compiled returns `Ok`; the interpreter returns
  `Err(IoError("<path>: already exists"))`. Again a semantic divergence, not
  a representation one; left alone.
- **`march_csv_open`** is the one remaining `mk_err_errno()` caller. It is
  typed `Result(Int, CsvError)` (`stdlib/csv.march:26`), a different ADT with
  its own tag order, so it has the same class of defect but needs its own
  mapping. Not in this todo's scope.
- **`dir_list_full`** is named in the todo but has no runtime implementation
  and no typechecker entry — only a stale row and `PDeclare` in
  `lib/tir/llvm_builtins.ml`. Nothing to fix; left as-is.
- **The two gaps the todo listed as "related, separate"** are untouched:
  compiled `to_string` on these payloads still prints `#<tag:N>` rather than
  the constructor name, and March source still cannot pattern-match them by
  constructor name, both because the typechecker declares the error type as
  the bare `TCon("FileError", [])` while the only real `ptype FileError`
  lives in `mod File` and compiles as `File.FileError`. A new todo carries
  those forward.
