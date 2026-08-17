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

## Behavioural change: a repeat crash absorbed synchronously loses its backoff delay

One real pacing change falls out of the fix and is worth stating explicitly,
since it is not a bug but is a departure from pre-fix behaviour. Before this
fix, a REPEAT (`streak > 1`) sibling crash landing while a synchronous batch
restart was in flight took the `else if (is_batch && streak > 1)` branch,
claimed `delayed_batch_pending`, and was picked up later by
`delayed_restart_thread` — which runs after `march_restart_delay_ms`'s
exponential backoff has parked the thread. After this fix, the same repeat
crash instead observes `batch_restart_in_flight` already held, is deflected
by `skip_due_to_pending`, and gets absorbed by the release-path loop
described above — which re-runs the strategy immediately, with **no park
and no backoff delay**, as soon as the in-flight pass returns.

This is bounded by the same `march_restart_budget_ok` check that bounds the
delayed absorb loop, and it mirrors a choice `delayed_restart_thread`
already makes for its own absorbed siblings (that loop doesn't re-park
between passes either). But there the crash reached the loop only after
at least one backoff park had already happened upstream; here a repeat
crasher can be re-run with zero delay if it lands inside the synchronous
window. In a genuine crash storm this makes the synchronous path slightly
more aggressive about immediately re-trying than the delayed path was for
the same child, right up until the restart-budget bound kicks in and kills
the supervisor. Flagged by Task 3's reviewer; not fixed, because bounding
it further would mean re-deriving backoff timing inside a section that
must not block, which is out of scope for this race fix.

## Disposition of the two remaining review minors

Two smaller items surfaced during Task 3's review and were deferred rather
than fixed. Task 6's close-out re-examined both to decide, per item, whether
they need a new todo or are adequately covered already:

- **A `longjmp` escaping the strategy call would skip the marker release,
  wedging that supervisor into skip-forever.** No new todo: this is not a
  gap specific to `batch_restart_in_flight` but the general, already-tracked
  hazard of a crash-trap `longjmp` unwinding past code that has not yet run
  its cleanup — the exact defect shape closed for the RC field by
  `specs/progress/2026-08-14-crash-trap-longjmp-heap-corruption.md`,
  `specs/progress/2026-08-14-actor-dispatch-rc-clobber-uaf.md`, and (for the
  crash trap's own RC skip) commit `acfa832c`
  ("restore the actor RC the crash trap's longjmp skipped"). The delayed
  path's `delayed_batch_pending` clear has carried the identical exposure
  since it was written, so this fix introduces no new risk — it's covered by
  the standing longjmp/crash-trap audit line of work, not a fresh gap.
- **The no-drop case clears the marker unconditionally, even on a pass that
  killed the supervisor** — a small asymmetry with the "leave it set on a
  dead supervisor" rule two lines above. No new todo: Task 3's report argued
  this matches pre-fix behaviour (a dead supervisor never re-enters
  `march_supervisor_notify`, so a marker left set or cleared on it is
  unobservable either way), and the reviewer accepted that argument. Recorded
  here as the closing word rather than left as a dangling "accepted" in the
  ledger.
