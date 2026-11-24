# Most authority-restoring catch sites have no test (2026-11-19)

Found by the ocap phase 4 Task 10b review. Task 10b made every native panic-catch
site restore the authority in force where the catch was entered (about ten sites
in runtime/march_runtime.c). The review found most of them untested: actor
`on_stop`, the stop/crash traps, task cancellation, `Actor.inspect`, the
hot-reload migrate check, observers and the test runners.

What to do: one `test/cap_conformance` (or test/native) fixture per site where the
site is reachable from a program: a scoped function whose callee panics into that
site, then a capability operation after the catch that must run under the outer
authority.

## One more site (2026-11-24)

The count above missed `march_repl_guarded`, the native REPL's per-input guard,
which had no restore at all (fixed, with a test:
`specs/progress/2026-11-24-repl-jit-panic-leaves-frame-authority.md`). The other
`setjmp` catcher without a restore, `shell_task` in `runtime/march_shell.c`, ends
its green thread right after the catch, so nothing runs under the stale slot.
