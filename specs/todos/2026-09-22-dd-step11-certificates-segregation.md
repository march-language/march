# `[P3]` Distributed deploys, build step 11: node certificates and segregation

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 3, II.9, D3, D4.

**What.** Certificates replace the shared secret in `ClusterAuth.prove` /
`NetKernel.handshake`; a per-frame MAC in `NetFrame`; the two-way role check in
`offer_verdict` and `fill_roles`; raw-send denial in `ClusterNode.send_msg` and
`route` against the peer's certificate flags. Cross-node references
(`GlobalPid.make`, `GlobalRegistry.lookup`) are checked against the certificate.

**Acceptance.** A node holding `IO.Foreign` on its own pool cannot offer a role its
certificate does not name, nor raw-send into another pool; a tampered frame is dropped
and counted.
