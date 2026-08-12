/* runtime/march_http_io.c — Non-blocking I/O state machines for the event loop.
 *
 * Implements:
 *   - march_set_nonblocking()     — set O_NONBLOCK on an fd
 *   - march_recv_nonblocking()    — accumulate data, detect complete requests
 *   - march_send_nonblocking()    — drain iovec with partial-write tracking
 *   - conn_state_alloc/free()     — per-thread free-list pool
 */

#include "march_http_io.h"
#include "march_http_parse_simd.h"

#include <sys/socket.h>
#include <sys/uio.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

/* ── O_NONBLOCK helper ────────────────────────────────────────────────── */

int march_set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return -1;
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

/* ── Non-blocking recv ────────────────────────────────────────────────── */

io_result_t march_recv_nonblocking(conn_state_t *c) {
    /* Drain until EAGAIN, growing the buffer as needed.
     *
     * Both halves matter, and the event loop is edge-triggered (EPOLLET /
     * EV_CLEAR):
     *
     *   - Draining: with edge triggering the kernel reports readability only
     *     on a transition. Stopping while data remains means no further event
     *     is delivered for it.
     *   - Growing: the buffer used to be a fixed 64 KB inline array. A request
     *     whose body exceeded that filled it, failed to parse, and returned
     *     IO_PARTIAL — after which handle_read waited for an event that could
     *     never arrive. The connection hung until the client or proxy gave up,
     *     with nothing logged, because the request was never dispatched. Any
     *     upload over 64 KB was affected.
     *
     * Only a request past CONN_READ_BUF_MAX is refused, which is where the
     * thread-pool server draws the line too. */
    for (;;) {
        if (c->rbuf_len == c->rbuf_cap) {
            if (c->rbuf_cap >= CONN_READ_BUF_MAX)
                return IO_ERROR;                  /* genuinely too large */
            size_t ncap = c->rbuf_cap ? c->rbuf_cap * 2 : CONN_READ_BUF_SIZE;
            if (ncap > CONN_READ_BUF_MAX) ncap = CONN_READ_BUF_MAX;
            char *nbuf = (char *)realloc(c->rbuf, ncap);
            if (!nbuf) return IO_ERROR;
            c->rbuf     = nbuf;
            c->rbuf_cap = ncap;
        }

        ssize_t n = recv(c->fd, c->rbuf + c->rbuf_len,
                         c->rbuf_cap - c->rbuf_len, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;  /* drained */
            return IO_ERROR;
        }
        if (n == 0)
            return IO_ERROR;   /* peer closed */

        c->rbuf_len += (size_t)n;

        /* A complete request may be available already; dispatch it without
         * waiting for the socket to run dry. A request whose body is still
         * arriving does not parse, so this keeps draining for those. */
        march_http_request_t probe;
        size_t consumed = 0;
        if (march_http_parse_pipelined(c->rbuf, c->rbuf_len,
                                       &probe, 1, &consumed) > 0)
            return IO_COMPLETE;
    }

    /* Socket drained. One last parse: the final recv may have completed a
     * request exactly as the buffer ran dry. */
    if (c->rbuf_len > 0) {
        march_http_request_t probe;
        size_t consumed = 0;
        if (march_http_parse_pipelined(c->rbuf, c->rbuf_len,
                                       &probe, 1, &consumed) > 0)
            return IO_COMPLETE;
    }
    return IO_PARTIAL;
}

/* ── Non-blocking send ────────────────────────────────────────────────── */

io_result_t march_send_nonblocking(conn_state_t *c) {
    while (c->wbuf_pos < c->wbuf_count) {
        int remaining = c->wbuf_count - c->wbuf_pos;
        ssize_t n = writev(c->fd,
                           &c->wbuf[c->wbuf_pos],
                           remaining);
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                return IO_PARTIAL;
            if (errno == EINTR)
                continue;
            return IO_ERROR;
        }

        /* Advance past fully-sent iovec entries. */
        size_t sent = (size_t)n;
        while (sent > 0 && c->wbuf_pos < c->wbuf_count) {
            struct iovec *v = &c->wbuf[c->wbuf_pos];
            if (sent >= v->iov_len) {
                sent -= v->iov_len;
                c->wbuf_pos++;
            } else {
                v->iov_base = (char *)v->iov_base + sent;
                v->iov_len -= sent;
                sent = 0;
            }
        }
    }
    return IO_COMPLETE;
}

/* ── Per-thread connection state pool ─────────────────────────────────── */

static _Thread_local conn_state_t *tl_free_list = NULL;

conn_state_t *conn_state_alloc(void) {
    conn_state_t *c = tl_free_list;
    char  *keep_buf = NULL;
    size_t keep_cap = 0;
    if (c) {
        tl_free_list = c->next_free;
        /* Carry the read buffer across reuse — the memset below would
         * otherwise drop the pointer and leak it, and a connection that has
         * already grown its buffer should not have to grow it again. */
        keep_buf = c->rbuf;
        keep_cap = c->rbuf_cap;
    } else {
        c = (conn_state_t *)malloc(sizeof(conn_state_t));
        if (!c) return NULL;
    }
    memset(c, 0, sizeof(conn_state_t));
    c->rbuf     = keep_buf;
    c->rbuf_cap = keep_cap;
    return c;
}

void conn_state_free(conn_state_t *c) {
    c->next_free = tl_free_list;
    tl_free_list = c;
}
