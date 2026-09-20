# `[P2]` The protocol fingerprint ignores what a payload type is made of

Filed 2026-09-20 by the choreography UX pass ([[2026-09-20-choreography-ux-hardening]]).

`<P>_Msg.fingerprint()` digests the protocol's roles and steps, with each payload type by
NAME (`Desugar_endpoints.ty_key`). Two nodes whose `Thing` is `{ x : Int }` on one and
`{ x : String }` on the other share a fingerprint, so an access point accepts the session
and the mismatch surfaces as a decode failure mid-session (`Protocol(role, "undecodable
message: ...")`) rather than as a refusal at the invitation.

Fix: fold the DEFINITION of every user type a payload mentions into the digest (the
`DType` body, recursively, for types declared in the module; types from other modules are
out of reach at desugar time and would need the typechecker's view). Also: the standalone
runner and `cluster_<Role>` do not exchange the fingerprint at all; sending it in the hello
and refusing on a mismatch would make a version skew a setup error everywhere, not only at
access points.
