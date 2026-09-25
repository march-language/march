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

- ~~The two-way role check in `offer_verdict` and `fill_roles`~~ **done**
  (2026-09-25): `SessionAP.authorize` (stdlib/session_ap.march);
  `offer_verdict` checks the initiator by `Delivery.from_node`, `candidates`
  checks each offer's holder, and an access point's session checks every
  role's registry holder. Tests: `test/session/cert_authz.march` (fake
  `ClusterOps`), two-node `cert_role_denied` and `cert_initiate_denied`.
- ~~Raw-send denial in `ClusterNode.send_msg` and `route`~~ **done**
  (2026-09-25): both ends need `raw_send`; `send_msg`, `queue_for`, inbound
  routes, `NodeSend.cast`/`handle_frame` and `NodeCall` on direct connections
  (`NetKernel.raw_allowed`). Session routes (`route_session`) and control
  frames exempt. Tests: `test/stdlib/test_session_ap.march`, two-node
  `cert_raw_send_denied`; `cert_ok`'s node-b gained `raw_send`.
- ~~Cross-node references~~ **done** (2026-09-25): `lookup`/`names` hide a
  binding unless raw sends to its holder are allowed (own bindings and the
  `ap:`/`session:`/`topo:` namespaces exempt); each replica records the
  registrant's certificate identity (`ClusterNode.registrant`);
  `GlobalPid.make` stays pure. Tests: `test/stdlib/test_cluster_node.march`
  ("cross-node references"), `cert_raw_send_denied` (raw.a / raw.b).
- SessionNode's direct-connection path (`dial_all` / `accept_all`) still calls
  the shared-secret `ClusterConn.connect_split_within` / `accept_split_within`;
  moving it to `connect_split_auth` / `accept_split_auth` gives it
  certificate mode.

**Acceptance.** A node holding `IO.Foreign` on its own pool cannot offer a role its
certificate does not name, nor raw-send into another pool. (The other half of the
original acceptance, "a tampered frame is dropped and counted", is met by 11a:
`test/two_node/frame_tampered`.)
