# `[P2]` Two-node scenarios still to write: partition, clock skew, and the Docker variant

Filed 2026-09-14 as the remainder of
[[2026-09-14-two-node-failure-semantics-harness]] (now a progress record).
The harness (`scripts/two-node.sh`) and three scenarios exist: `restart`
(creation counter), `stream` (`Session.Ops` over the network), `stall`
(SWIM suspect → dead → refutation). Each remaining scenario pins a claim
the docs still make in prose only.

## Scenario `partition` (was 2)

Drop packets A→B for 10 s while both run SWIM (the `stall` programs, both
sides symmetric); both mark the other `Dead`; each keeps its own registry
bindings (`GlobalRegistry`); on heal, `GlobalRegistry.merge`'s tiebreak on
`(node_id, pid)` picks the same winner on both sides — the CRDT law in a
real split rather than the in-process `g44` merge.

Fault hooks: on the ubuntu CI leg `sudo iptables -I INPUT -p tcp --sport
$PORT -j DROP` (GitHub runners have passwordless sudo — the CI workflow
already uses it for apt); on macOS `pfctl` needs sudo and is skipped with
a loud message unless `TWO_NODE_SUDO=1`. The harness gains `drop_from
<a|b>` / `heal` helpers that apply and remove the rule and record whether
they ran; a scenario that needs them and cannot get them exits 3 ("skipped:
needs root"), which CI treats as failure and local runs as skip.

Registry traffic today is the sync frames on the control connection; the
scenario needs the `GlobalRegistry` sync loop driven by the same tick as
SWIM (the `stall` programs' loop plus the `anti_entropy_peers` timer, which
`SwimDriver` already exposes).

## Scenario `skew` (was 4)

**Shipped 2026-09-15** with [[2026-09-15-two-node-skew-scenario]] (progress record): the
outcome was the bug, not a documented limit, and the one-line-class fix (age a load by
receipt time) landed with it; nothing left here.

## Scenario `monitor_reconnect` (was 5) and the `restart` monitor half

**Shipped 2026-09-15** with [[2026-09-15-monitor-fire-at-least-once]] (progress record); nothing left here.

## The Docker-network variant

The same scenarios with the two nodes in two containers on a user-defined
network: real routing, a real `iptables` inside the container (no sudo
needed), and the only way to run `partition` without touching the host.
`scripts/two-node.sh --docker` builds one image from `ci/Dockerfile.ubuntu`
(only `bin/main.exe`; its own `dune build` needs `node`, see the memory
note), starts `node_b` and `node_a` containers, and applies faults with
`docker exec` / `docker pause` (`pause` is `stall`'s SIGSTOP). A separate
CI job, nightly-class (~5 min), on the ubuntu leg.

## Also

- The harness's `ORDERED=1` mode and per-node goldens carry over; a
  scenario with a wall-clock-dependent line (`skew`) must print booleans,
  not timestamps.
- Scenario programs should keep printing from one actor or the main thread
  per node; `stall` and `stream` are the templates.
