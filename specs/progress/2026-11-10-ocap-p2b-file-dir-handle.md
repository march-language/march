# `File.Dir`: authority over a subtree (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 7. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- `File.Dir` handles; opens beneath a directory with Linux `openat2(RESOLVE_BENEATH)`, macOS best effort (`O_NOFOLLOW` per component; every symlink beneath a dir handle is refused, owner decision 2026-11-10).
- `FileError` gains `Escapes(String)`; new `runtime/march_file_beneath.c`.

## Done (2026-11-11, Task 7)

- `stdlib/file.march` (`mod File`): `open_dir` (`IO.FileRead`), `open_dir_write`
  (`IO.FileWrite`; the box's `aux` word is 1), `open_in`, `open_write_in`
  (`Err(Permission(rel))` on a read-only dir), `list_in` (`""` lists the dir itself),
  `close_dir`. Every use goes through a private `with_dir` (`handle_enter(d, 2)` /
  `handle_leave`), as `with_raw` does for `File.Handle`. A handle opened through a dir holds
  its own descriptor and outlives `close_dir`. The dir fd follows the inode: renaming the
  directory after `open_dir` does not change what `rel` resolves against (tested).
- `FileError` gains `Escapes(String)` (last; tag 6). The `FILEERR_*` tags moved to
  `runtime/march_runtime.h` (with `CLOSED` 5 and `ESCAPES` 6).
- `runtime/march_file_beneath.c` (role core, jit). Lexical refusal first on every platform
  (empty, absolute, NUL byte, a `..` climbing above the dir after normalisation, or `.`),
  then Linux `openat2(RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS)` with a fallback to the
  component walk on `ENOSYS`; macOS always walks (`O_DIRECTORY|O_NOFOLLOW` per
  intermediate component, `O_NOFOLLOW` on the last; a symlink is reported as `ELOOP` even
  where the platform says `ENOTDIR`). `EXDEV`/`ELOOP` become `Escapes(rel)`. The
  March-value builtins use helpers `march_runtime.c` now exports (`march_fh_register`,
  `march_file_ok`, `march_file_err`, `march_file_string_list`).
- `lib/eval/eval_beneath_stubs.c` `#include`s the same file with
  `MARCH_BENEATH_CORE_ONLY` (no March values), so both backends run one implementation;
  `lib/eval/dune` names it in `extra_deps`, and `scripts/check-runtime-sources.sh`
  Check 6 enforces both.
- Four raw builtins, stdlib-only, at every builtin site (typecheck signature + cap table,
  `stdlib_only`, `path_arg_builtins`, `Cap_symbols.table`, `cap_infer`, LSP inlay table,
  `llvm_builtins` row + preamble, borrow, defun, purity, golden preamble, interpreter, C):
  `dir_open` (`IO.FileRead`, path arg 0), `dir_open_write` (`IO.FileWrite`, path arg 0),
  `file_open_at : Int -> String -> Int -> Result(Int, FileError)` (flags 0 read,
  1 truncate, 2 append), `dir_list_at : Int -> String -> Result(List(String), FileError)`
  (sorted). **Deviation from the plan:** the plan names three builtins with only
  `dir_open` (`IO.FileRead`); `open_dir_write` built on it would be charged only
  `IO.FileRead`, so a read-only module could get a write-capable dir (against plan
  decision 5). `dir_open_write` is the same open, charged `IO.FileWrite`. It is not
  charged `IO.FileRead` as well: a builtin carries one capability and
  `IO.FileSystem` is not covered by `FileRead` + `FileWrite`.
- Tests: `test/stdlib/test_file_dir.march` (stdlib_march; `march test` and compiled
  `--compile --test` rules in `test/dune`); `test_codegen.ml` `dir_beneath_symlink_linux`
  (interpreted and compiled; skipped with the reason printed off Linux);
  `test_stdlib_only.ml` gates the four builtins. The "dir works in a `needs ()` function"
  test is written, commented out, marked `-- passes after Task 10` (ruling R9).
