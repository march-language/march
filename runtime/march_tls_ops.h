/* runtime/march_tls_ops.h — how the always-linked HTTP runtime reaches TLS.
 *
 * march_http.c, march_http_evloop.c and march_http_io.c are linked into
 * every program, while the OpenSSL code (march_tls_session.c,
 * march_tls_server.c, march_https_tls.c) sits in the runtime's optional
 * archive and is linked only into a program that reaches TLS, so a program
 * that never does records no libssl/libcrypto (test/test_link_deps.ml;
 * specs/2026-09-23-static-compile-output-design.md §5.1). A direct call from
 * the always-linked files would pull those members, and OpenSSL, into every
 * binary. So those files call through g_march_tls_ops, which
 * http_server_tls_configure (march_https_tls.c) installs; until then it is
 * NULL, and no TLS session can exist, so no call is ever made through it.
 *
 * A file that is always linked defines MARCH_TLS_VIA_OPS before including
 * this header: the mts_* calls it makes then compile to calls through the
 * table, with no source change at the call sites.
 */
#ifndef MARCH_TLS_OPS_H
#define MARCH_TLS_OPS_H

#include <stddef.h>
#include <stdint.h>
#include "march_tls_session.h"
#include "march_tls_server.h"

typedef struct {
    march_tls_session_t *(*new_from_slot)(void);
    int    (*feed)(march_tls_session_t *, const void *, size_t);
    mts_rc (*handshake)(march_tls_session_t *);
    int    (*is_established)(const march_tls_session_t *);
    mts_rc (*read)(march_tls_session_t *, void *, size_t, size_t *);
    int    (*write)(march_tls_session_t *, const void *, size_t);
    size_t (*out_len)(march_tls_session_t *);
    size_t (*take_out)(march_tls_session_t *, void *, size_t);
    int    (*has_input)(march_tls_session_t *);
    void   (*shutdown)(march_tls_session_t *);
    void   (*free_)(march_tls_session_t *);
    void   (*lock)(march_tls_session_t *);
    void   (*unlock)(march_tls_session_t *);
    void   (*send_lock)(march_tls_session_t *);
    void   (*send_unlock)(march_tls_session_t *);
    uint64_t (*slot_generation)(void);
    int    (*poller_start)(int);
    void   (*retain)(march_tls_session_t *);
    uint32_t (*gen)(const march_tls_session_t *);
    void   (*ws_begin)(march_tls_session_t *);
    int    (*ws_enter)(march_tls_session_t *);
    void   (*ws_leave)(march_tls_session_t *);
    void   (*ws_close)(march_tls_session_t *);
    int    (*ws_fd_busy)(march_tls_session_t *);
    int    (*ws_send)(march_tls_session_t *, const void *, size_t, const void *, size_t,
                      int (*)(int, const void *, size_t), int);
} march_tls_ops_t;

/* Defined in march_https.c (always linked); set by march_https_tls.c. */
extern const march_tls_ops_t *g_march_tls_ops;

/* A session on the slot's current certificate (NULL when none is installed). */
march_tls_session_t *mts_new_from_slot(void);

/* The table of the real implementations (march_tls_server.c). */
extern const march_tls_ops_t mts_real_ops;

#ifdef MARCH_TLS_VIA_OPS
#define mts_new_from_slot()     (g_march_tls_ops->new_from_slot())
#define mts_feed(...)           (g_march_tls_ops->feed(__VA_ARGS__))
#define mts_handshake(...)      (g_march_tls_ops->handshake(__VA_ARGS__))
#define mts_is_established(...) (g_march_tls_ops->is_established(__VA_ARGS__))
#define mts_read(...)           (g_march_tls_ops->read(__VA_ARGS__))
#define mts_write(...)          (g_march_tls_ops->write(__VA_ARGS__))
#define mts_out_len(...)        (g_march_tls_ops->out_len(__VA_ARGS__))
#define mts_take_out(...)       (g_march_tls_ops->take_out(__VA_ARGS__))
#define mts_has_input(...)      (g_march_tls_ops->has_input(__VA_ARGS__))
#define mts_shutdown(...)       (g_march_tls_ops->shutdown(__VA_ARGS__))
#define mts_free(...)           (g_march_tls_ops->free_(__VA_ARGS__))
#define mts_lock(...)           (g_march_tls_ops->lock(__VA_ARGS__))
#define mts_unlock(...)         (g_march_tls_ops->unlock(__VA_ARGS__))
#define mts_send_lock(...)      (g_march_tls_ops->send_lock(__VA_ARGS__))
#define mts_send_unlock(...)    (g_march_tls_ops->send_unlock(__VA_ARGS__))
#define mts_retain(...)         (g_march_tls_ops->retain(__VA_ARGS__))
#define mts_gen(...)            (g_march_tls_ops->gen(__VA_ARGS__))
#define mts_ws_begin(...)       (g_march_tls_ops->ws_begin(__VA_ARGS__))
#define mts_ws_enter(...)       (g_march_tls_ops->ws_enter(__VA_ARGS__))
#define mts_ws_leave(...)       (g_march_tls_ops->ws_leave(__VA_ARGS__))
#define mts_ws_close(...)       (g_march_tls_ops->ws_close(__VA_ARGS__))
#define mts_ws_fd_busy(...)     (g_march_tls_ops->ws_fd_busy(__VA_ARGS__))
#define mts_ws_send(...)        (g_march_tls_ops->ws_send(__VA_ARGS__))
#endif

#endif
