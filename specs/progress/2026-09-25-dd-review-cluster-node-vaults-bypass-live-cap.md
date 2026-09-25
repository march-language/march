# `[P2]` ClusterNode's internal Vaults are found by name, bypassing `Cap(ClusterNode.Live)`

Filed 2026-09-24 by the distributed-deploys review (D35, PR #601). The naming
predates #601 (same at `35e8e77ce^`), but it defeats D35 and II.1: the cap is
meant to be the only way in.

## Defect

`stdlib/cluster_node.march:1812-1826` names every node Vault
`"cluster_node_<x>_" ++ cfg.name ++ "." ++ pid`. `Vault.whereis` and
`Vault.open` (`stdlib/vault.march:210`, `:77`) hand any named Vault to code
holding `IO.Mut`. That reaches the node's `meta`, `names`, `routes` and
`failed` Vaults, so such code can stop the node or hijack deliveries without
ever holding the node cap.

## Confirmed

A private function that never sees `Cap(ClusterNode.Live)` scans
`Vault.whereis("cluster_node_meta_vbnode." ++ int_to_string(i))` and sets
`stopped`. Compiled and run, it printed `found node meta at pid 0` and
`forced stopped=1 without the cap`.

## Fix I would make

Create the node's Vaults anonymously, or under an unguessable per-node
nonce, so `whereis` cannot find them. Or give Vault an unregistered
constructor for runtime-internal state.

---

## Fixed 2026-09-25

`ClusterNode.start` names the node's Vaults `cluster_node_<x>_<name>.<pid>.<nonce>`,
the nonce `Crypto.random_hex(16)` (128 bits; the module already declared
`needs IO.Random`). Nothing else looked these Vaults up by name. Only the naming
changed.

Test: `test/native/cluster_node_vaults_unnamed.march` starts a real node and scans the
old names (`meta` and `names`) over pids 0..4095: `node Vaults found by name: 0`.
Before the fix the review's scan found the meta Vault at pid 0.

Not done: the placeholder `cluster_node_unset_*` Vaults of an unset handle keep fixed
names; they hold no live node's state.
