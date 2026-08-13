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
