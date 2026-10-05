# `[P1]` A pushed topology closes `Ctl.Control` on every node: the control plane has no leader after the first deploy

Found 2026-10-05 by the multi-host lab (`scripts/lab/run.sh deploy`, docs/lab.md), load
average 5.

In an app with a `[control]` section, the generated `main` places the control plane's
leader role itself: `Topology.offer_role("Ctl.Control", Topology.count_on(<label>, 1), ...)`
(lib/desugar/desugar_topology.ml). `Ctl.Control` is not in the topology digest's
`roles`: it is not the user's role, and `forge topology check` would reject it.

When a node re-reads its topology (a signed `TOPOLOGY` push from `forge deploy` or
`forge topology apply`, a SIGHUP, or a restart once a verified copy exists),
`Topology.apply_file` maps the build's roles through `apply_desired`
(stdlib/topology.march), which gives every base role the digest does not list
`PlaceNowhere`. `Ctl.Control` is one of them, so every candidate closes it:

```
control: API listening on port 7947
topology: Ctl.Control: placement count 1 on control -> not served here
topology: topology re-read from /var/lib/march/lab_app/.march/cas/hcr_state/0a40255212bcf7fc/topology.toml
```

and from then on every candidate answers `LEADER no` for good (checked minutes later on
all three). The pushed digest is the same file the node started with, `[control]` section
included; nothing in it asked for the change.

Consequences seen in the lab:

- after the first `forge deploy --via ssh` (restarts, then the topology pushed to each
  node's reload socket), there is no leader, so every later `forge deploy` on the
  cluster backend, `forge cluster cert --deliver` and `forge cluster revoke --deliver`
  have nothing to talk to (a plan made then sees no node running and plans restarts);
- with `--via auto`, the first deploy's topology release is accepted by a leader that
  closes its own role as the nodes apply the release; forge then reports
  `no control node answered: connection closed; ERR no_leader; ERR no_leader`
  ([2026-10-05-lab-forge-cluster-deploy-retry-and-leader-change.md](2026-10-05-lab-forge-cluster-deploy-retry-and-leader-change.md),
  part 2, is probably this).

Why the two-node `control_*` scenarios pass: their nodes never re-read a topology
(`control_forge_deploy` records v1's digest as deployed, so its release has no topology
step).

## Fix direction

`apply_desired` should leave roles the build places on its own (the control plane's, and
any other generated role the digest cannot name) at their base placement, or the digest
should carry the control plane's placement (from `[control]`) and `desired_of` should
read it. Add a `control_*` scenario that pushes a topology (or sends SIGHUP) and then
asks for a leader.

## Lab

`hot_role`, `leader_kill` and `cert_rotate` need a leader and are marked expected-fail on
this todo; `restart_persist` and `protocol_change` deploy over ssh (`--via ssh`) until it
is fixed.
