# `sched_stat` builtin + `Scheduler` stdlib module

Task 6 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`).

## What shipped

- `runtime/march_scheduler.c` / `.h`: a new `g_runq_len` atomic counter
  (incremented in `global_runq_push`, decremented in `global_runq_pop` only
  on an actual pop), a `march_stat_counters[8]` array reserved for
  cross-file counters (indices 3-5: stack-alloc failures, messages dropped,
  stacks recycled — bumped by later tasks), and
  `int64_t march_sched_stat(int64_t which)` dispatching on index:
  - 0 = `g_live_procs`, 1 = `g_next_pid`, 2 = `g_runq_len`,
    3-5 = `march_stat_counters[which]`, 6 = timer heap length
    (`g_timer_len`, read under `g_timer_mu`), default = 0.
- Compiler plumbing (typecheck/defun/llvm_builtins/eval — mirrored the
  existing `mailbox_size` builtin's 4 sites): `sched_stat(i : Int) : Int`.
  Interpreter has no C scheduler, so it reports the subset that's
  meaningful: index 0 = live actor count (`Hashtbl.length actor_registry`),
  index 1 = total spawned (`!next_pid`), everything else 0.
- `stdlib/scheduler.march`: `Scheduler.stat(i)`, `live_procs()`,
  `total_spawned()`, `runq_depth()`, `dropped_messages()`.
- `test/native/sched_stats.march` + `.expected` + a `test/dune` rule
  (cloned from the Task 5 `mailbox_depth` rule) — compiles natively, checks
  `live_procs()`/`total_spawned()` are both `>= 1` and an unknown index
  (`Scheduler.stat(99)`) reads `0`.

## Notes for future tasks

- Indices 3 (`MARCH_STAT_STACK_FAIL`), 4 (`MARCH_STAT_MSGS_DROPPED`), and 5
  (`MARCH_STAT_STACKS_RECYCLED`) are defined in `march_scheduler.h` but
  nothing bumps them yet — Tasks 13, 7, and 12 respectively are expected to
  wire those in via `march_stat_counters[MARCH_STAT_*]`.
- `stdlib/scheduler.march` brought the stdlib module count from 112 to 113;
  `scripts/check-docs.sh` flagged every doc pinning that count, all updated
  in this commit.
