/* runtime/march_https.c — the HTTPS server's process-wide configuration,
 * the builtins that need no OpenSSL, and the fd -> TLS session registry.
 * Linked into every program; everything that needs OpenSSL is in
 * march_https_tls.c / march_tls_server.c / march_tls_session.c, which a
 * program links only when it reaches TLS (see march_tls_ops.h). */

#include "march_https.h"
#include "march_tls_ops.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

march_https_config_t g_march_https = {
    .tls = 0, .handshake_secs = 10, .header_secs = 30, .progress_secs = 30,
    .idle_secs = 60, .poll_secs = 60, .wait_for_cert = 0, .files = 0,
    .plain_port = 0, .plain_pipeline = NULL,
};

const march_tls_ops_t *g_march_tls_ops = NULL;

void march_http_server_set_timeouts(int64_t handshake_secs, int64_t header_secs,
                                    int64_t progress_secs) {
    if (handshake_secs > 0) g_march_https.handshake_secs = (int)handshake_secs;
    if (header_secs > 0)    g_march_https.header_secs = (int)header_secs;
    if (progress_secs > 0)  g_march_https.progress_secs = (int)progress_secs;
}

void march_http_server_plain_listener(int64_t port, void *pipeline) {
    /* The closure is owned (Borrow.extern_owned_builtins): it lives for the
     * whole server run, like listen's pipeline. */
    g_march_https.plain_port = (int)port;
    g_march_https.plain_pipeline = pipeline;
}

void march_https_on_listen(void) {
    static int started;
    if (started || !g_march_https.tls) return;
    started = 1;
    if (g_march_https.files && g_march_https.poll_secs > 0 && g_march_tls_ops &&
        g_march_tls_ops->poller_start(g_march_https.poll_secs) != 0)
        fprintf(stderr, "march: https: cannot start the certificate poller\n");
    if (march_https_awaiting_cert())
        fprintf(stderr, "march: https: no certificate yet; the HTTPS port opens "
                        "when one is installed\n");
}

int march_https_awaiting_cert(void) {
    return g_march_https.tls && g_march_tls_ops && g_march_tls_ops->slot_generation() == 0;
}

int64_t march_http_conn_is_tls(int64_t fd) {
    if (fd < 0 || fd > 0x7fffffff) return 0;
    return mts_registry_get((int)fd) != NULL;
}

/* ── the fd -> session registry ───────────────────────────────────────── */
/* WebSocket functions, HttpServer.scheme and both servers' close paths find
 * a connection's TLS session by its fd. Entries hold pointers only. */

static pthread_mutex_t g_reg_mu = PTHREAD_MUTEX_INITIALIZER;
static march_tls_session_t **g_reg;
static size_t g_reg_cap;

void mts_registry_put(int fd, march_tls_session_t *s) {
    if (fd < 0) return;
    pthread_mutex_lock(&g_reg_mu);
    if ((size_t)fd >= g_reg_cap) {
        size_t cap = g_reg_cap ? g_reg_cap : 1024;
        while (cap <= (size_t)fd) cap *= 2;
        march_tls_session_t **n = realloc(g_reg, cap * sizeof *n);
        if (!n) { pthread_mutex_unlock(&g_reg_mu); return; }
        memset(n + g_reg_cap, 0, (cap - g_reg_cap) * sizeof *n);
        g_reg = n;
        g_reg_cap = cap;
    }
    g_reg[fd] = s;
    pthread_mutex_unlock(&g_reg_mu);
}

march_tls_session_t *mts_registry_get(int fd) {
    march_tls_session_t *s = NULL;
    pthread_mutex_lock(&g_reg_mu);
    if (fd >= 0 && (size_t)fd < g_reg_cap) s = g_reg[fd];
    pthread_mutex_unlock(&g_reg_mu);
    return s;
}

march_tls_session_t *mts_registry_take(int fd) {
    march_tls_session_t *s = NULL;
    pthread_mutex_lock(&g_reg_mu);
    if (fd >= 0 && (size_t)fd < g_reg_cap) { s = g_reg[fd]; g_reg[fd] = NULL; }
    pthread_mutex_unlock(&g_reg_mu);
    return s;
}
