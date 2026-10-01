# Distributed deploys, step 12a: the control plane wired into the cluster

**Design:** `specs/plans/2026-09-28-dd-step12-control-plane-design.md` (sections 3-9, D37-D41).
Builds on the pure core ([2026-09-28-dd-step12a-control-core.md](2026-09-28-dd-step12a-control-core.md)).
What is still open is in [../todos/2026-09-28-dd-step12a-control-wiring.md](../todos/2026-09-28-dd-step12a-control-wiring.md).

## What was built

- **`reload_request(line : String) : String`**, a stdlib-only builtin. `handle_client`'s verb
  chain is now `handle_line`, run over an I/O channel that is a real fd or a request held
  in memory; the socket loop and the builtin are the same code. A mutex keeps the
  file-static scratch buffers single-user. In-process requests share one session, so
  BEGIN_BATCH ... COMMIT_BATCH spans calls. The reload C harness (main, policy, restore)
  has in-process checks.
- **`NODE_STATE`** (reload server): release head, verified topology digest, highest drained
  epoch, base digest, CAS root, and the patch artifacts still in effect (a function's
  newest activation came from it).
- **The real Agent** (`Control.real_ops`, `agent_apply_recording`): reports from NODE_STATE,
  VERSIONS_DETAIL (hot slots), PINS and the status file. A version whose build is `*` is a
  patch artifact the node runs (the reload server knows artifacts, not build names).
  `AgentReport` gained `detail` and `pools`. `Control.order` ships the manifest and, for a
  topology step, the topology body as an artifact under its digest (it is not in the release).
- **Status** (`Topology.write_status`): an `offer <role> fp <fingerprint> sessions <n>` line
  per open offer and a `drain ...` line per closing one.
- **`[control]`** in topology.toml (`candidates = "<host label>"`, `port`), validated against
  host labels, in the digest only when present (other digests keep their bytes).
- **The wiring** (`lib/desugar/control_wiring.march`, spliced into the entry module of an app
  with `[control]`): `Ctl`/`CtlFetch` protocols and roles, the leader (`Ctl.Control`,
  `count = 1` over the candidates, D40), the Agent on every node, the artifact server, the
  control API listener (RELEASE, STATUS, LEADER, CAS_PUT/CHECK, the reload socket's
  unsigned reads; standbys forward RELEASE and STATUS), release durability on every
  reachable candidate before answering, a new leader loading the newest release from disk.
- **forge**: `Control_release` (writes and signs a release in Control's text form; a hot
  step's signed lines are recorded by running `Cmd_deploy_hot.run` against a fake reload
  server, so every gate `forge deploy hot` makes is made before anything is sent) and
  `Cluster_deploy` (upload to every candidate, RELEASE, follow STATUS). `forge topology gen
  ufw` opens the control port between candidates. `Cmd_deploy_hot.recv_line` no longer
  returns a fragment when a read ends mid-line (it lost the END of long answers).
- `Topology.config_from_env` honours MARCH_NODE_CERT (certificate mode) for generated mains.

## Decisions

- **Where the protocols live:** the nested-module limitation was not fixed. The wiring is
  emitted into the entry module only for apps with `[control]`, so every other program pays
  nothing and the eager stdlib is unchanged.
- **Role grants are what the bodies reach** (the capability walk checks them): Agent needs
  NetConnect, FileRead, Mut, Clock; Control adds FileWrite. Environment is read once in
  `ctl_start`, not in role bodies (a role body may not read it).
- **"Every node offers the Agent"** means every node plays the Agent role (it initiates; only
  the leader offers Control).

## Tests

`test/two_node/control_plane` (a hot release, no ssh, every node runs the patch once; a fake
`ssh` records any attempt), `control_leader_kill` (the leader is SIGKILLed after the canary;
the standby finishes, nothing applied twice), `control_partition` (SIGSTOP/SIGCONT stands in
for the partition; both sides converge), `control_cert` (a node whose certificate lacks
`Ctl.Control:offer` never leads). forge test for `[control]` parse/digest/ufw.

## Findings

- Compiled-only: reading a record's fields after handing it to `Control.leader_release` gave
  a stale signature; `ctl_release` reads what it needs first (not minimised; a repro is owed).
- The capability walk follows data from `Env.get` into a role body through a parameter; read
  config in a Vault instead.
- A node learns a peer's address only if it met it: seed every node with every candidate.
