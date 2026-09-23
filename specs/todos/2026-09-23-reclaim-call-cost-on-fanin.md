# `[P3]` Decide whether the reclaim calls' fan-in cost is acceptable

Carried over from [[2026-09-23-proc-struct-reclamation-metas]] ("Mechanism PR 1 as
landed", "Open: a fan-in throughput cost the design did not predict") when that item
closed, so the question is not lost with it.

## The measurement

Mechanism PR 1 ([[2026-09-22-proc-struct-reclaimed]]) measured
`bench/actors/fanin_flood.march` against its base on a shared box:

- **+8%** median wall time (n=60).
- **+19%** on a 10× variant.
- **+1.9%** with one scheduler thread.

A build with every `march_reclaim_*` call a no-op matched base, so the cost is the calls
themselves. Single-threaded that is ~2 ns per send: the TLS-touching
`march_reclaim_enter`/`exit` pair in `march_send`. At 8 threads it could not be pinned to
one entry point. `sample` showed the run dominated by `mbox_lock` spinning on the sink,
so contention timing is the likely mechanism, not instruction count. That is not proven.

Mechanism PR 2 (metas) moved each hot reader's `enter` ahead of `find_meta`, which adds no
calls. Against PR 1 as its base, same box, run order shuffled, load average 20–30:
`fanin_flood` 164.6 → 163.7 ms (n=60), and the 10× variant +6.8% (n=20) then +2.5%
(n=30), inside the p10–p90 spread both times.

## The decision

Either accept the PR 1 cost, or drop the depth bookkeeping from scheduler-thread sites
and keep it only on foreign threads. On a scheduler thread `enter`/`exit` exist only to
move the depth counter that `march_reclaim_check_switch` asserts on, so dropping them
there loses the "critical section held across a context switch" crash-at-the-cause check
for those sites. It does not weaken the grace period, which on a scheduler thread comes
from the quiescent state at the top of `sched_loop`.

A quieter box (load < 5) and `perf`/Instruments counters on the 8-thread run would settle
whether the calls cost anything beyond noise before trading away the assertion.
