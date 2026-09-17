# `getaddrinfo` off the scheduler thread

Shipped 2026-09-17; the one blocking call [[2026-09-17-protocol-errors-and-parked-socket-waits]]
left on `tcp_connect`'s path.

`march_sched_getaddrinfo(host, port, hints, res)` (`march_scheduler.c`) runs the lookup
on a detached helper pthread and parks the calling green thread until the result is in.
A slow resolver -- a remote DNS server, a stalled `/etc/hosts` read -- now stalls one
green thread, not the scheduler thread it happened to be on and every other green
thread queued there. The helper is not a scheduler thread, so the preemption signal
never reaches it, which also retires the reason `tcp_connect` masked SIGUSR1 around the
call (getaddrinfo is not async-signal-safe on macOS); the mask now covers `socket()` and
`connect()` only. Outside a scheduler, or if the helper cannot be created, it is the
plain call with SIGUSR1 masked, as before.

Two orderings carry the correctness:

- **Wake before park is fine**: the helper's `march_sched_wake` deposits the same permit
  the fd waiter and `task_wait_done` rely on, so the park consumes it.
- **The caller must not leave before the wake has been issued**: the request lives on
  the caller's stack and the wake names the caller's proc. So the helper copies the proc
  out, publishes `done` (the caller may read the result), issues the wake, then
  publishes `woke` (the caller may go); the caller parks on `done` and yields on `woke`.

Witness: `test/test_scheduler_fdwait.c` case 7 -- with the helper delayed 150 ms
(`MARCH_TEST_RESOLVE_DELAY_MS`, a test hook read only by the helper) a sibling green
thread that naps 30 ms finishes first, which on one scheduler thread is only possible
if the resolver parked; the lookup is `127.0.0.1` with `AI_NUMERICHOST`, so no DNS is
involved.
