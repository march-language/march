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
- The CtlFetch chunk-size measurement (default 32768 hex chars, unmeasured: the machine was
  under heavy load, and design 12a says never to measure then).
- `forge cluster cert --control-agent/--control-candidate` conveniences (the roles are
  Ctl.Agent:initiate, CtlFetch.Agent:initiate; candidates add Ctl.Control:offer, CtlFetch.Server:offer).
- The leader's audit log of accepted releases and ordered steps.
- A provoked skipped-gate report (STATUS has `NOTE` lines for it; the partition scenario heals
  without the old leader racing ahead).
- A minimal repro of the stale-record read in `ctl_release` (progress entry, Findings).
