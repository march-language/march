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
 * Result: Ok = tag 1, field0 = value;  Err = tag 0, field0 = String.
 */

#include "march_tls.h"
#include "march_runtime.h"

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* ── helpers ──────────────────────────────────────────────────────────── */

static void *make_ok_int(int64_t v) {
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1;          /* tag = 1 (Ok) */
    *(int64_t *)((char *)r + 16) = v;
    return r;
}

static void *make_ok_str(void *s) {
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1;
    *(void **)((char *)r + 16) = s;
    return r;
}

static void *make_err(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    /* tag stays 0 = Err */
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

    int rc = SSL_connect(ssl);
    if (rc != 1) {
        char buf[512];
        int err = SSL_get_error(ssl, rc);
        unsigned long e = ERR_get_error();
        if (e) {
            ERR_error_string_n(e, buf, sizeof buf);
        } else {
            snprintf(buf, sizeof buf, "SSL_connect failed (SSL error %d)", err);
        }
        SSL_free(ssl);
        return make_err(buf);
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

    int rc = SSL_accept(ssl);
    if (rc != 1) {
        char buf[512];
        int err = SSL_get_error(ssl, rc);
        unsigned long e = ERR_get_error();
        if (e) {
            ERR_error_string_n(e, buf, sizeof buf);
        } else {
            snprintf(buf, sizeof buf, "SSL_accept failed (SSL error %d)", err);
        }
        SSL_free(ssl);
        return make_err(buf);
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

    int n = SSL_read(ssl, buf, (int)cap);
    if (n > 0) {
        void *s = march_string_lit(buf, (int64_t)n);
        free(buf);
        return make_ok_str(s);
    }
    free(buf);

    int err = SSL_get_error(ssl, n);
    if (err == SSL_ERROR_ZERO_RETURN) {
        /* Clean shutdown */
        void *s = march_string_lit("", 0);
        return make_ok_str(s);
    }
    char errbuf[256];
    unsigned long e = ERR_get_error();
    if (e) {
        ERR_error_string_n(e, errbuf, sizeof errbuf);
    } else {
        snprintf(errbuf, sizeof errbuf, "SSL_read error %d", err);
    }
    return make_err(errbuf);
}

void *march_tls_write(int64_t ssl_handle, void *data) {
    SSL *ssl = (SSL *)(uintptr_t)ssl_handle;
    if (!ssl) return make_err("tls_write: null ssl handle");

    march_string *s = (march_string *)data;
    const char *src = s->data;
    int64_t total = s->len;
    int64_t written = 0;

    while (written < total) {
        int n = SSL_write(ssl, src + written, (int)(total - written));
        if (n <= 0) {
            int err = SSL_get_error(ssl, n);
            char errbuf[256];
            unsigned long e = ERR_get_error();
            if (e) {
                ERR_error_string_n(e, errbuf, sizeof errbuf);
            } else {
                snprintf(errbuf, sizeof errbuf, "SSL_write error %d", err);
            }
            return make_err(errbuf);
        }
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
