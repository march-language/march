# Startup getenv racing `main`'s Process.set_env (SIGSEGV in getenv)

**Date:** 2026-10-05

## Symptom

Two-node `cert_*` scenarios on the Linux CI leg died, rarely, before their
first line of output:

```
march: fatal SIGSEGV si_code=1 addr=0x460 pc=0x7f...48806 sched=-1 pid=-1 (no green thread running on this scheduler)
```

It hit `cert_initiate_denied` (node-a, PR #784's run 37248874352) and
`cert_raw_send_denied` (node-b, PR #777's run 37221514272). The last 300
failed CI runs show it at least twice before that, in `cert_expired`
(2026-10-02) and `cert_wrong_operator` (2026-10-01). Every hit is a `cert_*`
scenario, and every one of those calls `Process.set_env` first thing in
`main`. It is an old flake: no PR caused it, and each run just lost the race.

## Root cause

`pc` is `getenv+0x56` in Ubuntu 24.04's glibc 2.39 (`cmp (%rbx),%r13b`, the
read of an `environ` entry). The faulting thread is not a scheduler thread.

`march_sched_run` creates the worker threads first and only then calls
`march_sched_preempt_start`, whose first act is `march_preempt_signal()`, a
`getenv("MARCH_PREEMPT_SIGNAL")` (cached after the first call). An unpinned
`main` can be stolen and run by a worker as soon as that worker exists. Every
crashing node calls `Process.set_env` six times at the top of `main`. `setenv`
reallocs `environ` and frees the old array, so the main OS thread's getenv,
still in `preempt_start`, walked a freed array.

A second, rarer path had the same shape. `march_run_scheduler` starts the observe
socket (`getenv` x2) on the main OS thread. When a background scheduler is
already running (`march_ensure_sched_started`), `main` is already executing at
that point.

## Fix

- `march_sched_run` resolves the preemption signal before it creates any
  worker (`runtime/march_scheduler.c`).
- `spawn_main_impl` starts the observe socket before `main` is spawned
  (`runtime/march_runtime.c`). `march_run_scheduler` keeps its call for hosts
  that never call `march_spawn_main`. Both calls run only once.

## Evidence

The repro runs in a Linux arm64 container (glibc 2.39). The program is `main`
calling `Process.set_env` 400 times with distinct names, then `println("ok")`.
The binary ran `MARCH_NUM_SCHEDULERS=8`, once per run:

| runtime                    | crashed runs |
|----------------------------|--------------|
| before the fix (run 1)     | 22 / 1000    |
| before the fix (run 2)     | 68 / 1000    |
| preempt-signal fix only    | 0 / 1000     |
| both fixes                 | 0 / 2000     |

Every crash before the fix had the CI signature: `sched=-1` and `pc` at
`getenv`'s environ-entry load (`ldrb w1, [x19]`, getenv+0x4c on arm64).

## Not fixed (inherent to setenv)

`setenv` is not thread-safe against any concurrent `getenv`, so a program
that calls `Process.set_env` while other threads read the environment can
still race. Those readers include another green thread's `Process.env`, the
`getaddrinfo` helper thread (`resolve_thread`), and libc internals. This fix
only removes the reads the runtime itself made at startup, concurrently with
`main`'s first lines.
