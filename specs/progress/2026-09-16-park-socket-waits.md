# `[P2]` `tcp_accept` and socket reads block their scheduler thread, so N blocked readers need N+1 threads

Filed 2026-09-16, found by `test/native/session_node_fan_loopback` (three
`@[endpoints]` roles in one process, [[2026-09-16-session-node-multiparty-routing]]).

## What happens

`march_tcp_accept` calls `accept()` straight through:

```c
static int64_t tcp_accept_raw(int64_t listen_fd) {
    int fd = accept((int)listen_fd, (struct sockaddr *)&client_addr, &len);
    return (int64_t)fd;
}
```

(`runtime/march_http.c:216`, called from `march_tcp_accept` at `:241`.) Nothing sets
`O_NONBLOCK` and nothing parks the green thread, so the OS thread that runs the accept is
occupied until a peer connects. The same is true of the blocking socket reads a handshake
does. A green thread waiting on a socket therefore costs a whole SCHEDULER thread, not a
parked continuation.

The consequence is a hard floor on concurrency: a program with K green threads
simultaneously in blocking socket calls needs more than K scheduler threads, or every
thread is blocked and no actor turn, timer or ready task can run. It does not recover —
the work that would unblock the sockets is itself queued behind them.

## How it was found, and the measurement

The fan fixture runs three session roles in one process: six readers and handshakes sit in
blocking calls at once. Measured on that program (same binary, only the thread count
varying):

| `MARCH_NUM_SCHEDULERS` | result       |
|------------------------|--------------|
| 1, 2, 4                | hangs, 3/3   |
| 8, 16                  | passes, 3/3  |

"Auto" resolves to the usable CPU count, so a developer laptop (10+) passes and a
4-CPU CI runner hangs — which is exactly how it showed up: green locally, a 30-minute
step timeout on both CI legs with the fixture as the orphaned process. The dune rule now
pins `MARCH_NUM_SCHEDULERS=8` for that fixture, with the reasoning next to it.

The three-process form of the same protocol (`test/two_node/fan`) had the floor per
node: node-c holds four blocked readers (two data, two control), and with
`MARCH_NUM_SCHEDULERS` at 1 or 2 it stalled right after "up"; 4 passed. A process per
node lowered the floor; it did not remove it.

This is not specific to sessions. Any program that accepts several connections from
several green threads in one process has the same floor: an HTTP server accepting on
multiple listeners, a node that talks to several peers, a test harness that runs both
ends in one process.

## What to do

Make a green thread waiting on a socket park instead of holding its thread:

- `accept` on a non-blocking listener, and on `EAGAIN` register the fd with the
  scheduler's poller and park the green thread, exactly as a timed park does today.
  `march_sched_recv_until` already has the park-with-deadline shape to copy.
- The same for `connect` (`tcp_connect`) and the blocking reads behind
  `NetKernel.recv_frame_exact` / `Socket.recv_timeout`. `Socket.recv_timeout` is the one
  with a deadline already, so it is the smallest first step and the one the readers use.
- Until then, document the floor where it bites: a program blocking K green threads on
  sockets needs `MARCH_NUM_SCHEDULERS > K`.

Worth checking while doing it: whether `march_http.c`'s own accept loop (`:2334`) has the
same property, and whether the HTTP server's thread count is sized by the same accident.

## Witness to keep

`test/native/session_node_fan_loopback` with the `setenv` removed hangs on any machine
whose usable CPU count is 4 or fewer — that is the regression test for the fix. When
accepts and reads park, the `setenv` should come back out and the fixture should pass at
`MARCH_NUM_SCHEDULERS=1`.

---

## Shipped 2026-09-16

### `march_sched_wait_fd(fd, want_write, deadline_ms)` (`runtime/march_scheduler.c`)

One kqueue/epoll fd for the process, armed **one-shot** per wait, a list of waiters keyed
by fd, and the preempt daemon draining it every quantum next to `timer_service`. The
waiter registers, then `march_sched_park_self_until` in 60 s chunks (a wait with no
deadline must not push a never-expiring timer entry: the heap has no cancellation).
Off a green thread, or with no daemon running, it degrades to the blocking `poll()` it
replaces, so every caller works in every mode.

Two rules carry the correctness, both about the list mutex:

1. **The daemon wakes under the mutex.** A waiter's entry lives on its stack and is on
   the list only while it is inside the call; the daemon marks it done and calls
   `march_sched_wake` without releasing `g_fdwait_mu`, so an entry — and the proc it
   names — can never be removed, and the proc never freed, between lookup and wake. That
   is the use-after-free a late readiness event would otherwise cause after a timeout.
   Holding the mutex across the wake cannot deadlock: the waiter takes no scheduler lock
   while holding it, and `march_sched_wake` never takes it.
2. **Register, then park.** Readiness can arrive before the park (the daemon is another
   thread); `march_sched_wake` then finds the proc RUNNING and deposits the `wake_pending`
   permit, which the park consumes instead of parking — the permit that already closes
   `task_wait_done`'s window. No lost wakeup is possible.

Removing a waiter re-arms the fd for any other waiter still on it, else deletes the fd
from the poller, so a reused fd number never carries a stale registration. On epoll,
`EPOLLERR`/`EPOLLHUP` are "ready" for every waiter on the fd; the syscall reports it.

### Call sites converted (`runtime/march_http.c`)

- `march_wait_readable` — the `poll()` behind `Socket.recv_timeout`, `tcp_recv_timeout`
  and `tcp_recv_all` — now parks. **Its callers held the preempt mask across it, which
  would have parked with SIGUSR1 masked and left the next green thread on that OS thread
  unpreemptable**; each now masks around its `recv()` only. The first draft of this change
  missed one of them (`march_tcp_recv_timeout`), which is why the rule is written on the
  primitive's doc comment.
- `Socket.recv` (untimed, `march_tcp_recv_chunk`) — parks first. An fd carrying
  `SO_RCVTIMEO` (`tcp_set_recv_timeout`) keeps its deadline: it is read back with
  `getsockopt` and applied to the wait, so `test_socket_timeout`'s probe B (option set,
  untimed read, must still time out) holds. This was the reader path the `PeerReader`
  loops actually sit in, and the first run still hung until it was converted.
- `tcp_accept` — parks until the listener is readable, then the (still blocking) `accept()`
  returns at once. No `O_NONBLOCK` on the listener, so the HTTP server's `select()`-gated
  loop is untouched in behaviour.
- `tcp_recv_exact` (`NetKernel.recv_frame_exact`) — parks before each `recv`.

Not converted here: `tcp_connect` (loopback connects are immediate; a real remote connect
still held its thread for the handshake), `Socket.write`/`send`, the WebSocket reads, and
anything through OpenSSL. Each was the same mechanical change; none was on the path that
hung. **All converted 2026-09-17** in
[[2026-09-17-protocol-errors-and-parked-socket-waits]].

### Readiness is a hint, so no syscall after a wait may block

A wake can be stale: the daemon dequeues an event for an fd, the waiter that owned it
times out and leaves, a new waiter registers the same fd, and the daemon — holding an
event it already took — marks the new one done. A blocking `recv()` after such a hint
would hold the scheduler thread, the very thing the poller exists to prevent. So every
syscall that follows a wait is non-blocking (`MSG_DONTWAIT` for `recv`; a zero-timeout
`poll` before `accept`) and loops back to the wait on `EAGAIN`, deadline still counting.
The first cut did not do this. It never showed up on macOS; CI's x86 leg was the first
run where the `partition` scenario went unstable.

### A scenario race the timing change exposed

`test/two_node/partition` tracked the post-heal events as a linear phase counter, so a
node that merged the registry sync before its own SWIM view flipped the peer back to
Alive skipped the "Alive again" print forever. Reads that park wake at the poller's
tick rather than at `poll()`'s return, which was enough to change the order. The two
events are now separate flags, in either order. Not a runtime bug, but found by this
change: it reproduced 1/3 in the Linux container.

The same scenario had a second order dependence that only ASAN's slowdown exposed (the
sanitize gate, 1 of 7 scenarios): node-b replied to the sync at once, node-a ended the
session on that reply and closed, and node-b then saw the close before its own SWIM view
had flipped node-a to Alive — so "Alive again" was never printed. node-b now holds its
reply until it has seen node-a Alive, which makes its print causally precede node-a's
close. Both of these were hand-written phase machines assuming an order the network never
promised; the parked reads changed the timing, they did not create the assumption.

### The measurements that decide it

- **`test/test_scheduler_fdwait.c`**, built at `-DMARCH_NUM_SCHEDULERS=1` on purpose:
  every case has one green thread waiting on a socket another has yet to write, so with a
  single OS thread the writer can only run if the waiter really parked. Late write wakes
  the waiter (in ~60 ms, not the 5 s deadline); a silent peer times out at its deadline;
  data present before the wait is ready at once; two waiters on one fd are both woken.
- **`test/native/session_node_fan_loopback`** — the fixture that found this — now pinned
  to `MARCH_NUM_SCHEDULERS=1` in its dune rule, where before the change it hung at 4 and
  needed 8: 5/5 runs, output byte-identical to the golden. That is the regression test,
  and it is not vacuous.
- The three-process `fan` scenario (#499's branch) still exports 8; once both land its pin
  can drop to 1 with the same reasoning.
