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
