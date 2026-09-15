# `[P3]` `test_scheduler_count`'s "every requested OS thread dispatches" assertion is timing-based on runners with fewer CPUs than threads

Filed 2026-09-15. `test/test_scheduler_count.c`,
`test_live_scheduler_threads_match_request`: requests 7 scheduler threads,
spawns `N_WORKERS` green threads that each spin 40 rounds (200 000
iterations each) with a `march_sched_yield` between rounds, then asserts
that the set of OS threads observed dispatching a worker has exactly 7
members. On the ubuntu-24.04 CI runner (4 usable CPUs) it reported
`distinct dispatching OS threads: 6, requested 7` on run 34925521318
(PR #467, which touches no runtime file); the pinned variant of the same
test passed in the same job, and a rerun passed.

The comment in `worker_fn` says a scheduler thread "cannot avoid being
observed", which holds only while every thread gets CPU time before the
work runs out. With 7 threads on 4 CPUs and ~40 × 200k iterations of work
per worker, one thread can be descheduled by the OS for the whole window.
The assertion is about the scheduler's thread count, not about the OS's
fairness, so it should not depend on the latter.

## What to do

Either (a) make the observation rendezvous a real barrier — each worker
waits until `g_seen_len == N_REQUESTED` (with a generous timeout) before
finishing, so the work cannot run out while a thread is unobserved; or (b)
assert `distinct <= N_REQUESTED` and, separately, that the scheduler
*created* exactly `N_REQUESTED` threads (a count the scheduler can expose
directly, `march_sched_thread_count()`), which is what the test means.
(b) is the honest one: it measures the property, not the OS schedule.
