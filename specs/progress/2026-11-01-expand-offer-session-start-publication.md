# Publish fresh session starts for an unchanged expand offer

`protocol_expand_contract` kept its original Shop offer when the expand
build deliberately retained the old role fingerprint. Under per-frame
routing, that offer's saved start/body closures correctly retained their
creation epoch too, so every session on it still ran Shop phase 1. Both CI
and the unchanged local scenario reported the same missing pairing:
`v2 Buyer with an expand Shop: NOT seen`. Contract sessions worked because
the changed fingerprint caused the hosting actor to create a fresh offer.

The fixture now publishes a complete session-start callback from each
hosting actor turn, indexed by the offered role fingerprint. A retained
offer loads that callback before creating its Endpoint. Calling the newly
created closure selects its own epoch; a session already executing an older
closure keeps its original epoch. Contract publication uses a different
key, preserving the expand callback for the old offer while it drains.

The publication type contains only a session id, abandonment predicate,
and the stable session result. Protocol-specific typed endpoint values
are constructed inside the callback rather than passed between versions.
This is an explicit fixture work boundary, not a change to ordinary
closure pinning or an unchecked call into a new endpoint ABI.

Both expected-output files and all deployment/counter assertions remain
unchanged. `node_b.march` remains a symlink to the baseline monolith.
The related unchanged `protocol_evolve` scenario passed; it already creates
new offers when the protocol fingerprint changes.

Validation: the corrected `protocol_expand_contract` scenario passed with
all original pairings, no-loss and reload-counter checks. The remaining
shard-2 scenarios (`session_churn`, `setup_timeout`, `slow_start`, `stream`,
and `topology_rejoin`) also passed.
