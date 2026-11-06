/* runtime/march_tls_server.h — the HTTPS server's certificate state.
 *
 * One process-global slot holds the live SSL_CTX. Installing a new pair
 * builds a fresh context outside the lock and swaps it in; connections that
 * already acquired the old one keep it (SSL_CTX is refcounted), new ones get
 * the new one. A pair that does not load, does not match, or (on reload) has
 * expired is refused and the old context stays. The poller watches a cert/key
 * file pair and installs it when its content changes; the registry maps a
 * connection's fd to its TLS session so WebSocket I/O, which only has the fd,
 * can find it. No March heap is used.
 * Design: specs/2026-11-05-https-server-design.md. */
#ifndef MARCH_TLS_SERVER_H
#define MARCH_TLS_SERVER_H

#include <stddef.h>
#include <stdint.h>
#include <openssl/ssl.h>

typedef struct march_tls_session march_tls_session_t;

/* Key-exchange groups every March TLS context offers, hybrid post-quantum
 * first (rationale at its use in march_tls.c). A library that rejects the
 * list keeps its own defaults. */
#define MARCH_TLS_PQ_GROUPS "X25519MLKEM768:X25519:P-256:P-384:P-521"

/* Build a server context from PEM text: the first certificate in [cert] is
 * the leaf, the rest its chain. 0 ok (*out owns one ref), nonzero with a
 * message in err. allow_expired = 0 refuses a leaf whose notAfter has passed. */
int  mts_ctx_from_pem(const char *cert, size_t cert_len, const char *key, size_t key_len,
                      int allow_expired, SSL_CTX **out, char *err, size_t errlen);
int  mts_slot_install_pem(const char *cert, size_t cert_len, const char *key, size_t key_len,
                          int allow_expired, char *err, size_t errlen);
SSL_CTX *mts_slot_acquire(void);          /* +1 ref or NULL; release with SSL_CTX_free */
uint64_t mts_slot_generation(void);       /* bumps on each successful install */

typedef void (*mts_consumer_fn)(const char *cert, size_t cert_len,
                                const char *key, size_t key_len, void *arg);
void mts_slot_add_consumer(mts_consumer_fn fn, void *arg);   /* called after each install */

typedef enum { MTS_POLL_UNCHANGED, MTS_POLL_INSTALLED, MTS_POLL_REFUSED, MTS_POLL_MISSING } mts_poll_rc;
void mts_poller_set_paths(const char *cert_path, const char *key_path);
mts_poll_rc mts_poll_once(char *err, size_t errlen);     /* reload: refuses an expired leaf */
/* The first read at startup: like mts_poll_once, but an expired leaf is
 * installed with a warning (a server that had to restart keeps serving). */
mts_poll_rc mts_poll_initial(char *err, size_t errlen);
int  mts_poller_start(int poll_secs);     /* detached pthread; 0 ok */

void mts_registry_put(int fd, march_tls_session_t *s);
march_tls_session_t *mts_registry_get(int fd);
march_tls_session_t *mts_registry_take(int fd);

#endif
