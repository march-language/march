/* test/test_http_response.c — Tests for the zero-copy HTTP response builder.
 *
 * Compile and run (standalone):
 *   cc -std=gnu11 -Wall -Wextra -I../runtime \
 *      test_http_response.c \
 *      ../runtime/march_http_response.c \
 *      -lpthread -o test_http_response
 *   ./test_http_response
 *
 * Also built and run via `dune runtest` (see test/dune).
 */

#include "march_http_response.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include <sys/socket.h>
#include <time.h>
#include <pthread.h>

/* ── Test harness ─────────────────────────────────────────────────────── */

static int g_total  = 0;
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond)                                                         \
    do {                                                                    \
        g_total++;                                                          \
        if (cond) {                                                         \
            g_passed++;                                                     \
        } else {                                                            \
            g_failed++;                                                     \
            fprintf(stderr, "FAIL [%s:%d] %s\n", __FILE__, __LINE__, #cond); \
        }                                                                   \
    } while (0)

#define CHECK_STR_EQ(got, got_len, expected)                               \
    do {                                                                    \
        size_t _elen = strlen(expected);                                    \
        CHECK((got_len) == _elen &&                                         \
              memcmp((got), (expected), _elen) == 0);                       \
    } while (0)

/* ── Socket-pair helper ──────────────────────────────────────────────── */

/* Open a connected Unix socket pair.  Writes to sv[1] are readable from
 * sv[0].  Returns 0 on success, -1 on failure. */
static int make_socketpair(int sv[2]) {
    return socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
}

/* Read exactly n bytes from fd into buf.  Returns n on success, < n on EOF
 * or error. */
static ssize_t read_all(int fd, char *buf, size_t n) {
    size_t total = 0;
    while (total < n) {
        ssize_t r = read(fd, buf + total, n - total);
        if (r <= 0) break;
        total += (size_t)r;
    }
    return (ssize_t)total;
}

/* ── 1. module init is safe to call multiple times ───────────────────── */

static void test_module_init_idempotent(void) {
    march_http_response_module_init();
    march_http_response_module_init();
    march_http_response_module_init();
    CHECK(1);  /* should not crash */
}

/* ── 2. march_response_init resets state ─────────────────────────────── */

static void test_response_init(void) {
    march_response_t resp;
    /* Pre-dirty the struct */
    memset(&resp, 0xFF, sizeof(resp));
    march_response_init(&resp);
    CHECK(resp.iov_count    == 0);
    CHECK(resp.scratch_used == 0);
}

/* ── 3. Set status 200 uses pre-serialized string ────────────────────── */

static void test_set_status_200(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_set_status(&resp, 200);
    CHECK(resp.iov_count == 1);
    /* The iov should point directly at SL_200 — not into scratch. */
    const char *base = (const char *)resp.iov[0].iov_base;
    size_t      len  = resp.iov[0].iov_len;
    CHECK_STR_EQ(base, len, "HTTP/1.1 200 OK\r\n");
    /* No scratch consumed for static status lines. */
    CHECK(resp.scratch_used == 0);
}

/* ── 4. Set status 404 uses pre-serialized string ────────────────────── */

static void test_set_status_404(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_set_status(&resp, 404);
    CHECK(resp.iov_count == 1);
    const char *base = (const char *)resp.iov[0].iov_base;
    size_t      len  = resp.iov[0].iov_len;
    CHECK_STR_EQ(base, len, "HTTP/1.1 404 Not Found\r\n");
}

/* ── 5. Unknown status code is formatted into scratch ────────────────── */

static void test_set_status_unknown(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_set_status(&resp, 418);
    CHECK(resp.iov_count == 1);
    /* Should begin with "HTTP/1.1 418" */
    const char *base = (const char *)resp.iov[0].iov_base;
    size_t      len  = resp.iov[0].iov_len;
    CHECK(len >= 12);
    CHECK(memcmp(base, "HTTP/1.1 418", 12) == 0);
    /* Scratch was used for this one. */
    CHECK(resp.scratch_used > 0);
}

/* ── 6. add_header produces 4 iovec entries ──────────────────────────── */

static void test_add_header(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_add_header(&resp,
                               "Content-Type", 12,
                               "text/html",    9);
    CHECK(resp.iov_count == 4);
    /* name */
    CHECK(resp.iov[0].iov_len == 12);
    CHECK(memcmp(resp.iov[0].iov_base, "Content-Type", 12) == 0);
    /* ": " */
    CHECK(resp.iov[1].iov_len == 2);
    CHECK(memcmp(resp.iov[1].iov_base, ": ", 2) == 0);
    /* value */
    CHECK(resp.iov[2].iov_len == 9);
    CHECK(memcmp(resp.iov[2].iov_base, "text/html", 9) == 0);
    /* "\r\n" */
    CHECK(resp.iov[3].iov_len == 2);
    CHECK(memcmp(resp.iov[3].iov_base, "\r\n", 2) == 0);
}

/* ── 7. add_date_header appends one iov entry with a valid Date value ── */

static void test_add_date_header(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_add_date_header(&resp);
    CHECK(resp.iov_count == 1);
    const char *base = (const char *)resp.iov[0].iov_base;
    size_t      len  = resp.iov[0].iov_len;
    /* Must start with "Date: " and end with "GMT\r\n" */
    CHECK(len > 6);
    CHECK(memcmp(base, "Date: ", 6) == 0);
    CHECK(len >= 5 && memcmp(base + len - 5, "GMT\r\n", 5) == 0);
}

/* ── 8. set_body appends CL header + CRLF + body ────────────────────── */

static void test_set_body(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_set_body(&resp, "Hello", 5);

    /* At least: Content-Length line (1), CRLF (1), body (1) = 3 */
    CHECK(resp.iov_count >= 3);

    /* Find the Content-Length iov (first one). */
    const char *cl = (const char *)resp.iov[0].iov_base;
    size_t      cll = resp.iov[0].iov_len;
    CHECK(cll >= 16);
    CHECK(memcmp(cl, "Content-Length: ", 16) == 0);
    /* Should contain "5" somewhere */
    CHECK(memchr(cl, '5', cll) != NULL);

    /* CRLF separator */
    CHECK(resp.iov[1].iov_len == 2);
    CHECK(memcmp(resp.iov[1].iov_base, "\r\n", 2) == 0);

    /* Body */
    CHECK(resp.iov[2].iov_len == 5);
    CHECK(memcmp(resp.iov[2].iov_base, "Hello", 5) == 0);
}

/* ── 9. set_body with len=0 emits CL:0 + CRLF, no body iov ─────────── */

static void test_set_body_empty(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_set_body(&resp, NULL, 0);

    /* Content-Length: 0\r\n  +  \r\n  — exactly 2 iovecs */
    CHECK(resp.iov_count == 2);

    const char *cl  = (const char *)resp.iov[0].iov_base;
    size_t      cll = resp.iov[0].iov_len;
    CHECK(memchr(cl, '0', cll) != NULL);

    CHECK(resp.iov[1].iov_len == 2);
    CHECK(memcmp(resp.iov[1].iov_base, "\r\n", 2) == 0);
}

/* ── 10. Full response round-trip via socket pair ────────────────────── */

static void test_full_response_roundtrip(void) {
    int sv[2];
    if (make_socketpair(sv) != 0) {
        fprintf(stderr, "  [skip] socketpair failed\n");
        CHECK(1);   /* not a failure of our code */
        return;
    }

    march_response_t resp;
    march_response_init(&resp);
    march_response_set_status(&resp, 200);
    march_response_add_header(&resp, "Content-Type", 12, "text/plain", 10);
    march_response_add_date_header(&resp);
    march_response_set_body(&resp, "Hi", 2);
    int r = march_response_send(&resp, sv[1]);
    close(sv[1]);

    CHECK(r == 0);

    /* Read the response back. */
    char buf[1024];
    ssize_t total = read_all(sv[0], buf, sizeof(buf) - 1);
    close(sv[0]);
    buf[total] = '\0';

    CHECK(total > 0);
    CHECK(memcmp(buf, "HTTP/1.1 200 OK\r\n", 17) == 0);
    CHECK(strstr(buf, "Content-Type: text/plain\r\n") != NULL);
    CHECK(strstr(buf, "Date: ")  != NULL);
    CHECK(strstr(buf, "Content-Length: 2\r\n") != NULL);
    /* Body follows the blank line */
    const char *blank = strstr(buf, "\r\n\r\n");
    CHECK(blank != NULL);
    if (blank) {
        const char *body = blank + 4;
        CHECK(memcmp(body, "Hi", 2) == 0);
    }
}

/* ── 11. march_response_send_plaintext produces valid HTTP ───────────── */

static void test_plaintext_fast_path(void) {
    int sv[2];
    if (make_socketpair(sv) != 0) {
        fprintf(stderr, "  [skip] socketpair failed\n");
        CHECK(1);
        return;
    }

    int r = march_response_send_plaintext(sv[1]);
    close(sv[1]);

    CHECK(r == 0);

    char buf[1024];
    ssize_t total = read_all(sv[0], buf, sizeof(buf) - 1);
    close(sv[0]);
    buf[total] = '\0';

    CHECK(total > 0);
    CHECK(memcmp(buf, "HTTP/1.1 200 OK\r\n", 17) == 0);
    CHECK(strstr(buf, "Content-Type: text/plain\r\n") != NULL);
    CHECK(strstr(buf, "Content-Length: 13\r\n")       != NULL);
    CHECK(strstr(buf, "Server: March\r\n")             != NULL);
    /* Body */
    const char *blank = strstr(buf, "\r\n\r\n");
    CHECK(blank != NULL);
    if (blank) {
        const char *body = blank + 4;
        CHECK(memcmp(body, "Hello, World!", 13) == 0);
    }
}

/* ── 12. Plaintext static headers constant is well-formed ────────────── */

static void test_plaintext_static_headers_const(void) {
    /* LEN must match actual string length. */
    CHECK(MARCH_PLAINTEXT_STATIC_HEADERS_LEN == strlen(MARCH_PLAINTEXT_STATIC_HEADERS));
    CHECK(MARCH_PLAINTEXT_BODY_LEN == strlen(MARCH_PLAINTEXT_BODY));
    /* Content of the body. */
    CHECK(memcmp(MARCH_PLAINTEXT_BODY, "Hello, World!", 13) == 0);
}

/* ── 13. Date cache returns non-empty string ─────────────────────────── */

static void test_date_cache_non_empty(void) {
    size_t len = 0;
    const char *d = march_http_cached_date(&len);
    CHECK(d   != NULL);
    CHECK(len >  6);
    CHECK(memcmp(d, "Date: ", 6) == 0);
}

/* ── 14. Date cache returns same pointer within the same second ───────── */

static void test_date_cache_stable_within_second(void) {
    size_t len1 = 0, len2 = 0;
    const char *d1 = march_http_cached_date(&len1);
    const char *d2 = march_http_cached_date(&len2);
    /* Both calls within the same second — should use the same buffer. */
    CHECK(d1  != NULL);
    CHECK(d2  != NULL);
    CHECK(len1 == len2);
    CHECK(memcmp(d1, d2, len1) == 0);
}

/* ── 15. Multiple headers accumulate correctly ───────────────────────── */

static void test_multiple_headers(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_set_status(&resp, 201);
    march_response_add_header(&resp, "X-A", 3, "1", 1);
    march_response_add_header(&resp, "X-B", 3, "2", 1);
    march_response_add_header(&resp, "X-C", 3, "3", 1);
    /* 1 (status) + 3*4 (headers) = 13 */
    CHECK(resp.iov_count == 13);
}

/* ── 16. march_response_send on empty iov array is a no-op ──────────── */

static void test_send_empty_noop(void) {
    int sv[2];
    if (make_socketpair(sv) != 0) { CHECK(1); return; }

    march_response_t resp;
    march_response_init(&resp);
    int r = march_response_send(&resp, sv[1]);
    close(sv[1]);

    CHECK(r == 0);

    /* No bytes written — read should return 0 (EOF). */
    char buf[16];
    ssize_t n = read(sv[0], buf, sizeof(buf));
    close(sv[0]);
    CHECK(n == 0);
}

/* ── 17. 404 response round-trip ─────────────────────────────────────── */

static void test_404_roundtrip(void) {
    int sv[2];
    if (make_socketpair(sv) != 0) { CHECK(1); return; }

    march_response_t resp;
    march_response_init(&resp);
    march_response_set_status(&resp, 404);
    march_response_set_body(&resp, "Not Found", 9);
    march_response_send(&resp, sv[1]);
    close(sv[1]);

    char buf[512];
    ssize_t total = read_all(sv[0], buf, sizeof(buf) - 1);
    close(sv[0]);
    buf[total] = '\0';

    CHECK(memcmp(buf, "HTTP/1.1 404 Not Found\r\n", 24) == 0);
    CHECK(strstr(buf, "Content-Length: 9\r\n") != NULL);
    const char *blank = strstr(buf, "\r\n\r\n");
    CHECK(blank != NULL);
    if (blank) CHECK(memcmp(blank + 4, "Not Found", 9) == 0);
}

/* ── 18. Scratch buffer survives reinit ──────────────────────────────── */

static void test_scratch_reinit(void) {
    march_response_t resp;
    march_response_init(&resp);
    march_response_set_status(&resp, 418);   /* uses scratch */
    size_t used_after_first = resp.scratch_used;
    CHECK(used_after_first > 0);

    /* Reinit resets scratch. */
    march_response_init(&resp);
    CHECK(resp.scratch_used == 0);

    /* Can format another dynamic status into scratch. */
    march_response_set_status(&resp, 418);
    CHECK(resp.scratch_used == used_after_first);
}

/* ── 19. Pre-serialized plaintext body length matches Content-Length ─── */

static void test_plaintext_cl_matches_body(void) {
    /* MARCH_PLAINTEXT_STATIC_HEADERS contains "Content-Length: 13\r\n"
     * and MARCH_PLAINTEXT_BODY_LEN == 13. */
    CHECK(MARCH_PLAINTEXT_BODY_LEN == 13);
    CHECK(strstr(MARCH_PLAINTEXT_STATIC_HEADERS, "Content-Length: 13\r\n") != NULL);
}

/* ── 20. Thread-safety smoke test for Date cache ─────────────────────── */

#define DATE_THREADS 8
#define DATE_ITERS   1000

static void *date_thread(void *arg) {
    (void)arg;
    for (int i = 0; i < DATE_ITERS; i++) {
        size_t len = 0;
        const char *d = march_http_cached_date(&len);
        if (!d || len == 0 || memcmp(d, "Date: ", 6) != 0)
            return (void *)(intptr_t)1;  /* failure */
    }
    return NULL;
}

static void test_date_cache_thread_safe(void) {
    pthread_t threads[DATE_THREADS];
    for (int i = 0; i < DATE_THREADS; i++)
        pthread_create(&threads[i], NULL, date_thread, NULL);
    int ok = 1;
    for (int i = 0; i < DATE_THREADS; i++) {
        void *ret;
        pthread_join(threads[i], &ret);
        if (ret) ok = 0;
    }
    CHECK(ok);
}

/* ── main ────────────────────────────────────────────────────────────── */

int main(void) {
    printf("march_http_response tests\n");
    printf("==========================\n");

    march_http_response_module_init();

    test_module_init_idempotent();
    test_response_init();
    test_set_status_200();
    test_set_status_404();
    test_set_status_unknown();
    test_add_header();
    test_add_date_header();
    test_set_body();
    test_set_body_empty();
    test_full_response_roundtrip();
    test_plaintext_fast_path();
    test_plaintext_static_headers_const();
    test_date_cache_non_empty();
    test_date_cache_stable_within_second();
    test_multiple_headers();
    test_send_empty_noop();
    test_404_roundtrip();
    test_scratch_reinit();
    test_plaintext_cl_matches_body();
    test_date_cache_thread_safe();

    printf("\n%d/%d passed", g_passed, g_total);
    if (g_failed) printf(", %d FAILED", g_failed);
    printf("\n");

    return g_failed ? 1 : 0;
}
