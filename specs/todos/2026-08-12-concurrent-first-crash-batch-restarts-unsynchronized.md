# Two concurrent first-time crashes of a batch supervisor's children can race two unsynchronized restarts

Filed during Task 16's round-3 review
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`). Pre-existing
since the leaf-lock `g_supervise_mu` design (round 1 of the backoff
review), not something round 3 introduced or fixed.

## The mechanism

`march_supervisor_notify`'s leaf-lock section only guards against a
SECOND batch restart being scheduled while one is already
`delayed_batch_pending` (Important 2 / round 2 / round 3's absorb-loop
fix). It does nothing for the case where TWO DIFFERENT children of the
same `one_for_all`/`rest_for_one` supervisor crash for the FIRST time
(`streak == 1`, `delay == 0`) at genuinely the same moment, on different
OS threads (this codebase's default `MARCH_NUM_SCHEDULERS` gives true
parallelism between actors' green threads):

- Child B's crash takes the `delay == 0` synchronous path, calls
  `march_one_for_all_restart`/`march_rest_for_one_restart` directly —
  with `g_supervise_mu` NOT held (by design: the leaf-lock contract
  forbids holding it across a strategy call, since the strategy runs
  March closures and can call `do_actor_death`).
- Child C's crash, on another thread, arrives close enough in time that
  its own leaf-lock section also observes `delayed_batch_pending == 0`
  (nothing has claimed it yet — a first crash never claims the pending
  flag, only a repeat crash with `streak > 1` does) and ALSO takes the
  `delay == 0` synchronous path.
- Both now call a restart strategy function concurrently, unsynchronized,
  against the same supervisor's `sup_children`/state-array fields — the
  same shape of corruption as the delayed-path race round 3's fix report
  documented and closed (see
  `.superpowers/sdd/2026-08-11-actor-system-hardening/task-16-report.md`,
  "Fix report: review round 3").

## Why this wasn't caught by the delayed-path fix

The delayed-path fix works because a REPEAT crash (`streak > 1`) always
claims `delayed_batch_pending` before releasing the lock, so any other
crash arriving after that point sees the flag and gets dropped
(`skip_due_to_pending`), never launching a competing restart. A crash
with `streak == 1` never claims anything — by design, since round 1's
whole point was keeping the very first crash of every slot on the
original, pre-Task-16, synchronous zero-delay path for golden-byte
compatibility. Two such first-crashes, of two DIFFERENT slots, landing
close enough in time on two different OS threads is exactly the gap this
guard doesn't cover.

## Likely fix shape

The delayed path's fix (keep a flag held for the whole in-flight
duration of the strategy call, not just up to the moment it starts) is
the right template. Applying the same idea to the synchronous path means
even a `streak == 1` batch-strategy crash would need to claim some
"a batch restart is in flight" marker (not necessarily
`delayed_batch_pending` itself, since that name and its associated
`pending_min_child_idx`/`pending_drop_count` machinery are specific to
the delayed/backed-off case — but the SAME general shape: claim before
calling the strategy, release only after it returns, absorb any
crashes that land in between via widening + drop-counting like the
delayed path does) before calling the strategy synchronously, so a
second first-time crash of a sibling landing mid-flight is deflected the
same way a repeat crash already is.

Not fixed here: this is Important-sized (a real, evidenced-by-code-argument
concurrent-corruption path, not a cosmetic issue), but distinct enough
from round 3's specific ask (the `pending_min_child_idx` absorb-loop
completeness bug) that it deserves its own scoped review pass rather than
a rushed addition to an already-large diff.
