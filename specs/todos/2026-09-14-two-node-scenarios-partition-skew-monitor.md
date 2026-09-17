# `[P3]` Two-node scenarios: the two-container Docker-network variant

Filed 2026-09-14 as the remainder of
[[2026-09-14-two-node-failure-semantics-harness]] (now a progress record).

**Validated 2026-09-17:** every scenario this file listed has shipped (`partition`, `skew`,
`monitor_reconnect`, and since then `fan`, `gone`, `hosted`, `hosted_restart`,
`protocol`); `scripts/two-node.sh --list` is the live inventory. The one open item is the
section at the end, the two-container variant, and it stays P3: nothing needs a fault
loopback cannot express yet. The shipped sections are kept below for the links.

## Scenario `partition` (was 2)

**Shipped 2026-09-15** with [[2026-09-15-two-node-partition-scenario]] (progress record).
It found the bug it was written to catch: `REGISTRY_SYNC_RESP` dropped every entry's
`VectorClock`, so after a split each side kept its own binding. Fixed in the same change.
`drop_link` / `heal` drop both directions on the scenario port; pfctl is not implemented,
and macOS runs it through `scripts/two-node-docker.sh`.

## Scenario `skew` (was 4)

**Shipped 2026-09-15** with [[2026-09-15-two-node-skew-scenario]] (progress record): the
outcome was the bug, not a documented limit, and the one-line-class fix (age a load by
receipt time) landed with it; nothing left here.

## Scenario `monitor_reconnect` (was 5) and the `restart` monitor half

**Shipped 2026-09-15** with [[2026-09-15-monitor-fire-at-least-once]] (progress record); nothing left here.

## The Docker-network variant

**Half shipped 2026-09-15.** `scripts/two-node-docker.sh` (image `ci/Dockerfile.two-node`)
runs any scenario on Linux from any host: both nodes in one container, with iptables
applied to its own loopback. What remains is the variant this section asked for: the two
nodes in **two containers** on a user-defined network, with real routing, faults through
`docker exec` / `docker pause`, and a nightly-class CI job. The single-container runner
covers every fault the scenarios apply today, so nothing currently needs this; it is
worth building when a scenario needs a fault loopback cannot express (latency, MTU, one
host unreachable while another is not).

## Also

- The harness's `ORDERED=1` mode and per-node goldens carry over; a
  scenario with a wall-clock-dependent line (`skew`) must print booleans,
  not timestamps.
- Scenario programs should keep printing from one actor or the main thread
  per node; `stall` and `stream` are the templates.
