/* march_observe.c — the node observe socket and its JSON writer.
 * See march_observe.h for the protocol, and R0 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md for the design.
 *
 * Threads.  One detached accept thread, and one short-lived detached thread
 * per connection, at most MARCH_OBSERVE_MAX_CONNS at once.  None of them is a
 * scheduler thread or a green thread: they are created from the main OS
 * thread (march_run_scheduler) or from the accept thread, never from a green
 * thread (pthread_create on a green thread's stack is a silent SIGSEGV under
 * ASAN).  Every one of them blocks all signals, so process-directed signals
 * land on other threads and SO_RCVTIMEO is not restarted away by SA_RESTART.
 *
 * This file serves HELP and PING; other verbs are registered with
 * march_observe_add_verbs (the R1 snapshot verbs: march_observe_snapshot.c). */
#define _GNU_SOURCE
#include "march_observe.h"

#include <errno.h>
#include <math.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

/* ── JSON writer ──────────────────────────────────────────────────────── */

void march_jw_init(march_jw *w, size_t limit) {
    memset(w, 0, sizeof *w);
    w->limit = limit;
    w->first[0] = 1;
}

void march_jw_free(march_jw *w) {
    free(w->buf);
    w->buf = NULL;
    w->len = w->cap = 0;
}

const char *march_jw_text(const march_jw *w) { return w->buf ? w->buf : ""; }

int march_jw_ok(const march_jw *w) {
    return !w->truncated && !w->oom && w->depth == 0;
}

static void jw_raw(march_jw *w, const char *s, size_t n) {
    if (w->truncated || w->oom) return;
    if (w->len + n > w->limit) { w->truncated = 1; return; }
    if (w->len + n + 1 > w->cap) {
        size_t cap = w->cap ? w->cap : 256;
        while (cap < w->len + n + 1) cap *= 2;
        char *nb = (char *)realloc(w->buf, cap);
        if (!nb) { w->oom = 1; return; }
        w->buf = nb;
        w->cap = cap;
    }
    memcpy(w->buf + w->len, s, n);
    w->len += n;
    w->buf[w->len] = '\0';
}

/* Separator before a value or key: none right after a key, none before the
 * first element of a container, a comma otherwise. */
static void jw_sep(march_jw *w) {
    if (w->after_key) { w->after_key = 0; return; }
    if (w->depth > 0) {
        if (!w->first[w->depth]) jw_raw(w, ",", 1);
        w->first[w->depth] = 0;
    }
}

static void jw_open(march_jw *w, char c) {
    jw_sep(w);
    jw_raw(w, &c, 1);
    if (w->depth < MARCH_JW_MAX_DEPTH) {
        w->depth++;
        w->first[w->depth] = 1;
    } else {
        w->truncated = 1;   /* too deep to track commas: refuse */
    }
}

static void jw_close(march_jw *w, char c) {
    if (w->depth > 0) w->depth--;
    w->after_key = 0;
    jw_raw(w, &c, 1);
}

void march_jw_obj_begin(march_jw *w) { jw_open(w, '{'); }
void march_jw_obj_end(march_jw *w)   { jw_close(w, '}'); }
void march_jw_arr_begin(march_jw *w) { jw_open(w, '['); }
void march_jw_arr_end(march_jw *w)   { jw_close(w, ']'); }

/* A JSON string literal (RFC 8259 §7): quote, backslash and control
 * characters escaped; other bytes, UTF-8 included, pass through. */
static void jw_quoted(march_jw *w, const char *s, size_t n) {
    jw_raw(w, "\"", 1);
    size_t run = 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        const char *esc = NULL;
        char ubuf[8];
        switch (c) {
        case '"':  esc = "\\\""; break;
        case '\\': esc = "\\\\"; break;
        case '\n': esc = "\\n";  break;
        case '\r': esc = "\\r";  break;
        case '\t': esc = "\\t";  break;
        case '\b': esc = "\\b";  break;
        case '\f': esc = "\\f";  break;
        default:
            if (c < 0x20) {
                snprintf(ubuf, sizeof ubuf, "\\u%04x", c);
                esc = ubuf;
            }
        }
        if (esc) {
            jw_raw(w, s + i - run, run);
            run = 0;
            jw_raw(w, esc, strlen(esc));
        } else {
            run++;
        }
    }
    jw_raw(w, s + n - run, run);
    jw_raw(w, "\"", 1);
}

void march_jw_key(march_jw *w, const char *key) {
    jw_sep(w);
    jw_quoted(w, key, strlen(key));
    jw_raw(w, ":", 1);
    w->after_key = 1;
}

void march_jw_strn(march_jw *w, const char *s, size_t n) {
    jw_sep(w);
    jw_quoted(w, s ? s : "", s ? n : 0);
}

void march_jw_str(march_jw *w, const char *s) {
    march_jw_strn(w, s, s ? strlen(s) : 0);
}

void march_jw_i64(march_jw *w, int64_t v) {
    char b[32];
    int n = snprintf(b, sizeof b, "%lld", (long long)v);
    jw_sep(w);
    jw_raw(w, b, (size_t)n);
}

void march_jw_u64(march_jw *w, uint64_t v) {
    char b[32];
    int n = snprintf(b, sizeof b, "%llu", (unsigned long long)v);
    jw_sep(w);
    jw_raw(w, b, (size_t)n);
}

void march_jw_f64(march_jw *w, double v) {
    if (!isfinite(v)) { march_jw_null(w); return; }
    char b[40];
    int n = snprintf(b, sizeof b, "%.17g", v);
    /* Always a JSON float: an integral value keeps a ".0", so a typed
     * client never sees a float field arrive as an integer. */
    if (n > 0 && n < (int)sizeof b - 2 && !strpbrk(b, ".eEn")) {
        b[n++] = '.'; b[n++] = '0'; b[n] = '\0';
    }
    jw_sep(w);
    jw_raw(w, b, (size_t)n);
}

void march_jw_bool(march_jw *w, int v) {
    jw_sep(w);
    if (v) jw_raw(w, "true", 4); else jw_raw(w, "false", 5);
}

void march_jw_null(march_jw *w) {
    jw_sep(w);
    jw_raw(w, "null", 4);
}

/* ── Verbs ─────────────────────────────────────────────────────────────── */

/* Largest data document a verb may produce before it is reported as
 * truncated.  R1's ACTORS caps its row count well under this. */
#define OBS_DATA_LIMIT ((size_t)16 << 20)

/* The verb signature and record are public (march_observe.h) so other files
 * can register verbs: the snapshot verbs live in march_observe_snapshot.c,
 * which links against the rest of the runtime, while this file stays
 * standalone (test_observe links it alone). */
static const char *verb_help(march_jw *w, const char *args);
static const char *verb_ping(march_jw *w, const char *args);

static const march_observe_verb verbs[] = {
    { "HELP", "observe", "", "the verbs this node serves", verb_help },
    { "PING", "observe", "", "liveness: data is \"pong\"", verb_ping },
};
#define N_VERBS (sizeof verbs / sizeof verbs[0])

/* Registered verbs.  Written only before the server starts (registration
 * fails after), so connection threads read them without a lock: the accept
 * thread is created after the last write, and pthread_create orders it. */
#define MAX_EXTRA_VERBS 32
static const march_observe_verb *g_extra[MAX_EXTRA_VERBS];
static size_t g_n_extra;
static _Atomic int g_serving;

int march_observe_add_verbs(const march_observe_verb *v, size_t n) {
    if (atomic_load(&g_serving) || g_n_extra + n > MAX_EXTRA_VERBS) return -1;
    for (size_t i = 0; i < n; i++) g_extra[g_n_extra++] = &v[i];
    return 0;
}

static const march_observe_verb *find_verb(const char *name) {
    for (size_t i = 0; i < N_VERBS; i++)
        if (strcmp(verbs[i].name, name) == 0) return &verbs[i];
    for (size_t i = 0; i < g_n_extra; i++)
        if (strcmp(g_extra[i]->name, name) == 0) return g_extra[i];
    return NULL;
}

static void help_entry(march_jw *w, const march_observe_verb *v) {
    march_jw_obj_begin(w);
    march_jw_key(w, "name"); march_jw_str(w, v->name);
    march_jw_key(w, "tier"); march_jw_str(w, v->tier);
    march_jw_key(w, "args"); march_jw_str(w, v->args);
    march_jw_key(w, "help"); march_jw_str(w, v->help);
    march_jw_obj_end(w);
}

static const char *verb_help(march_jw *w, const char *args) {
    (void)args;
    march_jw_obj_begin(w);
    march_jw_key(w, "verbs");
    march_jw_arr_begin(w);
    for (size_t i = 0; i < N_VERBS; i++) help_entry(w, &verbs[i]);
    for (size_t i = 0; i < g_n_extra; i++) help_entry(w, g_extra[i]);
    march_jw_arr_end(w);
    march_jw_obj_end(w);
    return NULL;
}

static const char *verb_ping(march_jw *w, const char *args) {
    (void)args;
    march_jw_str(w, "pong");
    return NULL;
}

/* ── Envelope ─────────────────────────────────────────────────────────── */

static int64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int64_t mono_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static void node_name(char *out, size_t n) {
    const char *env = getenv("MARCH_NODE_NAME");
    if (env && *env) snprintf(out, n, "%s", env);
    else snprintf(out, n, "pid:%ld", (long)getpid());
}

/* Write the reply envelope for one request into [out].  [data] is the
 * verb's writer, or NULL for an error reply. */
static void build_envelope(march_jw *out, const char *error, march_jw *data,
                           int64_t took_us) {
    char node[256];
    node_name(node, sizeof node);
    march_jw_obj_begin(out);
    march_jw_key(out, "proto");    march_jw_str(out, "march.observe/1");
    march_jw_key(out, "node");     march_jw_str(out, node);
    march_jw_key(out, "at_ms");    march_jw_i64(out, now_ms());
    march_jw_key(out, "took_us");  march_jw_i64(out, took_us);
    int truncated = data && !march_jw_ok(data);
    march_jw_key(out, "truncated"); march_jw_bool(out, truncated);
    if (error) {
        march_jw_key(out, "error"); march_jw_str(out, error);
    } else {
        march_jw_key(out, "data");
        if (truncated) {
            march_jw_null(out);
        } else {
            /* Splice the verb's already-valid JSON in as the value. */
            out->after_key = 0;
            jw_raw(out, march_jw_text(data), data->len);
        }
    }
    march_jw_obj_end(out);
}

/* Handle one request line; the reply (without its newline) goes in [out]. */
static void handle_line(char *line, march_jw *out) {
    int64_t t0 = mono_us();
    char *args = strchr(line, ' ');
    if (args) *args++ = '\0'; else args = line + strlen(line);
    const march_observe_verb *v = find_verb(line);
    if (!v) {
        build_envelope(out, "unknown_verb", NULL, mono_us() - t0);
        return;
    }
    march_jw data;
    march_jw_init(&data, OBS_DATA_LIMIT);
    const char *err = v->fn(&data, args);
    build_envelope(out, err, err ? NULL : &data, mono_us() - t0);
    march_jw_free(&data);
}

/* The same reply a socket client gets, for an in-process caller (the
 * observe_query builtin, march_observe_snapshot.c).  [line] need not be
 * NUL-terminated; a line over MARCH_OBSERVE_LINE_MAX is refused. */
void march_observe_handle(const char *line, size_t n, march_jw *out) {
    char buf[MARCH_OBSERVE_LINE_MAX + 1];
    if (n > MARCH_OBSERVE_LINE_MAX) {
        build_envelope(out, "line_too_long", NULL, 0);
        return;
    }
    memcpy(buf, line, n);
    buf[n] = '\0';
    /* Trailing CR/LF from a caller that kept them. */
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = '\0';
    handle_line(buf, out);
}

/* ── Connections ──────────────────────────────────────────────────────── */

static _Atomic int g_active;
static int g_idle_ms = 5000;

int march_observe_active_conns(void) {
    return atomic_load_explicit(&g_active, memory_order_relaxed);
}

static void block_all_signals(void) {
    sigset_t all;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, NULL);
}

static void send_all(int fd, const char *p, size_t n) {
    while (n > 0) {
        ssize_t k = send(fd, p, n, MSG_NOSIGNAL);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) return;
        p += k;
        n -= (size_t)k;
    }
}

static void send_reply(int fd, march_jw *reply) {
    if (!march_jw_ok(reply)) {
        /* Only reachable on allocation failure: the envelope itself is tiny. */
        static const char oom[] =
            "{\"proto\":\"march.observe/1\",\"error\":\"out_of_memory\"}\n";
        send_all(fd, oom, sizeof oom - 1);
        return;
    }
    send_all(fd, march_jw_text(reply), reply->len);
    send_all(fd, "\n", 1);
}

static void send_error(int fd, const char *code) {
    march_jw out;
    march_jw_init(&out, 4096);
    build_envelope(&out, code, NULL, 0);
    send_reply(fd, &out);
    march_jw_free(&out);
}

/* Read one line (without its '\n'; a trailing '\r' is dropped).  Returns its
 * length, -1 on EOF/error/timeout before a newline, -2 if it is longer than
 * MARCH_OBSERVE_LINE_MAX. */
static int read_request(int fd, char *buf) {
    size_t n = 0;
    for (;;) {
        char c;
        ssize_t k = recv(fd, &c, 1, 0);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) return -1;
        if (c == '\n') break;
        if (n == MARCH_OBSERVE_LINE_MAX) return -2;
        buf[n++] = c;
    }
    if (n > 0 && buf[n - 1] == '\r') n--;
    buf[n] = '\0';
    return (int)n;
}

static void *conn_thread(void *arg) {
    int fd = (int)(intptr_t)arg;
    block_all_signals();
    char *line = (char *)malloc(MARCH_OBSERVE_LINE_MAX + 1);
    if (!line) {
        send_error(fd, "out_of_memory");
    } else {
        int n = read_request(fd, line);
        if (n == -2) {
            send_error(fd, "line_too_long");
        } else if (n >= 0) {
            march_jw out;
            march_jw_init(&out, OBS_DATA_LIMIT + 4096);
            handle_line(line, &out);
            send_reply(fd, &out);
            march_jw_free(&out);
        }
        free(line);
    }
    close(fd);
    atomic_fetch_sub_explicit(&g_active, 1, memory_order_release);
    return NULL;
}

/* A detached thread with a small stack, or, if the system refuses that size,
 * with the default one.  A hot-reload node on Linux once refused the 256 KiB
 * accept thread with EINVAL (forge's deploy e2e, 2026-10-02: "observe socket
 * thread: Invalid argument"); two reruns did not reproduce it and the cause
 * is not pinned down.  glibc does answer EINVAL when a requested stack cannot
 * hold the thread's static TLS, so a fixed small size is not safe in every
 * program; falling back costs only address space. */
static int spawn_detached(void *(*fn)(void *), void *arg) {
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&at, (size_t)256 << 10);
    pthread_t t;
    int rc = pthread_create(&t, &at, fn, arg);
    if (rc == EINVAL) {
        pthread_attr_destroy(&at);
        pthread_attr_init(&at);
        pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
        rc = pthread_create(&t, &at, fn, arg);
    }
    pthread_attr_destroy(&at);
    return rc;
}

static void *accept_thread(void *arg) {
    int ls = (int)(intptr_t)arg;
    block_all_signals();
    for (;;) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR || errno == ECONNABORTED) continue;
            /* EMFILE and friends: back off rather than spin. */
            struct timespec pause = { 0, 50 * 1000 * 1000 };
            nanosleep(&pause, NULL);
            continue;
        }
#ifdef SO_NOSIGPIPE
        { int one = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one); }
#endif
        /* A client that connects and never sends must not hold a slot. */
        struct timeval tv = { g_idle_ms / 1000, (g_idle_ms % 1000) * 1000 };
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);

        if (atomic_fetch_add_explicit(&g_active, 1, memory_order_acq_rel)
                >= MARCH_OBSERVE_MAX_CONNS) {
            send_error(fd, "busy");
            close(fd);
            atomic_fetch_sub_explicit(&g_active, 1, memory_order_release);
            continue;
        }
        if (spawn_detached(conn_thread, (void *)(intptr_t)fd) != 0) {
            send_error(fd, "busy");
            close(fd);
            atomic_fetch_sub_explicit(&g_active, 1, memory_order_release);
        }
    }
    return NULL;
}

/* ── Start ────────────────────────────────────────────────────────────── */

static char g_path[sizeof(((struct sockaddr_un *)0)->sun_path)];

static void unlink_at_exit(void) {
    struct stat st;
    if (g_path[0] && lstat(g_path, &st) == 0 && S_ISSOCK(st.st_mode))
        unlink(g_path);
}

int march_observe_server_start(const char *path) {
    struct sockaddr_un a;
    if (!path || !*path) return -1;
    if (strlen(path) >= sizeof a.sun_path) {
        fprintf(stderr, "march: observe socket path too long (max %zu bytes): %s\n",
                sizeof a.sun_path - 1, path);
        return -1;
    }
    const char *idle = getenv("MARCH_OBSERVE_IDLE_MS");
    if (idle && *idle) {
        int v = atoi(idle);
        if (v > 0) g_idle_ms = v;
    }
    /* Replace a stale socket left by an earlier run, but never anything else. */
    struct stat st;
    if (lstat(path, &st) == 0) {
        if (!S_ISSOCK(st.st_mode)) {
            fprintf(stderr, "march: observe socket path exists and is not a socket: %s\n", path);
            return -1;
        }
        unlink(path);
    }
    int ls = socket(AF_UNIX, SOCK_STREAM, 0);
    if (ls < 0) {
        fprintf(stderr, "march: observe socket: %s\n", strerror(errno));
        return -1;
    }
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    memcpy(a.sun_path, path, strlen(path) + 1);
    if (bind(ls, (struct sockaddr *)&a, sizeof a) < 0) {
        fprintf(stderr, "march: observe socket bind %s: %s\n", path, strerror(errno));
        close(ls);
        return -1;
    }
    /* Owner-only: the socket's filesystem permissions are its authentication. */
    chmod(path, 0600);
    if (listen(ls, MARCH_OBSERVE_MAX_CONNS * 2) < 0) {
        fprintf(stderr, "march: observe socket listen: %s\n", strerror(errno));
        close(ls);
        unlink(path);
        return -1;
    }
    atomic_store(&g_serving, 1);   /* registration closes before any reader */
    int rc = spawn_detached(accept_thread, (void *)(intptr_t)ls);
    if (rc != 0) {
        fprintf(stderr, "march: observe socket thread: %s\n", strerror(rc));
        close(ls);
        unlink(path);
        return -1;
    }
    memcpy(g_path, path, strlen(path) + 1);
    atexit(unlink_at_exit);
    return 0;
}

void march_observe_maybe_start(void) {
    static int started;
    if (started) return;
    started = 1;
    const char *path = getenv("MARCH_OBSERVE_SOCKET");
    char derived[sizeof(((struct sockaddr_un *)0)->sun_path) + 16];
    if (!path || !*path) {
        const char *reload = getenv("MARCH_HOT_RELOAD_SOCKET");
        if (!reload || !*reload) return;
        snprintf(derived, sizeof derived, "%s.observe", reload);
        path = derived;
    }
    (void)march_observe_server_start(path);
}
