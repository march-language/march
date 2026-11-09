/* runtime/march_http_evloop.c — kqueue/epoll event-loop HTTP server.
 *
 * Replaces the thread-per-connection + mutex work-queue model with a fixed
 * pool of event-loop threads (one per CPU core).  Each thread owns its own
 * kqueue/epoll instance and a private SO_REUSEPORT listener fd, so there is
 * zero cross-thread synchronization on the hot path.
 *
 * Architecture:
 *
 *   port 8080 (SO_REUSEPORT)
 *       │
 *       ├── Thread 0:  kqueue/epoll  →  accept + recv + pipeline + send
 *       ├── Thread 1:  kqueue/epoll  →  accept + recv + pipeline + send
 *       └── ...
 *       └── Thread N:  kqueue/epoll  →  accept + recv + pipeline + send
 *
 * The March pipeline (Conn → Conn) is called synchronously inline — no
 * async/await or coroutines needed.
 */

#include "march_http_io.h"
#include "march_http_internal.h"
#include "march_http.h"
#include "march_http_parse_simd.h"
#include "march_http_response.h"
#include "march_scheduler.h"   /* march_sched_run_on_sched_stack */
#include "march_https.h"       /* g_march_https: phase timeouts, plain listener */
#define MARCH_TLS_VIA_OPS       /* TLS through g_march_tls_ops: see march_tls_ops.h */
#include "march_tls_ops.h"      /* per-connection TLS, the fd -> session registry */

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <assert.h>
#include <time.h>
#include <poll.h>

/* ── WebSocket upgrade thread ─────────────────────────────────────────── */

typedef struct {
    int                  fd;
    march_tls_session_t *tls;          /* NULL for plain */
    int64_t              ws_value;     /* the WsSocket Int (march_ws_sock_value) */
    void                *ws_closure;   /* March closure: WsSocket -> Unit */
    char                *key;          /* Sec-WebSocket-Key */
    size_t               key_len;
} ws_upgrade_arg_t;

/* Thread that sends the 101 and runs the blocking WebSocket handler.
 * Owns the fd (and the TLS session) and closes them on exit, once no other
 * task is using the socket (march_ws_tls_teardown). */
static void *ws_handler_thread(void *arg) {
    ws_upgrade_arg_t *a = (ws_upgrade_arg_t *)arg;
    int   fd         = a->fd;
    march_tls_session_t *tls = a->tls;
    int64_t ws_value = a->ws_value;
    void *ws_closure = a->ws_closure;

    /* This OS thread runs compiled March code outside the scheduler — force
     * atomic "local" refcounts so it doesn't race shared closures/constants. */
    march_rc_set_thread_concurrent(1);

    /* Switch fd back to blocking — WS send/recv use blocking syscalls. */
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);

    march_ws_send_101(ws_value, a->key, a->key_len);
    free(a->key);
    free(a);

    /* WsSocket(value): header(16) + one Int field. */
    void *ws_sock = march_alloc(24);
    *(int64_t *)((char *)ws_sock + 16) = ws_value;
    call_closure1(ws_closure, ws_sock);

    march_ws_tls_teardown(fd, tls);
    return NULL;
}

/* ── Platform event API selection ─────────────────────────────────────── */

#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
#  include <sys/event.h>
#  define EVLOOP_USE_KQUEUE 1
#elif defined(__linux__)
#  include <sys/epoll.h>
#  define EVLOOP_USE_EPOLL  1
#else
#  error "Event loop requires kqueue (macOS/BSD) or epoll (Linux)"
#endif

/* ── Constants ────────────────────────────────────────────────────────── */

/* Max events returned per kevent()/epoll_wait() call. */
#define EVLOOP_MAX_EVENTS 256

/* ── Per-connection deadlines ─────────────────────────────────────────── */
/*
 * Every connection is in one timed phase, each with its own limit from
 * g_march_https (design: specs/2026-11-05-https-server-design.md, "Timeouts"):
 *
 *   PH_HANDSHAKE  TLS handshake not finished              handshake_secs
 *   PH_IDLE       keep-alive, no request bytes            idle_secs
 *   PH_HEADERS    request started, headers incomplete     header_secs, from the FIRST byte
 *   PH_BODY       headers in, body incomplete             progress_secs, reset by each read
 *   PH_WRITE      response waiting on a full socket       progress_secs, reset by each send
 *   PH_NONE       upgraded WebSocket: not timed here
 *
 * The deadlines live in a per-thread binary min-heap of conn_state_t
 * pointers (each knows its slot), swept after every kevent/epoll_wait; the
 * wait itself is bounded by the earliest deadline.
 */
enum { PH_NONE = 0, PH_HANDSHAKE, PH_IDLE, PH_HEADERS, PH_BODY, PH_WRITE };

static _Thread_local conn_state_t **tl_heap;
static _Thread_local int            tl_heap_n;
static _Thread_local int            tl_heap_cap;

static int64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void heap_swap(int i, int j) {          /* 0-based slots */
    conn_state_t *a = tl_heap[i], *b = tl_heap[j];
    tl_heap[i] = b; b->heap_pos = i + 1;
    tl_heap[j] = a; a->heap_pos = j + 1;
}

static void heap_up(int i) {
    while (i > 0) {
        int p = (i - 1) / 2;
        if (tl_heap[p]->deadline_ms <= tl_heap[i]->deadline_ms) break;
        heap_swap(i, p);
        i = p;
    }
}

static void heap_down(int i) {
    for (;;) {
        int l = 2 * i + 1, r = l + 1, m = i;
        if (l < tl_heap_n && tl_heap[l]->deadline_ms < tl_heap[m]->deadline_ms) m = l;
        if (r < tl_heap_n && tl_heap[r]->deadline_ms < tl_heap[m]->deadline_ms) m = r;
        if (m == i) break;
        heap_swap(i, m);
        i = m;
    }
}

static void heap_remove(conn_state_t *c) {
    if (c->heap_pos == 0) return;
    int i = c->heap_pos - 1;
    c->heap_pos = 0;
    tl_heap_n--;
    if (i == tl_heap_n) return;
    tl_heap[i] = tl_heap[tl_heap_n];
    tl_heap[i]->heap_pos = i + 1;
    heap_up(i);
    heap_down(tl_heap[i]->heap_pos - 1);
}

static int phase_secs(int phase) {
    switch (phase) {
    case PH_HANDSHAKE: return g_march_https.handshake_secs;
    case PH_IDLE:      return g_march_https.idle_secs;
    case PH_HEADERS:   return g_march_https.header_secs;
    case PH_BODY:
    case PH_WRITE:     return g_march_https.progress_secs;
    default:           return 0;
    }
}

/* Enter [phase] with a fresh deadline (also used to reset a progress
 * deadline). PH_NONE takes the connection out of the heap. */
static void conn_set_phase(conn_state_t *c, int phase) {
    c->timed_phase = phase;
    int secs = phase_secs(phase);
    if (phase == PH_NONE || secs <= 0) { heap_remove(c); return; }
    c->deadline_ms = now_ms() + (int64_t)secs * 1000;
    if (c->heap_pos) {
        int i = c->heap_pos - 1;
        heap_up(i);
        heap_down(c->heap_pos - 1);
        return;
    }
    if (tl_heap_n == tl_heap_cap) {
        int ncap = tl_heap_cap ? tl_heap_cap * 2 : 256;
        conn_state_t **n = realloc(tl_heap, (size_t)ncap * sizeof *n);
        if (!n) return;                      /* untimed rather than crash */
        tl_heap = n;
        tl_heap_cap = ncap;
    }
    tl_heap[tl_heap_n] = c;
    c->heap_pos = ++tl_heap_n;
    heap_up(tl_heap_n - 1);
}

/* Milliseconds until the earliest deadline, capped at [cap_ms]. */
static int heap_wait_ms(int cap_ms) {
    if (tl_heap_n == 0) return cap_ms;
    int64_t d = tl_heap[0]->deadline_ms - now_ms();
    if (d < 0) d = 0;
    return d < cap_ms ? (int)d : cap_ms;
}

/* ── Shutdown flag (shared with march_http.c) ─────────────────────────── */

extern _Atomic int g_http_shutdown;

/* ── Per-thread event loop arguments ──────────────────────────────────── */

typedef struct {
    int    listener_fd;   /* SO_REUSEPORT fd owned by this thread */
    void  *pipeline;      /* March closure (Conn → Conn) */
    int    is_tls;        /* listener_fd serves HTTPS */
    int    plain_fd;      /* extra plain-HTTP listener, -1 if none */
    void  *plain_pipeline;
    int    port;          /* listener_fd's port (bound later in bootstrap mode) */
} evloop_thread_arg_t;

/* epoll user data for the two listeners (a conn_state_t pointer otherwise). */
#define EVLOOP_MAIN_LISTENER  ((void *)1)
#define EVLOOP_PLAIN_LISTENER ((void *)2)

/* ── Create a SO_REUSEPORT listener ───────────────────────────────────── */

static int create_reuseport_listener(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#if defined(SO_REUSEPORT)
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
#endif

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = march_http_bind_addr;
    addr.sin_port        = htons((uint16_t)port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    if (listen(fd, 1024) < 0) {
        close(fd);
        return -1;
    }
    if (march_set_nonblocking(fd) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

/* ── Accept a new connection ──────────────────────────────────────────── */

static void accept_connections(int listener_fd, int evfd, int is_tls, void *pipeline) {
    /* Accept in a loop — edge-triggered kqueue/epoll may batch multiple
     * ready connections into a single event. */
    for (;;) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int cfd = accept(listener_fd,
                          (struct sockaddr *)&client_addr, &client_len);
        if (cfd < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                break;   /* no more pending connections */
            if (errno == EINTR)
                continue;
            break;   /* unexpected error */
        }

        /* Set non-blocking and TCP_NODELAY. */
        march_set_nonblocking(cfd);
#if defined(IPPROTO_TCP) && defined(TCP_NODELAY)
        {
            int one = 1;
            setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        }
#endif

        /* Allocate per-connection state. */
        conn_state_t *c = conn_state_alloc();
        if (!c) { close(cfd); continue; }
        c->fd       = cfd;
        c->phase    = CONN_PHASE_READING;
        c->pipeline = pipeline;
        if (is_tls) {
            /* The session takes its own reference to the current context;
             * a later certificate swap leaves this connection's alone. */
            march_tls_session_t *s = mts_new_from_slot();
            if (!s) { close(cfd); conn_state_free(c); continue; }
            c->tls = s;
            mts_registry_put(cfd, s);
            conn_set_phase(c, PH_HANDSHAKE);
        } else {
            conn_set_phase(c, PH_IDLE);
        }

        /* Register for readability. */
#if EVLOOP_USE_KQUEUE
        struct kevent ev;
        EV_SET(&ev, cfd, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, c);
        kevent(evfd, &ev, 1, NULL, 0, NULL);
#elif EVLOOP_USE_EPOLL
        struct epoll_event ev;
        ev.events  = EPOLLIN | EPOLLET;
        ev.data.ptr = c;
        epoll_ctl(evfd, EPOLL_CTL_ADD, cfd, &ev);
#endif
    }
}

/* ── Arm fd for writing (switch from read → write interest) ───────────── */

static void arm_write(int evfd, conn_state_t *c) {
#if EVLOOP_USE_KQUEUE
    struct kevent evs[2];
    /* Remove read filter, add write filter.  EV_CLEAR = edge-triggered. */
    EV_SET(&evs[0], c->fd, EVFILT_READ,  EV_DELETE, 0, 0, NULL);
    EV_SET(&evs[1], c->fd, EVFILT_WRITE, EV_ADD | EV_CLEAR, 0, 0, c);
    kevent(evfd, evs, 2, NULL, 0, NULL);
#elif EVLOOP_USE_EPOLL
    struct epoll_event ev;
    ev.events   = EPOLLOUT | EPOLLET;
    ev.data.ptr = c;
    epoll_ctl(evfd, EPOLL_CTL_MOD, c->fd, &ev);
#endif
}

/* ── Arm fd for reading ───────────────────────────────────────────────── */

static void arm_read(int evfd, conn_state_t *c) {
#if EVLOOP_USE_KQUEUE
    struct kevent evs[2];
    EV_SET(&evs[0], c->fd, EVFILT_WRITE, EV_DELETE, 0, 0, NULL);
    EV_SET(&evs[1], c->fd, EVFILT_READ,  EV_ADD | EV_CLEAR, 0, 0, c);
    kevent(evfd, evs, 2, NULL, 0, NULL);
#elif EVLOOP_USE_EPOLL
    struct epoll_event ev;
    ev.events   = EPOLLIN | EPOLLET;
    ev.data.ptr = c;
    epoll_ctl(evfd, EPOLL_CTL_MOD, c->fd, &ev);
#endif
}

/* ── Close and free a connection ──────────────────────────────────────── */

static void close_conn(int evfd, conn_state_t *c) {
    heap_remove(c);
    if (c->ws_closure) { march_decrc(c->ws_closure); c->ws_closure = NULL; }
    free(c->ws_key);
    c->ws_key = NULL;
    c->ws_pending = 0;
    if (c->tls) {
        /* One best-effort close_notify, then forget the session BEFORE the
         * fd is closed: a new connection reusing the number must never find
         * this session in the registry. */
        mts_shutdown(c->tls);
        (void)march_tls_flush(c, NULL);
        mts_registry_take(c->fd);
        mts_free(c->tls);
        c->tls = NULL;
        march_tls_conn_free_out(c);
    }
#if EVLOOP_USE_KQUEUE
    /* kqueue automatically removes filters when fd is closed. */
    (void)evfd;
#elif EVLOOP_USE_EPOLL
    epoll_ctl(evfd, EPOLL_CTL_DEL, c->fd, NULL);
#endif
    close(c->fd);
    march_http_release_conns(c->pending_release, &c->pending_release_n);
    conn_state_free(c);
}

/* Close every connection whose phase deadline has passed. */
static void sweep_deadlines(int evfd) {
    int64_t now = now_ms();
    while (tl_heap_n > 0 && tl_heap[0]->deadline_ms <= now)
        close_conn(evfd, tl_heap[0]);
}

/* After a read: which phase is the connection in now? Empty buffer: idle
 * (a fresh keep-alive deadline). Headers complete but not the body: body,
 * whose deadline moves with every read that brought bytes. Otherwise the
 * request's headers are still arriving: the header deadline runs from the
 * first byte and is NOT moved by later bytes (a slowloris drip). */
static void update_read_phase(conn_state_t *c, int got_bytes, int dispatched) {
    if (c->tls && !mts_is_established(c->tls)) return;   /* still PH_HANDSHAKE */
    if (c->rbuf_len == 0) {
        if (c->timed_phase != PH_IDLE || got_bytes) conn_set_phase(c, PH_IDLE);
        return;
    }
    /* Still in the body of the request at the front of the buffer (nothing
     * was dispatched since): its headers are known complete, so skip the
     * scan; a large upload would otherwise rescan its whole buffer on
     * every read. */
    int headers_done = (c->timed_phase == PH_BODY && !dispatched) ||
                       march_http_has_header_end(c->rbuf, c->rbuf_len);
    if (headers_done) {
        if (c->timed_phase != PH_BODY || got_bytes) conn_set_phase(c, PH_BODY);
    } else if (c->timed_phase != PH_HEADERS) {
        conn_set_phase(c, PH_HEADERS);
    }
}

/* Hand a batch's results to the connection until its deferred write drains
 * (handle_write) or it closes (close_conn/detach_conn).  At most one batch
 * is ever in flight per connection — reads are not re-armed while writing —
 * so the array never overflows; the fallback release only guards a
 * programming error. */
static void park_pending(conn_state_t *c, void **conns, int *n) {
    for (int i = 0; i < *n; i++) {
        if (c->pending_release_n < EVLOOP_PIPELINE_BATCH)
            c->pending_release[c->pending_release_n++] = conns[i];
        else
            march_http_release_conn(conns[i]);
    }
    *n = 0;
}

/* ── Detach a connection from the event loop without closing the fd ───── */
/* Used for WebSocket upgrades: the fd is handed off to a blocking thread. */

static void detach_conn(int evfd, conn_state_t *c) {
    heap_remove(c);                          /* a WebSocket is not timed here */
#if EVLOOP_USE_KQUEUE
    /* Explicitly delete both kqueue filters.  We are NOT closing the fd, so
     * kqueue won't remove them automatically, and a WebSocket handed off
     * from the write phase (a wss:// upgrade waiting for its earlier
     * responses to drain) still has its write filter, whose events would
     * otherwise arrive for a recycled conn_state_t. Deleted one at a time:
     * a missing filter fails its own change only. */
    struct kevent ev;
    EV_SET(&ev, c->fd, EVFILT_READ, EV_DELETE, 0, 0, NULL);
    kevent(evfd, &ev, 1, NULL, 0, NULL);   /* ignore error — filter may be gone */
    EV_SET(&ev, c->fd, EVFILT_WRITE, EV_DELETE, 0, 0, NULL);
    kevent(evfd, &ev, 1, NULL, 0, NULL);
#elif EVLOOP_USE_EPOLL
    epoll_ctl(evfd, EPOLL_CTL_DEL, c->fd, NULL);
#endif
    /* Do NOT close c->fd — the WebSocket thread takes ownership. */
    march_tls_conn_free_out(c);
    march_http_release_conns(c->pending_release, &c->pending_release_n);
    conn_state_free(c);
}

/* Hand an upgraded connection to a WebSocket handler thread: the loop
 * forgets it (the TLS session stays registered under the fd, now in
 * WebSocket mode) and the thread sends the 101 and runs the handler. */
static void evloop_ws_handoff(int evfd, conn_state_t *c) {
    int   fd  = c->fd;
    march_tls_session_t *tls = c->tls;
    void *clo = c->ws_closure;
    char *key = c->ws_key;
    size_t klen = c->ws_key_len;
    c->tls = NULL;
    c->ws_closure = NULL;
    c->ws_key = NULL;
    c->ws_pending = 0;
    detach_conn(evfd, c);
    if (tls) mts_ws_begin(tls);
    ws_upgrade_arg_t *targ = malloc(sizeof(*targ));
    if (targ) {
        targ->fd         = fd;
        targ->tls        = tls;
        targ->ws_value   = march_ws_sock_value(fd, tls);
        targ->ws_closure = clo;
        targ->key        = key;
        targ->key_len    = klen;
        pthread_t tid;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        int rc = pthread_create(&tid, &attr, ws_handler_thread, targ);
        pthread_attr_destroy(&attr);
        if (rc == 0) return;
        free(targ);
    }
    free(key);
    march_decrc(clo);
    march_ws_tls_teardown(fd, tls);
}

/* ── Defer a partial/EAGAIN write to handle_write ─────────────────────── */

static void evloop_defer_write(int evfd, conn_state_t *c,
                                struct iovec *remaining, int n_remaining,
                                size_t scratch_used, int keep_alive) {
    /* Snapshot TLS scratch so iovecs remain valid after handle_read returns.
     * scratch_snap is MARCH_RESPONSE_SCRATCH_SIZE bytes — always fits. */
    if (scratch_used > 0) {
        assert(scratch_used <= MARCH_RESPONSE_SCRATCH_SIZE);
        char *tls = march_response_tls_scratch();
        memcpy(c->scratch_snap, tls, scratch_used);
        c->scratch_snap_len = scratch_used;
        /* Fix up iov_base pointers that point into tls_scratch. */
        for (int j = 0; j < n_remaining; j++) {
            char *base = (char *)remaining[j].iov_base;
            if (base >= tls && base < tls + MARCH_RESPONSE_SCRATCH_SIZE)
                remaining[j].iov_base = c->scratch_snap + (base - tls);
        }
    }

    int copy = n_remaining < CONN_BATCH_IOV_MAX ? n_remaining : CONN_BATCH_IOV_MAX;
    memcpy(c->wbuf, remaining, (size_t)copy * sizeof(struct iovec));
    c->wbuf_count = copy;
    c->wbuf_pos   = 0;
    c->keep_alive = keep_alive;
    c->phase      = CONN_PHASE_WRITING;
    conn_set_phase(c, PH_WRITE);
    arm_write(evfd, c);
}

/* ── Handle a readable connection ─────────────────────────────────────── */

/* Send a TLS connection's pending ciphertext. Returns 1 when all of it is
 * out; 0 when the rest waits for writability (the connection is now in the
 * write phase, armed for write, and keeps [keep_alive] for when it drains);
 * -1 after closing the connection on an error. */
static int tls_send_or_defer(int evfd, conn_state_t *c, int keep_alive) {
    io_result_t f = march_tls_flush(c, NULL);
    if (f == IO_COMPLETE) return 1;
    if (f == IO_ERROR) { close_conn(evfd, c); return -1; }
    c->keep_alive = keep_alive;
    c->phase      = CONN_PHASE_WRITING;
    if (mts_is_established(c->tls)) conn_set_phase(c, PH_WRITE);
    arm_write(evfd, c);
    return 0;
}

/* Write a batch: plaintext connections writev it; TLS ones encrypt it into
 * the session (the bytes are copied, so the batch is "all written" and its
 * results may be released) and send it later with tls_send_or_defer. */
static ssize_t conn_out(conn_state_t *c, struct iovec *iov, int n) {
    if (!c->tls) return writev(c->fd, iov, n);
    if (march_tls_write_iov(c, iov, n) != 0) { errno = EIO; return -1; }
    size_t total = 0;
    for (int i = 0; i < n; i++) total += iov[i].iov_len;
    return (ssize_t)total;
}

static void handle_read(int evfd, conn_state_t *c) {
    void       *pipeline = c->pipeline;
    size_t      before = c->rbuf_len;
    io_result_t r = march_recv_nonblocking(c);
    int         got_bytes = c->rbuf_len > before;

    if (r == IO_ERROR) {
        close_conn(evfd, c);
        return;
    }

    /* TLS: send what the session produced (handshake messages, tickets). */
    if (c->tls) {
        int s = tls_send_or_defer(evfd, c, 1);
        if (s < 0) return;
        if (s == 0) return;               /* resumes from handle_write */
    }

    if (r == IO_PARTIAL) {
        update_read_phase(c, got_bytes, 0);
        return;
    }

    /* IO_COMPLETE — at least one full request buffered.  Process all
     * pipelined requests in the buffer and send responses as one batch.
     * Same pattern as connection_thread (Phase 0 batch writev), but using
     * a single non-blocking writev attempt with EAGAIN fallback. */
    char        *clo = (char *)pipeline;
    closure_fn_t fn  = *(closure_fn_t *)(clo + 16);

    while (c->rbuf_len > 0) {
        march_http_request_t reqs[EVLOOP_PIPELINE_BATCH];
        size_t consumed = 0;
        int n = march_http_parse_pipelined(c->rbuf, c->rbuf_len,
                                            reqs, EVLOOP_PIPELINE_BATCH,
                                            &consumed);
        if (n <= 0) break;

        /* Build Conn objects NOW — reqs[i] pointers reference c->rbuf at its
         * current position.  We must call march_conn_from_parsed before the
         * memmove below, which overwrites the buffer and invalidates those
         * pointers.  march_conn_from_parsed copies all string data (via
         * march_string_lit) so the resulting Conn is safe after the shift. */
        void *pre_conns[EVLOOP_PIPELINE_BATCH];
        int   pre_keep_alives[EVLOOP_PIPELINE_BATCH];
        for (int i = 0; i < n; i++) {
            pre_keep_alives[i] = march_detect_keep_alive_simd(&reqs[i]);
            pre_conns[i]       = march_conn_from_parsed(&reqs[i],
                                                         c->rbuf, c->rbuf_len,
                                                         c->fd);
        }

        /* Shift consumed bytes NOW — before any send or early return.
         * Critical: EAGAIN/partial paths return early below; if the shift
         * were at the bottom of the loop, those paths would leave consumed
         * bytes in c->rbuf and re-parse the same requests next time.
         * Safe: pre_conns[] already copied all string data above. */
        if (consumed > 0 && consumed < c->rbuf_len) {
            memmove(c->rbuf, c->rbuf + consumed, c->rbuf_len - consumed);
            c->rbuf_len -= consumed;
        } else if (consumed >= c->rbuf_len) {
            c->rbuf_len = 0;
        }

        /* Build all N responses into a single iovec batch. */
        struct iovec     batch_iov[CONN_BATCH_IOV_MAX];
        int              batch_n = 0;
        march_response_t bresp;
        bresp.iov_count    = 0;
        bresp.scratch_used = 0;

        int batch_keep_alive = 1;
        int batch_ok         = 1;
        /* Results whose iovecs are in batch_iov.  Released after the writev
         * that drains them, or parked on the connection (pending_release)
         * when the write is deferred — their body/header strings are what
         * the deferred iovecs point at. */
        void *done_conns[EVLOOP_PIPELINE_BATCH];
        int   done_n = 0;

        for (int i = 0; i < n; i++) {
            int   keep_alive  = pre_keep_alives[i];
            void *conn        = pre_conns[i];
            /* One fresh closure reference per call — the compiled apply-fn
             * consumes it (see march_process_one_request in march_http.c). */
            march_incrc_local(pipeline);
            void *result_conn = fn(pipeline, conn);

            if (!result_conn) {
                if (batch_n > 0) { conn_out(c, batch_iov, batch_n); }
                if (c->tls) (void)march_tls_flush(c, NULL);
                else march_http_send_response(c->fd, 500, make_nil(),
                    march_string_lit("Internal Server Error", 21));
                march_http_release_conns(done_conns, &done_n);
                close_conn(evfd, c);
                batch_ok = 0;
                break;
            }

            /* WebSocket upgrade: complete the HTTP 101 handshake and hand
             * the fd off to a dedicated blocking thread that runs the
             * March WS handler closure.  The event-loop thread retains no
             * reference to the fd after this point. */
            char    *rc_p        = (char *)result_conn;
            void    *upgrade_val = *(void **)(rc_p + 112);
            int32_t  upgrade_tag = *(int32_t *)((char *)upgrade_val + 8);
            if (upgrade_tag == 1) {
                /* WebSocket upgrade. The handler runs on its own thread with
                 * the fd; this loop thread never waits on the client: the
                 * 101 is sent from the handler thread, and over TLS the
                 * batch's earlier responses drain first through the normal
                 * write phase (ws_pending, finished in handle_write). */
                void *ws_closure = *(void **)((char *)upgrade_val + 16);
                march_string *ws_key = (march_string *)find_ws_key_header(*(void **)(rc_p + 56));
                if (!ws_key || ws_key->len <= 0 || ws_key->len > 256) {
                    march_http_release_conns(done_conns, &done_n);
                    march_http_release_conn(result_conn);
                    close_conn(evfd, c);
                    batch_ok = 0;
                    break;
                }
                c->ws_key = malloc((size_t)ws_key->len);
                if (!c->ws_key) {
                    march_http_release_conns(done_conns, &done_n);
                    march_http_release_conn(result_conn);
                    close_conn(evfd, c);
                    batch_ok = 0;
                    break;
                }
                memcpy(c->ws_key, ws_key->data, (size_t)ws_key->len);
                c->ws_key_len = (size_t)ws_key->len;
                /* The WS thread's call consumes one closure reference; the
                 * result's `upgrade` field owns another, released with the
                 * result just below. */
                march_incrc(ws_closure);
                c->ws_closure = ws_closure;

                if (batch_n > 0) {
                    if (c->tls) conn_out(c, batch_iov, batch_n);
                    else writev(c->fd, batch_iov, batch_n);
                }
                march_http_release_conns(done_conns, &done_n);
                march_http_release_conn(result_conn);
                batch_ok = 0;
                if (c->tls) {
                    int sent = tls_send_or_defer(evfd, c, 1);
                    if (sent < 0) break;                 /* closed */
                    if (sent == 0) { c->ws_pending = 1; break; }
                }
                evloop_ws_handoff(evfd, c);
                break;
            }

            int64_t resp_status  = *(int64_t *)(rc_p + 72);
            void   *resp_headers = *(void **)(rc_p + 80);
            void   *resp_body    = *(void **)(rc_p + 88);
            if (resp_status == 0) resp_status = 200;

            /* Overflow guard: flush early if batch is near capacity. */
            if (batch_n + MARCH_RESPONSE_MAX_IOVEC > CONN_BATCH_IOV_MAX) {
                conn_out(c, batch_iov, batch_n);
                batch_n            = 0;
                march_http_release_conns(done_conns, &done_n);
                bresp.scratch_used = 0;
            }

            march_response_clear_no_free(&bresp);
            march_populate_response_ka(&bresp, resp_status,
                                        resp_headers, resp_body, keep_alive);
            memcpy(batch_iov + batch_n, bresp.iov,
                   (size_t)bresp.iov_count * sizeof(struct iovec));
            batch_n += bresp.iov_count;
            done_conns[done_n++] = result_conn;

            batch_keep_alive = keep_alive;
            if (!keep_alive) break;
        }

        if (!batch_ok) return;
        if (batch_n == 0) continue;

        if (c->tls) {
            ssize_t w = conn_out(c, batch_iov, batch_n);
            /* Encrypted (copied) into the session: the results are done. */
            march_http_release_conns(done_conns, &done_n);
            if (w < 0) { close_conn(evfd, c); return; }
            int s = tls_send_or_defer(evfd, c, batch_keep_alive);
            if (s <= 0) return;
            if (!batch_keep_alive) { close_conn(evfd, c); return; }
            continue;
        }

        /* ── Single non-blocking writev for the entire batch ─────── */
        ssize_t nsent = writev(c->fd, batch_iov, batch_n);

        if (nsent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            park_pending(c, done_conns, &done_n);
            evloop_defer_write(evfd, c, batch_iov, batch_n,
                               bresp.scratch_used, batch_keep_alive);
            return;
        }

        if (nsent < 0) {
            march_http_release_conns(done_conns, &done_n);
            close_conn(evfd, c);
            return;
        }

        /* Partial send — advance past sent iovecs, defer rest. */
        {
            size_t total = 0;
            for (int j = 0; j < batch_n; j++) total += batch_iov[j].iov_len;
            if ((size_t)nsent < total) {
                int    rem_pos = 0;
                size_t rem     = (size_t)nsent;
                while (rem > 0 && rem_pos < batch_n) {
                    if (rem >= batch_iov[rem_pos].iov_len) {
                        rem -= batch_iov[rem_pos].iov_len;
                        rem_pos++;
                    } else {
                        batch_iov[rem_pos].iov_base =
                            (char *)batch_iov[rem_pos].iov_base + rem;
                        batch_iov[rem_pos].iov_len -= rem;
                        rem = 0;
                    }
                }
                park_pending(c, done_conns, &done_n);
                evloop_defer_write(evfd, c,
                                   batch_iov + rem_pos, batch_n - rem_pos,
                                   bresp.scratch_used, batch_keep_alive);
                return;
            }
        }
        /* Every byte of the batch is out: the results' strings are no longer
         * referenced by any iovec. */
        march_http_release_conns(done_conns, &done_n);

        /* Full batch sent in one call (common case). */
        if (!batch_keep_alive) {
            close_conn(evfd, c);
            return;
        }
    }
    update_read_phase(c, got_bytes, 1);
    /* fd stays armed for read (edge-triggered, already registered). */
}

/* ── Handle a writable connection ─────────────────────────────────────── */

static void handle_write(int evfd, conn_state_t *c) {
    if (c->tls) {
        size_t sent = 0;
        io_result_t f = march_tls_flush(c, &sent);
        if (f == IO_PARTIAL) {
            if (sent && mts_is_established(c->tls)) conn_set_phase(c, PH_WRITE);
            return;
        }
        if (f == IO_ERROR) { close_conn(evfd, c); return; }
        if (c->ws_pending) { evloop_ws_handoff(evfd, c); return; }
        if (!c->keep_alive) { close_conn(evfd, c); return; }
        c->phase = CONN_PHASE_READING;
        if (mts_is_established(c->tls)) conn_set_phase(c, PH_IDLE);
        arm_read(evfd, c);
        /* Requests already decrypted, or ciphertext already fed, raise no
         * new readable edge: serve them now. */
        if (c->rbuf_len > 0 || mts_has_input(c->tls)) handle_read(evfd, c);
        return;
    }
    int         pos_before = c->wbuf_pos;
    size_t      len_before = c->wbuf_pos < c->wbuf_count ? c->wbuf[c->wbuf_pos].iov_len : 0;
    io_result_t r = march_send_nonblocking(c);

    if (r == IO_PARTIAL) {
        /* Progress resets the write deadline; a reader that keeps reading,
         * however slowly, is never cut. */
        if (c->wbuf_pos != pos_before ||
            (c->wbuf_pos < c->wbuf_count && c->wbuf[c->wbuf_pos].iov_len != len_before))
            conn_set_phase(c, PH_WRITE);
        return;   /* stay armed for write */
    }

    if (r == IO_ERROR || !c->keep_alive) {
        close_conn(evfd, c);
        return;
    }

    /* The deferred write has drained: release the results it referenced. */
    march_http_release_conns(c->pending_release, &c->pending_release_n);

    /* Response sent + keep-alive: back to reading. Pipelined requests that
     * arrived behind the deferred batch are still in rbuf (they used to be
     * discarded here) and raise no new readable edge: serve them now. */
    c->phase     = CONN_PHASE_READING;
    c->wbuf_count = 0;
    c->wbuf_pos   = 0;
    conn_set_phase(c, PH_IDLE);
    arm_read(evfd, c);
    if (c->rbuf_len > 0) handle_read(evfd, c);
}

/* ── Event loop (one per thread) ──────────────────────────────────────── */

static void *evloop_run(void *arg) {
    evloop_thread_arg_t *targ = (evloop_thread_arg_t *)arg;
    int    listener_fd    = targ->listener_fd;
    void  *pipeline       = targ->pipeline;
    int    is_tls         = targ->is_tls;
    int    plain_fd       = targ->plain_fd;
    void  *plain_pipeline = targ->plain_pipeline;
    int    port           = targ->port;
    free(targ);

    /* This OS thread runs compiled March code outside the scheduler — force
     * atomic "local" refcounts so concurrent evloop threads don't race on
     * shared closures/constants (pipeline closure, string literals). */
    march_rc_set_thread_concurrent(1);

#if EVLOOP_USE_KQUEUE
    int evfd = kqueue();
    if (evfd < 0) {
        fprintf(stderr, "march: kqueue() failed: %s\n", strerror(errno));
        close(listener_fd);
        return NULL;
    }

    /* Register the listener for read events. */
    struct kevent lev;
    if (listener_fd >= 0) {
        EV_SET(&lev, listener_fd, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL);
        kevent(evfd, &lev, 1, NULL, 0, NULL);
    }
    if (plain_fd >= 0) {
        EV_SET(&lev, plain_fd, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL);
        kevent(evfd, &lev, 1, NULL, 0, NULL);
    }

    struct kevent events[EVLOOP_MAX_EVENTS];
#elif EVLOOP_USE_EPOLL
    int evfd = epoll_create1(EPOLL_CLOEXEC);
    if (evfd < 0) {
        fprintf(stderr, "march: epoll_create1() failed: %s\n", strerror(errno));
        close(listener_fd);
        return NULL;
    }

    struct epoll_event lev;
    lev.events  = EPOLLIN | EPOLLET;
    lev.data.ptr = EVLOOP_MAIN_LISTENER;
    if (listener_fd >= 0) epoll_ctl(evfd, EPOLL_CTL_ADD, listener_fd, &lev);
    if (plain_fd >= 0) {
        lev.events  = EPOLLIN | EPOLLET;
        lev.data.ptr = EVLOOP_PLAIN_LISTENER;
        epoll_ctl(evfd, EPOLL_CTL_ADD, plain_fd, &lev);
    }

    struct epoll_event events[EVLOOP_MAX_EVENTS];
#endif

    /* ── Main event loop ──────────────────────────────────────────── */
    while (!atomic_load_explicit(&g_http_shutdown, memory_order_relaxed)) {
        /* Bootstrap mode: bind the HTTPS listener once a certificate exists
         * (checked at least once a second, the loop's longest wait). */
        if (listener_fd < 0 && !march_https_awaiting_cert()) {
            listener_fd = create_reuseport_listener(port);
            if (listener_fd >= 0) {
#if EVLOOP_USE_KQUEUE
                struct kevent bev;
                EV_SET(&bev, listener_fd, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL);
                kevent(evfd, &bev, 1, NULL, 0, NULL);
#elif EVLOOP_USE_EPOLL
                struct epoll_event bev;
                bev.events   = EPOLLIN | EPOLLET;
                bev.data.ptr = EVLOOP_MAIN_LISTENER;
                epoll_ctl(evfd, EPOLL_CTL_ADD, listener_fd, &bev);
#endif
            }
        }

#if EVLOOP_USE_KQUEUE
        int wait_ms = heap_wait_ms(1000);
        struct timespec ts = { .tv_sec = wait_ms / 1000,
                               .tv_nsec = (long)(wait_ms % 1000) * 1000000L };
        int nev = kevent(evfd, NULL, 0, events, EVLOOP_MAX_EVENTS, &ts);
#elif EVLOOP_USE_EPOLL
        int nev = epoll_wait(evfd, events, EVLOOP_MAX_EVENTS, heap_wait_ms(1000));
#endif

        if (nev < 0) {
            if (errno == EINTR) { sweep_deadlines(evfd); continue; }
            break;
        }

        for (int i = 0; i < nev; i++) {
#if EVLOOP_USE_KQUEUE
            int            ident = (int)events[i].ident;
            conn_state_t  *c     = (conn_state_t *)events[i].udata;

            if (listener_fd >= 0 && ident == listener_fd) {
                accept_connections(listener_fd, evfd, is_tls, pipeline);
                continue;
            }
            if (plain_fd >= 0 && ident == plain_fd) {
                accept_connections(plain_fd, evfd, 0, plain_pipeline);
                continue;
            }

            if (events[i].flags & (EV_EOF | EV_ERROR)) {
                if (c) close_conn(evfd, c);
                continue;
            }

            if (!c) continue;

            if (events[i].filter == EVFILT_READ) {
                handle_read(evfd, c);
            } else if (events[i].filter == EVFILT_WRITE) {
                handle_write(evfd, c);
            }
#elif EVLOOP_USE_EPOLL
            conn_state_t *c = (conn_state_t *)events[i].data.ptr;

            if (c == EVLOOP_MAIN_LISTENER) {
                accept_connections(listener_fd, evfd, is_tls, pipeline);
                continue;
            }
            if (c == EVLOOP_PLAIN_LISTENER) {
                accept_connections(plain_fd, evfd, 0, plain_pipeline);
                continue;
            }

            uint32_t ev = events[i].events;
            if (ev & (EPOLLERR | EPOLLHUP)) {
                close_conn(evfd, c);
                continue;
            }

            if (ev & EPOLLIN) {
                handle_read(evfd, c);
            }
            if (ev & EPOLLOUT) {
                handle_write(evfd, c);
            }
#endif
        }
        sweep_deadlines(evfd);
    }

    if (listener_fd >= 0) close(listener_fd);
    if (plain_fd >= 0) close(plain_fd);
    close(evfd);
    return NULL;
}

/* ── Public API: start the event-loop server ──────────────────────────── */

typedef struct {
    pthread_t *threads;
    int        nthreads;
    int        port;
    void      *pipeline;
    int        started;    /* out */
} evloop_spawn_t;

/* Open the listeners and start the event-loop threads.  Runs on the
 * scheduler's NATIVE stack (march_sched_run_on_sched_stack): the caller,
 * march_http_server_listen, is a green thread, and under ASAN pthread_create
 * runs with every signal blocked, so a lazy green-stack growth fault inside
 * it is fatal (silent exit 139; see march_sched_getaddrinfo's resolver spawn
 * in march_scheduler.c). */
static void evloop_spawn_all(void *argp) {
    evloop_spawn_t *s = (evloop_spawn_t *)argp;
    s->started = 0;
    int bootstrap = march_https_awaiting_cert();
    for (int i = 0; i < s->nthreads; i++) {
        int lfd = bootstrap ? -1 : create_reuseport_listener(s->port);
        if (lfd < 0 && !bootstrap) {
            fprintf(stderr, "march: SO_REUSEPORT listener[%d] failed: %s\n",
                    i, strerror(errno));
            continue;
        }
        int pfd = -1;
        if (g_march_https.plain_port > 0 && g_march_https.plain_pipeline) {
            pfd = create_reuseport_listener(g_march_https.plain_port);
            if (pfd < 0)
                fprintf(stderr, "march: plain listener[%d] on port %d failed: %s\n",
                        i, g_march_https.plain_port, strerror(errno));
        }

        evloop_thread_arg_t *arg = malloc(sizeof(evloop_thread_arg_t));
        if (!arg) { if (lfd >= 0) close(lfd); if (pfd >= 0) close(pfd); continue; }
        arg->listener_fd    = lfd;
        arg->pipeline       = s->pipeline;
        arg->is_tls         = g_march_https.tls;
        arg->plain_fd       = pfd;
        arg->plain_pipeline = g_march_https.plain_pipeline;
        arg->port           = s->port;

        if (pthread_create(&s->threads[s->started], NULL, evloop_run, arg) != 0) {
            fprintf(stderr, "march: evloop thread[%d] create failed: %s\n",
                    i, strerror(errno));
            free(arg);
            if (lfd >= 0) close(lfd);
            if (pfd >= 0) close(pfd);
            continue;
        }
        s->started++;
    }
}

void march_evloop_server_listen(int port, void *pipeline) {
    long ncpus = sysconf(_SC_NPROCESSORS_ONLN);
    if (ncpus <= 0) ncpus = 4;
    int nthreads = (int)ncpus;
    /* MARCH_HTTP_EVLOOP_THREADS: a fixed loop-thread count (tests use 1 to
     * show that one slow client never stalls the others on its thread). */
    const char *nt = getenv("MARCH_HTTP_EVLOOP_THREADS");
    if (nt && atoi(nt) > 0) nthreads = atoi(nt);

    fprintf(stderr, "march: event-loop server starting on port %d%s "
            "(%d threads, SO_REUSEPORT)\n", port,
            g_march_https.tls ? " (HTTPS)" : "", nthreads);
    if (g_march_https.plain_port > 0 && g_march_https.plain_pipeline)
        fprintf(stderr, "march: plain HTTP listener on port %d\n", g_march_https.plain_port);

    pthread_t *threads = malloc(sizeof(pthread_t) * (size_t)nthreads);
    if (!threads) {
        fprintf(stderr, "march: thread alloc failed\n");
        return;
    }

    evloop_spawn_t spawn = { threads, nthreads, port, pipeline, 0 };
    march_sched_run_on_sched_stack(evloop_spawn_all, &spawn);
    int started = spawn.started;

    if (started == 0) {
        fprintf(stderr, "march: no event-loop threads started — falling back\n");
        free(threads);
        return;
    }

    fprintf(stderr, "march: %d event-loop threads running\n", started);

    /* Wait for all threads to exit (on shutdown signal). */
    for (int i = 0; i < started; i++)
        pthread_join(threads[i], NULL);

    free(threads);
    fprintf(stderr, "march: event-loop server stopped\n");
}
