`[P2]` # Observability: no slow-mailbox alarm, no state inspection, no tracing

> **Process enumeration landed 2026-09-08** — `Actor.list()` (builtin
> `actor_pid_indices`) walks every live actor lock-free, and
> `docs/overload-resilience.md` now shows it closing the shedding loop. See
> `specs/progress/2026-09-08-process-enumeration.md`. This file is trimmed to
> the three pieces that did NOT land.

## What remains

- **A growing-mailbox alarm.** BEAM's `erlang:system_monitor` has a
  `long_message_queue` trigger that tells you *when* a process crosses a
  threshold. Ours must still be polled. Enumeration makes polling possible, so
  the loop is no longer broken — but a threshold callback is strictly better
  than a timer, and it is the shape `Scheduler.top_by_mailbox(n)` (see the
  sketch below) was suggested for: doing the walk inside the runtime and
  returning only the worst N, rather than materialising every actor.
- **Per-actor state inspection.** No equivalent of `sys:get_state/1`.
  `get_actor_field` exists but needs a Pid and a field index.
- **Tracing.** No `erlang:trace` equivalent — no way to watch one actor's
  message flow without editing the program.

## The original gap, for context

The 2026-08-12 hardening added the counters (`Scheduler.live_procs`,
`total_spawned`, `runq_depth`, `dropped_messages`) and fixed compiled
`mailbox_size` to report real queue depth. That answers *"is the system
behind?"* — it cannot answer **"which actor is behind?"**, which is the
question you actually have at 3am.

Specifically missing:

- **Process enumeration.** There is no way to list live actors from March. You
  can only call `mailbox_size(pid)` on a Pid you already hold, so finding the
  hot actor requires already knowing which one it is.
- **Per-actor state inspection.** No equivalent of `sys:get_state/1`.
  `get_actor_field` exists but needs a Pid and a field index.
- **A growing-mailbox alarm.** BEAM's `erlang:system_monitor` has a
  `long_message_queue` trigger that tells you *when* a process crosses a
  threshold. Ours must be polled, and polling requires enumeration (above), so
  the loop cannot currently be closed at all.
- **Tracing.** No `erlang:trace` equivalent — no way to watch one actor's
  message flow without editing the program.

## Why it matters now specifically

The whole point of the bounded-mailbox work is deciding *when to shed*, and
`docs/overload-resilience.md` tells readers to poll `Scheduler` counters and
`mailbox_size` to make that decision. For a real service that guidance is
incomplete: the counters are global, and `mailbox_size` needs a Pid the
monitoring code has no way to obtain. The shedding story needs the enumeration
to be genuinely actionable.

## Sketch

The runtime already holds everything needed. `g_actor_tbl` (256 buckets, keyed
by actor pointer) and the growable proc registry (Task 13) between them know
every live actor, and `march_sched_mbox_count` gives depth. What's missing is a
March-visible walk.

Design questions: a snapshot list of Pids is racy by nature (an actor can die
between enumeration and inspection) — probably fine, since every consumer
already handles a dead Pid. A `Scheduler.top_by_mailbox(n)` that does the walk
*inside* the runtime and returns only the worst N avoids materialising a list
of every actor and is the more useful shape for the alarm case.

Watch the lock discipline: enumeration walks the same structures the send path
touches, and Task 10 deliberately took `find_meta` off `g_tbl_mu` to keep sends
lock-free. An enumeration that takes that mutex on a monitoring timer would
re-serialise the very path that work freed. Use the same lock-free
bucket-head walk.

## Acceptance

A monitoring loop written in March can identify the deepest-mailbox actors
without holding their Pids in advance, and does not measurably slow the send
path while doing it.
