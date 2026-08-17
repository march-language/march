# delayed_restart_thread's supervisor-liveness recheck is address-based, not incarnation-precise

Found during the final-review fix wave on the actor-hardening branch
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`), while tracing the
send-vs-reap push-after-drain fix (`runtime/march_scheduler.c`,
`march_sched_send`). Adjacent to, but distinct from, the two sibling races
already filed:
`specs/todos/2026-08-12-do-actor-death-unlocked-cleanup-monitor-heads.md` and
`specs/todos/2026-08-12-supervised-child-registration-race.md`.

## The bug

`delayed_restart_thread` (`runtime/march_runtime.c`, ~2819) parks a
dedicated green thread until the backoff deadline, then re-validates the
supervisor is still alive before running the restart strategy:

```c
if (!march_is_alive(supervisor)) return;   /* supervisor died meanwhile */
```

`supervisor` is a bare `void *` captured into `march_delayed_restart` at
schedule time (~3041, `dr->supervisor = supervisor;`) and `march_is_alive`
is purely address-based:

```c
int64_t march_is_alive(void *actor) {
    return ((int64_t *)actor)[3];
}
```

It dereferences whatever is at that address and reads a status word — it
has no notion of *which* actor lived there. If the supervisor dies and its
March-heap allocation is reclaimed and reused for a *different* live actor
within the backoff delay window (`25 << min(streak-1, 7)` ms, capped at
3200ms pre-jitter, i.e. up to ~4s with jitter — see the `CHANGELOG.md`
"Exponential supervisor restart backoff" entry), `march_is_alive` reads
`1` (alive) for that unrelated actor's status word, and
`delayed_restart_thread` proceeds to treat it as the original supervisor:

- `find_meta(supervisor)` (~2836) looks up actor metadata keyed by the same
  reused address. If the reused address is registered as some other actor's
  raw pointer key too, this either returns that unrelated actor's meta (a
  type/identity confusion one level deeper) or `NULL` (silently absorbed —
  the `if (!sup_meta) return;` right after is a no-op in that case, so nothing
  crashes, but nothing restarts the real child either).
- If it happens to return a live `march_actor_meta` for the reused address
  (e.g. the address was recycled into another *supervisor* actor), the batch
  strategies (`march_one_for_all_restart`/`march_rest_for_one_restart`,
  strategies 1/2) run against that unrelated supervisor's child list and
  `pending_min_child_idx`/`pending_drop_count` bookkeeping — a spurious
  batch restart charged against the wrong supervisor's budget and children.
- For strategy 0 (one_for_one) the blast radius is smaller: a no-op restart
  attempt against an actor that isn't actually the original supervisor,
  wasting one green-thread wakeup and, in the unlucky case above, corrupting
  an unrelated supervisor's pending-restart state.

## Narrow-window honesty

This needs address reuse within the backoff window specifically — the
March heap allocator would have to free the dead supervisor's block and
hand the identical address back out to a new actor spawn before this
green thread wakes and rechecks. That is a real but narrow window (bounded
by allocator behavior and program spawn/death churn rate, not by anything
this code controls), the same class of "empirically rare, not addressed by
existing sync" risk noted as a pre-existing gap in the sibling todos above
— not a new hazard introduced by this backoff feature, but one this
feature's minutes-scale delay window makes meaningfully more likely to
land than an ordinary use-after-free race would.

## Suggested fix shape

- Stamp the supervisor's `pid_index` (already used for incarnation-precise
  lookups elsewhere — see `find_meta_by_pid_index`,
  `runtime/march_runtime.c:2368`, used by e.g. the child-registration path
  at ~2655/2704/2737) into `march_delayed_restart` at schedule time, instead
  of (or alongside) the raw `void *supervisor` pointer.
- Re-resolve via `find_meta_by_pid_index(dr_pid_index)` on wake, not a raw
  `march_is_alive(supervisor)` address probe. `find_meta_by_pid_index`
  already carries the incarnation-precise semantics this needs (it is keyed
  off the pid-index table, which is per-spawn, not per-address), so a
  successful lookup is proof the ORIGINAL supervisor incarnation is still
  the one being addressed, not a coincidentally-live reuse.
- Both liveness rechecks in `delayed_restart_thread` need the swap (the
  initial one at ~2835 and the per-pass TOCTOU recheck inside the batch loop
  at ~2851/2855), plus the `strategy == 0` early recheck at ~2840.
- Add a regression test once a fix lands: spawn a supervisor, let a child
  crash to schedule a delayed restart, kill the supervisor, then
  deliberately spawn+kill enough short-lived actors during the backoff
  window to pressure the allocator toward reusing the freed address, and
  assert the delayed restart neither touches an unrelated actor nor crashes.
  Likely needs to run under `MARCH_NUM_SCHEDULERS>1` (true parallelism) to
  have any chance of forcing the timing, and should be treated as a
  best-effort/flake-tolerant probe rather than a hard gate, same caveat the
  sibling registration-race todo gives its own regression test.

## The fix

`march_delayed_restart` gains `int64_t sup_pid_index;`, stamped at the
`malloc` site in `march_supervisor_notify` from the already-resolved
`sup_meta->pid_index` (atomic, relaxed load — same field, same discipline
`find_meta_by_pid_index` itself uses).

`delayed_restart_thread` now resolves `sup_meta` via
`find_meta_by_pid_index(sup_pid_index)` — pid-index-keyed, per-spawn,
never reused — instead of the old `find_meta(supervisor)` (address-keyed,
and address chains can alias a reused address to a newer, unrelated
actor's meta ahead of the original). This resolve had to move BEFORE the
first liveness check, since the new check needs `sup_meta` in hand to
compare against.

All three liveness probes (initial, the `strategy == 0` recheck, and the
per-pass TOCTOU recheck inside the batch loop) now go through a new
`static int sup_still_live(int64_t sup_pid_index, march_actor_meta
*sup_meta, void *supervisor)` helper — a function rather than the brief's
suggested local `#define`/`#undef` macro, to match this file's house
style (macros here are file-scope constants/table generators, not
function-scoped logic). It checks `find_meta_by_pid_index(sup_pid_index)
== sup_meta && march_is_alive(supervisor)`. The identity-confusion half of
the bug is actually closed by the pid-index-keyed *resolution* that produces
`sup_meta` in the first place — `delayed_restart_thread` now calls
`find_meta_by_pid_index(sup_pid_index)` once, up front, instead of the old
address-keyed `find_meta(supervisor)` — so restart bookkeeping is pinned to
the original incarnation's meta before any liveness check ever runs. The
`find_meta_by_pid_index(sup_pid_index) == sup_meta` conjunct inside
`sup_still_live` is a cheap invariant assertion on top of that pinning
(`g_pididx_tbl` is insert-only with never-reused keys, so this lookup always
returns the same pointer `sup_meta` already holds — it can never observe a
mismatch), not the mechanism that re-derives correctness on each call.
`march_is_alive` still gates whether to actually restart.
The dead-supervisor path's existing "leave `delayed_batch_pending` set,
don't clear it" behaviour (established by Task 3, see
`specs/progress/2026-08-16-sync-batch-restart-in-flight-marker.md`) is
untouched — `sup_still_live` returning false takes the exact same early
`return` that `march_is_alive(supervisor)` alone used to.

**Residual scope, stated honestly:** `march_is_alive(supervisor)` itself
still dereferences the raw address, which — if reused — now belongs to a
different live actor's memory; that read is memory-safe (it's the new
occupant's own live allocation) but can still read "alive" in the exact
narrow reuse window the todo describes. What the fix eliminates is running
this restart's *bookkeeping* (children array, `pending_min_child_idx`,
restart budget) against the wrong supervisor's `sup_meta` — the actual
corruption vector the todo's bug section describes. This matches the
todo's own "Narrow-window honesty" section: the underlying allocator-reuse
window isn't something this code can close outright.

**No new test** — human ruling 2026-08-16: address reuse cannot be forced
on demand, so a probe here would pass identically before and after the
fix; a test that cannot fail against the broken code is not evidence.
Evidence is the structural argument above, plus the existing suites
(`run_stdlib`, `run_codegen`, `dune runtest`) staying green with the
supervision backoff goldens byte-identical — this change alters WHICH
supervisor a delayed restart validates against, not WHEN it fires.
