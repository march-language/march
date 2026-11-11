# `Socket` and `Listener` handles; `Udp`, `Tls`, `WebSocket` opaque (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 5. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- `Socket.connect`/`listen`/`accept` and every `Socket` use take and return handles; `SocketError` gains `Closed`.
- `Udp.UdpSocket`, `Tls.TlsConn`, `Tls.TlsCtx`, `WebSocket.WsSocket` become opaque handle types.
- `Socket.raw_fd`/`adopt`/`borrow` are `@[stdlib_internal]`; seed the `stdlib_internal_2` golden diagnostic with the first attributed function.
- Known runtime gap to fix here (Task 1 review, measured): on macOS `shutdown()` on a listening socket or an unconnected UDP socket does not wake a thread parked in `accept()`/`recv()`, and TLS close does not shut down the aux tcp fd, so a close while parked defers the release indefinitely. Linux wakes both. Needs close-while-parked fixtures and a macOS wake (scheduler cancel of the parked wait, or `dup2` of a dead socket).
- `release_kind` in `runtime/march_handle.c` should `march_abort` when a TLS/TLS_CTX releaser is missing instead of leaking silently.
