# Choreography access points, phase A2: hosted offers

Shipped 2026-09-20, from [[2026-09-20-hosted-offers-implementation]]: phase A2 of
[[2026-09-19-choreography-access-points-and-crash-branches-design]], after A1
([[2026-09-20-choreography-access-points-a1]]). An actor hosts many sessions of a role
over a cluster node's access point, one `Parked_<Role>` per session id in a `LinearMap`
([[2026-09-18-linear-map]]). Part B of the design, crash branches, is a separate item.

## What it adds

- `SessionNode.run_cluster_hosted(io, node, my_role, peers, sid, on_close, host, start,
  deliver, cancel)`: `run_cluster` with the role hosted in an actor, as `run_hosted_or`
  hosts it over the standalone runner's connections. Both runners now call one
  `pfn host_party(p, s, host, start, deliver, cancel)` (the two forwards, the `HostWatch`,
  `start(s)`), and the cluster runner proper is `pfn run_cluster_party(..., drive,
  abandoned)`, which `run_cluster_with` and the new `pfn run_cluster_hosted_with` call
  with a callback body or the hosted setup. `stop_host_watch(p)` kills the watcher at the
  session's end in both runners (the cluster runner never did, since it had no hosted
  form).
- `SessionNode.offer_hosted(io, node, proto, fingerprint, my_role, peers, capacity,
  on_close, host, start, deliver, cancel)`: `offer_role` with every accepted session run
  by `run_cluster_hosted_with`. The offer actor and registration are one `pfn
  offer_with(node, proto, fingerprint, my_role, capacity, start)` shared by both.
- Generated, in `<P>_Run` (`Desugar_endpoints.run_module`), beside `offer_<Role>`:
  `offer_hosted_<Role>(io, node, capacity, host, start, deliver, cancel)` and
  `cluster_hosted_<Role>(io, node, session, host, start, deliver, cancel)`. Every
  callback carries the session id: `start(sid, s)`, `deliver(sid, s, from, msg, ep)`,
  `cancel(sid, s, role, cause, ep)`; `cluster_hosted_<Role>` passes its one session id,
  so one actor serves both forms. `host_<Role>` keeps its arity.
- The guide (`docs/choreography.md`, `specs/lang/choreography.md`): "Many sessions in
  one actor" under "Hosting a role in an actor", with the `LinearMap` shape (`take_slot`,
  `resume`, `fill` or `vacate`), and two rows in the entry-point table.

## Decisions

- **One `HostWatch` per session**, as the spec proposed: the standalone runner's shape,
  and each watcher reports `HostDown` for its own party. Cost: one small actor per
  session for the session's life, killed by `stop_host_watch` at its end.
- **Ready before the park.** The cluster runner replays held frames (`Ready`) once the
  drive returns. For a hosted party the drive only sends the start message, so a frame
  can be replayed before the actor has parked; it is then held by `deliver` (no handler),
  and the park's `Drain` finds it. No change was needed; the comment at the `Ready` send
  says so.

## What the tests found

- **A `Closed_<Role>` value cannot be consumed outside the role module.** The spec's
  "`vacate` after `finish`" needs the finished value dropped, but matching
  `Echo_Server.Closed_Server(_)` from the user's module fails with "I cannot find
  `Secret`" (the constructor's payload type is private to the role module), and the role
  module has no `take_closed`. The fixtures and the guide drop it through
  `pfn retire(linear p : a) : () do let _ = p; () end`: the checker trusts a `linear`
  parameter's definition and does not check its body, which is the loophole the error
  message for a generic drop points at ("mark it `linear` where `retire` is defined").
  Filed: [[2026-09-20-role-module-take-closed]]. The role module was out of this
  change's scope (concurrent edits).

## Tests

- `test/two_node/cluster_ap_hosted`: node-a hosts `Server` of a two-exchange `Echo` in
  one actor (capacity 4); node-b runs three sessions at once (three tasks), then a fourth.
  The actor prints each message with the session's own counter (an ordinary `Map` keyed
  by sid beside the `LinearMap`); sorted goldens.
- `test/two_node/cluster_ap_hosted_cancel` (three nodes): node-c's session stalls after
  its first exchange, node-b runs two sessions while it is parked, then node-c is killed.
  The actor's `Cancel` handler runs for that one sid ("session cancelled, Client gone"),
  the other two finished, and node-a stops at two done and one cancelled.
- `test/test_endpoints.ml`: the `<P>_Run` shape lists `offer_hosted_*` and
  `cluster_hosted_*`.
- `stdlib/session_node.march` still checks clean (`test/dune`'s `session_node_check`).

## Not in this phase

Choosing an offer by load; an offer's capacity across a restart; crash branches for
hosted roles ([[2026-09-20-crash-branches-implementation]], B2).
