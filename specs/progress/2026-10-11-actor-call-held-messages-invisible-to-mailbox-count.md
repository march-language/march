`[P3]` **An actor waiting in `Actor.call` hides the messages it holds from every mailbox count.**

Found 2026-10-02 while building the observe R1 test
([`progress/2026-10-02-observe-r1-snapshot-verbs.md`](../progress/2026-10-02-observe-r1-snapshot-verbs.md)).

An actor whose handler calls `Actor.call(other, Req, timeout)` takes every
message that arrives while it waits off its mailbox and holds it aside, putting
it back after the reply (the `last_recv_epoch` machinery in
`runtime/march_scheduler.h`). While it waits, `mailbox_size(pid)`,
`Actor.top_by_mailbox`, `Actor.over_mailbox` and the observe socket's
`ACTORS`/`MEM` all report those messages as gone: 500 messages sent to an actor
blocked in a call showed `mbox: 0`.

That is exactly the actor an operator is looking for (stuck in a slow call with
work piling up), and R3's planned `forge diagnose` mailbox-growth check would
miss it.

**Update (observe R2, 2026-10-02):** the observe socket side is done. The proc
now carries `held` (set by `call_held_push`, cleared by `call_held_restore`);
`ACTORS`/`ACTOR` rows report it, `ACTORS mbox` and `TOP mbox` rank by queued +
held, and `MEM` counts it (`test/native/observe_counters.march`). What is
left is the March-level API: `mailbox_size(pid)`, `Actor.top_by_mailbox` and
`Actor.over_mailbox` still read `mbox_count` alone. Whether `mailbox_size`
should include held messages is a semantic choice (it is also what fixtures
spin on while waiting for a message to land), so it is left open here.

Original fix shape: keep a count of held messages on the proc (written by the caller's
own thread, so a relaxed atomic store), add it to `mbox_count` reads that mean
"work queued for this actor", and expose `held` separately in the observe row.
Test: the R1 fixture's `Hot` actor stalled in an `Actor.call` instead of
`sleep_ms`, asserting `user_mbox + held = 500`.

## Done 2026-10-11: the March-level API

New builtin `mailbox_backlog(pid) : Int`. It returns `mailbox_size(pid)` plus
the proc's `held`, read through a new `march_sched_held_count` accessor
(`march_mailbox_backlog` in `runtime/march_runtime.c`). `Actor.top_by_mailbox`
and `Actor.over_mailbox` rank by it, matching the observe socket's
`ACTORS mbox` / `TOP mbox`.

`mailbox_size` is unchanged, as the open semantic question suggested: it
stays the queue depth that fixtures spin on while waiting for a message to
land. The interpreter's `Actor.call` sets nothing aside, so there the two
builtins agree.

Test: `test/native/mailbox_backlog_counts_held.march`. It is the observe
fixture's `Caller` shape: blocked in an `Actor.call` nobody answers while 150
messages arrive. `mailbox_size` reads 0, `mailbox_backlog` reads 150, and both
Actor functions report the caller at depth 150. Before this change,
`over_mailbox(c, 100)` did not list the caller at all.
