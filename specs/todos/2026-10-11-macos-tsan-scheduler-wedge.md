# `[P3]` `MARCH_SANITIZE=thread` binaries on macOS wedge with 2+ schedulers (no TSAN report)

Found 2026-10-11 while closing
`specs/progress/2026-10-07-macos-tsan-green-thread-races.md`. macOS 26, M3, Homebrew
LLVM 22.1.8 (the driver's TSAN fallback compiler).

## What happens

A TSAN build of a multi-scheduler program sometimes stops making progress: every thread
sits in the scheduler's 1 ms idle `nanosleep` poll (`ps -M`: each thread ~1% CPU, state
`S`), nothing is runnable, and the process never exits. TSAN prints nothing. A runnable
or parked-with-a-waker proc has been lost.

| program (TSAN build) | schedulers | runs | wedged |
|---|---|---|---|
| `test/native/run_until_idle_ping_pong.march` | 14 | 11 | 11 (no output at all) |
| same, with `n = 1000` instead of 200000 | 1 | 1 | 0 (`total 1000`) |
| same, `n = 1000` | 2 | 11 | 9 |
| `test/native/actor_counter.march` | default (14) | ~30 | ~9, after printing `value=5` (at exit) |
| `test/native/actor_monitor_down_reason.march` | 4 | 11 | 4, mid-output and at exit |
| `test/native/branch_alias_tail_drop.march` (one green thread) | 4 or 14 | 17 | 2, after its output (0 of 18 at 1, 2 or 8) |
| `nativearray_builtin_borrow_leak_probe.march` | default | ~29 | 2 |

## What it is not

- **Not this week's code.** A compiler built from 975bb7353 (2026-10-07) wedges the same
  way (`actor_counter` 2 of 3).
- **Not without TSAN.** The same `n = 1000` ping-pong at 2 schedulers: plain build 5/5
  clean, ASAN+UBSan build 5/5 clean, `MARCH_MALLOC=libc MARCH_NO_INLINE_RC=1` (the
  allocator and RC entry points a sanitizer build uses) 5/5 clean. Plain builds of the
  fixtures: `run_until_idle_ping_pong` at 14 schedulers 100/100, `actor_counter` 200/200,
  `branch_alias_tail_drop` 200/200.
- **Not an optimizer TLS hoist** (the `tl_sched`-across-a-switch class): relinking the
  TSAN build with the runtime at `-O0` still wedges (4 of 5).
- **Not a run-queue ownership violation**: a TSAN build with `-DMARCH_DEBUG` (the
  single-owner run-queue tripwires) wedges 5 of 5 without tripping one.

## Likely cause, unproven

TSAN on Darwin with ucontext green threads that migrate between OS threads. Candidates:
TSAN's interposed `sigprocmask`/`pthread_sigmask` inside libc's `swapcontext` (it may
process deferred signals there, and a ucontext's saved signal mask is restored on another
thread after a migration), or TSAN's deferred delivery of the SIGUSR1 preemption tick.
Neither has been tested.

## How to look (without a debugger)

Do not attach lldb to a wedged March process (see the kernel-panic note in the agent
memory). Instead: an env-gated watchdog thread in the runtime that, after N seconds with
no dispatch, prints each proc's status, owner scheduler and queue membership, then
`_exit`s. Repro: the `n = 1000` ping-pong under `MARCH_SANITIZE=thread`,
`MARCH_NUM_SCHEDULERS=2`, a 15 s alarm (`perl -e 'alarm shift; exec @ARGV' 15 ./bin`).

Until then, TSAN results on macOS are usable only from runs that exit; a wedged run says
nothing about March.
