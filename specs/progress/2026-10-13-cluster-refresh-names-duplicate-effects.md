# ClusterNode.refresh_names reported a rebound name twice (2026-10-13)

`refresh_names` (`stdlib/cluster_node.march`) walks every name visible before or
after a registry change and emits one `Named` effect per change. It built that list
as `List.dedup(List.append(Map.keys(st.vis), Map.keys(new_vis)))`, but `List.dedup`
drops only ADJACENT duplicates: with two visible names the list was
`["ap", "zz", "ap", "zz"]`, so every name present in both maps was visited twice.
An unchanged name emits nothing either time, but a name rebound to another pid
emitted its effect twice: watchers heard two `Bound`s, and a local registration
that lost the name heard `Lost` (and was dropped from `regs`, with an `Unwatch`)
followed by a `Bound` for the winner from the second visit.

Fix: the walk is now the old keys plus the new keys not already in the old map,
each name exactly once.

Test: `test/stdlib/test_cluster_node.march`, "names / a name rebound to another pid
is reported once" (two names held by b, then `ap` rebound from pid 7 to 9; exactly
one `ap bound to b`, nothing for `zz`). It fails on the old code at the count
assertion. Two-node `cluster_sessions`, `cluster_takeover`, `cluster_join` and
`cluster_ap_restart` pass.

Not changed, noted for follow-up: the same `List.dedup(List.append(..))` shape is in
`dial_targets` (a seed equal to an unlinked member's address, not adjacent to it, is
dialled twice in one tick) and in the fired-refs list of the DOWN path (duplicate
acks).
