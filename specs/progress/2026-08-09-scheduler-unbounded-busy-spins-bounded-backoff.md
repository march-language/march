# Fixed: scheduler unbounded busy-spins now back off instead of pegging a core (2026-08-09)

Filed 2026-07-23 as `[P1]` — the actor scheduler had unbounded busy-spins that
could peg a core at ~100% CPU under heavy host oversubscription (several
concurrent `march` processes on one box, each spawning ~`nproc` scheduler OS
threads). Never live-confirmed (~160 repro attempts all completed cleanly), but
the structural hazard was real: a stalled spin adds CPU pressure that worsens
the very starvation that caused it.

All three spin sites now bound their busy phase with a fixed spin grace, then
fall back to a 1 ms `nanosleep`, preserving wait-forever semantics (no timeout,
no changed contract) and staying migration-safe (the spin counter is a
stack-local `int64_t`, never a TLS read across a yield):

- `march_sched_wake`'s `PROC_PARKED` wait (`runtime/march_scheduler.c`) —
  `SCHED_WAKE_SPIN_GRACE` (4096) then backoff.
- `task_wait_done`'s in-scheduler branch (`runtime/march_runtime.c`, what
  `task_await`/`task_await_unwrap` call) — `CLOCK_MONOTONIC` grace period then
  `nanosleep`, mirroring `Actor.call`'s already-bounded timed-wait path.
- `march_sched_wait_idle` (`runtime/march_scheduler.c`) — the site the original
  repro (`erasedoptbin`) never reached, fixed here for completeness:
  `WAIT_IDLE_SPIN_GRACE` (4096) then a 1 ms `nanosleep`. This is the change
  landed on this branch; the other two were bounded in earlier work.

Scheduler unit tests pass (`run_codegen` scheduler group; standalone C
scheduler tests 10/0 and 3/0). See memory `project_scheduler_unbounded_spin_hangs`
for the original investigation and reproduction recipe.
