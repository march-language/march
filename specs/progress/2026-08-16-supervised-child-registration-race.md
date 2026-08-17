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

## Resolved

Verified fixed by reading `runtime/march_runtime.c` (not by re-running the
timing-sensitive `rfo_widen.march` repro — that reproducer is inherently
race-and-hope, and a structural read of the code is stronger evidence here:
the green thread that would read `meta->supervisor` too early simply does
not exist until after the write that this todo worried about).

The fix landed as deferred activation, exactly the shape this todo's
"Suggested shape" section proposed ("`march_spawn` accepts ... the
supervisor pointer directly, so `meta->supervisor` is set BEFORE the green
thread is started"), implemented as a `defer_activation` flag on the shared
spawn path rather than a variant taking the supervisor pointer directly:

- `march_spawn_common(actor, defer_activation)` is the single spawn
  implementation; `march_spawn(actor)` calls it with `defer_activation=0`
  (green thread starts immediately, the ordinary case), while
  `march_spawn_supervised(actor)` calls it with `defer_activation=1` —
  `activate_actor_green_thread(meta)` is skipped at spawn time, so no
  green thread exists yet to race the registration write.
- `march_respawn_child` (`runtime/march_runtime.c`) calls
  `march_spawn_supervised(raw)` to get the deferred child, then writes
  `new_meta->supervisor = supervisor;` (plus `sup_child_index`, `epoch`)
  **inside** a `pthread_mutex_lock(&g_tbl_mu)` / `pthread_mutex_unlock`
  pair — closing the other half of the original bug report, the unlocked
  write `march_respawn_child` used to do.
- Only after that locked publication does `march_respawn_child` call
  `activate_actor_green_thread(new_meta);`, per the comment directly above
  the call: "Publication above is complete before this proc can run and
  install its supervised panic trap."

So both halves of the original bug are closed: the ordering gap (green
thread now starts strictly after the supervisor write, not concurrently
with it) and the unlocked-write half (`march_respawn_child`'s write is now
under `g_tbl_mu`, matching `march_actor_register_child`'s existing
discipline).

Codegen confirmation that supervised children actually go through the
deferred path: `test/test_eval.ml:3475` and `test/test_codegen.ml:12564`
both assert the emitted IR calls `march_spawn_supervised` for supervise-
block children, not the immediate-activation `march_spawn`.
