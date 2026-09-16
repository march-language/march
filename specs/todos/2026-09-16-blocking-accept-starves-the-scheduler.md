# `[P2]` `tcp_accept` and socket reads block their scheduler thread, so N blocked readers need N+1 threads

Filed 2026-09-16, found by `test/native/session_node_fan_loopback` (three
`@[endpoints]` roles in one process, [[2026-09-16-session-node-multiparty-routing]]).
Plan added the same day, after reading the scheduler and every socket call site.

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
occupied until a peer connects. The same is true of every blocking socket read. A green
thread waiting on a socket therefore costs a whole SCHEDULER thread, not a parked
continuation.

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

The three-process form of the same protocol (`test/two_node/fan`) has the floor per
node: node-c holds four blocked readers (two data, two control), and with
`MARCH_NUM_SCHEDULERS` at 1 or 2 it stalls right after "up"; 4 passes. The scenario
exports 8. So a process per node lowers the floor, it does not remove it.

This is not specific to sessions. Any program that accepts several connections from
several green threads in one process has the same floor: an HTTP server accepting on
multiple listeners, a node that talks to several peers, a test harness that runs both
ends in one process.

## Every blocking socket call today (`runtime/march_http.c` unless noted)

| Builtin | Site | Behaviour |
|---|---|---|
| `tcp_accept` | `tcp_accept_raw` :216, `march_tcp_accept` :241 | bare `accept()`, no EINTR retry, no preempt mask, no park |
| `tcp_connect` | `march_tcp_connect` :785–880 | preempt-masked `getaddrinfo` + `connect`; EINTR/EINPROGRESS → `poll(POLLOUT, -1)`; blocks |
| `Socket.recv` | `march_tcp_recv_chunk` :528–555 | preempt-masked `recv`, EINTR loop, honours `SO_RCVTIMEO` if set; else blocks |
| `Socket.recv_timeout` | `march_tcp_recv_chunk_timeout` :565–600 | `poll()` then `recv()` via `march_wait_readable` :104; preempt-masked; per-call deadline |
| `Socket.write` | :415–430 | `send()` loop, EINTR retried; blocks |
| `NetKernel.recv_frame_exact` | `march_tcp_recv_exact` :686–705 | `recv` loop to N bytes, **no deadline at all** |
| WS reads | :722–770, :2492 | blocking `recv`, some `MSG_WAITALL` |

None sets `O_NONBLOCK`; `march_set_nonblocking` (`march_http_io.c:21`) is used only by
the HTTP event loop.

## What exists to build on

- **Park with deadline:** `march_sched_park_self_until(deadline_ms)` (`march_scheduler.c:3125`)
  returns `MARCH_PARK_WOKEN` / `MARCH_PARK_TIMEOUT`; spurious returns are allowed and
  every caller loops and re-checks. The timer heap gives the deadline half for free (no
  cancellation by design; `park_gen` makes a stale fire a harmless spurious wake).
- **Cross-thread wake:** `march_sched_wake(proc)` works from any thread — the preempt
  daemon already wakes parked procs from `timer_service` (`:3285`). The `wake_pending`
  permit (`march_scheduler.h:250`) closes the lost-wakeup window for a waker that arrives
  before the `PROC_PARKED` store.
- **The lock discipline to copy:** `march_sched_recv_until_mode` (`:3154`) checks the
  wait condition and publishes `PROC_PARKED` under ONE lock. A readiness registration must
  do the same (register fd → park, with the poller unable to slip a wake in between), or
  the exact lost-wakeup bug that function was written to fix reappears.
- **A working kqueue/epoll shape to copy structurally:** `runtime/march_http_evloop.c`
  (`evloop_run` :505, `arm_read`/`arm_write` :191–222, EAGAIN accept loop :144). It is
  NOT reusable as-is: its threads are raw pthreads with zero `march_sched_*` calls and it
  runs the March pipeline inline.

**Does not exist:** any fd readiness integration in the scheduler. Its only wait
primitives are the mailbox and the timer heap.

## Preemption constraints a parking implementation must keep

- SIGUSR1 is installed `SA_RESTART | SA_ONSTACK` and the preempt daemon signals every
  scheduler thread ~1 ms (`:3252–3305`). The preempt mask is **per OS thread** while
  green threads multiplex (`march_preempt.h:31`): a park IS a reschedule, so the current
  `march_block_preempt … syscall … unblock` pattern is illegal across a park. Drop the
  mask before parking; retake it only around each non-blocking syscall attempt.
- `SO_RCVTIMEO` under `SA_RESTART` restarts its timer from zero on every signal
  (`march_preempt.h:19–26`, `march_http.c:533`) — the reason deadline-bearing reads mask
  SIGUSR1 today. Once waiting moves to a poller with the timer heap as its deadline, that
  hazard disappears for those paths; `getaddrinfo` still needs the mask (`:802`, macOS).
- EINTR on the poller wait is retried, never surfaced. The error contract
  `MARCH_RECV_TIMEOUT_MSG` = `"recv: timed out"` (`:88`) is matched verbatim by
  `stdlib/socket.march` and `eval.ml`; a rewrite keeps producing it.

## Plan

1. **A scheduler-owned poller.** One kqueue/epoll fd (global first; per-scheduler later),
   serviced by the preempt daemon thread (it already owns `timer_service` and already
   wakes procs), with an fd → parked proc table and one-shot arming
   (`EV_ONESHOT` / `EPOLLONESHOT`) so a stale registration is a spurious wake, never a
   wrong one. Registration and the park happen under one lock, per the discipline above.
2. **`Socket.recv_timeout` first** (`march_tcp_recv_chunk_timeout`). It already has a
   deadline and the loop-and-recheck shape `park_self_until` demands, a dedicated test
   (`test/test_socket_timeout.ml`, four probes with a sentinel contract), and it is what
   the fan fixture's readers actually sit in. The change is local: replace
   `march_wait_readable(fd, ms)` with register-POLLIN → `park_self_until(deadline)` →
   loop, keeping the `recv()` and the preempt mask around the syscall only.
3. **Then, mechanically:** `accept` (non-blocking listener, park on EAGAIN), `connect`
   (park on EINPROGRESS for POLLOUT, then `SO_ERROR`), `tcp_recv_exact` /
   `NetKernel.recv_frame_exact` — the last one also needs a deadline INVENTED, since it
   has none today and blocks forever on a peer that stalls mid-frame.
4. **Take the pin out.** `test/native/session_node_fan_loopback`'s `setenv` comes out and
   the fixture must pass at `MARCH_NUM_SCHEDULERS=1` — that is the regression test, and
   it fails today at 4, so it is not vacuous.

## Tests that guard this

`test/test_socket_timeout.ml`; the C scheduler suites (`test_scheduler_timer.c` for
park-with-deadline, `_mbox`, `_mt`, `_churn`, `_count`, `_pin`); the native socket
fixtures (`node_send_loopback`, `node_send_typed_loopback`, `node_call_loopback`,
`node_discovery`, `net_frame_large_loopback`, `foreign_actor_http`, `sched_stress`);
the two-node scenarios; and `test_http_native`.
