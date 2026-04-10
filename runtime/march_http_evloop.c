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

/* Idle timeout for keep-alive connections (seconds).  After this, the
 * connection is closed to reclaim resources. */
#define EVLOOP_IDLE_TIMEOUT_S 10

/* ── Shutdown flag (shared with march_http.c) ─────────────────────────── */

extern _Atomic int g_http_shutdown;

/* ── Per-thread event loop arguments ──────────────────────────────────── */

typedef struct {
    int    listener_fd;   /* SO_REUSEPORT fd owned by this thread */
    void  *pipeline;      /* March closure (Conn → Conn) */
} evloop_thread_arg_t;

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
    addr.sin_addr.s_addr = INADDR_ANY;
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

static void accept_connections(int listener_fd, int evfd) {
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
        c->fd    = cfd;
        c->phase = CONN_PHASE_READING;

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
#if EVLOOP_USE_KQUEUE
    /* kqueue automatically removes filters when fd is closed. */
    (void)evfd;
#elif EVLOOP_USE_EPOLL
    epoll_ctl(evfd, EPOLL_CTL_DEL, c->fd, NULL);
#endif
    close(c->fd);
    conn_state_free(c);
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
    arm_write(evfd, c);
}

/* ── Handle a readable connection ─────────────────────────────────────── */

static void handle_read(int evfd, conn_state_t *c, void *pipeline) {
    io_result_t r = march_recv_nonblocking(c);

    if (r == IO_PARTIAL)
        return;

    if (r == IO_ERROR) {
        close_conn(evfd, c);
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

        for (int i = 0; i < n; i++) {
            int   keep_alive  = pre_keep_alives[i];
            void *conn        = pre_conns[i];
            void *result_conn = fn(pipeline, conn);

            if (!result_conn) {
                if (batch_n > 0) { writev(c->fd, batch_iov, batch_n); }
                march_http_send_response(c->fd, 500, make_nil(),
                    march_string_lit("Internal Server Error", 21));
                close_conn(evfd, c);
                batch_ok = 0;
                break;
            }

            /* WebSocket upgrade — fall through to close (full WS async
             * support requires a separate handler, out of scope here). */
            char    *rc_p        = (char *)result_conn;
            void    *upgrade_val = *(void **)(rc_p + 112);
            int32_t  upgrade_tag = *(int32_t *)((char *)upgrade_val + 8);
            if (upgrade_tag == 1) {
                if (batch_n > 0) { writev(c->fd, batch_iov, batch_n); }
                close_conn(evfd, c);
                batch_ok = 0;
                break;
            }

            int64_t resp_status  = *(int64_t *)(rc_p + 72);
            void   *resp_headers = *(void **)(rc_p + 80);
            void   *resp_body    = *(void **)(rc_p + 88);
            if (resp_status == 0) resp_status = 200;

            /* Overflow guard: flush early if batch is near capacity. */
            if (batch_n + MARCH_RESPONSE_MAX_IOVEC > CONN_BATCH_IOV_MAX) {
                writev(c->fd, batch_iov, batch_n);
                batch_n            = 0;
                bresp.scratch_used = 0;
            }

            march_response_clear_no_free(&bresp);
            march_populate_response_ka(&bresp, resp_status,
                                        resp_headers, resp_body, keep_alive);
            memcpy(batch_iov + batch_n, bresp.iov,
                   (size_t)bresp.iov_count * sizeof(struct iovec));
            batch_n += bresp.iov_count;

            batch_keep_alive = keep_alive;
            if (!keep_alive) break;
        }

        if (!batch_ok) return;
        if (batch_n == 0) continue;

        /* ── Single non-blocking writev for the entire batch ─────── */
        ssize_t nsent = writev(c->fd, batch_iov, batch_n);

        if (nsent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            evloop_defer_write(evfd, c, batch_iov, batch_n,
                               bresp.scratch_used, batch_keep_alive);
            return;
        }

        if (nsent < 0) {
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
                evloop_defer_write(evfd, c,
                                   batch_iov + rem_pos, batch_n - rem_pos,
                                   bresp.scratch_used, batch_keep_alive);
                return;
            }
        }

        /* Full batch sent in one call (common case). */
        if (!batch_keep_alive) {
            close_conn(evfd, c);
            return;
        }
    }
    /* fd stays armed for read (edge-triggered, already registered). */
}

/* ── Handle a writable connection ─────────────────────────────────────── */

static void handle_write(int evfd, conn_state_t *c) {
    /* This path is used when we switch to non-blocking writes (Phase 3).
     * For now, responses are sent synchronously in handle_read. */
    io_result_t r = march_send_nonblocking(c);

    if (r == IO_PARTIAL)
        return;   /* stay armed for write */

    if (r == IO_ERROR || !c->keep_alive) {
        close_conn(evfd, c);
        return;
    }

    /* Response sent + keep-alive: reset for next request. */
    c->phase     = CONN_PHASE_READING;
    c->rbuf_len  = 0;
    c->wbuf_count = 0;
    c->wbuf_pos   = 0;
    arm_read(evfd, c);
}

/* ── Event loop (one per thread) ──────────────────────────────────────── */

static void *evloop_run(void *arg) {
    evloop_thread_arg_t *targ = (evloop_thread_arg_t *)arg;
    int    listener_fd = targ->listener_fd;
    void  *pipeline    = targ->pipeline;
    free(targ);

#if EVLOOP_USE_KQUEUE
    int evfd = kqueue();
    if (evfd < 0) {
        fprintf(stderr, "march: kqueue() failed: %s\n", strerror(errno));
        close(listener_fd);
        return NULL;
    }

    /* Register the listener for read events. */
    struct kevent lev;
    EV_SET(&lev, listener_fd, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL);
    kevent(evfd, &lev, 1, NULL, 0, NULL);

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
    lev.data.ptr = NULL;  /* NULL = listener sentinel */
    epoll_ctl(evfd, EPOLL_CTL_ADD, listener_fd, &lev);

    struct epoll_event events[EVLOOP_MAX_EVENTS];
#endif

    /* ── Main event loop ──────────────────────────────────────────── */
    while (!atomic_load_explicit(&g_http_shutdown, memory_order_relaxed)) {

#if EVLOOP_USE_KQUEUE
        struct timespec ts = { .tv_sec = 1, .tv_nsec = 0 };
        int nev = kevent(evfd, NULL, 0, events, EVLOOP_MAX_EVENTS, &ts);
#elif EVLOOP_USE_EPOLL
        int nev = epoll_wait(evfd, events, EVLOOP_MAX_EVENTS, 1000);
#endif

        if (nev < 0) {
            if (errno == EINTR) continue;
            break;
        }

        for (int i = 0; i < nev; i++) {
#if EVLOOP_USE_KQUEUE
            int            ident = (int)events[i].ident;
            conn_state_t  *c     = (conn_state_t *)events[i].udata;

            if (ident == listener_fd) {
                accept_connections(listener_fd, evfd);
                continue;
            }

            if (events[i].flags & (EV_EOF | EV_ERROR)) {
                if (c) close_conn(evfd, c);
                continue;
            }

            if (!c) continue;

            if (events[i].filter == EVFILT_READ) {
                handle_read(evfd, c, pipeline);
            } else if (events[i].filter == EVFILT_WRITE) {
                handle_write(evfd, c);
            }
#elif EVLOOP_USE_EPOLL
            conn_state_t *c = (conn_state_t *)events[i].data.ptr;

            if (c == NULL) {
                /* Listener fd sentinel. */
                accept_connections(listener_fd, evfd);
                continue;
            }

            uint32_t ev = events[i].events;
            if (ev & (EPOLLERR | EPOLLHUP)) {
                close_conn(evfd, c);
                continue;
            }

            if (ev & EPOLLIN) {
                handle_read(evfd, c, pipeline);
            }
            if (ev & EPOLLOUT) {
                handle_write(evfd, c);
            }
#endif
        }
    }

    close(listener_fd);
    close(evfd);
    return NULL;
}

/* ── Public API: start the event-loop server ──────────────────────────── */

void march_evloop_server_listen(int port, void *pipeline) {
    long ncpus = sysconf(_SC_NPROCESSORS_ONLN);
    if (ncpus <= 0) ncpus = 4;
    int nthreads = (int)ncpus;

    fprintf(stderr, "march: event-loop server starting on port %d "
            "(%d threads, SO_REUSEPORT)\n", port, nthreads);

    pthread_t *threads = malloc(sizeof(pthread_t) * (size_t)nthreads);
    if (!threads) {
        fprintf(stderr, "march: thread alloc failed\n");
        return;
    }

    int started = 0;
    for (int i = 0; i < nthreads; i++) {
        int lfd = create_reuseport_listener(port);
        if (lfd < 0) {
            fprintf(stderr, "march: SO_REUSEPORT listener[%d] failed: %s\n",
                    i, strerror(errno));
            continue;
        }

        evloop_thread_arg_t *arg = malloc(sizeof(evloop_thread_arg_t));
        if (!arg) { close(lfd); continue; }
        arg->listener_fd = lfd;
        arg->pipeline    = pipeline;

        if (pthread_create(&threads[started], NULL, evloop_run, arg) != 0) {
            fprintf(stderr, "march: evloop thread[%d] create failed: %s\n",
                    i, strerror(errno));
            free(arg);
            close(lfd);
            continue;
        }
        started++;
    }

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
