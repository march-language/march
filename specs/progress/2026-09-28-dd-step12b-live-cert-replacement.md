# Distributed deploys step 12b, first half: live certificate replacement

**Landed** 2026-09-28. Design: section 10 "12b" of
`specs/plans/2026-09-28-dd-step12-control-plane-design.md`, on PR #671's branch at the
time of writing. Decision D39 there keeps issuance offline (`forge cluster cert`), so
a node has to accept a new certificate while it runs. Before this, a node read its
certificate once at start (`config_from_env`), and docs/cluster-certificates.md told
operators to renew and restart. The second half of 12b, the control plane delivering
certificates and revocations as release items, is not part of this change.

## What

- `ClusterNode.replace_cert(node, cert_text, key_hex)` (and `ClusterOps.replace_cert`).
  `key_hex` "" keeps the current key. The check runs in the caller (`replace_checked`):
  the operator's signature, not expired, names this node (`NodeCert.node_name`, as the
  handshake checks), names the key, not revoked (the node's live list, through the
  credentials' `revoked`). On `Err` the certificate in use is kept.
- The node's credentials now live in a Vault on the handle (`h.auth`), not in a
  `start`-time capture. The acceptor's `handshake_in`, `dial_one`, `own_cert` and the
  raw-send check (`h_raw_ok`) read them there, so the next handshake presents the new
  certificate. `CnHandle.own` is gone. The node actor then takes the certificate into
  `CnState.cfg.auth` (`ReplaceCert`, `core_replace_cert`), so dials and
  `core_own_cert` use it too.
- **Existing links: re-authenticated in place, not redialled.** A replaced link
  cancels every session on it (SessionNode's `peer_node_closed` on the link's
  `on_peer_closed`, and `recheck_links`). So `core_replace_cert` sends each linked peer
  a `CERT_UPDATE` control frame (tag 16): the new signed certificate plus an ed25519
  signature, by the NEW certificate's key, over
  `"march-cert-update-v1 <sender> <receiver> " ++ cert bytes`. The frame rides the
  link's MAC, so only the peer that did the link's handshake can send it. The proof
  shows that peer holds the new key, which makes a new-key certificate as safe to take
  in place as a same-key renewal. It also binds the receiver, so a frame recorded on
  one link is useless on another. The receiver (`core_peer_cert_update`) checks the
  operator's signature, expiry, revocation, that the certificate names the same node
  it presented before, and the proof. It then stores the certificate as the link's
  (`CnState.certs`, mirrored to `peer_cert`), so the per-tick expiry recheck, the
  raw-send and role checks and `peer_cert` all use the new one. A refusal changes
  nothing and is reported. A link formed after a replacement also gets a
  `CERT_UPDATE` (`CnState.rotated`), in case its handshake began under the old
  certificate.
- **Sessions are not dropped**, so nothing needs documenting as unavoidable, with one
  exception: a peer running a March from before `CERT_UPDATE` ignores the frame
  (`core_frame` drops unknown tags). It keeps the old certificate, drops the link at
  that certificate's expiry, and the redial then handshakes under the new one.
  Sessions on that link are lost. That case is documented, not tested.
- **The trigger from outside: a file watch, not a signal.** `config_from_env` sets
  `CnConfig.cert_files` when MARCH_NODE_CERT names a file. MARCH_NODE_KEY's file is
  watched too, and a key given as a value is kept. The ticker re-reads both every
  MARCH_NODE_CERT_POLL_MS (default 10 s) and calls `replace_cert` when either
  changed. Why a file:
  - SIGHUP is already Topology's reload, and SIGUSR1 is the scheduler's preemption
    tick, which the runtime reserves.
  - What renews certificates in practice rewrites a file and signals no one: a
    Kubernetes secret volume (an atomic symlink swap), cert-manager, a Vault agent, a
    CI job copying files. A signal would need a second step from each of them.
  - The files are the configuration the node already reads, so there is no second
    source of truth.
  - A signal-driven reload is still one `Signal.watch` plus `replace_cert` away for
    whoever wants one.

  Each distinct content is tried once. A refusal, such as a key file that lands before
  the certificate naming it, is reported and retried when either file changes again.
  The watch runs in the ticker task, which already moves to a new code epoch after a
  deploy (see `2026-09-25-dd-review-link-reader-tasks-pin-epoch.md`), so it adds no
  long-lived task.
- `SecurityEvent` gains `CertReplaced(node_id, serial)` (this node's own, or a peer's
  accepted update) and `CertRefused(node_id, why)`. `control_tags()` gains 16.
  `test/two_node/frame_tampered` matched every variant by name and now has a
  wildcard arm.

## Tests

- **Unit** (`test/stdlib/test_cluster_node.march`, "live certificate replacement", 8
  cases, eval harness; they call functions this change adds, so their red is not
  separately provable; the scenario's is):
  - a peer's update replaces its certificate, and the link survives ticks past the
    old certificate's expiry; without the update the same link is dropped;
  - a new-key certificate is taken when the proof is by the new key and refused when
    the proof is by the old one;
  - refusals: a proof made for another receiver, a certificate not signed by the
    operator, an expired one, one naming another node, a revoked one, a garbage
    frame, and a shared-secret node;
  - `core_replace_cert` sends each linked peer one update, and the peer's side
    accepts it;
  - a link formed after a replacement gets an update, and one before any does not;
  - a shared-secret node has nothing to replace.
- **Two-node** `test/two_node/cert_rotate` (three processes). node-b's first
  certificate lives 20 s. A session (loop protocol `Order`, one item every 200 ms)
  runs through the rotation. Then:
  - the scenario installs a certificate for a NEW key by replacing node-b's key and
    certificate files, key first;
  - node-b reports its own `CertReplaced`, and node-a the peer's;
  - past the old certificate's expiry the same session is still running, and node-a
    never reports node-b dead;
  - node-c then presents node-b's old certificate and key, and node-a refuses it with
    "certificate expired".

**Red without the change** (stdlib/cluster_node.march at `61f5820d7`, with the scenario's
two `CertReplaced`/`CertRefused` arms and the two "replaced" waits removed so it
compiles): node-b keeps its old certificate and node-a drops it at expiry:

```
node-a: node-b dead: certificate expired
node-a: refused a handshake: certificate expired
node-b: session failed: session_node: cancelled while waiting on role Shop: connection lost
```

and the "session still running after node-b's old certificate expired" line never
comes. With the change the scenario is green. One fixture fix on the way: node-a
printed `node-b dead: connection refused` at teardown (node-b stops first); node-a now
reports deaths only before the stop file exists.

**Not done here:** the control plane delivering certificates (the second half of 12b);
a test against a peer that predates `CERT_UPDATE`; own-certificate expiry alerting.
