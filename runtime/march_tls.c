/* runtime/march_tls.c — TLS builtins for March (OpenSSL 3 backend).
 *
 * Wraps OpenSSL 3.x to provide TLS client and server support over existing
 * TCP file descriptors.  SSL_CTX * and SSL * are stored as opaque int64_t
 * handles on the March side (cast from pointer), matching how March already
 * treats file descriptors.
 *
 * OpenSSL 3 include path (Homebrew macOS):
 *   /opt/homebrew/opt/openssl@3/include
 * Link with: -lssl -lcrypto
 *
 * Object header layout (all March heap values):
 *   offset  0: int64_t rc
 *   offset  8: int32_t tag
 *   offset 12: int32_t pad
 *   offset 16+: 8-byte fields
 *
 * Result: Ok = tag 0, field0 = value;  Err = tag 1, field0 = String.
 */

#include "march_tls.h"
#include "march_runtime.h"
#include "march_preempt.h"
#include "march_http.h"   /* MARCH_RECV_TIMEOUT_MSG — one spelling of an expired deadline */
#include "march_scheduler.h"   /* march_sched_wait_fd: park instead of blocking */
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/time.h>

#include <errno.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <poll.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

/* ── helpers ──────────────────────────────────────────────────────────── */

static void *make_ok_int(int64_t v) {
    void *r = march_alloc(16 + 8);
    /* tag stays 0 = Ok */
    *(int64_t *)((char *)r + 16) = v;
    return r;
}

static void *make_ok_str(void *s) {
    void *r = march_alloc(16 + 8);
    /* tag stays 0 = Ok */
    *(void **)((char *)r + 16) = s;
    return r;
}

static void *make_err(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1;          /* tag = 1 (Err) */
    *(void **)((char *)r + 16) = s;
    return r;
}

/* Collect the latest OpenSSL error string into a static buffer. */
static const char *ossl_error(void) {
    static char buf[256];
    unsigned long e = ERR_get_error();
    if (e == 0) {
        snprintf(buf, sizeof buf, "unknown TLS error");
    } else {
        ERR_error_string_n(e, buf, sizeof buf);
    }
    return buf;
}

/* Extract a C string from a march_string* (or "" if NULL/empty). */
static const char *ms_cstr(void *ms) {
    if (!ms) return "";
    march_string *s = (march_string *)ms;
    return (s->len == 0) ? "" : s->data;
}

/* Walk a March List(String) and build an OpenSSL ALPN wire-format buffer.
 * Format: <len><protocol><len><protocol>...
 * Caller must free() the result.  Returns NULL if list is empty/nil. */
static unsigned char *build_alpn_buf(void *list, unsigned int *out_len) {
    /* First pass: compute total length */
    size_t total = 0;
    void *cur = list;
    while (1) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break;  /* Nil */
        void *head = *(void **)((char *)cur + 16);
        march_string *s = (march_string *)head;
        total += 1 + (size_t)s->len;
        cur = *(void **)((char *)cur + 24);  /* tail */
    }
    if (total == 0) { *out_len = 0; return NULL; }

    unsigned char *buf = (unsigned char *)malloc(total);
    if (!buf) { *out_len = 0; return NULL; }

    size_t off = 0;
    cur = list;
    while (1) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break;
        void *head = *(void **)((char *)cur + 16);
        march_string *s = (march_string *)head;
        buf[off++] = (unsigned char)s->len;
        memcpy(buf + off, s->data, (size_t)s->len);
        off += (size_t)s->len;
        cur = *(void **)((char *)cur + 24);
    }
    *out_len = (unsigned int)total;
    return buf;
}

/* Apply ALPN to an SSL_CTX (client side). */
static int ctx_set_alpn_protos(SSL_CTX *ctx, void *alpn_list) {
    unsigned int len = 0;
    unsigned char *buf = build_alpn_buf(alpn_list, &len);
    if (!buf) return 0;  /* no ALPN requested */
    int rc = SSL_CTX_set_alpn_protos(ctx, buf, len);
    free(buf);
    return rc;  /* 0 = success in OpenSSL */
}

/* Set minimum TLS version on a context. */
static int ctx_set_min_version(SSL_CTX *ctx, int64_t ver) {
    int v = (ver == 1) ? TLS1_3_VERSION : TLS1_2_VERSION;
    return SSL_CTX_set_min_proto_version(ctx, v);
}

/* ── ALPN server callback ─────────────────────────────────────────────── */

/* arg points to: [unsigned int len][unsigned char wire_buf[len]] */
static int tls_alpn_server_cb(SSL *ssl,
                               const unsigned char **out, unsigned char *outlen,
                               const unsigned char *in,  unsigned int inlen,
                               void *arg) {
    (void)ssl;
    unsigned char *p = (unsigned char *)arg;
    unsigned int slen;
    memcpy(&slen, p, sizeof slen);
    const unsigned char *protos = p + sizeof slen;
    return SSL_select_next_proto((unsigned char **)out, outlen,
                                 protos, slen, in, inlen)
           == OPENSSL_NPN_NEGOTIATED ? SSL_TLSEXT_ERR_OK : SSL_TLSEXT_ERR_NOACK;
}

/* ── Context creation ─────────────────────────────────────────────────── */

void *march_tls_client_ctx(void *ca_file, void *alpn_list,
                            int64_t min_tls_ver, int64_t verify_peer) {
    SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) return make_err(ossl_error());

    /* Certificate verification */
    if (verify_peer) {
        SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
        const char *ca = ms_cstr(ca_file);
        if (ca && ca[0] != '\0') {
            if (SSL_CTX_load_verify_locations(ctx, ca, NULL) != 1) {
                const char *e = ossl_error();
                SSL_CTX_free(ctx);
                return make_err(e);
            }
        } else {
            /* Use the system default CA bundle */
            if (SSL_CTX_set_default_verify_paths(ctx) != 1) {
                const char *e = ossl_error();
                SSL_CTX_free(ctx);
                return make_err(e);
            }
        }
    } else {
        SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);
    }

    /* Minimum TLS version */
    if (!ctx_set_min_version(ctx, min_tls_ver)) {
        const char *e = ossl_error();
        SSL_CTX_free(ctx);
        return make_err(e);
    }

    /* ALPN */
    ctx_set_alpn_protos(ctx, alpn_list);

    /* Enable session tickets for TLS 1.3 resumption */
    SSL_CTX_set_options(ctx, SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3);

    /* Without this, a bare SSL_read() can return 0 (with SSL_get_error()
     * reporting SSL_ERROR_ZERO_RETURN/SSL_ERROR_SYSCALL rather than a
     * retry-me signal) after internally consuming a non-application-data
     * record — e.g. a TLS 1.3 post-handshake NewSessionTicket, which most
     * real-world servers send immediately after the handshake completes,
     * before any application data. march_tls_read has no retry loop and
     * treats that as end-of-stream, so a real HTTPS response byte never
     * arrives (verified: a bare-socket exchange with the same server via
     * `openssl s_client` gets the real response instantly). This never
     * showed up against a plain local dev TLS server that skips session
     * tickets; only against a real remote TLS 1.3 server. */
    SSL_CTX_set_mode(ctx, SSL_MODE_AUTO_RETRY);

    return make_ok_int((int64_t)(uintptr_t)ctx);
}

void *march_tls_server_ctx(void *cert_file, void *key_file, void *ca_file,
                            void *alpn_list, int64_t min_tls_ver) {
    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
    if (!ctx) return make_err(ossl_error());

    const char *cert = ms_cstr(cert_file);
    const char *key  = ms_cstr(key_file);

    if (!cert || cert[0] == '\0') {
        SSL_CTX_free(ctx);
        return make_err("server_ctx: cert_file is required");
    }
    if (!key || key[0] == '\0') {
        SSL_CTX_free(ctx);
        return make_err("server_ctx: key_file is required");
    }

    if (SSL_CTX_use_certificate_chain_file(ctx, cert) != 1) {
        const char *e = ossl_error();
        SSL_CTX_free(ctx);
        return make_err(e);
    }
    if (SSL_CTX_use_PrivateKey_file(ctx, key, SSL_FILETYPE_PEM) != 1) {
        const char *e = ossl_error();
        SSL_CTX_free(ctx);
        return make_err(e);
    }
    if (SSL_CTX_check_private_key(ctx) != 1) {
        const char *e = ossl_error();
        SSL_CTX_free(ctx);
        return make_err(e);
    }

    const char *ca = ms_cstr(ca_file);
    if (ca && ca[0] != '\0') {
        if (SSL_CTX_load_verify_locations(ctx, ca, NULL) != 1) {
            const char *e = ossl_error();
            SSL_CTX_free(ctx);
            return make_err(e);
        }
    }

    if (!ctx_set_min_version(ctx, min_tls_ver)) {
        const char *e = ossl_error();
        SSL_CTX_free(ctx);
        return make_err(e);
    }

    /* ALPN callback for server */
    unsigned int alpn_len = 0;
    unsigned char *alpn_buf = build_alpn_buf(alpn_list, &alpn_len);
    if (alpn_buf && alpn_len > 0) {
        /* For the server ALPN callback we store the wire-format buffer in a
         * heap block prefixed with its length (4 bytes) so the callback can
         * find both the data and its size from a single pointer. */
        unsigned char *stored = (unsigned char *)malloc(sizeof(unsigned int) + alpn_len);
        if (stored) {
            memcpy(stored, &alpn_len, sizeof alpn_len);
            memcpy(stored + sizeof alpn_len, alpn_buf, alpn_len);
            SSL_CTX_set_alpn_select_cb(ctx, tls_alpn_server_cb, stored);
        }
        free(alpn_buf);
    }

    SSL_CTX_set_options(ctx, SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3);

    return make_ok_int((int64_t)(uintptr_t)ctx);
}

/* ── Handshake ────────────────────────────────────────────────────────── */

/* ── Driving OpenSSL without holding the thread ───────────────────────────
 * Every SSL_* call below runs on a NON-BLOCKING fd, and WANT_READ /
 * WANT_WRITE sends this green thread to march_sched_wait_fd for the
 * direction OpenSSL asked for -- so a handshake with a remote host, a read
 * on a silent peer or a write into a full buffer parks the green thread
 * instead of its scheduler thread.  The fd's flags are restored on every
 * exit: the fd may be shared with plain-socket code that assumes blocking.
 *
 * The preempt mask covers each SSL call only, never the wait (which parks).
 * A deadline of 0 is "no deadline"; on expiry *timed_out is set and the
 * last SSL return is handed back.  [op] chooses the call. */
enum tls_op { TLS_OP_CONNECT, TLS_OP_ACCEPT, TLS_OP_READ, TLS_OP_WRITE };

static int tls_drive(SSL *ssl, int fd, enum tls_op op, void *buf, int len,
                     int64_t deadline_ms, int *timed_out, int *last_err, int *saved_errno) {
    *timed_out = 0; *last_err = SSL_ERROR_NONE; *saved_errno = 0;
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0 && !(flags & O_NONBLOCK)) (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    int rc;
    for (;;) {
        sigset_t saved;
        march_block_preempt(&saved);
        /* errno through march_errno_set/march_errno_now, never directly: the
         * wait at the bottom of this loop parks, and on a later iteration the
         * green thread may be running on another scheduler thread.  glibc
         * declares __errno_location() const, so clang would reuse the address
         * it computed before the park -- clearing and then reading the OLD
         * thread's errno, which both loses this SSL call's errno (an
         * SSL_ERROR_SYSCALL misreported as EAGAIN, or the reverse) and
         * clobbers a thread that is running something else.  See
         * march_errno_now in march_scheduler.h. */
        march_errno_set(0);
        switch (op) {
            case TLS_OP_CONNECT: rc = SSL_connect(ssl); break;
            case TLS_OP_ACCEPT:  rc = SSL_accept(ssl);  break;
            case TLS_OP_READ:    rc = SSL_read(ssl, buf, len); break;
            default:             rc = SSL_write(ssl, buf, len); break;
        }
        *saved_errno = march_errno_now();
        int err = rc > 0 ? SSL_ERROR_NONE : SSL_get_error(ssl, rc);
        march_unblock_preempt(&saved);
        *last_err = err;
        if (rc > 0) break;
        if (err != SSL_ERROR_WANT_READ && err != SSL_ERROR_WANT_WRITE) break;
        int w = march_sched_wait_fd(fd, err == SSL_ERROR_WANT_WRITE, deadline_ms);
        if (w == MARCH_FDWAIT_TIMEOUT) { *timed_out = 1; break; }
        if (w < 0) {
            int e = march_errno_now();
            *saved_errno = e ? e : EIO;
            *last_err = SSL_ERROR_SYSCALL;
            break;
        }
    }
    if (flags >= 0 && !(flags & O_NONBLOCK)) (void)fcntl(fd, F_SETFL, flags);
    return rc;
}

/* The fd's own SO_RCVTIMEO as an absolute deadline, 0 when unset: what an
 * untimed TLS read honours, as the plain recv path does. */
static int64_t tls_rcvtimeo_deadline(int fd) {
    struct timeval tv;
    socklen_t tvlen = sizeof tv;
    if (getsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, &tvlen) == 0 && (tv.tv_sec > 0 || tv.tv_usec > 0))
        return march_now_ms() + (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
    return 0;
}

static void *tls_ssl_error(SSL *ssl, int rc, const char *what) {
    (void)ssl;
    char buf[512];
    unsigned long e = ERR_get_error();
    if (e) ERR_error_string_n(e, buf, sizeof buf);
    else   snprintf(buf, sizeof buf, "%s (SSL error %d)", what, rc);
    return make_err(buf);
}

void *march_tls_connect(int64_t fd, int64_t ctx_handle, void *hostname) {
    SSL_CTX *ctx = (SSL_CTX *)(uintptr_t)ctx_handle;
    SSL *ssl = SSL_new(ctx);
    if (!ssl) return make_err(ossl_error());

    /* SNI */
    const char *host = ms_cstr(hostname);
    if (host && host[0] != '\0') {
        SSL_set_tlsext_host_name(ssl, host);
        /* Also set for certificate hostname verification */
        SSL_set1_host(ssl, host);
    }

    if (SSL_set_fd(ssl, (int)fd) != 1) {
        const char *e = ossl_error();
        SSL_free(ssl);
        return make_err(e);
    }

    /* The handshake parks on the peer's response (tls_drive); a deadline
     * set on the fd (SO_RCVTIMEO) bounds it, as it always did. */
    int timed_out, err, en;
    int rc = tls_drive(ssl, (int)fd, TLS_OP_CONNECT, NULL, 0, tls_rcvtimeo_deadline((int)fd), &timed_out, &err, &en);
    if (rc != 1) {
        void *r = timed_out ? make_err(MARCH_RECV_TIMEOUT_MSG) : tls_ssl_error(ssl, err, "SSL_connect failed");
        SSL_free(ssl);
        return r;
    }

    return make_ok_int((int64_t)(uintptr_t)ssl);
}

void *march_tls_accept(int64_t fd, int64_t ctx_handle) {
    SSL_CTX *ctx = (SSL_CTX *)(uintptr_t)ctx_handle;
    SSL *ssl = SSL_new(ctx);
    if (!ssl) return make_err(ossl_error());

    if (SSL_set_fd(ssl, (int)fd) != 1) {
        const char *e = ossl_error();
        SSL_free(ssl);
        return make_err(e);
    }

    int timed_out, err, en;
    int rc = tls_drive(ssl, (int)fd, TLS_OP_ACCEPT, NULL, 0, tls_rcvtimeo_deadline((int)fd), &timed_out, &err, &en);
    if (rc != 1) {
        void *r = timed_out ? make_err(MARCH_RECV_TIMEOUT_MSG) : tls_ssl_error(ssl, err, "SSL_accept failed");
        SSL_free(ssl);
        return r;
    }

    return make_ok_int((int64_t)(uintptr_t)ssl);
}

/* ── I/O ──────────────────────────────────────────────────────────────── */

void *march_tls_read(int64_t ssl_handle, int64_t max_bytes) {
    SSL *ssl = (SSL *)(uintptr_t)ssl_handle;
    if (!ssl) return make_err("tls_read: null ssl handle");

    int64_t cap = (max_bytes <= 0 || max_bytes > 1048576) ? 65536 : max_bytes;
    char *buf = (char *)malloc((size_t)cap);
    if (!buf) return make_err("tls_read: out of memory");

    /* The read parks on a silent peer (tls_drive); the fd's SO_RCVTIMEO,
     * set by set_recv_timeout before the handshake, is its deadline, and an
     * expiry gets the same sentinel the plain-recv path uses -- a caller
     * that cannot tell a silent peer from a broken one cannot say why a
     * stream ended. */
    int fd = SSL_get_fd(ssl);
    int timed_out, err, read_errno;
    int n = tls_drive(ssl, fd, TLS_OP_READ, buf, (int)cap, tls_rcvtimeo_deadline(fd), &timed_out, &err, &read_errno);
    if (n > 0) {
        void *s = march_string_lit(buf, (int64_t)n);
        free(buf);
        return make_ok_str(s);
    }
    free(buf);
    if (timed_out) return make_err(MARCH_RECV_TIMEOUT_MSG);
    if (err == SSL_ERROR_ZERO_RETURN) {
        /* Clean shutdown */
        void *s = march_string_lit("", 0);
        return make_ok_str(s);
    }
    if (err == SSL_ERROR_SYSCALL &&
        (read_errno == EAGAIN || read_errno == EWOULDBLOCK || read_errno == ETIMEDOUT)) {
        return make_err(MARCH_RECV_TIMEOUT_MSG);
    }
    return tls_ssl_error(ssl, err, "SSL_read error");
}

/* tls_read_timeout(ssl_handle, max_bytes, timeout_ms)
 *     -> Result(Option(String), String)
 *
 * A bounded TLS read that leaves NO lasting property on the fd, unlike the
 * SO_RCVTIMEO route march_tls_read relies on. Ok(None) is the deadline
 * expiring: the absence of an event rather than a kind of failure.
 *
 * Polling the fd and THEN calling a blocking SSL_read does not work, and the
 * first version of this did exactly that: right after a TLS 1.3 handshake the
 * server sends session tickets, so the socket is readable while holding no
 * application data at all. poll() returned ready, SSL_read consumed the
 * tickets, and then blocked until the peer hung up sixty seconds later — the
 * hang this exists to end. Readable bytes are not application data, and one
 * TLS record can need several socket reads.
 *
 * So the read itself gives up: the fd goes non-blocking for the duration,
 * SSL_read drives the loop, and WANT_READ/WANT_WRITE is what sends us to
 * poll() with whatever remains of the deadline. That also covers
 * renegotiation, where progress needs a WRITE and no amount of waiting to read
 * would ever arrive.
 *
 * Preemption is masked for the whole wait, for the reason march_tls_read
 * documents: under SA_RESTART the ~1ms SIGUSR1 tick restarts an interrupted
 * wait, and a deadline that restarts with it never expires.
 *
 * The original fd flags are restored on EVERY exit path. The same connection
 * is written to by a march_tls_write loop that assumes blocking semantics, and
 * leaving O_NONBLOCK behind would turn its partial write into an error.
 */
void *march_tls_read_timeout(int64_t ssl_handle, int64_t max_bytes, int64_t timeout_ms) {
    SSL *ssl = (SSL *)(uintptr_t)ssl_handle;
    if (!ssl) return make_err("tls_read_timeout: null ssl handle");

    int fd = SSL_get_fd(ssl);
    if (fd < 0) return make_err("tls_read_timeout: no file descriptor");

    int64_t cap = (max_bytes <= 0 || max_bytes > 1048576) ? 65536 : max_bytes;
    char *buf = (char *)malloc((size_t)cap);
    if (!buf) return make_err("tls_read_timeout: out of memory");

    /* SSL_read drives the loop and WANT_READ/WANT_WRITE is what parks us
     * (tls_drive): readable bytes are not application data (session tickets
     * after a TLS 1.3 handshake), and one record can need several reads, so
     * polling the fd and THEN reading was never right.  The deadline is
     * absolute: EINTR and partial records do not restart it. */
    int64_t deadline = timeout_ms > 0 ? march_now_ms() + timeout_ms : 0;
    int timed_out, err, en;
    int n = tls_drive(ssl, fd, TLS_OP_READ, buf, (int)cap, deadline, &timed_out, &err, &en);
    void *result;
    if (n > 0) result = make_ok_str(march_string_lit(buf, (int64_t)n));
    else if (timed_out) result = make_ok_str(NULL);                        /* None */
    else if (err == SSL_ERROR_ZERO_RETURN) result = make_ok_str(march_string_lit("", 0));
    else if (err == SSL_ERROR_SYSCALL && n == 0)
        /* Peer vanished without a close_notify. Still an end, not a timeout. */
        result = make_ok_str(march_string_lit("", 0));
    else result = tls_ssl_error(ssl, err, "SSL_read error");
    free(buf);
    return result;
}

void *march_tls_write(int64_t ssl_handle, void *data) {
    SSL *ssl = (SSL *)(uintptr_t)ssl_handle;
    if (!ssl) return make_err("tls_write: null ssl handle");

    march_string *s = (march_string *)data;
    const char *src = s->data;
    int64_t total = s->len;
    int64_t written = 0;

    int fd = SSL_get_fd(ssl);
    while (written < total) {
        int timed_out, err, en;
        int n = tls_drive(ssl, fd, TLS_OP_WRITE, (void *)(src + written), (int)(total - written), 0, &timed_out, &err, &en);
        if (n <= 0) return tls_ssl_error(ssl, err, "SSL_write error");
        written += n;
    }

    /* Return Ok(bytes_written) */
    return make_ok_int(written);
}

/* ── Teardown ─────────────────────────────────────────────────────────── */

void march_tls_close(int64_t ssl_handle) {
    if (!ssl_handle) return;
    SSL *ssl = (SSL *)(uintptr_t)ssl_handle;
    SSL_shutdown(ssl);
    SSL_free(ssl);
}

void march_tls_ctx_free(int64_t ctx_handle) {
    if (!ctx_handle) return;
    SSL_CTX *ctx = (SSL_CTX *)(uintptr_t)ctx_handle;
    SSL_CTX_free(ctx);
}

/* ── Introspection ────────────────────────────────────────────────────── */

void *march_tls_negotiated_alpn(int64_t ssl_handle) {
    if (!ssl_handle) return NULL;
    SSL *ssl = (SSL *)(uintptr_t)ssl_handle;
    const unsigned char *proto = NULL;
    unsigned int proto_len = 0;
    SSL_get0_alpn_selected(ssl, &proto, &proto_len);
    if (!proto || proto_len == 0) return NULL;
    return march_string_lit((const char *)proto, (int64_t)proto_len);
}

void *march_tls_peer_cn(int64_t ssl_handle) {
    if (!ssl_handle) return NULL;
    SSL *ssl = (SSL *)(uintptr_t)ssl_handle;
    X509 *cert = SSL_get_peer_certificate(ssl);
    if (!cert) return NULL;
    X509_NAME *name = X509_get_subject_name(cert);
    if (!name) { X509_free(cert); return NULL; }
    char buf[256] = {0};
    X509_NAME_get_text_by_NID(name, NID_commonName, buf, sizeof buf);
    X509_free(cert);
    return march_string_lit(buf, (int64_t)strlen(buf));
}
