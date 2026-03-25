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
    /* Read as much as the buffer can hold. */
    size_t space = CONN_READ_BUF_SIZE - c->rbuf_len;
    if (space == 0) {
        /* Buffer full — if we still can't parse, the request is too large. */
        return IO_ERROR;
    }

    ssize_t n = recv(c->fd, c->rbuf + c->rbuf_len, space, 0);
    if (n < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            return IO_PARTIAL;
        return IO_ERROR;
    }
    if (n == 0)
        return IO_ERROR;   /* peer closed */

    c->rbuf_len += (size_t)n;

    /* Check if we have at least one complete HTTP request by attempting
     * to parse.  We use the SIMD parser in "probe" mode — parse one
     * request to see if the headers are complete. */
    march_http_request_t probe;
    size_t consumed = 0;
    int nr = march_http_parse_pipelined(c->rbuf, c->rbuf_len,
                                         &probe, 1, &consumed);
    if (nr > 0)
        return IO_COMPLETE;

    /* Incomplete — need more data. */
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
    if (c) {
        tl_free_list = c->next_free;
    } else {
        c = (conn_state_t *)malloc(sizeof(conn_state_t));
        if (!c) return NULL;
    }
    /* Zero everything except the free-list pointer is irrelevant. */
    memset(c, 0, sizeof(conn_state_t));
    return c;
}

void conn_state_free(conn_state_t *c) {
    c->next_free = tl_free_list;
    tl_free_list = c;
}
