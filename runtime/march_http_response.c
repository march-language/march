/* runtime/march_http_response.c — Zero-copy HTTP response builder.
 *
 * Implements the API declared in march_http_response.h.
 *
 * Design notes:
 *
 *   Static strings: common status lines and fixed header fragments are stored
 *   as constant char arrays.  iovec entries point directly into them — no copy.
 *
 *   Thread-local scratch: each thread has a MARCH_RESPONSE_SCRATCH_SIZE buffer.
 *   march_response_init() resets scratch_used to 0.  Dynamic content (e.g.
 *   Content-Length digits, fallback status lines) is snprintf'd there.
 *
 *   Date cache: a single globally-cached "Date: ...\r\n" string is refreshed
 *   at most once per second.  The hot path does an atomic time_t compare to
 *   skip the mutex entirely when the cached value is still current.
 */

#include "march_http_response.h"

#include <sys/uio.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>

/* ── Static separator constants (shared with march_http.c) ─────────── */

static const char COLON_SP[] = ": ";
static const char CRLF[]     = "\r\n";

/* ── Pre-serialized status lines ─────────────────────────────────────── */

static const char SL_100[] = "HTTP/1.1 100 Continue\r\n";
static const char SL_200[] = "HTTP/1.1 200 OK\r\n";
static const char SL_201[] = "HTTP/1.1 201 Created\r\n";
static const char SL_204[] = "HTTP/1.1 204 No Content\r\n";
static const char SL_301[] = "HTTP/1.1 301 Moved Permanently\r\n";
static const char SL_302[] = "HTTP/1.1 302 Found\r\n";
static const char SL_304[] = "HTTP/1.1 304 Not Modified\r\n";
static const char SL_400[] = "HTTP/1.1 400 Bad Request\r\n";
static const char SL_401[] = "HTTP/1.1 401 Unauthorized\r\n";
static const char SL_403[] = "HTTP/1.1 403 Forbidden\r\n";
static const char SL_404[] = "HTTP/1.1 404 Not Found\r\n";
static const char SL_405[] = "HTTP/1.1 405 Method Not Allowed\r\n";
static const char SL_500[] = "HTTP/1.1 500 Internal Server Error\r\n";
static const char SL_503[] = "HTTP/1.1 503 Service Unavailable\r\n";

/* Return the pre-serialized status line string and its length for code.
 * Returns NULL if the code is not in the table (caller formats it). */
static const char *status_line_static(int code, size_t *len_out) {
#define SL(s)  do { *len_out = sizeof(s) - 1; return (s); } while (0)
    switch (code) {
        case 100: SL(SL_100);
        case 200: SL(SL_200);
        case 201: SL(SL_201);
        case 204: SL(SL_204);
        case 301: SL(SL_301);
        case 302: SL(SL_302);
        case 304: SL(SL_304);
        case 400: SL(SL_400);
        case 401: SL(SL_401);
        case 403: SL(SL_403);
        case 404: SL(SL_404);
        case 405: SL(SL_405);
        case 500: SL(SL_500);
        case 503: SL(SL_503);
        default:  *len_out = 0; return NULL;
    }
#undef SL
}

/* ── Pre-serialized plaintext benchmark response ─────────────────────── */

/* Static headers block for the TechEmpower /plaintext benchmark.
 * Does NOT include "Date:" (filled from cache) or the terminal "\r\n"
 * (added by march_response_set_body).
 *
 * Content-Length: 13 matches sizeof("Hello, World!") - 1. */
const char MARCH_PLAINTEXT_STATIC_HEADERS[] =
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: text/plain\r\n"
    "Content-Length: 13\r\n"
    "Server: March\r\n";

const size_t MARCH_PLAINTEXT_STATIC_HEADERS_LEN =
    sizeof(MARCH_PLAINTEXT_STATIC_HEADERS) - 1;  /* exclude NUL */

const char MARCH_PLAINTEXT_BODY[] = "Hello, World!";
const size_t MARCH_PLAINTEXT_BODY_LEN = sizeof(MARCH_PLAINTEXT_BODY) - 1;

/* ── Thread-local scratch buffer ─────────────────────────────────────── */

/* Each thread gets MARCH_RESPONSE_SCRATCH_SIZE bytes for dynamic content.
 * This is separate from the March GC heap — no malloc on the hot path. */
static _Thread_local char   tls_scratch[MARCH_RESPONSE_SCRATCH_SIZE];

/* Returns a pointer to the calling thread's TLS scratch buffer.
 * Used by the event loop to snapshot scratch bytes before an EAGAIN return
 * so deferred iovecs remain valid across event loop iterations. */
char *march_response_tls_scratch(void) { return tls_scratch; }

/* Allocate `needed` bytes from the calling thread's scratch buffer,
 * advancing the offset stored in resp->scratch_used.
 * Returns a pointer to the allocated region, or NULL if the buffer is full.
 * The pointer is valid until march_response_init() is called again. */
static char *scratch_alloc(march_response_t *resp, size_t needed) {
    if (resp->scratch_used + needed > MARCH_RESPONSE_SCRATCH_SIZE)
        return NULL;
    char *p = tls_scratch + resp->scratch_used;
    resp->scratch_used += needed;
    return p;
}

/* ── Date header cache ────────────────────────────────────────────────── */

/* The cached string includes the header name, value, and \r\n terminator:
 *   "Date: Wed, 25 Mar 2026 12:34:56 GMT\r\n"
 * Double-buffered so readers never see a half-written value. */
#define DATE_BUF_SZ 80

static char            g_date_buf[2][DATE_BUF_SZ];
static size_t          g_date_len[2];
static _Atomic int     g_date_active  = 0;      /* index of current buffer */
static _Atomic time_t  g_date_last_s  = 0;      /* last refresh second */
static pthread_mutex_t g_date_mutex   = PTHREAD_MUTEX_INITIALIZER;

/* Refresh the Date cache for `now`.  Must be called with g_date_mutex held. */
static void refresh_date_locked(time_t now) {
    int next = 1 - atomic_load_explicit(&g_date_active, memory_order_relaxed);
    struct tm tm_val;
    gmtime_r(&now, &tm_val);
    g_date_len[next] = (size_t)strftime(g_date_buf[next], DATE_BUF_SZ,
                                         "Date: %a, %d %b %Y %H:%M:%S GMT\r\n",
                                         &tm_val);
    /* Publish atomically: readers pick up the new buffer on the next load. */
    atomic_store_explicit(&g_date_active, next, memory_order_release);
    atomic_store_explicit(&g_date_last_s, now,  memory_order_release);
}

const char *march_http_cached_date(size_t *len_out) {
    time_t now = time(NULL);

    /* Fast path: cache is still fresh — no lock needed. */
    if (atomic_load_explicit(&g_date_last_s, memory_order_acquire) == now) {
        int idx = atomic_load_explicit(&g_date_active, memory_order_acquire);
        *len_out = g_date_len[idx];
        return g_date_buf[idx];
    }

    /* Slow path: take the lock, re-check, and refresh if still stale. */
    pthread_mutex_lock(&g_date_mutex);
    if (atomic_load_explicit(&g_date_last_s, memory_order_relaxed) != now)
        refresh_date_locked(now);
    pthread_mutex_unlock(&g_date_mutex);

    int idx = atomic_load_explicit(&g_date_active, memory_order_acquire);
    *len_out = g_date_len[idx];
    return g_date_buf[idx];
}

/* ── Module init ─────────────────────────────────────────────────────── */

void march_http_response_module_init(void) {
    /* Pre-populate the Date cache so the first request doesn't pay for it. */
    pthread_mutex_lock(&g_date_mutex);
    time_t now = time(NULL);
    if (atomic_load_explicit(&g_date_last_s, memory_order_relaxed) == 0)
        refresh_date_locked(now);
    pthread_mutex_unlock(&g_date_mutex);
}

/* ── writev helper ────────────────────────────────────────────────────── */

/* Drive writev() to completion, handling EINTR and partial writes. */
static int writev_all_resp(int fd, struct iovec *iov, int iovcnt) {
    while (iovcnt > 0) {
        ssize_t n = writev(fd, iov, iovcnt);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        while (n > 0 && iovcnt > 0) {
            if ((size_t)n >= iov->iov_len) {
                n      -= (ssize_t)iov->iov_len;
                iov++;
                iovcnt--;
            } else {
                iov->iov_base = (char *)iov->iov_base + n;
                iov->iov_len -= (size_t)n;
                n = 0;
            }
        }
    }
    return 0;
}

/* ── Response builder implementation ────────────────────────────────── */

void march_response_init(march_response_t *resp) {
    resp->iov_count   = 0;
    resp->scratch_used = 0;
}

/* Append one iovec entry; silently drops if array is full. */
static inline void push_iov(march_response_t *resp,
                              const void *base, size_t len) {
    if (resp->iov_count < MARCH_RESPONSE_MAX_IOVEC) {
        resp->iov[resp->iov_count].iov_base = (void *)base;
        resp->iov[resp->iov_count].iov_len  = len;
        resp->iov_count++;
    }
}

void march_response_set_status(march_response_t *resp, int status_code) {
    size_t     len = 0;
    const char *sl = status_line_static(status_code, &len);
    if (sl) {
        push_iov(resp, sl, len);
        return;
    }
    /* Unknown code: format into scratch buffer. */
    char *buf = scratch_alloc(resp, 64);
    if (!buf) return;   /* scratch full — skip silently */
    int n = snprintf(buf, 64, "HTTP/1.1 %d Unknown\r\n", status_code);
    if (n > 0) push_iov(resp, buf, (size_t)n);
}

void march_response_add_header(march_response_t *resp,
                                const char *name,  size_t name_len,
                                const char *value, size_t value_len) {
    push_iov(resp, name,      name_len);
    push_iov(resp, COLON_SP,  2);
    push_iov(resp, value,     value_len);
    push_iov(resp, CRLF,      2);
}

void march_response_add_date_header(march_response_t *resp) {
    size_t     len  = 0;
    const char *hdr = march_http_cached_date(&len);
    if (hdr && len > 0) push_iov(resp, hdr, len);
}

void march_response_set_body(march_response_t *resp,
                              const char *data, size_t len) {
    /* Format Content-Length into scratch. */
    char *cl_buf = scratch_alloc(resp, 48);
    if (cl_buf) {
        int n = snprintf(cl_buf, 48, "Content-Length: %zu\r\n", len);
        if (n > 0) push_iov(resp, cl_buf, (size_t)n);
    }

    /* Blank line terminating headers. */
    push_iov(resp, CRLF, 2);

    /* Body (skip if empty). */
    if (len > 0 && data) push_iov(resp, data, len);
}

int march_response_send(march_response_t *resp, int fd) {
    if (resp->iov_count == 0) return 0;
    return writev_all_resp(fd, resp->iov, resp->iov_count);
}

void march_response_clear_no_free(march_response_t *resp) {
    resp->iov_count = 0;
    /* scratch_used intentionally NOT reset — the caller manages the scratch
     * lifetime and may still have live iovecs pointing into scratch[0..used]. */
}

/* ── Plaintext fast path ──────────────────────────────────────────────── */

int march_response_send_plaintext(int fd) {
    /* iov layout:
     *   [0]  static headers (status + Content-Type + Content-Length + Server)
     *   [1]  cached Date header
     *   [2]  "\r\n"  (blank line, end of headers)
     *   [3]  "Hello, World!"
     */
    size_t     date_len = 0;
    const char *date    = march_http_cached_date(&date_len);

    struct iovec iov[4];
    iov[0].iov_base = (void *)MARCH_PLAINTEXT_STATIC_HEADERS;
    iov[0].iov_len  = MARCH_PLAINTEXT_STATIC_HEADERS_LEN;
    iov[1].iov_base = (void *)date;
    iov[1].iov_len  = date_len;
    iov[2].iov_base = (void *)CRLF;
    iov[2].iov_len  = 2;
    iov[3].iov_base = (void *)MARCH_PLAINTEXT_BODY;
    iov[3].iov_len  = MARCH_PLAINTEXT_BODY_LEN;

    int iovcnt = (date_len > 0) ? 4 : 3;
    if (date_len == 0) {
        /* No Date — collapse: static headers → CRLF → body */
        iov[1] = iov[2];
        iov[2] = iov[3];
    }

    return writev_all_resp(fd, iov, iovcnt);
}
