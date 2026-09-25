# `[P3]` Distributed deploys, build step 11b: role and raw-send enforcement

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 3, 7.4, II.9, D3, D4.

**Done (11a, the identity half):** node certificates (`NodeCert`, `forge cluster
keygen | cert | revoke`), the certificate-mode handshake, the per-frame MAC in
`NetFrame`, expiry and gossiped revocation. See
[../progress/2026-09-24-dd-step11a-node-certificates.md](../progress/2026-09-24-dd-step11a-node-certificates.md).
Every certificate-mode peer's verified certificate is available as
`ClusterNode.peer_cert(c, node_id)` (through the `ClusterOps` dictionary) and
`ClusterConn.peer_cert(node_id)`.

**What remains (11b, the authorization half, after D27 lands):**

- The two-way role check in `offer_verdict` and `fill_roles`
  (stdlib/session_node.march): an offer checks the initiator's certificate
  names `Proto.Role:initiate` for the role it plays, and the initiator checks
  each offering node's certificate names `Proto.Role:offer` for the role it
  offers.
- Raw-send denial in `ClusterNode.send_msg` and `route` against the peer's
  certificate `raw_send` flag.
- Cross-node references (`GlobalPid.make`, `GlobalRegistry.lookup`) checked
  against the certificate.
- SessionNode's direct-connection path (`dial_all` / `accept_all`) still calls
  the shared-secret `ClusterConn.connect_split_within` / `accept_split_within`;
  moving it to `connect_split_auth` / `accept_split_auth` gives it
  certificate mode.

**Acceptance.** A node holding `IO.Foreign` on its own pool cannot offer a role its
certificate does not name, nor raw-send into another pool. (The other half of the
original acceptance, "a tampered frame is dropped and counted", is met by 11a:
`test/two_node/frame_tampered`.)
