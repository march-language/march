/* runtime/march_http_response.h — Zero-copy HTTP response builder for March.
 *
 * Provides a zero-allocation response pipeline for the server hot path:
 *
 *  1. Pre-serialized static components (status lines, common headers, plaintext
 *     body) are stored as const globals.  iovec entries point directly into them.
 *
 *  2. march_response_t holds a fixed-size iovec array.  Helper functions fill it
 *     in without malloc.  A single writev() call sends the complete response.
 *
 *  3. A thread-local scratch buffer (MARCH_RESPONSE_SCRATCH_SIZE bytes) holds
 *     dynamically-formatted parts such as Content-Length digits and custom Date
 *     values.  The buffer is reset per-response via march_response_init().
 *
 *  4. The Date header value is cached globally and refreshed at most once per
 *     second — not per request.
 *
 * Typical usage:
 *
 *   march_response_t resp;
 *   march_response_init(&resp);
 *   march_response_set_status(&resp, 200);
 *   march_response_add_header(&resp, "Content-Type", 12, "text/plain", 10);
 *   march_response_add_date_header(&resp);
 *   march_response_set_body(&resp, "Hello, World!", 13);
 *   march_response_send(&resp, client_fd);
 *
 * For the TechEmpower /plaintext benchmark, use the pre-built fast path:
 *
 *   march_response_send_plaintext(client_fd);   // single writev, zero alloc
 */
#pragma once

#include <sys/uio.h>
#include <stddef.h>
#include <stdint.h>

/* ── Limits ──────────────────────────────────────────────────────────── */

/* Maximum iovec entries in one response:
 *   1 (status) + 4*32 (headers) + 1 (CL) + 1 (CRLF) + 1 (body) = 132.
 *   Round up to a power-of-two for cache alignment. */
#define MARCH_RESPONSE_MAX_IOVEC    160

/* Per-thread scratch buffer for dynamic response parts (CL digits, etc.). */
#define MARCH_RESPONSE_SCRATCH_SIZE (16 * 1024)   /* 16 KB */

/* ── Pre-serialized plaintext benchmark components ───────────────────── */

/* Status + fixed headers block for TechEmpower /plaintext.
 * Does NOT include a Date header (appended from the cache) or the blank line
 * (appended by march_response_set_body). */
extern const char   MARCH_PLAINTEXT_STATIC_HEADERS[];
extern const size_t MARCH_PLAINTEXT_STATIC_HEADERS_LEN;

/* "Hello, World!" body. */
extern const char   MARCH_PLAINTEXT_BODY[];
extern const size_t MARCH_PLAINTEXT_BODY_LEN;

/* ── Response builder ─────────────────────────────────────────────────── */

typedef struct {
    struct iovec iov[MARCH_RESPONSE_MAX_IOVEC];
    int          iov_count;
    /* Bytes consumed in the thread-local scratch buffer for this response.
     * Reset to 0 by march_response_init(). */
    size_t       scratch_used;
} march_response_t;

/* ── Module init ─────────────────────────────────────────────────────── */

/* Call once at server startup (e.g. from march_http_server_listen).
 * Seeds the Date header cache so the first request does not pay the
 * gmtime_r() cost.  Safe to call from multiple threads — idempotent. */
void march_http_response_module_init(void);

/* ── Response builder API ────────────────────────────────────────────── */

/* Reset resp for a new request.  Also resets the scratch offset so the
 * thread-local buffer is available for this response's dynamic content. */
void march_response_init(march_response_t *resp);

/* Append the status line for status_code to resp's iovec array.
 * For common codes (200, 400, 404, 500, …) this points to a static string.
 * Unknown codes are formatted into the scratch buffer. */
void march_response_set_status(march_response_t *resp, int status_code);

/* Append a single header as four iovec entries:
 *   name  |  ": "  |  value  |  "\r\n"
 * The name and value pointers must remain valid until march_response_send(). */
void march_response_add_header(march_response_t *resp,
                                const char *name,  size_t name_len,
                                const char *value, size_t value_len);

/* Append the cached Date header as a single iovec entry.
 * The returned pointer is valid for the lifetime of this request (the cache
 * is never overwritten mid-request — it is only replaced atomically). */
void march_response_add_date_header(march_response_t *resp);

/* Append:
 *   Content-Length: <len>\r\n
 *   \r\n
 *   <body data>
 * The Content-Length line is formatted into the scratch buffer.
 * data must remain valid until march_response_send().
 * Pass data=NULL / len=0 for an empty body (headers are still terminated). */
void march_response_set_body(march_response_t *resp,
                              const char *data, size_t len);

/* Send the response by issuing a single writev() call.
 * Retries on EINTR and partial writes.
 * Returns 0 on success, -1 on error (errno set). */
int march_response_send(march_response_t *resp, int fd);

/* Reset resp for reuse in a batch without touching scratch_used.
 * Sets iov_count = 0 but does NOT reset scratch_used — the iovecs already
 * appended to the batch may still point into the scratch buffer and must
 * remain valid until the entire batch has been written.
 *
 * Use pattern for batch pipelining:
 *   march_response_t bresp = { .iov_count = 0, .scratch_used = 0 };
 *   for each request:
 *     march_response_clear_no_free(&bresp);  // carry scratch_used forward
 *     build response into bresp ...
 *     memcpy batch_iov + n, bresp.iov, bresp.iov_count * sizeof(iovec)
 *     n += bresp.iov_count;
 *   writev_all(fd, batch_iov, n);            // one syscall for the batch
 */
void march_response_clear_no_free(march_response_t *resp);

/* ── Plaintext fast path ──────────────────────────────────────────────── */

/* Send a pre-built HTTP/1.1 200 text/plain "Hello, World!" response to fd.
 * Uses at most 4 iovec entries (static headers, Date, CRLF, body).
 * Zero per-request heap allocation; Date is refreshed at most once/second.
 * Returns 0 on success, -1 on error. */
int march_response_send_plaintext(int fd);

/* ── Date header cache ────────────────────────────────────────────────── */

/* Return a pointer to the current cached Date header string of the form
 *   "Date: Wed, 25 Mar 2026 12:34:56 GMT\r\n"
 * and store its length in *len_out.  The pointer is valid until the next
 * second boundary — callers must consume it before yielding.
 * Thread-safe: the cache is protected by an internal lock. */
const char *march_http_cached_date(size_t *len_out);
