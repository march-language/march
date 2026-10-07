# `[P2]` GlobalRegistry tombstones are never collected (design proposal)

Found 2026-10-06 while chasing what a cluster session leaves behind
(specs/progress/2026-10-06-session-ops-leak.md and its follow-ups). After the leak fixes,
a single-node session probe leaves ~72 objects per session. About 15 of them are the
`GlobalRegistry` tombstones for the session's `session:<sid>/<role>` names: an `Entry`
record, its `VectorClock`, the name string and the map node, per role.

This is by design today. `unregister` leaves `present = false` (an LWW-element-set
removal) so that a delayed, causally older binding gossiped from another replica cannot
resurrect the name. But nothing ever removes a tombstone, and session names are unique per
session (the sid is never reused), so a long-running node's registry, and every Merkle
anti-entropy round over it, grows by one entry per finished session role, forever.

## Options

**A. Causal-stability GC (precise).** A tombstone may be purged once every live member has
seen it: each node already carries per-name vector clocks, and SWIM gives membership. Each
node gossips its *stable frontier*, the pointwise minimum of the clocks it has acked from
every current member; a tombstone whose clock is dominated by the frontier can never be
overtaken by an older binding still in flight, so it is dropped. Cost: a new piece of
gossip state and a membership-change rule (a member that leaves stops holding the frontier
back; one that rejoins with a new `creation` cannot carry old bindings, since those are
already hidden and tombstoned by creation).

**B. Grace-period GC (simple).** Purge a tombstone after it has been a tombstone for a grace
period G (Cassandra's `gc_grace_seconds`), G much longer than any partition the cluster is
expected to heal from (hours). Cost: one timestamp per tombstone (local bookkeeping, like
`registrant`: never on the wire, not hashed). Risk: a partition longer than G can resurrect
a name whose holder is gone. For a holder that is gone, the node service already hides a
binding from an earlier creation and the owner re-tombstones it, so the damage is bounded.

**C. Ephemeral names outside the CRDT.** `session:` names live exactly as long as a session
and are looked up only by its parties. Register them in a scope without tombstones (a
plain delete), accepting that a delayed duplicate can briefly re-add one. Cost: a second
registration path, plus deciding which names are ephemeral.

## Recommendation

B, with G configurable (default a few hours) and purging done during the existing
anti-entropy tick. It is local, needs no new gossip, keeps the Merkle hash meaning "same
live view", and its one failure mode is already bounded by the creation check. Do A only if
a deployment needs exactness across long partitions. C is the cheapest fix for sessions
alone, but it adds a second set of name semantics.

The decision is the user's; nothing here is implemented.
