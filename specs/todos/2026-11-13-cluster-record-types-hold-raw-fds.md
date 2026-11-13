`[P3]` Cluster record types still hold raw `Int` descriptors (2026-11-13)

Ocap phase 2b, Task 9. The cluster plumbing (`NetKernel`, `ClusterConn`, `SessionNode`, `PeerRegistry`, `ClusterNode`, `NodeQueue`) is `@[stdlib_internal]`, so user code cannot call it with a descriptor, but its public record types still carry raw fds: `PeerRegistry.Peer { fd, data_fd }`, `ClusterNode.CnLink { cfd, dfd }`, `CnHalf { cfd, dfd }`, `NodeQueue.WriterState { fd }`, `SessionNode.Link { data_fd, control_fd }`. A user holding a `Peer` (from `ClusterConn.connect_to_peer`) can read an fd out of it, and the types are not in the handle-unsendable list (they are plain records of `Int`).

Expected: the fields hold `Socket` handles (adopted at the open), so a leaked record is not a descriptor and a cluster record cannot be forged with an arbitrary fd. This needs the cluster read/write loops moved from `NetKernel.*(fd, ...)` to `Socket` calls, or an opaque `Peer`.

Source: stdlib/peer_registry.march:12, stdlib/cluster_node.march:445-451, stdlib/node_queue.march:91, stdlib/session_node.march:91. Task 9 report: .superpowers/sdd/2026-11-10-ocap-p2-handles-plan/task-9-report.md.
