# `[P3]` Nothing tests that `initiate` prefers its own node's offer

Filed 2026-09-24 by the distributed-deploys review (step 3, PR #610). Plan:
4.2 ("Prefer a local offer"), II.3 item 3.

## Defect

`cluster_ap_local` is a single node, so its only candidate is local. No
two-node scenario both offers and initiates on the same node.

## Confirmed

In a scratch worktree, `stdlib/session_node.march:2194` was changed to order
the local candidates LAST. `scripts/two-node.sh cluster_ap_local` still
printed `two-node[cluster_ap_local]: ok`.

## Fix I would make

A two-node scenario where both nodes offer the role and one of them
initiates, asserting that its own offer served the session.
