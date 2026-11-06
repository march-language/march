/* runtime/march_tls_session.c — one server-side TLS session on memory BIOs.
 * See march_tls_session.h for the contract. */

#include "march_tls_session.h"

#include <openssl/err.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct march_tls_session {
    SSL  *ssl;
    BIO  *rbio;          /* ciphertext in  (owned by ssl) */
    BIO  *wbio;          /* ciphertext out (owned by ssl) */
    int   established;
    pthread_mutex_t lock;
    pthread_mutex_t send_lock;
    char  err[256];
};

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
    return s;
}

void mts_free(march_tls_session_t *s) {
    if (!s) return;
    SSL_free(s->ssl);            /* frees both BIOs */
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
        if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE)
            return *got > 0 ? MTS_DONE : MTS_NEED_INPUT;
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
    return r > 0 ? (size_t)r : 0;
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
