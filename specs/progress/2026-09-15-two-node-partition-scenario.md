# Two-node scenario `partition`: a real split, and the registry sync that lost its clocks

Shipped 2026-09-15, closing the `partition` part of
[[2026-09-14-two-node-scenarios-partition-skew-monitor]]. That todo stays open for the
two-container Docker-network variant.

## What the scenario pins

`test/two_node/partition`. Both nodes run the `stall` SWIM loop over one connection and
hold a `GlobalRegistry` replica.
1. After both have an ack, the harness applies `drop_link`: iptables drops every TCP
   packet to or from the scenario port on loopback, in both directions.
2. The connection stays open and TCP retransmits, so this is a partition, not a close.
   Each side reaches `Dead` on timeouts alone.
3. Each then registers `leader` for itself, concurrently, in its own half.
4. `heal` removes the rules. SWIM's refutation brings each peer back to `Alive`.
5. node-a sends a `REGISTRY_SYNC_RESP` with all its entries. node-b merges it
   (`GlobalRegistry.diff_entries`), prints, and answers with its merged registry.
6. node-a merges, prints, and closes.

The claim is the CRDT law `g44` pins in process: both sides print the same leader, and
the tiebreak (higher `node_id`) picks `node-b`.

Harness (`scripts/two-node.sh`): `drop_link` / `heal` use Linux iptables, as root or
through passwordless sudo, and the rules are removed on exit. Anywhere else the scenario
exits 3 ("skipped: needs root"). CI's ubuntu leg has passwordless sudo and runs it
through `--list`. pfctl is not implemented; macOS uses the Docker runner below.

## The bug it found, on the first run

Before the fix, node-a printed `leader after merge -> node-a` and node-b printed
`-> node-b`: the replicas never converged. `NetKernel.encode_registry_sync_resp`
encoded each leaf as `[name, node_id, pid, present]`, although the module header already
documented a clock field. The decoder filled in `VectorClock.new()`. An empty clock is
causally *before* any local claim, so `GlobalRegistry.wins` kept the local binding on
both sides. The in-process `g44` merge never saw this, because it never crosses the wire.

Fix: a leaf is `[name, node_id, pid, present, clock]`, with `clock` as
`[[actor_id, ts], ...]` (`VectorClock.entries`, rebuilt with `VectorClock.advance`). A
four-element leaf, the original encoding, still decodes with an empty clock. Unit tests
(`test/stdlib/test_net_kernel.march`) cover the clock round-trip, the legacy leaf, and
concurrent claims merged through the codec converging on both sides. After the fix both
nodes print `-> node-b`.

## The Docker runner (half of the "Docker variant")

`scripts/two-node-docker.sh <scenario>... | --all` runs scenarios in a Linux container
built from `ci/Dockerfile.two-node`: the ubuntu CI toolchain plus iptables, with no
source baked in. The checkout is bind-mounted and built into a named volume, never the
host's `_build`. The container gets `NET_ADMIN` and runs as root, so the partition applies
to its own loopback. The build uses `@bin/warm-cache`, because `bin/main.exe` alone
stages no runtime into a fresh build dir (clang then fails on
`march_monitor_registry.h`).

Measured in that container: `partition` passed 3/3 (about 6 s each), and `restart`,
`stream`, `stall`, `skew` and `monitor_reconnect` all passed on Linux.
