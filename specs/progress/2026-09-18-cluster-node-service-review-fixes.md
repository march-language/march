# DONE 2026-09-18 — cluster node service: review fixes

A review of the branch that shipped [[2026-09-18-cluster-node-service]]
(phases 0-4) found seven defects, all fixed here.

| # | Defect | Fix | Witness |
|---|---|---|---|
| 1 | A seed spelled differently from its node's advertised address (a hostname, another interface, 127.0.0.1 vs an explicit advertise) was redialled every time its dial deadline expired (~8 s); each redial REPLACED the live pair, cancelling every cluster session to that node. A seed naming the node itself was dialled forever. | `seed_ids`: a dial records which node the dialled address reached (`core_dialed`), a self-dial is recorded as us (`core_seed_self`, message `SeedIsSelf`); a seed is satisfied when that node is linked or is us. | core tests "a seed spelled differently ... is not redialled once linked", "a seed that reaches this node itself is never dialled again" (both red without the fix) |
| 2 | A dropped link's sockets were shut down, never closed: 4 fds leaked per dropped pair (both sides), and a rejected duplicate pair leaked too. | `release_link`: the fds close once the node's drop AND both readers are done (a close under a parked reader loses its wakeup; an early close lets a later shutdown or queued write hit the fd number after the OS reuses it), through each writer's mailbox -- new `CtlClose` on the control writer, new `NodeQueue.close` / `CloseFd` on the data writer, which then goes dead. A never-installed pair is a new `Discard` effect (need 1). Shutdown closes half-assembled inbound pairs. | two-node `cluster_fd_release`: 15 join/leave cycles, fds grow by at most 2 (pre-fix probe: +60) |
| 3 | A dial or handshake finishing after `stop()` installed a live link on the stopped node (readers parked forever: the process might never exit). | `Dialed` / `Accepted` on a stopped node close the fds instead. | (by construction; exercised by every scenario's stop) |
| 4 | `SessionNode.run_cluster` installed its peer-closed handler after finding its peers: a peer node whose connection ended in between was never reported, and with no heartbeat the session waited forever. | `recheck_links` after installing the handler: a link that is no longer its node's current queue is reported gone ("connection lost before the session formed"). | cluster session scenarios unchanged |
| 5 | `register` of a pid that had just died could leave a permanent binding to a dead process (its watcher's `LocalDown` raced the `Register`). | The node actor checks `is_alive` in the `Register` turn; a death after that is queued behind it. | -- |
| 6 | A registration refused by a race (register() had returned Ok) told nobody. | The name's watchers get `Lost(name, holder)`; the doc says so. | core test "a registration that lost a race tells the name's watchers" |
| 7 | The duplicate-pair rule ignored creation: a restarted peer's new pair could lose to a stale pair to its previous life until SWIM timed that out. | `CnLink.creation`; a newer creation's pair always wins. | core test "a pair from a newer creation of the peer replaces the old one" (red without the fix) |

All 22 root-free two-node scenarios, `run_stdlib` (885), `test_stdlib_march`
(69; `test_cluster_node` now 28 cases) green; `cluster_node` still checks
clean as the entry.
