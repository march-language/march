# Hosted access points: implementation spec (phase A2)

Implements phase A2 of [[2026-09-19-choreography-access-points-and-crash-branches-design]]:
an actor hosting many sessions of a role, one `Parked_<Role>` per session id in a
`LinearMap`, over a cluster node's access point. A1 ([[2026-09-20-choreography-access-points-a1]])
shipped `offer_<Role>` / `initiate_<Role>` for callback bodies; this adds the actor form.

## What exists to build on

- `SessionNode.run_hosted_or(io, my_role, peers, node_id, secret, addrs, on_close, host,
  start, deliver, cancel)`: the standalone hosted runner. It sets `p.forward` (key "f")
  and `p.forward_cancel` (key "c"), spawns a `HostWatch` monitoring the host actor, and
  runs the body as `start(s)`. Deliveries for an awaiting endpoint go to `deliver(s, from,
  msg, ep)`; the actor resumes (`Parked_<Role>.resume`) and re-parks (`await_*`), whose
  `suspend` sends `Drain` to the endpoint actor.
- `SessionNode.run_cluster_with(io, node, my_role, peers, sid, on_close, body, abandoned)`
  and `offer_role(...)`, whose `start` closure runs one session per accepted invitation.
- `LinearMap` (`stdlib/linear_map.march`): `take_slot` / `fill` / `vacate` is the intended
  per-session pattern (`specs/progress/2026-09-18-linear-map.md`, lines 183-201).

## Design

**`SessionNode.run_cluster_hosted_with(io, node, my_role, peers, sid, on_close, host,
start, deliver, cancel, abandoned)`**: `run_cluster_with` with the hosted party setup
factored out of `run_hosted_or` into a shared `pfn host_party(p, host, start, deliver,
cancel)` that both runners call after the party is formed (sets the two forwards, spawns
`HostWatch`, records "watch", calls `start(s)`). Do not duplicate the body of
`run_hosted_or`; extract and reuse.

**Session id in the callbacks.** A hosted offer runs many sessions in one actor, so every
callback carries the sid: `start(sid, s)`, `deliver(sid, s, from, msg, ep)`,
`cancel(sid, s, role, cause, ep)`. The standalone `host_<Role>` keeps its current
arity; only the new cluster/offer functions take the sid.

**Generated** (`Desugar_endpoints.run_module`), alongside `offer_<Role>`:

```
offer_hosted_<Role>(io, node, capacity, host, start, deliver, cancel)
  : Result(SessionNode.Offer, SessionNode.RunError)
cluster_hosted_<Role>(io, node, session, host, start, deliver, cancel)
  : Result((), SessionNode.RunError)
```

`host : Pid(a)` as in `host_<Role>` (`Pid`'s parameter is phantom to linearity). Callback
types: `start : String -> Cap(Session.Live) -> Unit`, `deliver : String ->
Cap(Session.Live) -> Int -> Bytes -> Int -> Unit`, `cancel : String -> Cap(Session.Live)
-> Int -> String -> Int -> Unit`.

`SessionNode.offer_hosted(io, node, proto, fingerprint, my_role, peers, capacity,
on_close, host, start, deliver, cancel)`: `offer_role` with the session `start` closure
running `run_cluster_hosted_with`. Factor the offer-actor / invitation machinery so both
`offer_role` and `offer_hosted` share it (a `pfn offer_with(..., start : String -> (Int
-> Bool) -> Result((), RunError))` that both call).

**The actor side** (user code, shown in the guide): state holds `sessions :
LinearMap(String, <P>_<Role>.Parked_<Role>)`; the `Start(sid, s)` handler does
`register` + `await_*` and `put`s; `Deliver(sid, s, from, msg, ep)` does `take_slot(sid)`,
`resume`, then `fill` with the next `await_*` or `vacate` after `finish`; `Cancel(sid,
...)` does `take` and `cancel`. Session state that the actor keeps besides the parked
value (a per-session counter) goes in a second ordinary `Map` keyed by sid.

**HostWatch per session or per offer?** One `HostWatch` per session is simplest and
matches the standalone runner; an actor that dies takes every session with it, and each
watcher reports `HostDown` for its own party. Keep per session; note the cost (one small
actor per session) in the progress record.

## Files

`stdlib/session_node.march` (the two new runners, `host_party`, `offer_with`),
`lib/desugar/desugar_endpoints.ml` (the two generated functions; do NOT touch
`annotate`/`project`/`msg_module`, which other concurrent work edits),
`docs/choreography.md` + `specs/lang/choreography.md` (a subsection under "Hosting a role
in an actor": "Many sessions in one actor", with the `LinearMap` shape; update the
entry-point table), CHANGELOG, `specs/progress/2026-09-20-choreography-access-points-a2.md`,
and move `specs/todos/2026-09-18-choreography-access-points.md` to `specs/progress/`
(A2 was its last open phase; say the crash-branch part is
[[2026-09-20-crash-branches-implementation]]).

## Tests

- `test/two_node/cluster_ap_hosted`: node-a offers `Server` hosted in an actor with a
  `LinearMap` of parked sessions, capacity 4; node-b initiates three sessions
  CONCURRENTLY (three tasks) and each gets its own answer (`n * 10`), then one more
  after they finish. The actor prints one line per session with the sid's counter, sorted
  goldens (not ORDERED: three concurrent sessions). Precompile both nodes in scenario.sh.
- `test/two_node/cluster_ap_hosted_cancel`: as above, but node-b kills one of its
  sessions' peer early (a second initiator node, node-c, is killed mid-session): the
  actor's `Cancel` handler runs for that sid only, the other sessions finish. Three
  nodes; precompile.
- `test/test_endpoints.ml`: the `<P>_Run` shape test lists the two new functions.
- `stdlib/session_node.march` must still check clean (`test/dune`'s
  `session_node_check` pin: `dune build --root . ./test/session_node_check.out` and the
  file must be empty).

## Out of scope

Choosing an offer by load; an offer's capacity across a restart; crash branches for
hosted roles (that is B2 of the other spec).
