# [P2] A partition heal could be reported as `NodeUp`, not `NodeRejoined` (cluster_partition flake)

**Logged and fixed:** 2026-09-26

## Symptom

`test/two_node/cluster_partition` timed out about one run in twenty on Linux
(CI run 36212137762 of PR #665; `scripts/two-node-docker.sh`: 1/20 on
origin/main, 1/15 on the PR branch):

```
node-a: registered leader
node-a: lost leader to node-b
node-a: never saw node-b rejoin
```

The registries had merged (the `Lost` arrived), so the link was back; only the
rejoin event was missing, on either node.

## Mechanism

`member_events` (`stdlib/cluster_node.march`) diffs the member view across
one `core_tick`. On the heal both nodes redial the Dead peer, and the
duplicate rule closes one of the two pairs; that close queues `ConnLost`. When
the new link's Alive observation (`core_linked`, incarnation + 1) and the
`ConnLost` are folded in the same SWIM step, SWIM goes Dead -> Alive ->
Suspect, so the tick sees Dead -> Suspect, which emits nothing. The peer's
refutation a tick later is Suspect -> Alive, and that was reported as
`NodeUp` unless the peer was in `rejoining`, which only held peers whose
*creation* changed. The scenario (like any subscriber that has already seen
the peer up) never heard a rejoin.

## Fix

`next_rejoining` also keeps a peer that was Dead before the step and is not
Alive after it, so its first Alive is reported as `NodeRejoined`.

Test: `test/stdlib/test_cluster_node.march`, "rejoin reporting": "a Dead peer
healed through Suspect (a closed pair in the same tick) is reported rejoined"
(Dead peer, `core_linked` + `core_link_closed` before one tick, then the
refutation). RED before the fix at its last assertion (no "b rejoined").
