# `[P3]` A failed or closed offer leaks its `OfferActor` (and two Vaults)

**DONE 2026-09-28.** Cause: `open_offer` spawned the `OfferActor` and made two
per-offer Vault tables (`session_ap_flags_<tag>`, `session_ap_strs_<tag>`) before
`ClusterNode.register`; its `AlreadyOffered` arm only unrouted, and `close_offer`
only set "closing", unregistered and unrouted, so neither ever ended the actor. A
Vault table is never freed at all (the runtime registers it by name for the life of
the process; there is no destroy op), so the two tables leaked on every offer, closed
or not. Fix (stdlib/session_node.march only): the `AlreadyOffered` arm kills the
actor; `close_offer` (a no-op on a dead actor, so closing twice is harmless) sets
the flag and sends the actor `Close(o)`; the actor retires in `retire_offer` when
`Close` finds no session running or the last `Ended` arrives while closing. The
kill runs in a task outside the actor's turn, and the "closing" flag is dropped only
after it, so no invitation the node hands over in between is accepted. Offers now
keep their state in two SHARED tables (`session_ap_flags`, `session_ap_strs`) under
keys prefixed with the actor's pid (`Offer.id`): "c<id>" closing, "w<id>/<sid>"
withdrawn, "r<id>" the route key; retirement drops them. Epoch holds: the
`OfferActor` takes none (each session's Endpoint takes and releases its own in
`end_party`), so ending it strands or double-releases nothing. Topology is
unchanged and still right: `active(o)` reads 0 for a dead worker, which is when
`watch_draining` drops a retired offer anyway. Test: two-node scenario
`cluster_ap_offer_retire` (one node) counts `Scheduler.live_procs()` across 5
open/close cycles, 5 refused re-offers, a close with a session running (the actor
stays until the session ends), and the same for hosted offers, and checks the shared
tables are empty at the end. Against the old session_node.march it printed
`false (5 over)`, `false (5 over)`, `actor alive: true`, `false (11 over)`,
`false (5 over)`, `false (1 over)`, `false (7 over)`; with the closing-flag delete
removed from `retire_offer` it printed `offer keys left: 12`.


**Filed** 2026-09-25 from the distributed-deploys review's unconfirmed item 5.
Confirmed from the code: `SessionNode.offer_with` (stdlib/session_node.march) spawns
the `OfferActor` and creates two Vaults before `ClusterNode.register`; on
`AlreadyOffered` it unroutes but leaves the actor and the Vaults alive. Topology's
`open_role` treats `AlreadyOffered` as "try again next tick" while the previous
name is released asynchronously, so one actor leaks per tick for that window.
`close_offer` never stops the `OfferActor` either, so every retired offer (a
placement change, a reload, a capacity change) leaves its actor behind.

Dismissed part of the original item: "`retire` adds each retired offer to
`st.draining` and never removes it" is wrong; `watch_draining` drops the entry once
its `active` count is 0.

**Fix** (session_node.march, coordinate with its owner): stop the actor on the
`AlreadyOffered` path, and stop it from `close_offer` once `active` reaches 0 (or at
once when nothing runs). Test: count live actors across N placement ticks with a
name still held.
