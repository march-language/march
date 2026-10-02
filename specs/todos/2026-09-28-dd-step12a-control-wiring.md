# `[P3]` Distributed deploys, step 12a: wire the control plane's core into the cluster

**Design:** `specs/plans/2026-09-28-dd-step12-control-plane-design.md`,
sections 6–10. **Built so far:** [../progress/2026-09-28-dd-step12a-control-core.md](../progress/2026-09-28-dd-step12a-control-core.md)
(`stdlib/control.march`: release format, executor, leader memory, `agent_apply`, the
protocols' payloads; the `Ctl` and `CtlFetch` protocols and their role bodies in
`test/session/control_peers.march`; all tested in one process).

Everything below was held back while PR #671 (12-pre) was open, since it touches
`runtime/march_reload.c`, `stdlib/topology.march`, `forge/lib/cmd_deploy_hot.ml`
or `test/test_reload_activate4.c`, or needs a running cluster. #671 has since
merged, so it is unblocked.

**Landed:** see [../progress/2026-09-30-dd-step12a-control-wiring.md](../progress/2026-09-30-dd-step12a-control-wiring.md).

**What remains.**

- `forge deploy` on the cluster backend as a command: `Cluster_deploy`/`Control_release` exist and
  are exercised by `hcr_deploy release`, but `Cmd_deploy` does not yet select them (a `[backend]
  kind = "cluster"`, `make_plan` over the control API's STATUS instead of ssh, restart-class steps
  refused with a pointer to the process backend, D38).
- The one `forge test --upgrade-from` fixture for a release through the control plane.
- `CtlFetch` is not in the wiring: a session message costs far more than its bytes
  ([2026-10-01-session-message-encoding-leak.md](2026-10-01-session-message-encoding-leak.md)),
  so artifacts go over the control API as raw bytes (`CAS_GET`). A byte payload type for
  sessions would let a chunked fetch over a session come back.
- `forge cluster cert --control-agent/--control-candidate` conveniences (the roles are
  Ctl.Agent:initiate; candidates add Ctl.Control:offer).
- The leader's audit log of accepted releases and ordered steps.
- A provoked skipped-gate report (STATUS has `NOTE` lines for it; the partition scenario heals
  without the old leader racing ahead).
- The two compiled-only record-update misbehaviours the wiring works around:
  [2026-10-01-compiled-record-with-projection-sigsegv.md](2026-10-01-compiled-record-with-projection-sigsegv.md).
- The session-runtime leaks the wiring routes around:
  [2026-10-01-session-node-vault-tables-leak.md](2026-10-01-session-node-vault-tables-leak.md).
