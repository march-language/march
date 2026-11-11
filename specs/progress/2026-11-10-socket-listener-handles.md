# Socket and Listener handles; Udp, Tls, WebSocket handles opaque (2026-11-10)

Ocap phase 2, Task 5 (plan: `specs/plans/2026-11-10-ocap-p2-handles-plan.md`).

- `stdlib/socket.march`: every connection function takes a `Socket` (kind TCP = 3,
  TCP_BORROWED = 4 accepted); `connect` / `connect_timeout` return
  `Result(Socket, SocketError)`; `close` returns `Result((), SocketError)`. New
  `listen` / `accept` / `accept_timeout` / `local_port` / `close_listener` over a
  `Listener` (kind 5). `SocketError` gains `ListenFailed`, `AcceptFailed` and `Closed`, and
  derives `Eq`. A read cut short by a concurrent `close` (EOF from `shutdown`, or the
  cancelled wait) is `Err(Closed)`. `@[stdlib_internal]`: `raw_fd`, `adopt`, `borrow`.
- `stdlib/udp.march`: `opaque type UdpSocket = UdpSocket(Socket)` over kind UDP (6);
  `UdpError` gains `Closed`; every use is bracketed by `handle_enter` / `handle_leave`.
- `stdlib/tls.march`: `TlsCtx` / `TlsConn` are opaque over kinds TLS_CTX (8) / TLS (7).
  `connect(s, ctx, host)` / `accept(s, ctx)` detach `s` while still in flight and store the
  fd as the TLS box's aux, so `Tls.close` closes both; on failure `s` stays the caller's.
  `TlsError` gains `Closed`. `https_get` now frees its context.
- `stdlib/websocket.march`: `opaque type WsSocket = WsSocket(Socket)`, a TCP_BORROWED box
  built by the server (`march_ws_sock_new`, runtime/march_http.c; all three handoff sites:
  the sequential server, the pooled connection loop, the event loop's handler thread). The
  server closes the box when the handler returns (`march_ws_sock_done`), so a task still
  holding the socket gets no further access to a connection whose fd is about to be closed
  and reused. A borrowed box never closes the fd.
- Close wakes a parked user on macOS too (ruling R3). `march_sched_fdwait_cancel(fd)`
  (runtime/march_scheduler.c) wakes every green thread parked on `fd` in
  `march_sched_wait_fd(s)` and makes those calls, and later ones, return
  `MARCH_FDWAIT_ERROR` / `ECANCELED` until `march_sched_fdwait_forget(fd)`, which the box's
  release calls just before `close(fd)`. The blocking (off-scheduler) wait polls in 100 ms
  slices and checks the same set. `march_handle_close` cancels TCP, LISTENER and UDP
  descriptors after its `shutdown`; for TLS it cancels the aux fd and shuts down only its
  read side, and only when another use is in flight (so a plain close still sends
  close_notify, and no write to a shut-down socket can raise SIGPIPE).
- Ruling R4: a TLS or TLS_CTX box released with no registered closer aborts.
- `runtime/march_tls.c`: SSL_shutdown's close_notify to a peer that had reset the
  connection raised SIGPIPE (exit 141; seen as the TLS groups probe's server dying after
  C1). The fd gets `SO_NOSIGPIPE` at `march_tls_connect` / `march_tls_accept` (setting it
  at close time is too late: setsockopt on a reset socket fails with EINVAL); on Linux the
  close blocks SIGPIPE around SSL_shutdown and consumes it. SSL_write/SSL_read on Linux
  are still unprotected (pre-existing).
- `lib/modules/module_registry.ml`: an `opaque type`'s constructors are no longer exported
  across the module boundary. They were, with only their arity, so `Udp.UdpSocket(5)`
  typechecked with a fresh variable for the argument.
- Callers: cluster stack (`cluster_conn`, `cluster_node`: `handle_detach` after connect;
  `net_kernel`: `Socket.borrow`), `http_transport` (`Socket.adopt` + `Tls.connect`),
  `forge/tasks/forge_registry.march`, the cluster native and two-node fixtures (raw
  `tcp_*` builtins until Task 9 / 10), the socket fixtures (handle API).
- Tests: `test/stdlib/test_socket.march` (migrated; listen/accept round trip, use after
  close, accept timeout; also run by `march test` and compiled `--compile --test`),
  `test/native/socket_close_while_recv`, `listener_close_while_accept`, `udp_close_while_recv`,
  `socket_sent_to_local_actor`, the TLS groups probe's C4 case (Tls.close while parked in
  Tls.read), `test/test_handle.c` (missing TLS closer is fatal; close cancels a wait on a
  listening socket), `test/errors/handle_forge_1` and `stdlib_internal_2`, and
  `test/stdlib/test_tls.march` (migrated; use after close).
