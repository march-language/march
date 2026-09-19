# DONE 2026-09-19 — flake: `test/apps/actor_stress` output order

**Symptom.** macOS `test` job, PR #524 (run 35458723472): `native_actor_stress`
printed the Stack actor's last two replies (`stack.size=0`, `stack.top=42`)
after `=== tasks: basic === … collected count=5 total=55`, not before
`counter=11`.

**Cause.** The golden pinned the scheduler's drain order, not the source order.
Every section's `send`s were fire-and-forget, and nothing waited for them, so
all the section headers printed first and every actor's output came after,
in whatever order the run queue drained. The file header called that order
deterministic under `MARCH_NUM_SCHEDULERS=1`, but it isn't: the preempt
daemon zeroes the running green thread's reductions every `MARCH_QUANTUM_US`
(1 ms), so an actor can be cut off partway through its mailbox and requeued
behind the other actors and the main thread. Wall-clock time decides where
that cut lands. Under CPU load, the old binary missed its golden in 35 of
300 runs locally (12 spinning processes, `MARCH_NUM_SCHEDULERS=1`).

**Fix (test only).** Each actor section now ends with `run_until_idle()`,
which in compiled code parks main until no process is runnable and every
mailbox is empty (`march_sched_wait_idle`). Each section's output now prints
under its own header. "many counters" still interleaves its sends across three
actors, but it drains after each `Print` so the three replies come out in a
fixed order. The stress is unchanged: every send is still fire-and-forget,
FIFO order within a mailbox still decides every printed value, and `receive()`
inside a handler still finds `Answer` already queued, because the drain comes
after both sends. The golden is regenerated.

**Verified.** Under the same load, 0/300 failures with `MARCH_NUM_SCHEDULERS=1`
and 0/100 at the default scheduler count.
