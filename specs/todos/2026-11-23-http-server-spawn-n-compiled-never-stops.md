`[P3]` Compiled `HttpServer.spawn_n(server, n)` does not stop after n requests, and signals ready before it binds (2026-11-23)

From reading the source; not run.

`march_http_server_spawn_n` (runtime/march_http.c, about line 2996) forks a child that calls
`march_http_server_listen` and never returns. The counters meant to stop it,
`g_spawn_n_target` and `g_spawn_n_served`, are written at lines 3027-3028 and read nowhere, and
`spawn_n_server_thread` is an empty stub. The doc string says the server "handles n requests and
then exits"; the code's own comment says the test is expected to kill the child. So
`HttpServer.wait_for(h)` after n requests would block until something else kills the child. The
interpreter's implementation does count.

Second defect in the same function: the child writes the "ready" byte to the pipe before
`march_http_server_listen` has bound the port, so the parent can return and connect before the
listener exists.

Fix: count requests in the child and exit after the n-th response is written; write the ready
byte after `bind` and `listen` succeed. Do it in the same change as
2026-11-13-http-server-spawn-n-handle-int.md and
2026-11-11-http-server-spawn-n-no-release-conn.md, which edit the same function and builtin
signature. Test: a compiled test that serves n requests and then `wait_for` returns.

Found 2026-11-23 while reading the handle code for
specs/plans/2026-11-23-pre-1.0-bug-first-plan.md (unit U6).
