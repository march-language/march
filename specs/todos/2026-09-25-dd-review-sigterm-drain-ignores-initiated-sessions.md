# `[P2]` The SIGTERM drain counts only offer sessions

**Filed** 2026-09-25 from the distributed-deploys review's unconfirmed item 3.
Confirmed from the code, which is deterministic here: `Topology.running`
(stdlib/topology.march) sums `active` over the node's open and draining offers and
has no other input. Sessions a hook's task started with `initiate_R`, or a
hand-written `cluster_R`, are not counted, so a pool that serves no role exits 0 at
once on SIGTERM and cuts its in-flight initiated sessions. The step-3 progress entry
says it "exits 0 once no session runs", with no listed deviation.

**Fix.** Count initiated sessions too, e.g. a per-node counter that
`SessionNode.initiate` maintains (session_node.march: coordinate with its owner),
and add a test: a pool that serves no role, initiates a long session from its hook,
gets SIGTERM, and must wait for it.
