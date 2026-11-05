`[P3]` Dedicated schedulers: pin any actor or task to an OS thread it does not share

Filed 2026-11-04 from a value-proposition discussion about game servers (persistent
worlds, zone simulations), where a tick loop needs a predictable OS thread to itself.

## What exists

Main-thread pinning, built for cube_forge's GLFW/Cocoa requirement (cube_forge
`GAPS.md` G15):

- `specs/progress/2026-09-03-pin-main-green-thread-to-scheduler-0.md`: a `pinned`
  field on `march_proc` and a scheduler-0-only FIFO, the "pin queue"
  (`pin_runq_push`/`pin_runq_pop`, `runtime/march_scheduler.c`). Only scheduler 0,
  the thread that called `march_sched_run`, pops it.
- `specs/progress/2026-09-17-pin-main-compiler-switch.md`: `march --pin-main`
  (`march_spawn_main_pinned`); `MARCH_PIN_MAIN=1` can still turn it on.
- `specs/progress/2026-09-22-forge-pin-main.md`: `forge.toml` `[package] pin_main = true`.

## Why that is not enough for a simulation thread

1. **Only `main` can be pinned.** `march_sched_spawn_pinned` has no March-level
   surface, so a program cannot spawn a simulation actor and pin it.
2. **Pinning is affinity, not exclusivity.** `sched_loop` on scheduler 0 still pops
   the global runq first, then its own deque, and steals from other schedulers
   (`runtime/march_scheduler.c`, the dequeue block after `global_runq_pop`). Any green
   thread can land on the pinned proc's OS thread and delay its tick.
3. **There is one target, scheduler 0.** Several zones cannot each have a core.
4. **Preemption still applies.** The preemption daemon signals scheduler 0 like any
   worker (`g_scheds[0].thread = pthread_self()` "so the preemption daemon can send
   SIGUSR1 to it"), and `march_sched_tick`'s reduction budget yields cooperatively.
   On a thread with one proc that is wasted work and jitter.
5. **No OS CPU affinity** (`pthread_setaffinity_np` on Linux; macOS has only
   affinity tags, `THREAD_AFFINITY_POLICY`, which are hints).

## Shape to design

- **One pin queue per scheduler** instead of scheduler 0's alone. Every enqueue point
  that routes a pinned proc today (spawn, yield re-push, `march_sched_wake`, the
  deque-overflow path) routes to its owner's queue.
- **A March-level spawn**, e.g. `Actor.spawn_pinned` / `Task.spawn_pinned` or a spawn
  option, returning the usual handle. Message passing to and from it is unchanged.
- **Exclusive schedulers**: a scheduler reserved for pinned procs, which never pops
  the global runq, is never stolen from and never steals, and is skipped by the
  preemption daemon and the reduction budget. Configured by count, e.g.
  `forge.toml` `[runtime] dedicated_schedulers = N` and a `MARCH_DEDICATED_SCHEDULERS`
  override, taken from the worker pool or added on top of it (decide).
- **Optional CPU affinity** for exclusive schedulers on Linux, best-effort on macOS.
- **What happens when the pinned proc parks** (waits on `receive`): the thread idles
  rather than taking other work. Decide between a spin-then-sleep wait and a plain
  condition-variable sleep, and measure the wake latency of each.

Open questions: interaction with hot code reload (a pinned actor's epoch drain, and
whether a reload may move it), with `forge observe`/`forge top` (show the pin and the
owning scheduler), and with a pinned proc that dies or is restarted by a supervisor
(the restart must be pinned to the same scheduler).

## Done when

A program can spawn an actor onto a dedicated scheduler, the actor's thread runs
nothing else (checked by a test that floods the other schedulers and asserts the
pinned actor's thread id and an empty steal count), its tick-time jitter is measured
against an unpinned actor under the same load, and the reference docs
(`specs/lang/` actors chapter, `docs/tooling.md` for the `forge.toml` key) describe it.

Related: `2026-11-04-alloc-bound-contract.md` (a bounded-allocation tick is the
other half of a predictable frame), and the missing UDP support (no todo yet).
