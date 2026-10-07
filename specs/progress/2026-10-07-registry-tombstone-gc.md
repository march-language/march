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

## Built (2026-10-07): option B, with the stamp on the wire

The user chose B. A purely local timer (each replica stamps a tombstone when it first
sees it) does not converge. Anti-entropy re-sends every entry whenever two replicas'
root hashes differ, and replicas purge at slightly different moments, so the first to
purge is handed the tombstone back by a peer that has not purged yet, with a fresh
countdown. The two can trade it indefinitely. So the stamp travels with the entry.

- `GlobalRegistry.Entry.retired_at` (Unix ms; 0 = present, or not stamped yet). Not in
  the Merkle hash (`entry_to_bytes` is unchanged) and no part of the merge order. Two
  copies of the same tombstone (Equal clocks) keep the EARLIER stamp (`observe`), so a
  re-sent copy never restarts a countdown.
- `GlobalRegistry.collect_tombstones(reg, now, grace_ms)` stamps unstamped tombstones and
  drops those stamped at least `grace_ms` ago. Present bindings are untouched.
  `tombstone_count` is new too.
- Wire: the stamp rides in the leaf's clock array as an extra `[0, ms]` pair
  (`NetKernel.encode_registry_sync_resp` / `decode_retired`). A node that predates this
  skips any pair that is not `[actor_id, ts]`, so the leaf format is unchanged for it.
  Adding a seventh leaf element was not an option: the old decoder requires exactly one
  element after the clock, and would have read every creation as 0. In a mixed cluster
  the old nodes never purge and keep re-sending unstamped copies, so tombstones persist
  there as they do today; collection starts once every node runs this.
- `ClusterNode`: `CnConfig.tombstone_grace_ms` (default 3 h, from
  `MARCH_REGISTRY_TOMBSTONE_GRACE_MS`), and `core_tick` runs the collection at most once
  a minute and at least four times per grace (`CnState.reg_swept_at`). A tombstone
  outlives its grace by at most one interval.

## Measured

- In isolation, each tombstone held costs 8 objects (entry record, clock, name, map
  node); a registry churned through 100 names and collected keeps none of them.
- Single-node session probe (`session_party_released`) with
  `MARCH_REGISTRY_TOMBSTONE_GRACE_MS=1`: every sweep empties the tombstones (two per
  session), and per-session leftovers fall by 4 objects. With the default 3 h grace they
  accumulate as before until they expire.

## Tests

`test/stdlib/test_global_registry.march` ("collect_tombstones"): stamp-keep-drop, present
bindings kept, a re-sent copy keeps the earlier stamp, an expired copy from a peer is
dropped at the next pass, the stamp is not hashed. `test/stdlib/test_net_kernel.march`:
the stamp round-trips without touching the clock or creation, a present binding carries
none, and two replicas that stamped 300 ms apart both end empty after re-syncing.
Perturbation: a `collect_tombstones` that never drops turns the registry suite red.
