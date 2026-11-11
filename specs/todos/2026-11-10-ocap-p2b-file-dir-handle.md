# `File.Dir`: authority over a subtree (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 7. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- `File.Dir` handles; opens beneath a directory with Linux `openat2(RESOLVE_BENEATH)`, macOS best effort (`O_NOFOLLOW` per component; every symlink beneath a dir handle is refused, owner decision 2026-11-10).
- `FileError` gains `Escapes(String)`; new `runtime/march_file_beneath.c`.
