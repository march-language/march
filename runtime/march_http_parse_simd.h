/* runtime/march_http_parse_simd.h — SIMD-accelerated HTTP/1.x request parser.
 *
 * Provides a standalone C API for parsing HTTP/1.x requests from a flat
 * buffer.  On x86-64 with SSE4.2 the fast path uses PCMPESTRI to scan
 * 16 bytes per cycle; on other architectures (e.g. ARM64) the scalar
 * fallback is used automatically.
 *
 * The API is independent of the March runtime heap — callers receive
 * pointers into the *input buffer* (zero-copy) rather than march_string
 * objects.  march_http.c wraps this into March heap values.
 */
#pragma once

#include <stddef.h>
#include <stdint.h>

/* Maximum number of headers we will parse per request. */
#define MARCH_HTTP_MAX_HEADERS 64

/* One HTTP header name/value pair.
 * Both pointers point into the original input buffer — no allocation. */
typedef struct {
    const char *name;
    size_t      name_len;
    const char *value;
    size_t      value_len;
} march_http_header_t;

/* Parsed HTTP/1.x request.
 * All string fields are slices into the caller-owned input buffer.
 * The struct does NOT own any memory. */
typedef struct {
    const char *method;       /* e.g. "GET", "POST" */
    size_t      method_len;
    const char *path;         /* request-target (URI path + query) */
    size_t      path_len;
    int         minor_version; /* 0 = HTTP/1.0, 1 = HTTP/1.1 */

    march_http_header_t headers[MARCH_HTTP_MAX_HEADERS];
    size_t num_headers;

    /* Offset past the header section (start of the body, if any).
     * Set to the number of bytes consumed to parse the request line +
     * all headers + the final \r\n\r\n terminator. */
    size_t header_end;
} march_http_request_t;

/* ── Single-request API ──────────────────────────────────────────────── */

/* Parse one HTTP/1.x request from buf[0..len).
 *
 * Returns:
 *   > 0   Number of bytes consumed (= req->header_end).  req is fully
 *          populated.  The body, if any, begins at buf + return_value.
 *   0     Incomplete request — need more data.  req is unmodified.
 *  -1     Parse error (malformed request line or headers).
 *
 * On success, all string fields in req point into buf.  buf must remain
 * valid for as long as req is used. */
int march_http_parse_request_simd(const char *buf, size_t len,
                                   march_http_request_t *req);

/* ── Pipelined-request API ───────────────────────────────────────────── */

/* Parse up to max_reqs pipelined HTTP/1.x requests from buf[0..len).
 *
 * Each request is parsed sequentially; parsing stops when one of:
 *   - max_reqs requests have been filled, or
 *   - the buffer is exhausted / incomplete, or
 *   - a parse error occurs.
 *
 * Returns the number of fully-parsed requests stored in reqs[].
 * *consumed is set to the total number of bytes consumed across all
 * parsed requests (the caller should advance its buffer by this amount).
 *
 * A return value of 0 with *consumed == 0 means either the buffer is
 * empty, incomplete, or malformed.  Distinguish incomplete from error
 * by checking the single-request API on the remaining data. */
int march_http_parse_pipelined(const char *buf, size_t len,
                                march_http_request_t *reqs, int max_reqs,
                                size_t *consumed);

/* ── Utility ─────────────────────────────────────────────────────────── */

/* Returns 1 if the compiled binary has the SSE4.2 SIMD fast path enabled,
 * 0 if running on scalar-only fallback.  Useful for benchmarks / logging. */
int march_http_simd_available(void);
