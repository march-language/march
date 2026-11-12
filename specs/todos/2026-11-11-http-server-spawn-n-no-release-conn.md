`[P3]` `HttpServer.spawn_n` does not pass `release_conn`, so each request leaks its result `Conn` (2026-11-11)

`listen` passes `release_conn` to `http_server_listen` so the runtime deep-drops each handler result. `spawn_n` calls `http_server_spawn_n(port, n, mc, it, pipeline_fn)` with no releaser, and the runtime comment says it keeps the old behaviour: one leaked result per request. The path is the forked test server, which exits after `n` requests, so the leak is bounded; it matters for leak-checked test runs.

Repro: none that runs standalone; classified from the current source (see the pointer below).

Expected: the spawned server releases each result like `listen` does.

Actual (interpreted / compiled): by source reading only: runtime/march_http.c `march_http_server_spawn_n` ("No releaser: this test-only path has no March-side drop closure").

Source: `spawn_n`, stdlib/http_server.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
