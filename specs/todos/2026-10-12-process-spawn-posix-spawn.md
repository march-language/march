`[P4]` Spawn child processes with `posix_spawnp` instead of `fork` + `execvp`

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
