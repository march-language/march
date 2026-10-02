/* runtime/march_http_internal.h — Shared internals between march_http.c and
 * march_http_evloop.c.
 *
 * NOT part of the public API.  Only include from the HTTP implementation files.
 */
#pragma once

#include "march_http_parse_simd.h"
#include "march_http_response.h"
#include "march_runtime.h"
#include <ctype.h>
#include <stddef.h>
#include <stdint.h>

/* Closure function pointer: fn(closure, arg) → result. */
typedef void *(*closure_fn_t)(void *clo, void *arg);

/* ── Releasing handler results ────────────────────────────────────────
 * The pipeline returns a Conn the runtime only reads (status, headers, body)
 * before writing the response; it never owned a way to free it: march_decrc
 * is shallow (free one cell, orphan the children), and `assigns`/`upgrade`
 * can hold arbitrary March values no C walk can shape.  So HttpServer.listen
 * hands the runtime a compiled `Conn -> Unit` closure whose body is the
 * synthesized deep drop (lib/tir/drop.ml), and every server path calls it on
 * each result once the response bytes are out of the iovecs — after a
 * completed writev, or when a deferred write drains/the connection closes.
 * Before this, every request leaked the result record and its strings
 * (~0.5 KiB; forgepm at 800 req/s grew 400 MB/min).  NULL = no releaser
 * (the http_server_spawn_n test path), which restores the old leak rather
 * than crashing. */
extern void *g_march_http_release_clo;
void march_http_release_conn(void *conn);
static inline void march_http_release_conns(void **conns, int *n) {
    for (int i = 0; i < *n; i++) march_http_release_conn(conns[i]);
    *n = 0;
}

/* Build an empty March List (Nil tag=0).  Used for empty headers lists. */
static inline void *make_nil(void) { return march_alloc(16); }

/* ── WebSocket helpers (used by both march_http.c and march_http_evloop.c) ── */

/* Case-insensitive strncmp. */
static inline int istrncmp_ws(const char *a, const char *b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        int ca = tolower((unsigned char)a[i]);
        int cb = tolower((unsigned char)b[i]);
        if (ca != cb) return ca - cb;
        if (ca == '\0') return 0;
    }
    return 0;
}

/* Walk a March List(Header) and return the String value of the
 * Sec-WebSocket-Key header, or NULL if not present.
 * Header layout: [rc|tag|name_ptr@16|value_ptr@24], List cell [rc|tag@8|head@16|tail@24]. */
static inline void *find_ws_key_header(void *headers) {
    void *cur = headers;
    while (cur) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break;  /* Nil */
        void *hdr  = *(void **)((char *)cur + 16);
        void *tail = *(void **)((char *)cur + 24);
        march_string *hname = *(march_string **)((char *)hdr + 16);
        if (hname->len == 17 &&
            istrncmp_ws(hname->data, "sec-websocket-key", 17) == 0) {
            return *(void **)((char *)hdr + 24);  /* value */
        }
        cur = tail;
    }
    return NULL;
}

/* Invoke a March closure with one argument.
 * March closure layout: [rc(8)|tag(4)|pad(4)|fn_ptr(8)|captures...]
 * Calling convention: fn_ptr(closure, arg). */
static inline void *call_closure1(void *clo, void *arg) {
    typedef void *(*clo_fn1_t)(void *, void *);
    clo_fn1_t fn = *(clo_fn1_t *)((char *)clo + 16);
    return fn(clo, arg);
}

/* Build a March Conn heap object directly from a parsed SIMD request.
 * This is the fast path that avoids the intermediate Ok(tuple(...)) allocation
 * used by the legacy march_http_parse_request() path. */
void *march_conn_from_parsed(const march_http_request_t *req,
                              const char *buf, size_t buf_len,
                              int fd);

/* Detect keep-alive from a parsed SIMD request (HTTP version + Connection hdr).
 * Returns 1 for keep-alive, 0 for close. */
int march_detect_keep_alive_simd(const march_http_request_t *req);

/* Send an HTTP response with a Connection: keep-alive or close header.
 * Uses the zero-copy march_response_t builder + writev.
 * Returns 0 on success, -1 on error. */
int march_send_response_with_ka(int fd, int64_t status, void *headers,
                                 void *body, int keep_alive);

/* Process one parsed request through the March pipeline and send the response.
 * Returns: 1 = keep going, 0 = close connection, -1 = error. */
int march_process_one_request(int fd, void *pipeline, closure_fn_t fn,
                               const march_http_request_t *req,
                               const char *buf, size_t buf_len);

/* Build a response into *resp using the zero-copy builder.
 * resp->iov_count is reset to 0 (via march_response_clear_no_free before the
 * call); resp->scratch_used carries forward so iovecs from multiple pipelined
 * responses share the TLS scratch buffer without overlap.
 * Use the batch pattern: init bresp once, call clear_no_free + this per req,
 * accumulate iovecs into batch_iov[], then writev the entire batch at once. */
void march_populate_response_ka(march_response_t *resp,
                                 int64_t status, void *headers,
                                 void *body, int keep_alive);
