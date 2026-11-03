# `[P3]` `cluster_<Role>` does not exchange the protocol fingerprint — FIXED 2026-10-18

Filed 2026-09-21 by [[2026-09-21-protocol-fingerprint-payload-definitions]], which covered
the other half of its own todo and not this one.

The direct runner now puts `<P>_Msg.fingerprint()` in the session hello and refuses a peer
whose own differs, so a version skew is a setup error there. `cluster_<Role>`
(`SessionNode.run_cluster_party`) has no hello to extend: it finds its peers by name in the
cluster node's registry (`session:<sid>/<role>`) and rides the node's shared data queues.
Two nodes built from different versions of a protocol that meet through
`cluster_<Role>` alone still form a session and discover the skew mid-session.

A `cluster_<Role>` reached through an ACCESS POINT is already protected: `offer_role` /
`offer_hosted` compare the fingerprint carried by `SessionAP.Invite`
(`SessionNode.offer_verdict`). It is the bare cluster pair that is uncovered.

Fix: register the fingerprint alongside the endpoint entry and compare it when a peer's
endpoint is found, refusing with the same `RunError` vocabulary `join_dialed` /
`join_accepted` use. A registered entry with no fingerprint means a peer built before the
check and must be a refusal with a clear reason, as the missing hello field is.

## Fixed 2026-10-18

A registry binding carries a pid and nothing else, so the fingerprint goes in a
second NAME: `run_cluster_party` registers `session:<sid>/<role>#<fingerprint>`
for the endpoint, before the role's own name, and unregisters both on every exit.
Once its peers are found by their role names, `check_peer_fingerprints`
(`stdlib/session_node.march`) reads each peer's `#…` companion
(`ClusterNode.names`, which the `session:` namespace never hides) and refuses,
before anything is linked or sent, with `Err(Connect(role, why))`:

- a different fingerprint: "role R's node was built from a DIFFERENT version of
  the protocol (fingerprint … here, … there)";
- none within 2 s (the companion is registered first, so this only covers
  registry-sync lag): "role R's endpoint registered no protocol fingerprint, so
  its node was built before cluster sessions carried one". The refusing side's
  abandon tells the found peers the role is cancelled, so an old peer that does
  not check does not wait for ever.

A refusing party then LINGERS up to 2 s with its names still registered
(`linger_refused`) before it tears down. Without that, the party that found its
peer first refused and unregistered before the peer's registry ever showed it, and
the peer waited out `find_peers`' 30 s and reported "no endpoint registered for role
R" instead of the skew (seen on the first run of the scenario below). The linger
also registers `session:<sid>/<role>!refused`; a peer refusing in turn ends its own
linger the moment it sees that marker (or the role's name gone), so two checking
parties do not each wait out the other.

`SessionNode.run_cluster` and `run_cluster_hosted` gained a `fingerprint`
parameter (after `session`, as `run` has one); the generated `cluster_<Role>` /
`cluster_hosted_<Role>` pass `<P>_Msg.role_fingerprint(role)`
(`lib/desugar/desugar_endpoints.ml`). `""` checks nothing. Access-point sessions
(`run_cluster_with` / `run_cluster_hosted_with`, from `offer_role` / `initiate`)
pass `""`: their Invite already carried the fingerprint, and their
compatibility table may admit a different one, which an exact compare here would
refuse.

Test: two-node scenario `cluster_fingerprint_skew` (session s1, `fingerprint_skew`'s
two `Thing` definitions over `cluster_<Role>`; session s2, a peer that registers no
fingerprint), both refused on BOTH nodes before either body runs. Verified red with
`check_peer_fingerprints` short-circuited to `Ok(())`: node-a then hangs in s1 (the
mid-session skew: B cannot decode A's `Thing`), and the harness times out.
