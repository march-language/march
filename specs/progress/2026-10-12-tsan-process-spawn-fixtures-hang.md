`[P4]` `MARCH_SANITIZE=thread` builds of the process-spawn fixtures never finish — RESOLVED as a TSAN limitation (Darwin), skipped by the sweep

Found 2026-10-12 by the TSAN sweep (`test/native/*.march` with an `.expected`, built with
`MARCH_SANITIZE=thread` on macOS 26 / M3, Homebrew LLVM 22.1.8). Two fixtures timed out at
1, 2 and 14 schedulers, with no TSAN report, while plain builds pass them:
`live_process_registry` (stuck after `p1 exit: 0`, in its concurrent phase) and
`process_handle_leak_probe` (after `run = 40, flat: true`). The process used 90-190% CPU.

## Not a March bug: two TSAN-on-Darwin effects

Diagnosed without a debugger: timing prints in a scratch copy of the runtime, `ps`/`lsof`,
and an in-process watchdog (a `DYLD_INSERT_LIBRARIES` dylib that, after N seconds,
`thread_suspend`s the other threads and prints their frame-pointer chains with raw
syscalls only, symbolized afterwards with `atos -o <binary> -l <load address>`).

**1. Every fork is slow (both fixtures, any scheduler count).** In a TSAN process, `fork()`
takes ~0.2 s, almost all of it kernel time, and the child takes another ~0.2 s to `exec`
and write its first line. The same holds for a plain C program, so this is not March:

| C program, fork + exec `echo`, 20 times | fork | child's first line |
|---|---|---|
| plain | 0.3 ms | 3.3 ms |
| `-fsanitize=thread` | 207 ms | 206 ms |
| `-fsanitize=thread`, 200 MB touched first | 195 ms | 231 ms |
| `-fsanitize=thread`, `posix_spawnp` instead of fork | 0.9 ms | 5.1 ms |

The TSAN run spent 7.6 s of system time out of 7.8 s wall (97% CPU): that is the CPU the
sweep saw. Copying a TSAN process's address space (its shadow mappings) is what costs.
The fixtures spawn about 250 processes each, so even when nothing blocks they need
roughly 70-90 s under TSAN, more than the sweep's deadline. Measured, each run alone:

| fixture (TSAN) | 1 scheduler | 14 schedulers |
|---|---|---|
| `live_process_registry` | 71 s, golden, 0 reports | did not finish in 900 s |
| `process_handle_leak_probe` | 89 s, golden, 0 reports | 93 s, golden, 0 reports |

**2. fork deadlocks inside TSAN (`live_process_registry` at 14 schedulers).** The watchdog
showed the forking thread inside `wrap_fork` -> libc `fork` -> `wrap_os_unfair_lock_lock`,
blocked on a libc lock (libc's fork takes its own locks before forking). Another scheduler
thread was in `march_int_to_string` -> `snprintf` -> `localeconv_l`: it held that libc lock
and was waiting in `__tsan::SlotLock`, which `wrap_fork` had taken (TSAN's `ForkBefore`)
before calling the real fork. That is a lock-order inversion between TSAN's fork
interceptor and libc's fork locks. Every other thread then piled up in `SlotLock` too
(`AfterSleep` in the scheduler idle loop and the preempt daemon, `MutexUnlock` on
`live_proc_mu`). A plain C program reproduces it: four threads looping on `snprintf` while
the main thread forks + execs `echo` 50 times hangs under TSAN (2 of 2 runs hit a 120 s
deadline). The plain build finishes in 0.2 s, and the `posix_spawnp` version under TSAN
finishes too. At one scheduler no other thread runs March code during the fork, so the
fixture is only slow there.

The runtime spawns with `fork()` + `execvp` in `march_process_spawn_async` and
`march_process_spawn_sync`. That is correct in plain builds. Switching to `posix_spawnp`
would avoid both effects, but it changes what a failed exec looks like (an error returned
by the spawn rather than a child that exits 127), so it is filed separately:
`specs/todos/2026-10-12-process-spawn-posix-spawn.md`.

## Resolution

- `scripts/tsan-sweep.sh` (new) is the sweep, committed: it builds each fixture that has
  an `.expected` under `MARCH_SANITIZE=thread`, runs it at 1, 2 and 14 schedulers with a
  SIGALRM deadline, and fails on a TSAN report or a deadline. On Darwin it skips these two
  fixtures, printing the reason above. It also skips, with their reasons, the fixtures
  `specs/todos/2026-10-12-tsan-sweep-uncovered-fixtures.md` lists as not runnable
  standalone (FFI objects, `--target js`, client-driven observe/shell programs).
- Linux is not skipped: its TSAN fork path was not measured here.

Checked: `scripts/tsan-sweep.sh -s "1 14" live_process_registry process_handle_leak_probe
js_let_shadowing supervisor_one_for_one_restart actor_counter supervisor_concurrent_child_crash`
-> 3 skipped with reasons, 6 runs, 0 failed.
