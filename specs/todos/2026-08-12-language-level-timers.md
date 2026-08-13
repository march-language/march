`[P2]` # No `send_after` / `cancel_timer`: the timer heap exists but isn't exposed

## The gap

March has no way to schedule a message. There is no `send_after`,
`cancel_timer`, or `Process.sleep`. An actor that wants to poll, retry, time
something out, or tick has to burn a task green thread in a yield loop.

## Why this is the cheapest item on the list

The hard part is already built and shipped. The 2026-08-12 hardening (Task 2)
added a real timer subsystem to the scheduler:

- a mutex-guarded binary min-heap of `(deadline_ms, proc, park_gen)`
  (`runtime/march_scheduler.c`), serviced every `MARCH_QUANTUM_US` from the
  preemption daemon;
- `march_sched_park_self_until(deadline_ms)` and `march_now_ms()`;
- lazy cancellation via `park_gen`, so a woken-early proc's stale entry is
  skipped rather than firing (added in Task 16's review round).

That machinery is entirely runtime-internal: it backs `Actor.call` deadlines and
supervisor restart backoff. Nothing surfaces it to March.

## Sketch

`send_after(pid, msg, delay_ms) : TimerRef` — enqueue into the same heap with a
payload variant that performs a `march_sched_send` on fire, instead of only
waking a parked proc. `cancel_timer(ref)` can reuse the `park_gen` trick
(bump a generation, let the stale entry fire into nothing) rather than needing
real heap removal.

Two things to decide:

1. **Ownership/RC of the pending message.** The heap would hold a March value
   between now and the deadline — it needs a reference, and a cancelled or
   dead-target timer must dispose it. The `march_sched_set_msg_dtor` hook added
   in Task 14 is exactly the disposal channel to reuse.
2. **Timer entries pin their target proc.** Procs are leak-don't-free, so a
   long timer cannot dangle — but a long timer *does* keep the scheduler from
   going idle, which now matters because `march_sched_wait_idle` counts live
   timer entries as busy (Task 16). A one-hour `send_after` would keep
   `run_until_idle()` from returning. Decide whether scheduled sends count as
   "work pending" (they do for a server; they probably should not for
   `run_until_idle` in a test).

## Acceptance

`send_after` delivers after the delay and not before; `cancel_timer` before the
deadline delivers nothing and leaks nothing; a cancelled or dead-target timer's
message is disposed through the registered dtor.
