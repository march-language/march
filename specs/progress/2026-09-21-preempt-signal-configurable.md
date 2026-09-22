# DONE 2026-09-21: the preemption signal is configurable, chains to the host's handler, and is restored

All four steps of the original todo (below), with one deliberate deviation on
step 1's default.

## What changed (`runtime/march_scheduler.c` unless noted)

1. **Selection.** `march_preempt_signal()` resolves once: `$MARCH_PREEMPT_SIGNAL`
   (`USR1`, `USR2`, Linux `RTMIN`/`RTMIN+<n>`, optional `SIG` prefix, or a
   number), else SIGUSR1; an unusable value warns and falls back.
   `march_sched_set_preempt_signal(signo)` is the embedder entry point (refused
   once preemption is running, or for anything but USR1/USR2/RT signals).
   Every hardcoded site now asks for it: the daemon's `pthread_kill`,
   `march_block_preempt` (`runtime/march_preempt.h`, used by the HTTP/TLS
   blocking calls), the `getaddrinfo` mask, and preempt_stop's daemon wake.
   **Default stays SIGUSR1 on Linux too**, contrary to the todo's "prefer
   SIGRTMIN": real-time signals queue instead of coalescing, so every ~1ms tick
   to a thread that has the signal masked (march_block_preempt around a slow
   syscall) adds a queued delivery against the user's RLIMIT_SIGPENDING, which
   is shared with every other process of that user. RT signals are available
   by choice.
2. **Chaining.** The handler (now `SA_SIGINFO`, still `SA_RESTART|SA_ONSTACK`)
   decides "ours" without touching TLS first (a host's process-directed signal
   can land on a thread March never initialised, and first TLS access on
   Darwin mallocs): it finds its thread in `g_scheds` by `pthread_self()` and
   consumes that scheduler's new `preempt_tick` flag, which the daemon sets
   (release) just before signalling. Anything else is passed to the saved
   previous disposition, if that was a real handler; a previous `SIG_DFL`
   (terminate, for SIGUSR1) or `SIG_IGN` is not called, so a standalone
   program ignores stray SIGUSR1 as before.
   A delivery from another process (`si_pid > 0 && != getpid()`) is chained
   BEFORE the flag is consulted and without consuming it. Two things were
   found while testing this, both measured:
   - macOS delivers many of our own `pthread_kill` ticks with `si_pid == 0`
     under this scheduler (~250 of ~650 in a 400 ms run), so "!= getpid()"
     alone chained our ticks to the host; the check is `si_pid > 0`.
   - consuming the flag while handling an external signal let a host signal
     that landed between the daemon's flag store and its tick eat the flag,
     and the tick itself was then chained (2 of 30 runs). External
     deliveries no longer touch the flag.
   - "store flag, then kill" is itself racy under load: a late handler for
     tick N can run between the daemon's flag store for N+1 and its kill, and
     consume N+1's flag, so N+1's delivery is chained to the host. The full
     Linux `dune runtest` caught it. The daemon now signals only on the
     flag's 0 -> 1 transition (a kill while it is 1 would have coalesced
     anyway), so each kill pairs with exactly one consumption; flags are reset
     at preempt_start. Measured with 8 concurrent copies of the test:
     Docker ubuntu aarch64 old 62/80 runs failed, new 0/80; macOS old 19/48,
     new 0/48.
3. **Restore.** `march_sched_preempt_stop` puts the saved disposition back
   (it used to leave March's handler installed forever). Before restoring it
   masks the signal and consumes one pending delivery, so a tick cannot be
   delivered under a restored `SIG_DFL`. That drain is defensive: no test
   reaches it (swapcontext restores the scheduler's unblocked mask, and a tick
   sent before the daemon is joined is delivered on the join's return; a test
   that masked the signal inside a green thread stayed green with the drain
   removed).
4. **Reserved-signal diagnostic** (`runtime/march_runtime.c`): `Signal.watch`
   refuses the code of whichever signal is in use (Usr1 by default; Usr2 if
   moved there; none for an RT signal) and names it.

Docs: `specs/lang/parallelism.md` and `docs/parallelism.md` gained "The
preemption signal".

## Verification

`test/test_preempt_signal.c` (`test_preempt_signal_runner`, runtest; scheduler
only, pinned at 2 schedulers; every case in its own forked child; the "host"
signals come from a separate process so the assertions are exact):

- host_handler_chained: a host SIGUSR1 handler receives the other process's
  deliveries (20 sent, 19-20 received), receives none of March's ticks,
  preemption still fires (~650 ticks), and the handler is restored.
- default_disposition_survives_stop: 20 start/stop rounds at SIG_DFL, SIG_DFL
  restored, process alive.
- env_moves_signal (USR2: SIGUSR1 untouched for the whole run, preemption
  fires), env_rt_signal (Linux, RTMIN+1), bad_env_falls_back,
  api_rejects_bad_signal.

| where | fix | red control (no chaining, no restore) |
|---|---|---|
| macOS arm64, 10 runs + 40 runs of case 1 + 48 under 8x concurrency | all pass | host_handler_chained and default_disposition FAIL |
| Docker ubuntu aarch64, 10 runs + 80 under 8x concurrency | all 6 pass (incl. RT) | same two FAIL |

**Inside a live BEAM** (OTP 29, erts-17.0.6, macOS arm64): a dirty NIF that
links the scheduler and runs two green threads for 300 ms, reading the BEAM's
SIGUSR1 handler address before, during and after:

| scheduler | before | during | after | restored |
|---|---|---|---|---|
| origin/main | 0x104872A80 | 0x1124A178C | 0x1124A178C | no |
| this change | 0x10048AA80 | 0x10E159D1C | 0x10048AA80 | yes |
| this change, `MARCH_PREEMPT_SIGNAL=USR2` | 0x100D9AA80 | 0x100D9AA80 | 0x100D9AA80 | untouched |

(~490 preemption ticks observed in each.) The BEAM's crash dump on a real
`kill -USR1` was not triggered on purpose: it halts the VM. Not re-run as the
full March-compiled NIF from the spike; this NIF links the same scheduler
source the compiled .so does.

---

## Original todo (filed 2026-08-03)

# Make the green-thread preemption signal configurable (SIGUSR1 collides with host VMs)

Filed 2026-08-03, out of the March-as-Elixir-NIF spike
(`specs/2026-08-02-nif-feasibility-assessment.md`).

## Problem

`march_sched_preempt_start` (`runtime/march_scheduler.c:1530`) installs a process-wide
SIGUSR1 handler for green-thread preemption, and SIGUSR1 is hardcoded as reserved
throughout the runtime (`runtime/march_runtime.c:4659` refuses to let user code watch it).

That is fine for a March binary that owns its process. It is wrong when March is loaded
into a host process it does not own — a NIF, or any C-ABI embedding, which is the entire
phase 6 wedge. Measured inside a live BEAM (OTP 29, macOS arm64):

```
SIGUSR1 handler BEFORE March: 0x100F0E7D0    (the BEAM's own)
SIGUSR1 handler AFTER  March: 0x10EEDB7B4    (March's, after one Task.async)
```

**SIGUSR1 is the BEAM's crash-dump trigger.** After the first March green thread spawns,
`kill -USR1 <beam>` silently runs March's preemption handler instead of writing
`erl_crash.dump`. Symmetrically, a host that re-installs its handler later silently
disables March preemption. Nothing crashes; a facility just disappears.

Any embedding host with its own SIGUSR1 use has the same collision — this is not
BEAM-specific.

## Fix

1. Select the preemption signal at scheduler init instead of hardcoding: an env var
   (`MARCH_PREEMPT_SIGNAL`) and/or an explicit init entry point for embedders. On Linux
   prefer a real-time signal (`SIGRTMIN`-range), which exists precisely so libraries do
   not fight over SIGUSR1/2.
2. Save the previous `sigaction` and **chain to it** for deliveries that are not ours, so
   a host's handler keeps working rather than being replaced.
3. Restore the previous handler in `march_sched_preempt_stop`.
4. Keep the reserved-signal diagnostic in sync — it must name whichever signal is actually
   in use, not always SIGUSR1.

## Verification

- A test that installs a sentinel SIGUSR1 handler, runs March green threads, and asserts
  the sentinel still runs (currently it would not).
- Re-run the NIF spike and confirm the handler address is unchanged across a March call.
- Linux needs its own run: the handler already carries a Linux-specific
  `SA_RESTART|SA_ONSTACK` fix (see `specs/progress/` scheduler notes), so signal-choice
  changes must be re-validated there rather than assumed from macOS.
