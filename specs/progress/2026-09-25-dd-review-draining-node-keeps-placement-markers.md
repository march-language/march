# `[P2]` A draining node keeps its placement markers, so its `count = n` roles are offered nowhere until SWIM declares it dead

Filed 2026-09-24 by the distributed-deploys review (step 3, PR #610). Plan:
4.2 ("losing a role is a drain, not a cut"), D19.

## Defect

On SIGTERM, `close_all` (`stdlib/topology.march:419-423`) closes the offers
and sets `closing`, which stops `place_loop` (`:289`). Nothing unregisters the
node's `topo:<role>/<own id>` markers, and `drain_wait` (`:450-459`) ends in
`process_exit` without `ClusterNode.stop`. Other nodes still rank the draining
node first for its roles, so they do not offer them. That lasts through the
whole drain (up to `hard_ms`, 120 s by default) plus SWIM's suspect timeout. In
a rolling restart, a `count = 1` role is unavailable cluster-wide for about two
minutes.

## Confirmed

A scratch copy of `test/session/topology_placement.march` that prints the fake
registry after `Topology.close_all(c)`:

```
closed: n0 offers []
after close_all, n0's marker still registered: yes
peer n2 sees eligible ids: [n2, n1, n0]
```

## Fix I would make

In `close_all`, unmark every ranked role the node holds (a brief duplicate is
already tolerated, D19; running sessions continue). Call `ClusterNode.stop`,
or a graceful leave, before `process_exit` in `drain_wait`.

---

## Fixed 2026-09-25

`Topology.close_all` first unregisters the node's marker for every ranked role
(`mark(..., false)`), then retires its offers. `drain_wait` calls `ClusterNode.stop`
(close links and listener) before `process_exit`, on both the drained and the
hard-deadline path.

Test: `test/session/topology_placement.march` now prints, after `close_all`,
`after close_all, n0's marker still registered: no` and
`a peer sees eligible ids: [n1, n2]`; before the fix those were `yes` and
`[n0, n1, n2]` (the review's repro). D27's branch edits `drain` a few lines above;
expect a trivial merge.
