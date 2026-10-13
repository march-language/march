# `[P3]` A session message costs far more than its bytes (per-byte `List(Int)` framing); the retention after delivery is gone

Filed 2026-10-01 (dd step 12a). A session payload is a `derive Json` value encoded over
`List(Int)` framing (`stdlib/net_frame.march`, `NetFrame`): one cons cell and one tagged
Int per byte on the wire, built on both sides. Design section 2.5 of
`specs/plans/2026-09-28-dd-step12-control-plane-design.md` predicted "tens of MB of
allocation per node" for a 1 MB artifact; measured, it is worse, and some of it does not
come back.

## Measurements (compiled, macOS arm64, 2026-10-01)

- A `CtlFetch` session (the real roles, in-process transport) moving a 2 MB artifact as
  hex in 32 KB chunks: `fetched 1 x 4000000`, 31 MB RSS for one fetch; fine in isolation.
  But the three nodes of `test/two_node/control_partition`, each fetching the patch once
  over a real cluster session, went from ~100 MB to 1–2.5 GB each within ten seconds of
  the release being ordered, and never came back down.
- A `Ctl` session polled every 200 ms with a 900-byte report: +1.5 MB/s per node, all of
  it retained (see [2026-10-01-session-node-vault-tables-leak.md](../progress/2026-10-01-session-node-vault-tables-leak.md)
  for the per-session part).

## What the control plane does instead

- **Artifacts never travel as session messages.** `CtlFetch` was removed from the wiring
  (its protocol and roles stay in `test/session/control_peers.march` as the chaos/golden
  test of the generated roles). An agent fetches an artifact from a candidate's control
  API with `CAS_GET <hash>` (`DATA <size>` then the raw bytes, over the same TCP line
  protocol as `CAS_PUT`) and stores it through its own reload server. The three nodes
  above then stayed under 150 MB through the whole scenario.
- **A poll's report carries no `detail`** (the hello's does; the leader keeps it,
  `Control.leader_report`).
- **No `VERSIONS_DETAIL` in a report** (one line per function, ~14,000 in a small app).

## What remains

- Where the bytes go: whether `NetFrame`'s per-byte list is freed after decoding, and what
  the session runtime keeps per message (`SessionNode`'s `pending` / `heard` tables?).
  A repro: one in-process session, 1000 messages of 9 KB, `live_allocs()` before and after.
- A byte-string payload type for sessions (a `Bytes` message encoded as bytes, not as a
  JSON array of Ints) would make a chunked fetch over a session viable again.

## Re-measured 2026-10-13 (origin/main 3d2925fce): nothing is retained after delivery

The repro this file asked for, compiled, private HOME, `live_allocs()` before and after:

- **One node, in-process cluster session** (the `session_party_released` shape: an offer,
  `Ping_Run.initiate_Client` in a loop), 500 sessions of two messages each, i.e. 1000
  messages. Left behind after the run: 8,101 objects with a 2-byte `String` payload and
  8,101 with a 9,000-byte one, on macOS and on Linux (ubuntu arm64 container) alike. A
  9 KB message's per-byte `List(Int)` framing (Msgpack frame, `NodeQueue`) is freed; the
  ~16 objects per session that do stay are the session's registry tombstones (two names,
  8 objects each, kept 3 h by design) and the known one-`GlobalPid` leftover
  ([2026-10-07-session-refresh-names-globalpid-leftover.md](2026-10-07-session-refresh-names-globalpid-leftover.md)).
- **Two nodes over TCP** (`cluster_A` / `cluster_B`, 200 sessions, 9 KB echoed both ways):
  ~3,750 objects left per node either way, the same ~19 per session. Peak RSS ~90 MB per
  node with the 9 KB payload (the transient per-byte lists), and back.
- What the 10-01 numbers were: the nodes then still leaked every session's 13 Vault
  tables and every value a Vault write displaced (fixed by #785, 2026-10-05; see
  [../progress/2026-09-28-linux-per-session-memory-growth.md](../progress/2026-09-28-linux-per-session-memory-growth.md)),
  the likely source of the "some of it does not come back" part (not re-run on the
  10-01 tree, so not proven).
- While measuring, the two-node runs with a 2-byte payload were the SLOW ones: a registry
  that answered every pushed name change with its whole contents made session churn
  quadratic (fixed 2026-10-13,
  [../progress/2026-10-13-registry-push-answered-with-full-dump.md](../progress/2026-10-13-registry-push-answered-with-full-dump.md)).

So the leak half of this item is closed. What stays open is the cost half: a session
message is still encoded as one cons cell and one tagged Int per byte on both sides (a
9 KB message is ~9,000 cells of transient garbage per hop), and there is still no
byte-string payload type that would make a chunked artifact fetch over a session viable.
That is a performance feature, not a leak; the control plane does not need it
(`CAS_GET`, above).
