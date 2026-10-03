# `[P3]` Distributed deploys, step 10b follow-ups

What [../progress/2026-09-22-dd-step10-ssh-backend-and-plan.md](../progress/2026-09-22-dd-step10-ssh-backend-and-plan.md)
left open, each small:

- **Node policy vs function caps.** `MARCH_DEPLOY_POLICY` bounds each patched
  function's own IO caps as well as the closures of the roles the node serves. The
  policy now adds the runner's caps (`Host_init.runner_caps`), and since 2026-10-02
  the gate ignores proof caps (`Session.Live` in every role body's own caps) and the
  closures of roles the pool does not serve, such as the control plane's `Ctl.*`
  (a `serves` line in the generated policy:
  [../progress/2026-10-01-role-body-hot-patch-needs-session-live-in-policy.md](../progress/2026-10-01-role-body-hot-patch-needs-session-live-in-policy.md)).
  Still open: a patch that changes a stdlib function outside the pool's caps and the
  runner's (e.g. the cluster's networking) is refused. A stdlib change cannot ship as
  a patch at all today (forge refuses it on `stdlib_hash`), so this bites only once
  it can: add the runtime's own caps then, or have the gate apply the policy to role
  closures only.
- **Topology hook.** Fill `march_hcr_on_topology` (runtime) so a signed `TOPOLOGY`
  push is applied by the node; the ssh backend then stops writing the digest file and
  sending SIGHUP itself.
- **Single writer.** The ssh backend still uses the local lock file; two operators on
  two machines are not excluded (a lease comes with step 12).
- **CAS after compaction.** Old patch artifacts stay in the host's CAS; `COMPACT`
  reports their bytes. Remove artifacts no persisted entry names.
- **Several pools per host** (distinct units, sockets and cluster ports).
- **"What may be lost"**: `loop atomic` sessions (once D27 lands), unsupervised actors a
  hard deadline would kill (needs supervision facts in an artifact), sessions per
  protocol rather than per node.
- **Hooks**: only the hook's own impl hash restarts its pool; a helper only the hook
  calls is hot-patched although the hook already ran.
- **Per-target manifests**: the plan reads the first target's manifest of a build.
- **Uploads**: a restart uploads the whole base image; the host's CAS could dedupe.
- ~~**Step 9's split in the deploy.**~~ Done 2026-09-28: forge's own split (holding the
  chooser role's functions back) is gone; `Deploy_plan.splits_of` uses
  `Protocol_split.plan`, and `Cmd_deploy` builds the expand with `--protocol-expand`.
  See [../progress/2026-09-28-dd-d21-split-in-forge-deploy.md](../progress/2026-09-28-dd-d21-split-in-forge-deploy.md).
