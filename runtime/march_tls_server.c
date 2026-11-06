/* runtime/march_tls_server.c — the HTTPS server's certificate slot, file
 * poller and fd -> session registry. See march_tls_server.h. */

#include "march_tls_server.h"

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509.h>

#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ── building a context ───────────────────────────────────────────────── */

/* ALPN: HTTP/1.1 only. A client that offers no http/1.1 still connects
 * without ALPN (NOACK) and is served HTTP/1.1. The wire string is static, so
 * nothing is allocated per context. */
static const unsigned char k_alpn_http11[] = "\x08http/1.1";

static int alpn_select_http11(SSL *ssl, const unsigned char **out, unsigned char *outlen,
                              const unsigned char *in, unsigned int inlen, void *arg) {
    (void)ssl; (void)arg;
    unsigned char *o = NULL;
    if (SSL_select_next_proto(&o, outlen, k_alpn_http11, sizeof k_alpn_http11 - 1, in, inlen)
        != OPENSSL_NPN_NEGOTIATED)
        return SSL_TLSEXT_ERR_NOACK;
    *out = o;
    return SSL_TLSEXT_ERR_OK;
}

/* A key file with a passphrase would otherwise make OpenSSL prompt on the
 * terminal and hang the server; refuse instead. */
static int no_passphrase(char *buf, int size, int rwflag, void *u) {
    (void)buf; (void)size; (void)rwflag; (void)u;
    return -1;
}

static void put_err(char *err, size_t errlen, const char *what) {
    if (!err || errlen == 0) return;
    unsigned long e = ERR_peek_last_error();
    if (e != 0) {
        char ossl[200];
        ERR_error_string_n(e, ossl, sizeof ossl);
        snprintf(err, errlen, "%s (%s)", what, ossl);
    } else {
        snprintf(err, errlen, "%s", what);
    }
    ERR_clear_error();
}

static void asn1_time_str(const ASN1_TIME *t, char *out, size_t outlen) {
    out[0] = '\0';
    BIO *b = BIO_new(BIO_s_mem());
    if (!b) return;
    if (ASN1_TIME_print(b, t) == 1) {
        int n = BIO_read(b, out, (int)outlen - 1);
        out[n > 0 ? n : 0] = '\0';
    }
    BIO_free(b);
}

int mts_ctx_from_pem(const char *cert, size_t cert_len, const char *key, size_t key_len,
                     int allow_expired, SSL_CTX **out, char *err, size_t errlen) {
    *out = NULL;
    ERR_clear_error();
    if (cert_len > 0x7fffffff || key_len > 0x7fffffff) {
        put_err(err, errlen, "certificate or key is too large");
        return -1;
    }
    int rc = -1;
    SSL_CTX *ctx = NULL;
    X509 *leaf = NULL;
    EVP_PKEY *pkey = NULL;
    BIO *cb = BIO_new_mem_buf(cert, (int)cert_len);
    BIO *kb = BIO_new_mem_buf(key, (int)key_len);
    if (!cb || !kb) { put_err(err, errlen, "out of memory"); goto done; }

    leaf = PEM_read_bio_X509(cb, NULL, no_passphrase, NULL);
    if (!leaf) { put_err(err, errlen, "no certificate found in the certificate PEM"); goto done; }
    if (!allow_expired && ASN1_TIME_cmp_time_t(X509_get0_notAfter(leaf), time(NULL)) < 0) {
        char when[64];
        asn1_time_str(X509_get0_notAfter(leaf), when, sizeof when);
        char msg[160];
        snprintf(msg, sizeof msg, "certificate expired %s", when);
        ERR_clear_error();
        put_err(err, errlen, msg);
        goto done;
    }
    pkey = PEM_read_bio_PrivateKey(kb, NULL, no_passphrase, NULL);
    if (!pkey) { put_err(err, errlen, "no usable private key found in the key PEM"); goto done; }

    ctx = SSL_CTX_new(TLS_server_method());
    if (!ctx) { put_err(err, errlen, "cannot create a TLS context"); goto done; }
    if (SSL_CTX_use_certificate(ctx, leaf) != 1) { put_err(err, errlen, "certificate rejected"); goto done; }
    for (;;) {
        X509 *x = PEM_read_bio_X509(cb, NULL, no_passphrase, NULL);
        if (!x) break;
        if (SSL_CTX_add0_chain_cert(ctx, x) != 1) {
            X509_free(x);
            put_err(err, errlen, "chain certificate rejected");
            goto done;
        }
    }
    ERR_clear_error();                     /* the end-of-PEM "no start line" */
    if (SSL_CTX_use_PrivateKey(ctx, pkey) != 1) {
        /* OpenSSL checks the pair here already; say so in plain words. */
        int mismatch = ERR_GET_REASON(ERR_peek_last_error()) == X509_R_KEY_VALUES_MISMATCH;
        put_err(err, errlen, mismatch ? "certificate and private key do not match"
                                      : "private key rejected");
        goto done;
    }
    if (SSL_CTX_check_private_key(ctx) != 1) {
        put_err(err, errlen, "certificate and private key do not match");
        goto done;
    }
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    SSL_CTX_set_options(ctx, SSL_OP_NO_RENEGOTIATION);
    SSL_CTX_set_max_early_data(ctx, 0);
    if (SSL_CTX_set1_groups_list(ctx, MARCH_TLS_PQ_GROUPS) != 1) ERR_clear_error();
    SSL_CTX_set_alpn_select_cb(ctx, alpn_select_http11, NULL);
    *out = ctx;
    ctx = NULL;
    rc = 0;
done:
    SSL_CTX_free(ctx);
    X509_free(leaf);
    EVP_PKEY_free(pkey);
    BIO_free(cb);
    BIO_free(kb);
    return rc;
}

/* ── the slot ─────────────────────────────────────────────────────────── */

#define MTS_MAX_CONSUMERS 8

static pthread_mutex_t g_slot_mu = PTHREAD_MUTEX_INITIALIZER;
static SSL_CTX *g_slot_ctx;
static uint64_t g_slot_gen;
static struct { mts_consumer_fn fn; void *arg; } g_consumers[MTS_MAX_CONSUMERS];
static int g_nconsumers;

int mts_slot_install_pem(const char *cert, size_t cert_len, const char *key, size_t key_len,
                         int allow_expired, char *err, size_t errlen) {
    SSL_CTX *fresh = NULL;
    if (mts_ctx_from_pem(cert, cert_len, key, key_len, allow_expired, &fresh, err, errlen) != 0)
        return -1;
    struct { mts_consumer_fn fn; void *arg; } cs[MTS_MAX_CONSUMERS];
    pthread_mutex_lock(&g_slot_mu);
    SSL_CTX *old = g_slot_ctx;
    g_slot_ctx = fresh;
    __atomic_store_n(&g_slot_gen, g_slot_gen + 1, __ATOMIC_RELEASE);
    int n = g_nconsumers;
    memcpy(cs, g_consumers, sizeof cs);
    pthread_mutex_unlock(&g_slot_mu);
    SSL_CTX_free(old);            /* connections holding a ref keep it alive */
    for (int i = 0; i < n; i++) cs[i].fn(cert, cert_len, key, key_len, cs[i].arg);
    return 0;
}

SSL_CTX *mts_slot_acquire(void) {
    pthread_mutex_lock(&g_slot_mu);
    SSL_CTX *c = g_slot_ctx;
    if (c) SSL_CTX_up_ref(c);
    pthread_mutex_unlock(&g_slot_mu);
    return c;
}

uint64_t mts_slot_generation(void) {
    return __atomic_load_n(&g_slot_gen, __ATOMIC_ACQUIRE);
}

void mts_slot_add_consumer(mts_consumer_fn fn, void *arg) {
    pthread_mutex_lock(&g_slot_mu);
    if (g_nconsumers < MTS_MAX_CONSUMERS) {
        g_consumers[g_nconsumers].fn = fn;
        g_consumers[g_nconsumers].arg = arg;
        g_nconsumers++;
    } else {
        fprintf(stderr, "march: https: too many certificate consumers (max %d)\n", MTS_MAX_CONSUMERS);
    }
    pthread_mutex_unlock(&g_slot_mu);
}

/* ── the poller ───────────────────────────────────────────────────────── */

#define MTS_MAX_PEM_FILE (1 << 20)

static pthread_mutex_t g_poll_mu = PTHREAD_MUTEX_INITIALIZER;
static char *g_cert_path, *g_key_path;
static unsigned char g_last_tried[32];
static int g_have_last_tried;
static int g_logged_missing;

void mts_poller_set_paths(const char *cert_path, const char *key_path) {
    pthread_mutex_lock(&g_poll_mu);
    free(g_cert_path); free(g_key_path);
    g_cert_path = strdup(cert_path);
    g_key_path = strdup(key_path);
    g_have_last_tried = 0;
    g_logged_missing = 0;
    pthread_mutex_unlock(&g_poll_mu);
}

/* Read a whole file (following symlinks, as certbot's live/ paths are).
 * NULL with errno set on failure. */
static char *read_whole(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    char *buf = malloc(MTS_MAX_PEM_FILE + 1);
    if (!buf) { fclose(f); errno = ENOMEM; return NULL; }
    size_t n = fread(buf, 1, MTS_MAX_PEM_FILE + 1, f);
    int bad = ferror(f);
    fclose(f);
    if (bad) { free(buf); errno = EIO; return NULL; }
    if (n > MTS_MAX_PEM_FILE) { free(buf); errno = EFBIG; return NULL; }
    buf[n] = '\0';
    *len = n;
    return buf;
}

static void pair_hash(const char *c, size_t cl, const char *k, size_t kl, unsigned char out[32]) {
    EVP_MD_CTX *m = EVP_MD_CTX_new();
    unsigned int olen = 0;
    static const unsigned char zero = 0;
    EVP_DigestInit_ex(m, EVP_sha256(), NULL);
    EVP_DigestUpdate(m, c, cl);
    EVP_DigestUpdate(m, &zero, 1);
    EVP_DigestUpdate(m, k, kl);
    EVP_DigestFinal_ex(m, out, &olen);
    EVP_MD_CTX_free(m);
}

static void leaf_not_after(const char *cert, size_t cert_len, char *out, size_t outlen, int *expired) {
    out[0] = '\0';
    *expired = 0;
    BIO *b = BIO_new_mem_buf(cert, (int)cert_len);
    X509 *x = b ? PEM_read_bio_X509(b, NULL, no_passphrase, NULL) : NULL;
    if (x) {
        asn1_time_str(X509_get0_notAfter(x), out, outlen);
        *expired = ASN1_TIME_cmp_time_t(X509_get0_notAfter(x), time(NULL)) < 0;
    }
    X509_free(x);
    BIO_free(b);
    ERR_clear_error();
}

static mts_poll_rc poll_step(int allow_expired, char *err, size_t errlen) {
    if (err && errlen) err[0] = '\0';
    pthread_mutex_lock(&g_poll_mu);
    mts_poll_rc rc;
    char *cert = NULL, *key = NULL;
    size_t cl = 0, kl = 0;
    if (!g_cert_path || !g_key_path) {
        if (err && errlen) snprintf(err, errlen, "no certificate paths configured");
        rc = MTS_POLL_MISSING;
        goto out;
    }
    cert = read_whole(g_cert_path, &cl);
    if (!cert) {
        if (err && errlen) snprintf(err, errlen, "cannot read %s: %s", g_cert_path, strerror(errno));
        rc = MTS_POLL_MISSING;
        goto missing;
    }
    key = read_whole(g_key_path, &kl);
    if (!key) {
        if (err && errlen) snprintf(err, errlen, "cannot read %s: %s", g_key_path, strerror(errno));
        rc = MTS_POLL_MISSING;
        goto missing;
    }
    g_logged_missing = 0;
    unsigned char h[32];
    pair_hash(cert, cl, key, kl, h);
    if (g_have_last_tried && memcmp(h, g_last_tried, 32) == 0) { rc = MTS_POLL_UNCHANGED; goto out; }
    memcpy(g_last_tried, h, 32);
    g_have_last_tried = 1;
    char why[256] = "";
    if (mts_slot_install_pem(cert, cl, key, kl, allow_expired, why, sizeof why) == 0) {
        char when[64]; int expired;
        leaf_not_after(cert, cl, when, sizeof when, &expired);
        if (expired)
            fprintf(stderr, "march: https: warning: certificate %s expired %s\n", g_cert_path, when);
        fprintf(stderr, "march: https: installed certificate %s (notAfter %s)\n", g_cert_path, when);
        rc = MTS_POLL_INSTALLED;
    } else {
        fprintf(stderr, "march: https: refused certificate %s: %s\n", g_cert_path, why);
        if (err && errlen) snprintf(err, errlen, "%s: %s", g_cert_path, why);
        rc = MTS_POLL_REFUSED;
    }
    goto out;
missing:
    if (!g_logged_missing) {
        fprintf(stderr, "march: https: waiting for certificate: %s\n", err && errlen ? err : "");
        g_logged_missing = 1;
    }
out:
    pthread_mutex_unlock(&g_poll_mu);
    free(cert);
    free(key);
    return rc;
}

mts_poll_rc mts_poll_once(char *err, size_t errlen) { return poll_step(0, err, errlen); }
mts_poll_rc mts_poll_initial(char *err, size_t errlen) { return poll_step(1, err, errlen); }

static void *poller_main(void *arg) {
    int secs = (int)(intptr_t)arg;
    for (;;) {
        struct timespec ts = { secs, 0 }, rem;
        while (nanosleep(&ts, &rem) != 0 && errno == EINTR) ts = rem;
        char err[512];
        (void)poll_step(0, err, sizeof err);
    }
    return NULL;
}

int mts_poller_start(int poll_secs) {
    if (poll_secs <= 0) return 0;
    pthread_t t;
    pthread_attr_t a;
    pthread_attr_init(&a);
    pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
    int r = pthread_create(&t, &a, poller_main, (void *)(intptr_t)poll_secs);
    pthread_attr_destroy(&a);
    return r == 0 ? 0 : -1;
}

/* ── the fd -> session registry ───────────────────────────────────────── */

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
