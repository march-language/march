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

## Fixed 2026-11-06

The harness records every `start_node` independently of live PIDs and fails the
final comparison if a started node has no expected file. Waiting, killing, or
restarting a node cannot erase this obligation; unstarted nodes need no golden.
Existing golden comparisons (including scenarios that launch their own nodes)
are preserved.

`scripts/test-two-node.sh` drives the real harness using shell node fixtures and
a stub compiler: missing goldens for a/b/c fail, completed nodes still require
goldens, unstarted nodes need none, restarts work, and mismatches fail. It runs
in doc-lint CI and through the affected-suite selector.

`cert_order` was the sole scenario with literal `start_node` calls missing goldens.
It now checks b/c output too, removing only the exact per-session placement lines
after its existing nonzero cross-node-session assertion. Raw output is retained.

Validation: the regression script and all 47 affected-selector checks pass;
all 95 scenario scripts' literal `start_node` calls have goldens. The real
`cert_order` scenario passed (12 sessions, 6 cross-node) with all three goldens.
The full 95-scenario network sweep was not run locally.
