# `[P3]` Distributed deploys, build step 10: ssh backend, `forge host init`, `forge deploy --plan`, signed per-role manifests

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), sections 5, 6.5, 6.8, II.2 ("Hot deploys"), II.8.
Groundwork done: G7 (`Hosts.run_on` is the ssh backend's driver), G5.

**What.** The `ssh` reconciler backend on `Hosts.run_on`, with a topology overlay
constructor for `Hosts.host` (labels included); `forge host init`; host-local
persisted state so hot deploys survive restarts (6.5); signed reconciler actions and
the signed `TOPOLOGY` verb; `forge deploy` classification and the six-block `--plan`
output (6.8) as a pure function over the manifest, schema, protocol, hook and
placement diffs; patch-stack compaction; `ROLE <Proto.Role> caps=...` manifest lines
and the `ACTIVATE5` verb with per-role closures checked by the admission gate.

**Acceptance.** `--plan` classification unit-tested on fixture pairs in forge/test;
an `ACTIVATE5` whose role closure widens without `--grant-cap` is refused by the
server; `forge host init` is idempotent against a container host.
