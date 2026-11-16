# HTTPS for the stdlib HTTP server — design

Status: design, approved scope 2026-11-05. Not started.
Tracking: `specs/todos/2026-11-05-https-server.md`.
Later work this unblocks: HTTP/3 over QUIC (`specs/plans/http2-http3-udp-plan.md`, Part 3), which
needs a TLS-terminating server and an `Alt-Svc` header sent over HTTPS before browsers will try it.
That plan orders Part 3 after HTTP/2 (Part 2); this design supersedes that ordering, since
`Alt-Svc` works over HTTP/1.1 on TLS and HTTP/2 is not a prerequisite for HTTP/3.

## Why

A March app should be able to sit on a public server and answer `https://` itself, with no load
balancer or reverse proxy in front. Today it can't: the runtime binds system OpenSSL and has
server-side builtins (`tls_server_ctx`, `tls_accept` in `runtime/march_tls.c`), but `HttpServer`
never calls them. Both server modes read and write the raw socket (`runtime/march_http_evloop.c`,
`connection_thread` in `runtime/march_http.c`), and so does the WebSocket handoff.

The reference user is **forgepm** (`~/code/forgepm`, served at forgepm.org), the package
registry. It runs one binary on a droplet, serves HTML plus Bastion islands over WebSockets
(`IslandSocket`, which calls `WebSocket.upgrade` / `recv` / `send_frame`; Bastion's channel
server also pushes with `send_frame` from other tasks), accepts package tarball uploads, already
sends HSTS from its own `SecurityHeaders` plug in prod, and has a Docker `HEALTHCHECK` that curls
`http://localhost:4000/health`. **Today it sits behind a Cloudflare Tunnel**: cloudflared on the
droplet forwards to `http://127.0.0.1:4040`, and `lib/forgepm/web/client_ip.march` trusts
`CF-Connecting-IP` from loopback peers for rate limiting and audit identity.

### Done means

forgepm **keeps its Cloudflare Tunnel** (owner's decision, 2026-11-06), so it is the model for
the requirements (WebSockets with cross-task pushes, large uploads, a plain health check) but
not the acceptance test. Acceptance (my call) is:

1. The HTTPS end-to-end group below passes on both server modes, plus its ASAN run.
2. A staging deploy of a small example app (`examples/https_hello.march`: a page, a large
   upload endpoint, and a `wss://` echo that also pushes from a second task) serves itself on
   443 on a public host with a Let's Encrypt certificate from `certbot --webroot` through
   `acme_webroot`, nothing in front of it. `certbot renew --force-renewal` takes effect
   without a restart (new `notAfter` visible to a fresh `openssl s_client`), while a WebSocket
   opened before the renewal stays up. Checked with curl, a browser, and `testssl.sh`; the
   results go in the progress file.

## Goals

1. HTTPS (HTTP/1.1 over TLS) on **both** server modes: the default event loop and the
   `MARCH_HTTP_EVLOOP=0` thread pool. (`MARCH_HTTP_SEQUENTIAL` rides the pool's
   `connection_thread`, so it comes along.)
2. `wss://`: WebSocket upgrades on an HTTPS connection keep working, **with no change to
   `WebSocket`'s public API or to `WsSocket`'s shape**, so Bastion and forgepm compile unchanged.
3. Certificate rotation without a restart, from two triggers:
   - **file polling**: the server re-reads the cert and key files periodically and swaps in a
     changed pair (certbot, cert-manager or a CI job rewrites the files and signals no one);
   - **`HttpServer.reload_tls`**: March code that fetched a certificate itself installs it,
     from file paths or from PEM text in memory.
4. A failed reload never takes the site down: the previous certificate keeps serving and the
   failure is reported.
5. Timeouts that actually apply: a TLS handshake deadline, and `HttpServer.idle_timeout`
   honoured by both modes (it is discarded today: `(void)idle_timeout` at
   `runtime/march_http.c:2553`; the evloop has none at all, and the pool hard-codes 10 s at
   `runtime/march_http.c:2053`).
6. A second, plain-HTTP listener in the same process, started by the same `listen` call, with
   its own plug list: for the port-80 redirect and ACME challenges, or for a local health check.
7. Two stdlib plugs: redirect to `https://`, and serve ACME HTTP-01 challenge responses.
8. A handler can tell whether its request arrived over TLS (`HttpServer.scheme(conn)`), for
   building absolute URLs and deciding secure-cookie flags.

## Non-goals

- More than one certificate per port (SNI selection). One cert chain per server.
- Client certificates (mTLS).
- HTTP/2. ALPN offers `http/1.1` only; advertising `h2` without speaking it would break clients.
- An ACME client in March. Nothing here may block one: `reload_tls` with PEM text is its hook.
- kTLS or other kernel offload.
- More than one HTTPS server per process. The server's state is already process-global
  (`g_http_shutdown`, `g_march_http_release_clo`, `march_http_bind_addr`); this keeps that model.
- `max_connections` enforcement on the event loop (separate, pre-existing gap).
- OCSP stapling.

## Anti-goals (would make this a failure even if it "works")

- **Plain HTTP gets slower.** The evloop's plain path is the measured hot path
  (`specs/benchmarks.md`, Run 5: ~76-80k req/s on 4-vCPU Linux). A TLS branch on it must not move
  that measurably.
- **A renewal can take the site down.** A half-written file, a cert for a new key whose key file
  isn't written yet, a mismatched pair: each is refused and the old pair keeps serving.
- **A silent client can hold a connection forever** during or after the handshake.
- **Bastion or forgepm need code changes** to keep working. `Conn` keeps its 13 positional fields
  (Bastion's `testing/test_conn.march` destructures `HttpServer.Conn(fd, m, …, u)`), and
  `WsSocket` stays `WsSocket(Int)`.
- **Unsafe TLS defaults** a user has to know to fix.

## Constraints from the existing code

- **Event-loop threads must never block** (comment at `march_http_evloop_enabled`,
  `runtime/march_http.c`). They are plain OS threads outside the scheduler, so `tls_drive`'s
  `march_sched_wait_fd` would degrade to a blocking `poll()` there. The evloop needs a TLS
  path that never waits.
- **The evloop is edge-triggered** (`EV_CLEAR` / `EPOLLET`). OpenSSL buffers: after `SSL_read`
  returns data, more decrypted bytes or whole records can sit inside OpenSSL with no further
  socket edge coming. Reads must drain to `WANT_READ`, never stop on "got some".
- **Responses are batched iovecs** pointing into handler-result strings and a thread-local
  scratch buffer (`march_populate_response_ka`, `evloop_defer_write`), released only after the
  bytes leave (`pending_release`). OpenSSL has no `writev`, and one `SSL_write` per small iovec
  would emit one tiny TLS record each.
- **WebSocket handoff passes a bare fd.** Evloop: `ws_handler_thread` sets the fd blocking and
  runs the closure on a new pthread. Pool: inline in `connection_thread`. `march_ws_recv`,
  `march_ws_send`, `march_ws_handshake` and `ws_select` all do raw `recv`/`send`/`poll` on
  that fd.
- **Signals are taken.** `SIGHUP` is Topology's reload (`stdlib/topology.march`), `SIGUSR1`
  the scheduler's preemption. Precedent for cert rotation by file polling is
  `ClusterNode`'s `watch_cert_files` (`stdlib/cluster_node.march:2633-2660`): poll, try each
  distinct content once, report a refusal, retry only when a file changes.
- **New builtins are expensive.** Each touches typecheck, the capability tables
  (`lib/typecheck/typecheck_builtins.ml`, `lib/caps/cap_symbols.ml`), `lib/tir/llvm_builtins.ml`,
  `defun.ml` / `borrow.ml` lists, the eval side, and the runtime. Load the `compiler-builtin`
  skill. Keep the count small.
- **`spawn_n`** (the test harness) forks a child that calls `march_http_server_listen`, so any
  configuration set before `spawn_n` must survive the fork.

## Design

### Public API (`stdlib/http_server.march`)

`Server` is built by `HttpServer.new`, never destructured outside `http_server.march`, so it may
gain fields. Proposed surface (names are the builder's to polish; shapes are the decision):

```march
type TlsSource = TlsFiles(String, String)   -- cert chain PEM path, private key PEM path
               | TlsPem(String, String)     -- cert chain PEM text, private key PEM text

HttpServer.new(443)
|> HttpServer.tls(TlsFiles("/etc/letsencrypt/live/forge.pm/fullchain.pem",
                           "/etc/letsencrypt/live/forge.pm/privkey.pem"))
|> HttpServer.plain_listener(80, [HttpServer.acme_webroot("/var/www/acme"),
                                  HttpServer.redirect_to_https(443)])
|> HttpServer.plug(app)
|> HttpServer.listen()
```

- `tls(server, source)`: serve this server's port over TLS. Optional knobs, each with a default:
  `tls_handshake_timeout(server, secs)` (default 10), `tls_poll_interval(server, secs)`
  (default 60; 0 disables polling; polling only applies to `TlsFiles`).
- `plain_listener(server, port, plugs)`: one extra plain-HTTP port, own pipeline. One extra
  listener is enough for the goals; a list is fine if it costs nothing more.
- `reload_tls(source) : Result((), String)`: callable from any task while `listen` runs.
  Builds a new context; on success swaps it in and returns `Ok(())`; on failure returns
  `Err(reason)` and changes nothing. `Err` if no TLS server is running.
- `scheme(conn) : String`: `"https"` or `"http"`. Works on any `Conn`, including ones Bastion's
  test helpers build (unknown fd → `"http"`).
- `redirect_to_https(port) : Conn -> Conn`: responds 301 to
  `https://<Host without port>[:port unless 443]<path>[?query]`; 400 if there is no `Host`.
  Leaves requests under `/.well-known/acme-challenge/` alone so it composes after the ACME plug
  in either order. GET/HEAD get 301; other methods 308.
- `acme_webroot(dir) : Conn -> Conn`: for `GET /.well-known/acme-challenge/<token>` serves
  `<dir>/.well-known/acme-challenge/<token>` as `text/plain` (the layout certbot's `--webroot`
  writes). Tokens are restricted to the base64url alphabet; anything else is 404, never a path
  traversal. Also `acme_responder(lookup : String -> Option(String))` for code that keeps
  challenges in memory.
- `listen` with an invalid TLS configuration (missing file, unreadable key, mismatched pair)
  fails fast: a clear one-line message and a nonzero exit, before binding anything. An expired
  certificate at startup is a warning, not a failure: serving an expired cert beats serving
  nothing, and the poller will pick up the renewal.
- **First issuance (my call):** fail-fast makes the very first certificate impossible to obtain
  through this binary's own `acme_webroot` plug (no cert → no `listen` → no challenge answers).
  `tls_wait_for_cert(server)` opts into a bootstrap mode: if the `TlsFiles` are *missing* (not
  invalid), `listen` starts the plain listener and the poller but does not bind the TLS port;
  the first valid pair the poller or `reload_tls` installs binds it. Without the opt-in, missing
  files fail fast as above. The deployment recipe documents both routes (`certbot --standalone`
  before first start, or bootstrap mode with `--webroot`).

Capabilities (revised during implementation, 2026-11-06; the first draft required
`IO.NetConnect.TLS` too): serving HTTPS and `reload_tls` need `IO.NetListen`. Capabilities are
checked by reachability from `main`, and `listen` reaches the TLS configuration on every server,
plain ones included; and a module that imports `HttpServer` must declare every module-level
`needs` `HttpServer` has (`import_cap_missing`), which Bastion and forgepm do not, so
`HttpServer` keeps `needs IO.NetListen` alone. The file-reading ACME plug is therefore
`HttpAcme.webroot` in a module of its own (`needs IO.FileRead`). `scheme` needs nothing.

**Interpreter (my call).** `forge run` uses the interpreter, whose HTTP server is a separate
OCaml implementation (`lib/eval/eval_builtins.ml`) with stub TLS builtins. It must never
silently serve plain HTTP for a TLS configuration: `tls(...)` under the interpreter makes
`listen` fail with a message saying HTTPS needs a compiled build. `scheme` returns `"http"`.
`plain_listener` and an enforced `idle_timeout` are implemented in the interpreter if cheap;
otherwise `plain_listener` fails the same loud way and `idle_timeout` stays advisory there
(documented).

### Runtime builtins (my call: configure-then-listen, like `bind_host`)

Rather than widening `http_server_listen`'s signature, configuration is set into the runtime's
existing process-global server state before `listen`, the same pattern as `http_server_bind_host`.
This keeps `spawn_n` working unchanged (the child inherits the configuration across `fork`).
Four new builtins:

| Builtin | Does |
|---|---|
| `http_server_tls_configure(kind, a, b, handshake_secs, poll_secs) : Result((), String)` | Build and validate the context now; store it and the polling parameters. |
| `http_server_reload_tls(kind, a, b) : Result((), String)` | Build a context; swap it in on success. |
| `http_server_plain_listener(port, pipeline) : ()` | Register the extra plain listener and its pipeline closure. |
| `http_conn_is_tls(fd) : Bool` | Registry lookup (below). |

`kind` selects files vs PEM text. `HttpServer.listen` calls the configure builtins, then the
existing `http_server_listen`.

### TLS session: one abstraction, memory BIOs (my call)

A small runtime type, `march_tls_session_t` (new file, e.g. `runtime/march_tls_server.c`, added
to `runtime/sources.list` in the http link group), wraps one `SSL *` bound to **memory BIOs**
rather than to the socket:

- `feed(ciphertext, n)` — bytes the caller read from the socket go in;
- `read(plain_buf, cap)` — decrypted bytes out; reports "need more input" when drained;
- `write(plain, n)` — plaintext in; always succeeds into the outgoing BIO;
- `pending_out()` / `consume_out(n)` — ciphertext the caller must send;
- `handshake()` — advance; reports done / need input / failed.

Every caller keeps doing its own socket I/O, so the event loop's non-blocking `recv`/`writev`
machinery, the pool's blocking reads, and the WebSocket thread all drive the same object.
Consequences:

- `WANT_WRITE` never happens with a memory BIO; "want read" just means "feed me more". The
  evloop's state machine stays read-armed / write-armed as today.
- Plaintext is copied into ciphertext by `write`, so handler results can be released as soon as
  they are encrypted, not after the socket drains. The TLS path does not need `pending_release`
  or the scratch snapshot.
- Responses coalesce naturally: iterate the batch's iovecs into `write`, OpenSSL emits
  full-size records. (Builder: check the record size behaviour; a per-connection plaintext
  staging buffer of ~16 KiB in front of `SSL_write` is the fallback if OpenSSL emits one record
  per call.)
- Cost: one extra copy of ciphertext through the BIO. Small next to the encryption itself.
- kTLS later would need a socket BIO instead. It is a non-goal; noted so the choice is
  deliberate.

The rejected alternative is `SSL_set_fd` on the non-blocking socket, mapping `WANT_READ` /
`WANT_WRITE` to `arm_read` / `arm_write`. It works for the evloop but makes the WebSocket
handoff and the pool each need their own OpenSSL driving loop, and `SSL_write`'s retry rule
(same buffer, or `SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER`) collides with the deferred-iovec path.

### Context and rotation

- One server `SSL_CTX` at a time, held in a process-global slot behind a mutex. A new
  connection takes the lock, `SSL_CTX_up_ref`s the current context, unlocks, `SSL_new`s from it,
  and drops its extra ref. Reload builds a new context entirely outside the lock, then swaps the
  pointer and drops the slot's ref on the old one. OpenSSL's own refcounting frees the old
  context when its last connection closes. Existing connections are never touched.
- **More than one consumer (my call, for HTTP/3).** A QUIC stack (ngtcp2 or similar) needs its
  own TLS context built from the same certificate. So the slot also keeps the validated cert
  chain and key as PEM, and a reload notifies a small list of registered consumers ("here is a
  new validated pair, build yours"). This design registers one consumer, the TCP server; HTTP/3
  adds its own without touching rotation.
- Context construction: refactor `march_tls_server_ctx`'s body into a C helper returning
  `SSL_CTX *` or an error string, used by the existing builtin and by the new ones. Fix the
  existing leak on the way: the ALPN callback's argument (`malloc`ed at
  `runtime/march_tls.c:296`) is never freed with its context, which would leak once per reload.
  Free it with the context (e.g. `SSL_CTX` ex_data with a free callback). Add the
  PEM-text variant (`BIO_new_mem_buf`, first cert via `SSL_CTX_use_certificate`, the rest of the
  chain via `SSL_CTX_add1_chain_cert`, key via `PEM_read_bio_PrivateKey`), then
  `SSL_CTX_check_private_key`.
- Reload refuses: unparsable PEM, key/cert mismatch, a leaf whose `notAfter` is already past.
  Refusal leaves the slot untouched.
- **Polling** (only for `TlsFiles`, only when `poll_secs > 0`): one runtime pthread started by
  `listen`. Every `poll_secs` it reads both files (following symlinks: certbot's `live/` names
  are symlinks into `archive/`), hashes the concatenated contents, and if the hash differs from
  the last one **tried**, tries a reload. Each distinct content is tried once: a refusal is
  logged to stderr with the reason and not retried until a file changes again (a cert written
  before its key settles on the next poll). Success is logged too, one line, with the new
  leaf's `notAfter`.
- `reload_tls` from March and the poller go through the same function. Last writer wins.

### TLS settings

- Minimum TLS 1.2; OpenSSL's default cipher suites; the existing post-quantum-first group list
  (`ctx_set_default_groups`).
- ALPN: `http/1.1` only, via the existing server callback.
- `SSL_OP_NO_RENEGOTIATION`. No 0-RTT (OpenSSL's default `max_early_data` of 0; don't change it).
- Session resumption: OpenSSL's server defaults (session cache plus TLS 1.3 tickets). One shared
  context across evloop threads means a client resumes on any thread. A rotation changes ticket
  keys, so the next connection after a rotation does a full handshake; acceptable.

### fd → session registry

A process-global table mapping a socket fd to its `march_tls_session_t *` (fds are small dense
integers: a growable array guarded by a lock, or sharded; the builder's call). Entries are added
right after accept on a TLS listener and **removed before `close(fd)`**, so a reused fd never
inherits a stale session. It serves:

- `http_conn_is_tls(fd)` → `HttpServer.scheme`;
- the WebSocket functions: `march_ws_handshake`, `march_ws_recv`, `march_ws_send` and
  `ws_select` look up the fd and go through the session when there is one, raw socket
  otherwise. `ws_select` must report "readable" when the session already holds decrypted bytes
  or undecrypted ciphertext, not only when `poll()` says the socket is readable.
- **Concurrent send while another thread reads.** Bastion's channel server pushes with
  `WebSocket.send_frame` from other tasks while the socket's handler is blocked in `recv`. An
  `SSL *` must not be used by two threads at once, so each session has a lock held **only around
  OpenSSL calls, never across a socket wait**: the reader waits on the socket unlocked, then
  locks to `feed` + `read`. Writers also take a per-session send lock, held from encrypting a
  frame until its ciphertext is fully sent, so frames from two senders never interleave on the
  wire. Lock order: send lock, then session lock.

### Event loop changes (`runtime/march_http_evloop.c`, `march_http_io.c`)

- Each thread owns one `SO_REUSEPORT` listener **per configured port** (main, plus the plain
  listener if set). The listener an fd came from decides its pipeline and whether it is TLS;
  `conn_state_t` gains `pipeline` and `tls` (session pointer, NULL for plain).
- **Plain connections take exactly today's code path.** The TLS branch sits at the I/O edges:
  - read: `recv` ciphertext into a small per-connection buffer, `feed`, then `read` plaintext
    into `c->rbuf` until drained, then parse as today. Before the handshake completes, drive
    `handshake()` instead and send whatever `pending_out` holds;
  - write: run the batch iovecs through the session, then send `pending_out` with the
    existing non-blocking send and deferred-write path (the deferred buffer now holds owned
    ciphertext, not iovecs into handler results);
  - close: best-effort `close_notify` (one non-blocking send attempt), remove the registry entry,
    free the session, close the fd;
  - WebSocket upgrade: send the 101 through the session, then hand the fd to
    `ws_handler_thread` as today. The session stays in the registry, so the thread's
    `ws_recv`/`ws_send` encrypt. Any plaintext already sitting in `c->rbuf` after the upgrade
    request, or ciphertext not yet decrypted, must be carried to the WS thread, not dropped.
    Carrying it in the session's buffers is enough if the registry is how the thread reads.
- **Timers (my call).** Each connection has one absolute deadline, set by its phase. The phases
  have different lengths, so a single move-to-tail list does not stay sorted: use a per-thread
  min-heap (or one list per phase length). On every loop wake (the `kevent` / `epoll_wait`
  timeout is already 1 s), close connections whose deadline has passed. Phases:

  | Phase | Deadline | Resets on |
  |---|---|---|
  | accept → handshake done (TLS only) | `tls_handshake_timeout` (10 s) | nothing |
  | waiting for the next request to start (after accept / handshake / last response) | `idle_timeout` (60 s) | nothing |
  | request line + headers arriving | `header_timeout` (new knob, 30 s) from the first byte | nothing, so a client dribbling headers (slowloris) is cut off |
  | body arriving | 30 s without progress | each read that adds body bytes |
  | response being written | 30 s without progress | each write that sends bytes |

  So a slow but moving tarball upload or download is never cut off, and a stalled one is,
  within 30 s. The 30 s progress window is a fixed default; making it a knob is the builder's
  call. Plain connections get the same deadlines (goal 5, and a behaviour change worth a
  CHANGELOG line). WebSocket connections leave the timer at handoff.

### Thread-pool changes (`connection_thread`, `runtime/march_http.c`)

- The accept loop `select`s over the main and the plain listener.
- A TLS connection does its handshake with the session on the worker thread, then the request
  loop reads ciphertext, feeds, reads plaintext into its buffer, and writes responses through the
  session.
- **Deadlines, not `SO_RCVTIMEO`.** `SO_RCVTIMEO` resets on every `recv`, so it cannot enforce
  the header deadline, and on a scheduler green thread (`MARCH_HTTP_SEQUENTIAL`) the preemption
  signal restarts the read and its timer. Every socket wait in `connection_thread` goes through
  `march_sched_wait_fd(fd, want_write, absolute_deadline_ms)` instead, with the same phase
  deadlines as the evloop. Off a green thread (pool workers) that call is a `poll()`; on one
  (sequential mode) it parks. Remove the hard-coded 10 s `SO_RCVTIMEO` and the step that clears
  it at WebSocket handoff.
- WebSocket upgrade: as in the evloop, through the registry.

### Plugs and helpers in March

`redirect_to_https`, `acme_webroot`, `acme_responder` and `scheme` are ordinary stdlib functions
over existing `Conn` accessors plus `http_conn_is_tls`. `acme_webroot` reads files with
`File.read`, so a server using it needs file-read capability; document that.

## Testing

- **Unit (March, `test/stdlib/test_http_server.march`):** `redirect_to_https` (host with and
  without port, query preserved, missing Host → 400, ACME paths untouched, 301 vs 308),
  `acme_webroot` token validation and traversal attempts, `scheme` on a hand-built `Conn`.
- **End to end (compiled server, `test/test_http_native.ml`, which rides `run_stdlib`):** add an
  HTTPS group. Certificates are generated at test time with the `openssl` CLI into a temp dir
  (no committed private keys, no fixture that expires). A client: `HttpClient` over `Tls` with
  `ca_file` set to the test CA, or `openssl s_client` driven from OCaml; the builder's call.
  Cases, on **both** server modes:
  - GET over HTTPS, keep-alive with several sequential requests, pipelined requests, and a body
    larger than one TLS record and larger than 64 KiB (the old evloop stall size);
  - a WebSocket echo over `wss://`, including a frame larger than one record, and an idle WS
    connection that outlives `idle_timeout` (it must not be cut);
  - concurrent push: one task blocked in `WebSocket.recv` while another sends frames on the same
    socket; every pushed frame arrives intact and promptly (run under TSAN or ASAN as well);
  - handshake timeout: connect, send nothing, server closes within the deadline;
  - idle timeout on plain and TLS, and the slowloris case (headers dribbled one byte per
    second);
  - a slow but moving upload and a slow-reading download, each lasting longer than
    `idle_timeout`: both complete; the same two stalled: both are cut within the progress
    window;
  - bootstrap mode: start with the cert files missing, plain listener answers, write the files,
    TLS port comes up;
  - rotation by polling: replace the files with a pair from a different CA, observe new
    connections get the new leaf while a connection opened before still works;
  - rotation refusal: write a mismatched pair, old cert keeps serving, stderr names the
    reason; then fix the key file and see it picked up;
  - `reload_tls` with `TlsPem`, success and refusal;
  - the plain listener serving its own pipeline beside the TLS port;
  - startup failure on a missing key file exits nonzero before binding.
- **Leaks and races:** run the HTTPS e2e group under ASAN (`march-debug` skill) and check RSS
  across a sustained run as the existing HTTP leak checks do. Sessions, contexts and registry
  entries must all be freed.
- **Interop smoke (manual, record the result in the progress file):** `curl -v https://`,
  a browser, and `testssl.sh` or SSL Labs against a staging deploy, to confirm protocol
  versions, ALPN and the chain.

## Performance

- Plain HTTP on the evloop: run the Linux `wrk -c256` comparison from `specs/benchmarks.md`
  (Run 5 method, quiet box, order-swapped) before and after. Must be within noise.
- HTTPS: measure and record req/s and CPU-µs/request for handshake-heavy (new connection per
  request) and keep-alive loads. No target in this design; the numbers go in the progress file
  and `specs/benchmarks.md`.

## Rollout and docs

- `CHANGELOG.md` under `[Unreleased]`: Added (HTTPS server, `wss://`, cert rotation, the two
  plugs, `scheme`); Changed (`idle_timeout` is now enforced on both modes; the pool's default
  idle cut-off moves from a hard-coded 10 s to the configured value, 60 s by default).
- Stdlib reference: it is generated from `doc` strings, so every new public function gets a
  `doc` string with an example, and doctests where they can run without a network
  (`march-docs` skill). `specs/lang/` has no HttpServer chapter (`standard-library.md` only
  lists the module); no `specs/lang/` edit is needed unless one is added.
- A deployment recipe: certbot with `--webroot` pointed at the `acme_webroot` directory, the
  poll interval, Docker volume mounts for `/etc/letsencrypt` (mount the whole directory: `live/`
  holds symlinks into `archive/`), and binding 443/80 (root, `CAP_NET_BIND_SERVICE`, or Docker
  port mapping).
- No forgepm change: it keeps the Cloudflare Tunnel and plain HTTP on loopback. (If it ever
  drops the tunnel, its `ClientIp` must stop trusting `CF-Connecting-IP` and use the socket
  peer; recorded here so that isn't forgotten.)

## Left to the builder

- Final names of the new API functions and builtins.
- Registry data structure; the size of the per-connection ciphertext buffer.
- Whether the plain listener is one listener or a list.
- The HTTPS e2e client (`HttpClient`+`Tls` or `openssl s_client`).
- Exact log wording, as long as each line names the server, the file(s), and the reason.
