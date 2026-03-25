/* test/test_http_simd.c — C tests for SIMD HTTP parser.
 *
 * Compile and run:
 *   cc -std=gnu11 -Wall -Wextra -I../runtime -msse4.2 \
 *      test_http_simd.c ../runtime/march_http_parse_simd.c -o test_http_simd
 *   ./test_http_simd
 *
 * On ARM64 (no SSE4.2) drop -msse4.2; scalar fallback is used automatically.
 */

#include "march_http_parse_simd.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

/* ── Test harness ─────────────────────────────────────────────────────── */

static int g_total   = 0;
static int g_passed  = 0;
static int g_failed  = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        g_total++;                                                      \
        if (cond) {                                                     \
            g_passed++;                                                 \
        } else {                                                        \
            g_failed++;                                                 \
            fprintf(stderr, "FAIL [%s:%d] %s\n", __FILE__, __LINE__, #cond); \
        }                                                               \
    } while (0)

#define CHECK_STR_EQ(ptr, len, expected)                                \
    do {                                                                \
        size_t elen = strlen(expected);                                 \
        CHECK((len) == elen && memcmp((ptr), (expected), elen) == 0);  \
    } while (0)

/* ── Helpers ──────────────────────────────────────────────────────────── */

/* Find header by name (case-sensitive for simplicity in tests). */
static const march_http_header_t *
find_header(const march_http_request_t *req, const char *name) {
    size_t nlen = strlen(name);
    for (size_t i = 0; i < req->num_headers; i++) {
        if (req->headers[i].name_len == nlen &&
            memcmp(req->headers[i].name, name, nlen) == 0)
            return &req->headers[i];
    }
    return NULL;
}

/* ── Test cases ───────────────────────────────────────────────────────── */

/* 1. Minimal GET request */
static void test_get_minimal(void) {
    const char *req_str = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n";
    march_http_request_t req;

    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r > 0);
    CHECK_STR_EQ(req.method, req.method_len, "GET");
    CHECK_STR_EQ(req.path, req.path_len, "/");
    CHECK(req.minor_version == 1);
    CHECK(req.num_headers == 1);
    CHECK_STR_EQ(req.headers[0].name,  req.headers[0].name_len,  "Host");
    CHECK_STR_EQ(req.headers[0].value, req.headers[0].value_len, "example.com");
    CHECK((size_t)r == strlen(req_str));
}

/* 2. GET with longer path and multiple headers */
static void test_get_multi_headers(void) {
    const char *req_str =
        "GET /api/v1/users?page=1&limit=10 HTTP/1.1\r\n"
        "Host: api.example.com\r\n"
        "Accept: application/json\r\n"
        "Authorization: Bearer tok123\r\n"
        "Connection: keep-alive\r\n"
        "\r\n";

    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r > 0);
    CHECK_STR_EQ(req.method, req.method_len, "GET");
    CHECK_STR_EQ(req.path, req.path_len, "/api/v1/users?page=1&limit=10");
    CHECK(req.minor_version == 1);
    CHECK(req.num_headers == 4);

    const march_http_header_t *auth = find_header(&req, "Authorization");
    CHECK(auth != NULL);
    if (auth) CHECK_STR_EQ(auth->value, auth->value_len, "Bearer tok123");

    const march_http_header_t *conn = find_header(&req, "Connection");
    CHECK(conn != NULL);
    if (conn) CHECK_STR_EQ(conn->value, conn->value_len, "keep-alive");
}

/* 3. POST request with body (parser only reads headers) */
static void test_post_with_body(void) {
    const char *req_str =
        "POST /login HTTP/1.1\r\n"
        "Host: example.com\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
        "Content-Length: 29\r\n"
        "\r\n"
        "username=admin&password=secret";

    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r > 0);
    CHECK_STR_EQ(req.method, req.method_len, "POST");
    CHECK_STR_EQ(req.path, req.path_len, "/login");
    CHECK(req.num_headers == 3);

    /* header_end should point just before the body */
    const char *body_start = req_str + r;
    CHECK(memcmp(body_start, "username=admin", 14) == 0);

    const march_http_header_t *ct = find_header(&req, "Content-Type");
    CHECK(ct != NULL);
    if (ct) CHECK_STR_EQ(ct->value, ct->value_len,
                         "application/x-www-form-urlencoded");
}

/* 4. HTTP/1.0 request */
static void test_http10(void) {
    const char *req_str = "GET /index.html HTTP/1.0\r\n\r\n";
    march_http_request_t req;

    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r > 0);
    CHECK(req.minor_version == 0);
    CHECK(req.num_headers == 0);
}

/* 5. Various HTTP methods */
static void test_methods(void) {
    static const char *methods[] = {
        "DELETE", "PUT", "PATCH", "OPTIONS", "HEAD", NULL
    };
    for (int i = 0; methods[i]; i++) {
        char buf[256];
        snprintf(buf, sizeof(buf),
                 "%s /resource HTTP/1.1\r\nHost: x\r\n\r\n", methods[i]);
        march_http_request_t req;
        int r = march_http_parse_request_simd(buf, strlen(buf), &req);
        CHECK(r > 0);
        CHECK(req.method_len == strlen(methods[i]));
        CHECK(memcmp(req.method, methods[i], req.method_len) == 0);
    }
}

/* 6. Pipelined requests — two requests in one buffer */
static void test_pipelined_two(void) {
    const char *req_str =
        "GET /a HTTP/1.1\r\nHost: x\r\n\r\n"
        "GET /b HTTP/1.1\r\nHost: y\r\n\r\n";

    march_http_request_t reqs[8];
    size_t consumed = 0;
    int n = march_http_parse_pipelined(req_str, strlen(req_str),
                                        reqs, 8, &consumed);
    CHECK(n == 2);
    CHECK(consumed == strlen(req_str));
    CHECK_STR_EQ(reqs[0].path, reqs[0].path_len, "/a");
    CHECK_STR_EQ(reqs[1].path, reqs[1].path_len, "/b");
}

/* 7. Pipelined — max_reqs cap */
static void test_pipelined_cap(void) {
    const char *req_str =
        "GET /a HTTP/1.1\r\nHost: x\r\n\r\n"
        "GET /b HTTP/1.1\r\nHost: y\r\n\r\n"
        "GET /c HTTP/1.1\r\nHost: z\r\n\r\n";

    march_http_request_t reqs[2];
    size_t consumed = 0;
    int n = march_http_parse_pipelined(req_str, strlen(req_str),
                                        reqs, 2, &consumed);
    /* Only 2 parsed due to max_reqs=2 */
    CHECK(n == 2);
    CHECK_STR_EQ(reqs[0].path, reqs[0].path_len, "/a");
    CHECK_STR_EQ(reqs[1].path, reqs[1].path_len, "/b");
    /* consumed should be length of first two requests */
    size_t first_two = strlen("GET /a HTTP/1.1\r\nHost: x\r\n\r\n"
                              "GET /b HTTP/1.1\r\nHost: y\r\n\r\n");
    CHECK(consumed == first_two);
}

/* 8. Malformed input — bad HTTP version */
static void test_malformed_version(void) {
    const char *req_str = "GET / HTTP/2.0\r\nHost: x\r\n\r\n";
    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r == -1);
}

/* 9. Malformed — invalid method (contains digit) */
static void test_malformed_method(void) {
    const char *req_str = "G3T / HTTP/1.1\r\nHost: x\r\n\r\n";
    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r == -1);
}

/* 10. Malformed — missing path */
static void test_malformed_empty_path(void) {
    const char *req_str = "GET  HTTP/1.1\r\nHost: x\r\n\r\n";
    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    /* Either -1 (error) or 0 (incomplete) — must not be positive */
    CHECK(r <= 0);
}

/* 11. Partial request — incomplete headers */
static void test_partial_headers(void) {
    /* Truncated mid-header, no \r\n\r\n yet */
    const char *req_str = "GET / HTTP/1.1\r\nHost: exam";
    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r == 0);
}

/* 12. Partial request — truncated request line */
static void test_partial_request_line(void) {
    const char *req_str = "GET /path";
    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r == 0);
}

/* 13. Empty input */
static void test_empty_input(void) {
    march_http_request_t req;
    int r = march_http_parse_request_simd("", 0, &req);
    CHECK(r == -1);
}

/* 14. NULL input */
static void test_null_input(void) {
    march_http_request_t req;
    int r = march_http_parse_request_simd(NULL, 0, &req);
    CHECK(r == -1);
}

/* 15. Header with leading/trailing whitespace trimming */
static void test_header_whitespace(void) {
    const char *req_str =
        "GET / HTTP/1.1\r\n"
        "X-Custom:   hello world   \r\n"
        "\r\n";
    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r > 0);
    CHECK(req.num_headers == 1);
    /* Leading whitespace trimmed */
    CHECK_STR_EQ(req.headers[0].value, req.headers[0].value_len,
                 "hello world");
}

/* 16. Large request with many headers */
static void test_many_headers(void) {
    char buf[4096];
    int pos = snprintf(buf, sizeof(buf), "GET / HTTP/1.1\r\n");

    for (int i = 0; i < 20; i++) {
        pos += snprintf(buf + pos, sizeof(buf) - (size_t)pos,
                        "X-Header-%d: value%d\r\n", i, i);
    }
    pos += snprintf(buf + pos, sizeof(buf) - (size_t)pos, "\r\n");

    march_http_request_t req;
    int r = march_http_parse_request_simd(buf, (size_t)pos, &req);
    CHECK(r > 0);
    CHECK(req.num_headers == 20);
}

/* 17. SIMD availability report (informational, always passes) */
static void test_simd_available(void) {
    int avail = march_http_simd_available();
    printf("  [info] SSE4.2 SIMD fast path: %s\n",
           avail ? "ENABLED" : "disabled (scalar fallback)");
    CHECK(1); /* always pass — just log */
}

/* 18. Pipelined empty buffer */
static void test_pipelined_empty(void) {
    march_http_request_t reqs[4];
    size_t consumed = 0;
    int n = march_http_parse_pipelined("", 0, reqs, 4, &consumed);
    CHECK(n == 0);
    CHECK(consumed == 0);
}

/* 19. Header limit enforcement */
static void test_header_limit(void) {
    char buf[8192];
    int pos = snprintf(buf, sizeof(buf), "GET / HTTP/1.1\r\n");
    /* Generate more than MARCH_HTTP_MAX_HEADERS headers */
    for (int i = 0; i < MARCH_HTTP_MAX_HEADERS + 5; i++) {
        pos += snprintf(buf + pos, sizeof(buf) - (size_t)pos,
                        "X-H-%d: v\r\n", i);
    }
    pos += snprintf(buf + pos, sizeof(buf) - (size_t)pos, "\r\n");

    march_http_request_t req;
    int r = march_http_parse_request_simd(buf, (size_t)pos, &req);
    /* Must either succeed (capping at MARCH_HTTP_MAX_HEADERS) or error */
    if (r > 0) {
        CHECK(req.num_headers == MARCH_HTTP_MAX_HEADERS);
    } else {
        CHECK(r == -1);
    }
}

/* 20. POST request to /plaintext with typical TechEmpower headers */
static void test_techempower_plaintext(void) {
    const char *req_str =
        "GET /plaintext HTTP/1.1\r\n"
        "Host: tfb-server\r\n"
        "Accept: text/plain,text/html;q=0.9,*/*;q=0.8\r\n"
        "Accept-Language: en-US,en;q=0.5\r\n"
        "Connection: keep-alive\r\n"
        "\r\n";

    march_http_request_t req;
    int r = march_http_parse_request_simd(req_str, strlen(req_str), &req);
    CHECK(r > 0);
    CHECK_STR_EQ(req.method, req.method_len, "GET");
    CHECK_STR_EQ(req.path, req.path_len, "/plaintext");
    CHECK(req.num_headers == 4);
    CHECK(req.minor_version == 1);
}

/* ── main ──────────────────────────────────────────────────────────────── */

int main(void) {
    printf("march_http_parse_simd tests\n");
    printf("============================\n");

    test_get_minimal();
    test_get_multi_headers();
    test_post_with_body();
    test_http10();
    test_methods();
    test_pipelined_two();
    test_pipelined_cap();
    test_malformed_version();
    test_malformed_method();
    test_malformed_empty_path();
    test_partial_headers();
    test_partial_request_line();
    test_empty_input();
    test_null_input();
    test_header_whitespace();
    test_many_headers();
    test_simd_available();
    test_pipelined_empty();
    test_header_limit();
    test_techempower_plaintext();

    printf("\n%d/%d passed", g_passed, g_total);
    if (g_failed) printf(", %d FAILED", g_failed);
    printf("\n");

    return g_failed ? 1 : 0;
}
