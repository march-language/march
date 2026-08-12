/* runtime/march_http_io.h — Non-blocking I/O infrastructure for the event loop.
 *
 * Defines per-connection state (conn_state_t) and non-blocking recv/send
 * state machines used by the kqueue/epoll event loop (march_http_evloop.c).
 *
 * Each connection progresses through phases:
 *   READING  → accumulate bytes until a complete HTTP request is buffered
 *   WRITING  → drain the response iovec until all bytes are sent
 *
 * The conn_state_t objects are pooled per-thread via a lock-free free-list
 * to avoid malloc/free on the hot path.
 */
#pragma once

#include "march_http_response.h"
#include "march_http_parse_simd.h"
#include <stdint.h>
#include <stddef.h>
#include <sys/uio.h>

/* ── Batch write sizing ───────────────────────────────────────────────── */

/* Maximum iovecs in one pipelined response batch.
 * EVLOOP_PIPELINE_BATCH(32) requests × ~16 iov/request typical = 512.
 * conn_state_t.wbuf is sized to this so it can hold a full deferred batch. */
#define CONN_BATCH_IOV_MAX 512

/* ── Connection phases ────────────────────────────────────────────────── */

typedef enum {
    CONN_PHASE_READING,          /* waiting for complete request(s) */
    CONN_PHASE_WRITING,          /* draining response iovec */
} conn_phase_t;

/* ── Per-connection read buffer ───────────────────────────────────────── */

/* Initial per-connection read buffer.  64 KB is enough for many pipelined GET
 * requests in a single recv() call; it GROWS on demand (doubling) for requests
 * with larger bodies — see march_recv_nonblocking. */
#define CONN_READ_BUF_SIZE (64 * 1024)

/* Hard ceiling on one buffered request.  Matches MAX_REQ_SIZE in march_http.c
 * so the two servers refuse the same things. */
#define CONN_READ_BUF_MAX  (32 * 1024 * 1024)

/* ── Per-connection state ─────────────────────────────────────────────── */

/* Maximum pipelined requests parsed from a single buffer slice. */
#define EVLOOP_PIPELINE_BATCH 32

typedef struct conn_state conn_state_t;
struct conn_state {
    int           fd;
    conn_phase_t  phase;
    int           keep_alive;

    /* ── Read state ─────────────────────────────────────────────────── */
    /* Heap-allocated and grown on demand, NOT inline: the event loop is
     * edge-triggered, so a full buffer that cannot be grown is a permanent
     * stall — no further readable event is delivered for data already sitting
     * in the socket, and the connection hangs until the peer gives up.
     * Retained across free-list reuse so a busy connection allocates once. */
    char         *rbuf;                  /* NULL until the first read */
    size_t        rbuf_cap;              /* allocated bytes */
    size_t        rbuf_len;              /* valid bytes in rbuf */

    /* ── Write state ────────────────────────────────────────────────── */
    /* Holds remaining iovecs when a batch writev returns EAGAIN.
     * Sized to hold a full CONN_BATCH_IOV_MAX-entry batch (defined above). */
    struct iovec  wbuf[CONN_BATCH_IOV_MAX];
    int           wbuf_count;
    int           wbuf_pos;              /* next iovec entry to send */

    /* Snapshot of TLS scratch bytes used by this batch's responses.
     * Must be exactly MARCH_RESPONSE_SCRATCH_SIZE so the pointer fixup in
     * evloop_defer_write is always safe — any TLS scratch offset is valid. */
    char          scratch_snap[MARCH_RESPONSE_SCRATCH_SIZE];
    size_t        scratch_snap_len;

    /* ── Free-list link ─────────────────────────────────────────────── */
    conn_state_t *next_free;
};

/* ── Non-blocking I/O return codes ───────────────────────────────────── */

typedef enum {
    IO_COMPLETE,   /* operation finished (full request read / response sent) */
    IO_PARTIAL,    /* need more events (EAGAIN) */
    IO_ERROR,      /* unrecoverable error — close connection */
} io_result_t;

/* ── Non-blocking recv ────────────────────────────────────────────────── */

/* Read available data from c->fd into c->rbuf.  Returns:
 *   IO_COMPLETE — at least one complete HTTP request is in the buffer
 *   IO_PARTIAL  — got EAGAIN, need to wait for more readability
 *   IO_ERROR    — connection closed or fatal error */
io_result_t march_recv_nonblocking(conn_state_t *c);

/* ── Non-blocking send ────────────────────────────────────────────────── */

/* Drain c->wbuf[wbuf_pos..wbuf_count] to c->fd.  Returns:
 *   IO_COMPLETE — entire response sent
 *   IO_PARTIAL  — got EAGAIN, need to wait for writability
 *   IO_ERROR    — fatal write error */
io_result_t march_send_nonblocking(conn_state_t *c);

/* ── Connection state pool (per-thread) ──────────────────────────────── */

/* Allocate a conn_state_t from the calling thread's free-list, or malloc
 * a fresh one if the list is empty.  The returned object is zeroed except
 * for the free-list pointer. */
conn_state_t *conn_state_alloc(void);

/* Return a conn_state_t to the calling thread's free-list for reuse. */
void conn_state_free(conn_state_t *c);

/* ── Helpers ──────────────────────────────────────────────────────────── */

/* Set fd to O_NONBLOCK.  Returns 0 on success, -1 on error. */
int march_set_nonblocking(int fd);
