# `[P2]` Distributed deploys, step 4 remainder: `ClusterHandle` as `Cap(Cluster.Live)` (D35)

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
D35 and section 7.2 (level 3). The rest of step 4 shipped:
[../progress/2026-09-22-dd-step04-per-role-grants.md](../progress/2026-09-22-dd-step04-per-role-grants.md).

**What.** `ClusterHandle` (`stdlib/cluster_node.march`) is a plain record; make it
`Cap(Cluster.Live)` with an `Ops` dictionary (`members`, `subscribe`, `register`,
`lookup`, `queue_for`, `route`, `creation`), minted by `ClusterNode.start` and swappable
by `Cluster.attach(io, ops)` in tests. `SessionAP` and `SessionNode` already take the
handle everywhere, so the change is the type of one parameter plus the dictionary
indirection at its use sites; the generated `<P>_Run` fronts name the type once
(`node : ClusterNode.ClusterHandle`, `Desugar_endpoints.run_module`).

**Why it waited.** Another session was editing `stdlib/cluster_node.march` when step 4
landed, and the piece is independent of the grants, the check and the peers.

**Acceptance.** A placement test injects `NodeDead` through an `Ops` dictionary and
asserts a role moved, with no sockets; the existing two-node cluster scenarios pass
unchanged.
