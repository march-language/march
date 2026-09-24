# `[P3]` Distributed deploys, build step 10b: ssh backend, `forge host init`, `forge deploy --plan` (10a done)

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), sections 5, 6.5, 6.8, II.2 ("Hot deploys"), II.8.
Groundwork done: G7 (`Hosts.run_on` is the ssh backend's driver), G5.

**Split.** Step 10 landed in two halves. **10a is done** (2026-09-24,
[../progress/2026-09-24-dd-step10a-role-closures-and-persisted-state.md](../progress/2026-09-24-dd-step10a-role-closures-and-persisted-state.md)):
`ROLE <Proto.Role> caps=...` manifest lines, the client-side per-role gate, the
per-role verb (named `ACTIVATE6`, since step 6 had already taken `ACTIVATE5`) checked
by the admission gate, host-local persisted state replayed at start (6.5), the signed
`TOPOLOGY` verb (with a no-op `march_hcr_on_topology` hook for step 8 to fill), and
the `COMPACT` report behind patch-stack compaction. Its acceptance (a widened role
closure refused by the server) is met.

**What remains (10b).** The `ssh` reconciler backend on `Hosts.run_on`, with a
topology overlay constructor for `Hosts.host` (labels included); `forge host init`;
`forge deploy` classification and the six-block `--plan` output (6.8) as a pure
function over the manifest, schema, protocol, hook and placement diffs; the
reconciler's use of 10a's pieces: pushing topologies with
`Cmd_deploy_hot.push_topology`, checking a host's restored state (the `RESTORED`
line's `manifest` digest) against the desired one, and deciding from `COMPACT` when
to rebuild a base image (the rebuild itself). Also open from 10a: the node-side
policy generated from a pool's `caps` (the gate exists; nothing generates the policy
file yet), and filling `march_hcr_on_topology` once step 8 lands.

**Acceptance (10b).** `--plan` classification unit-tested on fixture pairs in
forge/test; `forge host init` is idempotent against a container host.
