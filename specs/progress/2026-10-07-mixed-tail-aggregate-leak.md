# An aggregate returned on one path leaked on the paths that only read it

**FIXED 2026-10-07.** The bulk of what a finished cluster session still left behind:
single-node session probe (`session_party_released`, 40 sessions) from ~79 objects
per session to ~21 (default tombstone grace), and from ~71 to ~6 with tombstones
expiring at once.

## Finding it

Allocation-site tracing put two survivors per session party in
`SessionNode.Endpoint`'s handlers (`AwaitOutcome`, `LinkEnded`). A referrer scan (a
table of live objects with their allocation sites, scanned at exit) showed the roots
were 56-byte records with refcount 1 and NO heap referrers, holding the party's pieces.
These were the endpoint's state record (`n, links, ended, failed, waiters`): not held by
the dead actor, simply never released. An actor copying `Endpoint`'s handlers reproduced
it outside the session machinery: 3 objects per actor when the outcome settles before
the ask, 11 when the ask waits.

## Cause

Both handlers bind a record and then return it on one branch while only reading it on
the other:

```march
let st = ep_state(.., state.ended + 1, failed, state.waiters)
if settled(st) do
  ..
  ep_state(st.n, st.links, st.ended, st.failed, Nil)   -- reads st
else
  st                                                    -- hands st over
end
```

and, in `AwaitOutcome`, `state` itself the same way. Perceus places the scope-end drop
of a let-bound aggregate at the scope's tails (`drop_agg_at_tails`, which decides per
path). Two things kept it from ever running on the reading path:

1. `insert_rc_expr` skipped the drop entirely when ANY tail of the scope was the
   aggregate (`tail_value_is_var` was a `List.exists`).
2. When the deciding branch sat in a `let`'s right-hand side
   (`let $result = if .. do state else {..} end in ..`, the shape every actor handler
   lowers to), the paths of that right-hand side disagreed, and `drop_agg_at_tails` gave
   up ("a leak at worst").

## Fix (lib/tir/perceus_core.ml)

1. The drop is skipped only when EVERY tail is the aggregate (`every_tail_is_var`).
   Otherwise `drop_agg_at_tails` decides per path: a path that returns the value has a
   negative balance and is left alone, and every other path gets the release.
2. In `drop_agg_at_tails`, a `let` whose right-hand side branches with disagreeing paths,
   and whose body never mentions the aggregate again, carries the per-path release into
   that right-hand side: each path binds its value, then releases.

## Evidence

- `test/native/mixed_tail_aggregate_drop.march`: both shapes in plain functions, 100
  calls each, half taking each branch. RED before (201 objects left per shape at
  `--opt 0` and `--opt 2`), GREEN after; the interpreter agrees on the values.
- The `Endpoint`-shaped actor repro: 150 -> 0 and 550 -> 0 objects over 50 actors.
- TIR snapshot suite unchanged (no corpus program has the shape).
- `bench/tree_transform`, `list_ops` and `binary_trees` emit identical IR before and
  after (register names aside).
- IR oracle and ASAN corpus sweep: see the PR.
