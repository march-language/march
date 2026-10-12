# `[P2]` A restarted node offers a `count = 1` role at once, before it knows its peers: two nodes offer it for the settle period

Found 2026-10-05 by the multi-host lab (`scripts/lab/run.sh failover`, docs/lab.md), main
at 53d66f068, load 7.

`Order.Ledger` is placed `{ on = "books", count = 1 }` over lab-3 and lab-4. The lab stops
the container offering it (lab-4); lab-3 takes it over within a second (the stopped
host's links close, and a refused redial is definite). Then the lab starts lab-4 again
and samples both nodes' status files every half second
(`LAB_DIR/logs/failover-timeline.txt`, condensed):

```
t=1s..16s   lab-4=yes lab-3=yes    (24 samples: both offer Order.Ledger)
t=16s..45s  lab-4=yes lab-3=no     (36 samples)
```

The restarted node offers the role 1 s after it starts, and lab-3 keeps it until lab-4
has counted as rejoined for `MARCH_PLACEMENT_SETTLE_MS` (15 s). For those 15 s two nodes
offer a `count = 1` role with no partition at all, and the settle period meant to stop a
returning node pulling roles back is applied by its peers but not by the node itself.

## Cause (from the code)

`Topology.reconcile_role` (stdlib/topology.march) ranks this node against
`eligible_others`, the members whose eligibility marker this node can see in its registry
replica and that have settled. A node that has just started has not synced the registry
yet, sees no other marker, ranks first among itself alone, and opens the offer at its
first tick. Nothing makes a starting node wait for its first registry sync, or for the
settle period, before taking a ranked role.

## Fix direction

A starting node should not take a ranked role before it has synced with its seeds (or
before `settle_ms` from its own start), the mirror of the rule its peers apply to it.
A two-node test: B holds a `count = 1` role, restart A (which ranks higher), and assert A
does not offer it for `settle_ms`.

## Lab

`failover` asserts the returning host does not offer the role inside the settle period,
and is marked expected-fail on this todo.

## Fixed 2026-10-12

**Cause.** As above: `reconcile_role` ranked a just-started node against the markers in
its own registry replica only. Before its first registry sync it saw none, so it ranked
first among itself alone; and even after the sync, its peers did not count it (they saw
`NodeRejoined` and apply `MARCH_PLACEMENT_SETTLE_MS`) while it counted itself, so a
returning node that ranks first offered the role for the whole settle period beside the
survivor that held it. Waiting for the first sync alone would not have fixed it.

**Fix.** The settle rule is now applied by the node to itself, for opening a ranked role
it does not already offer (`Topology.may_open`, pure, called from `reconcile_role`):

- Before its first registry sync (`ClusterNode.registry_synced`: a peer's registry
  replica has been merged, or the node was started with no seeds) it opens no ranked
  role, for at most `MARCH_PLACEMENT_SETTLE_MS` from when placement began: a node whose
  seeds are all unreachable still takes its roles after the bound, and a seedless
  (single-node) cluster is unaffected.
- While a peer counts it as rejoined (`ClusterNode.rejoined_at`, within the settle
  period) it opens the role only if the other non-dead nodes marked eligible cannot fill
  the count without it (fewer than n), the mirror of the peers' view. It never drops an
  offer it holds because of this, so a partition heal (both sides offering) is as before.

`rejoined_at` is the moment a peer's MEMBERS_SYNC (sent when a link comes up) showed this
node at an earlier creation, or Dead at its own creation: the cases in which that peer's
`member_events` report the node as `NodeRejoined` (members are never reaped, so a peer
always remembers). The core counts it (`CnState.remembered`, `self_stale`) and the I/O
layer stamps the time in `mirror`; `reg_synced` is set when a REGISTRY_SYNC_RESP is
merged. Both are new `ClusterOps` fields; `ops_stub` answers synced / never rejoined, so
fake clusters behave as before. The survivor's takeover is unchanged: it is synced and not
rejoining. A deferral is reported once ("ranks for it but a peer counts it as rejoined and
it is settling"); the bounded wait for a first sync is silent.

**Tests.**

- `test/stdlib/test_topology.march`: the decision (`may_open`) for the restart case,
  the first-sync gate and its bound, a rejoining node still filling a count its peers
  cannot. RED by perturbing `may_open` to ignore `rejoined_at`: two tests fail.
- `test/stdlib/test_cluster_node.march`: a peer's real `core_linked` MEMBERS_SYNC to a
  node restarted at creation 2 counts as remembered, the registry sync after it sets
  `reg_synced`; a fresh node is not remembered, a seedless node is synced. RED by
  perturbing the count: fails at the `core_remembered` assertion.
- `test/two_node/topology_rejoin` (new): node-b ranks first for a `count = 1` role, is
  SIGKILLed, node-a takes it over, node-b restarts at creation 2 and places at once; it
  must not offer the role until `MARCH_PLACEMENT_SETTLE_MS` (4 s here) after a peer showed
  it rejoining, then takes it back and node-a drains. GREEN: `two-node[topology_rejoin]:
  ok`. RED with the old `stdlib/topology.march` copied back (into `stdlib/` and the staged
  `_build/default/stdlib/`): node-b's golden differs with `offered Ledger.Server inside
  the settle period`.

Also run green: two-node `topology_move`, `drain_initiated`, `hosted_protocol_change`,
`control_leader_kill`, `control_plane`, `control_certs_restart`; the dune goldens
`native_topology_place`, `native_topology_hook_timeout`, `topology_placement`,
`topology_conflict`, `topology_pinned`. `control_certs` failed ("b died") the same way on
this change and on main, at load average ~80: pre-existing, not this change.

**Lab.** `scripts/lab/scenarios/failover.sh` no longer lists this item in `LAB_XFAIL`
(nor its "inside the 15s settle period" failure text); it stays expected-fail on
`2026-10-05-lab-restarted-node-offers-invisible.md`. The lab itself (containers) was not
run for this fix.
