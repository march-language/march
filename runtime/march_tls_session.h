/* runtime/march_tls_session.h — one server-side TLS session on memory BIOs.
 *
 * The session never touches a socket: the caller feeds it ciphertext it
 * received (mts_feed), takes the ciphertext it must send (mts_take_out), and
 * reads/writes plaintext in between. Both HTTP server modes drive it from
 * their own socket I/O, so blocking, parking and deadlines stay theirs.
 *
 * Functions never lock internally. A caller that shares a session between
 * threads (a WebSocket handler and a pushing task) wraps calls in
 * mts_lock/mts_unlock; mts_send_lock orders whole ciphertext sends so two
 * senders' records never interleave on the wire. No March heap is used.
 * Design: specs/2026-11-05-https-server-design.md. */
#ifndef MARCH_TLS_SESSION_H
#define MARCH_TLS_SESSION_H

#include <stddef.h>
#include <openssl/ssl.h>

typedef struct march_tls_session march_tls_session_t;

typedef enum {
    MTS_DONE       =  0,   /* progress made / handshake complete */
    MTS_NEED_INPUT =  1,   /* nothing more without more ciphertext */
    MTS_EOF        =  2,   /* peer sent close_notify */
    MTS_FAIL       = -1    /* protocol error; see mts_error */
} mts_rc;

march_tls_session_t *mts_new_server(SSL_CTX *ctx);   /* NULL on failure; takes its own ref on ctx */
void   mts_free(march_tls_session_t *s);
int    mts_feed(march_tls_session_t *s, const void *buf, size_t n);  /* 0 ok, -1 fail */
mts_rc mts_handshake(march_tls_session_t *s);
int    mts_is_established(const march_tls_session_t *s);
mts_rc mts_read(march_tls_session_t *s, void *out, size_t cap, size_t *got);
int    mts_write(march_tls_session_t *s, const void *buf, size_t n); /* 0 = whole buffer, -1 fail */
size_t mts_out_len(march_tls_session_t *s);
size_t mts_take_out(march_tls_session_t *s, void *buf, size_t cap);
int    mts_has_input(march_tls_session_t *s);
void   mts_shutdown(march_tls_session_t *s);
const char *mts_error(const march_tls_session_t *s);

void mts_lock(march_tls_session_t *s);
void mts_unlock(march_tls_session_t *s);
void mts_send_lock(march_tls_session_t *s);
void mts_send_unlock(march_tls_session_t *s);

#endif
