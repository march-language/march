# `[P2]` After a deploy, a process whose actor is parked in a nested `receive()` never exits

Filed 2026-09-24 by the distributed-deploys review (step 6, PR #612, commit
1157997f5). Plan: II.4.6; progress deviation 13.

## Defect

Markers stay queued until the actor loop reaches them, and a nested
`receive()` cannot consume them (deviation 13). But the scheduler still counts
a queued marker as deliverable work:

- `mbox_waiting_has_deliverable` (`runtime/march_scheduler.c:1153-1157`)
  tests `mbox_count > 0` for any wait mode other than 2, and markers are
  counted in `mbox_count`.
- `wake_idle_daemons` (`:1731-1747`), the shutdown endgame, skips a WAITING
  daemon that "has deliverable" mail, so it never gets `request_stop`. Every
  actor is a daemon.
- `march_sched_wait_idle` (`:2381-2410`) treats the same proc as busy, so
  `run_until_idle` never returns.

So once any deploy has run, an actor blocked in a nested `receive()` holds its
marker for ever. At exit the process spins in the 1 ms idle loop instead of
exiting. Before step 6 the same actor, with an empty mailbox, was stopped and
the process exited.

## Confirmed

C harness against the real runtime: one actor whose handler calls
`march_actor_recv()` and blocks. `main` returns either directly (control) or
after one `march_hcr_activate`. `alarm(10)` turns a hang into exit status 142.
Three runs each:

```
run1 control=0 deploy=142
run2 control=0 deploy=142
run3 control=0 deploy=142
```

The source is in the review session's scratchpad
(`m1/repro_marker_exit_hang.c`), built with the `cc` line of
`test/dune`'s `test_hcr_migrate_order_runner` rule.

## Fix I would make

Count user messages, not nodes, wherever "deliverable" means "a receive in
this mode can take something". `mbox_waiting_has_deliverable` should use
`mbox_user_msgs(p) > 0 || control_mailbox` for modes other than 2 (markers
are only deliverable to wait mode 2). Add the harness as a case in
`test_hcr_migrate_order.c`.

---

## Fixed 2026-09-25

`mbox_waiting_has_deliverable` (runtime/march_scheduler.c) now counts what a receive
in the proc's wait mode can take. The actor loop (mode 2) takes markers, so any
user-mailbox node counts. Every other wait (a nested `receive()`, or a proc not in a
mailbox wait) counts user messages (`user_mbox_count - mbox_markers`) plus the
control plane (`mbox_count - user_mbox_count`), never a marker. `mbox_markers` became
`_Atomic int64_t` so the check can read it without the mailbox lock, as it reads the
other two counters; its writers still run under the lock, now with explicit relaxed
atomics.

Scope: only the receive-loop marker path; D27's hold/drain code (PR #648, merged
while this was in review) was not touched.

Test: `test/test_hcr_migrate_order.c` spawns itself twice (`nested-exit` and
`nested-exit-deploy`, `alarm(10)`): an actor whose handler blocks in
`march_actor_recv()`, and `main` returns with or without one activation. Output:
`control exit=0 deploy exit=0`, 62/62 at the time. The review's repro measured
`control=0 deploy=142` before the fix.
