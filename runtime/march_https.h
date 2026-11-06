/* runtime/march_https.h — HTTPS configuration for the stdlib HTTP server.
 *
 * HttpServer.listen sets this process-global configuration through the
 * builtins below, then calls the existing march_http_server_listen, which
 * reads it. One HTTPS server per process (the spec's non-goal). The
 * certificate itself lives in march_tls_server.c's slot.
 * Design: specs/2026-11-05-https-server-design.md. */
#ifndef MARCH_HTTPS_H
#define MARCH_HTTPS_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    int   tls;              /* 1 once tls_configure succeeded */
    int   handshake_secs;   /* TLS handshake deadline */
    int   header_secs;      /* first byte -> end of headers */
    int   progress_secs;    /* body read / response write without progress */
    int   idle_secs;        /* keep-alive idle (from listen's idle_timeout) */
    int   poll_secs;        /* certificate file poll interval; 0 = off */
    int   wait_for_cert;    /* bootstrap: missing files are not fatal */
    int   files;            /* the certificate came from files (pollable) */
    int   plain_port;       /* extra plain-HTTP listener; 0 = none */
    void *plain_pipeline;   /* its pipeline closure (owned) */
} march_https_config_t;

extern march_https_config_t g_march_https;   /* defaults: 0,10,30,30,60,60,0,0,NULL */

/* kind 0 = files (a, b are paths), 1 = PEM text. Result(Int, String). */
void   *march_http_server_tls_configure(int64_t kind, void *a, void *b,
                                        int64_t poll_secs, int64_t wait_for_cert);
void    march_http_server_set_timeouts(int64_t handshake_secs, int64_t header_secs,
                                       int64_t progress_secs);
void   *march_http_server_reload_tls(int64_t kind, void *a, void *b);
void    march_http_server_plain_listener(int64_t port, void *pipeline);
int64_t march_http_conn_is_tls(int64_t fd);

/* WebSocket handoff of a connection that may be TLS (march_http.c). The
 * WsSocket Int for fd and its session (s may be NULL for plain), and the
 * teardown that closes it once no WebSocket operation is using the fd. */
typedef struct march_tls_session march_tls_session_t;
int64_t march_ws_sock_value(int fd, march_tls_session_t *s);
void    march_ws_tls_teardown(int fd, march_tls_session_t *s);
void    march_ws_send_101(int64_t v, const char *key, size_t key_len);

/* Called by march_http_server_listen: starts the certificate file poller
 * (once) for a TlsFiles server with a nonzero poll interval. */
void    march_https_on_listen(void);

/* 1 while an HTTPS server waits for its first certificate (bootstrap mode:
 * tls_wait_for_cert and no pair installed yet); its HTTPS listener is
 * bound once this turns 0. */
int     march_https_awaiting_cert(void);

#endif
