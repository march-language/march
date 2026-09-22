# `[P2]` Distributed deploys, build step 8: local reconciler, placement, automatic drain, `forge test --upgrade-from`

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), sections 4.2, 5, 6.2, 6.6, II.6, II.8, D16, D19, D21, D27.
Groundwork done: G6 (`Procs`), G7 (`Hosts.run_on`).

**What.** `forge/lib/reconcile.ml` with `Backend.{hosts; run_on; push_topology;
status}` and the `local` backend on `Procs` (`push_topology` writes the JSON and sends
SIGHUP). Nodes open their own offers from the pushed topology (D16). Placement for the
monolith: `on`, `count` by rendezvous hashing over SWIM membership, hysteresis,
settling period, local-first offers. Automatic drain at loop boundaries with
`_or_drain` overrides and `loop atomic` (D27). `forge test --upgrade-from <ref>`:
worktree at `<ref>`, build, start under `Procs`, drive `test/upgrade_*.march`, deploy
the working tree through `cmd_deploy_hot.run` on a local socket, assert on `PINS` and
delivery-failure counters.

**Acceptance.** A three-node local cluster moves a `count = 1` role off a killed node
once SWIM declares it dead; `forge test --upgrade-from HEAD~1` passes on a fixture app
and fails on one whose upgrade drops messages.
