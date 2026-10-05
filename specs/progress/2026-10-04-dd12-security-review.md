# Security review: distributed-deploys step 12 (the in-cluster control plane), end to end

**Date:** 2026-10-04. **Base:** `origin/main` @ `308d37764`. Read-only,
adversarial. No production code was changed. A prior similar review of steps 2–6
(#614) found 7 P1s; this pass covers step 12 (the code path that ships code,
topology and certificates to running nodes), which had only been reviewed
PR-by-PR.

## Scope

Merged code behind the step-12 PRs #671, #677/#731, #748, #749, #676, #765, #727:
- `runtime/march_reload.c` (reload server, sequenced releases, CAS, TOPOLOGY,
  DRAIN audit, slot resolution).
- `stdlib/control.march` (release parse/sign/verify/accept, executor, leader,
  Agent, cert/revocation items).
- `lib/desugar/control_wiring.march` (the Ctl protocol bodies, the leader, the
  Agent, the control-API TCP listener, cert delivery).
- `stdlib/cluster_node.march`, `stdlib/node_cert.march` (cert handling,
  `replace_cert`, CERT_UPDATE, revocation).
- `forge/lib/cmd_deploy_hot.ml`, `cluster_deploy.ml`, `cmd_cluster.ml`,
  `control_release.ml`, `deploy_plan.ml` (build/classify/sign/upload/follow).
- `lib/tir/llvm_toplevel.ml`, `hot_reload.ml`, `tir_names.ml` (patch slot ids by
  name, #765; stdlib actors off the boundary, #727).

Checked against the design: D37 (control plane holds no root keys, cannot forge),
D40 (no strict lease; nodes enforce seq/id), and the parent threat model (a
misbehaving member on a trusted network; confidentiality deferred, D4).

## Method

Each P1/P2 is confirmed with a runnable repro and its captured output. Repros
live under `specs/reviews/dd12/` — there is no dune file there, so **nothing in
this review runs in CI** (verified; `scripts/check-docs.sh` also passes). Two
areas were reviewed by independent sub-reviewers whose repros are included. The
P1 was found independently by two reviewers.

Driver: `bash specs/reviews/dd12/repro.sh` (findings P1, the AUDIT_COPY P2, and
the resource-exhaustion P2) after `dune build --root . bin/main.exe
test/hcr_deploy.exe`. The cert findings compile/run their own `.march` repros.

## Findings by severity

### P1
- **CAS artifact bytes are never bound to the signed `cas_hash`; a signed
  ACTIVATE loads unverified code.**
  `specs/progress/2026-10-04-dd12-review-cas-artifact-unverified.md` (fixed).
  `CAS_PUT` stores client-declared-hash bytes without hashing them; `activate_items`
  only `access(F_OK)`+`dlopen`s; `cas_hash` is a compilation hash, not a byte
  hash, and no signed digest of the `.so` bytes exists anywhere. Reachable
  unauthenticated over the control-API `CAS_PUT` and over the local reload socket.
  Breaks D37 (a party who can write the CAS runs arbitrary code under the
  operator's signature). Confirmed over both the local socket and the network
  (`cas_probe.py`, `api_probe.py`); a C-level repro
  (`repro_cas_substitution.c`, build with `cas_substitution_build.sh`) drove the
  full `dlopen` and the substituted function returned the attacker value.

### P2
- **Unauthenticated `AUDIT_COPY` forges audit-log entries.**
  `specs/todos/2026-10-04-dd12-review-audit-copy-unauthenticated.md`. Any TCP peer
  appends arbitrary JSON to a candidate's `audit.jsonl`, served back by `AUDIT`.
  Confirmed (`api_probe.py`).
- **Unauthenticated control-API writes allow disk exhaustion.**
  `specs/todos/2026-10-04-dd12-review-control-api-resource-exhaustion.md`.
  `CAS_PUT` (64 MB × unbounded distinct hashes, never GC'd) and `AUDIT_COPY`
  (1 MB × unbounded) from any peer. Confirmed accept-and-store; not run to a full
  disk.
- **Cert rollback after a restart via replay of an old cert-only release.**
  `specs/todos/2026-10-04-dd12-review-cert-downgrade-after-restart.md`. The replay
  floor is `max(reload head, cert_floor)`; `cert_floor` is in-process (lost on
  restart) and a cert-only release never advances the reload head, while
  `replace_checked` has no `not_after`/serial monotonicity. A compromised leader
  restores removed roles/flags (and can install an earlier-expiring cert).
  Confirmed with a compiled repro using the real `ClusterNode.replace_cert`.
- **CERT_UPDATE frame replay escapes revocation.**
  `specs/todos/2026-10-04-dd12-review-cert-update-replay-escapes-revocation.md`.
  The update proof is not bound to the link transcript; a holder of a leaked old
  key replays a recorded frame on a new link and survives the old cert's
  revocation. Confirmed with a pure-core interpreted repro.

### P3
- **The local reload socket is created without an explicit mode** (owner-only
  only by umask). `specs/progress/2026-10-04-dd12-review-reload-socket-permissions.md` (fixed).
  Under a permissive umask any local user can connect and reach every verb
  (including the P1 CAS poisoning). Code-confirmed (no `chmod`/`fchmod`/`umask`
  around `bind`).

## What is safe (checked, with the guarding line)

- **Forgery of a signed line.** A compromised leader/agent/standby can reorder or
  withhold but cannot forge an `ACTIVATE/TOPOLOGY/DRAIN`: the node re-verifies the
  operator ed25519 signature in C, and the leader verifies the release signature
  before storing (`control_wiring.march:977`, `stdlib/control.march:520`). The
  only forgery path is the P1 (bytes, not the signed line).
- **Cross-release replay/ordering.** Sequenced releases refuse a lower seq
  (`ERR stale_release`) and a same-seq/other-id fork (`ERR release_fork`);
  unwrapped signed verbs are refused once a release is held or with
  `MARCH_HCR_REQUIRE_RELEASE=1` (`runtime/march_reload.c:1068-1123`,
  `:1822`). The head is read before the socket opens, so restart replay is
  refused; an unreadable head file refuses all signed requests
  (`load_release_head`, `:1040`).
- **TOPOLOGY integrity.** The body must hash to the signed digest
  (`handle_topology`, `:1191-1196`) — the check the CAS path lacks.
- **Slot resolution (#765).** The published slot is chosen from the running
  binary's name→id table by the *signed* name, and `dlsym` uses that name
  (`runtime/march_reload.c:791-826`); a patch's own `__march_init` name cells only
  steer the patch's own call sites, which also resolve by name against the running
  table. A missing name leaves the private id 0 (static path to the patch's own
  copy); no out-of-range id can be injected; nothing writes outside the slot
  table. A post-#727 stdlib name is not in the slot table → `ERR unknown_name`; a
  patch cannot bind into a stdlib slot. `unslotted_carriers` is forge-side
  planning that only emits more signed ACTIVATEs for registered slots.
- **Certificate authorization basics.** Cert-for-another-node, wrong-operator,
  expired, wrong-key and revoked are all refused
  (`stdlib/cluster_node.march:2893-2900`, `stdlib/control.march:1277`); roles come
  only from the operator-signed body; revocations are additive, deduplicated and
  operator-signed, so a replayed list cannot un-revoke and no member can revoke on
  its own. The Agent verifies the release with the deploy key, separate from the
  operator cert key, and the order's digest+seq are cross-checked against the
  signed release, so unsigned StepOrder fields don't steer which cert installs.

## Unconfirmed / lower-severity (no repro — not filed as todos)

- **Delivered revocations are not durable (P3).** `ctl_cert_ops.revoke` calls only
  `ClusterNode.revoke`; nothing writes `MARCH_CLUSTER_REVOCATIONS`, so after a
  full-cluster restart a release-revoked cert is accepted again. `forge … revoke
  --deliver` reporting "complete" invites skipping the manual step.
- **The Agent does not check a release's `env` (P3).** With a per-machine deploy
  key signing several environments, a leader could feed one env's release to
  another; realistic impact is a floor bump (minor DoS), since the inner cert
  still needs the operator and node keys.
- **Name comparison uses only the last URI segment (P3).** A same-name, same-key
  cert in another pool/domain would be accepted; needs operator issuance, so only
  matters if one operator key spans domains.
- **STATUS / `AgentReport.certs` are unauthenticated (P3).** A compromised leader
  can report "delivered/complete" for a cert/revocation that never applied — false
  assurance, not an unsigned action.
- **`apply_cert` same-serial shortcut (P3).** A matching serial is treated as
  "already in use" without comparing bodies; harmless (nothing installed) but the
  report claims applied.
- **Intra-release reapply.** The node accepts any line of the current head release
  again (same seq+id) in any order/any number of times; I could not construct
  concrete harm (re-applying the same signed ACTIVATE is a no-op; re-DRAIN of
  already-drained epochs is a no-op). The design's open question 12.2 notes it.
- **Single-threaded reload socket wedge.** `handle_client` is serial with no read
  timeout, so a same-uid local client that stalls mid-line blocks other
  *socket-delivered* deploys; it does not block the control-plane (in-process
  `reload_request`) path, and the socket is owner-only by default — low impact.
- **CERT_UPDATE CPU cost.** Two ed25519 verifies per frame; a linked member can
  burn a peer's CPU.

## Open PRs touching these files (listed, not reviewed in depth)

A scan at review time found no open PR modifying the control-plane core
(`runtime/march_reload.c`, `stdlib/control.march`,
`lib/desugar/control_wiring.march`, `stdlib/cluster_node.march`, `node_cert.march`)
or the forge cluster/deploy backends. One open PR touches a file in scope only
incidentally: #756 ("fix(rc): stop the steady per-call leaks behind an idle
conduit worker's growth") edits `lib/tir/tir_names.ml` (an RC-leak fix, not a
control-plane change). (If new control-plane PRs land, re-check the P1 CAS binding
against them.)

## Deliberately not reviewed

- `lib/jit/` (REPL JIT) — not on the patch-`.so` deploy path.
- Full `test/two_node/` end-to-end over real sockets and leader failover
  (confirmations used the reload socket, the network control API, and core-level
  `.march` repros).
- Compiled-vs-interpreted parity of the cert/control paths.
- forge's `Cluster_deploy.status`/`follow` output parsing, and the file-watch
  (`.delivered.tmp`) TOCTOU.
- Cap-root / role-closure admission correctness (ACTIVATE4/6) beyond confirming it
  runs after signature and before staging.
