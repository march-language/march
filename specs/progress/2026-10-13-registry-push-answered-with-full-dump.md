# `[P1]` A pushed registry change was answered with the whole registry: session churn slowed to ~1-2 s per session and burst hundreds of MB

Found and fixed 2026-10-13, while re-measuring
[2026-09-28-linux-per-session-memory-growth.md](2026-09-28-linux-per-session-memory-growth.md)
and [../todos/2026-10-01-session-message-encoding-leak.md](../todos/2026-10-01-session-message-encoding-leak.md).

## Symptom

Two nodes, one runs role A and the other role B of back-to-back cluster sessions
(`Echo_Run.cluster_A` / `cluster_B`, a 2-byte payload), origin/main 3d2925fce:

| | before | after |
|---|---|---|
| Linux (arm64 container), 400 sessions | 326 s; ~55 ms/session for the first ~100, then ~1 s each; 3 sessions failed; node-a peak RSS 456 MB, node-b 273 MB; up to 7.5 M live objects mid-run | 23 s, flat ~56 ms/session; 0 failed; peak RSS 39 / 43 MB |
| macOS arm64, 400 sessions (stopped at ~500 of 600 before) | slowed from ~55 ms to ~2 s per session past ~250; peak RSS 286 MB; 0.1-0.5 M transient live objects | 22 s, flat; peak RSS 10-11 MB |

What stays after the run is the same before and after (~17 objects per session, back
within a few seconds of the last session): the registry's two tombstones per session
(8 objects each, kept for `MARCH_REGISTRY_TOMBSTONE_GRACE_MS`, 3 h by default; by design,
[2026-10-07-registry-tombstone-gc.md](2026-10-07-registry-tombstone-gc.md)). The bursts
were transient: live objects came back to that baseline once the nodes went quiet.

## Cause

`ClusterNode.push_leaves` sends every registry change (a register, an unregister, a
retired stale binding) to each linked peer as a `REGISTRY_SYNC_RESP` carrying the changed
leaf and the sender's root hash. `registry_frame` handled it like a full sync: after
merging, when its own root differed from the sender's, it answered with
`GlobalRegistry.all_entries` (every entry, tombstones included), and the receiver of that
answered it again the same way while its own root differed. A cluster session registers
and unregisters `session:<sid>/<role>` names on both nodes, so during churn the two roots
almost never match and nearly every push turned into full dumps in both directions. The
registry gains two tombstones per session, so each dump grows with the number of sessions
the pair has run: O(sessions) bytes per name change, each byte a cons cell and a tagged
Int on both sides (NetKernel/Msgpack over `List(Int)`), plus an O(n log n) sort and a
hash of every entry for each root computed. Hence the quadratic slowdown and the bursts.

Also, `core_tick` computed the registry's root hash (sorting and hashing every entry)
every 100 ms tick to build an anti-entropy request that is only sent every 30 s.

## Fix (`stdlib/cluster_node.march`)

- `push_leaves` sends its leaves with the root `push_root()` (`"push"`, never a real root:
  those are hex digests or `""`). `registry_frame` merges a pushed frame's leaves
  (`GlobalRegistry.observe` each, no root comparison) and never answers it. A divergence a
  lost push could leave is repaired by what already ran: the full sync both sides send at
  link-up and the periodic anti-entropy (REQ with a real root, then full RESPs).
- `core_tick` builds the anti-entropy request only when a peer is due.
- Wire compatibility: the frame format is unchanged. A node that predates this compares
  `"push"` with its own root, which never matches, and answers with everything, as it
  always did; a new node merges such an answer like any full sync.

## Tests

- `test/stdlib/test_cluster_node.march`, "a pushed registration is merged, not answered
  with the whole registry": node b's real push of a registration, delivered to a node
  that holds a name b lacks, binds the name and sends nothing back. RED on the old
  `registry_frame` (1/67 failed), GREEN after. A companion test pins that a full sync
  from a peer lacking our names is still answered.
- Two-node scenarios, Linux container, on the fix: cluster_sessions, cluster_join,
  cluster_takeover, session_churn, protocol_evolve, protocol_expand_contract, cluster_ap*,
  restart, hosted, session_redial and the other cluster_*/monitor/fan/gone ones pass.
  `partition` / `cluster_partition` need iptables (CAP_NET_ADMIN), not available there.

## Noticed, not changed

`refresh_names` still rebuilds the visible-name map from every entry (tombstones
included) on every tick and registry frame, and `List.dedup` there removes only adjacent
duplicates, so a name in both the old and the new map is visited twice. Neither showed up
in the measurements above once the dumps stopped.

## A test this exposed

`test/two_node/control_certs` checked, after revoking node c, that neither a nor c had
seen b die. c, cut off by a and b, rightly declares both dead once its SWIM suspect
timeout runs (measured: ~3.2-3.5 s after the cut), and the release completes ~3.6-3.7 s
after the cut, so the check raced the timeout. It probably passed on main because c's node
was busy with registry dumps; with them gone it failed 4 of 4 runs. It failed on main too, 1 of 4
(c timed out 0.2 s before the release completed). This branch's own fix (read only a's
output) was dropped when it joined the 0.5.0 release train: #961 fixed the same race on
main first, and better (it ignores c's lines after the revocation but still checks c's
lines from before it). The train keeps #961's check; its runs with this fix are recorded
in the train PR.
