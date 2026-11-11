# Mark the stdlib's cluster fd plumbing `@[stdlib_internal]` (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 9. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- `ClusterConn`/`NetKernel`/`ClusterNode` expose `fd : Int` publicly; mark the fd plumbing internal (prefer migrating fixtures to handles over exempting them).
