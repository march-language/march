# Synchronous batch restarts now claim an in-flight marker (and absorb deflected siblings)

Closes `specs/todos/2026-08-12-concurrent-first-crash-batch-restarts-unsynchronized.md`.

## The bug

`march_supervisor_notify`'s leaf-lock section only claimed
`delayed_batch_pending` in the `else if (is_batch && streak > 1)` branch.
A FIRST crash (`streak == 1`) of a `one_for_all`/`rest_for_one` child
claimed nothing and fell straight through to the `if (delay == 0)`
synchronous branch, which calls the strategy with `g_supervise_mu`
released (the leaf-lock contract forbids holding it across a strategy
call — strategies run March closures and can call `do_actor_death`).

So two DIFFERENT children of the same batch supervisor crashing for the
first time on two OS threads (`MARCH_NUM_SCHEDULERS > 1` is the default)
both observed "not pending" and both ran a strategy function concurrently
against the same `sup_children` array — the same corruption shape the
delayed path's round-3 fix closed.

## The fix

New `march_actor_meta` field `int batch_restart_in_flight;` (zeroed by the
existing `calloc`, mutated only under `g_supervise_mu`):

- `skip_due_to_pending` now tests `delayed_batch_pending ||
  batch_restart_in_flight`.
- A new `else if (is_batch)` branch (reached only when `streak == 1`, i.e.
  `delay == 0`) claims the marker, seeds `pending_min_child_idx = child_idx`,
  and snapshots `pending_drop_count` — all inside the SAME critical section
  that decided this crash is not being skipped.
- The `delay == 0` branch releases the marker only after the strategy has
  fully returned, so the deflection window covers the whole call.

## Why the release path needs an absorb loop

A sibling deflected by the new marker takes the `skip_due_to_pending` path:
it widens `pending_min_child_idx`, bumps `pending_drop_count`, and performs
NO restart of its own. On the delayed path `delayed_restart_thread`'s absorb
loop consumes those. A synchronous restart has no such thread, so the
release site must do it or the deflected sibling stays dead forever
(a dead slot never crashes again on its own). Two reachable strandings:

1. `rest_for_one`'s window is literally `[child_idx, n)` (see
   `march_rest_for_one_restart`: the respawn loop is
   `for (i = child_idx; i < n; i++)`). A deflected sibling at a LOWER index
   is outside it. This is exactly the hazard `pending_min_child_idx` was
   introduced for on the delayed path — it applies verbatim here.
2. EITHER batch strategy: a slot the in-flight pass already respawned can
   crash again before the marker is released. That drop does not lower
   `pending_min_child_idx`, which is why the loop condition is
   `pending_drop_count` (round 3's correction), not the min.

So `one_for_all` alone is NOT sufficient justification for skipping the
loop, and `rest_for_one` genuinely strands. The release path therefore
mirrors `delayed_restart_thread`: re-run the strategy at the widened
`pending_min_child_idx` while `pending_drop_count` keeps advancing, and
clear the marker only after a pass that absorbs nothing. Liveness is
re-checked before each extra pass (a strategy can kill the supervisor via
restart-intensity exhaustion), and on a dead supervisor the marker is left
SET — the same deliberate choice `delayed_restart_thread` documents.

Termination: an endlessly re-crashing child bounds the loop through
`march_restart_budget_ok`, which eventually fails and kills the supervisor,
tripping the `!alive` return.

## Golden compatibility

The first pass is still unconditional and still at the original `child_idx`,
so the single-crash supervision goldens
(`test/native/supervisor_{one_for_one,one_for_all,rest_for_one}_restart`)
are byte-identical: nothing is deflected in them, `pending_drop_count` never
advances, and the loop exits after one pass.

## No regression test

An attempted test (a `one_for_all` supervisor whose two children both crash
for the first time must charge exactly ONE batch restart) was written in
`test/test_supervision.ml`, run post-fix, then run against a reverted
`runtime/march_runtime.c` — it PASSED both ways and was deleted, per the
2026-08-16 ruling that a test which cannot fail against the broken code is
not evidence.

Two independent reasons it cannot discriminate:

- `test_supervision.ml`'s dune stanza links `march_eval` only. That binary
  contains no C runtime, so it cannot execute `march_supervisor_notify` at
  all — the interpreter has its own, single-threaded supervision path in
  `lib/eval/eval.ml`.
- Sequentially, the bug does not exist: the race needs two OS threads
  interleaved inside `march_supervisor_notify` between the leaf-lock unlock
  and the strategy call. Reproducing that deterministically would require an
  injected hook in the runtime; a spawn-many-and-hope loop is not acceptable
  evidence.

The fix therefore rests on the structural argument above: the claim happens
in the same critical section as the skip decision, so the claim and the
"am I skipping?" test are atomic with respect to each other, and the marker
is held across the entire strategy call. That is the identical invariant the
delayed path already relies on.
