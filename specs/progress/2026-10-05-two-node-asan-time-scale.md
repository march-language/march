# two-node: in-program deadlines scaled under ASan (sanitize sweep flakes)

Landed 2026-10-05. Test/CI-only in effect: nothing changes unless
`MARCH_SANITIZE` is set or one of the three new `MARCH_SWIM_*_MS` variables is.

## The problem

The sanitize gate's two-node sweep (`specs/lang/golden/sanitize.sh`, Corpus 3)
runs every `test/two_node` scenario with `MARCH_SANITIZE=1` and
`TWO_NODE_TIMEOUT=240`. Across 2026-10-01..05 nearly every CI run failed it on a
DIFFERENT scenario, none with a sanitizer report. The harness's own waits were
already 240 s; what tripped were deadlines INSIDE the nodes, which ASan's
slowdown (worse on a loaded 4-vCPU runner) pushes past:

- SWIM's 3 s suspect timeout declaring a slow but healthy peer dead
  (`hcr_new_code_session`, measured 2026-09-29; `session_churn`, PR #785;
  `cert_update_replay`, PR #779). Each was patched in its own scenario
  (`HCR_SUSPECT_MS`, `CHURN_SUSPECT_MS`, a 600 s suspect in the node).
- `topology_move` (run 37318071834): node-b reports "cannot be offered ...
  its endpoint name is held by another offer on this node". That report is
  `Topology.on_conflict`, reached only once `MARCH_PLACEMENT_CONFLICT_GRACE_MS`
  (5 s) has passed since the node last retired an offer: under ASan the node
  actor took longer than 5 s to release the name.
- `cluster_ap_restart` (job 110623577738): node-b re-offered as creation 2, but
  node-a's hard-coded 20 s `wait_new_offer` ran out first ("the restarted
  offer never appeared").

ClusterNode's SWIM timings could not be moved from outside at all: the
control-plane scenarios exported `MARCH_SWIM_PROBE_MS=300 MARCH_SWIM_SUSPECT_MS=1500`
(control_plane/lib.sh, hcr_role_policy, control_forge_deploy), but nothing ever
read them.

## The mechanism

- `ClusterNode.config` takes its SWIM defaults from `MARCH_SWIM_PERIOD_MS`
  (1000), `MARCH_SWIM_ACK_MS` (500) and `MARCH_SWIM_SUSPECT_MS` (3000) when set
  to a positive integer. A record update of the config still wins. Unset, the
  config is exactly what it was.
- `scripts/two-node.sh`: under `MARCH_SANITIZE`, `TIME_SCALE` is
  `TWO_NODE_ASAN_SCALE` (default 5), else 1. Every node is launched through
  `run_node`, which (only when `TIME_SCALE` > 1) multiplies each deadline that
  DECLARES A FAILURE by it: the scenario's value, or the stdlib default when
  the scenario set none. The list: `MARCH_SWIM_SUSPECT_MS`,
  `MARCH_SESSION_CONNECT_MS`, `MARCH_SESSION_TIMEOUT_MS`,
  `MARCH_PLACEMENT_CONFLICT_GRACE_MS`, `MARCH_HOOK_TIMEOUT_MS`,
  `MARCH_CONTROL_AGENT_GRACE_MS`. Poll intervals and "wait at least" delays
  (`*_TICK_MS`, `*_POLL_MS`, `MARCH_PLACEMENT_SETTLE_MS`, the CAS grace, the
  control API idle close, which `control_api_auth` measures) are left alone:
  scaling them only slows a slow run further. With `TIME_SCALE` 1, `run_node`
  is a bare `exec`, so the normal two-node job is unchanged.
- SWIM's probe period and ack timeout are NOT scaled, only its suspect
  timeout. A suspect is cleared by its own refutation, which travels on the
  next probes' gossip, so a longer period slows exactly what the suspect
  timeout is waiting for. Measured below: all three scaled by 3 or by 4 still
  declared node-a dead; the 1 s period with a 15 s suspect timeout (5 x 3 s,
  hence the default 5) did not.
- `TWO_NODE_TIME_SCALE` is exported for a node's own deadlines
  (`cluster_ap_restart`'s waits use it), and `ctl_until` (control_plane/lib.sh)
  stretches its poll limit by it, as does `ctl_release`'s default `FOLLOW_S`.
- `TIME_SCALE_EXEMPT` lets a scenario keep a deadline unscaled where the
  deadline IS the test: `slow_start` (A's 4 s start must outlast the 2 s
  heartbeat timeout).
- The three hand-written launchers (`ctl_start`, `rp_start`, `fd_start`) end
  with `run_node`; their dead `MARCH_SWIM_*` exports are dropped, since they
  would otherwise now tighten SWIM to 1.5 s in the normal job.
- `hcr_new_code_session`'s `HCR_SUSPECT_MS` special case is removed (covered).
  `session_churn`'s `CHURN_SUSPECT_MS` (#785) and `cert_update_replay` (#779)
  are not on main yet and are left to those PRs.

## Not covered (not timing)

- `cluster_stop_loopback`: node-a never exits (a hang past 240 s);
  `specs/todos/2026-10-03-cluster-stop-loopback-asan-exit-hang.md`.
- `control_artifact_digest` "ERR not_staged": main breakage, fixed by #790.
- `protocol_evolve` / `protocol_expand_contract`: still skipped under ASan
  (`specs/todos/2026-09-25-protocol-evolve-under-asan.md`).

## Reproduction

In `ci/Dockerfile.two-node` (linux/arm64, ubuntu 24.04), capped at 2 CPUs
(`docker update --cpus 2`) with 2 busy loops for a loaded runner, the gate's
`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 MARCH_SANITIZE=1 TWO_NODE_TIMEOUT=240`.
`TWO_NODE_ASAN_SCALE=1` is the control: this tree with no scaling, i.e. main
without `hcr_new_code_session`'s own patch.

(results being filled in)
