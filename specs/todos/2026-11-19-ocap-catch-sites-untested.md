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

## Status by site (2026-11-24)

| Site (`runtime/march_runtime.c`) | Fixture | Fails under a count one too low? |
|---|---|---|
| `march_try_call_val`, `march_try_finally` | `test/cap_conformance/panic_caught_mortal_mark` | yes (ASan use-after-free, and the output changes) |
| `march_try_call` | `test/cap_conformance/panic_caught_try_call` | yes |
| `actor_run_on_stop` | `test/cap_conformance/on_stop_panic_in_frame` | yes (ASan) |
| `diag_dispatch` (crash observers) | `test/cap_conformance/observer_panic_in_frame_restores` | no: four crashes still leave a spare reference; find which before relying on it |
| `march_test_run` | `test/test_reports/panic_under_needs` | not checked (the mark is the launch authority, not a counted cell) |
| crash trap (`actor_green_thread`) | `test/cap_conformance/actor_restart_keeps_authority` (older) | not checked |
| `march_repl_guarded` | `test/test_jit.ml`, "a panic inside a frame leaves the launch authority" | missed by the original count; it had no restore at all (`specs/progress/2026-11-24-repl-jit-panic-leaves-frame-authority.md`) |
| stop trap (`actor_green_thread`) | none | blocked: `specs/todos/2026-11-24-on-stop-after-stop-in-nested-receive-diverges.md` |
| `march_thunk_trampoline` (task cancelled at a drain deadline) | none | needs a hard drain deadline; the task's thread ends at the catch |
| `actor_answer_inspect` | none | the renderer is compiler-generated and calls no function with `needs` |
| `actor_answer_migrate_check` | none | needs a hot-reload patch whose migration panics inside a function with `needs` |

"Fails under a count one too low" was checked by replacing `march_incrc(mark)`
with `march_cap_release(mark)` in a copy of the runtime (`MARCH_RUNTIME_DIR`).
The first five rows and the three older caught-panic fixtures also run under
ASan in CI (`specs/lang/golden/sanitize.sh`, the `cap` leg).

After the observer, on_stop, stop-trap, crash-trap and task catches nothing
else runs on that thread under the restored authority (the actor or task ends,
and an observer is a function value that enters its own authority), so for
those sites the restore matters only for the count. `shell_task`
(`runtime/march_shell.c`) catches without a restore for the same reason.

Left: the last four rows, and making the observer fixture able to fail.
## One more site (2026-11-24)

The count above missed `march_repl_guarded`, the native REPL's per-input guard,
which had no restore at all (fixed, with a test:
`specs/progress/2026-11-24-repl-jit-panic-leaves-frame-authority.md`). The other
`setjmp` catcher without a restore, `shell_task` in `runtime/march_shell.c`, ends
its green thread right after the catch, so nothing runs under the stale slot.
