/* test/test_tls_session.c — unit tests for runtime/march_tls_session.c.
 *
 * The server side is a march_tls_session_t on memory BIOs; the client side is
 * a plain OpenSSL SSL on its own memory BIOs. pump() moves ciphertext between
 * them, so no sockets are involved. Each case prints "ok <name>"; any failure
 * prints "FAIL <name>: <why>" and exits 1. */

#include "march_tls_session.h"

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/x509.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *g_case = "?";
#define CHECK(cond, why) do { if (!(cond)) { \
    fprintf(stderr, "FAIL %s: %s (line %d)\n", g_case, why, __LINE__); \
    ERR_print_errors_fp(stderr); exit(1); } } while (0)

static EVP_PKEY *g_key;
static X509     *g_cert;

static void make_cert(void) {
    g_key = EVP_EC_gen("P-256");
    CHECK(g_key, "EVP_EC_gen");
    g_cert = X509_new();
    X509_set_version(g_cert, 2);
    ASN1_INTEGER_set(X509_get_serialNumber(g_cert), 1);
    X509_gmtime_adj(X509_getm_notBefore(g_cert), -60);
    X509_gmtime_adj(X509_getm_notAfter(g_cert), 3600);
    X509_set_pubkey(g_cert, g_key);
    X509_NAME *n = X509_NAME_new();
    X509_NAME_add_entry_by_txt(n, "CN", MBSTRING_ASC, (const unsigned char *)"localhost", -1, -1, 0);
    X509_set_subject_name(g_cert, n);
    X509_set_issuer_name(g_cert, n);
    X509_NAME_free(n);
    CHECK(X509_sign(g_cert, g_key, EVP_sha256()) > 0, "X509_sign");
}

static int alpn_cb(SSL *ssl, const unsigned char **out, unsigned char *outlen,
                   const unsigned char *in, unsigned int inlen, void *arg) {
    (void)ssl; (void)arg;
    static const unsigned char want[] = "\x08http/1.1";
    unsigned char *o = NULL;
    if (SSL_select_next_proto(&o, outlen, want, sizeof want - 1, in, inlen)
        != OPENSSL_NPN_NEGOTIATED) return SSL_TLSEXT_ERR_NOACK;
    *out = o;
    return SSL_TLSEXT_ERR_OK;
}

static SSL_CTX *server_ctx(void) {
    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
    CHECK(ctx, "server SSL_CTX_new");
    CHECK(SSL_CTX_use_certificate(ctx, g_cert) == 1, "use_certificate");
    CHECK(SSL_CTX_use_PrivateKey(ctx, g_key) == 1, "use_PrivateKey");
    SSL_CTX_set_alpn_select_cb(ctx, alpn_cb, NULL);
    return ctx;
}

typedef struct { SSL *ssl; BIO *rbio, *wbio; } client_t;

static client_t client_new(void) {
    static SSL_CTX *cctx;
    if (!cctx) {
        cctx = SSL_CTX_new(TLS_client_method());
        SSL_CTX_set_verify(cctx, SSL_VERIFY_NONE, NULL);
        static const unsigned char protos[] = "\x08http/1.1";
        SSL_CTX_set_alpn_protos(cctx, protos, sizeof protos - 1);
    }
    client_t c;
    c.ssl = SSL_new(cctx);
    c.rbio = BIO_new(BIO_s_mem());
    c.wbio = BIO_new(BIO_s_mem());
    SSL_set_bio(c.ssl, c.rbio, c.wbio);
    SSL_set_connect_state(c.ssl);
    return c;
}

/* Move all pending ciphertext both ways. feed_chunk 0 = all at once. */
static void pump(march_tls_session_t *s, client_t *c, size_t feed_chunk) {
    char buf[65536];
    for (;;) {
        int moved = 0;
        size_t n;
        while ((n = mts_take_out(s, buf, sizeof buf)) > 0) {
            BIO_write(c->rbio, buf, (int)n); moved = 1;
        }
        int k;
        while ((k = BIO_read(c->wbio, buf, sizeof buf)) > 0) {
            if (feed_chunk == 0) CHECK(mts_feed(s, buf, (size_t)k) == 0, "mts_feed");
            else for (int i = 0; i < k; i += (int)feed_chunk) {
                size_t m = (size_t)(k - i) < feed_chunk ? (size_t)(k - i) : feed_chunk;
                CHECK(mts_feed(s, buf + i, m) == 0, "mts_feed chunk");
            }
            moved = 1;
        }
        if (!moved) break;
    }
}

static void handshake(march_tls_session_t *s, client_t *c, size_t feed_chunk) {
    for (int round = 0; round < 10; round++) {
        SSL_do_handshake(c->ssl);
        pump(s, c, feed_chunk);
        mts_rc rc = mts_handshake(s);
        CHECK(rc != MTS_FAIL, mts_error(s));
        pump(s, c, feed_chunk);
        if (rc == MTS_DONE && SSL_is_init_finished(c->ssl)) return;
    }
    CHECK(0, "handshake did not complete in 10 rounds");
}

static void fill_pattern(unsigned char *p, size_t n) {
    for (size_t i = 0; i < n; i++) p[i] = (unsigned char)(i * 7 + 3);
}

/* Read all plaintext the client can currently see into out; returns count. */
static size_t client_read_all(client_t *c, unsigned char *out, size_t cap) {
    size_t got = 0;
    for (;;) {
        size_t k = 0;
        if (got >= cap) break;
        if (SSL_read_ex(c->ssl, out + got, cap - got, &k) != 1) break;
        got += k;
    }
    return got;
}

static void t_handshake_completes(SSL_CTX *ctx) {
    g_case = "handshake_completes";
    march_tls_session_t *s = mts_new_server(ctx);
    CHECK(s, "mts_new_server");
    client_t c = client_new();
    CHECK(!mts_is_established(s), "established before handshake");
    handshake(s, &c, 0);
    CHECK(mts_is_established(s), "not established");
    const unsigned char *p = NULL; unsigned int plen = 0;
    SSL_get0_alpn_selected(c.ssl, &p, &plen);
    CHECK(plen == 8 && memcmp(p, "http/1.1", 8) == 0, "ALPN not http/1.1");
    SSL_free(c.ssl); mts_free(s);
    printf("ok %s\n", g_case);
}

static void t_roundtrip_100k(SSL_CTX *ctx) {
    g_case = "roundtrip_100k";
    enum { N = 100000 };
    static unsigned char src[N], dst[N + 16];
    fill_pattern(src, N);
    march_tls_session_t *s = mts_new_server(ctx);
    client_t c = client_new();
    handshake(s, &c, 0);
    size_t off = 0;
    while (off < N) {
        size_t w = 0;
        CHECK(SSL_write_ex(c.ssl, src + off, N - off, &w) == 1, "client write");
        off += w;
    }
    pump(s, &c, 0);
    size_t got = 0;
    for (;;) {
        size_t k = 0;
        mts_rc rc = mts_read(s, dst + got, sizeof dst - got, &k);
        got += k;
        if (rc == MTS_NEED_INPUT) break;
        CHECK(rc == MTS_DONE, "mts_read rc");
    }
    CHECK(got == N && memcmp(src, dst, N) == 0, "server read mismatch");
    CHECK(mts_write(s, src, N) == 0, "mts_write");
    CHECK(mts_out_len(s) > 0, "no ciphertext after write");
    pump(s, &c, 0);
    memset(dst, 0, sizeof dst);
    got = client_read_all(&c, dst, N);
    CHECK(got == N && memcmp(src, dst, N) == 0, "client read mismatch");
    SSL_free(c.ssl); mts_free(s);
    printf("ok %s\n", g_case);
}

static void t_one_byte_feeds(SSL_CTX *ctx) {
    g_case = "one_byte_feeds";
    march_tls_session_t *s = mts_new_server(ctx);
    client_t c = client_new();
    handshake(s, &c, 1);
    CHECK(mts_is_established(s), "not established");
    SSL_free(c.ssl); mts_free(s);
    printf("ok %s\n", g_case);
}

static void t_drain_reports_need_input(SSL_CTX *ctx) {
    g_case = "drain_reports_need_input";
    march_tls_session_t *s = mts_new_server(ctx);
    client_t c = client_new();
    handshake(s, &c, 0);
    size_t w;
    CHECK(SSL_write_ex(c.ssl, "hello", 5, &w) == 1, "client write");
    pump(s, &c, 0);
    char buf[64]; size_t k = 0;
    mts_rc rc = mts_read(s, buf, sizeof buf, &k);
    CHECK(rc == MTS_DONE && k == 5 && memcmp(buf, "hello", 5) == 0, "first read");
    rc = mts_read(s, buf, sizeof buf, &k);
    CHECK(rc == MTS_NEED_INPUT && k == 0, "drained read not NEED_INPUT");
    CHECK(mts_has_input(s) == 0, "has_input after drain");
    SSL_free(c.ssl); mts_free(s);
    printf("ok %s\n", g_case);
}

static void t_has_input_with_buffered(SSL_CTX *ctx) {
    g_case = "has_input_with_buffered";
    march_tls_session_t *s = mts_new_server(ctx);
    client_t c = client_new();
    handshake(s, &c, 0);
    size_t w;
    CHECK(SSL_write_ex(c.ssl, "0123456789abcdefghij", 20, &w) == 1, "write 1");
    CHECK(SSL_write_ex(c.ssl, "second-record", 13, &w) == 1, "write 2");
    pump(s, &c, 0);
    char buf[10]; size_t k = 0;
    CHECK(mts_read(s, buf, sizeof buf, &k) == MTS_DONE && k == 10, "read 10");
    CHECK(mts_has_input(s) == 1, "has_input with buffered data");
    SSL_free(c.ssl); mts_free(s);
    printf("ok %s\n", g_case);
}

static void t_close_notify_is_eof(SSL_CTX *ctx) {
    g_case = "close_notify_is_eof";
    march_tls_session_t *s = mts_new_server(ctx);
    client_t c = client_new();
    handshake(s, &c, 0);
    SSL_shutdown(c.ssl);
    pump(s, &c, 0);
    char buf[16]; size_t k = 0;
    CHECK(mts_read(s, buf, sizeof buf, &k) == MTS_EOF, "not EOF after close_notify");
    SSL_free(c.ssl); mts_free(s);
    printf("ok %s\n", g_case);
}

static void t_garbage_fails(SSL_CTX *ctx) {
    g_case = "garbage_fails";
    march_tls_session_t *s = mts_new_server(ctx);
    const char *g = "GET / HTTP/1.1\r\n\r\n";
    CHECK(mts_feed(s, g, strlen(g)) == 0, "feed");
    CHECK(mts_handshake(s) == MTS_FAIL, "garbage did not fail");
    CHECK(mts_error(s) && mts_error(s)[0] != '\0', "empty error");
    mts_free(s);
    printf("ok %s\n", g_case);
}

static void t_shutdown_queues_close_notify(SSL_CTX *ctx) {
    g_case = "shutdown_queues_close_notify";
    march_tls_session_t *s = mts_new_server(ctx);
    client_t c = client_new();
    handshake(s, &c, 0);
    while (mts_out_len(s) > 0) { char b[4096]; mts_take_out(s, b, sizeof b); }
    mts_shutdown(s);
    CHECK(mts_out_len(s) > 0, "no close_notify queued");
    pump(s, &c, 0);
    char buf[16]; size_t k = 0;
    int r = SSL_read_ex(c.ssl, buf, sizeof buf, &k);
    CHECK(r != 1 && SSL_get_error(c.ssl, r) == SSL_ERROR_ZERO_RETURN, "client did not see close_notify");
    SSL_free(c.ssl); mts_free(s);
    printf("ok %s\n", g_case);
}

int main(void) {
    make_cert();
    SSL_CTX *ctx = server_ctx();
    t_handshake_completes(ctx);
    t_roundtrip_100k(ctx);
    t_one_byte_feeds(ctx);
    t_drain_reports_need_input(ctx);
    t_has_input_with_buffered(ctx);
    t_close_notify_is_eof(ctx);
    t_garbage_fails(ctx);
    t_shutdown_queues_close_notify(ctx);
    SSL_CTX_free(ctx);
    printf("all tls session tests passed\n");
    return 0;
}
