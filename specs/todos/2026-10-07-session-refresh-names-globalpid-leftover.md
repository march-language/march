# `[P3]` One `GlobalPid` per cluster session is never released

Filed 2026-10-07, the last per-session leftover after
specs/progress/2026-10-07-mixed-tail-aggregate-leak.md and
specs/progress/2026-10-07-monitor-leaked-both-actors.md. With both fixes and tombstones
expiring at once (`MARCH_REGISTRY_TOMBSTONE_GRACE_MS=1`), the single-node session probe
(`test/native/session_party_released.march`, 40 sessions) leaves ~2 objects per
session. One of them is a 40-byte `GlobalPid.Pid` record.

## What is known

- Allocated in `ClusterNode.refresh_names` (`visible_map`'s per-name lambda): the pid of
  a visible registry name, one per session (a `session:<sid>/<role>` endpoint name).
- At exit it has refcount 2 and NO heap referrer (a referrer scan of every live
  `march_alloc` object), so both references sit off-heap: a Vault's C table, a mailbox
  node, a timer entry or a C-side registry.
- Not `h.names`: `ClusterNode.names` reports a single present name after the run, and
  `Vault.set` / overwrite / `Vault.drop` of a record value is balanced (probe).
- Not the party's slot Vault: `close_cluster_party` closes it.
- An RC watch of every such object (alloc site filter, every inc/dec with three frames,
  `MARCH_TRACE_GC` makes the inline fast path call out) shows the survivors' histories
  differ from freed ones only in the number of balanced inc/dec pairs, with no single
  unmatched site at three frames. Walking more than three frames up crashes at the green
  thread's stack root, so a deeper view needs a bounded frame-pointer walk.

## Narrowed 2026-10-07 (with specs/progress/2026-10-07-reused-closure-captures-leak.md)

- That fix (a closure cell reused by FBIP now releases its captures) took the probe from
  ~2 objects per session to ~16 total for 40 sessions; the GlobalPid is what remains,
  about one per session.
- The surviving pid is the session's offer actor (`local_pid=2`), not a party's.
- A bounded frame-pointer walk (32 frames, stopping at the green thread's stack top)
  replaced the three-frame view. It still shows no unmatched increment site.
- A compile-time listing of every apply function that keeps a used capture alive
  (the class the closure fix closed) names no closure that captures a `GlobalPid`
  directly, so the pid is not held by a leaked closure cell.

## Next step

Follow the offer actor's pid off-heap: log every `Vault.set` / mailbox enqueue /
timer registration whose payload contains a `GlobalPid` with `local_pid=2`, and pair it
with its release. Candidates are the offer's `Named(Bound(..))` watcher registration and
`SessionNode.invite_role` / `fill_roles`.
