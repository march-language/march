# Distributed deploys step 11b: authorization by node certificate

**Plan:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
section 1 ("cross-node references are handed out, not computed"), section 3
(two-way checks when a session forms; protocols bound reach; raw primitives;
untrusted input), 7.4 (reach, shape, record), II.9, D3, D4, D31. The identity
half is [2026-09-24-dd-step11a-node-certificates.md](2026-09-24-dd-step11a-node-certificates.md).
This file was the step-11 todo (filed 2026-09-22), moved here when 11b landed.

Every check below applies in **certificate mode only**. A shared-secret node has
no certificates and checks nothing, as before; `specs/lang/clustering.md`,
"Authorization", says so and gives the threat model (authority, not availability
or confidentiality).

Four commits, one per item, on top of D27 (#648).

## 1. The two-way role check at session formation

- **`SessionAP`** (new module, `stdlib/session_ap.march`): the pure check
  `SessionAP.authorize(cert, proto, role, mode)`, `Ok(())` or `Err("not
  authorized for Proto.Role")` / `Err("presented no certificate")`;
  `permission`, `role_label`, `role_name(roles, i)`, `offer_mode()` /
  `initiate_mode()` (`offer` is a reserved word). It is the seam the step-9
  session (protocol evolution, fingerprint compatibility table) agreed to call
  from `offer_verdict`, so the two changes merge by clause.
- **`ClusterNode.own_cert`, `certified`, `authorize_peer(c, node_id, proto, role,
  mode)`** (`own_cert` through the `ClusterOps` dictionary; `ops_stub` answers
  None, i.e. shared-secret, so stub-based tests check nothing unless they say so).
- **Role names reach the runtime.** Nothing at runtime knew "Checkout.Ledger":
  SessionNode had the protocol name and role NUMBERS. `offer_role`,
  `offer_hosted` and `initiate` take `roles : List((String, Int))` after the
  fingerprint, and the generated fronts pass `<P>_Msg.role_names()`.
- **The sender of a frame is the link, not a claim.** `NodeSend.Delivery`
  gains `from_node`, "" from `decode_msg`, filled by ClusterNode's data reader
  with the link's verified peer (its own id for the loopback). An invitation's
  reply pid is a claim the initiator makes; `from_node` is what the offer checks.
- **Offer side** (`offer_verdict(o, active, fp, from, irole)`): closing,
  fingerprint, then `initiator_verdict` (the initiator's certificate must name
  `Proto.Role:initiate` for the role it plays: verdict `"initiator node-a not
  authorized for Checkout.Client"`), then capacity. The Invite gains a 4th
  element, the initiator's role number (`decode_invite` accepts the old 3-element
  form as role -1, refused in certificate mode: "did not name its role").
- **Initiator side** (`candidates`): each offer's HOLDING node (the binding's
  node, where the invitation goes) must have a certificate naming
  `Proto.Role:offer`; one that does not is skipped before any invitation and
  listed in `NoOffer`'s reasons (`"node-b not authorized for Checkout.Ledger, not
  invited"`). `candidates` returns `(offers, skipped)`; the skipped text seeds
  `invite_role`'s reasons.
- **Beyond what was asked: the formed session's role holders.** Parties find
  each other by `session:<sid>/<role>` names, which any member can write, and
  session ids are predictable (node, creation, counter). A member without the
  role could bind the name first and receive the role's messages. Access-point
  sessions now pass a `holder_ok` check into `run_cluster_party`: every role's
  endpoint must be on a node certified for that role (offer or initiate), else
  `Connect(role, "session s: role P.R is held by node-c: not authorized for
  P.R")`. The public `run_cluster` (caller-chosen session id) passes none.
- **A node does not open an offer its own certificate lacks**:
  `Err(Unauthorized(role, why))`, a new `RunError` variant (`Listen` was
  port-shaped). A courtesy check; the initiator's is the one that holds.
- `node_label` falls back to the certificate's node name: a member's name can
  be its id (`Membership` observations), which made refusals print hex ids.

## 2. Raw-send denial

The rule: a raw frame crosses a link only when the certificates at BOTH ends
carry `raw_send`. "Refuse frames to/from a peer whose certificate lacks
raw_send", made symmetric: a node without the flag cannot use the primitives
either (it is the isolated `IO.Foreign` pool of D3). A node's frames to itself
(the loopback) are never raw sends.

- `ClusterNode.send_msg`: `Err(NodeQueue.NotAuthorized)` (new `EnqueueError`
  variant), never queued.
- `ClusterNode.queue_for` (what `Node.enqueue` uses, and the only way to the
  data fd): `None`. SessionNode uses the new `session_queue_for`.
- Inbound, `deliver_local`: a raw frame from such a peer is refused before any
  pid or type route and answered `DELIVERY_FAILED` ("not authorized: ..."),
  so the sender's `on_delivery_failed` hears it; the receiver counts it.
- **Exempt, enumerated** (`ClusterNode.session_tags()`, `control_tags()`):
  session traffic, the ten `SessionAP.*` / `SessionNode.*` type tags (before any
  `#<sid>`), when delivered to a route opened with the new `route_session`
  (SessionNode's parties, offers and inboxes); and every control-connection
  frame (tags 0-3, 5-8, 10-15), which ClusterNode alone writes and which never
  reaches a route. A session tag sent to an ordinary route, or a raw tag sent to
  a session route, is refused. The tag list lives in `NodeSend` (loaded first)
  and ClusterNode delegates.
- **Direct certificate-mode connections** (`ClusterConn.*_auth`, what a
  program dials itself): the handshake records `NetKernel.raw_allowed(fd)`.
  `NodeSend.cast` (`Node.send`) returns `Refused(seq, "not authorized: ...")`
  and `handle_frame` answers `DELIVERY_FAILED`; `NodeCall.call` (`RemoteCall`)
  returns the new `CallError.Forbidden` (wire code 6; not `NotAuthorized`, a
  constructor name `NodeQueue` now has, since ambiguous constructors are a
  known miscompile class) and `serve_one` answers `Forbidden` without
  dispatching.
- **Counted and reported**: `ClusterNode.raw_refused` (new `ClusterOps` field),
  `NetKernel.raw_refused()`, and the new `RawSendRefused(node_id, what)` security
  event (`what` = "outbound <tag>", "outbound queue", "inbound <tag>").
- **A race fixed on the way**: `mirror` (the Vault copy of peer certificates)
  ran after the effects, so a link's data reader could start before its
  certificate was visible and wrongly refuse the first frames. The `Install`
  effect now writes the certificate before spawning the readers.

## 3. Cross-node references

**The rule:** in certificate mode `ClusterNode.lookup` and `names` hide a
binding unless a raw send to its holder would be allowed (this node's
certificate and the holder's verified one both carry `raw_send`): a name you
cannot raw-send to is not a reference you should hold. This node's own bindings
always show; a holder it has not verified (no link yet) stays hidden until it
is. The stdlib's coordination namespaces are exempt
(`ClusterNode.reference_namespaces()`: `ap:` offers, `session:` endpoints,
`topo:` topology markers), because they are found by name whatever the holder's
flags and checked by role where they are used. `GlobalPid.make` stays pure: a
pid built by hand is only a value, and sending to it goes through item 2. It is
the plan's "cross-node references are handed out, not computed" line made
concrete: the registry is where they are handed out, and it hands out only what
this node could use.

- Implemented in the pure core (`reference_visible`, inside `visible_map`), so
  visibility refreshes on every tick and on every registry frame.
- **`GlobalRegistry.Entry.registrant`** (`register_as`): each replica records
  the registering certificate's identity: its own for its own bindings, the
  link's verified peer for bindings that peer holds, and the holder's
  certificate if it has one for relayed bindings (keeping what it recorded for
  the same binding before). `ClusterNode.registrant(c, name)` reads it (new
  `ClusterOps` field, not hidden). **Deviation:** it is local bookkeeping, not on
  the wire. Registry leaves have a strict decoder (`[..., clock, creation]`
  exactly), so a new element would make every pre-11b node read `creation` 0.
  It is also out of the Merkle hash and the merge order, so replicas that
  recorded it differently still converge. Registrations are not signed (plan:
  "later"), so a relayed binding claiming another node's pid is attributed to
  the claimed holder; any send to it is still checked.
- Registry WRITES are not refused: a node without `raw_send` can register, and
  no certificate-mode reader sees the name outside the exempt namespaces.

## 4. SessionNode's direct path

- `dial_all` / `accept_all` use `ClusterConn.connect_split_auth` /
  `accept_split_auth`. The auth comes from the new
  `ClusterNode.auth_from_env(name, secret)`: certificate mode when
  `MARCH_NODE_CERT` is set (the variables `config_from_env` reads, including
  `MARCH_CLUSTER_REVOCATIONS` for the revoked predicate), else the secret. So
  `run_<Role>` / `host_<Role>` switch mode exactly as a cluster node does, with
  no new argument for the user.
- **The two-way check** on the direct path: a direct session has no offer or
  initiator, so each side checks that the peer's certificate names the role it
  plays, as `:offer` or `:initiate` (`direct_role_ok`). The dialer checks right
  after the handshake (it knows the role it dialled), and the acceptor checks
  once the peer's hello names its role. A refusal is `Connect(role, "role
  Audit.A is played by node-a: not authorized for Audit.A")` or `Accept(...)`.
- `SessionNode.run`, `run_hosted` and `run_hosted_or` take `proto` and `roles`
  after the fingerprint; the generated runners pass them
  (`test/two_node/protocol/node_b.march`, the one direct caller, updated). The
  "(do both nodes run with the same secret?)" hint is only added in
  shared-secret mode.

## Tests

- `test/session/cert_authz.march` (dune rule, compiled): fake `ClusterOps`
  dictionaries sharing a fake registry and network, no sockets: the initiator
  skips an offer whose node lacks the role (and sends it no invitation), that
  node's own `offer_Ledger` refuses, the offer refuses an unauthorized
  initiator, capacity 0 shows the check passed ("full"), shared-secret mode
  checks nothing, and a squatter on a session role name is refused.
  **Deviations:** compiled only (the interpreter does not run the offer actor
  while the initiator polls), and `--no-cap-strict`: calling
  `NodeQueue.start_local` from user code (the fake's data queue) fails the
  capability ceiling in stdlib `Socket`, which declares no `needs`. That is
  pre-existing, with a 9-line repro, filed as
  [../todos/2026-09-25-nodequeue-start-local-socket-ceiling.md](../todos/2026-09-25-nodequeue-start-local-socket-ceiling.md).
- `test/stdlib/test_session_ap.march` (pure: authorize, raw policy, session
  tags, control tags, `Forbidden` on the wire) and `test_cluster_node.march`
  "cross-node references" (the pure core: hidden and visible by flag, exempt
  namespaces, shared-secret mode, the recorded registrant, the Merkle hash).
  Each was checked red on an intentional perturbation.
- Two-node scenarios (compiled, `scripts/two-node.sh`):
  - `cert_role_denied`: node-b's certificate names only `Thumbs.Render:offer`;
    its `offer_Ledger` is refused, it forges the Ledger offer name, node-a
    skips it without inviting (0 invitations reach it), and a Thumbs session
    forms.
  - `cert_initiate_denied`: node-a's certificate names only
    `Thumbs.Client:initiate`; node-b's Checkout offer refuses it.
  - `cert_raw_send_denied`: node-b has no `raw_send`. Both nodes' raw
    `send_msg` / `queue_for` to each other are refused. The loopback is
    allowed. node-b, skipping its own check through the session queue, sends
    one frame of each non-exempt kind (raw tag to a pid route, to a type route,
    session tag to a raw route, raw tag to a session route), and node-a drops
    and counts each and answers DELIVERY_FAILED; the exempt kind (session tag
    to a session route) is delivered. `Node.send`'s and `RemoteCall`'s paths on
    a direct certificate-mode connection are refused at both ends. Each node's
    registered name reaches the other with its registrant, hidden from lookup,
    while its own shows.
  - `cert_direct`: `run_<Role>` in certificate mode; Pair runs, Audit is
    refused by the dialer, Ledger by the acceptor.
- **Found by the full suite:** the refinement coverage audit's corpus baseline
  (`test/refine_audit/corpus.baseline`) gained `session_ap`'s two lines, as it
  did for `node_cert` in 11a. The quick suite does not run `test_refinecheck`,
  so this landed as a follow-up commit after the four.
- **Changed fixture:** `cert_ok`'s node-b certificate gains `raw_send` (node-a
  raw-sends it pings, which the new rule refuses otherwise); its golden shows
  `flags=raw_send`. `frame_tampered` and `node_send_typed_loopback` gained a
  match arm for the new constructors.

## Not done / open

- `SessionAP.authorize` is the seam for step 9's fingerprint table; their
  `fp_verdict` goes in place of the fingerprint line of `offer_verdict`.
- Registrations are unsigned (above). Remote monitors (control tags 7, 8 and
  12) are not raw sends and are not refused. They leak liveness, not
  authority.
- The session log of 7.4 ("Record") is not built.
