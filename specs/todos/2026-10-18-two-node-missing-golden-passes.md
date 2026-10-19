# `[P3]` `scripts/two-node.sh`: a scenario with no `node_<x>.expected` passes vacuously

Filed 2026-10-18 while adding `test/two_node/cluster_fingerprint_skew`.

The golden comparison at the end of `scripts/two-node.sh` skips any node whose
`node_<x>.expected` does not exist (`[ -f "$dir/node_$n.expected" ] || continue`), so a
scenario whose goldens were never written, or were deleted, reports
`two-node[<scenario>]: ok` as long as every node exits 0. The new scenario did exactly
that on its first run, before its goldens existed, with node-a reporting the wrong
error.

Fix: fail when a node the scenario STARTED (`start_node`) has no `.expected`; a node
the scenario never starts needs none. Then check every directory under
`test/two_node/` still passes (`scripts/two-node.sh --list`).
