# Green-thread scheduler: Go-style single-owner run-queue fix

**Goal:** Make it structurally impossible for two scheduler OS-threads to run the
same `march_proc` (green thread) at the same time, eliminating the intermittent
memory-unsafe stack-corruption crash that surfaces under actor kill+respawn churn
at `MARCH_NUM_SCHEDULERS > 1`.

**Approach:** Adopt the Go runtime's invariant — *a runnable process is in exactly
one run queue, and is claimed by an atomic state transition before any thread
executes it* — and enforce it at the enqueue side (so double-enqueue cannot
happen) rather than papering over it at the dispatch side (which is what the
reverted `READY→RUNNING` CAS attempt did, trading crashes for hangs). Keep the
per-scheduler Chase-Lev work-stealing deques for cache locality; add a
thread-safe global run queue for every cross-thread enqueue; forbid cross-thread
deque pushes entirely.

**Files:** `runtime/march_scheduler.{c,h}` only. `runtime/march_deque.h` is
correct as-is and is not modified (the bug is *misuse*, not the deque).

---

## Global Constraints

- Verify every C change with an ACTUAL forced clang compile
  (`march --compile`), never just `dune build bin/main.exe` (which only checks
  the OCaml).
- The stress gate for every task is the real repro at `MARCH_NUM_SCHEDULERS=4`
  **and** `=8`: `examples/supervision_strategies.march` (and the minimal
  `kill_respawn_race2.march`) run ≥200×, zero crashes/hangs. A change that builds
  and passes the alcotest suite but is not stress-clean at N>1 is NOT done.
- The full six-runner suite (`scripts/run-tests.sh`) must stay green.
- Do not free `march_proc` structs (the existing leak-don't-free decision stands
  — a stale-but-allocated proc correctly reads `PROC_DEAD`; this fix relies on
  that, see §Invariants).
- No `Co-Authored-By`; explicit `git add` by name; build with `dune build --root .`.

---

## Background: why the current design is violable

A `march_proc` has one mmap'd machine stack and one saved `ucontext`. The hard
invariant is: **at most one OS thread may `swapcontext` into a given proc at a
time.** Two threads on one stack corrupt each other's spilled registers and
frames — observed as `sched_loop`'s own `sched` parameter reading back as
near-NULL garbage, then a wild deref.

Today `march_proc.status` (`_Atomic march_proc_status`) is doing double duty: it
tracks lifecycle *and* is the only thing standing between "runnable" and "in a
run queue." Two structural weaknesses follow:

1. **Dispatch is an unconditional store, not a claim.** `sched_loop` does
   `atomic_store(&p->status, PROC_RUNNING)` then `swapcontext`. If the same proc
   is reachable from two places, both threads store `RUNNING` and both
   `swapcontext` in. Nothing atomically arbitrates "I, and only I, may run this."

2. **Cross-thread deque pushes exist.** Chase-Lev deques are single-owner for
   push/pop; only *steal* is a sanctioned cross-thread read. But
   `march_sched_wake` does `march_deque_push(&g_scheds[0].local_queue, target)`
   in its `else` branch (waker not inside a scheduler), which is a cross-thread
   push into scheduler 0's deque — a Chase-Lev contract violation that can
   corrupt `bottom` against scheduler 0's concurrent pop, and corrupted deque
   state can hand the same item to both a `pop` and a `steal` (→ double-dispatch).

The confirmed double-dispatch (caught live 2/40 by a CAS detector) is one or both
of these. The fix below makes the *exact* current culprit moot by construction:
enqueue becomes single-winner and cross-thread pushes are removed, so no proc can
ever be in two queues, so no two threads can ever claim it.

---

## The invariant (the whole design in one paragraph)

> A `march_proc` is in **at most one** run structure (one scheduler's local deque,
> or the global run queue) at any instant. Membership is authorized by exactly one
> atomic CAS *into* the `RUNNABLE` state; only the thread that wins that CAS
> performs the enqueue. A scheduler runs a proc only after winning a CAS
> `RUNNABLE → RUNNING`; because a runnable proc is single-membership, that CAS
> can fail only for a genuinely stale reference (never a live duplicate), so the
> loser safely drops it. `WAITING`, `PARKED`, `RUNNING`, and `DEAD` procs are in
> no run structure.

Everything below is bookkeeping to uphold that paragraph at each site.

---

## State model

Reuse the existing enum; give the states precise queue-membership meaning. Only
one rename (`READY → RUNNABLE`) plus tightened transition rules — no new struct
fields except the global-runq plumbing.

| State           | In a run queue? | Meaning                                                              |
|-----------------|-----------------|---------------------------------------------------------------------|
| `PROC_RUNNABLE` | **yes, exactly one** | Enqueued, waiting for a CPU. Entered only by a CAS that authorizes the enqueue. |
| `PROC_RUNNING`  | no              | Claimed by one scheduler; that scheduler is `swapcontext`-ed into it. |
| `PROC_WAITING`  | no              | Parked on `recv`, context saved. A waker moves it `WAITING→RUNNABLE`. |
| `PROC_PARKED`   | no              | Transient: `recv` set it, `swapcontext` not yet returned to the scheduler. Wakers spin until it becomes `WAITING`. |
| `PROC_DEAD`     | no              | Finished. Never re-enqueued.                                        |

**Authorized enqueue transitions** (the CAS winner, and only it, enqueues):

- `NEW → RUNNABLE` — at spawn.
- `WAITING → RUNNABLE` — at wake (message arrival, kill-wake, shutdown daemon wake).
- `RUNNING → RUNNABLE` — at yield (uncontended: only the running proc itself does this, on its own scheduler thread).

**The claim transition** (dispatch): `RUNNABLE → RUNNING`, CAS, in `sched_loop`
after obtaining a reference from any queue. Win → `swapcontext`. Lose → drop.

---

## The global run queue (cross-thread enqueue path)

Chase-Lev local deques stay, but **every cross-thread enqueue goes to a global
run queue instead of pushing into another thread's deque.** Generalize the
existing lock-free external-spawn stack (`g_ext_spawn_head`, a Treiber stack over
the free `march_proc.next` intrusive link) into the single global runq:

- Rename `g_ext_spawn_head → g_global_runq_head` (Treiber stack, push via CAS on
  `p->next`, pop via CAS on the head). It is already MPMC-safe.
- **Producers:** any authorized enqueue whose executing thread is *not* the proc's
  intended local owner, OR is not a scheduler thread at all, pushes here. Simplest
  correct rule: **wake and non-scheduler spawn always use the global runq; only
  same-thread enqueues (yield-repush, spawn from within a scheduler) use the local
  deque.** (Optional later optimization: a scheduler waking a proc may push to its
  *own* local deque, since that is an owner-push — but start with "cross-thread →
  global" for simplicity and correctness.)
- **Consumers:** `sched_loop`, when its local deque and steals come up empty,
  drains one proc from `g_global_runq_head` (the drain loop already exists for
  ext-spawn; it stays, just renamed). This is the correct cross-thread hand-off:
  producers never touch a consumer's deque.

Note: `march_proc.next` is documented as "unused with deque, kept for compat" —
it is exactly the intrusive link this Treiber stack needs, so no new field.

Chase-Lev **steal** is unchanged and remains the only cross-thread deque
operation — it is contract-legal (steal from `top`) and correct.

---

## Per-site changes

Each row states the new behavior; all transitions into `RUNNABLE` are CAS and gate
the enqueue.

| Site (`march_scheduler.c`) | Change |
|---|---|
| `sched_spawn_common` (~411) | Create as `PROC_RUNNABLE`. If `tl_sched` (inside a scheduler): local `march_deque_push`. Else: push to `g_global_runq_head` (unchanged path, renamed). |
| `sched_loop` claim (~666) | Replace `atomic_store(RUNNING)` with **CAS `RUNNABLE → RUNNING`**. On success: set `reductions`, `owner_sched`, `current`; `swapcontext`. On failure: `continue` (stale ref; safe to drop — see Invariants). |
| `sched_loop` post-swap `PROC_READY` branch (~679) | Rename to `RUNNABLE`. The proc yielded (it CAS'd `RUNNING→RUNNABLE` in `yield`); re-push to **this scheduler's own** local deque (same-thread, legal). |
| `sched_loop` post-swap `PROC_PARKED` branch (~683) | Unchanged in spirit: store `WAITING` (publishes "context saved" to spinning wakers). Not enqueued. |
| `march_sched_yield` (~711) | CAS `RUNNING → RUNNABLE` (uncontended), then `swapcontext` to sched. The scheduler re-enqueues locally (row above). |
| `march_sched_recv` (~818) | Unchanged: under `mbox_lock`, if mailbox non-empty pop+return; else store `PROC_PARKED`, release, `swapcontext`. (The lock already closes the lost-wakeup window with `send`.) |
| `march_sched_wake` (~876) | Spin while `PARKED` (unchanged). Then **CAS `WAITING → RUNNABLE`**; only the winner enqueues, and it enqueues to **`g_global_runq_head`** (never a cross-thread deque push). Delete the `g_scheds[0]` deque-push branch entirely. |
| `march_sched_send` (~805) | Unchanged: `mbox_push` under lock; if target `WAITING`/`PARKED`, call `wake`. |
| `march_sched_exit` (~755) | Unchanged: store `PROC_DEAD`, `swapcontext`. Never re-enqueued. |
| `wake_idle_daemons` (~500) | Unchanged (it calls `march_sched_wake`, which now routes through the global runq). |

---

## Why "drop on claim-CAS failure" is safe now (it wasn't in the reverted attempt)

The reverted attempt CAS'd at dispatch but left double-*enqueue* intact, so a
proc could be in two queues; dropping one reference on CAS-loss dropped a proc
that nothing else would re-run → hang.

Under this design a runnable proc is in **exactly one** queue (single-winner
enqueue). Therefore, once a scheduler pops/steals/drains a reference, **no other
thread holds a reference to that proc.** The `RUNNABLE → RUNNING` CAS can then
fail only if the proc is no longer `RUNNABLE` — which, for a single-membership
proc that this thread just dequeued, cannot happen in correct operation.

So the claim CAS is a *backstop that should never fire.* Make its failure a
`MARCH_DEBUG`-gated assert/log: if it ever fires, the single-membership invariant
was violated and we have caught a real bug at the moment it happens, instead of a
corrupted stack minutes later. In release builds the failure path is just
`continue` (defensive, harmless).

---

## Edge cases (each must be walked in review)

1. **Park/wake handoff.** `recv` sets `PARKED` under `mbox_lock`; a concurrent
   `send` under the same lock either sees a non-empty mailbox (no park) or sees
   `PARKED` and wakes. `wake` spins until the scheduler publishes `WAITING`, then
   CAS `WAITING→RUNNABLE`. Single winner, single global-runq enqueue. No lost
   wakeup, no double-enqueue.
2. **Two concurrent senders to a parked proc.** Both `mbox_push`; both `wake`;
   both spin to `WAITING`; both attempt CAS `WAITING→RUNNABLE`; exactly one wins
   and enqueues. Loser returns.
3. **Kill-wake racing a message-wake.** Same as (2): both are `WAITING→RUNNABLE`
   CAS attempts; one wins. The proc runs once, drains its mailbox, and re-parks or
   exits.
4. **Yield racing an external wake.** A `RUNNING` proc is not `WAITING`, so `wake`
   sees `RUNNING` and returns without touching it. The proc's own
   `RUNNING→RUNNABLE` yield transition is uncontended. No overlap.
5. **Steal racing local pop.** Unchanged Chase-Lev guarantee: `pop` and `steal`
   of the last element arbitrate via the `top` CAS; exactly one returns the proc.
   (This only held before when the deque was uncorrupted — which the "no
   cross-thread push" rule now guarantees.)
6. **Shutdown daemon wake.** `wake_idle_daemons` wakes parked daemons via
   `march_sched_wake` → global runq; a scheduler drains and runs them so their
   loops exit. Unchanged semantics.
7. **`main` runs as a green thread on scheduler 0.** So `send`/`kill` from `main`
   execute with `tl_sched == g_scheds[0]`; wakes still route to the global runq
   (per the "wake always global" rule), so there is no owner/non-owner ambiguity.
8. **Reduction preemption (SIGUSR1).** Untouched — it only zeroes a thread-local
   counter, causing a cooperative `yield` at the next tick, which flows through
   the `RUNNING→RUNNABLE` path above.

---

## What explicitly does NOT change

- `march_deque.h` (Chase-Lev push/pop/steal internals) — correct as written.
- Reduction-based cooperative preemption and the `SIGUSR1` daemon.
- The lazy stack-growth `SIGSEGV`/`sigaltstack` machinery.
- Leak-don't-free proc lifecycle, the mailbox spinlock, the `crash_jmp` trap, and
  the four already-landed race fixes (mailbox lock, proc-lifecycle no-free,
  `meta->supervisor` lock, sanitizer fiber annotations) — this fix composes with
  all of them.

---

## Task breakdown (each ends stress-clean at N=4 and N=8)

- **Task 1 — rename + tighten states.** `PROC_READY → PROC_RUNNABLE` across the
  file; document the queue-membership meaning in the enum. No behavior change yet.
  Gate: builds (forced compile), suite green.
- **Task 2 — global run queue.** Rename `g_ext_spawn_head → g_global_runq_head`;
  confirm spawn-from-non-scheduler and the `sched_loop` drain both use it. No
  behavior change yet (pure rename + comment). Gate: builds, suite green,
  stress-clean at N=1 (baseline).
- **Task 3 — kill the cross-thread deque push.** In `march_sched_wake`, replace
  both push branches with a single `g_global_runq_head` push, gated on the
  `WAITING→RUNNABLE` CAS winner. Gate: builds; stress the repro at N=4 — expect a
  large crash-rate drop even before Task 4 (this removes the Chase-Lev violation).
- **Task 4 — single-winner enqueue + claim CAS.** Convert spawn/yield enqueues to
  the authorized-CAS discipline; convert `sched_loop` dispatch to
  `RUNNABLE→RUNNING` CAS with the debug-assert backstop. Gate: **200× clean at
  N=4 and N=8** on both the demo and the minimal repro; full suite green;
  `MARCH_SANITIZE=thread` shows no new races on the sched paths (the known benign
  Chase-Lev fence false-positives remain).
- **Task 5 — flip the default + close the finding.** Once Task 4 is stress-clean,
  set the compile-time default back to `MARCH_NUM_SCHEDULERS = 4` (or keep 1 with
  4 opt-in — decide with maintainer), add `examples/supervision_strategies.march`
  as a native golden, mark the `specs/todos.md` scheduler finding FIXED, update
  `specs/progress.md`. Gate: golden `verify.sh`, six-runner suite, `check-docs.sh`.

---

## Verification harness (already built this session, reuse it)

- The minimal repro `kill_respawn_race2.march` and the full 3-strategy demo.
- ASan + TSan fiber-switch annotations are wired (`MARCH_SANITIZE=thread`); use
  TSan to confirm no *new* sched races and ASan for heap/stack overflow.
- Keep the double-dispatch detector (an `_Atomic` "currently dispatched by
  scheduler N" tag CAS'd around `swapcontext`) available behind `MARCH_DEBUG` as a
  permanent regression tripwire — in the fixed design it must never fire.
- Stress loop: N ∈ {2,4,8}, ≥200 runs each, count `exit==0` vs crash vs 4s-hang.

---

## Alternative considered (simpler, lower ceiling): one global mutex run queue

Drop the Chase-Lev deques entirely; use a single mutex-protected global run queue
(all schedulers pop under the lock). This makes double-enqueue and cross-thread
push *trivially* impossible and is the smallest provably-correct design, but it
serializes scheduling and discards the existing work-stealing performance work.
Recommended only as a fallback if the invariant design above proves hard to land;
the Go-style local-deque-plus-global-runq design keeps the parallelism the deques
were built for.

---

## Risk notes

- **Highest-scrutiny area.** This is the actor/scheduler concurrency core; a
  wrong memory-order or a missed transition reintroduces exactly the class of bug
  we are fixing. Every task's gate is *stress-clean at N>1*, not just "builds."
- **Memory ordering.** Enqueue CAS: `acq_rel`. Claim CAS: `acq_rel`. Global-runq
  Treiber push/pop: `acq_rel`/`acquire` (as the existing ext-spawn stack already
  uses). The deque's own fences are unchanged.
- **Fairness/perf.** Routing all wakes through the global runq adds mild
  contention vs. local-deque wakes. Acceptable for correctness-first; the
  "scheduler wakes to its own deque" optimization (owner-push) can be added later,
  behind the same invariant, once N>1 is proven stable.
