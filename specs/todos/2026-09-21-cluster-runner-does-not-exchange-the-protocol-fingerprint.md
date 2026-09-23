# `[P3]` `cluster_<Role>` does not exchange the protocol fingerprint

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
