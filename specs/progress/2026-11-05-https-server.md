`[P2]` HTTPS for the stdlib HTTP server — done 2026-11-06

Filed 2026-11-05. Design: `specs/2026-11-05-https-server-design.md`. Plan:
`specs/plans/2026-11-06-https-server-plan.md`.

## What

`HttpServer` could not serve `https://`. It now serves HTTP/1.1 over TLS on both server modes
(event loop, thread pool, and the pool's sequential variant), with `wss://` through the
unchanged `WebSocket` API, certificate rotation without a restart (file polling and
`HttpServer.reload_tls`, files or PEM text), a bootstrap mode for the first certificate
(`tls_wait_for_cert`), per-phase timeouts that apply (`idle_timeout` was discarded by the event
loop and fixed at 10 s on the pool), an extra plain listener (`plain_listener`), and
`redirect_to_https` / `acme_responder` plugs and `HttpAcme.webroot`. `scheme(conn)` tells the two
listeners apart.

## How

- `runtime/march_tls_session.c`: one server-side TLS session on OpenSSL memory BIOs, driven by
  each server's own socket I/O (feed / handshake / read / write / take ciphertext / shutdown,
  plus a session lock and a send lock).
- `runtime/march_tls_server.c`: the process-wide certificate slot (build a context outside the
  lock, swap it in, connections keep the context they started with), the file poller (SHA-256
  of the pair; a refused pair is tried, and logged, once), and the `mts_*` ops table.
- `runtime/march_https.c` (always linked): the configuration `listen` reads, the builtins that
  need no OpenSSL, and the fd → session registry. `runtime/march_https_tls.c`:
  `http_server_tls_configure` and `http_server_reload_tls`.
- OpenSSL stays out of programs that do not serve HTTPS: the three OpenSSL files are members of
  the runtime's optional archive (`Runtime_archive.archived_members`), the always-linked HTTP
  runtime calls them through `runtime/march_tls_ops.h`'s table (installed by the configure
  builtin), and `HttpServer.tls` builds the closure that calls the configure builtin, so a
  plain server never references it. `test_link_deps` pins both a plain and an HTTPS server's
  dependency sets.
- Event loop: per-port listeners; TLS reads feed the session and decrypt into the read buffer;
  response batches are encrypted (copied, so results are released at once) and the ciphertext
  is held per connection until sent; per-connection deadlines in a per-thread min-heap.
- Pool / sequential: `connection_thread` waits through `march_sched_wait_fd` with absolute
  deadlines (parking in sequential mode) on an O_NONBLOCK socket; the TLS handshake, reads and
  writes go through the session.
- `wss://`: the WebSocket functions find the session by fd; recv waits unlocked and
  feeds/reads under the session lock, send encrypts under it and sends under the send lock.

Also fixed on the way: `Tls.server_ctx` leaked its ALPN buffer; the event loop dropped pipelined
requests that arrived behind a deferred write; macOS `TCP_NOPUSH` around the pool's pipelined
batches is off (Darwin does not push queued data when it is cleared, which stranded small
pipelined responses once the socket was non-blocking).

## Capabilities

The design said an HTTPS `listen` needs `IO.NetListen` and `IO.NetConnect.TLS`. Two constraints
changed that: capabilities are checked by reachability from `main` (and `listen` reaches the TLS
configuration on every server), and a module that imports `HttpServer` must declare all of
`HttpServer`'s module-level `needs` (`import_cap_missing`; adding `IO.NetConnect.TLS` and
`IO.FileRead` there broke Bastion 0.3.1, found by building forgepm). So serving HTTPS and
`reload_tls` need `IO.NetListen`, `HttpServer` still declares only that, and the file-reading
ACME plug is `HttpAcme.webroot` (`stdlib/http_acme.march`, `needs IO.FileRead`). A test pins
`HttpServer`'s `needs`. The design doc says so.

## Tests

- C units: `test/test_tls_session.c` (8 cases), `test/test_tls_server.c` (8 cases).
- `test/stdlib/test_http_server.march`: builders, `scheme`, the three plugs (14 cases).
- `test/test_https_native.ml`, suite `https server (compiled, end-to-end)`, 14 groups:
  configuration errors and a bad certificate at startup; the seven deadline cases on all three
  modes; eleven HTTPS cases and five WebSocket cases (including 200 frames pushed by another
  task while the handler is in `recv`) on all three modes; rotation by polling, a refused pair
  logged once, `reload_tls` with PEM text, 100 reloads racing 200 handshakes, bootstrap mode and
  an expired certificate at startup on the event loop and the pool.
- `test_eval`: an HTTPS `listen` under the interpreter fails with "need a compiled build".
- `test_link_deps`: an HTTP server loads OpenSSL only when it serves HTTPS.
- `importer_needs_unchanged`: `HttpServer` declares only `needs IO.NetListen`.

## Sanitizers (2026-11-06)

- macOS cannot run ASAN (CrowdStrike Falcon), so both C unit tests were run in `gcc:14`
  (Debian, OpenSSL 3.5) with `-fsanitize=address,undefined` and LeakSanitizer: clean.
- The HTTPS end-to-end suite ran in an Ubuntu 24.04 container (the CI image recipe,
  OpenSSL 3.0.13, epoll) with every server compiled `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`
  (`__asan_report` call sites confirmed in the binary) and
  `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`, on the final tree: 15/15 groups green, no
  ASAN or UBSan report. LeakSanitizer was not run on the servers: the harness ends them with
  SIGKILL, so LSan's exit-time check never runs.
- That run is what caught a compiler bug: the first version of the closure `HttpServer.tls`
  builds freed the captured certificate paths before the borrowing builtin read them (a
  heap-use-after-free at startup that the macOS suite could not see). Worked around in the
  stdlib; filed as `specs/todos/2026-11-06-closure-borrowed-tail-call-uaf.md`.

## Benchmark and downstream

- `specs/benchmarks.md`, "HTTPS server and phase deadlines": plain HTTP CPU per request within
  noise of base (+2%), HTTPS keep-alive ~6 µs/request more, on a loaded macOS box. The Run 5
  Linux measurement is still owed.
- forgepm, built with this branch's compiler from a scratch copy, stops on one error that the
  merge-base compiler gives too (`bastion/0.3.1/lib/view/js.march:209: Unknown module JS`); no
  new error. Before the capability change above it also failed with `import_cap_missing` in
  three Bastion modules.

## Not done here

- The staging acceptance deploy (design "Done means", item 2: an example app serving itself on
  443 with a certbot certificate, `wss://`, and a forced renewal taking effect without a
  restart) is the owner's manual step; `examples/https_hello.march` and the recipe in
  `specs/features/http-and-networking.md` are ready for it.
