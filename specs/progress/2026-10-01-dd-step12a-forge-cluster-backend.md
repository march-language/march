# Distributed deploys, step 12a: `forge deploy` on the cluster backend, the upgrade fixture, the leader's audit log

**Design:** `specs/plans/2026-09-28-dd-step12-control-plane-design.md`, sections 4, 8, 9 and
10, D37-D41. Finishes the operator-facing items #731 left open
([2026-09-30-dd-step12a-control-wiring.md](2026-09-30-dd-step12a-control-wiring.md)); what is
still open is in [../todos/2026-09-28-dd-step12a-control-wiring.md](../todos/2026-09-28-dd-step12a-control-wiring.md).

## What was built

- **`forge deploy` selects the cluster backend** (`Cmd_deploy.choose_backend`): `--via
  auto|cluster|ssh`, `auto` meaning cluster when the environment's topology has a `[control]`
  section. Why the topology and not a flag or a `[backend] kind = "cluster"`: the `[control]`
  section is what makes the nodes run the control plane, and a node in control-plane mode
  takes its hot changes as sequenced releases from the leader; a second backend kind would
  have to agree with it, and `[backend] kind = "ssh"` is still needed for the restart-class
  steps (D38) and `forge host init`. `--via ssh` is the break-glass path (design 12, open
  question).
- **The cluster path** (`Cmd_deploy.run_cluster`): `make_plan` over the leader's STATUS
  instead of ssh (`cluster_node_status`: a node is up when it reports), the plan's pools cut
  into **segments** in plan order (consecutive hot pools share a release, the topology goes
  in the last one, a restart-class pool closes the release before it and runs over ssh
  through `restart_pool`, factored out of the ssh path). Each release segment goes through
  `Cluster_deploy.prepare` (STATUS, waiting up to 120 s for a leader, as after a restart
  segment; `build_release`), `upload_artifacts`, `send_and_follow`. A control plane that
  does not answer at plan time (nothing runs yet: a first deploy, all restarts) is planned
  as no node running.
  Afterwards forge records the deploy as the ssh path does, so the next plan compares
  against it. A release's scratch directory is under `/tmp`: the recorder's Unix socket under
  a project's `.forge/` passed macOS's 104-byte `sun_path` (`ENAMETOOLONG`).
- **`--plan` on the cluster backend** adds "6. Through the control plane" (each segment;
  restart-class ones marked NEEDS SSH with their hosts) and "7.n", each release it would
  sign, in full, also saved as `.forge/deploy/<env>/build/release-<n>.txt`. Seq and parent are
  taken again when it is sent. A later release in the same plan is shown over the earlier
  one's digest.
- **Progress**: `Cluster_deploy.follow` prints `step k of N: <step>` for every step it
  passes, including one that began and ended between two polls (`(done)`), then the leader's
  decisions and NOTE lines as they change; a halt is the error, with the leader's reason and
  every node's report.
- **`--status`** (the leader's view) and **`--audit [N]`** (the audit log, below); both need
  only the topology, not the deploy key or host records. `--follow SECONDS` (default 1800).
  `FORGE_CONTROL_ENDPOINTS=host:port,...` overrides the endpoints, which are otherwise each
  host carrying the candidates' label (its ssh target's address) at the `[control]` port.
  `FORGE_DEPLOY_NATIVE=1` builds a Linux host of this machine's own target natively (CI's
  two-node job has no zig).
- **The leader's audit log** (`Control.audit_release/order/step/decision`, the lines; the
  wiring writes them): `<MARCH_CONTROL_DIR>/audit.jsonl` on every candidate, JSON lines in the
  node log's shape (`ts`, `type`, then `leader` and the type's fields). Every release offered
  (accepted, or refused: `err_stale`, `err_fork`, `err_parent` at the compare-and-set,
  `err_invalid`, `err_sig`, `err_parse`, `err_store`, `err_replicate`), every order sent
  (`order`), every answer (`step`), and the release's `halt` or `complete` (once per release).
  The leader appends and queues each line; a copier task on each candidate sends the queue to
  the other candidates once a second (`AUDIT_COPY <size>`). `AUDIT [n]` answers one
  candidate's file; `Cluster_deploy.audit` asks them all and shows the union in time order.
- **`forge test --upgrade-from` through the control plane** (`Upgrade_test.deploy_through_
  control`): when the topology has `[control]`, it waits for a leader that hears from every
  process, then sends one release (the patch on every pool at once) and follows it; no
  reload socket is used for the deploy. `forge run --processes` gives each process its own
  `MARCH_CONTROL_DIR` (`.forge/run/<node>.control`) and `MARCH_CONTROL_PORT_OFFSET=1000`.

## Found and fixed on the way

- **A release ordered activations no node can take.** `Control_release.record_hot` answers
  the recorder's ABI_QUERY with every function of the last deployed manifest. The control
  wiring (spliced into the entry module, outside the hot-reload prefix) has no slots, and its
  ~80 functions change hash whenever the entry file's length changes; the release ordered
  them and every node refused the batch (`ERR commit_partial_failure`, `err_abi` in the node
  audit log). `Cluster_deploy.build_release` now asks the candidates for VERSIONS_DETAIL and
  gives the recorder the manifest restricted to real slots (`restrict_manifest`), which is
  what `forge deploy hot` activates against a real node. The hash instability is filed:
  [../todos/2026-10-01-control-wiring-hashes-follow-entry-file.md](../todos/2026-10-01-control-wiring-hashes-follow-entry-file.md).
- **A cluster member that runs no Agent held every rollout.** `ctl_ready` waited for a report
  from every live member, so the upgrade test's traffic node (a cluster member, no Agent)
  kept the leader at "waiting for every node to report". An Agent now marks itself
  (`Topology.marker("Ctl.Agent", node_id)`, bound to its respawner); a marked member is
  waited for until it reports, an unmarked one for a grace period from when the leader first
  saw it (`MARCH_CONTROL_AGENT_GRACE_MS`, default 20 s), so a member whose mark has not
  propagated yet is not skipped. A step passed without a late member is caught up when it
  reports (the executor is level-triggered).

## Tests

- `test/two_node/control_forge_deploy`: the real `forge` against three local nodes started
  from the project's v1 base (forge's own build flags, its digest, host records of this
  machine's target, v1 recorded as deployed). `--plan` (control-plane section, "nothing needs
  ssh", a signed release, no node changed), the deploy (`--canary 1`: per-step progress,
  complete, every node applied it once), a second deploy is "nothing to deploy", `--status`,
  `--audit` (the accepted release, an order per node, the completion) and both candidates'
  own `AUDIT`, then a stale release (`hcr_deploy release-stale`) refused and audited
  `err_stale`, `--audit 3`. A fake `ssh` must record nothing.
- forge/test/test_upgrade_from.ml, "the same patch through the in-cluster control plane
  passes": fixtures/upgrade `control_v1` (v1's topology with two control candidates) as the
  ref, `live` as the working tree (the new role body spawns a task, reads the old Vault and
  starts a session): the release reaches both processes, the traffic gets the new body's
  answer, nothing dropped, and no process is deployed through its socket.
- forge/test/test_deploy_plan.ml, "cluster backend": segments (releases between restarts,
  the topology in the last release or one of its own), the backend choice, the endpoints
  (ssh targets to addresses, the override), the recorder's baseline restricted to slots.
- test/stdlib/test_control.march, `audit`: the lines are JSON with the node log's fields, a
  refusal is named by its kind (stale, parent, fork, invalid), a quoted reason survives.
- The existing `control_*` scenarios pass unchanged.
