# `block_sender` mailbox policy — transitive backpressure via sender parking

Task 8 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`).

## What shipped

- `runtime/march_scheduler.h`: `march_proc` gains two new fields —
  `mbox_send_waiters` (intrusive singly-linked list of sender procs parked
  on THIS proc's full mailbox, read/written only under this proc's own
  `mbox_lock`) and `send_wait_next` (the intrusive link, deliberately a
  dedicated field rather than reusing `p->next`, which is the global-runq
  link — a blocked sender gets pushed to the runq by `march_sched_wake`
  while still logically "in" the waiter list at the moment the wake fires,
  so sharing one field would corrupt both lists).
- `runtime/march_scheduler.c`:
  - `mbox_take_waiters_if_low(p)`: called under `p`'s own `mbox_lock`
    immediately after a successful `mbox_pop`. If the pop just crossed the
    low-water mark (`count <= limit/2`), unlinks and returns the WHOLE
    waiter list (level-triggered, not edge-triggered — safe because the
    list is empty after the first successful take, so redundant qualifying
    pops are no-ops).
  - `mbox_wake_waiters(list)`: walks a taken list and calls
    `march_sched_wake` on each entry, wake-all not wake-one (each waiter
    re-checks capacity in its own retry and re-parks if it lost the race;
    the herd is bounded by the waiter count). Must run AFTER the caller
    releases `mbox_lock`.
  - Both are wired into every mailbox-drain call site: `march_sched_recv`
    (both its fast-path pop and its post-wake pop), `march_sched_try_recv`,
    `march_sched_try_recv2`, and `march_sched_recv_until` (both its
    pre-park pop and its post-wake pop) — six sites total. The seventh
    `mbox_pop` call site, `MARCH_MBOX_DROP_OLD`'s eviction inside
    `march_sched_send`, is deliberately excluded: it pops one message and
    then immediately pushes the new one back in the same critical section,
    so mailbox depth is net-unchanged and can never cross the low-water
    mark.
  - `march_sched_send`'s `MARCH_MBOX_BLOCK` case (previously `default:`
    fall-through from Task 7) now delegates to a new dedicated
    `static __attribute__((noinline)) int mbox_block_register_and_park
    (march_proc *target)` helper (mailbox lock already held by the caller;
    the helper always releases it, on every return path). Foreign threads
    (no `tl_sched->current`) sleep-poll at 1ms; green threads register into
    `target->mbox_send_waiters`, release the lock, and park.
    `march_sched_send` itself is a `for (;;)` loop (not the brief's literal
    recursive `return march_sched_send(...)` retry — see deviation note
    below) that calls this helper once per retry and `continue`s.
  - Dead-during-registration race: the helper rechecks
    `target->status == PROC_DEAD` UNDER THE LOCK, immediately before
    registering, and bails out with `MARCH_SEND_DEAD` instead of
    registering if so. This closes a lost-wakeup window distinct from the
    "ordinary" one: if the target died and was already reaped (see below)
    BEFORE this proc reached `mbox_lock_acquire`, blindly registering would
    park with no one left to ever wake it (`PROC_DEAD` is terminal — reap
    runs at most once). The recheck is race-free because `mbox_lock_acquire`
    (`memory_order_acquire`) synchronizes-with the reap branch's
    `mbox_lock_release` (`memory_order_release`), which transitively makes
    the reaped proc's earlier `status = PROC_DEAD` store (same thread,
    program order, before the reap's own lock acquire) visible. If the
    target dies AFTER registration instead, the ordinary `wake_pending`
    permit handshake (identical in shape to `march_sched_recv`'s existing
    park sequence) covers it — no special-casing needed.
  - `sched_loop`'s `PROC_DEAD` reap branch now also drains and wakes the
    dead proc's `mbox_send_waiters` under its own `mbox_lock`, so senders
    parked waiting for a target that died un-park and observe `DEAD` on
    retry instead of hanging forever.
- `test/test_scheduler_mbox.c`: new `test_block_live_scheduler()` (2 tx
  procs racing to send 1000 messages each to a `MARCH_MBOX_BLOCK`-limited
  (limit 16) rx proc; asserts nothing dropped, everything arrived, and peak
  observed depth stayed within `limit + 2`). Runs FIRST in `main()`, in its
  own `march_sched_init()`/`march_sched_run()` pair — it's the only segment
  that needs a live, running scheduler — before the pre-existing
  deterministic (never-run-scheduler) segments, which still start from a
  fresh `march_sched_init()` and are unaffected by the reordering (the
  `MARCH_STAT_MSGS_DROPPED` delta discipline in `test_drop_old` already
  reads before/after within its own segment, so it doesn't care what ran
  earlier in the process).

## A genuine, hard-to-find concurrency bug found and fixed along the way

The stress-test loop (40+ direct runs) surfaced a real deadlock at roughly a
1-in-5 to 1-in-10 rate on this 4-scheduler build — NOT the lost-wakeup shape
anticipated by the brief's audit, but a `_Thread_local` (`tl_sched`)
loop-invariant-code-motion hazard already known to this codebase (see
`march_sched_yield`'s own `noinline` comment, fixed for a different
call site during the original green-thread scheduler work): nothing in
`march_sched_send`'s retry loop, nor in `march_sched_park_self`'s body
(even un-inlined, visible whole to the optimizer within the same
translation unit), ever WRITES `tl_sched` — that write only happens in
`sched_loop`, on whatever OS thread later resumes the parked green thread,
invisible to this function's dataflow. clang -O2 is therefore free to treat
`tl_sched` as loop-invariant for the ENTIRE `march_sched_send` activation
and hoist the sender's `self = tl_sched->current` read out of the `for(;;)`
loop entirely, reusing the pre-migration thread's stale scheduler/proc
pointer on every later retry. That stale `self` then re-registered itself
into a target's `mbox_send_waiters` list whose own prior entry was never
removed, forming a self-referential cycle (`self->send_wait_next == self`)
that no drain-side wake could ever fully unwind — the deadlock.

Marking `march_sched_park_self` itself `noinline` (matching its siblings
`march_sched_recv`/`march_sched_recv_until`) was an insufficient first
attempt: it only stops the compiler from merging park_self's OWN internal
`tl_sched` read into an inlining caller (the mechanism that mattered for the
original `march_sched_yield`/`march_sched_wait_idle` bug). It does nothing
about a read that lives directly in the CALLER's own loop body, which is
what `march_sched_send` had. The fix that actually worked follows the
established pattern exactly: push the `tl_sched` read into a dedicated
`static __attribute__((noinline))` helper
(`mbox_block_register_and_park`) that the loop calls FRESH every
iteration, so every iteration crosses a real, opaque call boundary the
optimizer cannot hoist a TLS read across.

Confirmed via two independent pieces of evidence before landing the fix:
(1) a minimal standalone `ucontext_t` + `pthread` reproducer showing a
`_Thread_local` read staying stuck at its first-resolved value across
repeated cross-thread `swapcontext` resumes, while `pthread_self()`
correctly tracked the real current thread (ruling out a simpler ARM64/x18
register-corruption theory — that reproducer showed `pthread_self()` and
TLS staying CONSISTENT across one migration, which is what sent the
investigation looking for a compiler-level cause instead); and (2) the
original (insufficient) `noinline`-on-`park_self`-only build still
deadlocking on attempt 1 of a fresh 20-run stress loop, forcing the deeper
LICM diagnosis. `-DMARCH_DEBUG`'s `dbg_queued`/`dbg_running_on`
single-membership tripwire never fired in any repro, confirming the bug was
entirely within the new `mbox_send_waiters` list — a structure the
tripwire has no visibility into — not a violation of the pre-existing
run-queue dispatch invariant.

## Deviation from the brief

The brief's snippet used a literal recursive
`return march_sched_send(target, msg);` retry for both the green-thread and
foreign-thread `MARCH_MBOX_BLOCK` paths. Converted to a `for (;;)` loop with
`continue` instead: BLOCK's park/wake cycle can repeat an unbounded number
of times under sustained backpressure (each retry is a genuine tail call,
but C gives no TCO guarantee), and a green thread's initial stack is only
`MARCH_STACK_INITIAL` (4 KiB) — an unbounded recursion depth on a
pathological sender herd would risk exhausting it before the lazy
stack-growth guard page ever gets a chance to react. Behavior is otherwise
identical to the brief's design.

## Verification

- `dune build bin/main.exe --root .` — clean.
- `dune build @test/runtest --root .` — all 844 tests green.
- `./_build/default/test/test_scheduler_mbox_runner` run 80x directly in a
  foreground loop (not backgrounded) — 80/80 pass after the LICM fix; the
  pre-fix build failed at roughly 1-in-5 to 1-in-10 across multiple
  independent stress runs.
- `scripts/run-tests.sh -q` — green (see task report for the
  concurrent-session contention caveat already on file from Tasks 6/7: this
  host runs multiple worktree sessions in parallel).

## Notes for future tasks

- Task 14 (real message dtor): unaffected by this task — `MARCH_MBOX_BLOCK`
  never drops a message (delivery is guaranteed), so there is nothing new
  for the disposer hook to handle here.
- The `mbox_block_register_and_park` / `march_sched_yield` noinline
  discipline (push any post-migration `tl_sched` read into its own
  noinline function, called fresh per loop iteration) is now demonstrated
  twice in this file. Any FUTURE code that calls a park/wake primitive from
  inside a loop and then reads `tl_sched` (directly or via `self`/`p`
  derived from it) again on a later iteration needs the same treatment —
  worth calling out explicitly in the CLAUDE.md scheduler notes if a Task 9+
  touches this file again.
