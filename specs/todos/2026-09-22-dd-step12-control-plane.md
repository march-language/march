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

**12b (certificate distribution and live rotation): done.** Live replacement:
[../progress/2026-09-28-dd-step12b-live-cert-replacement.md](../progress/2026-09-28-dd-step12b-live-cert-replacement.md).
Certificates and revocations as release items (`forge cluster cert|revoke --deliver`):
[../progress/2026-10-01-dd-step12b-cert-delivery.md](../progress/2026-10-01-dd-step12b-cert-delivery.md).
Left from it, none blocking:

- The Agent's replay floor for certificate releases (`Control.cert_floor`) lives in memory;
  after a restart only the reload server's release head bounds it. Persisting it needs the
  `Ctl.Agent` role to write a file (or a reload-server verb that records it).
- `STATUS` keeps showing a node's failure from an earlier, halted release after a later
  release succeeds on that node (`Control.leader_report` keeps a known failure when a report
  omits it). It does not halt anything; it reads as if it did.
- The deferred issuer design of section 10 (a control-plane issuer certificate, short-lived
  node certificates, join tokens) stays deferred (D39).
