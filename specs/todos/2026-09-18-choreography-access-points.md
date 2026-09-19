# `[P2]` Choreography access points: repeated sessions and local restart

Filed 2026-09-18 as phase 4 of [[2026-09-18-choreography-failure-handling]], whose phases 1
to 3 shipped. That design sequenced this one "design note first", because it has an open
question the others did not; this file is that note's starting point.

**Built on [[2026-09-18-cluster-node-service]]** (shipped the same day): access points are
found by name through the node's `GlobalRegistry` replica, and cluster-mode sessions
multiplex over the node's peer connections, with SWIM as the failure detector. What is there
to build on: `ClusterNode.register / lookup / watch` (a `Lost(name, winner)` tells an access
point it no longer holds its name after a partition heals), and
`SessionNode.run_cluster` / `<P>_Run.cluster_<Role>(io, node, session, body)`, which forms
a session by registering each role's endpoint under `"session:<sid>/<role>"` and finding
the others by name. What an access point adds is choosing `<sid>` and pairing registrations
(the open question below).

## What it is for

Maty's recovery story (Fowler and Hu, *Speak Now*, section 5): a failed session is cancelled
and discarded, a supervisor restarts the crashed actor, and the restarted actor registers
again at an **access point** and joins the *next* session. No cross-node restart
coordination is needed. Today the runner runs one session per `run` call, so "start again"
means every node calling `run` again, arranged by whoever runs the nodes.

## The outline

- **A network access point.** A node offers a role of a protocol for repeated sessions
  rather than one. Each established session gets a fresh **session id** (Maty's fresh
  session name), carried in the hello and in every frame, so a node partitioned out of a
  session, or restarted, can never rejoin it.
- **Several sessions at once** per node or hosting actor (the paper's KP3). The party state
  (`SessionNode.Party`) becomes per session.
- **Restart is local.** The supervisor restarts the actor; it registers again; the next
  session forms. The surviving roles, cancelled out of the failed session by phases 1 to 3,
  register again themselves.

## Decisions (2026-09-19)

- **Access points are found by name through `GlobalRegistry`, and that comes first.** The
  registry is a CRDT data type with a sync wire format, but nothing runs it: there is no
  live node that assembles SWIM, the peer connections and a registry replica, and SWIM
  members carry no addresses. So step 0 of this item is a **cluster node service** (joining
  from seeds, SWIM with advertised addresses, one persistent connection per peer, a synced
  registry replica, `register`/`lookup`/watch). It is specced separately.
- **Sessions multiplex over the node's peer connections**, carrying a session id, and SWIM
  is the failure detector for cluster sessions: a node declared dead cancels all its roles
  in every session.
- **Several sessions per hosting actor are checked statically**, not with a runtime
  use-once flag. That needs two pieces of type-system work: record fields holding a linear
  value tracked like linear fields (shipped 2026-09-19,
  [[2026-09-19-record-field-holding-linear-value]]) and a keyed collection that can hold
  linear values (a `LinearMap`, specced separately).
- **The standalone runner stays** (environment addresses, per-connection heartbeat) as the
  no-cluster mode.

## The open question

**Forming sessions when a role has many instances** (one server, many clients). Maty's
access point establishes a session as soon as one registration per role is present. Across
nodes, the lowest-numbered role's node is the natural matchmaker, since it already listens
under the connect rule. What it must decide: how it pairs registrations, what a client
waits for, and what happens to a registration whose node dies before its session forms.
Settle that here before building.

Several sessions per hosting actor need a map from session id to the linear
`Parked_<Role>`; that collection is designed in [[2026-09-18-linear-map]].
