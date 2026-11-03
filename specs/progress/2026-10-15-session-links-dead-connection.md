# `[P2]` A session forming as a peer node dies links to the dead connection and never ends

**Filed and fixed** 2026-10-15. `test/two_node/drain_initiator_killed` (added by #986)
failed once in CI's `sanitize-gate (3/3)` (run 38682507255, job 116249980589) and passed
on rerun: after `node-b: node-c dead`, node-b's SIGTERM drain reached its hard deadline
(4 s) with 1 session still running and exited 1. No ASan report. Not a timing-bound
expectation: the 4 s hard deadline is generous for a session whose peer node is already
dead, and the run took ~7 s in all. It is a real race that ASan's slowdown made likelier.

## Cause

`ClusterNode`'s data reader, on its connection's end of file (`read_data`), ran the
close handlers (`data_closed`, which tells every session party `on_peer_closed`) and
only then sent the node actor `LinkClosed`. The connection's queue stays in `h.links` /
`h.qs` until its third release (`release_link`), so in between
`ClusterNode.session_queue_for` still handed out the dead queue.

A session forming in that window (`SessionNode.run_cluster_party`):

1. `cluster_links` got the dead queue for the peer's node, so did not wait (and
   never reached the `node_dead` check #986 added, which runs only for a MISSING queue);
2. subscribed with `on_peer_closed` after the close had already been told;
3. `recheck_links`, there for exactly this case, compared the queue with
   `session_queue_for`, which still returned it, and so took the link for current.

The link to the dead node never got `LinkEnded`, so `serve_cluster_outcome` (which
waits for every link's end) never returned, even after the endpoint itself was
cancelled. The offer's session count never dropped, and node-b's drain hit its hard
deadline.

Shown by stage markers in `run_cluster_party` with the reader's window widened by a
sleep between `data_closed` and `LinkClosed` (no ASan): the stuck session, on node-b,
formed 2 ms after node-c's last activity; node-a's role of the same session was
cancelled 4 ms later and ended; node-b's Ledger never ended.

## Fix

`read_data` marks the connection (`data_closed_key`, in `h.meta`) BEFORE running the
close handlers, and `h_queue_for` returns `None` for a marked connection; `release_link`
drops the mark before the fds close (a new connection may reuse the number). Every
party that got the queue before the mark either subscribed in time and is told, or
subscribed later and its `recheck_links` now sees no queue and reports the peer gone.
A session forming after the mark finds no queue, so `cluster_links` waits for a redial
or gives up once SWIM declares the node dead. A send on a connection that has already
ended now gets `Err(NoConnection)` instead of being queued into a closed socket.

## Tests

- `test/two_node/peer_closed_queue_gone` (new, two nodes, deterministic): node-b asks,
  from inside its `on_peer_closed` handler, for its session queue to the SIGKILLed
  node-a, and must find none. Red before the fix (2 of 3 runs printed `still handed
  out`; the one green run lost the race the other way), green after.
- `drain_initiator_killed` with the window widened failed 1 in 9 runs before the fix,
  0 in 6 after; unwidened, it did not reproduce locally under ASan in 23 runs (macOS),
  which is why the deterministic scenario above is the regression test.
