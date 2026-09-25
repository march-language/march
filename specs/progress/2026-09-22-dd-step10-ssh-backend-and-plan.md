# Distributed deploys, build step 10: the ssh backend, `forge host init`, `forge deploy --plan`, compaction

**DONE.** 10a (the compiler/runtime half) on 2026-09-24:
[2026-09-24-dd-step10a-role-closures-and-persisted-state.md](2026-09-24-dd-step10a-role-closures-and-persisted-state.md).
10b (forge) on 2026-09-25, this file. Parent:
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
sections 5 ("Host setup", "At small scale the reconciler is forge"), 6.5, 6.8, II.6,
II.8; D21, D26. Five commits, one per item. Follow-ups:
[../todos/2026-09-25-dd-step10b-followups.md](../todos/2026-09-25-dd-step10b-followups.md).

## 1. The `ssh` backend (`forge/lib/reconcile.ml`)

An overlay with `[backend] kind = "ssh"` gets it. `ssh_nodes` makes one node per host
of each pool: `Hosts.of_topology_host` (node name `<pool>-<host>`, labels from the
overlay, the reload socket from `Host_layout`), and the target `forge host init`
recorded (`.forge/hosts/<env>.json`, `host_record`). A host in two pools is refused.
`run_on` is `Hosts.run_on`. `push_topology` sends the signed `TOPOLOGY` verb over an
ssh tunnel (`Cmd_deploy_hot.open_tunnel`/`push_topology_conn`), then writes the digest
to the node's `MARCH_TOPOLOGY_FILE` and sends its unit SIGHUP (only when the node
reports; a refused push is `Push_failed` and nothing is signalled). `status` reads the
unit's `is-active`, the status file, and `VERSIONS_DETAIL` (now keeping the `RESTORED`
line: `parse_versions_detail_full`), `PINS`, `COMPACT` and `HCR_INFO`. `shared_epoch`
fetches `GET_EPOCH` once per batch; `ping` is the canary probe; `drift` compares a node's
running slots with the manifest forge last deployed.

`Remote.transport` (`exec`, `with_socket`, `upload`) runs the same code over ssh or
against local sockets and `sh` (the tests). `FORGE_SSH_CONFIG` adds `-F` to every ssh.
`Reconcile.apply` and `status_text` pick the ssh backend from the overlay; the observed
state is `.forge/deploy/<env>/topology.json`; a restart-needing change is refused with
"run `forge deploy`". The local backend is unchanged.

Also in this commit: `forge deploy hot`'s `run` now preflights `HCR_INFO` against the
manifest (`check_identity`) before uploading: #606 added the verb and a parser, and
nothing called it. The manifest parser never read `# hcr_abi` (an 8-character prefix
compared with the 9-character key); fixed.

## 2. `forge host init --env <env>` (`forge/lib/host_init.ml`)

One idempotent script per host (`ok <path>` / `changed <path>` lines, parsed into the
report): the `march` user (useradd or busybox adduser), the directories of
`Host_layout`, the unit from the step-7 template with the host's `Environment=`
(`Topology.Gen.systemd_unit`), the env file (secret, 0640 root:march), `deploy.pub`,
the policy file from the pool's written or compiler-derived caps, node certificates in
certificate mode (`Cmd_cluster.run_cert`, reused while 30+ days remain and the roles are
the same), the pool's ufw rules (applied when ufw exists), the digest; `daemon-reload`
and `enable` only when needed and only where systemd is PID 1. `uname -sm` becomes the
recorded target. The systemd template now names `MARCH_POOLS` and `MARCH_TOPOLOGY_FILE`
(it wrote `MARCH_POOL`/`MARCH_TOPOLOGY`, which nothing reads) and runs as `User=march`;
the ufw template keeps ssh open before `ufw --force enable`.

## 3. `forge deploy --plan` (`forge/lib/deploy_plan.ml`, `forge/lib/cmd_deploy.ml`)

`Deploy_plan.classify` is pure: builds (old and new manifest, schemas, base-image
identity, the slots the running nodes report), protocols (deployed and current
structure), topologies, derived values, grants, live sessions → a per-pool mechanism
with its reasons, order, splits, widenings, compaction; `render` prints the six blocks
of 6.8. Inputs, by source:

| diff | source |
|---|---|
| functions | manifest set-diff; signature changes shown |
| actor state / messages | `.schemas.json`; `migrate_state` presence = a `<actor>_migrate_state` in the manifest (not `nm`, which fails on a cross-built `.so` on macOS) |
| protocol fingerprints | the generated `<P>_Msg.fingerprint`'s impl hash (its body is the fingerprint literal); the KIND of change from forge's own structure of the declaration, kept in `.forge/protocols/<P>.json` |
| hooks | the hook's impl hash (prefix-stripped name) |
| placement | `Reconcile.diff_topologies` over the deployed and the new digest |
| derived caps | `--emit-core-ast`'s `topology` object, deployed (`derived.json`) vs now |
| role closures | the manifests' `ROLE` lines (`compute_role_widening`) |
| C runtime / ABI | `Cas.runtime_identity_of_dir` of the toolchain's runtime vs the deployed base (`<build>.base.json`); `# hcr_abi` and `# target` |

No compiler flag was added. The D21 split fires when one build serves or initiates both
the chooser and a receiver of a choice that gained exactly one branch; deploy one holds
back the chooser role's functions (`<P>_<Role>.*`, its bound body or actor dispatch).
Receivers' pools are ordered before the chooser's. The finer rule is step 9's.

## 4. `forge deploy --env <env>` executes it

Pool by pool in the plan's order: hot via `Cmd_deploy_hot.deploy_one` (now `?tunnel`)
with the batch's shared epoch and the host's recorded target checked first; restart onto
a base image built per build and target (`Cmd_build.build ~target` with the hot-reload
flags), uploaded, the unit restarted, the reload socket waited for as the health gate;
then the topology push. Rolling, simultaneous, `--canary N`. `--yes` skips the prompt.
Baselines go to `.forge/deploy/<env>/`. A split writes `pending_split.json`; running the
same build again does deploy two.

## 5. Compaction

`--compact`, or automatic when a node's `COMPACT` stack exceeds `[hot-reload]
compact_after` (new `Project.hr_compact_after`): the build's pools restart onto a base
rebuilt from the current version; forge then checks `COMPACT` is empty on each node,
removes the `state.base-changed` the runtime set aside (and, if a stack survived because
the rebuilt base had the same baseline hashes, removes it and restarts once more).

## Deviations and findings

1. **Topology-app functions have no dispatch slot.** The entry module's functions reach
   TIR as `Back.x`, not `TopologyApp.Back.x`, so `--hot-reload <entry module>` covers
   none of them; only actor dispatchers are slots. And the compiler's generated names
   (`$lam<n>`, `$jp<n>`) come from a global counter, so an edit renumbers every later
   closure and changes the impl hashes of unrelated functions (`Front.*`, `main`). Before
   this step, `forge deploy hot` would activate nothing for such a change and still
   report success. The plan now asks each node for its slots and restarts when a changed
   function has no slot and no changed slotted caller (`Deploy_plan.undeliverable`,
   over the manifest's `callers:`). The end-to-end test hot-patches a function under
   `[hot-reload] module_prefix = "Back"`. Compiler side filed:
   [../todos/2026-09-25-hcr-topology-app-functions-no-dispatch-slots.md](../todos/2026-09-25-hcr-topology-app-functions-no-dispatch-slots.md).
2. **`HCR_INFO` quotes the triple.** A real server answers
   `abi:march-hcr-v2;triple="aarch64-unknown-linux-gnu";ptr=8` (the runtime stringifies
   an already quoted `MARCH_HCR_TRIPLE`); the manifest writes it bare. forge compares
   without quotes. Filed: [../todos/2026-09-25-hcr-info-abi-quoted-triple.md](../todos/2026-09-25-hcr-info-abi-quoted-triple.md).
3. **The runtime's topology hook is still a no-op**, so the ssh backend writes the digest
   file and SIGHUPs the unit after the signed push (the unsigned half rides on ssh's own
   authority).
4. **The policy file bounds functions too.** `MARCH_DEPLOY_POLICY` is applied to each
   patched function's own caps as well as to role closures; a policy generated from a
   pool's caps can refuse a patch that changes a stdlib function using a cap outside
   them (the cluster runner's networking). Generated as the brief says, from the pool's
   caps; follow-up in the 10b todo.
5. **The connectivity-graph firewall may partition SWIM.** The step-7 ufw rules open the
   cluster port only between pools that exchange protocol messages; membership probes
   every member. `host init` applies them when ufw is installed. Filed:
   [../todos/2026-09-25-topology-firewall-cluster-port-vs-swim.md](../todos/2026-09-25-topology-firewall-cluster-port-vs-swim.md).
6. **One pool per host** for the ssh backend (one unit, socket and cluster port per
   pool; a second pool would collide). Refused with a message.
7. **Protocol baselines** are kept per environment (`.forge/deploy/<env>/protocols/`)
   and also written to `.forge/protocols/` (the path step 9's `--protocol-baseline`
   will read), which the plan falls back to.
8. **`loop atomic` and unsupervised actors** ("what may be lost") are not detected: the
   first is D27's syntax (another session), the second is not in any artifact. Drains
   report live sessions per pool (the status file counts sessions per node, not per
   protocol).
9. **`deploy_env`'s `run_status` fleet selection** is unchanged (G7's note).
10. **Stale `_build` stdlib/runtime** made a direct cross compile fail
    (`Topology.offer_role` undefined); restaging every `stdlib`/`runtime` source fixed
    it. The dune rules stage them fresh.

## Tests

- `forge/test/test_reconcile.ml` +11: nodes from the overlay, one pool per host,
  host records, the ssh push (signed `TOPOLOGY` verified by a fake server, digest file,
  SIGHUP only to reporting units, a wrong key refused and nothing signalled), status
  (`RESTORED`, `COMPACT`, `HCR_INFO`), shared epoch and PING, drift, `topology apply`
  over ssh, identity checks (quoted ABI included), `# hcr_abi` parsing, `deploy hot`
  refusing another target before any upload.
- `forge/test/test_host_init.ml` (3): local (files, environment, secret and
  certificate modes, second run changes nothing); refusal of a non-ssh topology; the
  acceptance, over real ssh against an alpine sshd container, as root: user, owners and
  modes, recorded target, a second run with no change. SKIP banner without Docker.
- `forge/test/test_deploy_plan.ml` (20): one fixture pair per classification branch
  and the six blocks in order.
- `forge/test/test_deploy_e2e.ml` (1, Slow): the real forge and compiler against a
  Debian sshd container (a stand-in `systemctl` runs the unit): host init; a first deploy
  restarting onto a cross-built `linux/arm64` base; nothing to do; a closure edit planned
  and deployed as a restart; `Back.scale` hot-patched through the tunnel
  (`activated: Back.scale`, persisted, "running code matches"); `--compact` clearing the
  stack (`was 1 entry`, no `state.base-changed` left). SKIP banner without Docker, zig or
  the cross sysroot.
- Perturbations, each red on exactly its case and green restored: identity preflight
  skipped (the target case), `# hcr_abi` parse reverted, the ssh push guard dropped,
  file idempotence dropped (second run), hook detection, split detection, removing the
  set-aside stack skipped (the end-to-end test).

## Results

Run from the worktree with `--root .`, at the final tree, load 9-13 on the 14-core Mac.

`dune build --root . @forge/test/runtest`: exit 0, 29 suites, no SKIP. The new ones:

| suite | tests | time |
|---|---:|---:|
| reconcile | 19 | 1.8 s |
| host-init (incl. the alpine sshd container) | 3 | 6.5 s |
| deploy-plan | 20 | 0.01 s |
| deploy-e2e (Debian sshd container, cross-built linux/arm64 base) | 1 | 172 s |

`scripts/run-tests.sh -q`: exit 0.

| suite | tests |
|---|---:|
| compiler | 1223 |
| eval | 282 |
| codegen | 629 |
| stdlib | 823 |
| stdlib_march | 74 |
| test_jit | 7 |
| LSP (lsp, utf16, jsonrpc, incremental, query_cli) | 377, 5, 37, 10, 7 |

`scripts/check-docs.sh`: passed.
