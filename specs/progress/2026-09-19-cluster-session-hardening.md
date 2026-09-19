# Cluster sessions: early frames, a queue bound, and a clean `session_node`

Shipped 2026-09-19. Three items of the choreography hardening pass (the fourth, a
miscompile that looked like a cluster bug, is
[[2026-09-19-purity-effectful-builtins]]).

## 1. An early frame no longer blocks the reader every session shares

A cluster session's frames arrive on the node's data connection to that peer, whose
reader is one task shared by every session and route on it. A frame for a session that
was not ready yet (its peers found, its party complete) made that reader POLL for the
session, up to 10 s. Every other session's frames, and the access-point invitations
routed on the same connection, waited behind it.

Now the reader never waits: it hands such a frame to that session's own endpoint actor
(`Early`), which holds it until `Ready` and replays it. Both go through one mailbox, so
the handoff cannot race and order is kept. A held frame is handled IN that turn
(`cluster_kind_here`), not re-sent to the mailbox, where it would land behind frames the
reader forwarded after it.

**`Ready` is sent after the role is driven to its first suspension**, not when the party
completes. A frame replayed earlier finds no handler installed and is parked where, in
the callback API, nothing drains it: the session waits for ever. (That is the reason the
standalone runner starts its readers after the drive.) The first version sent `Ready`
early and a 12-session stress hung 3 runs in 5; after the move, 8 of 8.

The race it closes is not new: main's reader forwarded a frame as soon as the party was
set, which could also beat the first handler, just less often.

## 2. A bound on what a peer that stopped reading can queue

Session frames are queued without limit so none is ever dropped
([[2026-09-18-session-frames-never-dropped]]). Standalone, the heartbeat gives a stalled
peer up and `drop_link` lets its queue go. In cluster mode there is no heartbeat: SWIM
watches whether the node answers, not whether it reads its data connection, so a peer
that stops reading could grow the queue without bound.

`send_frame` now checks the queue's depth first. Past `MARCH_SESSION_QUEUE_MAX_BYTES`
(default 64 MiB) unread for that peer, it is given up on, once: standalone the
connection is this session's own and is torn down; in cluster mode the connection is the
node's, shared with every other session to it, so only this session treats the peer as
gone and discards its frames from then on.

## 3. `session_node.march` checks clean, and stays clean

`march --check stdlib/session_node.march` reported 17 errors that no program ever saw
(bin/main.ml filters stdlib spans): four arms mixing `send`'s `Option(())` with `()`,
and missing `needs IO` / `IO.Process` / `Session.Live`. `cluster_node` had one such
hidden error compile to a call of the wrong function, so these are pinned now:
`test/dune` fails on any error or warning in the module. Hints are allowed: the runners
take `Cap(IO)` because `Session.attach` does, and the checker hints at every such
function.

Also cleared: ambiguous constructors (`RunError.Accept` / `Connect` / `Left` qualified;
`Stop` to the host watcher replaced by `kill`, so the watcher's `receive` has one arm
and no unreachable catch-all), and `show_roles` rewritten without recursion.

## 4. A test race in `cluster_sessions`

node-a read its link count after its sessions ended, but node-b calls
`ClusterNode.stop` as soon as ITS sessions end, which closes the connection. Under the
sanitizer's slowdown node-b usually won, and CI failed with "A: links 0" (seen on #524
and on main). The count is now taken inside each session, where node-b cannot have
stopped: its side waits for this role's Bye.

## Tests

- `test/two_node/cluster_queue_limit`: node-b is frozen after the go-ahead, node-a sends
  three 200 KB messages (the first goes out inside the node's 256 KB credit window, the
  second waits for credit) and the third finds the queue over the limit: the session ends
  "stopped reading", before SWIM notices. With the limit at 0 it ends "node node-b dead:
  suspect timeout" instead.
- `test/dune`: `session_node_check.out` must be empty (checked to catch a reintroduced
  mismatch).
- Every cluster scenario, and a 12-session-per-round stress by hand.
