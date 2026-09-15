# Loopback monitor goldens no longer print scheduling-dependent pids

Shipped 2026-09-15. Test-only fix; no compiler or runtime change.

## Symptom

Four native goldens flaked on CI for PRs that could not affect them. Each
printed node-b's target pid, and the value was sometimes `0` where the
`.expected` had `1`:

- `test/native/monitor_ack_retry_loopback` (ubuntu, run 35021168772)
- `test/native/monitor_expiry_loopback` (macos, run 35024363368)
- `test/native/dist_monitor_loopback`, `test/native/monitor_after_death_loopback`
  (same shape, same race)

## Cause

Both "nodes" run in one process. node-b is a `task_spawn`ed task that does
`spawn(Target)`, while `main` (node-a) concurrently does `spawn(Watcher)`.
Local pids come from one process-wide counter, so Target got 0 or 1 depending
on which spawn ran first. The pid value was only ever printed, never checked.

## Fix

Each test now prints `node-b's target actor` in place of the raw pid. In the
three tests that receive a MONITOR_FIRE, node-a passes the pid node-b
announced in its hello frame into the fire handler, and a `target_label`
helper prints `the monitored target` when the fired pid matches it and
`UNEXPECTED target N (monitored M)` when it doesn't. Before, the test only
showed a number; now it asserts that the fire names the pid that was
monitored. Every other line (reasons, dedupe count, resend and pending counts,
Down count) is unchanged.

## Verification

- 30 sequential runs of each binary matched its `.expected` (30/30 each), and
  so did 48 more run concurrently (12 per test) to mimic a loaded host.
- Red check: a copy of `dist_monitor_loopback` passing `target.local_pid + 1`
  printed `UNEXPECTED target 1 (monitored 2)` and failed the diff.
- Other `*loopback*` goldens were checked; none print a pid
  (`peer_reader_loopback`'s `seq 1` is a message sequence number).
- `test/refine_audit/corpus.baseline` needs no regeneration: the new helper
  carries no refinement contracts, so the entries stay `0 enforced`.
