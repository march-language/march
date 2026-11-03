# `[P4]` TSAN: `g_fdwait_fd` read by the preempt daemon without its mutex — FIXED

Found 2026-10-12 by the TSAN sweep over `test/native/*.march` (`MARCH_SANITIZE=thread`,
1, 2 and 14 schedulers). It was the most frequent report: 7 fixtures, including
`c_symbol_collision`, `block_sender_loopback` and `cluster_accept_silent_peer`. It fires
at every scheduler count, because the preempt daemon is its own OS thread.

## What raced

`march_sched_wait_fd` creates the process-wide kqueue/epoll fd lazily, in
`fdwait_open`, under `g_fdwait_mu`. `fdwait_service` runs on the preempt daemon every
quantum. It read `g_fdwait_fd` with no lock (`if (g_fdwait_fd < 0) return;`) and then
passed it to `kevent`/`epoll_wait`. That is a plain write against a plain read on two
threads.

It was harmless in practice. The value goes from -1 to a valid fd exactly once, an
`int` cannot tear, and the fd names a kernel object, so no memory has to be published
with it. A stale -1 delays servicing by one quantum, and the waiter has already
registered under the mutex. It was still a C11 data race, and any TSAN report is a
deadlock trigger on macOS (`2026-10-11-macos-tsan-scheduler-wedge.md`).

## Fix (`runtime/march_scheduler.c`)

- `fdwait_open` builds the fd in a local and publishes it with one release
  `__atomic_store_n`, only on success (failure still leaves -1, as before).
- `fdwait_service` loads it once with acquire semantics into a local and uses that
  local for `kevent`/`epoll_wait`.
- The other accesses already hold `g_fdwait_mu` and are unchanged.

The cost is one `ldar` per daemon quantum.

Verified: `c_symbol_collision`, `block_sender_loopback`,
`credit_backpressure_loopback` and `control_channel_loopback`, rebuilt with the fix,
report nothing at 1, 2 and 14 schedulers.
