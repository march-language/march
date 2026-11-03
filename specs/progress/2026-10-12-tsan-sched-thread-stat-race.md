# `[P4]` TSAN: per-scheduler thread statistics read across threads with plain accesses — FIXED

Found 2026-10-12 by the TSAN sweep over `test/native/*.march` (`MARCH_SANITIZE=thread`).
It showed up in `recon_basic` at 2 and 14 schedulers (7 reports across two pairs):

- `march_sched_thread_stat` (called by the observe snapshot's `write_sched`, via
  `Recon.node_stats`) against `sched_loop`'s `sched->stat_idle_polls++`
- the same reader against `sched->entered = 1`

## Benign

`started`, `entered`, `stat_dispatches` and `stat_idle_polls` in `march_scheduler`
(`runtime/march_scheduler.h`) are statistics. Each has one writer: the owning
scheduler thread, or `march_sched_run` for `started`. They are read by an observe
snapshot from another thread, and the header comment already called that read "a racy
snapshot". Nothing makes a decision on these values. Still, the plain accesses were a
C11 data race, and any TSAN report on a green thread can deadlock TSAN on macOS
(`2026-10-11-macos-tsan-scheduler-wedge.md`).

## Fix

- Every write is a relaxed `__atomic_store_n`. The two counters are bumped with
  `MARCH_SCHED_STAT_BUMP`: a relaxed load plus a relaxed store, not an atomic RMW,
  which is exact with one writer.
- `march_sched_thread_stat` reads with relaxed `__atomic_load_n`.

On arm64 the bump is the same `ldr`/`add`/`str` as `x++`, so the dispatch hot path is
unchanged.

Verified: `recon_basic`, rebuilt with the fix, reports nothing in 6 runs at 2 and 14
schedulers.
