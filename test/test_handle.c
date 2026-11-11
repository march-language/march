/* test_handle.c — the handle box (runtime/march_handle.c), ocap phase 2 task 1.
 *
 * A handle is a 48-byte reference-counted cell holding a raw descriptor, a
 * kind, and an atomic state word (closed bit, released bit, in-flight count).
 * These cases pin the contract the stdlib layer builds on:
 *   - a use after close is refused (enter returns -1);
 *   - the descriptor is released exactly once, never while a use is in
 *     flight, and close wakes a reader parked in recv (shutdown);
 *   - the destructor releases an unclosed box, and a detached box is never
 *     released;
 *   - a kind mismatch is fatal (and runs the fatal hook);
 *   - a message copy shares the box, and to_string renders it by kind.
 * Real descriptors from pipe() and socketpair(); "released" is checked with
 * fcntl(fd, F_GETFD) == -1 && errno == EBADF. */
#define _GNU_SOURCE
#include "../runtime/march_runtime.h"
#include "../runtime/march_reclaim.h"
#include "../runtime/march_heap.h"
#include "../runtime/march_message.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int g_failed = 0, g_checks = 0;

#define CHECK(cond, msg) do {                                               \
    g_checks++;                                                             \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

static int fd_is_open(int fd) {
    errno = 0;
    return !(fcntl(fd, F_GETFD) == -1 && errno == EBADF);
}

/* Counting release hook: closes the raw fd like the real DIR/TCP release. */
static atomic_int g_releases;
static void counting_release(int64_t kind, int64_t raw, int64_t aux) {
    (void)kind; (void)aux;
    atomic_fetch_add(&g_releases, 1);
    close((int)raw);
}
static void install_counter(void) {
    atomic_store(&g_releases, 0);
    march_handle_test_release_hook = counting_release;
}
static void remove_counter(void) { march_handle_test_release_hook = NULL; }

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* ── enter_after_close_refused ─────────────────────────────────────────── */
static void test_enter_after_close_refused(void) {
    int p[2];
    if (pipe(p) != 0) { perror("pipe"); exit(2); }
    install_counter();
    void *h = march_handle_new(MARCH_HANDLE_DIR, p[0], 0);
    CHECK(march_handle_enter(h, MARCH_HANDLE_DIR) == p[0], "enter on an open box returns raw");
    march_handle_leave(h);
    CHECK(march_handle_is_closed(h) == 0, "a fresh box is not closed");
    CHECK(march_handle_close(h) == 1, "close on an open box returns 1");
    CHECK(march_handle_is_closed(h) == 1, "is_closed after close");
    CHECK(march_handle_enter(h, MARCH_HANDLE_DIR) == -1, "enter after close returns -1");
    CHECK(atomic_load(&g_releases) == 1, "close with nothing in flight releases now");
    march_decrc(h);
    CHECK(atomic_load(&g_releases) == 1, "the destructor does not release twice");
    remove_counter();
    close(p[1]);
}

/* ── close_twice ───────────────────────────────────────────────────────── */
static void test_close_twice(void) {
    int p[2];
    if (pipe(p) != 0) { perror("pipe"); exit(2); }
    install_counter();
    void *h = march_handle_new(MARCH_HANDLE_DIR, p[0], 0);
    CHECK(march_handle_close(h) == 1, "first close returns 1");
    CHECK(march_handle_close(h) == 0, "second close returns 0");
    CHECK(atomic_load(&g_releases) == 1, "the fd is released once");
    CHECK(!fd_is_open(p[0]), "the fd is closed after close");
    march_decrc(h);
    CHECK(atomic_load(&g_releases) == 1, "dtor after close does not release again");
    remove_counter();
    close(p[1]);
}

/* ── close_wakes_and_defers_release ────────────────────────────────────── */
typedef struct {
    void *h;
    int   fd;
    atomic_int entered, recv_done, may_leave, left;
    ssize_t recv_rc;
    double  recv_at;
} wake_ctx;

static void *wake_reader(void *arg) {
    wake_ctx *c = (wake_ctx *)arg;
    int64_t raw = march_handle_enter(c->h, MARCH_HANDLE_TCP);
    atomic_store(&c->entered, 1);
    char buf[16];
    c->recv_rc = recv((int)raw, buf, sizeof buf, 0);   /* blocks until shutdown */
    c->recv_at = now_s();
    atomic_store(&c->recv_done, 1);
    while (!atomic_load(&c->may_leave)) usleep(1000);
    march_handle_leave(c->h);
    atomic_store(&c->left, 1);
    return NULL;
}

static void test_close_wakes_and_defers_release(void) {
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) { perror("socketpair"); exit(2); }
    remove_counter();                       /* the real TCP release: close(raw) */
    wake_ctx c;
    memset(&c, 0, sizeof c);
    c.h = march_handle_new(MARCH_HANDLE_TCP, sv[0], 0);
    c.fd = sv[0];
    pthread_t t;
    pthread_create(&t, NULL, wake_reader, &c);
    while (!atomic_load(&c.entered)) usleep(1000);
    usleep(50 * 1000);                      /* let it park in recv */
    CHECK(!atomic_load(&c.recv_done), "the reader is parked in recv before close");
    double closed_at = now_s();
    CHECK(march_handle_close(c.h) == 1, "close returns 1");
    for (int i = 0; i < 1000 && !atomic_load(&c.recv_done); i++) usleep(1000);
    CHECK(atomic_load(&c.recv_done), "recv returned after close");
    CHECK(c.recv_rc <= 0, "recv returned <= 0 (shutdown)");
    CHECK(c.recv_at - closed_at < 1.0, "recv woke within 1 s");
    CHECK(fd_is_open(sv[0]), "the fd stays valid while the reader is in flight");
    atomic_store(&c.may_leave, 1);
    pthread_join(t, NULL);
    CHECK(atomic_load(&c.left), "the reader left");
    CHECK(!fd_is_open(sv[0]), "the last leave released the fd");
    march_decrc(c.h);
    close(sv[1]);
}

/* ── release_exactly_once ──────────────────────────────────────────────── */
#define HAMMER_THREADS 8
#define HAMMER_ITERS   100000
static atomic_int g_go;

static void *hammer(void *arg) {
    void *h = arg;
    while (!atomic_load(&g_go)) ;
    for (int i = 0; i < HAMMER_ITERS; i++) {
        int64_t raw = march_handle_enter(h, MARCH_HANDLE_TCP);
        if (raw == -1) continue;            /* closed: refused, nothing to leave */
        march_handle_leave(h);
    }
    return NULL;
}

static void *closer(void *arg) {
    void *h = arg;
    while (!atomic_load(&g_go)) ;
    usleep(2000);
    march_handle_close(h);
    return NULL;
}

static void test_release_exactly_once(void) {
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) { perror("socketpair"); exit(2); }
    install_counter();
    void *h = march_handle_new(MARCH_HANDLE_TCP, sv[0], 0);
    atomic_store(&g_go, 0);
    pthread_t ts[HAMMER_THREADS + 1];
    for (int i = 0; i < HAMMER_THREADS; i++) pthread_create(&ts[i], NULL, hammer, h);
    pthread_create(&ts[HAMMER_THREADS], NULL, closer, h);
    atomic_store(&g_go, 1);
    for (int i = 0; i <= HAMMER_THREADS; i++) pthread_join(ts[i], NULL);
    CHECK(atomic_load(&g_releases) == 1, "exactly one release under contention");
    CHECK(march_handle_is_closed(h) == 1, "closed after the race");
    march_decrc(h);
    CHECK(atomic_load(&g_releases) == 1, "dtor adds no second release");
    remove_counter();
    close(sv[1]);
}

/* ── dtor_releases_unclosed ────────────────────────────────────────────── */
static void test_dtor_releases_unclosed(void) {
    int p[2];
    if (pipe(p) != 0) { perror("pipe"); exit(2); }
    remove_counter();                       /* the real DIR release: close(raw) */
    void *h = march_handle_new(MARCH_HANDLE_DIR, p[0], 0);
    CHECK(fd_is_open(p[0]), "fd open while the box lives");
    march_decrc(h);
    CHECK(!fd_is_open(p[0]), "dropping the last reference released the fd");
    close(p[1]);
}

/* ── detach_does_not_release ───────────────────────────────────────────── */
static void test_detach_does_not_release(void) {
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) { perror("socketpair"); exit(2); }
    remove_counter();
    void *h = march_handle_new(MARCH_HANDLE_TCP, sv[0], 7);
    CHECK(march_handle_aux(h) == 7, "aux reads back");
    CHECK(march_handle_detach(h) == sv[0], "detach returns raw");
    CHECK(march_handle_is_closed(h) == 1, "a detached box is closed");
    CHECK(march_handle_enter(h, MARCH_HANDLE_TCP) == -1, "enter after detach is refused");
    CHECK(march_handle_detach(h) == -1, "a second detach returns -1");
    CHECK(march_handle_close(h) == 0, "close after detach returns 0");
    CHECK(fd_is_open(sv[0]), "detach (and a later close) leaves the fd open");
    march_decrc(h);
    CHECK(fd_is_open(sv[0]), "the destructor does not close a detached fd");
    /* Still a working socket: no shutdown either. */
    CHECK(send(sv[1], "x", 1, 0) == 1, "peer can still send");
    char b;
    CHECK(recv(sv[0], &b, 1, 0) == 1 && b == 'x', "the detached fd still reads");
    close(sv[0]);
    close(sv[1]);
}

/* ── borrowed TCP satisfies TCP, and is never released ─────────────────── */
static void test_borrowed_tcp(void) {
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) { perror("socketpair"); exit(2); }
    remove_counter();
    void *h = march_handle_new(MARCH_HANDLE_TCP_BORROWED, sv[0], 0);
    CHECK(march_handle_enter(h, MARCH_HANDLE_TCP) == sv[0], "TCP_BORROWED satisfies an expected TCP");
    march_handle_leave(h);
    CHECK(march_handle_close(h) == 1, "close a borrowed box");
    march_decrc(h);
    CHECK(fd_is_open(sv[0]), "a borrowed descriptor is never released by the box");
    close(sv[0]);
    close(sv[1]);
}

/* ── kind_mismatch_is_fatal ────────────────────────────────────────────── */
static int g_hook_pipe[2];
static void fatal_hook(const char *why) {
    (void)why;
    char c = 'h';
    (void)!write(g_hook_pipe[1], &c, 1);
}

enum fatal_case { WRONG_KIND, NOT_A_HANDLE, BORROWED_FOR_LISTENER,
                  TLS_NO_RELEASER, TLS_CTX_NO_RELEASER };

static void run_fatal_case(enum fatal_case fc, const char *what) {
    if (pipe(g_hook_pipe) != 0) { perror("pipe"); exit(2); }
    fflush(stderr);
    pid_t pid = fork();
    if (pid == 0) {
        close(g_hook_pipe[0]);
        march_fatal_set_hook(fatal_hook);
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) dup2(devnull, 2);   /* keep the expected message quiet */
        if (fc == WRONG_KIND) {
            void *h = march_handle_new(MARCH_HANDLE_DIR, 99, 0);
            (void)march_handle_enter(h, MARCH_HANDLE_FILE);
        } else if (fc == NOT_A_HANDLE) {
            void *cell = march_alloc(24);
            ((march_hdr *)cell)->tag = 0;
            (void)march_handle_enter(cell, MARCH_HANDLE_FILE);
        } else if (fc == BORROWED_FOR_LISTENER) {
            void *h = march_handle_new(MARCH_HANDLE_TCP_BORROWED, 99, 0);
            (void)march_handle_enter(h, MARCH_HANDLE_LISTENER);
        } else {
            /* This runner links no march_tls.c, so no TLS closer is
             * registered: releasing the box must abort, not leak (R4). */
            march_handle_test_release_hook = NULL;
            void *h = march_handle_new(fc == TLS_NO_RELEASER ? MARCH_HANDLE_TLS
                                                             : MARCH_HANDLE_TLS_CTX, 1234, -1);
            (void)march_handle_close(h);
        }
        _exit(0);                            /* reached only if enter did not die */
    }
    close(g_hook_pipe[1]);
    char c = 0;
    ssize_t n = read(g_hook_pipe[0], &c, 1);
    close(g_hook_pipe[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    char msg[160];
    snprintf(msg, sizeof msg, "%s: the process aborts", what);
    CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT, msg);
    snprintf(msg, sizeof msg, "%s: the fatal hook fires", what);
    CHECK(n == 1 && c == 'h', msg);
}

static void test_kind_mismatch_is_fatal(void) {
    run_fatal_case(WRONG_KIND, "DIR box entered as FILE");
    run_fatal_case(NOT_A_HANDLE, "ordinary cell entered as a handle");
    run_fatal_case(BORROWED_FOR_LISTENER, "TCP_BORROWED box entered as LISTENER");
}

static void test_missing_tls_releaser_is_fatal(void) {
    run_fatal_case(TLS_NO_RELEASER, "TLS box released with no closer registered");
    run_fatal_case(TLS_CTX_NO_RELEASER, "TLS_CTX box released with no closer registered");
}

/* ── close cancels a wait on the descriptor (R3) ───────────────────────────
 * A thread waits for a LISTENING socket to become readable (what accept
 * parks on) through march_sched_wait_fd.  Off a green thread that is the
 * blocking path.  On macOS shutdown() on a listening socket fails with
 * ENOTCONN and wakes nothing, so only the scheduler's cancellation can end
 * the wait; on Linux both do. */
#include "../runtime/march_scheduler.h"
#include <netinet/in.h>

static int listening_socket(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = 0;
    if (fd < 0 || bind(fd, (struct sockaddr *)&a, sizeof a) != 0 || listen(fd, 4) != 0) {
        perror("listening_socket"); exit(2);
    }
    return fd;
}

typedef struct { void *h; int rc; int err; int64_t took_ms; } waiter_arg;

static int64_t mono_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void *wait_listener(void *p) {
    waiter_arg *a = p;
    int64_t fd = march_handle_enter(a->h, MARCH_HANDLE_LISTENER);
    int64_t t0 = mono_ms();
    a->rc = march_sched_wait_fd((int)fd, 0, mono_ms() + 5000);
    a->err = errno;
    a->took_ms = mono_ms() - t0;
    march_handle_leave(a->h);
    return NULL;
}

static void test_close_cancels_listener_wait(void) {
    remove_counter();
    int lfd = listening_socket();
    void *h = march_handle_new(MARCH_HANDLE_LISTENER, lfd, 0);
    waiter_arg a = { h, 99, 0, 0 };
    pthread_t t;
    pthread_create(&t, NULL, wait_listener, &a);
    struct timespec ts = { 0, 100 * 1000000L };
    nanosleep(&ts, NULL);
    CHECK(march_handle_close(h) == 1, "close the listener");
    pthread_join(t, NULL);
    CHECK(a.rc == MARCH_FDWAIT_ERROR, "the parked wait ends in an error, not a timeout");
    CHECK(a.err == ECANCELED, "errno is ECANCELED");
    CHECK(a.took_ms < 1000, "the wait ends well before its 5 s deadline");
    CHECK(!fd_is_open(lfd), "the listener is released after the waiter leaves");
    /* The cancellation went with the descriptor: a new socket that reuses the
     * number waits normally (times out). */
    int again = listening_socket();
    int rc = march_sched_wait_fd(again, 0, mono_ms() + 150);
    CHECK(rc == MARCH_FDWAIT_TIMEOUT, "a reused descriptor number is not cancelled");
    close(again);
    march_decrc(h);
}

/* ── message copy shares the box ───────────────────────────────────────── */
static void test_msg_copy_shares(void) {
    remove_counter();
    int p[2];
    if (pipe(p) != 0) { perror("pipe"); exit(2); }
    void *h = march_handle_new(MARCH_HANDLE_DIR, p[0], 0);
    march_heap_t src, dst;
    march_heap_init(&src);
    march_heap_init(&dst);
    void *copy = march_msg_copy(&src, &dst, h);
    CHECK(copy == h, "a handle is shared by a message copy, not byte-copied");
    CHECK(((march_hdr *)h)->rc == 2, "the copy holds its own reference");
    march_decrc(copy);
    CHECK(fd_is_open(p[0]), "dropping the copy leaves the fd open");
    march_decrc(h);
    CHECK(!fd_is_open(p[0]), "dropping the last reference releases it");
    march_heap_destroy(&src);
    march_heap_destroy(&dst);
    close(p[1]);
}

/* ── to_string renders by kind ─────────────────────────────────────────── */
static int str_eq(void *s, const char *want) {
    char scratch[MARCH_SSO_MAX + 1];
    int64_t len = march_str_len(s);
    const char *d = march_str_data(s, scratch);
    size_t n = strlen(want);
    int ok = len == (int64_t)n && memcmp(d, want, n) == 0;
    if (!ok) fprintf(stderr, "    got \"%.*s\", want \"%s\"\n", (int)len, d, want);
    return ok;
}

static void test_to_string(void) {
    install_counter();
    struct { int64_t kind; const char *open, *closed; } cases[] = {
        { MARCH_HANDLE_FILE,         "#<File.Handle>",   "#<File.Handle closed>" },
        { MARCH_HANDLE_DIR,          "#<File.Dir>",      "#<File.Dir closed>" },
        { MARCH_HANDLE_TCP,          "#<Socket>",        "#<Socket closed>" },
        { MARCH_HANDLE_TCP_BORROWED, "#<Socket>",        "#<Socket closed>" },
        { MARCH_HANDLE_LISTENER,     "#<Listener>",      "#<Listener closed>" },
        { MARCH_HANDLE_UDP,          "#<Udp.UdpSocket>", "#<Udp.UdpSocket closed>" },
        { MARCH_HANDLE_TLS,          "#<Tls.TlsConn>",   "#<Tls.TlsConn closed>" },
        { MARCH_HANDLE_TLS_CTX,      "#<Tls.TlsCtx>",    "#<Tls.TlsCtx closed>" },
        { MARCH_HANDLE_PROCESS,      "#<Process>",       "#<Process closed>" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        int p[2];
        if (pipe(p) != 0) { perror("pipe"); exit(2); }
        void *h = march_handle_new(cases[i].kind, p[0], 0);
        void *s = march_value_to_string(h);
        CHECK(str_eq(s, cases[i].open), cases[i].open);
        march_decrc(s);
        march_handle_close(h);
        s = march_value_to_string(h);
        CHECK(str_eq(s, cases[i].closed), cases[i].closed);
        march_decrc(s);
        march_decrc(h);
        close(p[1]);
    }
    remove_counter();
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    test_enter_after_close_refused();
    test_close_twice();
    test_close_wakes_and_defers_release();
    test_release_exactly_once();
    test_dtor_releases_unclosed();
    test_detach_does_not_release();
    test_borrowed_tcp();
    test_kind_mismatch_is_fatal();
    test_missing_tls_releaser_is_fatal();
    test_close_cancels_listener_wait();
    test_msg_copy_shares();
    test_to_string();
    if (g_failed) {
        fprintf(stderr, "test_handle: %d of %d checks FAILED\n", g_failed, g_checks);
        return 1;
    }
    printf("test_handle: all %d checks passed\n", g_checks);
    return 0;
}
