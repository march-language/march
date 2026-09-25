# `[P3]` Distributed deploys, step 10b follow-ups

What [../progress/2026-09-22-dd-step10-ssh-backend-and-plan.md](../progress/2026-09-22-dd-step10-ssh-backend-and-plan.md)
left open, each small:

- **Node policy vs function caps.** `MARCH_DEPLOY_POLICY` bounds each patched
  function's own caps as well as role closures; a policy from a pool's caps refuses a
  patch that changes a stdlib function outside them (e.g. the cluster runner's
  networking). Generate the policy from the pool's caps plus the runtime's own, or have
  the gate apply the policy to role closures only.
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
