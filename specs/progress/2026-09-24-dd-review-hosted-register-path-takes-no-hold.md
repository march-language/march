# Multi-session hosted actors take no epoch hold, and `finish`/`cancel` release one they never took

**DONE 2026-09-24.** The hold is the transport's: `SessionNode`'s hosted `register`
takes it and its hosted `close` releases it, both in the host actor's turn, so both
hosting patterns (`take_idle` then `register`, and `await_X(s, register(s, 0))` for many
sessions) hold exactly once; `take_idle` no longer holds and `finish` no longer releases
(its `close` does), and the generated `cancel` -- a started endpoint that never reaches
`finish` -- is now `cancel(s, p)` and releases through `Session.release_epoch(s)`. Tests:
`test/two_node/hosted` (single-session pattern) and `test/two_node/cluster_ap_local`
(many-session pattern) print `Session.epoch_holds_here()` after the start (1) and after
`finish` (0); `test/test_endpoints.ml` pins that no generated function holds and only
`cancel` releases. Filed 2026-09-24; the text below is the finding as filed.

Filed 2026-09-24 by the distributed-deploys review (step 6, PR #612, commit
753336d36). Plan: 6.1 (nesting rule), II.4.4, D28; progress deviation 10.

## Defect

The generated hosted API takes its hold only in `take_idle`
(`lib/desugar/desugar_endpoints.ml:1077-1082`) and releases in `finish`
(`:1134`) and in `cancel` of an awaiting endpoint (`:1196`). `take_idle` is
only called by the single-session pattern that parks an `idle()` placeholder
first (`test/two_node/hosted/node_b.march:30`). The multi-session pattern,
`await_X(s, register(s, 0))`, never calls it. That is the pattern the language
reference documents for many sessions (`specs/lang/choreography.md:782`), the
one `offer_hosted_R` hosts use, and the one a D23 topology actor binding
needs. `test/test_endpoints.ml:284-285` asserts that `await_*` neither holds
nor releases, so the test pins the gap.

Two consequences:

1. **No hold.** An actor hosting many old-protocol sessions reaches its
   marker and advances while it still keeps their parked endpoints, typed by
   the old protocol. This is exactly what D28 exists to prevent.
2. **Unbalanced release.** `finish`/`cancel` release a hold the actor never
   took. `march_epoch_release` clamps at 0, so on its own this is silent. But
   in an actor that mixes the two patterns, or that holds for another reason,
   one session's `finish` drops another session's hold.

## Confirmed

In the same instrumented run of `test/two_node/cluster_ap_local` as the sibling
todo (`…-cluster-party-never-releases-epoch-hold.md`), the hosted `PingServer`
(`register` then `await_Ping`, then `finish`) produced `HOLDTRACE release
pid=23` with no `hold pid=23` anywhere in the trace.

## Fix I would make

Take the hold where an endpoint first becomes started, whatever the path: in
each `await_*` when its argument is the role's entry state (the value
`register` returns), or in `register` itself when called from an actor. Keep
`take_idle`'s hold for the idle path, but track per endpoint whether it holds,
for example with a flag in the parked value, so `finish`/`cancel` release only
what was taken. Replace the `test_endpoints` assertion with a behavioural test:
a hosted actor with an open session defers its marker.
