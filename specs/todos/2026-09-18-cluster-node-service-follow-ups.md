# `[P3]` Cluster node service: follow-ups

Filed 2026-09-18 when [[2026-09-18-cluster-node-service]] shipped (all four
phases). None of these blocks choreography access points.

## Open questions carried over from the design

- **Creation from wall-clock time** is monotone on one host but not across a
  clock step backwards; a persisted counter (`~/.march/node/<name>/creation`)
  is the alternative. The harness passes explicit creations.
- **Registering a local name instead of a pid** (`register_name(global,
  local_name)`, resolved through `Actor.whereis` on the holder), so a
  supervisor restart keeps the global binding valid.
- **ECONNREFUSED as Dead on multi-host deployments**, where a firewall can
  refuse too: maybe only when the advertised host is local. Needs a
  two-container measurement ([[2026-09-14-two-node-scenarios-partition-skew-monitor]]'s
  Docker-network variant).
- **The ticker** (a task sending `Tick` every 100 ms) versus a runtime timer.

## Things found while building it

- **Stdlib type errors hidden by the diagnostic filter.** `march --check` on
  the module itself shows errors a program that loads it never sees:
  `session_node.march` (match arms mixing `send(...)`, which returns
  `Option(())`, with `()` in HostWatch, the hosted `Drain` path and
  `run_party`; `Cap(IO)` without `needs IO`), and missing `needs` in
  `net_kernel`, `socket`, `swim_driver`. One such hidden error in
  `cluster_node` became a call of the wrong function (see its phase-3 record).
  `test/dune` now pins `cluster_node` clean; a sweep that `--check`s every
  stdlib module and ratchets the count down would catch the rest.
- **Three ClusterNodes in ONE process formed their mesh slowly** (more than 10 s
  in an in-process probe; three processes converge in about a second in
  `cluster_join`). Unexplained; nothing ships that way.
- **The partition witness does not isolate the Dead-member redial**: node-b's
  seed is node-a and seeds are redialled while unlinked, so the heal comes
  from there (a core test pins the Dead redial instead). A three-node
  partition where the healed pair are not each other's seeds would.
- **A typed send over the service.** `Node.send(peer, ...)` writes the socket
  directly and cannot be used on a node's connections; `Node.enqueue(q, ...)`
  with `ClusterNode.queue_for` works. A `ClusterNode.send(node, to, msg)` that
  the compiler rewrites like `Node.send` would read better.
- **Cluster session frames use `DropNew` and ignore its result**, as the standalone runner
  does: a frame larger than the queue budget (256 KiB here, 4 KiB standalone) or a burst
  past it is dropped silently and the session hangs or loses messages while both sides
  report Ok. A separate deadlock review of the standalone runner (decision graph node 2181,
  2026-09-18) found exactly that there. The fix belongs to both modes: an `emit` whose
  frame is refused should cancel the endpoint (a hole in the session is a failure), and
  frames bigger than the budget need a path (chunking, or a budget floor per frame).
- **Cluster sessions with two roles on one node** (a node has no connection
  to itself; they would need a local route).
- `SwimDriver.dispatch` / `dispatch_all` still write a peer's fd directly;
  the service uses `action_frames`. Only the legacy fixtures use dispatch.
