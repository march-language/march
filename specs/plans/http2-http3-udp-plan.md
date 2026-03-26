# HTTP/2, HTTP/3, and UDP Transport Plan

## Overview

This plan extends March's networking stack beyond HTTP/1.1 with:

- **Part 1 — TLS Foundation**: OpenSSL-backed TLS for both client and server
- **Part 2 — HTTP/2**: Multiplexed streams over TLS using `nghttp2`
- **Part 3 — HTTP/3 / QUIC**: UDP-based multiplexed transport via `quiche` or `ngtcp2`
- **Part 4 — Raw UDP**: First-class UDP socket support for custom protocols

Each part builds on the previous. Parts 2–4 are future work; Part 1 is the prerequisite.

---

## Part 1 — TLS Foundation

### Goal

Add TLS support to March's networking layer so HTTPS client connections and
HTTPS server listeners both work. The TLS layer wraps existing TCP file
descriptors returned by `tcp_connect` / `tcp_accept` and exposes an
identical read/write API.

### Design Decisions

- **Backend**: OpenSSL 3.x (available via Homebrew on macOS, system package on
  Linux). BoringSSL is API-compatible; the C file can be compiled against
  either by adjusting the include path.
- **Object model**: TLS contexts (`SSL_CTX *`) and connections (`SSL *`) are
  stored as opaque `int64_t` handles (pointer-cast) on the March side, matching
  how March already treats file descriptors.
- **Blocking I/O**: The initial version uses blocking `SSL_read` / `SSL_write`.
  Non-blocking integration with `kqueue`/`epoll` is a follow-on (Part 2).
- **Certificate verification**: Enabled by default for clients; disabled by
  default for servers (server sends cert, does not request one from client).
- **SNI**: `SSL_set_tlsext_host_name` is called automatically on client connect.
- **ALPN**: Configurable list of protocol names (e.g. `["h2", "http/1.1"]`).
- **Session resumption**: TLS 1.3 session tickets enabled by default; 0-RTT
  is left for Part 2 (requires careful replay protection).
- **Min TLS version**: Defaults to TLS 1.2; configurable to TLS 1.3.

### C API (`runtime/march_tls.c` + `runtime/march_tls.h`)

```c
// Build a server-side SSL_CTX. cert_file/key_file are PEM paths.
// alpn is a March List(String). min_tls_version: 0→TLS1.2, 1→TLS1.3.
// Returns Ok(ctx_handle:i64) or Err(String).
void *march_tls_server_ctx(void *cert_file, void *key_file,
                            void *ca_file, void *alpn_list,
                            int64_t min_tls_version);

// Build a client-side SSL_CTX. ca_file may be NULL (uses system roots).
void *march_tls_client_ctx(void *ca_file, void *alpn_list,
                            int64_t min_tls_version, int64_t verify_peer);

// Perform TLS client handshake on an already-connected TCP fd.
// hostname is used for SNI and certificate verification.
// Returns Ok(ssl_handle:i64) or Err(String).
void *march_tls_connect(int64_t fd, int64_t ctx_handle, void *hostname);

// Perform TLS server handshake on an accepted TCP fd.
// Returns Ok(ssl_handle:i64) or Err(String).
void *march_tls_accept(int64_t fd, int64_t ctx_handle);

// Read up to max_bytes from a TLS connection.
// Returns Ok(String) or Err(String). Ok("") means clean shutdown.
void *march_tls_read(int64_t ssl_handle, int64_t max_bytes);

// Write data to a TLS connection.
// Returns Ok(Int) — bytes written — or Err(String).
void *march_tls_write(int64_t ssl_handle, void *data);

// Perform TLS shutdown and free the SSL object. Does NOT close the fd.
void march_tls_close(int64_t ssl_handle);

// Free an SSL_CTX.
void march_tls_ctx_free(int64_t ctx_handle);
```

### March API (`stdlib/tls.march`)

```
mod Tls do

  -- TlsVersion: minimum TLS protocol version
  type TlsVersion = Tls12 | Tls13

  -- TlsError: all failure modes
  type TlsError =
    TlsHandshakeFailed(String)
    | TlsCertError(String)
    | TlsReadError(String)
    | TlsWriteError(String)
    | TlsContextError(String)

  -- TlsConfig: configuration for a TLS context
  type TlsConfig =
    TlsConfig(
      String,        -- cert_file  (PEM path, "" for client-only ctx)
      String,        -- key_file   (PEM path, "" for client-only ctx)
      String,        -- ca_file    (PEM path, "" → system roots)
      List(String),  -- alpn       (e.g. ["h2", "http/1.1"])
      TlsVersion,    -- min_version
      Bool           -- verify_peer (True for clients, False for servers)
    )

  -- Opaque context and connection handles
  type TlsCtx  = TlsCtx(Int)
  type TlsConn = TlsConn(Int)

  fn client_ctx(config) ...
  fn server_ctx(config) ...
  fn connect(fd, ctx, hostname) ...
  fn accept(fd, ctx) ...
  fn read(conn, max_bytes) ...
  fn write(conn, data) ...
  fn close(conn) ...
  fn ctx_free(ctx) ...

  -- Convenience: full HTTPS GET
  fn https_get(url) ...

end
```

### Tests (`test/stdlib/test_tls.march`)

Unit tests cover:
1. Default `TlsConfig` construction and field access
2. `client_ctx` with system roots returns `Ok(TlsCtx(_))`
3. `tls_version_to_string` helpers
4. `connect` to `example.com:443` returns `Ok(conn)`, reads HTTP response
5. `write` + `read` round-trip over loopback (requires spawning a test server)
6. `close` is idempotent (no crash on double-close guard)
7. `server_ctx` with a self-signed cert returns `Ok(TlsCtx(_))`

### Build integration

`runtime/march_tls.c` is compiled as part of the native March binary. It
requires linking against `-lssl -lcrypto`. The `bin/dune` file (or the Makefile
for the native executable) must add:

```
(c_names march_tls)
(c_library_flags (-lssl -lcrypto))
```

Or equivalently in the Makefile:

```makefile
LDFLAGS += -lssl -lcrypto
```

The OpenSSL headers are found at:
- macOS (Homebrew): `/opt/homebrew/opt/openssl@3/include`
- Linux: `/usr/include/openssl`

### File list

| File | Description |
|------|-------------|
| `specs/plans/http2-http3-udp-plan.md` | This file |
| `runtime/march_tls.h` | C header |
| `runtime/march_tls.c` | OpenSSL 3 implementation |
| `stdlib/tls.march` | March TLS module |
| `test/stdlib/test_tls.march` | Unit tests |

---

## Part 2 — HTTP/2 (Future)

Depends on Part 1 (TLS). Uses `nghttp2` for HPACK and stream multiplexing.
Integrates with an async event loop (kqueue/epoll) for non-blocking I/O.

---

## Part 3 — HTTP/3 / QUIC (Future)

Depends on Part 2. QUIC is TLS 1.3 over UDP; requires a QUIC library such
as `quiche` (Cloudflare) or `ngtcp2` + `nghttp3`.

---

## Part 4 — Raw UDP (Future)

`socket(AF_INET, SOCK_DGRAM, 0)` based API. Useful for DNS, NTP, game
protocols, custom binary protocols. Sendto/recvfrom with address tuples.
