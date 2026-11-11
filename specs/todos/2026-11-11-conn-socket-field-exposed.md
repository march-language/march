`[P3]` # A handler can reach the server's borrowed Socket through `Conn(s, ...)` (2026-11-11)

Found in review of ocap phase 2b, Task 6.

`HttpServer.Conn` is a plain `type`, so a handler can match `Conn(s, _, ...)` and take field 0,
the connection's `Socket`: a TCP_BORROWED box the server runtime made over the descriptor it
owns (`march_http_conn_sock`, runtime/march_http.c). With it a handler can:

- `Socket.close(s)`: closes the box only (a borrowed box never closes the fd), but every later
  use through any copy of that box, including the server's own `HttpServer.peer_addr` /
  `scheme` for later requests on the connection, then sees a closed socket;
- `Socket.recv` / `Socket.write` on it: read or write bytes on the server's connection
  underneath the HTTP parser, or park in `recv` on the server's descriptor.

A close deliberately does not cancel waits on a borrowed descriptor (ruling R12): the cancel
(`fd_cancel_waits`) is keyed by fd, so a borrowed close would also cancel the server's own
waits on that fd. A handler parked in `recv` on the borrowed socket is therefore woken only
by the connection itself.

Fix: make `HttpServer.Conn` opaque (`opaque type Conn`), so outside `HttpServer` / `WebSocket`
it is built only by the runtime and `HttpServer.test_conn` and read only through the
accessors. `WebSocket.upgrade` rebuilds a `Conn` positionally and would need an `HttpServer`
helper.
