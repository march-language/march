# `[P3]` `march_sched_send`'s BLOCK self-deadlock guard read a stale `tl_sched` after a migration — FIXED

Found 2026-10-12 by the TSAN sweep over `test/native/*.march` (`MARCH_SANITIZE=thread`).
It showed up in `proc_reclaim_kill_respawn` at 2 and 14 schedulers, in 3 of 3 runs, as
two report pairs:

- `march_sched_send` (the `MARCH_MBOX_BLOCK` case) read `tl_sched->current` and
  raced with `sched_loop`'s `sched->current = p`, on another scheduler thread.
- The same read raced with `sched_loop`'s `sched->current = NULL`.

## Why that read can race at all

A green thread reading its OWN scheduler's `current` cannot race with that scheduler.
The scheduler wrote it and then `__tsan_switch_to_fiber`'d (synchronising) into the
proc. So the read was hitting a DIFFERENT scheduler.

The guard `if (tl_sched && !tl_sched->current) break;` sits inside `march_sched_send`'s
`for (;;)` retry loop, and the loop re-runs it after `mbox_block_register_and_park`.
That park can resume the sender on another OS thread. clang treats a `_Thread_local`
address as loop-invariant within one activation, so it can hoist the `tl_sched` read
out of the loop. This is the hazard class documented at length on
`mbox_block_register_and_park`. That function's comment says every `tl_sched` read in
this loop must go through a fresh noinline call. The guard was the one read left
inline.

## Consequence (non-TSAN builds too)

After a migration, the retry iteration checked the PRE-migration scheduler's
`current`:

- If that scheduler was idle (`current == NULL`), a genuine green-thread sender took
  the "running on a scheduler's own C stack" bypass. It pushed past a
  `MARCH_MBOX_BLOCK` mailbox's limit instead of waiting again.
- If the old scheduler was dispatching something, the check happened to give the
  right answer.

No crash and no lost message, but BLOCK's capacity bound was silently not enforced
for that send.

## Fix (`runtime/march_scheduler.c`)

`on_sched_control_plane()` is a `noinline` helper that reads `tl_sched` fresh. The
guard calls it.

Verified: `proc_reclaim_kill_respawn`, rebuilt with the fix, gets 0 `march_sched_send`
reports in 6 runs at 2 and 14 schedulers. It was in 3 of 3 runs before. That fixture's
remaining report is the supervisor child-slot race, filed in
`specs/todos/2026-10-12-supervisor-child-slot-race.md`.
