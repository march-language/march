# `[P2]` `cluster_stop_loopback` under ASAN: node-a sometimes never exits after `main` returns

Found 2026-10-03 (sanitize-gate failures on `fix/bytes-drop-leak`, 2026-10-02, and on
#767's first run, 2026-10-03). Node-a prints every line of `node_a.expected`, `main`
returns, and the process stays alive past the gate's 240 s `TWO_NODE_ASAN_TIMEOUT`.

## Reproduction

In `ci/Dockerfile.two-node` (linux/arm64), with the gate's settings:

```
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 MARCH_SANITIZE=1 TWO_NODE_TIMEOUT=60 \
  scripts/two-node.sh cluster_stop_loopback
```

1 hang in 30 runs. Without `detect_leaks=0`, every run fails on LeakSanitizer's exit
report instead, so set it. Not seen without ASAN.

## What is alive

A temporary dump of the live procs (scheduler idle loop, after shutdown was requested;
not committed) caught two hangs. Both had 7 live procs, 1 of them non-daemon:

- pid 8: `daemon=0`, spawned through `march_thunk_trampoline` (a `task_spawn`),
  `status=WAITING`, empty mailbox, `mbox_wait_mode=2`, and in no `march_sched_wait_fd`
  wait. The scheduler exits only once `g_live_procs` drains, and `wake_idle_daemons`
  wakes only daemons, so this task holds the process forever.
- 6 daemons in `actor_green_thread`, all WAITING with empty mailboxes. They are left
  alone because `wake_idle_daemons` runs only once `g_live_nondaemon <= 0`.

Open: which task pid 8 is. `mbox_wait_mode=2` is the actor loop's receive, which no task
path calls, so the value may be stale or racy. Recording each task's closure code pointer
on the proc (to name the March function) made the hang disappear in 200 runs. Candidates:
a task spawned by `ClusterNode.start`, by the session machinery, or by `NodeQueue`'s
loopback link, that waits for a message `ClusterNode.stop` never sends.

## Done when

The non-daemon task is named and `ClusterNode.stop` ends it (or it becomes a daemon if it
is infrastructure). The repro above then runs 100/100 clean.

## Resolution (FIXED 2026-10-07)

### Reproduced

`node_a` was compiled with `MARCH_SANITIZE=1` and run directly in a linux/arm64 container
(a one-node scenario needs no harness), 6 at a time, each with its own port, under the
gate's `ASAN_OPTIONS`: 4 hangs in 60 runs.

### Named without perturbing it

The earlier attempt recorded each task's closure at spawn, which changed the timing and
hid the hang. This time a scratch runtime dumped only once the process was already hung:
`MARCH_HANG_DUMP`, scheduler 0's idle path, after 20 s of shutdown with a non-daemon proc
alive. For each live proc it printed status, `park_gen`, the wake permit and its
timer-heap entries. For the non-daemon one it also printed the saved context and every
code address on its green stack, symbolized offline. 2 hangs in 90 runs, both identical:

- pid 8, non-daemon, WAITING, `mbox_wait_mode=2`, with a LIVE timer entry (generation
  matching, due in under 200 ms): not a lost wakeup, a loop that re-arms.
- Stack: `run_cluster_party` -> `serve_cluster_outcome` -> `SessionNode.await_outcome` ->
  `actor_call_wait`. That is a session party polling its endpoint actor for the outcome
  (`Actor.call(p.ep, OutcomeReq, 1000)`, retried while the endpoint lives).

### Cause

`ClusterNode.stop` closes the loopback (the node's queue to itself), and frames still
queued on it are refused. A party whose peers are on the same node learns that its
session ended only from its peers' frames, or from `on_peer_closed`, which fires when a
link to another node drops (`data_closed`). The loopback is not such a link, so nothing
told it. When the first session's server party had not yet seen the client's last frames
before stop, its endpoint waited for them forever, `await_outcome` kept polling, and the
party's non-daemon runner task held the scheduler (which exits only once every non-daemon
proc is gone). ASAN's slowdown widens the window between the session's last frames and
stop, which is why it was never seen without it.

### Fix

`h_stop` (stdlib/cluster_node.march) fires every `on_peer_closed` callback for the node's
own id ("node stopped") right after closing the loopback. Each party with a peer on this
node then cancels (`peer_node_closed`), its endpoint reports an outcome, and the runner
returns.

### Evidence

- Fixed, with the dump runtime: 0 hangs in 120 runs. Control, the unfixed binary run
  again right after under the same load: 4 hangs in 90.
- Fixed, with the production runtime: 100/100 clean.
- `cluster_stop_loopback` now registers an `on_peer_closed` callback before stop and
  prints what it was told: `nothing` on main, `node stopped` with the fix (a
  deterministic check of the mechanism, independent of the race).
