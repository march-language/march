# `[P3]` A failed or closed offer leaks its `OfferActor` (and two Vaults)

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
