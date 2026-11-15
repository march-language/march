`[P3]` `HttpServer.spawn_n` still returns an `Int` server handle, the last integer handle (2026-11-13)

Ocap phase 2b. Every file, socket, TLS, WebSocket, UDP and process handle is now a box. `HttpServer.spawn_n(server, n)` still returns the `Int` the runtime hands back, and `HttpServer.wait_for(h)` takes it. A program can forge one and wait on another server. That grants nothing (a wait reads no data and opens nothing), but it is the last integer handle.

Expected: `spawn_n` returns an opaque `HttpServer.Spawned` (a handle box or a record the module does not export the constructor of), and `wait_for` takes it.

Source: `spawn_n`, `wait_for`, stdlib/http_server.march; `march_http_server_spawn_n` in runtime/march_http.c. Related: 2026-11-11-http-server-spawn-n-no-release-conn.md.
