# `[P2]` Choreography access points: repeated sessions and local restart

Filed 2026-09-18 as phase 4 of [[2026-09-18-choreography-failure-handling]], whose phases 1
to 3 shipped. That design sequenced this one "design note first", because it has an open
question the others did not; this file is that note's starting point.

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

## The open question

**Forming sessions when a role has many instances** (one server, many clients). Maty's
access point establishes a session as soon as one registration per role is present. Across
nodes, the lowest-numbered role's node is the natural matchmaker, since it already listens
under the connect rule. What it must decide: how it pairs registrations, what a client
waits for, and what happens to a registration whose node dies before its session forms.
Settle that here before building.

Several sessions per hosting actor need a map from session id to the linear
`Parked_<Role>`; that collection is designed in [[2026-09-18-linear-map]].
