# All other file_*/dir_* runtime builtins still build a bare-string Err, not a FileError cell

Follow-up to `specs/progress/2026-08-08-file-open-fileerror-representation-fix.md`,
which fixed only `march_file_open`.

Every remaining `mk_err_errno()` call site in `runtime/march_runtime.c` —
`march_file_read`, `march_file_write`, `march_file_append`,
`march_file_delete`, `march_file_copy`, `march_file_rename`,
`march_file_stat`, `march_dir_mkdir`, `march_dir_mkdir_p`, `march_dir_rmdir`,
`march_dir_rm_rf`, `march_dir_list`, `march_dir_list_full` — is typed
`Result(_, FileError)` by the typechecker but still returns
`Err(<bare march_string>)` at the C level, the same representation misread
`march_file_open` had. A compiled program matching or destructuring the
`Err` payload of any of these reads a `march_string` header as if it were a
`FileError` cell.

Fix: route each of these through the `mk_err_errno_file(path)` /
`mk_err_file(tag, payload)` helpers added alongside `march_file_open` (see
the progress doc above), choosing the right `errno`→tag mapping per call
site (mirroring `lib/eval/eval.ml`'s `unix_error_to_file_error` /
`sys_error_to_file_error`, which additionally maps `EISDIR -> IsDirectory`
and `ENOTEMPTY -> NotEmpty` for the dir builtins). Add compiled-vs-interpreted
regression coverage per builtin (or at least one representative file_* and
one dir_* case) following the pattern of
`test_compiled_file_open_err_is_real_fileerror` in `test/test_stdlib_suite.ml`.

## Related, separate gap (also left open)

Compiled `to_string`/`Show` on a `file_open`-style `Err` payload prints
`"#<tag:0>"` instead of the interpreter's `"NotFound(...)"`, because the
typechecker registers these builtins' error type as the bare, unqualified
`FileError` (`TCon("FileError", [])` in `lib/typecheck/typecheck.ml`) while
the only real `ptype FileError` is declared inside `mod File`
(`stdlib/file.march:12`) and compiled as `File.FileError`. This also means
March source cannot currently pattern-match a `file_open`/`file_read`/etc.
`Err` payload by constructor name at all — `Err(NotFound(p))` and
`Err(File.NotFound(p))` both fail to typecheck against the bare-typed
result; only `Err(e)` with `e` treated opaquely works. Fixing this likely
means either (a) qualifying these builtins' declared error type as
`File.FileError` in the typechecker table, or (b) registering a bare
top-level alias/type-def for `FileError` that resolves to the same compiled
type-def as `File.FileError`. Needs investigation into how other
module-qualified ptypes used by bare builtins are (or aren't) handled
elsewhere before picking an approach.
