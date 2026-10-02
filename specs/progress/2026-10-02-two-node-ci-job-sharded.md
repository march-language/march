# CI: the `two-node` job is two shards; sanitize-gate's step limit raised

**Date:** 2026-10-02

## Symptom

`two-node` on main timed out at the scenarios step's 55 min ("The action
'Two-node scenarios' has timed out after 55 minutes"): main runs 36945831912
(078067811, last line `two-node[setup_timeout]: ok`) and 36953454223
(46bd9f736, last line `two-node[silent]: ok`), and PR #733's run 36951612638
(last line `two-node[restart]: ok`). Every scenario that ran reported `ok`.

## Cause: the list grew; nothing hung or slowed down

Per-scenario wall time, from the timestamped job logs
(`gh api --allow-escape-sequences repos/march-language/march/actions/jobs/<id>/logs`,
time between consecutive `two-node[<s>]: ok` lines), for six green runs of
2026-09-30..10-01 against the three timed-out ones:

- Every scenario present in both took the same time to within a few seconds
  on a runner of the same speed. Nothing after `setup_timeout` hangs: the
  three timeouts stop at three different scenarios, which is where the clock
  ran out.
- Ubuntu runners come in two speeds, ~25% apart on every scenario. The 67
  scenarios of the green runs took 2332-2340 s on a fast runner and
  2925-3011 s on a slow one: 39-50 min of a 55-min step.
- `8542e1fb0` / `6e369e9a1` (control plane) added `control_cert` (~143 s),
  `control_leader_kill` (~146 s), `control_partition` (~200 s) and
  `control_plane` (~136 s): ~625 s. The 71-scenario list is ~48 min on a fast
  runner and ~61 min on a slow one.

The #746 observe socket, #741 mimalloc, #732 fold inline loop and #735 actor
message leak changes moved no scenario's time.

## Fix

- `scripts/two-node.sh --list K/N` prints shard K of N: the sorted list dealt
  round-robin (index mod N), so the families that share a name prefix and a
  cost (`control_*`, `protocol_*`, `cert_*`) spread across shards. Bare
  `--list` is `--list 1/1`. A malformed or out-of-range K/N exits 2.
- `ci.yml`'s `two-node` job is a matrix over `shard: [1, 2]`
  (`two-node (1/2)`, `two-node (2/2)`). With the slow-runner weights the
  shards come out at 30.0 and 30.6 min (~24 on a fast runner). The scenarios
  step is 50 min and the job 80. The node_discovery soak runs in shard 1 only.
  The cost is one more Linux runner and ~2 min of setup + build (opam is
  cached) per run.
- The CI loop captures the list before iterating and fails on an empty or
  failed list: `for s in $(scripts/two-node.sh --list 3/2)` would run zero
  scenarios and pass.
- sanitize-gate runs the same scenarios under ASan, and its step reached
  60 of its 65 min on a slow runner (run 36953454223). Its comment's policy is
  to raise the limit while it ends before `test (macos-15, all)`, so 65 -> 85
  (job 80 -> 100). `specs/lang/golden/sanitize.sh` honours
  `SANITIZE_TWO_NODE_SHARD=K/N` for the day it needs sharding instead, and now
  fails on a failed `--list` rather than sweeping nothing.

## When it recurs

A shard timing out with every scenario `ok` means the list outgrew the shards.
Add a third (`shard: [1, 2, 3]` and `--list K/3`) once a shard's green runs
reach ~40 min. The quickest check is the per-scenario table: diff consecutive
`ok` timestamps from the full job logs (`gh run view --log` truncates).
