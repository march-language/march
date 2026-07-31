# Current State (as of 2026-07-31, HTTP server measured: the default pool starves past 28 connections)


**Counts:** `run_compiler` 619, `run_codegen` 521, `run_eval` 256,
`run_stdlib` **828** (+2 new compiled HTTP e2e cases) with only the
pre-existing environmental `MARCH_SANITIZE` failure — 2224 total.

**The default thread-pool server silently serves only `ncpus*2` connections.**
`march_http.c` sizes the pool at 28 on a 14-core box, and `connection_thread`
owns a connection for its **entire keep-alive lifetime**. At 100 concurrent
connections the kernel accepts all 100 — so clients see no error — but 72 are
never read. Server-side socket queues sampled mid-run: thread pool 100
established, **72 with `Recv-Q > 0`** (request bytes sitting unread), 28
served; event loop 100 established, **0 unread**. Past `pool_size`, a client
connects successfully and then waits indefinitely. This is a production
defect, not a benchmark artifact. The fix is to return the fd to the queue
after each request/batch rather than looping inside the worker; **not done
here** — it is a design change, and the event loop already avoids it.

**The event loop's "3.4x worse latency" was that defect, seen from the client
side.** wrk's latency statistic only reflects connections that were answered,
so the pool looked fast by not doing the work. Little's Law closes it exactly:
pool 28/30,268 = 0.93 ms predicted vs 0.92 ms measured; evloop 100/31,210 =
3.20 ms predicted vs 3.20 ms measured — the ratio *is* 100/28. Per **served**
connection both are ~33 µs, and the event loop costs **15–17% less CPU per
request** (26.4–27.3 vs 31.0–32.1 CPU-µs/req). At c=28, where the pool starves
nobody, the event loop wins on all three axes. An oversubscription theory was
**refuted** by an env-gated thread sweep: 1 loop thread and 14 are
indistinguishable (29.9–31.5k rps, 3.15–3.35 ms), because the server never
exceeded 0.84 of 14 cores.

**Per-request cost, thread-pool path: ~32 µs CPU, 92% of it system time.** All
March user-space work is **1.7 µs (5%)** — `march_conn_from_parsed` 0.8 µs, the
pipeline 0.7 µs, request header `List(Header)` 0.2 µs. The per-call
`march_incrc_local(pipeline)` required for correctness costs **~6 ns (0.02%)`,
measured by slope across 200 extra atomic pairs at ~5.75 ns per atomic RMW —
no bulk pre-bump or codegen borrow is warranted. The `TCP_NOPUSH` cork pair
cost ~1.5 µs and is now skipped for single-request batches (−4.5%). Neither
server's throughput was movable on this box: both cap at ~31k rps while using
under one core, and a second independent client process raised the aggregate
only to 31,243 — the ceiling is macOS loopback, not March. **Only CPU-µs/req
is a valid metric here**; req/s was flat across every ablation including one
that does zero March work.

`march_response_send_plaintext` (`march_http_response.c`) remains dead code and
should be **deleted rather than wired up**: it hardcodes `Content-Length: 13`
and the literal body `"Hello, World!"`, and reaching it requires bypassing the
user's March router entirely, so the program nominally under benchmark never
runs. A general small-fixed-response path is separately not worth building —
the response path is already zero-copy, with iovecs pointing directly into
March strings and static constants and one `snprintf` of Content-Length into
thread-local scratch.
