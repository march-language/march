# Compiled HttpServer leaks ~0.5 KiB per request (both server modes)

Logged 2026-10-02 while running forgepm's pool acceptance (sub-project A,
`specs/2026-10-01-forgepm-pooled-db-design.md`), where RSS grew linearly.
**Fixed the same day**, together with a second ~1 KiB/request leak the fix
uncovered: see `2026-10-02-http-result-conn-and-join-point-closure-leaks.md`.
After the fix the repro below measures 0.006 KiB/req; the regression guard is
`test/test_http_native.ml` Phase E (20,000 pipelined requests, < 2 MiB growth).

## Repro

`test/native/http_text_leak_repro.march` (kept as the minimal repro; the
e2e harness's own server is the wired test): a
text-only handler, `HttpServer.new(port) |> plug(fn conn -> conn |>
HttpServer.text(200, "ok")) |> listen()`. Compiled with `--opt 2` on main
(2026-10-02), driven with `wrk -t4 -c32 -d10s` after a 2 s warm-up:

| mode | requests in 10 s | RSS growth | per request |
|---|---|---|---|
| `MARCH_HTTP_EVLOOP=0` (thread pool) | 312,858 | 158,304 KiB | 0.51 KiB |
| `MARCH_HTTP_EVLOOP=1` (event loop) | 319,742 | 161,216 KiB | 0.50 KiB |

Growth is linear (10 s runs scale from 60 s runs), so it is a leak, not a
warm-up plateau. No actors, no stdlib beyond `HttpServer`, so the owner is the
HTTP request path in the runtime: `march_conn_from_parsed` (`runtime/
march_http.c`: conn record + method/path/header strings ≈ this size), the
pipeline-closure RC per call (`march_incrc_local(pipeline)` before
`fn(pipeline, conn)` in both `march_http_evloop.c` and `march_http.c`), or the
response path. Both modes leak the same amount, so suspect the shared code.

Stacked on top in forgepm (same method, pooled binary, thread pool):
`test/native/pooled_actor_http.march`'s actor checkout adds ~0.4–0.6 KiB/req;
depot `Db.exec("SELECT 1")` adds ~7.8 KiB per query; a 404 through forgepm's
full router costs 36 KiB/req (2 GB in 10 s). forgepm prod at ~40 req/s only
survives because it is slow; the pooled Repo (13× faster) would OOM it.

## Plan

1. Reproduce with LSAN/ASAN in Docker (`project_asan_local_requires_docker`),
   or count `march_alloc` vs `march_free` per request with `MARCH_TRACE_GC`.
2. Fix at the owner; then wire the repro into `test/test_http_native.ml`'s
   `with_compiled_server` with an RSS-per-request assertion (the existing
   `run_pooled_e2e` bound of 8 MiB over 1800 requests is 4.5 KiB/req and
   cannot see a 0.5 KiB/req leak; tighten it once this is fixed).
3. Then the depot `Db.exec` 7.8 KiB/query and forgepm's router path.
