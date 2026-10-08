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

## Next step

Record, for each watched object, the running balance per (inc site, dec site) pair, or
walk frame pointers with a bound at the proc's stack top, and look for the increment
whose holder never runs its release: likely a `Named(Bound(..))` watcher callback, or
`SessionNode.invite_role` / `fill_roles` storing the pid somewhere off-heap.
