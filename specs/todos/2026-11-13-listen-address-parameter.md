`[P3]` `Socket.listen(port)` takes no address: the bind address is one process-wide setting (2026-11-13)

Ocap phase 2b. `Socket.listen(port)` is checked as `IO.NetListen` on the port only. Which address it binds (all interfaces by default) comes from the process-wide `march_http_bind_addr`, set by `HttpServer`'s `bind_to`, not from the call. A module cannot say "listen on loopback only", and a `needs IO.NetListen(...)` scope has no host to check.

Expected: `Socket.listen(host, port)` (or an options record) so the address is part of the authority checked at the call, and `IO.NetListen` can scope it.

Actual: any module with `IO.NetListen` on a port binds whatever address the last `bind_to` chose.

Source: `listen`, stdlib/socket.march; `tcp_listen` in lib/eval/eval_builtins.ml and runtime/march_http.c (`march_http_bind_addr`).
