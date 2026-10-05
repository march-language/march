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
