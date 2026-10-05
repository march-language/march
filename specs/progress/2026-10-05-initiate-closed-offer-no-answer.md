# Initiator waited out the setup time on an offer closed mid-invitation

**Symptom.** The two-node scenario `protocol_evolve` failed intermittently in CI
(3 of 9 runs that included #778, which made a hot deploy's activation slower):
node-b reported one session `refused at formation: node-a did not answer`.

**Cause.** `SessionNode.close_offer` sets the offer's closing flag, unregisters
its name and **unroutes it at once**. node-b's view of the registry lags, so a
Buyer can still pick the old offer and invite it. An invitation that reaches
node-a after the unroute finds no route: node-a's reader answers it with
DELIVERY_FAILED (`ClusterNode.deliver_raw`, "no route to pid ..."), which nothing
ties to the initiator's wait. `await_answer` then waits out the whole setup
budget (`MARCH_SESSION_CONNECT_MS`, 20 s) and `invite_role` reports "did not
answer". The existing "refused: closing" retry in `fill_roles` only covered an
invitation that arrived between the flag and the unroute. Under the scenario,
node-a's ShopHost re-offers Shop under version 2 right after node-a's hot
deploy and closes the old offer, while node-b starts a session every 150 ms.
A slower activation widens the window, which made the race more frequent.
It was a pre-existing race, not a deterministic break.

**Fix** (`stdlib/session_node.march`). While it waits, `await_answer` checks
that the invited offer's registry name (rebuilt by `offer_name` from the
candidate's prefix, fingerprint and node) still binds the invited pid. Once it
doesn't, the wait ends as `OfferGone`. `invite_role` sends a Withdraw (in
case the offer accepted just before it closed) and records "<node> closed its
offer before answering". `fill_roles` retries that reason as it does
"refused: closing", so the replacement offer is found once its registration
arrives, all within the same setup budget.
