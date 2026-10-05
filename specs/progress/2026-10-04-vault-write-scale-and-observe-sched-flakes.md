# DONE 2026-10-04: two runner-noise flakes, made robust without going vacuous

Both failed PR #780's CI (run 37243574824), a test-only change touching neither
feature. Neither failure was a real regression; both assertions were
measuring host scheduling instead of the property they exist for.

## 1. `test/test_vault_write_scale.c` (conformance, ubuntu-24.04, `@vault-scale`)

**Failure:** `4 threads writing distinct keys took 87ms vs 14ms solo — worse
than serialisation (bound 84ms)`, ratio 6.21 against a `T * 1.5 = 6.0` bound.

**What it is for:** distinct-key Vault writes must not serialise on one lock
(the pre-2026-09-20 per-table write lock; see
`2026-09-20-vault-write-partitioning.md`).

**Why wall time cannot carry that on CI hardware.** 80 CI runs of the
correct, sharded runtime: ubuntu (4 vCPU) ratio 2.62 / ~3.5 / 5.53
(min / median / max), macOS (3 cores) 2.21 / ~2.9 / 4.62. Plain serialisation
is 4.0 and 3.0, so the hosted hardware barely scales this workload, and the
bound was the only thing between the two. Worse, it never caught the bug there
either; with the bug reintroduced (below), the old bound **passed** it:

| 30 runs each, old 6.0x bound | correct | one lock per table | global lock around `set` |
|---|---|---|---|
| linux/arm64, 4 CPUs + 4 `yes` | 1 false FAIL | **30 PASS** (ratio 2.7-3.9) | **29 PASS** |
| macOS 14 cores, 14 `yes` (load 120-180) | 6-7 false FAILs | 13 PASS | 18 PASS |

When threads don't overlap on CPU there is nothing for a lock to serialise, so
under load a global lock and the shards look the same by the clock.

**Fix: count locks, not milliseconds.** `test/vault_lock_probe.h` is
force-included (`-include`) into every source of the runner, runtime included,
and turns `pthread_mutex_lock` into `vault_probe_mutex_lock`, which tallies
acquisitions per mutex address on probed writer threads. Four threads each do
20,000 writes to their own 64 keys. The run fails if

- one mutex covers at least 50% of **every** thread's writes (shards: 6.25%,
  16 mutexes; table or global lock: 100%), or
- the probe saw fewer acquisitions than writes (the write path stopped using a
  pthread mutex, so the probe can't see its lock; this fails rather than
  passing blind; verified by swapping the shard lock for a trylock spin).

Key hashing is deterministic, so the verdict is too. The timing ratio is still
measured and printed (it is the partitioning work's deliverable), but no
longer asserted. The header has no `#include`s, by design: the first version
included `<pthread.h>`, which ran glibc's feature selection before
`march_scheduler.c`'s own `_GNU_SOURCE` and lost `CPU_ZERO` on Linux. The
object-like macro lets each file's own `<pthread.h>` declare the probe.

| 30 runs each, new check | correct | one lock per table | global lock around `set` |
|---|---|---|---|
| linux/arm64, 4 CPUs + 4 `yes` | 30 PASS (6.25%) | 30 FAIL (100%) | 30 FAIL (100%) |
| macOS, 14 `yes` | 30 PASS (6.25%) | 30 FAIL (100%) | 30 FAIL (100%) |

## 2. `test/native/observe_sched` (test, macos-15): idle readings of running actors

**Failure:** `running actors read under 50 ms idle (5 samples)` with readings
`5,5,12,101 9,9,0,28 2,11,11,2 1,10,17,10 9,9,9,0`: 1 of 20 over.

**What it is for:** a running actor's `idle_ms` must not be stale. It once
came from a per-scheduler clock refreshed every 1024 dispatches, which put
nearly every reading over 50 ms. The 101 ms was real lateness instead: four
spinners on four scheduler threads time-sharing a 3-core runner, and one
thread was descheduled mid-slice.

**Fix (`test/observe_snapshot_check.ml`):** 10 samples (40 readings), keyed by
pid. Fail if any actor is over 50 ms in half or more of its samples, or more
than a quarter of all readings are over. The readings go to stderr on every
run, so CI logs carry the distribution.

Readings over 50 ms per run (of 40), 30 runs each:

| | correct | stale A: 1024-dispatch clock | stale B: coarse clock every 100 ms |
|---|---|---|---|
| linux/arm64, 4 CPUs + 4 `yes` | 0-6 (p50 3 ms, p99 85 ms), 30 PASS | 38-40, 30 FAIL | 24-40, 30 FAIL |
| macOS, 14 `yes` (load ~125) | 0-6 (p50 4 ms, p99 73 ms), 30 PASS | 36-40, 30 FAIL | 21-40, 30 FAIL |

Under the old rule (any of the first 5 samples' readings over 50 ms fails),
the same correct runs would have failed 4/30 (Linux) and 6/30 (macOS). The
fail line (>10 of 40) sits between the correct worst (6) and the mildest
stale variant's best (21).

Both bugs were reintroduced only in throwaway builds (`runtime/` is
unchanged in this commit).
