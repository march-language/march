# Actor-system hardening, phase 1: single-node runtime — shipped

Plan: `docs/superpowers/plans/2026-08-11-actor-system-hardening.md`. Full
task-by-task working ledger (every commit range, every review finding, every
deferred/minor item): `.superpowers/sdd/2026-08-11-actor-system-hardening/progress.md`.
This file is the summary; that ledger is the detail trail.

Base at start: `cbb8346e`. Sixteen tasks (plus one inserted mid-plan, 12b)
landed sequentially, each gated on a clean code review (several needed 1-3
fix rounds before the reviewer signed off — noted below where relevant).
PR #258 (https://github.com/march-language/march/pull/258) carries tasks
1-9; the branch continued past it for tasks 10-16 and this close-out task.

## The problem this closes

The actor runtime had four independent failure classes under load, found by
an upfront analysis before any task started:

1. **Unbounded mailboxes** — a producer outrunning its consumer grows a
   mailbox without limit; no backpressure, no observability into it.
2. **No observability** — no way to ask the runtime how many actors are
   alive, how deep a queue is, or how many messages were dropped.
3. **Scaling cliffs** — fixed-size tables (a 65536-pid process registry) and
   silent overflow paths (a bounded local work-stealing deque whose push
   failure was never checked) that held up fine at small scale and then
   either corrupted state or wedged the whole process once load crossed an
   invisible threshold.
4. **Lock-heavy send path + fragile supervision timing** — a single global
   table mutex on the hot send path, `Actor.call` timeouts that could
   deliver a late reply as the answer to a later unrelated call, and
   supervisor restarts with no backoff (a repeatedly-crashing child gets
   respawned as fast as it can crash, burning CPU and log volume).

Task 1 built a saturation-gate harness (`scripts/actor-load.sh`, four
scenarios: `fanin`, `churn`, `callstorm`, `crashloop`) with an `EXPECTED_FAIL`
allowlist specifically so each of these could go from a documented,
reproducible failure to a gate that provably flips to green — "provable, not
plausible" was the standard for the whole plan.

## Harness before/after

At Task 1 (before any fix landed), running `scripts/actor-load.sh`:

- `churn` **hung** at roughly 4,000-4,500 churned actors (spawn/crash/respawn
  in a tight loop) — far below the plan's original ~20-30k estimate for
  where a cliff might appear. This was the plan's sole `EXPECTED_FAIL` entry
  for the rest of the early tasks.
- The other three scenarios (`fanin`, `callstorm`, `crashloop`) ran but
  without any of the fixes below, so they measured the pre-hardening
  baseline numbers cited in individual task entries (e.g. call-storm
  533ms → ~430ms after Task 3).

After Task 12b (root-caused and fixed the `churn` hang) and Task 13 (removed
the registry's 65536-pid lifetime cliff), `scripts/actor-load.sh` runs all
four scenarios to `status=PASS` with no `EXPECTED_FAIL` entries left — the
first time in the plan the harness was clean end to end. It stayed clean
through Tasks 14-16 and this close-out task's fixture fix.

## What shipped, by task

- **Task 1 — saturation-gate harness.** `scripts/actor-load.sh`, four
  scenarios, `run_with_bound` wall-clock kill guard (macOS has no
  `timeout(1)`), `EXPECTED_FAIL` allowlist. Found the `churn` cliff
  immediately (see above).
- **Task 2 — scheduler timers.** Green threads can park with a deadline;
  foundation for `Actor.call` timeouts (Task 3/4) and supervisor backoff
  (Task 16).
- **Task 3 — call-storm collapse.** Fixed a lost-wakeup window (reply
  arriving between an empty `try_recv` and the PARKED store would sleep the
  full timeout instead of waking immediately); call-storm 533ms → ~430ms.
- **Task 4 — late-reply correlation.** A late reply from a timed-out
  `Actor.call` is now wrapped in an envelope carrying that call's
  correlation id; a reply whose id doesn't match the in-flight call is
  discarded instead of being misdelivered as the answer to a *later*,
  unrelated call (`march_actor_call_unwrap`, `runtime/march_runtime.c`).
- **Task 5 — mailbox depth observability groundwork**, feeding Task 6's
  counters.
- **Task 6 — `Scheduler` module + `sched_stat` builtin.** `live_procs`,
  `total_spawned`, `runq_depth`, `dropped_messages`, raw `stat(i)` escape
  hatch. The load-shedding substrate the rest of the plan's observability
  builds on.
- **Task 7 — bounded mailboxes, drop policies.** `march_sched_set_mbox_limit`
  with `MARCH_MBOX_DROP_NEW`/`MARCH_MBOX_DROP_OLD`; dropped messages counted
  via Task 6's counters.
- **Task 8 — `block_sender` policy.** Transitive backpressure: a sender
  parks until the target's mailbox drains below its low-water mark, instead
  of dropping. Review found and fixed 2 Critical bugs (waiter-list
  corruption under spurious wakes; a scheduler-thread self-deadlock at
  N=1) before landing.
- **Task 9 — `Actor.set_queue_limit` surface.** The March-facing API:
  `Actor.set_queue_limit(pid, limit, policy)` (`0` unbounded, `1` drop_new,
  `2` drop_old, `3` block_sender — the interpreter treats `3` as unbounded,
  since its single-threaded eager scheduler cannot park a sender without
  deadlocking).
- **Task 10 — process-registry/send-path locking.** Converted several
  plain cross-thread fields (`pid_index`, `green_thread`) to `_Atomic` with
  proper acquire/release pairing. Flagged (not fixed, out of diff scope)
  two pre-existing races later filed as follow-up todos at this close-out:
  `do_actor_death`'s unlocked `cleanup_head`/`monitor_head` mutation, and
  `march_actor_broadcast_migrate`'s dead-target message leak.
- **Task 11 — exit-path audit.** Verified every actor exit path (normal
  return, crash-trap, `kill`, supervisor-triggered) converges correctly on
  the hardened Task 10 primitives.
- **Task 12 — proc/VMA free-list.** Dead green-thread stacks recycle
  through a free-list instead of leaking, fixing unbounded VMA growth under
  churn (peak-concurrency cap, does not shrink — the "leak-don't-free"
  design item filed as distributed-plane follow-up item 5).
- **Task 12b — churn-hang root cause.** Diagnosed and fixed: the local
  work-stealing deque's bounded push was failing silently (return value
  never checked) and *dropping the runnable proc* — the actual mechanism
  behind Task 1's ~4,000-actor hang. Fixed by falling back to the global run
  queue on local-deque overflow. **This is the fix that flipped the churn
  gate from `EXPECTED_FAIL` to `PASS`** — first all-four-scenario clean run
  of the whole plan.
- **Task 13 — registry lifetime cliff.** Replaced the fixed
  `g_proc_registry[65536]` array (a program that had spawned 65536 procs
  *over its lifetime*, not concurrently, silently lost registry lookups for
  anything spawned after) with a growable, header-prefixed structure.
- **Task 14 — real dtor for dropped/overflowed messages.** Replaced the
  Task 7 "leaked-with-count" placeholder with an actual `march_decrc`-based
  disposer, restructured to dispose outside the mailbox spinlock per Task
  7's own forward-looking review note (avoiding a deadlock if the dtor
  re-enters the lock).
- **Task 15 — O(1) pid→meta lookup.** Fixed a Critical bug found in review
  (a pid-index double-insert on actor-pointer reuse could splice/cycle the
  side-table's chains) with a fresh-meta-on-reuse prepend design.
- **Task 16 — supervisor backoff.** Exponential backoff with jitter on
  repeat crashes of the same child slot: first crash restarts immediately
  (unchanged from pre-plan behavior); a streak > 1 delays
  `25 << min(streak-1, 7)` ms (50, 100, ... capped at 3200ms pre-jitter —
  the shift saturates at 7) ± 25% jitter (observed max ~4000ms), running on a
  dedicated green thread. Three review rounds fixed 2 Critical bugs
  (`g_supervise_mu` self-deadlock via `do_actor_death` re-entry; a mutex
  held across `swapcontext`) and 2 Important bugs (a ghost-timer blocking
  `wait_idle`; a `rest_for_one` widening gap that could strand a
  lower-index sibling). `MARCH_SUP_TRACE=1` prints each restart decision.
- **Task 17 (this task) — close-out.** Fixed 4 `test/native/*.march`
  fixtures broken by a concurrently-merged capability rule (main() needing
  an explicit `Cap(IO.Console)` parameter); full verification battery;
  this progress file; distributed-plane and runtime-race follow-up todos;
  `specs/lang/actors.md` + `docs/actors.md` + `specs/lang/supervision.md` +
  `docs/supervision.md` documentation for everything above; `CHANGELOG.md`
  audit (all entries already present under `[Unreleased]`, added none new).

## Deliberately out of scope

The plan's self-review scoped the **distributed plane** out of phase 1 from
the start: cross-node flow control, a control/data connection split,
`MONITOR_FIRE` delivery guarantees, declaration-site `mailbox N policy`
syntax, full epoch-based proc reclamation (vs. Task 12's peak-cap free-list),
and interpreter parity for the `block_sender` policy. Filed as
`specs/todos/2026-08-11-actor-hardening-distributed-plane.md`.

Three additional runtime races were found during review but were pre-existing
(not introduced by, and not required to fix as part of, the tasks that found
them) and are filed as individual follow-ups rather than fixed inline under
time pressure in a crash-isolation/concurrency-critical path:
`specs/todos/2026-08-12-do-actor-death-unlocked-cleanup-monitor-heads.md`,
`specs/todos/2026-08-12-send-checked-epoch-plain-cross-thread-read.md`,
`specs/todos/2026-08-12-broadcast-migrate-dead-target-message-leak.md`.
(Two related pre-existing races were already filed by Tasks 15/16:
`specs/todos/2026-08-12-supervised-child-registration-race.md` and
`specs/todos/2026-08-12-concurrent-first-crash-batch-restarts-unsynchronized.md`.)

## Verification

Full detail (suite output tails, benchmark numbers, snapshot check) is in
this task's report: `.superpowers/sdd/2026-08-11-actor-system-hardening/task-17-report.md`.
Summary: `dune build`, the full `scripts/run-tests.sh` suite (including Slow
tests), `dune build @test/runtest`, `scripts/actor-load.sh` (all four
scenarios `PASS`), `scripts/check-docs.sh`, and the TIR golden-snapshot suite
(`test/run_snapshots.exe`, unchanged — nothing in this plan altered TIR
shape) all green; `bench/binary_trees.march` and `bench/tree_transform.march`
run compiled without regression (direction-only comparison, per this
session's box being shared with other concurrent work).
