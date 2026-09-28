# Scenario "cluster_ap_offer_retire": ONE node opens and closes offers and
# counts what is left behind (review finding 2026-09-25-dd-review-offer-
# actors-leak): a closed offer's OfferActor must end once no session runs
# under it, a refused re-offer (AlreadyOffered) must not leave its actor
# behind, and the keys an offer keeps in SessionNode's shared tables must be
# gone once it retires. Plain and hosted offers both. Single-threaded output.
ORDERED=1
start_node a
wait_exit a
