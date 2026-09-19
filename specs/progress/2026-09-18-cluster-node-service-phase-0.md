# DONE 2026-09-18 — cluster node service, phase 0: the data model

Phase 0 of [[2026-09-18-cluster-node-service]] (the design, still open for
the later phases). All pure; every old wire shape still decodes.

- **`Membership.Member`** gains `creation`, `name`, `addr` (the advertised
  "host:port"). The merge order is lexicographic over (creation, incarnation,
  severity): a restarted node outranks every verdict about its previous life.
  `alive/suspect/dead(id, inc)` keep building the origin-less shape (creation
  0, name = id, addr ""), which is what the legacy tag-3 gossip frame and every
  hand-wired fixture produce. New: `member(...)`, `with_status`, and `verdict`,
  which builds a Suspect/Dead about a node with the origin fields the view
  already holds -- a verdict built origin-less (creation 0) would be outranked
  by the member it is about, so `Swim.end_period` / `expire_suspects` /
  `refute` and `SwimDriver`'s `PeerDown` now use it.
- **`Swim.suspect_member`** and **`SwimDriver.ConnLost(id)`**: a closed
  connection as a hint (Suspect, suspect timer armed), beside `PeerDown`,
  which stays the definitive Dead.
- **Tags 13 MEMBER_GOSSIP / 14 MEMBERS_SYNC** (`SwimDriver.encode_member_gossip`,
  `encode_members_sync` and decoders): a member with its origin fields. Tag 3
  was already overloaded by element count. `SwimDriver.action_frames` turns a
  `Swim.Action` into (destination, frame) pairs for a transport with its own
  writers.
- **`GlobalRegistry.Entry`** gains `creation`; the tiebreak is node_id, then
  creation, then pid. New `register_at`, `entry`, `next_clock` (the name's
  clock with our slot bumped: a takeover after seeing a binding is causally
  newer), and `unregister_own`, a compare-and-delete (plain `unregister`
  tombstones whatever is present). `root_hash` now covers the clock and the
  creation, so replicas that differ only there still exchange them.
  REGISTRY_SYNC_RESP leaves carry the creation as a sixth element; 4- and
  5-element leaves still decode.
- **`Handshake.Hello`** gains `addr` (the sender's advertised address), sent
  as a sixth element only when set, so a hello without one is byte-identical
  to before. `NetKernel.handshake_addr` runs the handshake sending it, every
  read bounded by one deadline and asking for at most the bytes still missing
  (a SIGSTOPped peer's kernel still completes the TCP connect and then never
  sends a hello).

Witnesses: new cases in `test_membership` (creation order, verdict origin),
`test_global_registry` (compare-and-delete, a stale unregister cannot erase
the winner, a takeover is causally newer, the hash covers creation and
clock), `test_net_kernel` (leaf creation, the 5-element leaf),
`test_handshake` (addr round trip, the addr-less hello), `test_swim_driver`
(the new frames, ConnLost -> Suspect -> Dead, action_frames). Proved to fail
on a flipped merge order. The existing `stall`, `skew`, `partition` goldens
are unchanged (`stall` re-run: ok).
