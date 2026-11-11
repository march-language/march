# `Process` handles (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 8. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- `Process.spawn` returns a `Process` handle; `ProcessError = Closed | ProcessFailed(String)`.
- Known gap (Task 1 review): releasing a PROCESS box frees the slot and closes the streams but does not reap the child, so a closed and dropped `Process` stays a zombie until waited on. Reap at release (`waitpid(WNOHANG)`, then a deferred reap) without killing the child.
