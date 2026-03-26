/* runtime/march_tls.h — TLS builtins for March (OpenSSL 3 backend).
 *
 * These functions are called from compiled March code and from the interpreter.
 * TLS contexts (SSL_CTX *) and connections (SSL *) are stored as opaque
 * int64_t handles (cast from pointer) so March code treats them like file
 * descriptors.
 *
 * All March heap objects follow the standard layout:
 *   offset  0: int64_t  rc   (reference count)
 *   offset  8: int32_t  tag  (constructor tag)
 *   offset 12: int32_t  pad
 *   offset 16+: fields (8 bytes each)
 *
 * Result layout: Ok = tag 1, field0 = value; Err = tag 0, field0 = string.
 */
#pragma once
#include "march_runtime.h"
#include <stdint.h>

/* ── Context creation ────────────────────────────────────────────────── */

/* Build a client-side SSL_CTX.
 *   ca_file       — march_string* path to PEM CA bundle, or NULL/empty → system roots
 *   alpn_list     — March List(String) of ALPN protocols (e.g. ["http/1.1"])
 *   min_tls_ver   — 0 → TLS 1.2,  1 → TLS 1.3
 *   verify_peer   — 1 → verify server cert (recommended), 0 → skip
 * Returns Ok(ctx_handle:Int) or Err(String). */
void *march_tls_client_ctx(void *ca_file, void *alpn_list,
                            int64_t min_tls_ver, int64_t verify_peer);

/* Build a server-side SSL_CTX.
 *   cert_file     — march_string* path to PEM certificate (chain)
 *   key_file      — march_string* path to PEM private key
 *   ca_file       — march_string* path to PEM CA bundle, or NULL/empty
 *   alpn_list     — March List(String) of ALPN protocols
 *   min_tls_ver   — 0 → TLS 1.2,  1 → TLS 1.3
 * Returns Ok(ctx_handle:Int) or Err(String). */
void *march_tls_server_ctx(void *cert_file, void *key_file, void *ca_file,
                            void *alpn_list, int64_t min_tls_ver);

/* ── Handshake ───────────────────────────────────────────────────────── */

/* Client-side TLS handshake on an already-connected TCP fd.
 *   hostname — march_string* used for SNI + certificate verification
 * Returns Ok(ssl_handle:Int) or Err(String). */
void *march_tls_connect(int64_t fd, int64_t ctx_handle, void *hostname);

/* Server-side TLS handshake on an accepted TCP fd.
 * Returns Ok(ssl_handle:Int) or Err(String). */
void *march_tls_accept(int64_t fd, int64_t ctx_handle);

/* ── I/O ─────────────────────────────────────────────────────────────── */

/* Read up to max_bytes from a TLS connection.
 * Returns Ok(String) or Err(String). Ok("") signals clean shutdown. */
void *march_tls_read(int64_t ssl_handle, int64_t max_bytes);

/* Write data to a TLS connection.
 * Returns Ok(Int) — bytes written — or Err(String). */
void *march_tls_write(int64_t ssl_handle, void *data);

/* ── Teardown ────────────────────────────────────────────────────────── */

/* TLS shutdown + free the SSL object.  Does NOT close the underlying fd.
 * Safe to call with handle == 0 (no-op). */
void march_tls_close(int64_t ssl_handle);

/* Free an SSL_CTX.  Safe to call with handle == 0 (no-op). */
void march_tls_ctx_free(int64_t ctx_handle);

/* ── Introspection ───────────────────────────────────────────────────── */

/* Return the negotiated ALPN protocol as a march_string*, or NULL if none. */
void *march_tls_negotiated_alpn(int64_t ssl_handle);

/* Return the peer certificate's Common Name as a march_string*, or NULL. */
void *march_tls_peer_cn(int64_t ssl_handle);
