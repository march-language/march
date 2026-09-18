# Choreography session frames are never dropped

Shipped 2026-09-18. Found by a deadlock review of the choreography runtime
(`stdlib/session_node.march`), after [[2026-09-18-choreography-failure-handling]].

## The bug

Every session frame (Deliver, Bye, Cancel, Ping) went through the peer's
`NodeQueue` under `DropNew`, and SessionNode ignored the result. `DropNew` refuses a
frame once more than the 4096-byte budget is queued waiting for credit, so:

- **A message over the budget was always refused.** Two nodes, `A -> B : String`
  (5000 bytes) then `B -> A : Int`: B waited for the string, A waited for the reply,
  both kept heartbeating, and neither ever finished. 3000 bytes worked.
- **Bursts lost most of their frames, silently.** A sending 300 messages of 200 bytes
  in a row: B received 54, and both nodes reported a clean close.
- **A lost Bye or Cancel** did not hang, but ended the session about 10 s later with
  the wrong cause ("no heartbeat").

A second hang sat on the same path, independent of the drop. The receiver announces
its consumed total only every budget/4 bytes (`NodeQueue.consumed`), so up to 1023
consumed bytes can stay unannounced for good, and the writer sent a frame only when
`sent + len <= granted`. A frame over 3/4 of the budget that followed a small message
waited on credit that never came: 900 bytes then 3400 bytes, each under the budget,
hung both nodes.

## The fix

`stdlib/node_queue.march`:
- `may_write`: the head frame may also go when everything written may already be
  consumed (`sent - announced < budget / 4`). At most one such frame plus budget/4
  bytes is then in flight.
- `fits`: a frame larger than the whole budget is admitted into an empty queue, alone,
  under every policy; it could never fit otherwise.
- New policy `Unbounded`: never refuses, never waits; the frame queues past the budget
  and still goes out only under credit.
- `close`: the owner gives the connection up; the writer stops, lets its queue go and
  answers blocked callers. A frame for a dead writer is let go instead of kept.

`stdlib/session_node.march`: every session frame goes through `send_frame`, under
`Unbounded`. The heartbeat's teardown is `drop_link`, which now also closes the queue,
so a peer that stops reading costs at most what was sent to it before the heartbeat
timeout. Pings stay `DropNew`: while the queue is full, data frames already prove the
sender alive.

### Why not `BlockSender`

The first version blocked the sender for credit (`BlockSender`, bounded by the session
timeout). It passed every burst and size test, and hung `stalled_reader`: sends run in
the endpoint actor's turn, and `BlockSender` rides `Actor.call`, which in an actor's
handler takes the actor's own incoming messages as its reply
([[2026-09-18-actor-call-in-handler-takes-own-messages]]). The reader's `LinkEnded` and
the heartbeat's `PeerGone` were swallowed, and `serve` waited forever. Blocking would be
the wrong shape even with that fixed: a node's one endpoint actor serves every peer, and
waiting on one slow peer would hold up the rest. `Unbounded` matches local actor
mailboxes, which are unbounded too.

## Tests

- `test/two_node/bulk`: 900, 3400 and 20000-byte messages, B's count of what arrived,
  then a burst of 500 × 500 bytes sent inside the endpoint actor's turn. Hangs on main's
  stdlib. With only `may_write` reverted it fails too: the 20000-byte frame never goes,
  the pings queued behind it never reach B, and B declares A dead.
- `test/two_node/stalled_reader`: A streams 20000 × 500 bytes inside the endpoint
  actor's turn to a B that is frozen mid-stream; A must finish. Hung with the
  `BlockSender` version.
- `test/stdlib/test_node_queue.march`: an oversized frame into an empty queue;
  `Unbounded` admits past the budget. `test_node.march`'s typed-enqueue backpressure
  test now overflows with a second frame (a lone oversized one is admitted by design).
- Stress, by hand: 2000 × 3000 bytes and 200 × 20000 bytes on one scheduler thread, and
  5000 × 10 bytes: every frame delivered.

Throughput with frames near the 4096-byte window is low (about 1 MB/s for 3000-byte
frames), because each frame waits for a credit round trip. Not addressed here.
