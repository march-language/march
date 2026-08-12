# Fix silent local-deque overflow stranding runnable green threads

Task 12b of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`) — an inserted task,
found during Task 12's review, not in the original plan document.

## The bug

`runtime/march_deque.h`'s Chase-Lev work-stealing deque is bounded at
`MARCH_DEQUE_CAPACITY` (4096) and `march_deque_push` returns `-1` when full.
Both call sites in `runtime/march_scheduler.c` ignored that return value:

1. `sched_spawn_common`'s spawn-from-scheduler-thread push (the owner-push
   path taken when a green thread spawns another proc).
2. `sched_loop`'s yield-repush (a proc that yields while still `RUNNABLE` is
   pushed back onto its own scheduler's local deque).

When either push silently failed, the proc was already marked `RUNNABLE`
and counted in `g_live_procs`, but was never actually enqueued anywhere —
stranded forever. Since a queued-but-unreachable proc still counts as live,
`g_live_procs` never drains to zero and every scheduler thread eventually
idle-parks waiting for work that will never arrive: a livelock, not a crash,
so nothing but a wall-clock watchdog catches it. `bench/actors/spawn_churn.march`
(40k sequential spawn+kill) hung at this cliff; a reduced 6000-churn repro
hung within 30s.

## Confirmation

Added a temporary `fprintf`+`abort()` on `march_deque_push` failure at both
sites (not committed), rebuilt, and reran the 6000-churn repro: the abort
fired at `spawn_local_push` (`TASK12B-PROBE: spawn_local_push deque full`,
exit 134), confirming the hypothesis before touching the fix.

## The fix

At both call sites, on `march_deque_push` failure, fall back to
`global_runq_push(p)` (the existing unbounded, mutex-guarded global run
queue — already the fallback used when a non-scheduler thread spawns). Both
sites are restructured so `dbg_mark_enqueued` (the `MARCH_DEBUG`
single-membership tripwire) fires exactly once per actual enqueue: attempt
the deque push first, mark enqueued only on success; on failure,
`global_runq_push` does its own marking. (Previously `dbg_mark_enqueued` was
called unconditionally before the push, which would have double-marked —
and aborted a debug build — if simply added on top of the old ordering.)

No other caller of `march_deque_push` exists outside `march_scheduler.c`.

## Regression test

Added a segment to `test/test_scheduler_churn.c`: a single green thread
(`churn_burst_spawner`) spawns 5000 tiny procs from *inside* the scheduler
(so the spawns hit the owner's local Chase-Lev deque, not the global run
queue), run to quiescence under the file's existing `alarm(60)` watchdog,
with an atomic counter (`g_churn_burst_done`) asserted `== 5000` after.

Verified the test actually reproduces the pre-fix hang: compiled
`test_scheduler_churn.c` against `git show HEAD:runtime/march_scheduler.c`
(HEAD at task start, i.e. pre-fix) via a temp copy — the run printed
`recycled=3000` (first segment, unaffected) then hung until the file's own
`alarm(60)` fired (SIGALRM, exit 142), never reaching the burst assertion.
Against the fixed scheduler it completes in well under a second and prints
`churn_burst_done=5000 (expected 5000)`.

## Verification

- `dune build --root . @test/runtest` — full suite green, including the new
  churn-burst segment.
- `bench/actors/spawn_churn.march` at both the reduced (6000) and full
  (40000) churn counts now complete (previously hung indefinitely at both).
- `scripts/actor-load.sh churn` — see report for exact before/after numbers
  and the `EXPECTED_FAIL` gate decision.

## Files touched

- `runtime/march_scheduler.c` — the two-site fix.
- `test/test_scheduler_churn.c` — new burst-overflow regression segment.
- `scripts/actor-load.sh` — `EXPECTED_FAIL` updated if churn now passes.
- `CHANGELOG.md` — user-facing `### Fixed` entry.
