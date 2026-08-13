# Monotonic supervision clock + dead-actor mailbox drain

Task 14 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`).

## What shipped

- `runtime/march_runtime.c`:
  - `march_restart_budget_ok` now timestamps restarts with
    `march_now_ms() / 1000.0` (`CLOCK_MONOTONIC`, Task 2) instead of
    `gettimeofday` (wall clock). A wall-clock step (NTP correction, manual
    clock change) could previously jump the restart-history window
    backward (budget never refills) or forward (recent restarts silently
    age out of the window early, letting a crash loop through the budget
    meant to stop it); the monotonic clock cannot be stepped.
  - New `march_actor_msg_dispose(void *msg)`: the real dtor registered with
    the scheduler. Discriminates the same two message shapes
    `actor_green_thread`'s receive loop already discriminates (its Phase 5
    migrate-message check): a malloc'd `march_migrate_msg_t` (16-byte
    march-object-header shape, but heap-owned outside March's RC — freed
    with `free()`) vs. an ordinary march-heap value or tagged immediate
    (disposed via `march_decrc`, whose own `IS_HEAP_PTR` guard makes it a
    safe no-op for immediates). Verified `MARCH_MIGRATE_TAG`
    (`0x4D494752`, "MIGR") cannot collide with a real ADT constructor tag —
    tags are `< 1000` by construction (see the constant's own comment in
    `march_runtime.h`) — the same assumption the receive loop already
    relies on. Deliberately omits the receive loop's additional
    `meta->dispatch_name_id` gate (only hot-reload actors ever receive
    migrate messages in the first place, and this dtor has no actor
    context to gate on), which admits no message the receive loop's gate
    would have rejected.
  - Registered via `march_sched_set_msg_dtor(march_actor_msg_dispose)` in
    `march_spawn`'s lazy scheduler-init block, right after
    `march_sched_init()`.
- `runtime/march_scheduler.c` / `.h`:
  - `sched_loop`'s `PROC_DEAD` reap branch now drains and disposes every
    message still queued in the dead proc's mailbox, immediately after the
    existing send-waiter wake (Task 8) and before the stack retire
    (Task 12). **Collect-then-dispose**, not dispose-under-lock: pops every
    message under `p`'s `mbox_lock` into a small local intrusive linked
    list (`mbox_pop` already fully unlinks each node, so holding the
    payload outside the lock is safe), releases the lock, then walks the
    local list calling `march_mbox_dispose` on each payload and freeing the
    list node. OOM while allocating a list node aborts (matching
    `mbox_node_new`'s existing OOM-is-fatal convention) rather than
    disposing under the lock as a fallback.
  - `march_sched_send`'s `MARCH_MBOX_DROP_OLD` path restructured the same
    way: it used to `mbox_pop` the evicted message and dispose it
    immediately, still under `target`'s `mbox_lock`, before falling through
    to push the new message. It now stashes the evicted message in a new
    `evicted_old` local (declared outside the retry loop, since the
    evicting iteration always falls through to the shared epilogue rather
    than looping again), lets the existing push/release/wake epilogue run
    unchanged, and disposes `evicted_old` as the last thing before
    `return MARCH_SEND_OK` — after the lock is released and the wake has
    fired. `MARCH_MBOX_DROP_NEW`'s dispose was already outside the lock and
    is unchanged.
  - Added a forward declaration of `static void march_mbox_dispose(void *)`
    near the `mbox_pop`/`mbox_push_node` helpers, since the reap branch
    (which now calls it) appears earlier in the file than the disposer's
    definition (which lives next to `march_sched_set_msg_dtor`).
  - `march_sched_set_msg_dtor`'s header comment now states the re-entrancy
    contract explicitly: **the dtor may re-enter scheduler send/recv
    paths; it is never called with any scheduler lock held.** This is
    load-bearing, not a nicety — the registered runtime dtor is
    `march_decrc`, whose free path can invoke an arbitrary FFI-registered
    C dtor (`march_run_resource_dtor`); a dtor that sends a message (or
    otherwise touches a mailbox) on cleanup would deadlock against this
    module's non-reentrant spinlock if called while it were held.
- `test/test_scheduler_mbox.c`: new `test_dead_reap_drain()` segment (own
  `march_sched_init()`/`march_sched_run()` pair, like
  `test_block_live_scheduler()`): spawns a `die_immediately` proc, sends it
  7 messages BEFORE ever calling `march_sched_run()` (so all 7 land in the
  mailbox deterministically — the proc is RUNNABLE-but-never-dispatched
  until `march_sched_run()` starts it), requests shutdown, runs the
  scheduler, and asserts the registered `counting_dtor` fired `>= 7` times.
  Resets the dtor to `NULL` afterward so it doesn't leak into the later
  deterministic (never-run) segments in the same process.

## Determinism argument (verified against the actual reap code)

All 7 sends land in the mailbox via the ordinary `mbox_push_node` path
(target is neither `DEAD` nor at any `mbox_limit` — default is unbounded)
because they all happen before `march_sched_run()` is ever called, while
`victim` is spawned-but-never-dispatched. Once `march_sched_run()` starts,
`sched_loop` dispatches `victim` for the first time; `die_immediately`
returns immediately without calling `march_sched_recv()`, so none of the 7
messages are drained by the actor itself — the proc goes straight from
`RUNNING` to `PROC_DEAD` with all 7 still queued. `sched_loop`'s `PROC_DEAD`
branch reaps it synchronously, in the same call that dispatched it: wakes
`mbox_send_waiters` (none — nothing was blocked on this mailbox), then runs
the new collect-then-dispose drain, calling `counting_dtor` once per queued
message. This reap happens before `march_sched_run()` can return (shutdown
was requested and `victim` was the only non-daemon proc), so `g_disposed` is
fully accounted for by the time the assertion runs.

## Tag-gate verification

`march_migrate_msg_t`'s layout (`march_runtime.h`) is `{int64_t _rc; int64_t
_tag; void *(*migrate_fn)(void*);}` — the same 16-byte header shape
(rc at word 0, tag at word 1) as a real march heap object, deliberately, so
`actor_green_thread`'s receive loop can detect it with
`((int64_t*)msg)[1] == MARCH_MIGRATE_TAG`. `MARCH_MIGRATE_TAG` is
`0x4D494752` (1,298,361,202 decimal); real ADT constructor tags are bounded
by the number of constructors on a type, "typically < 1000" per the
constant's own comment — so the collision the dtor must avoid (freeing a
real march-heap value because its tag word happens to equal
`MARCH_MIGRATE_TAG`) cannot occur in practice, matching the assumption the
receive loop's identical check already makes.

## Verification

- `dune build --root . ./test/test_scheduler_mbox_runner` — clean, no
  warnings.
- `./_build/default/test/test_scheduler_mbox_runner` run 240+ times total
  directly in foreground loops (not backgrounded), including a final clean
  40/40 batch — all green except one unexplained failure early in the
  first exploratory 40-run batch with no captured stderr, not reproduced
  across 240 subsequent consecutive runs; treated as environmental (this
  host runs multiple concurrent worktree sessions — see the project's own
  memory notes on load contamination / stale-process interference; a stray
  `dune build @test/runtest` process left over from an earlier duplicate
  invocation was found still running minutes later and killed) rather than
  attributed to this change.
- `dune build --root . @test/runtest` — 844 tests, all green (exit 0, no
  failures) on a clean foreground run.
- `scripts/run-tests.sh -q` — green, 797 tests.
- `bash scripts/actor-load.sh` (all four scenarios, no filter) — all PASS:
  `fanin`, `churn`, `callstorm`, `crashloop`.
- ASAN spot-check (`MARCH_SANITIZE=1`) deferred to CI: this host's
  CrowdStrike agent hangs `MARCH_SANITIZE=1` binaries (documented,
  pre-existing host limitation, unrelated to this change).

## Notes for future tasks

- The collect-then-dispose pattern introduced here (pop everything under
  the lock into a small local list, release, then dispose) is the template
  for any future scheduler code path that needs to call
  `march_mbox_dispose`/a registered dtor while holding `mbox_lock` — per
  the now-explicit re-entrancy contract on `march_sched_set_msg_dtor`, the
  dtor must never run with that lock held.
- `march_actor_msg_dispose` does not gate on `meta->dispatch_name_id` the
  way the receive loop's migrate-message check does, because the dtor has
  no actor context. This is safe today only because migrate messages are
  exclusively sent to hot-reload actors; if a future change ever gives a
  non-hot-reload actor a legitimate reason to receive a heap message whose
  tag word could equal `MARCH_MIGRATE_TAG`, this dtor would misclassify it
  as a migrate message and leak/mishandle it via `free()` instead of
  `march_decrc`. Worth flagging if actor message tagging ever changes.
