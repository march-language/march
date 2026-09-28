# `[P3]` Distributed deploys, build step 12: the control plane in the cluster

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 5, II.9.

**Design:** [../plans/2026-09-28-dd-step12-control-plane-design.md](../plans/2026-09-28-dd-step12-control-plane-design.md)
supersedes the sketch below (operator-signed releases, a keyless control plane, and a
node-side replay fix, "12-pre", that lands first). Decisions D37–D41 are in its section 11:
no root keys in the control plane, restarts through the process backend, certificate
issuance offline, `count = 1` leader with no strict lease. 12-pre is done:
[../progress/2026-09-28-dd-step12-pre-sequenced-releases.md](../progress/2026-09-28-dd-step12-pre-sequenced-releases.md).

**What.** An `@[endpoints]` protocol between `Control` and `Agent` roles; the `Agent`
body wraps the reload-socket verbs; `reconcile.ml` gets a `cluster` backend; the
control plane issues certificates (step 11) and holds a leader lease.

**Acceptance.** With the control plane running, `forge deploy` needs no ssh: it talks
to the leader, which reconciles every node; killing the leader moves the lease and a
deploy in progress completes or reports.
