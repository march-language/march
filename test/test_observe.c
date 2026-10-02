/* test_observe.c — the observe socket and its JSON writer (R0 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md).
 *
 * Links runtime/march_observe.c alone: R0's server needs no scheduler, so the
 * harness starts it in-process with march_observe_server_start and drives it
 * as a client, the way test_reload_activate4.c drives the reload server.
 * Every reply is checked to be valid JSON by a small validator below. */
#define _GNU_SOURCE
#include "march_observe.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int failures, checks;

#define CHECK(cond, ...) do { \
    checks++; \
    if (!(cond)) { failures++; fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); \
                   fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } \
} while (0)

/* ── A minimal JSON validator (RFC 8259 grammar, no semantic checks) ───── */

static const char *js_ws(const char *p) { while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++; return p; }
static const char *js_value(const char *p, int depth);

static const char *js_string(const char *p) {
    if (*p != '"') return NULL;
    p++;
    while (*p && *p != '"') {
        if ((unsigned char)*p < 0x20) return NULL;
        if (*p == '\\') {
            p++;
            if (*p == 'u') {
                for (int i = 1; i <= 4; i++) {
                    char c = p[i];
                    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return NULL;
                }
                p += 5;
                continue;
            }
            if (!strchr("\"\\/bfnrt", *p)) return NULL;
        }
        p++;
    }
    return *p == '"' ? p + 1 : NULL;
}

static const char *js_number(const char *p) {
    const char *s = p;
    if (*p == '-') p++;
    if (*p == '0') p++;
    else if (*p >= '1' && *p <= '9') while (*p >= '0' && *p <= '9') p++;
    else return NULL;
    if (*p == '.') { p++; if (!(*p >= '0' && *p <= '9')) return NULL; while (*p >= '0' && *p <= '9') p++; }
    if (*p == 'e' || *p == 'E') {
        p++;
        if (*p == '+' || *p == '-') p++;
        if (!(*p >= '0' && *p <= '9')) return NULL;
        while (*p >= '0' && *p <= '9') p++;
    }
    return p > s ? p : NULL;
}

static const char *js_value(const char *p, int depth) {
    if (depth > 64) return NULL;
    p = js_ws(p);
    if (*p == '{') {
        p = js_ws(p + 1);
        if (*p == '}') return p + 1;
        for (;;) {
            p = js_string(js_ws(p)); if (!p) return NULL;
            p = js_ws(p); if (*p != ':') return NULL;
            p = js_value(p + 1, depth + 1); if (!p) return NULL;
            p = js_ws(p);
            if (*p == ',') { p++; continue; }
            return *p == '}' ? p + 1 : NULL;
        }
    }
    if (*p == '[') {
        p = js_ws(p + 1);
        if (*p == ']') return p + 1;
        for (;;) {
            p = js_value(p, depth + 1); if (!p) return NULL;
            p = js_ws(p);
            if (*p == ',') { p++; continue; }
            return *p == ']' ? p + 1 : NULL;
        }
    }
    if (*p == '"') return js_string(p);
    if (!strncmp(p, "true", 4)) return p + 4;
    if (!strncmp(p, "false", 5)) return p + 5;
    if (!strncmp(p, "null", 4)) return p + 4;
    return js_number(p);
}

static int is_json(const char *s) {
    const char *e = js_value(s, 0);
    return e && *js_ws(e) == '\0';
}

/* ── JSON writer ───────────────────────────────────────────────────────── */

static void test_writer(void) {
    march_jw w;

    march_jw_init(&w, 1 << 16);
    march_jw_obj_begin(&w);
    march_jw_key(&w, "a"); march_jw_i64(&w, -3);
    march_jw_key(&w, "b"); march_jw_arr_begin(&w);
        march_jw_u64(&w, 18446744073709551615ULL); march_jw_bool(&w, 1); march_jw_null(&w);
        march_jw_obj_begin(&w); march_jw_obj_end(&w);
        march_jw_arr_begin(&w); march_jw_arr_end(&w);
    march_jw_arr_end(&w);
    march_jw_key(&w, "c"); march_jw_f64(&w, 0.5);
    march_jw_obj_end(&w);
    CHECK(march_jw_ok(&w), "nested document ok");
    CHECK(!strcmp(march_jw_text(&w),
                  "{\"a\":-3,\"b\":[18446744073709551615,true,null,{},[]],\"c\":0.5}"),
          "nested document text: %s", march_jw_text(&w));
    march_jw_free(&w);

    march_jw_init(&w, 1 << 16);
    march_jw_str(&w, "q\"b\\n\nt\tc\x01" "\xc3\xa9");
    CHECK(!strcmp(march_jw_text(&w), "\"q\\\"b\\\\n\\nt\\tc\\u0001\xc3\xa9\""),
          "string escaping: %s", march_jw_text(&w));
    CHECK(is_json(march_jw_text(&w)), "escaped string is JSON");
    march_jw_free(&w);

    march_jw_init(&w, 1 << 16);
    march_jw_arr_begin(&w);
    march_jw_f64(&w, 1.0 / 0.0); march_jw_f64(&w, 0.0 / 0.0);
    march_jw_arr_end(&w);
    CHECK(!strcmp(march_jw_text(&w), "[null,null]"), "non-finite floats: %s", march_jw_text(&w));
    march_jw_free(&w);

    march_jw_init(&w, 16);
    march_jw_arr_begin(&w);
    for (int i = 0; i < 100; i++) march_jw_i64(&w, i);
    march_jw_arr_end(&w);
    CHECK(w.truncated && !march_jw_ok(&w), "limit sets truncated");
    CHECK(w.len <= 16, "never writes past the limit (len %zu)", w.len);
    march_jw_free(&w);

    march_jw_init(&w, 1 << 16);
    march_jw_obj_begin(&w);
    CHECK(!march_jw_ok(&w), "an unclosed object is not ok");
    march_jw_free(&w);
}

/* ── Socket client helpers ─────────────────────────────────────────────── */

static int connect_sock(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    snprintf(a.sun_path, sizeof a.sun_path, "%s", path);
    struct timeval tv = { 3, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    if (connect(fd, (struct sockaddr *)&a, sizeof a) < 0) { close(fd); return -1; }
    return fd;
}

/* Read until the peer closes; returns the text without a trailing newline. */
static char *read_all(int fd) {
    size_t cap = 4096, len = 0;
    char *buf = malloc(cap);
    for (;;) {
        if (len + 1 >= cap) { cap *= 2; buf = realloc(buf, cap); }
        ssize_t k = recv(fd, buf + len, cap - len - 1, 0);
        if (k <= 0) break;
        len += (size_t)k;
    }
    while (len > 0 && buf[len - 1] == '\n') len--;
    buf[len] = '\0';
    return buf;
}

static char *query(const char *path, const char *line) {
    int fd = connect_sock(path);
    if (fd < 0) return NULL;
    send(fd, line, strlen(line), 0);
    send(fd, "\n", 1, 0);
    char *r = read_all(fd);
    close(fd);
    return r;
}

static void sleep_ms(int ms) {
    struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

static int wait_active(int want, int ms) {
    for (int i = 0; i < ms / 10; i++) {
        if (march_observe_active_conns() == want) return 1;
        sleep_ms(10);
    }
    return march_observe_active_conns() == want;
}

/* ── Server ────────────────────────────────────────────────────────────── */

static void test_server(const char *path) {
    char *r;

    r = query(path, "PING");
    CHECK(r && is_json(r), "PING reply is JSON: %s", r ? r : "(null)");
    CHECK(r && strstr(r, "\"proto\":\"march.observe/1\""), "PING envelope proto: %s", r ? r : "");
    CHECK(r && strstr(r, "\"data\":\"pong\""), "PING data is pong: %s", r ? r : "");
    CHECK(r && strstr(r, "\"truncated\":false"), "PING not truncated");
    free(r);

    r = query(path, "HELP");
    CHECK(r && is_json(r), "HELP reply is JSON: %s", r ? r : "(null)");
    CHECK(r && strstr(r, "{\"name\":\"HELP\",\"tier\":\"observe\""), "HELP lists HELP: %s", r ? r : "");
    CHECK(r && strstr(r, "{\"name\":\"PING\",\"tier\":\"observe\""), "HELP lists PING: %s", r ? r : "");
    free(r);

    r = query(path, "PING\r");   /* a CRLF client */
    CHECK(r && strstr(r, "\"data\":\"pong\""), "CRLF line accepted: %s", r ? r : "");
    free(r);

    r = query(path, "NOPE");
    CHECK(r && is_json(r) && strstr(r, "\"error\":\"unknown_verb\""), "unknown verb: %s", r ? r : "");
    CHECK(r && !strstr(r, "\"data\""), "an error reply carries no data");
    free(r);

    /* A line longer than MARCH_OBSERVE_LINE_MAX is refused, not truncated. */
    size_t big = MARCH_OBSERVE_LINE_MAX + 100;
    char *longline = malloc(big + 1);
    memset(longline, 'A', big);
    longline[big] = '\0';
    r = query(path, longline);
    CHECK(r && strstr(r, "\"error\":\"line_too_long\""), "long line refused: %s", r ? r : "");
    free(r);
    free(longline);

    /* Eight silent clients fill every slot; the ninth is told it is busy. */
    CHECK(wait_active(0, 2000), "idle before the cap test");
    int held[MARCH_OBSERVE_MAX_CONNS];
    for (int i = 0; i < MARCH_OBSERVE_MAX_CONNS; i++) held[i] = connect_sock(path);
    CHECK(wait_active(MARCH_OBSERVE_MAX_CONNS, 2000), "eight connections held (active %d)",
          march_observe_active_conns());
    r = query(path, "PING");
    CHECK(r && strstr(r, "\"error\":\"busy\""), "ninth client gets busy: %s", r ? r : "");
    free(r);
    for (int i = 0; i < MARCH_OBSERVE_MAX_CONNS; i++) if (held[i] >= 0) close(held[i]);
    CHECK(wait_active(0, 2000), "slots freed when clients close (active %d)",
          march_observe_active_conns());
    r = query(path, "PING");
    CHECK(r && strstr(r, "\"data\":\"pong\""), "served again after the cap: %s", r ? r : "");
    free(r);

    /* A client that never sends is dropped after MARCH_OBSERVE_IDLE_MS. */
    int idle = connect_sock(path);
    CHECK(idle >= 0, "idle client connects");
    CHECK(wait_active(1, 2000), "idle client holds a slot");
    char *gone = read_all(idle);   /* returns at EOF: the server closed it */
    CHECK(gone && gone[0] == '\0', "idle client closed with no reply");
    free(gone);
    close(idle);
    CHECK(wait_active(0, 2000), "idle slot released");
}

static void test_refuses_non_socket(const char *dir) {
    char path[512];
    snprintf(path, sizeof path, "%s/regular_file", dir);
    FILE *f = fopen(path, "w");
    fputs("keep me", f);
    fclose(f);
    CHECK(march_observe_server_start(path) == -1, "refuses a path holding a regular file");
    struct stat st;
    CHECK(stat(path, &st) == 0 && S_ISREG(st.st_mode), "and leaves the file alone");
    unlink(path);

    char toolong[200];
    memset(toolong, 'x', sizeof toolong - 1);
    toolong[sizeof toolong - 1] = '\0';
    CHECK(march_observe_server_start(toolong) == -1, "refuses a path longer than sun_path");
}

int main(void) {
    char dir[] = "/tmp/obsXXXXXX";
    if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
    char path[256];
    snprintf(path, sizeof path, "%s/o.sock", dir);
    setenv("MARCH_OBSERVE_IDLE_MS", "300", 1);

    test_writer();
    test_refuses_non_socket(dir);
    if (march_observe_server_start(path) != 0) { fprintf(stderr, "server failed to start\n"); return 1; }
    struct stat st;
    CHECK(stat(path, &st) == 0 && (st.st_mode & 0777) == 0600, "socket is owner-only (mode %o)",
          (unsigned)(st.st_mode & 0777));
    test_server(path);

    unlink(path);
    rmdir(dir);
    printf("test_observe: %d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
