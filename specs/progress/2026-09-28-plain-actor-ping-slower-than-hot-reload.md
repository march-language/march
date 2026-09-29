# `[P2]` A plain actor ping-pong ran 2.7× slower than the `--hot-reload` build (DONE, 2026-09-28)

**Filed:** 2026-09-23 as `specs/todos/2026-09-23-plain-actor-ping-slower-than-hot-reload.md`
(found by the G1 boundary-cost measurement,
`specs/progress/2026-09-23-hot-reload-boundary-cost.md`). **Closed:** 2026-09-28.

## Cause

Not the dispatch call shape: a waker sleeping in `march_sched_wake`.

A proc that parks stores `PROC_PARKED` and swaps to its scheduler; only after
`swapcontext` returns does `sched_loop` store `PROC_WAITING` (its context is then
saved and it may be enqueued). `march_sched_wake` found a `PARKED` target and
**waited** for `WAITING`: 4096 spins, then `nanosleep(1 ms)` per poll. In a ping-pong
across 14 schedulers the partner's handler often finishes and sends before the
parking scheduler thread has reached its `WAITING` store (that thread can simply be
descheduled for a moment at load ~10), so the sender slept.

Counted with temporary counters in `march_sched_wake` (1,000,000 messages, 14
schedulers):

| build | wakes | saw `PARKED` | fell back to 1 ms sleep | wall |
|---|---:|---:|---:|---:|
| plain | 999,977 | 1,817 | **972** | 2.42 s |
| `--hot-reload Game` | 999,989 | 385 | 201 | 1.53 s |

~970 sleeps of ≥1 ms is the whole gap. Instructions retired were the same for both
builds (16.8 G vs 16.5 G); the plain build was idle, not busy. The hot-reload build's
extra per-message work (`march_dispatch_enter_unit`/`leave` around the handler)
only made the race window rarer. With `MARCH_NUM_SCHEDULERS=1` or `2` both builds ran
in ~1.0-1.2 s.

## Fix (`runtime/march_scheduler.c`)

The waker no longer waits. It already deposits the target's `wake_pending` permit
before reading `status`; if the target is `PARKED` it now just returns. `sched_loop`,
right after its `PARKED -> WAITING` store, reads the permit and, if one is set, wins
the `WAITING -> RUNNABLE` CAS itself and pushes the proc to the global run queue (the
queue every wake uses). seq_cst on the permit store/status load (waker) and the
`WAITING` store/permit load (scheduler) makes it a Dekker pair: either the waker sees
`WAITING` and enqueues, or the scheduler sees the permit; the CAS lets exactly one of
them enqueue. The permit is cleared only by the CAS winner, never consumed before the
CAS, so a permit a newer waker leaves for the proc's NEXT park is not swallowed.
`park_self`'s un-park path (it consumes a permit that lands after its `PARKED` store)
is unchanged and needs nothing from the handoff.

A permit left stale (its waker found the proc `RUNNABLE`/`RUNNING` after reading
`PARKED` under the mailbox lock) now costs at most one spurious wake at the proc's
next park, which every park site already tolerates by looping.

Pushing the handed-off proc to the parking scheduler's own deque instead of the
global queue was tried and measured the same on both benchmarks below; the global
push keeps the "every wake goes global" rule single-cased.

## Measurements

Same compiler binary; `MARCH_RUNTIME_DIR` pointed at an origin/main (14ec3b71f) copy
of `runtime/` vs this branch's. Compiled `--opt 2`, runs alternating which variant goes
first, min of N; 14-core Mac, load average 8-10 (other sessions).

| benchmark | origin/main | this change |
|---|---:|---:|
| `bench/actor_ping.march` plain (N=7) | 3.067 s | **1.178 s** |
| `bench/actor_ping.march --hot-reload Game` (N=7) | 1.446 s | 1.222 s |
| `bench/actors/call_storm.march` (N=5) | 0.285 s | 0.284 s |
| `bench/actors/fanin_flood.march` (N=5) | 0.133 s | 0.119 s |
| `bench/actors/send_after_churn.march` (N=9) | 0.834 s | 0.767 s |
| `bench/actors/spawn_churn.march` (N=15; medians 0.436 / 0.425) | 0.377 s | 0.391 s |
| `bench/actors/crash_loop.march` (sleep-dominated, N=5) | 45.94 s | 41.95 s |

Plain is now within 4% of the hot-reload build (1.178 vs 1.222 s; acceptance: ~10%).
The two `actor_ping` rows are the final runtime; load average 11-20 during them.

## Tests

- Every C scheduler runner that links `march_scheduler.c` (21 runners: scheduler,
  pin, count, count_pinned, preempt_signal, timer, fdwait, mbox, churn, mt,
  broadcast_migrate_leak, hcr_migrate_order, signal_watch, float_box, vault_*,
  actor_registry, ffi) passes; the concurrency-heavy ones (scheduler, mt, mbox, churn,
  timer, fdwait, vault_concurrency, actor_registry) 20/20 runs each.
- New `test/test_scheduler.c` case `test_wake_parked_does_not_wait`: a proc left in
  `PROC_PARKED` with nothing to finish the park is woken; the wake must return at once,
  leave the permit and not enqueue. GREEN; RED on origin/main's scheduler (the wake never
  returns: killed by the test's 10 s alarm, rc 142).
- `scripts/run-tests.sh` (full): passes.
- 99 dune-rule native/session fixtures whose names mention actors, spawn, sessions,
  tasks, supervision, mailboxes, monitors, registries or calls (compiled and, where the
  rule has one, interpreted): all match their goldens.
- Linux container (arm64, `march-amdr-repro` image), `MARCH_SANITIZE=thread` on a
  20,000-message `actor_ping`: every report on both runtimes is in
  `march_preempt_signal_handler` (a pre-existing class: 70-118 per run here, 112-126 on
  origin/main); none touches the wake or the handoff. `MARCH_SANITIZE=1` on the same
  program and on `spawn_churn`: no ASAN error on either runtime; LeakSanitizer totals are
  identical to origin/main's (960,048 and ~2,508,954 bytes).
