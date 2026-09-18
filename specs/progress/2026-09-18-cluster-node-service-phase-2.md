# DONE 2026-09-18 — cluster node service, phase 2: the registry

Phase 2 of [[2026-09-18-cluster-node-service]]: the node holds a live
`GlobalRegistry` replica, with `register` / `unregister` / `lookup` /
`names` / `watch` / `unwatch` / `stale_bindings` on `ClusterNode`.

## What it does

- **Core** (`core_register`, `core_unregister`, `core_local_down`,
  `core_lookup`, and registry frames 5/6 in `core_frame`): a registration's
  clock is `GlobalRegistry.next_clock` (the name's clock, our slot bumped), so a
  takeover after seeing a binding is causally newer. `unregister` is
  `unregister_own` (compare-and-delete). A local change is pushed at once to
  every linked peer (REGISTRY_SYNC_RESP with the changed leaf); a new link
  exchanges the whole registry; `SwimDriver.anti_entropy_peers` (30 s) sends
  REGISTRY_SYNC_REQ with the root hash, answered with everything when the
  roots differ. A RESP whose root differs from ours after merging is answered
  with our whole registry -- two rounds at most, since both then hold the join.
- **Visibility.** `vis` is recomputed after every change (and every tick,
  since a holder going Dead hides its bindings): a binding is visible unless
  its holder is Dead here or has a different creation than the binding (a
  restart). A binding of a holder we have not heard of is visible. Changes go
  to watchers as `Bound` / `Unbound` / `Lost`: `Lost(name, winner)` when a
  binding made HERE is superseded by another holder's, visible or not.
- **Owner tombstoning.** After every merge, our own present bindings from an
  earlier creation are tombstoned (`unregister_own` with a bumped clock) and
  the tombstones pushed.
- **Local holder death.** `register` spawns a `RegWatch` actor that monitors
  the pid (the SessionNode.HostWatch pattern: `Down` is a raw message read
  with `receive`); its `Down` sends `LocalDown(pid)`, which unregisters every
  name the pid held. An unregister or a Lost kills the watcher.
- **Mirrors**: `lookup` / `names` read a Vault of the visible bindings.

## Fixed on the way (phase 1 code)

`cluster_stall` hung 2 runs in 8 with node-b printing "done" and never
exiting: `stop` closed the listen socket right after the wake-up connection,
and a close drops the fd's kqueue registration, so an acceptor whose wake-up
had not yet been delivered never woke. The acceptor now closes the listen
socket itself when it sees the stop flag. 10/10 after.

## Parser traps hit again

A multi-line `a &&` newline `(match ...)` inside a match arm, and a one-line
`match kv do (k, f) -> if ... end end` inside a lambda, both failed to parse
("I got stuck here" / "expecting ->"). Rewritten with `let` and a named helper.

## Witnesses

| Scenario | Pins | Red check |
|---|---|---|
| `cluster_takeover` (no root) | node-b holds "leader", SIGKILL, node-a sees Unbound and takes it over; node-b restarts as creation 2, resolves "leader" to node-a, and retires its own stale "cfg" binding | retire_stale disabled: `my stale bindings: 1`; a fresh clock instead of `next_clock`: node-a's claim loses to node-b's stale one at once (timeout) |
| `cluster_partition` (root, iptables) | both listen ports dropped until each marks the other Dead; each claims "leader"; after heal both print node-b (the tiebreak's winner, higher node_id) and node-a's watch prints `Lost` | see the phase-2 commit notes / CI: needs Linux root, run via scripts/two-node-docker.sh |

`scripts/two-node.sh`'s `drop_link` takes a list of ports (default node-b's):
in the service both nodes listen and either may redial the other, so dropping
one port lets a new connection route around the fault.

Unit tests: 7 new cases in `test_cluster_node` (21 in all); two perturbed
assertions fail as expected. Phase-1 witnesses re-run green.
