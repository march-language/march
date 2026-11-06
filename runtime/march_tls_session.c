/* runtime/march_tls_session.c — one server-side TLS session on memory BIOs.
 * See march_tls_session.h for the contract. */

#include "march_tls_session.h"

#include <openssl/buffer.h>
#include <openssl/err.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ws_chunk { struct ws_chunk *next; size_t len; char data[]; } ws_chunk;

struct march_tls_session {
    SSL  *ssl;
    BIO  *rbio;          /* ciphertext in  (owned by ssl) */
    BIO  *wbio;          /* ciphertext out (owned by ssl) */
    int   established;
    _Atomic int refs;    /* the owner's + each in-flight registry lookup's */
    uint32_t gen;        /* unique per process, never 0 */
    pthread_mutex_t lock;
    pthread_mutex_t send_lock;
    /* WebSocket state, under [lock] (see "WebSocket" below). */
    int   ws;            /* handed to a WebSocket handler */
    int   closed;        /* its server is closing it */
    int   fd_users;      /* WebSocket operations touching the fd right now */
    int   draining;      /* one sender is sending the queue */
    ws_chunk *q_head, *q_tail;
    char  err[256];
};

/* A memory BIO's buffer only grows: after a large response it would hold its
 * peak size for the rest of the connection. Replaced once drained and big. */
#define MTS_BIO_KEEP_MAX (256 * 1024)

static size_t bio_capacity(BIO *b) {
    BUF_MEM *bm = NULL;
    BIO_get_mem_ptr(b, &bm);
    return bm ? bm->max : 0;
}

/* Record the reason for a failure: the OpenSSL error queue if it has one,
 * else the SSL_get_error code. Clears the thread's queue either way, so a
 * later session on this thread never reads a stale error. */
static void set_error(march_tls_session_t *s, int ssl_err) {
    unsigned long e = ERR_get_error();
    if (e != 0)
        ERR_error_string_n(e, s->err, sizeof s->err);
    else
        snprintf(s->err, sizeof s->err, "TLS error (SSL_get_error %d)", ssl_err);
    ERR_clear_error();
}

march_tls_session_t *mts_new_server(SSL_CTX *ctx) {
    if (!ctx) return NULL;
    march_tls_session_t *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    s->ssl = SSL_new(ctx);
    s->rbio = BIO_new(BIO_s_mem());
    s->wbio = BIO_new(BIO_s_mem());
    if (!s->ssl || !s->rbio || !s->wbio) {
        /* The BIOs are not attached yet, so SSL_free leaves them to us. */
        SSL_free(s->ssl);
        BIO_free(s->rbio);
        BIO_free(s->wbio);
        free(s);
        ERR_clear_error();
        return NULL;
    }
    /* An empty memory BIO reports "retry" rather than EOF, which maps to
     * SSL_ERROR_WANT_READ: exactly "need more ciphertext". */
    BIO_set_mem_eof_return(s->rbio, -1);
    SSL_set_bio(s->ssl, s->rbio, s->wbio);
    SSL_set_accept_state(s->ssl);
    pthread_mutex_init(&s->lock, NULL);
    pthread_mutex_init(&s->send_lock, NULL);
    static _Atomic uint32_t next_gen;
    uint32_t g;
    do { g = atomic_fetch_add(&next_gen, 1) + 1; } while (g == 0);
    s->gen = g;
    atomic_store(&s->refs, 1);
    return s;
}

void mts_retain(march_tls_session_t *s) { atomic_fetch_add(&s->refs, 1); }

uint32_t mts_gen(const march_tls_session_t *s) { return s->gen; }

void mts_free(march_tls_session_t *s) {
    if (!s || atomic_fetch_sub(&s->refs, 1) != 1) return;
    SSL_free(s->ssl);            /* frees both BIOs */
    for (ws_chunk *c = s->q_head, *n; c; c = n) { n = c->next; free(c); }
    pthread_mutex_destroy(&s->lock);
    pthread_mutex_destroy(&s->send_lock);
    free(s);
}

int mts_feed(march_tls_session_t *s, const void *buf, size_t n) {
    if (n == 0) return 0;
    if (n > (size_t)0x7fffffff) return -1;
    return BIO_write(s->rbio, buf, (int)n) == (int)n ? 0 : -1;
}

mts_rc mts_handshake(march_tls_session_t *s) {
    if (s->established) return MTS_DONE;
    int r = SSL_do_handshake(s->ssl);
    if (r == 1) { s->established = 1; return MTS_DONE; }
    int e = SSL_get_error(s->ssl, r);
    if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE) return MTS_NEED_INPUT;
    set_error(s, e);
    return MTS_FAIL;
}

int mts_is_established(const march_tls_session_t *s) { return s->established; }

mts_rc mts_read(march_tls_session_t *s, void *out, size_t cap, size_t *got) {
    *got = 0;
    if (!s->established) {
        mts_rc h = mts_handshake(s);
        if (h != MTS_DONE) return h;
    }
    while (*got < cap) {
        size_t k = 0;
        int r = SSL_read_ex(s->ssl, (char *)out + *got, cap - *got, &k);
        if (r == 1) { *got += k; continue; }
        int e = SSL_get_error(s->ssl, r);
        if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE) {
            if (BIO_ctrl_pending(s->rbio) == 0 && bio_capacity(s->rbio) > MTS_BIO_KEEP_MAX) {
                BIO *nb = BIO_new(BIO_s_mem());
                if (nb) {
                    BIO_set_mem_eof_return(nb, -1);
                    SSL_set0_rbio(s->ssl, nb);        /* frees the old one */
                    s->rbio = nb;
                }
            }
            return *got > 0 ? MTS_DONE : MTS_NEED_INPUT;
        }
        if (e == SSL_ERROR_ZERO_RETURN)
            return *got > 0 ? MTS_DONE : MTS_EOF;
        if (*got > 0) { ERR_clear_error(); return MTS_DONE; }
        set_error(s, e);
        return MTS_FAIL;
    }
    return MTS_DONE;
}

int mts_write(march_tls_session_t *s, const void *buf, size_t n) {
    size_t off = 0;
    while (off < n) {
        size_t w = 0;
        int r = SSL_write_ex(s->ssl, (const char *)buf + off, n - off, &w);
        if (r != 1) { set_error(s, SSL_get_error(s->ssl, r)); return -1; }
        off += w;
    }
    return 0;
}

size_t mts_out_len(march_tls_session_t *s) { return BIO_ctrl_pending(s->wbio); }

size_t mts_take_out(march_tls_session_t *s, void *buf, size_t cap) {
    if (cap == 0) return 0;
    if (cap > (size_t)0x7fffffff) cap = 0x7fffffff;
    int r = BIO_read(s->wbio, buf, (int)cap);
    if (BIO_ctrl_pending(s->wbio) == 0 && bio_capacity(s->wbio) > MTS_BIO_KEEP_MAX) {
        BIO *nb = BIO_new(BIO_s_mem());
        if (nb) {
            SSL_set0_wbio(s->ssl, nb);                /* frees the old one */
            s->wbio = nb;
        }
    }
    return r > 0 ? (size_t)r : 0;
}

size_t mts_buffer_capacity(march_tls_session_t *s) {
    return bio_capacity(s->rbio) + bio_capacity(s->wbio);
}

int mts_has_input(march_tls_session_t *s) {
    return SSL_pending(s->ssl) > 0 || BIO_ctrl_pending(s->rbio) > 0;
}

void mts_shutdown(march_tls_session_t *s) {
    if (s->established) {
        if (SSL_shutdown(s->ssl) < 0) ERR_clear_error();
    }
}

const char *mts_error(const march_tls_session_t *s) { return s->err; }

void mts_lock(march_tls_session_t *s)        { pthread_mutex_lock(&s->lock); }
void mts_unlock(march_tls_session_t *s)      { pthread_mutex_unlock(&s->lock); }
void mts_send_lock(march_tls_session_t *s)   { pthread_mutex_lock(&s->send_lock); }
void mts_send_unlock(march_tls_session_t *s) { pthread_mutex_unlock(&s->send_lock); }

/* ── WebSocket ─────────────────────────────────────────────────────────── */
/* These lock internally. A WebSocket handler and other tasks may use the
 * session at once; [fd_users] counts the operations that are touching the
 * socket, so the server that closes the connection (mts_ws_close, then
 * shutdown(2), then waiting for mts_ws_fd_busy to clear) never closes an fd
 * that a send or recv is still using, and no operation starts after it. */

void mts_ws_begin(march_tls_session_t *s) {
    pthread_mutex_lock(&s->lock);
    s->ws = 1;
    pthread_mutex_unlock(&s->lock);
}

int mts_ws_enter(march_tls_session_t *s) {
    pthread_mutex_lock(&s->lock);
    int ok = s->ws && !s->closed;
    if (ok) s->fd_users++;
    pthread_mutex_unlock(&s->lock);
    return ok;
}

void mts_ws_leave(march_tls_session_t *s) {
    pthread_mutex_lock(&s->lock);
    s->fd_users--;
    pthread_mutex_unlock(&s->lock);
}

void mts_ws_close(march_tls_session_t *s) {
    pthread_mutex_lock(&s->lock);
    s->closed = 1;
    pthread_mutex_unlock(&s->lock);
}

int mts_ws_fd_busy(march_tls_session_t *s) {
    pthread_mutex_lock(&s->lock);
    int busy = s->fd_users > 0;
    pthread_mutex_unlock(&s->lock);
    return busy;
}

/* Encrypt a then b and queue the ciphertext; if no other sender is
 * draining the queue, drain it here with [send_all], which may wait (park)
 * for the socket. No lock is held while it waits, so a parked sender never
 * blocks another thread on a mutex; senders that find a drain in progress
 * return at once and their frames go out in queue order. 0 ok, -1 when the
 * session is closed or a send failed. */
int mts_ws_send(march_tls_session_t *s, const void *a, size_t al, const void *b, size_t bl,
                int (*send_all)(int fd, const void *buf, size_t n), int fd) {
    pthread_mutex_lock(&s->lock);
    if (!s->ws || s->closed) { pthread_mutex_unlock(&s->lock); return -1; }
    int ok = (al == 0 || mts_write(s, a, al) == 0) && (bl == 0 || mts_write(s, b, bl) == 0);
    size_t n = ok ? mts_out_len(s) : 0;
    if (n > 0) {
        ws_chunk *c = malloc(sizeof *c + n);
        if (!c) ok = 0;
        else {
            c->next = NULL;
            c->len = mts_take_out(s, c->data, n);
            if (s->q_tail) s->q_tail->next = c; else s->q_head = c;
            s->q_tail = c;
        }
    }
    if (!ok) { pthread_mutex_unlock(&s->lock); return -1; }
    if (s->draining) { pthread_mutex_unlock(&s->lock); return 0; }
    s->draining = 1;
    s->fd_users++;
    int rc = 0;
    for (;;) {
        ws_chunk *c = s->q_head;
        if (!c || s->closed) break;
        s->q_head = c->next;
        if (!s->q_head) s->q_tail = NULL;
        pthread_mutex_unlock(&s->lock);
        int r = send_all(fd, c->data, c->len);
        free(c);
        pthread_mutex_lock(&s->lock);
        if (r < 0) { rc = -1; break; }
    }
    if (rc < 0 || s->closed) {
        for (ws_chunk *c = s->q_head, *nx; c; c = nx) { nx = c->next; free(c); }
        s->q_head = s->q_tail = NULL;
        if (s->closed) rc = -1;
    }
    s->draining = 0;
    s->fd_users--;
    pthread_mutex_unlock(&s->lock);
    return rc;
}

