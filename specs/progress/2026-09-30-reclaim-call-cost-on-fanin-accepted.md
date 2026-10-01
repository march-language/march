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

## Resolution (2026-09-30): accepted, not gated

Owner decision was measure first, then gate. The measurement says there is nothing
to gate.

**Why gating cannot win by construction.** `march_reclaim_enter`/`exit` are called
unconditionally because a foreign thread needs the real epoch announce, and the call
site cannot know which kind of thread it is without the same TLS read the call does.
Gating the depth bookkeeping behind a debug macro would therefore remove only a
`depth++` / `depth--` (plus the assertion's operand), never the call or the TLS
access. So the best any gate could do is bounded above by a build where the
scheduler-thread calls return immediately.

**Upper-bound A/B.** Same box, same compiler (`origin/main` at 0b9c22275), runtime
swapped through `MARCH_RUNTIME_DIR`. Variant = `if (t->qsbr) return;` as the first
statement of `march_reclaim_enter` and `march_reclaim_exit` (verified in the
disassembly), i.e. scheduler-thread bookkeeping removed entirely and the assertion
blind. `--compile --opt 2`, runs alternate A B A B, wall time of the whole process.

| workload | base min / median | no-bookkeeping min / median | n each |
|---|---|---|---|
| `fanin_flood`, 8 schedulers | 99.2 / 126.0 ms | 104.3 / 129.6 ms | 40 |
| `fanin_flood`, 8 schedulers (first run) | 92.6 / 129.7 ms | 108.6 / 132.5 ms | 15 |
| `fanin_flood` x10 msgs, 8 schedulers | 975.6 / 1208.8 ms | 996.5 / 1245.6 ms | 15 |
| `fanin_flood`, 1 scheduler | 56.8 / 62.1 ms | 56.0 / 62.9 ms | 30 |

Removing the bookkeeping did not make anything faster: the variant is within noise,
and nominally slower on three of four rows. Load average was 14-20 for every run
(1-min), far above the < 5 target, so a small delta would not be readable here; but
the sign and the size (|delta| <= 3%, inside the min-to-median spread of 25-30%) are
what the "contention timing, not instruction count" reading predicted. The original
+8% / +19% was most likely a different lock-acquisition interleaving, not the cost of
the calls.

**Decision.** Keep `march_reclaim_enter`/`exit` and `march_reclaim_check_switch`
exactly as they are in every build, including release. The "critical section held
across a context switch" assertion stays everywhere and no `MARCH_*` build macro is
added. No code change. Reopen only if a quiet-box (load < 5) run with Instruments
shows the calls above the `mbox_lock` spin.
