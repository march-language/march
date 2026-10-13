# `[P3]` `hosted_protocol_change`: "served N, holds" off by one, under ASan

Found 2026-10-13 while looping the scenario under ASan for the
out-of-order-hello fix
(specs/progress/2026-10-05-hosted-protocol-change-unexpected-hello-under-asan.md).

**This is separate from that fix.** The out-of-order-hello panic was a delivery-order
bug in `SessionNode.deliver` and is fixed; this is a count in the scenario's expected
output read before a hold is released, seen in an UNFIXED run, and the per-sender
FIFO change neither causes nor fixes it.
One of 200 unfixed runs in the container (8 busy loops) printed
`host 1: served 1, holds 3` / `served 2, holds 2` / `served 3, holds 1`
instead of 2 / 1 / 0. Every served line was one hold higher than expected.

Likely cause: `Session.epoch_holds_here()` is read when the line prints,
and one hold was not yet released. The candidate is session 4's (its host's
`finish`, or its client's Endpoint, which releases on `ReleaseEpoch` in its
own turn, after `session(...)` has already returned in `main`). If so, the
golden asserts a count that races a release. Either `main` waits for the
holds to settle before `release(gate, ...)`, or the line prints the count
relative to this host. Not seen in plain runs.
