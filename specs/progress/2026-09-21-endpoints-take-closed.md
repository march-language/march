# `take_closed`: retiring a hosted session without a generic linear dropper

Shipped 2026-09-21. Closes a linearity hole that the hosted-access-point work
([[2026-09-20-choreography-access-points-a2]], PR #537) left in the guide rather than
in the checker.

## The hole

An actor that hosts a role keeps a linear `Parked_<Role>` per session. When the session
finishes (`finish`) or is cancelled (`cancel`), what comes back is a `Closed_<Role>`:
still linear, still the actor's to consume, and nothing in the generated role module
consumed it. `docs/choreography.md` (and its twin `specs/lang/choreography.md`) told the
reader to write their own:

```march
pfn retire(linear p : a) : () do
  let _ = p
  ()
end
```

That function is generic in `a`, so it drops *any* linear value: a live `Parked_<Role>`
that still owns an endpoint, a `LinearMap`, anything else linear the program holds. The
guide was handing every reader a universal escape hatch from the linearity check, and one
typo (`retire(parked)` where `retire(Echo_Server.cancel(parked))` was meant) silently
discarded a running session.

## The fix

`lib/desugar/desugar_endpoints.ml` generates a `take_closed` beside the existing
`take_idle`, in the same list of event-API declarations:

```
fn take_closed(p : Parked_<Role>) : ()
```

It matches `Closed_<Role>(_)` to `()` and panics on every other constructor
("<Proto>, role <Role>: take_closed on an endpoint that has not finished"), exactly the
shape `take_idle` already had for the mirror case. Because the parameter is typed at this
role's own `Parked_<Role>`, it consumes a closed session and nothing else: a live parked
endpoint of another role does not even typecheck, and a live parked endpoint of this role
is a run-time panic rather than a silent drop.

No checker change was needed. The linear value is consumed by being matched on, which is
the same mechanism `cancel` and `take_idle` already relied on.

## What changed

- `lib/desugar/desugar_endpoints.ml`: `take_closed`, registered in `event_api`.
- `docs/choreography.md`, `specs/lang/choreography.md`: the `pfn retire` passage is gone,
  along with the claim that the role module has no function that consumes a closed value.
  The three call sites in the "Many sessions in one actor" example now call
  `Echo_Server.take_closed`, and the duplicate-session arm wraps the displaced value in
  `Echo_Server.cancel` first, so it is a closed value that gets retired.
- `test/test_endpoints.ml`: `take_closed` added to the generated-shape list and to both
  pinned name lists (`stream_prod_fns`, `stream_cons_fns`), plus an accept case retiring a
  finished session and a reject case showing the consumed value cannot be reused.
- `test/two_node/cluster_ap_hosted/node_a.march` and
  `test/two_node/cluster_ap_hosted_cancel/node_a.march`: the same `pfn retire` is gone
  from both scenarios, replaced by `Echo_Server.take_closed`.
- `specs/lang/types/accept/t280_endpoints_take_closed.march`, with its `INDEX.md` row and
  the three count sites (400/400: 167 accept, 233 reject).
- `specs/todos/2026-09-20-role-module-take-closed.md` filed this work as two items. Item 1
  is what shipped here; item 2, whether a `linear` parameter's body should be checked for
  exactly one use, is now `specs/todos/2026-09-21-linear-param-body-unchecked.md`. It is
  what made the generic dropper typecheck in the first place, and nothing shipped depends
  on it any more.
