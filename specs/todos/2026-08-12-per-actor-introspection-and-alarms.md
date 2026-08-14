`[P2]` # Observability is aggregate-only: no process enumeration, no slow-mailbox alarm

## The gap

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
