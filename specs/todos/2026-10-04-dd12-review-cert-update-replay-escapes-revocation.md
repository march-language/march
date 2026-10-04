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
