# `[P3]` `MARCH_SANITIZE=thread` binaries on macOS wedge with 2+ schedulers (no TSAN report) — FIXED

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

## Fixed 2026-10-11: TSAN deadlocked on itself, re-entered through the preemption handler

**Not a lost proc.** An in-process watchdog (a `DYLD_INSERT_LIBRARIES` dylib that, after N
seconds, `thread_suspend`s its own threads and walks each frame-pointer chain; no debugger
attach) caught a wedge. One green thread was deadlocked inside TSAN. Every other thread
was blocked in TSAN's `SlotLock` / `TraceSwitchPart`, waiting on the lock that thread held:

```
Player_Ball -> march_record_set_shape            (a racy write: TSAN report #1)
  ReportRace -> OutputReport -> SymbolizeStack   (holds the report mutex + all slots)
    DlAddrSymbolizer -> DemangleSwiftAndCXX      (in-process fallback: deep stack)
      SIGBUS on the green stack's lazy-growth guard page
        march_sigsegv_handler -> mprotect        (TSAN interceptor)
          ~ScopedInterceptor -> ProcessPendingSignals   (a deferred SIGUSR1 tick)
            march_preempt_signal_handler          (a racy write: TSAN report #2)
              ReportRace -> ScopedReportBase      (waits on the report mutex it holds)
```

What it takes:

1. **A TSAN report on a green thread.** The base runtime raised them all the time:
   `march_preempt_signal_handler` wrote `march_preempt_request` with a plain store that
   races with `march_yield_from_compiled`'s clear on another thread, TSAN found errno
   changed across the handler ("signal handler spoils errno"),
   `march_record_set_shape`'s memo `*cache` was a plain racy read and write, and the
   first `sched_loop`s raced to write `g_sched_sigmask`.
2. **Symbolization that runs on the green stack.** When `atos` works (it needs the task
   port), symbolization is out of process and shallow, and the report prints. When it
   cannot start, TSAN falls back to `dladdr` + the demangler on the 4 KiB-initial green
   stack, which faults into March's lazy stack growth. The earlier measurements were taken
   where `atos` could not start. The "TSAN prints nothing" symptom is this case: the
   wedge happens while the first report is still being symbolized.
3. **A report-raising preemption handler.** TSAN defers async signals and delivers them on
   interceptor exit, here `mprotect`'s exit inside the fault handler, nested inside the
   first report. A handler that reports again deadlocks.

That explains all the evidence: TSAN only (the reports are the trigger), any `-O` level
and no `MARCH_DEBUG` tripwire (nothing in March's queues is wrong), roughly proportional to
how often a program raised a report, and none at 1 scheduler (no cross-thread
`march_preempt_request` race).

**Fix (runtime only, no codegen change):**
- `march_preempt_request`: every C-side write goes through `MARCH_PREEMPT_REQUEST_SET`
  (runtime/march_scheduler.h), a relaxed `__atomic_store_n`, at the handler, the yield
  clear, `march_sched_stop_epoch` and the shell's `cancel_task`.
  It is the same `str` on arm64. Compiled code's `load volatile` is unchanged.
- `march_preempt_signal_handler` saves and restores `errno` around its body
  (`preempt_signal_handler_body`), as every async handler should.
- `march_record_set_shape`: the memo is read and written with relaxed atomics.
- `sched_loop`: the scheduler signal mask is recorded by the one scheduler that wins a CAS
  on `g_sched_sigmask_claim`.

With the handler report-free, a deferred tick delivered inside a report cannot nest a
second one, and with the runtime's own races gone, the test programs raise no report at
all. A user program with a real race still gets its report (and, when `atos` cannot
start, it is symbolized in-process without deadlocking).

**Darwin-specific?** The deadlock path is generic TSAN behaviour (deferred signals run on
interceptor exit, even inside a report), but it needs in-process symbolization on the
green stack. See the Linux results below.

**Regression loop (not in the default suite):** `scripts/tsan-wedge-loop.sh [RUNS]`
compiles the 1000-ball ping-pong under `MARCH_SANITIZE=thread` and runs it at 2 schedulers
(on macOS, in a sandbox with no task port, so `atos` cannot start). It fails on any wedge
or any TSAN report.

**Measured (macOS 26, M3, Homebrew LLVM 22.1.8).** "Sandboxed" = `sandbox-exec -p
'(version 1)(allow default)(deny mach-priv-task-port)'`, so `atos` cannot start (exit 142
= SIGALRM deadline = wedged):

| program | scheds | base wedged | fixed wedged | fixed runs with a TSAN report |
|---|---|---|---|---|
| ping-pong `n = 1000`, sandboxed | 2 | 12/20 (most print nothing) | 0/20 | 0/20 |
| `run_until_idle_ping_pong`, sandboxed | 14 | 1/6 (5 others aborted on ~100 reports each) | 0/6 | 0/6 |
| `actor_monitor_down_reason`, sandboxed | 4 | 2/11 | 0/11 | 0/11 |
| `actor_counter`, sandboxed | 14 | 0/15 | 0/15 | 0/15 |
| ping-pong `n = 1000`, not sandboxed | 2 | 0/~40 (but 2-16 reports in most runs) | 0/10 | 0/10 |

The same base binaries with `TSAN_OPTIONS=symbolize=0`, sandboxed: 0/13 wedged, which
confirms that the wedge needs in-process symbolization. `scripts/tsan-wedge-loop.sh 8`
against the base runtime (`MARCH_RUNTIME_DIR`): 5/8 wedged, exit 1. Against the fix: 0/10,
exit 0.

**Linux (Docker `march-ci-ubuntu-step6b`, Ubuntu clang 18 TSAN).** The base runtime
raises the same three handler reports (`march_preempt_signal_handler` write, errno
spoiling, `march_yield_from_compiled` clear) in 18/20 runs at 2 schedulers and 5/5 at 14,
but never wedges (0/25): its symbolizer runs out of process. The fix: 0 reports, 0 wedges
(0/25). So the races were portable and the deadlock was Darwin-specific: Darwin's
in-process `dladdr` + demangle fallback runs on the 4 KiB green stack. No 1-scheduler
default is needed under `MARCH_SANITIZE=thread`.

**Plain builds:** `--opt 2`, 11 interleaved runs, base runtime vs fix, load ~13. Median
`list_ops` 62 vs 66 ms, `binary_trees` 84 vs 83 ms. That is noise: a relaxed atomic load
or store is the same `ldr`/`str` as the plain access.
