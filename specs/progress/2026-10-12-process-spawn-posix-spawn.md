# `[P4]` Spawn child processes with `posix_spawn` instead of `fork` + `execvp` — DONE

Filed 2026-10-12 from `specs/progress/2026-10-12-tsan-process-spawn-fixtures-hang.md`.

`march_process_spawn_async` and `march_process_spawn_sync` (`runtime/march_runtime.c`)
`fork()` a multi-threaded process and then call `close` / `dup2` / `execvp` in the child.

- Under `MARCH_SANITIZE=thread` on Darwin, each fork costs ~0.4 s and can deadlock inside
  TSAN's fork interceptor (details in the progress file), so `live_process_registry` and
  `process_handle_leak_probe` are skipped by `scripts/tsan-sweep.sh` and the process code
  has no TSAN coverage there.
- In any build, only async-signal-safe calls are allowed between `fork` and `exec` in a
  multi-threaded process; `execvp` searches `PATH` and is not on that list.

`posix_spawnp` with file actions (`addclose` / `adddup2`) measured 0.9 ms per spawn under
TSAN (fork: 207 ms) and does not deadlock.

## What changes

A command that cannot be executed (not found, not executable) is reported by
`posix_spawnp`'s return value. Today the fork succeeds, the child exits 127, and the
program sees `Ok` plus exit code 127. Decide whether `Process.spawn_async` / `Process.run`
should keep that shape (map the error to a reaped child with status 127) or return `Err`,
and match the interpreter (`lib/eval`). Also set `FD_CLOEXEC` on the parent's pipe ends
at creation (`pipe` + `fcntl` before the spawn, or `posix_spawn_file_actions_addclose`
for every other live child's fds) instead of after the fork, closing the window where
another thread's child inherits them.

Then remove the Darwin skip in `scripts/tsan-sweep.sh`.

## Resolution (2026-10-12)

Decided by the owner: switch to `posix_spawn`, and report a failed exec as an `Err` from
the spawn call.

**Sites ported.** The two fork sites behind `Process.*` in `runtime/march_runtime.c`:
`march_process_spawn_sync` (`Process.run`, `System.cmd`, and through
`march_process_spawn_lines` `Process.run_stream`) and `march_process_spawn_async`
(`Process.spawn_async`). Both now go through one helper, `spawn_child`:

- `posix_spawn_file_actions_adddup2` puts the pipe ends on 0/1/2. Every pipe end is
  close-on-exec from creation (`pipe2(O_CLOEXEC)` on Linux; `pipe` + `fcntl` on Darwin)
  and moved above fd 2, so the dup2 is never a same-fd no-op.
- On Darwin, `POSIX_SPAWN_CLOEXEC_DEFAULT` closes every fd the file actions do not name
  (the stdio the child keeps is named with `addinherit_np`). That covers the window
  between `pipe` and `fcntl`, and as a side effect a child no longer inherits unrelated
  non-close-on-exec fds there. Linux behaviour is unchanged on that point.
- `POSIX_SPAWN_SETSIGMASK` (empty) | `POSIX_SPAWN_SETSIGDEF` (all signals): the child
  starts with nothing blocked and every signal at its default action. Under fork it
  inherited the spawning thread's mask and any `SIG_IGN`.
- The child inherits cwd and `environ` (so `Process.set_env` is visible), as under fork.
  The Process API takes no per-child cwd/env, so no `addchdir_np` action is needed.
- PATH is searched in the parent (`spawn_resolve_path`: `stat` + `access(X_OK)` per
  entry), and the resolved path goes to `posix_spawn`. Darwin's libc `posix_spawnp`
  makes one `posix_spawn` syscall per PATH entry, each a whole failed process creation:
  with this machine's 28-entry PATH (`/usr/bin` 15th) 300 spawns of `true` took 11-13 s
  against fork + execvp's 6-8 s under the same load. With the parent-side search they
  took 3.5-5.6 s (interleaved A/B, load average ~120). When nothing executable is found,
  `posix_spawnp` is called anyway so the errno is the one execvp would have given.

A first version ordered pipe creation against spawns with a `pthread_rwlock` instead of
`CLOEXEC_DEFAULT`. With 8 tasks spawning at once at 14 schedulers (the concurrent phase
of `live_process_registry`) it hung in 17 of 20 plain runs, every spawner stuck before
`posix_spawn` returned; a plain mutex did not hang but was 3x slower. The rwlock was
dropped, not diagnosed further.

**Behaviour change.** A command that cannot be executed (`ENOENT`, `EACCES`, ...) is
`Err("cannot execute <cmd>: <strerror>")` from `Process.run` / `run_stream` /
`spawn_async` / `System.cmd`. Before, compiled code returned `Ok` and the child exited
127. The interpreter (OCaml 5's `Unix.create_process`, itself `posix_spawn`) already
returned `Err`, with the bare strerror; it now builds the same message
(`Eval_runtime.process_spawn_error`). A shell that runs and exits 127 for a missing
command is still an ordinary `Ok` exit code.

**Callers checked.** No March code tested for 127: `forge/tasks/notebook.march`,
`notebook_server.march` and `forge_registry.march` already handle `Err`, and the test
fixtures that spawn (`sleep`, `echo`, `cat`, `sh`) always find their program. The `127`s
in forge's OCaml (`forge/lib/procs.ml` and its tests, `upgrade_test.ml`,
`registry_query.ml`) are forge's own `Unix.fork` code, not the March runtime.

**Tests.** `test/native/process_spawn_errors.march` (compiled and interpreted, one
`.expected`): missing program and non-executable path are `Err` from all three entry
points; echo/exit-code/stdout capture, stdin to a live `cat`, an inherited `set_env`
and cwd. `test/native/process_spawn_sigmask.march` (compiled only): its dune rule starts
it with SIGUSR1 blocked and SIGPIPE ignored, and the children must die of
`kill -USR1 $$` / `kill -PIPE $$`. Without the spawn attributes they print `survived`
(checked by building with the flags set to 0).

**TSAN.** The Darwin skip of `live_process_registry` and `process_handle_leak_probe` is
removed from `scripts/tsan-sweep.sh`. `MARCH_SANITIZE=thread`, macOS 26 / M3, three runs
per scheduler count, load average ~120:

| fixture | 1 scheduler | 2 | 14 | before (fork) |
|---|---|---|---|---|
| `live_process_registry` | 7.6-8.0 s | 4.1-5.0 s | 3.1-3.3 s | 71 s at 1; hung (>900 s) at 14 |
| `process_handle_leak_probe` | 3.6-5.7 s | 2.6-3.9 s | 2.6-4.8 s | 89 s at 1; 93 s at 14 |

All 18 runs golden with 0 TSAN reports; `scripts/tsan-sweep.sh -s "1 2 14"` over both
plus the three other process fixtures: 15 runs, 0 failed, 0 skipped. Linux
(`march-ci-ubuntu-step6b`, arm64): the five process fixtures golden in plain and ASAN
builds, 0 ASAN reports.
