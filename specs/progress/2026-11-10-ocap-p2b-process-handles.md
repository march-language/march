# `Process` handles (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 8. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- `Process.spawn` returns a `Process` handle; `ProcessError = Closed | ProcessFailed(String)`.
- Known gap (Task 1 review): releasing a PROCESS box frees the slot and closes the streams but does not reap the child, so a closed and dropped `Process` stays a zombie until waited on. Reap at release (`waitpid(WNOHANG)`, then a deferred reap) without killing the child.

## Done (2026-11-12, Task 8)

- `stdlib/process.march`: `spawn_async(command, args) : Result(Result(Process, ProcessError), CapError)`
  (`Authority.check("IO.Process", command)` first, as phase 1 left it; ruling R2). The
  `Process` box is kind PROCESS (9), `raw` = the runtime's stream slot, `aux` = the pid.
  `read_line : Result(Option(String), ProcessError)`, `write` / `kill : Result((), ProcessError)`,
  `wait_proc : Result(Int, ProcessError)`; none is capability-wrapped. Each goes through a
  private `with_live` (`handle_enter(p, 9)`, rebuild `LiveProcess(handle_aux(p), slot)`, call
  the raw builtin, `handle_leave`), as `File.with_raw` does. `wait_proc` reaps and then closes
  the handle, so a second `wait_proc`, a `write`, a `read_line` and a `kill` are `Err(Closed)`
  (a `kill` after the reap could otherwise signal a reused pid).
- `ptype ProcessError = Closed | ProcessFailed(String)` (`derive Eq`); a spawn failure's
  message ("cannot execute <cmd>: <reason>") is `ProcessFailed(msg)`.
  `opaque type LiveProcess = LiveProcess(Int, Int)` is the raw builtins' view only.
- Release without `wait_proc` (ruling R4, which supersedes the "without killing" line
  above): `march_process_release_handle` (runtime/march_runtime.c; `march_handle.c`'s PROCESS
  case) closes the streams, SIGTERMs a child that `waitpid(WNOHANG)` finds still running, reaps
  with `waitpid(WNOHANG)`, and keeps a child that has not exited yet on a pending list that the
  next spawn (`spawn_async`, `spawn_sync`) or release sweeps, never blocking. A handle whose slot
  `wait_proc` already released is a no-op (the generation check), so a reaped pid is never
  signalled. The interpreter's twin is `Eval_runtime.live_proc_release` /
  `live_proc_reap_sweep`, registered as the PROCESS releaser in `eval_builtins.ml`.
- The raw `process_*` builtins are unchanged and still callable from user code; gating them
  stdlib-only is Task 10 (`specs/todos/2026-11-10-ocap-p2b-gate-raw-builtins.md`).
- Tests: `test/stdlib/test_process.march` "async handles" (stdlib_march, plus new dune rules for
  `march test` and `--compile --test`); `process_release_reaps_child` in test_eval (close,
  interpreted) and test_codegen (close and drop, compiled), fixture
  `Test_helpers.process_reap_src`, which polls `ps -o stat= -p PID` until the pid is gone.
  The native fixtures `live_process_registry` (the stale p0 is now `Err(Closed)`),
  `process_handle_leak_probe`, `process_spawn_errors` and `process_spawn_sigmask` are migrated.
