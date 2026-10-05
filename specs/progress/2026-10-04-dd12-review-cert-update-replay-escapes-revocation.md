# [P2] DD step 12b: a CERT_UPDATE frame can be replayed on a later link, letting a holder of a leaked old key escape revocation

**Review:** `specs/progress/2026-10-04-dd12-security-review.md`. PR #676 (live cert
replacement / re-handshake).

## What breaks

A node's live certificate replacement sends a `CERT_UPDATE` frame whose proof
covers only `"march-cert-update-v1 " ++ from ++ " " ++ to ++ cert bytes`
(`stdlib/cluster_node.march:594-597`) — it is **not** bound to the link's
handshake transcript, a nonce, or time. Cluster frames are MAC'd but not
encrypted (`specs/lang/clustering.md:320`), so any on-path party can record one.
`core_peer_cert_update` (`cluster_node.march:648-680`) then accepts that recorded
frame on any later link from the same sender and replaces `st.certs[b]`. The
per-tick recheck (`core_check_certs`/`cert_problem`, `:527-551`) looks only at the
*currently held* cert, forgetting the cert the link actually authenticated with.

Consequence: a party holding b's leaked old key can keep a live link after the
operator revokes that old cert.

## Attack, concretely

1. b's key A leaks; operator issues cert B (new key) and revokes cert A.
2. Real b sends a its `CERT_UPDATE(B)`; attacker records the frame.
3. In a window where a does not yet know A's revocation (before gossip, or after a
   restarts without the token in `MARCH_CLUSTER_REVOCATIONS`), the attacker
   handshakes as b with cert A, then replays the recorded frame.
4. a now holds B for the attacker's link; when A's revocation arrives the link is
   not dropped, and it keeps B's roles until B expires.

## Evidence

`specs/reviews/dd12/cert_update_replay_escapes_revocation.march` — pure
`ClusterNode` core (no sockets), as in `test/stdlib/test_cluster_node.march`:

    dune build --root . bin/main.exe
    ./_build/default/bin/main.exe specs/reviews/dd12/cert_update_replay_escapes_revocation.march

Output:

    honest update on link 1: accepted, a holds serial-b-new
    attacker link 2 up, a holds serial-b-old
    control, no replay: drops after revocation = 1
    replayed update on link 2: accepted, a holds serial-b-new
    after replay: drops after revocation = 0

The control shows the old cert's revocation drops the link (1); after replaying
the recorded frame the same revocation drops nothing (0).

## Suggested fix (not applied)

Bind the proof to the link: include the handshake transcript hash (or both
nonces) in `cert_update_message`. Also keep the handshake-time certificate per
link and drop the link if either it or the current cert is revoked.

## Resolution (2026-10-04)

A CERT_UPDATE is now bound to its link (`stdlib/cluster_node.march`, the
"live certificate replacement" section):
- The handshake records each sealed connection's transcript hash
  (`NetKernel.link_binding(fd)`, set in both handshake modes, dropped by
  `forget`). The transcript covers both hellos (nonces, ephemeral keys,
  certificates), so no two connections share one. It is symmetric
  (`ClusterAuth.transcript` orders by nonce), so both ends hold the same
  bytes. `CnLink` carries the control connection's transcript as `binding`
  (`core_linked_bound` / `core_dialed_bound`; the unbound `core_linked` /
  `core_dialed` keep an empty binding for pure tests).
- The proof (`cert_update_message`, now `march-cert-update-v2`) signs
  sender, receiver, the per-link counter, the binding and the certificate.
  The frame is `[16, "v2", counter, cert, proof]`. The sender raises
  `cu_sent` per link on every update. The receiver verifies against *its*
  link's binding, requires `counter > cu_seen`, and records it. A frame from
  another link fails the signature. One taken before on the same link fails
  the counter (the MAC replay window already refuses a byte-identical
  re-send; the counter makes the proof itself one-shot).
- An update whose certificate was issued before the held one is refused
  (`NodeCert.order_problem`), so an update cannot downgrade a link either.
- A v1 frame (no binding) is refused ("not bound to this link"). Mixed
  versions fall back to the expiry redial, as a pre-CERT_UPDATE peer does.

Revocation ordering. A replayed update can no longer swap the certificate a
link is held under, so `core_check_certs` keeps checking the certificate the
attacker's link authenticated with, and the revocation drops it. Handshakes
and updates both refuse a revoked certificate, so a revocation always wins
over a later replay of the revoked one.

The review's "also keep the handshake-time certificate and drop the link if
either is revoked" was considered and not done. With the binding, an update
taken on a link proves the new key's holder made it for that exact transcript,
so the link is the real node's. Dropping it when the *old* certificate is
revoked would cut the sessions of every honest node that rotated away from a
leaked key, the case live replacement exists for.

Tests (red against `origin/main`'s sources, then green):
- `test/two_node/cert_update_replay`: node-b reaches node-a through node-c, a
  proxy that records b's CERT_UPDATE off the wire. node-c holds b's leaked old
  key, handshakes as b after b stops, and replays the recorded payload sealed
  on its own link. On main, node-a prints `node-b's certificate replaced (2)`
  (replay taken). Now it prints `refused node-b's certificate update: the proof
  is not by the new certificate's key for this link`.
- `test/stdlib/test_cluster_node.march`: the review's core repro (recorded on
  link 1, replayed on link 2: refused, and the old certificate's revocation
  then drops link 2), same-link replay refused, a v1 frame refused, and
  successive replacements numbered per link. A perturbation that verifies
  against an empty binding fails 3 of them.

The interpreted repro under `specs/reviews/dd12/` calls the old 4-argument
`sign_cert_update`. It is kept as the review's historical record and no longer
compiles against this API.
