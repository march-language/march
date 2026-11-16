# HTTPS for the stdlib HTTP server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `HttpServer` serves HTTP/1.1 over TLS on both server modes, with `wss://`, certificate rotation without a restart, per-phase timeouts, an extra plain listener, and redirect/ACME plugs.

**Architecture:** A pure-C TLS session over OpenSSL memory BIOs (`march_tls_session.c`) is driven by each server mode's own socket I/O. A pure-C server module (`march_tls_server.c`) owns the one live `SSL_CTX` slot, rotation, the file poller and the fd→session registry. A March-facing glue file (`march_https.c`) holds five new builtins and the process-global HTTPS config, which `HttpServer.listen` sets before calling the existing `http_server_listen`.

**Tech Stack:** C11 + OpenSSL 3.x (system, already linked: `-lssl -lcrypto`), pthreads, kqueue/epoll; March stdlib; OCaml/Alcotest e2e harness; `openssl` CLI in tests.

**Spec:** `specs/2026-11-05-https-server-design.md` (read it first; this plan argues from it).

## Global Constraints

- Build from the worktree with `--root .`. "BUILD" below means:
  `dune build --root . bin/main.exe test/run_stdlib.exe test/native_native_arr_fold_boundary_box_probe`
  (the last target depends on `(source_tree ../runtime)` and restages the runtime the driver compiles; a bare `bin/main.exe` build does NOT pick up `runtime/*.c` edits). After a runtime edit, confirm `grep -c <a new symbol> _build/default/runtime/<file>.c` is nonzero before trusting any result.
- E2E run command: `./_build/default/test/run_stdlib.exe test 'https server' -e` (new suite); existing: `... test 'http server' -e`.
- Defaults, verbatim from the spec: handshake **10 s**, idle **60 s**, header **30 s** from first byte, body/write progress **30 s** without progress, poll **60 s** (0 disables).
- TLS: minimum **TLS 1.2**; OpenSSL default ciphers; existing PQ-first group list (`ctx_set_default_groups`); ALPN exactly **`http/1.1`**; `SSL_OP_NO_RENEGOTIATION`; never enable early data.
- `HttpServer.Conn` keeps its **13 positional fields**; `WsSocket` stays **`WsSocket(Int)`**; `WebSocket`'s public API is unchanged.
- Plain connections on the event loop take today's code path; the TLS branch lives only at the I/O edges.
- Every new `runtime/*.c` gets one `runtime/sources.list` line with role `http`, jit `-`, and the link lists in `bin/main.ml`, `bin/toolchain.ml`, `test/test_helpers.ml` agree (`scripts/check-runtime-sources.sh` must pass).
- New builtins follow the `compiler-builtin` skill and mirror every site where `http_server_bind_host` appears (`grep -rn '"http_server_bind_host"' lib/`), plus `march_http.h` declarations. Bool-returning builtins mirror `tls_pq_available` (`ret_ty = Some Tir.TBool`, C returns `int64_t`).
- Capabilities (the cap tables map one builtin to one capability): `http_server_tls_configure`, `http_server_reload_tls` → `IO.NetConnect.TLS` (the `tls_server_ctx` precedent); `http_server_plain_listener`, `http_server_set_timeouts` → `IO.NetListen`; `http_conn_is_tls` → none. An HTTPS `listen` therefore needs `IO.NetListen` + `IO.NetConnect.TLS`, as the spec requires.
- Stage files by name (never `git add -A`/`.`); no `Co-Authored-By`. The feature is not usable until Task 10, so the `CHANGELOG.md` bullets, the `specs/progress/` entry and the todo move land together in Task 11.
- Never skip, disable or quarantine a test to get green.

## Review Focus

1. **Plain HTTP sent to the TLS port** (a browser typing `http://host:443`): the connection is closed quietly, the server stays up, the next TLS request works. Test in Task 7.
2. **No SNI** (`curl https://127.0.0.1`, `s_client` without `-servername`): the single cert is served anyway. Test in Task 7.
3. **TLS response bigger than the socket send buffer to a slow reader** (pipelined 1 MiB responses): the deferred-write path carries ciphertext correctly, nothing truncated or reordered. Test in Task 7.
4. **fd reuse**: an fd that was a TLS connection, closed, then reused by a plain connection must read as plain (`scheme` = `"http"`, raw I/O). Test in Task 7.
5. **Reload racing handshakes**: `reload_tls` called in a loop from a task while 200 clients handshake; every handshake succeeds with one of the two certs, no crash, no leak under ASAN. Test in Task 10.

---

## File Structure

| File | Responsibility |
|---|---|
| `runtime/march_tls_session.{c,h}` (new) | One server-side `SSL *` on memory BIOs: feed / read / write / take ciphertext / handshake / shutdown, plus its two mutexes. No March heap, no sockets. |
| `runtime/march_tls_server.{c,h}` (new) | Build an `SSL_CTX` from PEM; the process-global slot (swap, acquire, generation, consumers); reading the file pair; the poller; the fd→session registry. No March heap. |
| `runtime/march_https.{c,h}` (new) | `g_march_https` config; the five builtins; startup validation messages. Uses the March heap (`Result` objects). |
| `runtime/march_tls.c` | Free the ALPN callback buffer with its context. |
| `runtime/march_http_evloop.c`, `march_http_io.{c,h}` | Per-port listeners, per-connection deadlines, TLS I/O edges, WS handoff with session. |
| `runtime/march_http.c` | Pool/sequential deadlines via `march_sched_wait_fd`, pool TLS, second listener in the accept loop, WS functions through the registry. |
| `stdlib/http_server.march` | `TlsSource`, config builders, `reload_tls`, `scheme`, the three plugs, `listen` wiring. |
| `lib/**` builtin sites, `lib/eval/eval_builtins.ml` | Five builtins; interpreter behaviour. |
| `test/test_tls_session.c`, `test/test_tls_server.c` (new) + `test/dune` rules | C unit tests, linked against OpenSSL via `pkg-config openssl`. |
| `test/test_https_native.ml` (new) | HTTPS e2e suite `"https server (compiled, end-to-end)"`; reuses `Test_http_native.with_compiled_server`. Registered in `test/dune` modules (line 37) and `test/run_stdlib.ml`. |
| `test/stdlib/test_http_server.march` | Unit tests for `scheme` and the plugs. |
| `examples/https_hello.march`, `specs/features/http-and-networking.md`, `CHANGELOG.md`, `specs/benchmarks.md`, `specs/progress/` | Task 11. |

---

### Task 1: TLS session over memory BIOs

**Files:**
- Create: `runtime/march_tls_session.h`, `runtime/march_tls_session.c`
- Create: `test/test_tls_session.c`; Modify: `test/dune` (rule + `runtest` alias, modelled on `test_http_simd_runner` at `test/dune:1175-1185`, compile flags from `pkg-config --cflags --libs openssl`)
- Modify: `runtime/sources.list`, `bin/main.ml`, `bin/toolchain.ml`, `test/test_helpers.ml` (link lists)

**Interfaces — Produces** (`march_tls_session.h`):
```c
typedef struct march_tls_session march_tls_session_t;
typedef enum { MTS_DONE = 0, MTS_NEED_INPUT = 1, MTS_EOF = 2, MTS_FAIL = -1 } mts_rc;
march_tls_session_t *mts_new_server(SSL_CTX *ctx);          /* NULL on failure */
void   mts_free(march_tls_session_t *s);
int    mts_feed(march_tls_session_t *s, const void *buf, size_t n);   /* 0 ok, -1 fail */
mts_rc mts_handshake(march_tls_session_t *s);                /* DONE once established */
int    mts_is_established(const march_tls_session_t *s);
mts_rc mts_read(march_tls_session_t *s, void *out, size_t cap, size_t *got);
int    mts_write(march_tls_session_t *s, const void *buf, size_t n);  /* whole buffer or -1 */
size_t mts_out_len(march_tls_session_t *s);                  /* ciphertext waiting */
size_t mts_take_out(march_tls_session_t *s, void *buf, size_t cap);
int    mts_has_input(march_tls_session_t *s);                /* buffered plaintext or ciphertext */
void   mts_shutdown(march_tls_session_t *s);                 /* queue close_notify */
const char *mts_error(const march_tls_session_t *s);         /* last failure text */
void mts_lock(march_tls_session_t *s);  void mts_unlock(march_tls_session_t *s);
void mts_send_lock(march_tls_session_t *s); void mts_send_unlock(march_tls_session_t *s);
```
Functions never lock internally; callers that share a session across threads take `mts_lock` around calls (Task 9).

- [ ] **Step 1: Write the failing tests** in `test/test_tls_session.c`. A `main` that builds an in-memory self-signed EC cert (`EVP_EC_gen("P-256")`, `X509_sign`), a server `SSL_CTX` with ALPN `http/1.1`, and a client `SSL` on its own memory BIOs; a `pump()` helper that moves `mts_take_out` bytes to the client rbio and client wbio bytes to `mts_feed`. Cases (each prints `ok <name>` / exits 1 with the name):
  - `handshake_completes`: pump until `mts_handshake == MTS_DONE` within 10 rounds; client `SSL_get0_alpn_selected` == `"http/1.1"`.
  - `roundtrip_100k`: client writes 100 000 bytes of a repeating pattern; server `mts_read` loop until `MTS_NEED_INPUT` returns exactly those bytes; server `mts_write` 100 000 bytes back, client reads them all.
  - `one_byte_feeds`: same handshake but every `mts_feed` is 1 byte; still completes.
  - `drain_reports_need_input`: after all data is read, `mts_read` returns `MTS_NEED_INPUT` and `mts_has_input` is 0.
  - `has_input_with_buffered`: feed two records, read 10 bytes, `mts_has_input` is 1.
  - `close_notify_is_eof`: client `SSL_shutdown`, pump, `mts_read` returns `MTS_EOF`.
  - `garbage_fails`: fresh session, feed `"GET / HTTP/1.1\r\n\r\n"`, `mts_handshake` returns `MTS_FAIL`, `mts_error` non-empty.
  - `shutdown_queues_close_notify`: `mts_shutdown` then `mts_out_len > 0`; client sees `SSL_ERROR_ZERO_RETURN` after pumping.
- [ ] **Step 2: Run, expect FAIL** (link error: `mts_*` undefined). Run: `dune build --root . @test/runtest 2>&1 | grep -A3 test_tls_session` — or run the target rule directly.
- [ ] **Step 3: Implement** `march_tls_session.c`: `BIO_s_mem()` pair via `SSL_set_bio`, `SSL_set_accept_state`; `mts_read` loops `SSL_read_ex` and maps `SSL_ERROR_WANT_READ`→`MTS_NEED_INPUT`, `SSL_ERROR_ZERO_RETURN`→`MTS_EOF`; `mts_has_input` = `SSL_pending(ssl) > 0 || BIO_ctrl_pending(rbio) > 0`; `mts_error` copies `ERR_error_string_n` into an inline buffer. Add the `sources.list` line and the three link-list entries.
- [ ] **Step 4: Run, expect all `ok`**; also `scripts/check-runtime-sources.sh` exits 0.
- [ ] **Step 5: Commit** `runtime/march_tls_session.{c,h} test/test_tls_session.c test/dune runtime/sources.list bin/main.ml bin/toolchain.ml test/test_helpers.ml` — `runtime: TLS session over memory BIOs for the HTTPS server`.

### Task 2: Server context slot, rotation, poller, fd registry

**Files:**
- Create: `runtime/march_tls_server.h`, `runtime/march_tls_server.c`, `test/test_tls_server.c`; Modify: `test/dune`, `runtime/sources.list` + link lists
- Modify: `runtime/march_tls.c:289-303` (ALPN buffer leak)

**Interfaces — Consumes:** Task 1's `march_tls_session_t` (registry stores pointers only).
**Produces** (`march_tls_server.h`):
```c
int  mts_ctx_from_pem(const char *cert, size_t cert_len, const char *key, size_t key_len,
                      int allow_expired, SSL_CTX **out, char *err, size_t errlen); /* 0 ok */
int  mts_slot_install_pem(const char *cert, size_t cert_len, const char *key, size_t key_len,
                          int allow_expired, char *err, size_t errlen);           /* 0 ok */
SSL_CTX *mts_slot_acquire(void);          /* +1 ref or NULL; release with SSL_CTX_free */
uint64_t mts_slot_generation(void);       /* bumps on each successful install */
typedef void (*mts_consumer_fn)(const char *cert, size_t cert_len,
                                const char *key, size_t key_len, void *arg);
void mts_slot_add_consumer(mts_consumer_fn fn, void *arg);   /* called after each install */
typedef enum { MTS_POLL_UNCHANGED, MTS_POLL_INSTALLED, MTS_POLL_REFUSED, MTS_POLL_MISSING } mts_poll_rc;
void mts_poller_set_paths(const char *cert_path, const char *key_path);
mts_poll_rc mts_poll_once(char *err, size_t errlen);  /* one poll step, logs to stderr */
int  mts_poller_start(int poll_secs);                  /* detached pthread; 0 ok */
void mts_registry_put(int fd, march_tls_session_t *s);
march_tls_session_t *mts_registry_get(int fd);
march_tls_session_t *mts_registry_take(int fd);        /* remove and return */
```
Context settings: TLS 1.2 min, ALPN `http/1.1` from a static buffer (no allocation), `SSL_OP_NO_RENEGOTIATION`, `ctx_set_default_groups` equivalent (`MARCH_TLS_PQ_GROUPS` with fallback). PEM text: first cert `SSL_CTX_use_certificate`, rest `SSL_CTX_add1_chain_cert`, key `PEM_read_bio_PrivateKey`, then `SSL_CTX_check_private_key`; when `!allow_expired`, refuse if `X509_cmp_current_time(X509_get0_notAfter(leaf)) < 0` with an error containing `"expired"`. Poller: reads both files (following symlinks), SHA-256 of `cert || 0x00 || key`, skips if equal to the last hash *tried*; logs `march: https: installed certificate <cert_path> (notAfter <date>)` or `march: https: refused certificate <cert_path>: <reason>`.

- [ ] **Step 1: Failing tests** in `test/test_tls_server.c` (in-memory PEMs written with `PEM_write_bio_*`; temp files under `mkdtemp`):
  - `install_ok`: install pair A → 0, `mts_slot_generation()==1`, `mts_slot_acquire()` non-NULL.
  - `mismatch_refused_old_kept`: install A, then cert A + key B → nonzero, `err` non-empty, generation still 1, acquired ctx's cert is A's (compare `X509_cmp`).
  - `expired_refused_on_reload`: cert with notAfter yesterday, `allow_expired=0` → nonzero, `strstr(err,"expired")`; with `allow_expired=1` → 0.
  - `garbage_pem_refused`: `"not a cert"` → nonzero.
  - `consumer_notified`: add a consumer, install B → consumer called once with B's exact PEM bytes.
  - `old_ctx_survives_swap`: acquire ctx A (+1), install B, `SSL_new(ctxA)` still works, then `SSL_CTX_free`.
  - `poll_sequence`: paths → files with pair A: `MTS_POLL_INSTALLED`; again: `MTS_POLL_UNCHANGED`; overwrite key with B (mismatch): `MTS_POLL_REFUSED`; again unchanged content: `MTS_POLL_UNCHANGED` (tried once); write key A2 matching new cert: `MTS_POLL_INSTALLED`; delete files: `MTS_POLL_MISSING`, generation unchanged.
  - `registry`: put(7,s), get(7)==s, take(7)==s, get(7)==NULL; put on fd 70000 grows.
- [ ] **Step 2: Run, expect link FAIL.**
- [ ] **Step 3: Implement** `march_tls_server.c` per the interface; slot = `{SSL_CTX *ctx; char *cert, *key; size_t lens; uint64_t gen}` under one `pthread_mutex_t`, build outside the lock, swap inside, `SSL_CTX_free` the old pointer after unlocking; consumers called after unlock. Registry: growable `march_tls_session_t **` indexed by fd under a mutex. In `march_tls.c`, free the ALPN `stored` buffer with its context: `SSL_CTX_get_ex_new_index` with a free callback, set via `SSL_CTX_set_ex_data`.
- [ ] **Step 4: Run, expect all `ok`; `scripts/check-runtime-sources.sh` exits 0;** existing TLS client suite still green: `./_build/default/test/run_stdlib.exe test tls -e`.
- [ ] **Step 5: Commit** — `runtime: server TLS context slot, rotation, poller and fd registry`.

### Task 3: Builtins, config API, interpreter behaviour

**Files:**
- Create: `runtime/march_https.{c,h}` (+ `sources.list`, link lists)
- Modify: every `http_server_bind_host` site in `lib/` (typecheck type + cap, `cap_infer.ml`, `cap_symbols.ml`, `llvm_builtins.ml` entry + `PDeclare`, `defun.ml`, `borrow.ml`), `runtime/march_http.h`, `lib/eval/eval_builtins.ml`
- Modify: `stdlib/http_server.march`
- Create: `test/test_https_native.ml` (suite skeleton + config cases); Modify: `test/dune:37`, `test/run_stdlib.ml:8-9`

**Interfaces — Consumes:** Task 2's `mts_ctx_from_pem`, `mts_slot_install_pem`, `mts_poller_set_paths`.
**Produces:**
- C (`march_https.h`):
  ```c
  typedef struct { int tls; int handshake_secs, header_secs, progress_secs, idle_secs;
                   int poll_secs, wait_for_cert; int plain_port; void *plain_pipeline; } march_https_config_t;
  extern march_https_config_t g_march_https;  /* defaults: 0,10,30,30,60,60,0,0,NULL */
  void *march_http_server_tls_configure(int64_t kind, void *a, void *b, int64_t poll_secs, int64_t wait_for_cert); /* Result(Int,String) */
  void  march_http_server_set_timeouts(int64_t handshake_secs, int64_t header_secs, int64_t progress_secs);
  void *march_http_server_reload_tls(int64_t kind, void *a, void *b);   /* Result(Int,String) */
  void  march_http_server_plain_listener(int64_t port, void *pipeline);
  int64_t march_http_conn_is_tls(int64_t fd);                          /* Bool */
  ```
  `kind`: 0 = files (`a`,`b` paths), 1 = PEM text. Configure with files: read the pair; missing files and `wait_for_cert` → `Ok`, `tls=1`, slot empty; otherwise install with `allow_expired=1` (print `march: https: warning: certificate <path> expired <date>` when expired). Reload: `Err("reload_tls: no TLS server is configured")` when `tls==0`; otherwise install with `allow_expired=0`. `march_http_server_listen` copies its `idle_timeout` into `g_march_https.idle_secs`.
- March builtins: `http_server_tls_configure : Int -> String -> String -> Int -> Int -> Result(Int, String)`, `http_server_set_timeouts : Int -> Int -> Int -> Unit`, `http_server_reload_tls : Int -> String -> String -> Result(Int, String)`, `http_server_plain_listener : Int -> (Conn -> Conn) -> Unit` (poly like `http_server_listen`'s closure arg), `http_conn_is_tls : Int -> Bool`.
- Stdlib (`HttpServer`): `type TlsSource = TlsFiles(String, String) | TlsPem(String, String)`; `tls(server, src)`, `tls_handshake_timeout(server, secs)`, `tls_poll_interval(server, secs)`, `tls_wait_for_cert(server)`, `header_timeout(server, secs)`, `progress_timeout(server, secs)`, `plain_listener(server, port, plugs)` (each `-> Server`), `reload_tls(src) : Result((), String)`, `scheme(conn) : String` (`"https"` iff `http_conn_is_tls(fd)`). `Server` gains one options field (a record or ADT; builder's choice) holding these with the spec defaults. `listen`/`spawn_n`: if TLS set, call configure — on `Err(msg)` `panic("HttpServer.listen: " ++ msg)`; then `http_server_set_timeouts`; then `http_server_plain_listener` if set; then the existing builtin.
- Interpreter: `http_server_tls_configure` and `http_server_plain_listener` raise a runtime error `"HttpServer: HTTPS and plain_listener need a compiled build (march --compile / forge build)"`; `set_timeouts` no-op; `reload_tls` → `Err("reload_tls: no TLS server is configured")`; `http_conn_is_tls` → `false`.

- [ ] **Step 1: Failing tests.**
  - `test/stdlib/test_http_server.march`: `scheme` of a hand-built `Conn` (fd 0) is `"http"`; `tls(...)`, `plain_listener(...)` builders return a `Server` (no crash, accessors if any).
  - `test/test_https_native.ml`, suite `"https server (compiled, end-to-end)"`, case `config_errors`: compile (via `compile_march_or_skip`, `--opt 2`) a program whose `main` prints `http_server_reload_tls(0, "a", "b")` (expect `Err(reload_tls: no TLS server is configured)`), `http_server_tls_configure(0, "/nonexistent.pem", "/nonexistent.key", 0, 0)` (expect an `Err` naming `/nonexistent.pem`), and `HttpServer.scheme` of a fresh `Conn` (`http`). Case `listen_bad_cert_exits`: a server with `tls(TlsFiles(missing, missing))` exits nonzero within 5 s, stderr contains the missing path, and the port was never bound (connect refused).
  - `test/test_eval.ml` or the stdlib suite's interpreted section: interpreting a program that calls `HttpServer.tls(...) |> listen()` fails with the "need a compiled build" message.
- [ ] **Step 2: Run, expect FAIL** (unknown builtin / missing functions).
- [ ] **Step 3: Implement** the glue, builtin sites, stdlib API and interpreter entries.
- [ ] **Step 4: Run:** `./_build/default/test/run_stdlib.exe test 'https server' -e`; `dune exec --root . march -- test test/stdlib/test_http_server.march`; `./_build/default/test/run_stdlib.exe test 'http server' -e` (unchanged, green); `scripts/run-tests.sh -q compiler eval`.
- [ ] **Step 5: Commit** — `stdlib: HttpServer HTTPS configuration API and builtins`.

### Task 4: Redirect and ACME plugs

**Files:** Modify `stdlib/http_server.march`, `test/stdlib/test_http_server.march`.

**Interfaces — Produces:** `redirect_to_https(port : Int) : Conn -> Conn`, `acme_webroot(dir : String) : Conn -> Conn`, `acme_responder(lookup : String -> Option(String)) : Conn -> Conn`. Behaviour exactly as the spec's API section (301 for GET/HEAD, 308 otherwise, 400 without `Host`, `:port` omitted when 443, query kept, ACME paths left alone; token alphabet `[A-Za-z0-9_-]`, else 404; `text/plain`). Non-matching requests pass through unhalted.

- [ ] **Step 1: Failing tests:** `redirect_get` (`Host: example.com:8080`, `/a?b=1` → 301, `location: https://example.com/a?b=1`); `redirect_custom_port` (port 8443 → `https://example.com:8443/a`); `redirect_post_308`; `redirect_no_host_400`; `redirect_skips_acme` (`/.well-known/acme-challenge/x` not halted); `acme_responder_hit` (lookup `"tok"`→`Some("tok.key")` → 200 body `tok.key`); `acme_responder_miss_404`; `acme_bad_token_404` (`..%2f`, `a/b`, `a.b`); `acme_webroot_serves_file` (write `<tmp>/.well-known/acme-challenge/abc` then GET → body equals file); `acme_passthrough` (`/other` not halted).
- [ ] **Step 2: Run, expect FAIL.** `dune exec --root . march -- test test/stdlib/test_http_server.march`
- [ ] **Step 3: Implement** in March using existing `Conn` accessors and `File.read`; doc strings with examples on all three (`march-docs` skill).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `stdlib: redirect_to_https and ACME challenge plugs`.

### Task 5: Event-loop phase deadlines (plain HTTP)

**Files:** Modify `runtime/march_http_io.h` (`conn_state_t` gains `int64_t deadline_ms; int phase_kind;` and heap/list linkage), `runtime/march_http_io.c`, `runtime/march_http_evloop.c`. Test: `test/test_https_native.ml` (plain cases live in the HTTPS suite file under a `deadlines` group; they still exercise plain HTTP).

**Interfaces — Consumes:** `g_march_https.{idle_secs,header_secs,progress_secs}` (Task 3).
**Produces:** `static void conn_set_phase(conn_state_t *c, int phase)` in `march_http_evloop.c`, used by Task 7: phases `PH_HANDSHAKE`, `PH_IDLE`, `PH_HEADERS`, `PH_BODY`, `PH_WRITE`, `PH_NONE` (WS; removes the connection from the heap). It sets `c->deadline_ms = now + <that phase's seconds> * 1000` and fixes the connection's position in a `_Thread_local` min-heap keyed on `deadline_ms`; `static void sweep_deadlines(int evfd)` closes every expired connection and runs after every `kevent`/`epoll_wait` return. Header vs body: once `march_http_parse_*` sees the end of headers but the body is incomplete → `PH_BODY`; each read that adds bytes in `PH_BODY` resets; each `writev` that sends bytes in `PH_WRITE` resets.

- [ ] **Step 1: Failing e2e tests** (server src sets `idle_timeout(2) |> header_timeout(2) |> progress_timeout(2)`; event loop; each asserts server alive afterwards):
  - `idle_closes`: connect, send nothing; peer close (read returns 0) between 1.5 s and 4.5 s.
  - `idle_after_response`: one keep-alive request, then silence; closed within 4.5 s of the response.
  - `slowloris_closes`: send `GET / HTTP/1.1\r\n` then one header byte per 500 ms; closed before 4.5 s from the first byte although bytes keep arriving.
  - `slow_upload_survives`: POST with `Content-Length: 40000`, body sent 4 KB every 1 s (10 s total); 200 with the echoed length.
  - `stalled_upload_cut`: same POST, send 4 KB then stop; closed within 4.5 s.
  - `slow_reader_survives`: GET a 4 MiB body, read 64 KB every 500 ms; full body arrives intact.
  - `stalled_reader_cut`: GET 4 MiB, read nothing; server closes within ~5 s of the send buffer filling (assert closed within 8 s; server alive).
- [ ] **Step 2: Run, expect FAIL** (nothing is ever closed).
- [ ] **Step 3: Implement** the heap and phase transitions; `close_conn` removes from heap; WS handoff sets `PH_NONE`.
- [ ] **Step 4: Run** the deadline group, then `test 'http server'` (unchanged, green).
- [ ] **Step 5: Commit** — `runtime: per-phase deadlines on the event-loop HTTP server`.

### Task 6: Thread-pool and sequential deadlines (plain HTTP)

**Files:** Modify `runtime/march_http.c` (`connection_thread` ~2023-2290, WS handoff ~2160-2180).

**Interfaces — Consumes:** same config fields; `march_sched_wait_fd(fd, want_write, deadline_ms)` (`runtime/march_scheduler.h:1041`).
**Produces:** a static `int conn_wait(int fd, int want_write, int64_t deadline_ms)` used by Task 8; every read/write wait in `connection_thread` goes through it with recv/send `MSG_DONTWAIT`. Remove the 10 s `SO_RCVTIMEO` (`march_http.c:2050-2054`) and its WS-handoff clearing.

- [ ] **Step 1: Failing tests:** the seven Task 5 cases parameterised over three modes: event loop, thread pool (`~evloop:false`, which already exports `MARCH_HTTP_EVLOOP=0` to the server process at `test/test_http_native.ml:272-276`), and sequential. For sequential, add `?(extra_env = [||])` to `Test_http_native.with_compiled_server`, appended to the server's environment array there, and pass `[| "MARCH_HTTP_SEQUENTIAL=1" |]` with `~evloop:false`. Define `modes = [("evloop", true, [||]); ("pool", false, [||]); ("sequential", false, [|"MARCH_HTTP_SEQUENTIAL=1"|])]` once in `test_https_native.ml`; Tasks 7-10 reuse it.
- [ ] **Step 2: Run, expect FAIL** (pool: 10 s fixed, slowloris survives; sequential: never closes).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both variants + `test 'http server'` + the existing WS idle test in `test_stdlib_suite.ml` (`./_build/default/test/run_stdlib.exe test websocket -e`) — an idle WS must not be cut.
- [ ] **Step 5: Commit** — `runtime: deadline-based timeouts on the thread-pool HTTP server`.

### Task 7: HTTPS on the event loop, plus the plain listener

**Files:** Modify `runtime/march_http_evloop.c`, `runtime/march_http_io.{c,h}` (`conn_state_t` gains `march_tls_session_t *tls; void *pipeline;` and a ciphertext out buffer), `runtime/march_https.c` (start listeners). Test: `test/test_https_native.ml` + harness helpers.

**Interfaces — Consumes:** Tasks 1-3, 5.
**Produces (OCaml, in `test_https_native.ml`, used by Tasks 8-10):**
- `type pki = { dir : string; ca : string; cert : string; key : string }`
- `make_pki : dir:string -> name:string -> ?days:int -> unit -> pki` — `openssl` CLI: EC P-256 CA, leaf for `localhost` + `127.0.0.1` SAN signed by it; `?days` negative makes an expired leaf.
- `tls_connect_or_bail : server_ctx -> ca:string -> ?sni:string -> unit -> Unix.file_descr` — `Unix.socketpair`, child end as stdin+stdout of `openssl s_client -quiet -connect 127.0.0.1:<port> -CAfile <ca> -verify_return_error [-servername <sni>]`; returns the parent end, usable with `server_ctx.send` / `read_response`; kills the child on close.
- `served_leaf_serial : port:int -> ca:string -> string` (shells `openssl s_client … </dev/null | openssl x509 -noout -serial`).

Runtime: each evloop thread opens one `SO_REUSEPORT` listener per port (main; `g_march_https.plain_port` when set); epoll/kqueue user data on listeners identifies `{fd, pipeline, is_tls}`. On accept from a TLS listener: `ctx = mts_slot_acquire()` (NULL → close), `mts_new_server`, `SSL_CTX_free(ctx)`, `mts_registry_put(fd, s)`, `PH_HANDSHAKE`. Read: `recv` into a 16 KiB stack buffer → `mts_feed` → handshake or `mts_read` into `c->rbuf` until `MTS_NEED_INPUT`; `MTS_EOF`/`MTS_FAIL` → close. Write: each batch iovec → `mts_write`; release handler results immediately; then send `mts_take_out` bytes with the existing non-blocking send/defer machinery holding owned ciphertext. Close: `mts_shutdown` + one non-blocking send attempt, `mts_registry_take`, `mts_free`, `close`. Plain listener connections: today's path, their own pipeline.

- [ ] **Step 1: Failing e2e tests** (event loop; server: `tls(TlsFiles(pki.cert, pki.key))`, `plain_listener(<port2>, [route echoing scheme])`, routes `/echo`, `/big/<n>` returning n bytes, `/scheme`):
  - `https_basic`: GET `/echo?x=1` over `tls_connect_or_bail`, body asserted.
  - `https_keepalive_65`: 65 sequential requests on one TLS connection, bodies asserted.
  - `https_pipelined`: 16 pipelined requests in one write, 16 bodies in order.
  - `https_post_large`: POST 200 000-byte body, echoed length and checksum match.
  - `https_scheme`: `/scheme` → `https` over TLS; on the plain port → `http`.
  - `https_no_sni` (Review Focus 2): connect without `-servername` → 200.
  - `https_plaintext_to_tls_port` (Review Focus 1): raw TCP `GET / HTTP/1.1\r\n\r\n` to the TLS port → closed within 2 s, server alive, a following TLS request works.
  - `https_slow_reader_big` (Review Focus 3): pipeline 4 × `/big/1048576`, read 32 KB every 50 ms; all 4 bodies intact and in order.
  - `fd_reuse_plain_after_tls` (Review Focus 4): open+close 50 TLS connections, then 50 plain-port requests to `/scheme` all return `http`.
  - `handshake_timeout`: `tls_handshake_timeout(2)`; raw TCP connect, send nothing → closed within 1.5-4.5 s.
  - `plain_listener_own_pipeline`: plain port answers with its own pipeline's body, not the TLS pipeline's.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `test 'https server'`, `test 'http server'`, Task 5's deadline group.
- [ ] **Step 5: Commit** — `runtime: HTTPS on the event-loop server, plus an extra plain listener`.

### Task 8: HTTPS on the thread pool and sequential mode

**Files:** Modify `runtime/march_http.c` (accept loop `select` over both listeners ~2579-2660; `connection_thread`).

**Interfaces — Consumes:** Tasks 1-3, 6 (`conn_wait`), Task 7 harness helpers.
**Produces:** `connection_thread` takes `{fd, pipeline, is_tls}`; TLS handshake loop = `recv` → `mts_feed` → `mts_handshake`, sending `mts_take_out`, waiting via `conn_wait` with the handshake deadline; request loop reads via the session into its buffer; responses: iovecs → `mts_write` → send ciphertext with `conn_wait` for writability.

- [ ] **Step 1: Failing tests:** Task 7's eleven cases run over the `pool` and `sequential` entries of `modes`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** all three modes of the HTTPS suite + `test 'http server'`.
- [ ] **Step 5: Commit** — `runtime: HTTPS on the thread-pool server`.

### Task 9: `wss://` through the fd registry

**Files:** Modify `runtime/march_http.c` (`march_ws_handshake` 2748, `march_ws_recv` 2807, `march_ws_send` 2932, the `ws_select` builtin), `runtime/march_http_evloop.c` (`ws_handler_thread`, upgrade path), `connection_thread` upgrade path.

**Interfaces — Consumes:** `mts_registry_get`, `mts_lock`/`mts_send_lock`, Task 7 harness.
**Produces:** two static helpers in `march_http.c` used by every WS function: `ws_io_recv(int fd, void *buf, size_t n, int64_t deadline_ms) -> ssize_t` and `ws_io_send_all(int fd, const void *buf, size_t n) -> int`. With a session: recv = wait on the socket **unlocked**, then `mts_lock`; `mts_feed`; `mts_read`; `mts_unlock` (serve already-buffered plaintext before waiting); send = `mts_send_lock` → `mts_lock` → `mts_write` + `mts_take_out` → `mts_unlock` → blocking send of all ciphertext → `mts_send_unlock`. `ws_select` returns readable immediately when `mts_has_input`. Plaintext left in `c->rbuf` after the upgrade request is fed to the WS reader before the socket (evloop: pass it in `ws_upgrade_arg_t`; pool: keep it in the thread's buffer).

- [ ] **Step 1: Failing tests** (all three modes; a minimal WS client in OCaml over the `tls_connect_or_bail` fd: upgrade request with a fixed `Sec-WebSocket-Key`, masked text frames, frame parser; or reuse the parser from `test_stdlib_suite.ml`'s WS test if exportable):
  - `wss_echo`: upgrade over TLS → 101 with the correct `Sec-WebSocket-Accept`; 20 text frames echoed.
  - `wss_large_frame`: one 100 000-byte frame echoed intact.
  - `wss_idle_outlives_idle_timeout`: `idle_timeout(2)`; stay silent 6 s; then a frame is still echoed.
  - `wss_concurrent_push`: server handler spawns a task that sends `push <i>` for i in 1..200 while the handler blocks in `WebSocket.recv`; client receives all 200 in order, each intact, within 5 s, without sending anything.
  - `ws_plain_unchanged`: the same echo over the plain port still works.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** HTTPS suite (all modes) + `./_build/default/test/run_stdlib.exe test websocket -e` + `test 'http server'`.
- [ ] **Step 5: Commit** — `runtime: wss:// via the TLS session registry`.

### Task 10: Rotation, bootstrap and startup behaviour end to end

**Files:** Modify `runtime/march_https.c` (start poller from `listen` when files + `poll_secs > 0`; bootstrap: TLS listeners bound on first successful install — evloop threads check `mts_slot_generation()` on each wake and open the TLS listener once it is nonzero; pool accept loop the same), `runtime/march_http_evloop.c`, `runtime/march_http.c`.

**Interfaces — Consumes:** `mts_poller_start`, `mts_slot_generation`, harness `make_pki`, `served_leaf_serial`.

- [ ] **Step 1: Failing tests** (event loop and thread pool; `tls_poll_interval(1)`):
  - `poll_rotation`: start with pki A; open a TLS keep-alive connection; overwrite files with pki B (same CA dir layout, new serial; client trusts both CAs via a concatenated `-CAfile`); within 4 s `served_leaf_serial` is B's; the old connection still serves a request; stderr has `installed certificate`.
  - `poll_refusal_keeps_old`: write B's cert with A's key; after 3 s still A's serial; stderr has `refused certificate` exactly once (not once per poll); then write B's key → B served within 4 s.
  - `reload_tls_pem`: a route `/reload` that reads B's PEM files with `File.read` and calls `reload_tls(TlsPem(c, k))`, returning `ok`/the `Err` text; after it, B served. A mismatched pair → body contains the error, A still served.
  - `reload_race` (Review Focus 5): a route that starts a task calling `reload_tls` alternately with A and B 100 times; concurrently 200 sequential new TLS connections each GET `/echo`; all 200 succeed.
  - `bootstrap_mode`: `tls_wait_for_cert()`, files missing; plain listener answers; TLS port refuses; write pki A files; TLS request succeeds within 4 s.
  - `expired_at_startup_serves`: start with an expired leaf (`make_pki ~days:-1`); server starts, stderr has `expired`; `openssl s_client` (without `-verify_return_error`) completes a handshake.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** HTTPS suite (all modes), `test 'http server'`.
- [ ] **Step 5: Commit** — `runtime: HTTPS certificate rotation by polling and reload_tls, bootstrap mode`.

### Task 11: Example, docs, ASAN, benchmark, changelog, progress

**Files:** Create `examples/https_hello.march`; Modify `specs/features/http-and-networking.md` (HTTPS section + deployment recipe; update "Known Limitations"), `CHANGELOG.md`, `specs/benchmarks.md`; `git mv specs/todos/2026-11-05-https-server.md specs/progress/2026-11-05-https-server.md` and append results.

- [ ] **Step 1: Example app** `examples/https_hello.march`: page at `/`, `POST /upload` echoing byte count, `wss` echo at `/ws` that also pushes `tick <n>` every second from a second task; `tls(TlsFiles(env CERT, env KEY))`, `plain_listener(80, [acme_webroot(env WEBROOT), redirect_to_https(443)])`, `tls_wait_for_cert()`. Verify it compiles: `./_build/default/bin/main.exe --compile --opt 2 examples/https_hello.march -o /tmp/https_hello_$$` exits 0. If `test/test_bench_gate.ml` or an examples gate lists examples, register it there.
- [ ] **Step 2: Deployment recipe** in `specs/features/http-and-networking.md`: certbot `--webroot -w <dir>` first run in bootstrap mode (or `--standalone` before first start), `--deploy-hook` not needed (polling), mount the whole `/etc/letsencrypt` in Docker, binding 443/80 (root, `CAP_NET_BIND_SERVICE`, or port mapping), interpreter limitation. Run `scripts/check-docs.sh` → exit 0.
- [ ] **Step 3: ASAN:** run the HTTPS suite against an ASAN build (`march-debug` skill; on macOS ASAN needs Docker per the repo's memory notes). No leak or error reports attributable to `march_tls_*`/`march_https*`/evloop/pool code. Record the command and result in the progress file.
- [ ] **Step 4: Benchmark:** `specs/benchmarks.md` Run 5 method (Linux, quiet box, wrk `-c256`, order-swapped) on plain HTTP before (merge-base binary) and after: within noise. HTTPS: keep-alive and new-connection-per-request req/s and CPU-µs/request on the event loop; append both as a new dated Run section.
- [ ] **Step 5: Changelog** under `[Unreleased]`: Added — HTTPS for `HttpServer` (`tls`, `wss://`, `reload_tls`, certificate polling, `tls_wait_for_cert`, `plain_listener`, `scheme`, `redirect_to_https`, `acme_webroot`/`acme_responder`, `header_timeout`/`progress_timeout`); Changed — `idle_timeout` is enforced on both server modes (the thread pool's hard-coded 10 s becomes the configured value, 60 s by default), and request headers/bodies/responses have deadlines. Fixed — the ALPN buffer leak in `Tls.server_ctx`.
- [ ] **Step 6: Full suite:** `scripts/run-tests.sh` (full, not `-q`) green; `scripts/check-runtime-sources.sh`, `scripts/check-docs.sh` exit 0.
- [ ] **Step 6b: Downstream compiles unchanged** (anti-goal: no Bastion/forgepm changes): in `~/code/forgepm`, `forge build` using this branch's compiler (`MARCH_LIB_PATH` recipe in `CLAUDE.md`, or the worktree dev-compiler workflow) exits 0 with no source edits to forgepm or Bastion.
- [ ] **Step 7: Progress + commit:** `git mv` the todo into `specs/progress/`, add the ASAN, benchmark and test results, and note that the staging acceptance deploy (spec "Done means" item 2) is the owner's manual step. Commit all Task 11 files by name — `docs: HTTPS server example, deployment recipe, benchmarks, changelog`.
