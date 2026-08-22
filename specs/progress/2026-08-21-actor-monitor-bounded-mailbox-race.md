# `actor_monitor_down_reason`'s `PrimeBounded` case was racy at >1 scheduler

Filed 2026-08-20 (as `specs/todos/2026-08-20-actor-monitor-bounded-mailbox-race.md`
on the `test/multi-scheduler-fixture-coverage` branch, PR #319); fixed
2026-08-21. **Coordination note:** PR #319 was still unmerged when this landed,
so the fix here touches only the fixture, not `test/dune`'s monitor rules —
#319 owns those. When #319 merges, delete its now-resolved
`specs/todos/2026-08-20-actor-monitor-bounded-mailbox-race.md`; this file
supersedes it.

## The flake

`test/dune` runs `native_actor_monitor_down_reason` 100 times at
`MARCH_NUM_SCHEDULERS=4`. Roughly 0.1% of runs died with

```
panic: bounded Down or mailbox count mismatch
```

— about a 7% chance of reddening the 100-iteration loop, which is what made it
show up on unrelated PRs.

## Root cause

`main` sets the case up as:

```march
Actor.set_queue_limit(watcher, 1, 1)   -- limit 1, drop_new
monitor(watcher, killed)
send(watcher, PrimeBounded(killed, watcher))
kill(killed)                           -- THIS is what enqueues the Down
```

`kill` enqueues the `Down` synchronously on the caller's thread —
`march_kill` → `do_actor_death` → `deliver_monitor_down` → `march_sched_send_control`
(`runtime/march_runtime.c`) — but it runs *after* the `send`. The handler
samples `mailbox_size(watcher)` at entry and requires 1.

At `MARCH_NUM_SCHEDULERS=1` main cannot yield between the `send` and the `kill`,
so both messages are queued before the watcher is ever dispatched, and the
sample is deterministically 1. At >1 another scheduler thread can pick the
watcher up the instant the `send` lands, sample `mailbox_size` as 0, block in
`receive()` until the `Down` finally arrives, and then fail the `queued == 1`
check.

## Fix

Option 2 from the original todo: the handler now waits for the `Down` with the
fixture's existing `wait_for_queued_message(watcher)` helper before sampling.
At one scheduler the `Down` is already queued, so it returns immediately and the
golden's behaviour is bit-for-bit unchanged.

**The todo's preferred option 1 — reorder `kill(killed)` ahead of the `send` —
was rejected as strictly weaker, and the fixture now carries a comment saying
so.** The mailbox bound counts only USER messages (`mbox_user_count`,
`runtime/march_scheduler.c:2077`), and the `Down` goes out on the separate
`march_sched_send_control` path. The entire point of `set_queue_limit(watcher,
1, 1)` here is that the `Down` arrives *while `PrimeBounded` already occupies
the one user slot*, so a regression making the control path consult
`mbox_count` instead of `mbox_user_count` would drop it. Put the `Down` first
and it is enqueued while `user_count` is 0, never meets the bound at all, and
that regression passes the test. The original ordering is load-bearing; only
the handler's sampling point was wrong.

## Measured

Both binaries built once and run interleaved (6 workers x 2000 each arm,
concurrently, so contention is shared), `MARCH_NUM_SCHEDULERS=4`:

| Arm | Total | `panic: bounded Down…` | `rc=137` (host SIGKILL) |
|---|---|---|---|
| before | 15/12000 | **13** | 2 |
| after  | 1/12000  | **0**  | 1 |

Load average 21.55. An earlier non-interleaved baseline on the same binary gave
9 panics + 1 SIGKILL per 12000 at load 21.70, so the pre-fix panic rate is
22/24000 (~0.09%) across 24000 measured runs. Seeing 0 panics in 12000 if the
rate were unchanged has probability ~2e-6.

The surviving `rc=137` appears in **both** arms and carries the complete,
correct five-line output — it is the separate host-level SIGKILL phenomenon the
original todo already warned not to confuse with this bug (also reproduced at
1/6000 against an unrelated signal fixture during this session). It is not
addressed here and remains a host-environment question.
