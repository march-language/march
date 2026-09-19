# DONE 2026-09-18 — cluster node service, phase 4: sessions over the node

Phase 4 of [[2026-09-18-cluster-node-service]]: `SessionNode.run_cluster`
and the generated `<P>_Run.cluster_<Role>(io, node, session, body)` run a
choreography role over a running `ClusterNode`, which is the contract
[[2026-09-18-choreography-access-points]] builds on.

## What it does

- **Formation by name.** The role's endpoint actor gets a `ClusterNode.route`
  on its pid, then registers as `"session:<sid>/<role>"`; the peers are found
  by `lookup` (30 s) and each Link's queue is the node's data queue to that
  peer's node (`queue_for`). Links own no socket (`data_fd`/`control_fd` -1).
- **Frames.** Deliver / Bye / Cancel are the standalone frames with the
  session id appended to the type tag (`SessionNode.Deliver#<sid>`); the
  route refuses a frame for another session (DELIVERY_FAILED). Bye carries
  the sender's role in cluster mode (one route serves every peer, so the
  connection no longer says who sent it). The route handler waits for the
  party to be complete (a peer can only send after finding us, moments
  before), then sends Deliver / PeerGone to the endpoint actor as the
  standalone readers do, and a LinkEnded once per role.
- **Failure.** `ClusterNode.on_peer_closed`: when the data connection to a
  peer's node ends, every role on that node is `PeerGone(role, why)` with the
  node's cause ("node node-b dead: suspect timeout", "... connection
  refused", "connection lost"), told from the data reader AFTER its last
  delivery, so the drain rule holds. No heartbeat: SWIM decides.
- `finish` does nothing for a cluster party; `run_result` is shared with
  `run`. `cluster_node` now loads before `session_node`.

## Found and fixed on the way

- **A TRMC use-after-free** in the compiler
  ([[2026-09-18-trmc-reuse-hole-shared-scrutinee]]): Msgpack-encoding the same
  Bin payload twice corrupted it. The session's Bye/Cancel frames reuse one
  payload per peer and hit it on the second peer.
- The design's `BlockSender` for cluster frames was dropped for `DropNew`
  (as the standalone runner): a frame to a peer whose node is dead should be
  dropped, not block, and a live peer does not back 256 KiB of session frames
  up. The payloads are built inside the per-peer lambda.

## Witnesses

| Scenario | Pins | Red check |
|---|---|---|
| `cluster_fan_late_crash` (3 nodes) | the drain rule with the death reported by the node: B's 9 parked at C, node-b SIGKILLed, the session completes on A and C | (the TRMC bug made C crash here until fixed) |
| `cluster_session_silent` | a SIGSTOPped peer: A is cancelled with `node node-b dead: suspect timeout`, no session heartbeat | peer-closed handler not installed: A waits forever (timeout) |
| `cluster_sessions` | two concurrent sessions of one protocol between the same two nodes, one connection pair (`links 1`), each with its own result | role names without the session id: the second registration collides, s1 never completes |

All 21 two-node scenarios that need no root pass after this change
(including every standalone session scenario: fan, fan_early_crash,
fan_late_crash, gone, hosted, hosted_restart, protocol, restart, silent,
stream). `test_endpoints` pins `cluster_<Role>` in the generated `<P>_Run`.

## Limits (documented in docs/choreography.md)

Every role on a different node; a lost connection cancels the sessions
using it even if the node reconnects at once (frames in flight may be gone).
