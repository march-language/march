# Supervised-child crash-trap registration race: a fast-crashing child can panic uncaught

Discovered while validating Task 16's rest_for_one widening fix
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`), under this
codebase's DEFAULT multi-scheduler configuration (`MARCH_NUM_SCHEDULERS`
defaults to 4 — true OS-thread parallelism between actors' green
threads). Pre-existing since the original supervision implementation
(`393446c2 feat: compiled supervised-actor crash isolation + one_for_one
restart`); not introduced by, and not fixed as part of, Task 16.

## The bug

Spawning a supervised child and registering it as supervised are two
separate, non-atomic steps:

1. `<ActorName>_spawn()` calls `march_spawn(raw)`, which starts the
   child's `actor_green_thread` running immediately (on its own OS thread
   under multi-scheduler mode) — including its startup read of
   `meta->supervisor` (under `g_tbl_mu`) to decide whether to install a
   crash trap (`self->crash_jmp = &crash_jmp`).
2. Only afterward does `march_actor_register_child` (initial spawn) or
   `march_respawn_child` (a supervisor restart) actually write
   `child_meta->supervisor = supervisor` — `march_actor_register_child`
   takes `g_tbl_mu` around that write (so it's not a data race in the
   formal sense — both sides use the same lock), but `march_respawn_child`
   does NOT take any lock around its `new_meta->supervisor = supervisor;`
   at all.

If the new child's `actor_green_thread` reaches its `has_supervisor` read
before step 2 has run (or, for `march_respawn_child`, before its
unlocked write is even visible), `has_supervisor` reads false. That
child's crash trap is never installed for its entire remaining
lifetime — if it happens to receive a crash-inducing message before
registration would have caught up, `march_panic` finds
`cur_proc->crash_jmp == NULL`, falls through to the unsupervised path,
and calls `exit(1)`, killing the whole process instead of triggering a
supervised restart.

## Reproduction

A two-child (`a`, `b`) `rest_for_one` supervisor, `b` crashed twice in
quick succession (to build a real backoff streak) while `a` is crashed
once during the resulting delay window (see
`.superpowers/sdd/2026-08-11-actor-system-hardening/task-16-report.md`'s
"Fix report: review round 3" section for the full scratch repro script,
`rfo_widen.march`). Under the default multi-scheduler build, this hits an
uncaught `panic: poisoned` roughly 30–50% of the time. Confirmed via
direct instrumentation (temporary debug prints in `actor_green_thread`
and `march_panic`, not committed) that the actor which panics uncaught is
`a`'s ORIGINAL incarnation — spawned at `has_supervisor=0` at the very
start of the program, well before any of the backoff/widening logic runs
— i.e. this reproduces even on `a`'s very first registration, not only on
a supervisor-triggered respawn. Confirmed the failure disappears
(0/25+ runs) under `MARCH_NUM_SCHEDULERS=1`, which serializes all green
threads onto one OS thread and removes the true-parallelism window this
race needs.

## Why this wasn't fixed as part of Task 16

It's a distinct bug in the original supervised-spawn/register sequence
(predates Task 16 by many commits), not in anything Task 16 or its review
rounds added. Fixing it properly means closing a registration-ordering
gap between `march_spawn` and `march_actor_register_child`/
`march_respawn_child` — either by not starting the child's green thread
until after registration completes (a bigger restructuring of the spawn
sequence), or by having the child's `has_supervisor` decision re-check
after a first miss instead of being a one-time snapshot at green-thread
start. Neither is a small, scoped change, and guessing at a fix under
time pressure risks introducing a new, worse bug in a security/reliability-
critical path (crash isolation). Filed here instead of attempted inline.

## Suggested shape for a follow-up

- Make `march_respawn_child`'s `new_meta->supervisor = supervisor;` write
  consistent with `march_actor_register_child`'s locked write (take
  `g_tbl_mu`) — necessary but not sufficient, since the ordering gap is
  the real problem, not the lock.
- Consider: `march_spawn` accepts (or a new variant accepts) the
  supervisor pointer directly, so `meta->supervisor` is set BEFORE the
  green thread is started rather than after — removing the window
  entirely rather than narrowing it.
- Add a regression test exercising exactly this shape (a supervised child
  that can crash within microseconds of being spawned/respawned) once a
  fix lands, gated appropriately to avoid flaking a working fix under
  slow CI (this bug's own reproduction rate is already timing-sensitive,
  so the fix's test needs to be a structural assertion — e.g. an
  explicit synchronization checkpoint proving registration happens before
  the green thread's first dispatch — rather than a race-and-hope loop).
