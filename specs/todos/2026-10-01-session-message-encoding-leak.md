# `[P2]` A session message costs far more than its bytes, and keeps costing after it is delivered

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
