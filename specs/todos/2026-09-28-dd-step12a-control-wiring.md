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

**What remains.**

- **A home for `Ctl` and `CtlFetch`.** They cannot live in `stdlib/control.march`
  until [2026-09-28-endpoints-protocol-in-nested-module.md](2026-09-28-endpoints-protocol-in-nested-module.md)
  is fixed; the generated topology `main` (an entry module) can declare them, copying
  the declaration and role bodies from `test/session/control_peers.march`.
- **`reload_request(line : String) : String`**, a stdlib-only builtin (G3-gated to
  `stdlib/control.march`) that runs a request line through the reload socket's own
  dispatch, refactored into a function both call. Then the real `AgentOps`:
  `request` over it, `has` over `CAS_CHECK`, `report` from `Topology.write_status`
  plus `VERSIONS_DETAIL`, `PINS` and `RELEASE_HEAD`.
- **The Agent's CtlFetch step**: before `agent_apply`, fetch `Control.missing(...)`
  over `CtlFetch` and `CAS_PUT` each artifact. The chunk size comes from the
  measurement design section 2.5 asks for (JSON-over-`List(Int)` framing cost per
  chunk); `Control.chunks` takes it as a parameter today.
- **The leader**: a `[control]` topology section becoming a `Ctl.Control` role
  binding with `place = { on = "control", count = 1 }`; `offer_hosted_Control` with
  one actor holding the `CtlLeader` and implementing `ControlOps` for every agent's
  session; the leader's clock; storing releases and artifacts and copying them to
  every reachable candidate before answering forge; a new leader taking the highest
  valid `seq` among candidates and agents (`RolloutBehind` tells it to look).
- **Every node's Agent**: the generated `main` initiating `Ctl.Agent` whenever the
  topology has a `[control]` section, and re-initiating when the session ends (the
  leader changed, or its session budget ran out).
- **The control API listener** (`RELEASE`, `STATUS`, `CAS_PUT`, `CAS_CHECK`) and
  forge's `cluster` backend as its client; standbys forwarding `RELEASE`.
- **Status per fingerprint and per offer** in `Topology.write_status`, which the
  Agent's report needs for richer gates than `healthy`.
- **Audit**: the leader appends every accepted release and every ordered step.
- **Acceptance** (design section 10, 12a): a two-node scenario in `test/two_node/`
  and one `forge test --upgrade-from` fixture — `forge deploy` with no ssh; killing
  the leader mid-rollout; a partition during a rollout; an agent certificate without
  `Ctl.Control:offer` never leading.

**Open questions carried from the core.**

- Whether the protocols should ever be in the eagerly loaded stdlib: in it they cost
  every program about 0.07 s warm and 0.8 s cold (measured, see the progress entry).
- The executor matches steps by `(seq, step)` and end state; design section 12 asks
  whether per-step idempotency keys are needed beyond that. None were for the
  tested cases.
