# `[P3]` Flake: `test_live_scheduler_threads_match_request` sees fewer OS threads than requested

Filed 2026-09-17. Recurred on PR #509's ubuntu-24.04 `test` job (run 35261673191):

```
  (distinct dispatching OS threads: 6, requested 7)
  FAIL [test_live_scheduler_threads_match_request:218]: green threads must be dispatched
  by exactly as many OS threads as requested -- the workers stayed runnable for up to
  SEEN_WAIT_S waiting for the missing thread, so this is a real shortfall
```

The rerun passed. [[2026-09-15-test-scheduler-count-thread-observation-rendezvous]] fixed
the earlier shape of this (a thread that merely started late) by holding the workers
runnable for `SEEN_WAIT_S` (10 s); this sighting is the message that fix added for the
case it could not fix: the 4-CPU runner never dispatched a 7th scheduler thread within
10 s while 6 others were saturated with spinning workers. That is the OS's scheduling
policy, not the runtime's: seven runnable pthreads on four CPUs are not guaranteed a
turn each inside any bound.

**What to do.** The assertion is stronger than the property. What the test exists to
prove is that the runtime *creates* and *runs* as many scheduler threads as requested;
"each one dispatches a green thread within 10 s under contention" is a scheduling
outcome. Either count the threads that entered `sched_loop` (a rendezvous on entry, not
on dispatch), or run this case only when `usable CPUs >= requested`. Until then it costs
a rerun each time.
