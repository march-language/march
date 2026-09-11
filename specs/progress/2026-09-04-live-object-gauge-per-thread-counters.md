- ✅ **The always-on live-object gauge no longer serialises parallel allocation
  (`runtime/march_runtime.c`, 2026-09-04).** `march_live_allocs()` — the FFI/test
  leak gauge described in `specs/2026-06-19-c-ffi-abi-design.md` §14.4 — was a single
  `_Atomic int64_t` bumped by `MARCH_ALLOC_BUMP()` in `march_alloc` and by
  `MARCH_FREE_BUMP()` in every RC free-on-zero path (`march_decrc`,
  `march_decrc_freed`, the resource-dtor branch, and `march_string_alloc`/its free).
  It is **not** behind a debug flag — unlike the neighbouring `str_stats_on()` /
  `obj_alloc_count` counters, which are opt-in and were left alone — so every thread
  in the process read-modify-wrote **one cache line** on the two hottest paths there
  are.

  **Why it hid.** Nothing about the gauge is wrong: it is correct, it is cheap in
  isolation (an uncontended relaxed `fetch_add` is a few ns), and every existing test
  of it is single-threaded, where it costs nothing measurable. The defect is visible
  only as a *scaling* property, and only on allocation-dominated parallel work — which
  is exactly the workload the runtime's scheduler exists to serve. It was found while
  root-causing a voxel engine's whole-world meshing throughput, where `march_alloc`
  was the single largest March symbol in the `sample` profile (10,552 top-of-stack
  samples); replacing the counter moved it outside the top 25 and took meshing from
  1.6x to 2.1x on 14 threads.

  **Fix: per-thread slots, summed on read.** Each thread owns a `march_live_slot`
  that it alone writes, with a relaxed load/store *pair* rather than an atomic RMW —
  a plain `ldr`/`str`, no bus lock, no sharing. The slot's counter is `_Atomic` solely
  so the reader's concurrent load is defined behaviour instead of a data race.

  **The subtlety that makes a naive version wrong.** Allocation and freeing are not
  thread-affine: an object allocated on one scheduler thread is routinely freed on
  another, so an individual slot goes arbitrarily negative or positive and only the
  SUM is meaningful. That is fine for a gauge — but only if the sum survives thread
  *exit*. A `pthread_key_t` destructor folds an exiting thread's residual into a
  process-wide `march_live_residual` (via `atomic_exchange`, so the count is never
  seen twice nor lost by a concurrent reader) and releases the slot for reuse by a
  later thread; `march_live_allocs()` returns the residual plus a lock-free walk of
  the slot list. Slots are never freed, so the walk needs no lock.

  Exactness under concurrency is neither required nor regressed: the gauge is read
  between frames by FFI/leak tests, and `memory_order_relaxed` already gave no
  ordering guarantee.

  **Non-vacuousness.** The new multi-threaded case in `test/test_ffi.c` — eight
  threads allocate 512 objects each and **exit**, then eight fresh threads each free a
  slot they did not allocate (rotate by one) — was proved RED against a deliberately
  naive `_Thread_local int64_t` with no cross-thread aggregation (`Assertion failed:
  march_live_allocs() == base + MT_THREADS * MT_PER_THREAD`, test_ffi.c:222) before the
  real implementation was written. That same broken variant also trips a pre-existing
  assertion at test_ffi.c:204, which reads the gauge from a `march_run_blocking_i`
  OS thread — so the naive form was never reachable undetected.

  **Measured** (M3 Max, 14 cores, runtime built with `-DMARCH_NUM_SCHEDULERS=16`;
  `List.pmap_n` over 64 tasks each building and summing 2000-element cons lists 300
  times; best of 3 per cell). The machine was **saturated by other agents' compiler
  runs at load average 120–170**, so every absolute number is inflated and only the
  ratios carry meaning:

  | scheduler threads | global atomic (before) | per-thread (after) | gauge compiled out |
  |---|---|---|---|
  | 1  | 1875 ms | 2250 ms | 1867 ms |
  | 4  | 2198 ms |  917 ms |  938 ms |
  | 10 | 2700 ms |  474 ms |  621 ms |
  | 14 | 3022 ms |  471 ms |  546 ms |

  Before: 14 threads were **1.6x slower than 1 thread**. After: 14 threads are 4.8x
  faster than 1, and 6.4x faster than the old code at the same width — matching, at
  this noise level, a build with the gauge compiled out entirely. The 1-thread
  per-thread cell above is an outlier from machine load, not a real single-thread
  regression: a follow-up with 5 reps per variant, run twice, gave global 1774/1725,
  per-thread 1876/1675, compiled-out 1655/1741 — mutually indistinguishable. (TLS
  access is not free on macOS — `_tlv_get_addr` appears in profiles of this runtime —
  so this was measured rather than assumed.)

  **Verification.** `dune build @runtest` green (exit 0; `test/` alone: 693
  refinecheck cases + the rest, "Test Successful"). The three RC-sensitive
  benchmarks, compiled `--opt 2` and run as a same-box A/B against a compiler
  built with the old runtime (best of 5, interleaved): `binary_trees` 447 → 432 ms,
  `tree_transform` 861 → 866 ms, `list_ops` 135 → 109 ms — no regression, and stdout
  byte-identical between the two variants with the documented checksums
  (`tree_transform` 104857600, `list_ops` 333333666666). `.march/cas/artifacts-v2`
  was cleared before each runtime variant.

  **Out of scope, deliberately.** The stock runtime's compile-time cap of 4 scheduler
  threads (`MARCH_NUM_SCHEDULERS` in `runtime/march_scheduler.h`; the env var can only
  lower it) is a separate bug — the header was bumped to 16 for the measurement above
  and reverted, not changed here. `str_stats_on()` / `obj_alloc_count` and friends are
  already flag-gated and untouched.
