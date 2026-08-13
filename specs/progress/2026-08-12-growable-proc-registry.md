# Growable proc registry (65536-pid cliff removed) + loud spawn failure

Task 13 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`).

## Context this task inherited

The brief's Step 1 anticipated the 70000-spawn C segment possibly hanging,
citing a churn deadlock as the worry. That deadlock is already fixed (Task
12b, commit `13cebbe9`: local-deque overflow now falls back to the global
run queue), and the churn harness gate passes on current code. So the
70000-spawn segment was expected to run to completion even with the OLD
fixed-size registry — the observable defect is `march_sched_find` semantics
and `wait_idle`/`wake_idle_daemons` blindness for pid >= 65536, not a hang.

Confirmed empirically: ran the new test segment against the pre-existing
fixed-array code first (temporarily, not committed) — it completed without
hanging, and `march_sched_find(69999)` returned `NULL` after reap (same
outcome the growable-registry code produces), because the fixed array
already stored `NULL` at every out-of-range write attempt via its `if
(pid < MARCH_MAX_PROCS)` guard — the negative assertion alone doesn't
distinguish old from new code. The real regression witness is the added
*positive* assertion, `march_sched_find(69000) != NULL` taken **while the
proc is still alive** (spawned but not yet run) — on the old fixed array
this also happened to pass for pid 69000... no: 69000 >= 65536, so the old
`registry_add`'s guard `if (p->pid < MARCH_MAX_PROCS)` skipped the store
entirely, leaving the slot never populated, so `march_sched_find(69000)`
returned `NULL` even while alive under the OLD code — that is the actual
old/new behavioral divergence the positive assertion pins down.

## The fix

`runtime/march_scheduler.c`:

- Replaced the fixed `static march_proc *g_proc_registry[65536]` with a
  single header-prefixed allocation behind one atomic pointer:
  ```c
  typedef struct { int64_t cap; march_proc *slots[]; } march_registry;
  static _Atomic(march_registry *) g_registry = NULL;
  ```
  `MARCH_MAX_PROCS` (65536) is kept only as the initial/floor capacity for
  growth, not a hard limit.
- `registry_add` (under `g_registry_mu`): if the registry doesn't exist yet
  or `pid >= cap`, allocates a new array sized
  `max(2*old_cap, pid+1, MARCH_MAX_PROCS)`, `memcpy`s the old slots in,
  zeroes the rest, release-stores the new pointer, and **leaks the old
  array** — deliberately, matching the leak-don't-free discipline already
  used for retired procs. Doubling caps the leak count at O(log2(max pid)).
- `registry_remove` (under `g_registry_mu`): NULLs the slot if `pid < cap`
  of the currently-loaded registry.
- Every registry reader now follows the same pattern — load the pointer
  once, bound every index by *that snapshot's own* `cap`:
  - `march_sched_find` — unlocked, acquire load. Never took a lock before
    either; unchanged risk profile, now growth-safe via the embedded cap.
  - The `MARCH_DEBUG` SIGSEGV-handler fatal-fault walker — unlocked,
    acquire load, because it runs in **signal context** and cannot take
    `g_registry_mu`. This is exactly the reader the leak-don't-free
    discipline exists for: a growth racing this handler must never leave
    it holding a freed pointer.
  - `wake_idle_daemons` and `march_sched_wait_idle` — still hold
    `g_registry_mu` for the walk-vs-free race against `registry_remove`
    (unchanged from before), so their pointer load uses relaxed ordering
    (the mutex already provides the needed visibility) rather than
    acquire.
- `march_sched_init`: re-init no longer does `memset(g_proc_registry, 0,
  sizeof(...))` (that array no longer exists). It reuses whatever
  allocation growth already produced — freeing on re-init would race any
  unlocked reader still holding the old pointer, and the leak-don't-free
  discipline already accepts these allocations living for process
  lifetime — and instead zeroes just the slots (`memset(r->slots, 0,
  cap * sizeof(march_proc*))`) so every pid looks unregistered again. On
  the very first `march_sched_init()` call in a process, `g_registry` is
  still `NULL`; the first `registry_add` allocates lazily.
- `sched_spawn_common`'s two failure returns (`stack_alloc` NULL,
  `getcontext` fail) now each bump
  `march_stat_counters[MARCH_STAT_STACK_FAIL]` (Task 6's counter slot,
  index 3) before returning `NULL`.

`runtime/march_runtime.c` (`march_spawn`): captures
`march_sched_spawn_daemon`'s return value before the existing atomic
release-store, and if it's `NULL`, emits a one-shot stderr warning (via a
static `_Atomic int warned` flag + `atomic_exchange`, no lock needed since
`march_spawn` holds none here):

```
march: FAILED to start actor green thread (stack allocation) — this actor
will drop all messages; see Scheduler.stat(3)
```

## Test

`test/test_scheduler_churn.c` — added a fourth segment: spawns 70000 tiny
procs from `main` (a non-scheduler thread, so every spawn lands on the
global run queue and none of them execute until `march_sched_run()` is
called), asserting `march_sched_find(69000) != NULL` while every proc is
still alive (a pid comfortably above the old 65536 cliff), then
shuts down and runs to quiescence, then asserts
`march_sched_find(69999) == NULL` (reaped and removed, not merely never
seen). `alarm(120)` resets the file's watchdog for this segment alone
(`alarm()` overwrites rather than adds to the pending timer).

Measured: the full 70000-spawn segment runs in well under a second
(the whole 4-segment binary — including the pre-existing 3000+100 stack-
recycling segment and the 5000-burst local-deque-overflow segment — completes
in ~0.2s user / 0.7s system, ~0.8s wall on an idle box), so no watchdog
tension; `alarm(120)` is generous headroom, not a tight fit.

## Verification

- `dune build @test/runtest --root .` — full suite green (844 OCaml tests;
  the C `test_scheduler_churn_runner` runs under the same alias and passed).
- `./_build/default/test/test_scheduler_churn_runner` run 5x standalone —
  all 5 passed, no flakiness observed.
- `scripts/run-tests.sh -q` — green.
- `bash scripts/actor-load.sh` — all four scenarios PASS, including
  `churn` (previously listed in `EXPECTED_FAIL` per the Task 12b writeup;
  confirmed still passing, no `EXPECTED_FAIL` entry needed removal beyond
  what Task 12b already did).
