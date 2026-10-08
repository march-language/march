# Two ways a closure's captures were never released

**FIXED 2026-10-07.** Found chasing the last object a cluster session leaves behind
(specs/todos/2026-10-07-session-refresh-names-globalpid-leftover.md, from #871). With
#871 and #872, the single-node session probe drops to ~0 objects per session once its
tombstones expire. One 40-byte `GlobalPid` per session still survives; see "Left".

## 1. A closure whose cell FBIP reused released nothing it captured

`Map.node_fold` builds its recursive `go` closure inside the `HBranch` cell it has just
destructured (`reuse node as $Clo_go(go$apply, f)`), so `go`'s capture `f` (the caller's
fold function) moves into the reused cell. Releasing an environment's captures when it
dies is gated on the closure type "owning" them (`Drop.owning_apply_fns`). That gate
recognised only closures built by `EAlloc`. FBIP runs before it and had turned this
allocation into an `EReuse`, so the type had no noted allocation site and was never
owning. When `go` finished, its environment was freed and `f` was not: **every
`Map.fold` with a capturing closure leaked that closure.** `ClusterNode.collect_tombstones`
folds twice per session, and a probe of `Map.fold` with a capturing lambda left 100
objects over 100 calls.

Fix: the gate treats a closure `EReuse` exactly like an `EAlloc`. Perceus placed its RC
ops while it was still an `EAlloc`, judging it with the same `Borrow.closure_escapes`,
so both passes now agree. The closure-drop registration and DCE already walked `EReuse`.

## 2. A release of an owned parameter hid a covered tail call

`rewrite_apply_clo_drop` releases a closure environment's captures on the path where its
own release frees it. A tail call that uses a capture keeps that capture alive (the
documented "safe-direction leak"), unless Perceus already handed the call its own
reference: the run of `inc_rc c` right before the call (`covered`). Any other statement
in between reset that run, and `Perceus.insert_owned_aggregate_param_drops` puts exactly
such a statement there: the release of an owned record parameter right before the tail.
So in `SessionNode.run_cluster_with`'s `fn (_p, s) -> body(s)`, the release of `_p`
hid the `inc_rc body`, and the environment's reference to `body` (the role function)
leaked, once per cluster session.

Fix: the run of increments survives a release of a variable that is neither a capture,
nor one of the incremented variables, nor `$clo` itself (`releases_other`). Releasing an
unrelated value cannot affect whether a capture is still alive.

## Evidence

- `test/native/reused_closure_captures.march`: a fold with a capturing closure, a fold
  into a map, and the `run_cluster_with` shape; RED on main on all three (101, 94 and 201
  objects left over 100 calls), GREEN after, and the interpreter agrees on every value.
- IR over 432 programs, names normalised, against main: 41 differ (37 from fix 1, 4 more
  from fix 2: `hash_map_bench`, `record_field_tail_projection`, `signal_term_suppress`,
  `signal_watch`). Every program that folds a `Map` with a capturing closure, or that
  has a covered tail call behind a parameter drop, changes. The new lines are the
  capture releases on freed paths (`march_clo_release` and typed drops).
- Session probe with #871 and #872: from ~1 object per session (tombstones expiring at
  once) to ~0; ~16 with the default 3 h grace (the tombstones themselves).

## Left

One 40-byte `GlobalPid` per session (the offer's pid, rebuilt by
`ClusterNode.refresh_names`) still ends each run with refcount 2 and no heap referrer.
A compile-time listing of every apply function that still keeps a used capture on a
freed path (the documented safe-direction leak, `CAPLEAK` instrumentation, not
committed) shows none that captures a `GlobalPid` directly, so the holder is reached
indirectly. Tracked by specs/todos/2026-10-07-session-refresh-names-globalpid-leftover.md.
