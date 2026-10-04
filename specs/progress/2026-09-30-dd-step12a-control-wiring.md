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
  with `[control]`): the `Ctl` protocol and roles, the leader (`Ctl.Control`,
  `count = 1` over the candidates, D40), the Agent on every node, the
  control API listener (RELEASE, STATUS, LEADER, CAS_PUT/CHECK/GET, the reload socket's
  unsigned reads; standbys forward RELEASE and STATUS), release durability on every
  reachable candidate before answering, a new leader loading the newest release from disk.
  An agent fetches an artifact it lacks from a candidate's control API (`CAS_GET`, raw
  bytes) and stores it through its own reload server; `CtlFetch` is not used (below).
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

## Memory, and what was changed for it (2026-10-01)

The first version grew every node past 2 GB within a minute of a rollout starting
(the two-node CI job died of it). Measured with `live_allocs()` and RSS sampling, four
causes, each fixed or routed around; the leaks themselves are filed:

- A `Ctl` session formed every 200 ms (the agent re-initiated after each `Drained`
  outcome, and after a deploy of the node every new session was draining). Sessions are
  long-lived now; a drained one is restarted from an actor past the deploy's marker
  (`CtlRespawner`). [../todos/2026-10-01-session-node-vault-tables-leak.md](../todos/2026-10-01-session-node-vault-tables-leak.md).
- The leader's state, a record rewritten in a Vault on every poll, leaked all it pointed
  to: it is kept encoded (a String) now, the release in its own entry. Same todo.
- Reports carried `VERSIONS_DETAIL` (~14,000 lines) on every poll; now `NODE_STATE` and
  `PINS` only, and a poll's report has no `detail` at all (the hello's is kept).
- Artifacts moved over `CtlFetch` as JSON-over-`List(Int)` chunks: 1–2.5 GB per node for
  a 2 MB patch. They go over the control API as raw bytes instead.
  [../todos/2026-10-01-session-message-encoding-leak.md](../todos/2026-10-01-session-message-encoding-leak.md).

After: the three nodes of `control_partition` stay under 150 MB for the whole scenario
(were 2.5–5.5 GB). The chunk-size measurement the design asked for is answered by this:
a session is the wrong channel for an artifact at any chunk size.

## Findings

- Two compiled-only misbehaviours around record updates from a found record's field
  (a SIGSEGV in the leader's report merge; a stale signature read after
  `leader_release`), both worked around:
  [2026-10-01-compiled-record-with-projection-sigsegv.md](2026-10-01-compiled-record-with-projection-sigsegv.md).
- The capability walk follows data from `Env.get` into a role body through a parameter; read
  config in a Vault instead.
- A node learns a peer's address only if it met it: seed every node with every candidate.
