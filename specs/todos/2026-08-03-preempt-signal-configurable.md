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
