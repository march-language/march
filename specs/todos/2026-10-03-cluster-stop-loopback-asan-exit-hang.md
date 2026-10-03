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
