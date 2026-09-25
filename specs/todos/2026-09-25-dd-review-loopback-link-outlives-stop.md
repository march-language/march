# `[P3]` The loopback link outlives `ClusterNode.stop`

**Filed** 2026-09-25 from the distributed-deploys review's unconfirmed item 4.
Confirmed from the code: `h_stop` (stdlib/cluster_node.march) sets `stopped`, sends
`Shutdown` and wakes the acceptor, but never closes the loopback writer that
`NodeQueue.start_local` made, and `deliver_loopback` checks the frame's creation but
not `stopped`. `queue_for(h, own_id)` still returns `Some`, and the sink closure stays
in the global `node_queue_sinks` Vault (stdlib/node_queue.march). Harmless in a
process that exits; in one that starts and stops nodes (tests, embedding) it leaks
and keeps local sessions running after stop.

**Fix.** Close the loopback writer in `h_stop`, drop its sink, and make
`deliver_loopback` refuse once `stopped`. Test: start a node, stop it, and assert a
local initiate fails and `queue_for(h, own)` is `None`.
