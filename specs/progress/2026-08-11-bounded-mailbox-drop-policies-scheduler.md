# Bounded mailbox capacity + drop_new/drop_old overflow policies

Task 7 of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`).

## What shipped

- `runtime/march_scheduler.h`: `march_mbox_policy` enum
  (`MARCH_MBOX_UNBOUNDED`=0, `MARCH_MBOX_DROP_NEW`=1, `MARCH_MBOX_DROP_OLD`=2,
  `MARCH_MBOX_BLOCK`=3 — Task 8 implements BLOCK), `MARCH_SEND_OK`/
  `MARCH_SEND_DEAD`/`MARCH_SEND_DROPPED` result codes, two new plain
  `march_proc` fields (`mbox_limit`, `mbox_policy`) written/read only under
  `mbox_lock`, and declarations for `march_sched_set_mbox_limit` /
  `march_sched_set_msg_dtor`.
- `runtime/march_scheduler.c`: `march_sched_set_mbox_limit(p, limit, policy)`
  sets both fields under `mbox_lock_acquire/release` so it's safe to call
  while senders are active. `march_sched_send` now checks `mbox_limit` before
  `mbox_push`: at capacity, `DROP_NEW` rejects the incoming message (bumps
  `MARCH_STAT_MSGS_DROPPED`, hands the message to the disposer hook, returns
  `MARCH_SEND_DROPPED`), `DROP_OLD` evicts the head via `mbox_pop` (same stat
  bump + disposer) and falls through to enqueue the new message, `BLOCK`
  falls through to enqueue unchanged (`/* MARCH_MBOX_BLOCK: Task 8 */`
  comment on the `default` arm). A static `g_mbox_dispose` function pointer
  + `march_sched_set_msg_dtor` registration hook stands in for the real
  March-value dtor Task 14 will register; default is a no-op, so the
  standalone scheduler unit tests (which link `march_scheduler.c` alone,
  no `march_runtime.c`) still link and pass unchanged.
- `march_sched_init` now also resets `g_runq_len` to 0 (atomic relaxed
  store), alongside the existing runq head/tail reset — folded in from
  Task 6's review as a one-liner; a C harness that spawns/sends without ever
  running the scheduler (this task's own test) would otherwise carry a
  nonzero `g_runq_len` into the next `march_sched_init()` call in the same
  process.
- `runtime/march_runtime.c`: `march_send` now captures
  `march_sched_send`'s return code. `MARCH_SEND_DEAD` (the actor died in the
  window between `march_send`'s own dead-actor checks and the send) still
  `march_decrc`s the message and returns `None`, exactly as before.
  `MARCH_SEND_OK` and `MARCH_SEND_DROPPED` both return `Some(())` (unchanged
  fire-and-forget semantics) and — critically — neither calls `march_decrc`
  again: on the dropped path, `march_sched_send`'s own disposer hook already
  owns that one reference, so decrc-ing it again in `march_send` would be a
  double-free once Task 14 registers a real dtor.
- Audited every other `march_sched_send` call site
  (`grep -n "march_sched_send" runtime/*.c`): `march_actor_broadcast_migrate`
  (line ~2493), `march_actor_call` (line ~3046), `march_actor_reply` (legacy
  raw-proc path, line ~3143, and envelope path, line ~3153) — all five
  ignore the return value entirely (`void` call, no comparison), so none of
  them can misinterpret `MARCH_SEND_DROPPED` as an error or double-dispose
  anything. Only `march_send` needed a code change.
- `test/test_scheduler_mbox.c` + `test/dune` rule pair (cloned from the
  Task 2 `test_scheduler_timer` template — no `-DMARCH_NUM_SCHEDULERS=1`).
  Deterministic: spawns daemon procs and sends without ever calling
  `march_sched_run()`, so nothing drains a mailbox mid-assertion. Segments
  are split into their own functions (default unbounded, `DROP_NEW`,
  `DROP_OLD`, dead-target) so Task 8's live-scheduler `MARCH_MBOX_BLOCK`
  segment can be prepended to `main()` without disturbing these. The
  `DROP_OLD` segment can't inspect which payload survived eviction
  (`mbox_pop` is `static` to `march_scheduler.c`), so it asserts the
  externally observable facts instead: mailbox depth stays pinned at the
  limit, and the `MARCH_STAT_MSGS_DROPPED` counter's *delta* (read before
  and after the segment, not an absolute value — earlier segments in the
  same process may have already bumped it) increased by exactly 1.

## Verification

- `dune build bin/main.exe --root .` — clean.
- `dune build @test/runtest --root .` — all 844 tests green, including the
  new `test_scheduler_mbox` runner.
- `./_build/default/test/test_scheduler_mbox_runner` run 10x directly — all
  10 print `test_scheduler_mbox: all passed`.
- `scripts/run-tests.sh -q` — see task report for the concurrent-session
  caveat noted in Task 6's report (this host runs multiple worktree sessions
  in parallel, which can cause transient resource-contention flakes
  unrelated to this change).

## Notes for future tasks

- Task 8 (`MARCH_MBOX_BLOCK`): the `default` arm in `march_sched_send`'s
  switch is exactly where the sender needs to park; the mailbox lock is
  still held at that point in the current code, so Task 8 will need to
  decide whether to release it before parking (almost certainly yes, to
  avoid holding `mbox_lock` across a `march_sched_park_self`).
- Task 14 (real message dtor): call `march_sched_set_msg_dtor` once at
  runtime init with a `march_decrc`-based (or migrate-aware) disposer. Until
  then, `DROP_NEW`/`DROP_OLD` overflow leaks the dropped payload's one
  reference — acceptable for now since nothing calls
  `march_sched_set_mbox_limit` from March-level code yet (no stdlib/language
  surface was added in this task).
