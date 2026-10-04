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

**Landed:** see [../progress/2026-09-30-dd-step12a-control-wiring.md](../progress/2026-09-30-dd-step12a-control-wiring.md)
and, for `forge deploy` on the cluster backend, the `forge test --upgrade-from` fixture and the
leader's audit log, [../progress/2026-10-01-dd-step12a-forge-cluster-backend.md](../progress/2026-10-01-dd-step12a-forge-cluster-backend.md).

**What remains.**

- The plan on the cluster backend sees less than over ssh: STATUS carries no node's live
  sessions, hot slots or patch stack, so the drain counts, the "no dispatch slot" check and
  automatic compaction (`compact_after`) work from forge's records (`--compact` still forces
  one). A `NODE` line (or a `DETAIL <node>` verb) carrying them would close it.
- A build whose hosts span two targets is refused on the cluster backend: a release names one
  patch per build. Builds per target (`build web@linux/arm64 ...`, selected by the agent's
  `HCR_INFO` target) would lift it; it touches the release format.
- `CtlFetch` is not in the wiring: a session message costs far more than its bytes
  ([2026-10-01-session-message-encoding-leak.md](2026-10-01-session-message-encoding-leak.md)),
  so artifacts go over the control API as raw bytes (`CAS_GET`). A byte payload type for
  sessions would let a chunked fetch over a session come back.
- `forge cluster cert --control-agent/--control-candidate` conveniences (the roles are
  Ctl.Agent:initiate; candidates add Ctl.Control:offer).
- A provoked skipped-gate report (STATUS has `NOTE` lines for it; the partition scenario heals
  without the old leader racing ahead).
- The two compiled-only record-update misbehaviours the wiring works around are fixed
  ([../progress/2026-10-01-compiled-record-with-projection-sigsegv.md](../progress/2026-10-01-compiled-record-with-projection-sigsegv.md)),
  so both workarounds can be removed. Shape 1 was a type error the driver dropped: putting
  the report merge back in the `report` closure needs `fn (rep : Control.AgentReport) ->`,
  or it is now a compile error. Keeping the merge in `Control.leader_report` is also fine.
  Shape 2 (`Control.serialize`'s `if` over `r.signature`) compiles correctly now.
- The session-runtime leaks the wiring routes around:
  [2026-10-01-session-node-vault-tables-leak.md](2026-10-01-session-node-vault-tables-leak.md).
