# `test_scheduler_count` waits for every requested thread instead of hoping the OS schedules it

Shipped 2026-09-15. Test-only fix; no runtime change. Closes the `[P3]` todo
filed the same day (`test-scheduler-count-thread-observation-flake`).

## Symptom

`test_live_scheduler_threads_match_request` (`test/test_scheduler_count.c`,
run twice by `test/dune` as `test_scheduler_count_runner` and
`..._pinned_runner`) failed intermittently on the 4-CPU ubuntu-24.04 runner
with

```
  (distinct dispatching OS threads: 5, requested 7)
  FAIL: green threads must be dispatched by exactly as many OS threads as requested
```

seen on PRs that touch no runtime file (run 34925521318 reported 6, later
runs 5), while the pinned variant passed in the same job and a rerun passed.

## Cause

The test requests 7 scheduler threads, spawns 224 green threads that each do
40 rounds of a 200 000-iteration spin with a `march_sched_yield` between
rounds, and asserts that 7 distinct OS threads were observed dispatching one.

Nothing held the work open. All 224 procs go to the global run queue (they
are spawned from the main OS thread, before `march_sched_run`, so `tl_sched`
is NULL), every scheduler pops from it, and a scheduler thread that the OS
had not yet run found the queue already drained — it existed, it was counted,
it simply never got a turn. That is a property of the host's CPU scheduling,
not of March's.

`worker_fn`'s comment claimed workers "refuse to finish until enough peers are
simultaneously resident". They did not: the `g_spinning` counter that was
supposed to enforce it was incremented and decremented and **never read**.

## Fix

Option (a) from the todo, the rendezvous. After the same floor of real work,
every worker stays RUNNABLE — spinning briefly and yielding, so the procs keep
circulating through the global run queue — until either all `N_REQUESTED`
threads have been observed dispatching, or a 10 s deadline passes. A thread
that exists therefore cannot avoid being observed, and a count that is
genuinely short still fails (after the wait). `g_spinning` is gone.

Not option (b) (`distinct <= N_REQUESTED` plus a `march_sched_thread_count()`
the scheduler reports): the test exists because of G71, where the runtime's
own count said 14 while four threads ran. Asserting on a number the scheduler
hands out is the failure mode this test was written to detect, so contract 2
in the file header ("the honoured number is the number of OS scheduler threads
that actually dispatch green threads — not just a counter") stays literal.

## Verification

Both directions, with perturbed copies of `runtime/march_scheduler.c` built
against the old and new test:

- **Reproduces the CI symptom.** Delaying the last two `pthread_create`s by
  700 ms (what an overloaded runner's OS scheduler does for free) makes the
  OLD test fail 3/3 — `distinct dispatching OS threads: 4, requested 7` — and
  the NEW test pass 3/3. This is the decisive experiment: the flake is a
  late-starting thread, and the rendezvous is what absorbs it.
- **Still red on a real shortfall (non-vacuous).** With the runtime patched to
  create only `g_num_scheds - 2` threads, the new test fails with exactly the
  CI wording (`distinct dispatching OS threads: 5, requested 7`), taking the
  full 10 s deadline to say so.
- Healthy runs are unchanged in cost: 0.64 s / 0.56 s for the two dune
  runners (7 passed, 0 failed each), against 0.57 s before — the wait loop is
  never entered when all seven dispatch, which is immediate.
- 10/10 clean runs of both old and new inside a 4-CPU `ubuntu:24.04` container
  (`--cpuset-cpus=0-3`), with and without 12 competing CPU burners: the flake
  does not reproduce from load alone on this host, which is why the
  thread-start delay above is the control that matters.
- Builds warning-free under the rule's `-Wall -Wextra`.
