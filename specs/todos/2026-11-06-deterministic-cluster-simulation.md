`[P3]` Deterministic simulation of a cluster with fault injection, in one process.

Rung 6 of the distributed-proof ladder (2026-11-06 discussion; medium effort). Testing, not
proof: FoundationDB, TigerBeetle and Antithesis style.

## What it gives

Whole-cluster scenarios (several nodes, sessions, supervision, hot deploys) run in one
process on a simulated network and clock: message delay and loss, partitions, node crashes and
restarts, clock skew, all driven by one seed, so any failure replays exactly. Combined with
`2026-11-06-protocol-runtime-monitors` every run is a checked trace, and with
`2026-11-06-systematic-interleaving-exploration` the scheduler choices inside a node are
controlled too.

## Builds on

- The two-node harness and its scenarios (`scripts/two-node.sh`, partition / skew /
  monitor_reconnect / hosted / protocol; todo `2026-09-14-two-node-scenarios-partition-skew-monitor`),
  which today run real processes over loopback and are timing-dependent (the hosted and
  protocol scenarios have known flakes).
- The interpreter scheduler (single-threaded, controllable) and the node/transport layer
  (`stdlib/cluster_node.march`, `NetKernel`), which would get a simulated transport.

## Shape

1. A simulated transport and clock behind the cluster API (`ClusterNode.attach` already takes an
   ops dictionary: the test seam).
2. A fault schedule DSL (partition at t, heal at t', crash node n, skew clock by d) generated from
   the seed or written by hand.
3. Port the two-node scenarios to it; keep the real-process versions as a smaller smoke set.
4. On failure: the seed, the fault schedule and the message trace.

## Done when

- Every current two-node scenario runs under simulation, deterministically, across 1000 seeds,
  in under a minute; the known flaky scenarios either pass deterministically or fail with a
  replayable seed that points at a real bug.
- A rolling hot deploy (expand, then contract) runs under random partitions without a protocol
  monitor violation.
