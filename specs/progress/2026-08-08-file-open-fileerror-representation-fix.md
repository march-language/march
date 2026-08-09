# file_open's Err path built a bare string, not a FileError ADT cell (2026-08-08)

`file_open` is typed `Result(Int, FileError)` by the typechecker
(`lib/typecheck/typecheck.ml:2445`), and the interpreter (`lib/eval/eval.ml`)
correctly builds `Err(NotFound(path))` / `Err(Permission(path))` /
`Err(IoError(msg))` ADT values on failure. But the C runtime's
`march_file_open` (`runtime/march_runtime.c`) returned `mk_err_errno()`,
which builds `Err(<bare march_string>)` — a raw string pointer, not a boxed
`FileError` constructor cell. A natively compiled program matching
`Err(NotFound(path))` (or destructuring any `FileError` payload) would read
a `march_string` header's bytes as if they were a `FileError` cell's
tag/fields — a representation misread, not merely a wrong error message.

Separately, `lib/tir/llvm_builtins.ml`'s `file_open` row declared
`ret_ty = Result([TInt; TString])`, disagreeing with the typechecker's
`Result(Int, FileError)`.

## Fix

- `runtime/march_runtime.c`: added `mk_file_error(tag, payload)` /
  `mk_err_file(tag, payload)` / `mk_err_errno_file(path)` helpers that build
  a real tagged `FileError` cell (`march_alloc(24)` + `MARCH_SET_TAG` +
  field 0 = payload string), mapping `errno` the same way the interpreter's
  `unix_error_to_file_error` does for `file_open`: `ENOENT -> NotFound(path)`,
  `EACCES -> Permission(path)`, else `IoError(strerror(errno))`. Tags follow
  `stdlib/file.march`'s `ptype FileError` declaration order (NotFound=0,
  Permission=1, IsDirectory=2, NotEmpty=3, IoError=4). `march_file_open` now
  calls `mk_err_errno_file(ps->data)` instead of `mk_err_errno()`.
- `lib/tir/llvm_builtins.ml`: `file_open`'s `ret_ty` now reads
  `Result(Int, TCon("FileError", []))`, matching the typechecker. (This is a
  documentation-level fix only — both `TString` and `TCon(_, _)` lower to
  LLVM `ptr`, so it doesn't change emitted IR by itself.)
- Regression test: `test_compiled_file_open_err_is_real_fileerror` in
  `test/test_stdlib_suite.ml` (adversarial-regressions group) opens a
  nonexistent path via `file_open`, matches `Err(e) -> println(to_string(e))`,
  and checks the compiled binary's output reflects a correctly-tagged
  `FileError` cell (tag 0 = NotFound) rather than the old bug's raw errno
  string ("No such file or directory") leaking through unchanged. Verified
  by temporarily reverting the runtime fix (via a file-copy swap, not `git
  stash` — worktree stash stacks are shared across sessions) and confirming
  the pre-fix compiled output was exactly the raw `strerror(ENOENT)` string,
  while post-fix it reflects the real tag.

## Left open

- **Scope**: only `march_file_open` was fixed. Every other `mk_err_errno()`
  call site in `runtime/march_runtime.c` (`march_file_read`,
  `march_file_write`, `march_file_append`, `march_file_delete`,
  `march_file_copy`, `march_file_rename`, `march_file_stat`,
  `march_dir_mkdir*`, `march_dir_rmdir`, `march_dir_rm_rf`,
  `march_dir_list*`) has the exact same bare-string-instead-of-FileError-cell
  bug, since they're all typed `Result(_, FileError)` too. Filed as a
  follow-up todo (see `specs/todos/`) rather than fixed here, to keep this
  change reviewable.
- **Compiled `Show` can't resolve the bare `FileError` type's name**: even
  with a correctly-tagged cell, compiled `to_string(e)` on the value returned
  by `file_open`'s `Err` arm prints `"#<tag:0>"` instead of `"NotFound(...)"`
  the way the interpreter does. The typechecker registers `file_open`'s error
  type as the *bare*, unqualified `FileError` (`TCon("FileError", [])`,
  `lib/typecheck/typecheck.ml:2445`), while the only actual `ptype FileError`
  declaration lives inside `mod File` (`stdlib/file.march:12`), so its
  compiled type-def is registered under the qualified name `File.FileError`.
  Interpreted `to_string` dispatches structurally by constructor name and
  doesn't care about this split; compiled `Show` monomorphization needs the
  concrete type name to find the right printer and can't find one named bare
  `"FileError"`, so it falls back to a generic tag-only printer. This also
  means March source code cannot currently pattern-match `file_open`'s `Err`
  payload by constructor name at all (`Err(NotFound(p))` and
  `Err(File.NotFound(p))` both fail to typecheck against the bare-typed
  result) — only `Err(e)` with `e` treated opaquely (e.g. via `to_string`)
  works. Filed as a follow-up todo.
