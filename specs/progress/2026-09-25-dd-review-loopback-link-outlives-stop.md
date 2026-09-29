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

## Fixed (2026-09-28)

- `h_stop` (stdlib/cluster_node.march) now closes the loopback link: it drops
  `qs["loop"]`, so `queue_for(h, own_id)` (and `session_queue_for`, and
  `send_msg` to the node itself) answer None / `Err(NoConnection)` from then on,
  and sends the loopback writer `CloseFd`.
- `NodeQueue`'s `close_fd_state` now forgets a LOCAL queue (fd <= -2) when it
  is closed: its sink leaves the process-wide `node_queue_sinks` Vault and its
  `b<fd>`/`q<fd>` budget entries leave the queue table (`forget_local`). A local
  id is never reused, so nothing else ever dropped them.
- `deliver_loopback` refuses once the node is stopped: a frame queued before
  `stop` and handed to the sink after it is answered "node stopped" through the
  DELIVERY_FAILED handler instead of reaching a route.

**Test:** `test/two_node/cluster_stop_loopback` (one node): a session over the
loopback works before `stop`; after it, `queue_for(own)` is None, the node's
sink is gone from `node_queue_sinks`, a raw send to itself is refused, and a
local initiate fails.

**Red without the fix** (stdlib files reverted to `5f4aa31dc`, same scenario):

```
-queue to self after stop: none
-loopback sink released: true
-send to self after stop: refused
+queue to self after stop: some
+loopback sink released: false
+send to self after stop: queued
```

With only the `node_queue.march` half reverted, `loopback sink released: false`
alone, so each half is needed. Two things the scenario does not tell apart:
the "initiate after stop" line already read `refused` before the fix (the
initiator's own registration fails on a stopped node, `Err(Stopped)`), so it
guards against a regression but did not go red; and the `stopped` check in
`deliver_loopback` covers a frame racing `stop`, which no scenario can time
reliably.
