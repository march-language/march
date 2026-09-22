# `[P3]` Distributed deploys, build step 12: the control plane in the cluster

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 5, II.9.

**What.** An `@[endpoints]` protocol between `Control` and `Agent` roles; the `Agent`
body wraps the reload-socket verbs; `reconcile.ml` gets a `cluster` backend; the
control plane issues certificates (step 11) and holds a leader lease.

**Acceptance.** With the control plane running, `forge deploy` needs no ssh: it talks
to the leader, which reconciles every node; killing the leader moves the lease and a
deploy in progress completes or reports.
