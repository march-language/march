/* test/test_tls_server.c — unit tests for runtime/march_tls_server.c:
 * building a context from PEM text, the process-global slot (install, swap,
 * acquire, generation, consumers), the certificate file poller and the
 * fd -> session registry. The slot is process-global, so the cases run in a
 * fixed order and the generation counts below assume it. Each case prints
 * "ok <name>"; a failure prints "FAIL <name>: <why>" and exits 1. */

#include "march_tls_server.h"
#include "march_tls_session.h"

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *g_case = "?";
#define CHECK(cond, why) do { if (!(cond)) { \
    fprintf(stderr, "FAIL %s: %s (line %d)\n", g_case, why, __LINE__); \
    ERR_print_errors_fp(stderr); exit(1); } } while (0)

typedef struct { char *cert; size_t cert_len; char *key; size_t key_len; long serial; } pair_t;

static char *bio_to_str(BIO *b, size_t *len) {
    char *p = NULL;
    long n = BIO_get_mem_data(b, &p);
    char *s = malloc((size_t)n + 1);
    memcpy(s, p, (size_t)n); s[n] = '\0';
    *len = (size_t)n;
    return s;
}

/* A self-signed P-256 leaf valid from now-2d to now+not_after_secs. */
static pair_t make_pair(long serial, long not_after_secs) {
    pair_t p; p.serial = serial;
    EVP_PKEY *key = EVP_EC_gen("P-256");
    X509 *x = X509_new();
    X509_set_version(x, 2);
    ASN1_INTEGER_set(X509_get_serialNumber(x), serial);
    X509_gmtime_adj(X509_getm_notBefore(x), -2 * 86400);
    X509_gmtime_adj(X509_getm_notAfter(x), not_after_secs);
    X509_set_pubkey(x, key);
    X509_NAME *n = X509_NAME_new();
    X509_NAME_add_entry_by_txt(n, "CN", MBSTRING_ASC, (const unsigned char *)"localhost", -1, -1, 0);
    X509_set_subject_name(x, n); X509_set_issuer_name(x, n); X509_NAME_free(n);
    X509_sign(x, key, EVP_sha256());
    BIO *bc = BIO_new(BIO_s_mem()); PEM_write_bio_X509(bc, x);
    BIO *bk = BIO_new(BIO_s_mem()); PEM_write_bio_PrivateKey(bk, key, NULL, NULL, 0, NULL, NULL);
    p.cert = bio_to_str(bc, &p.cert_len);
    p.key  = bio_to_str(bk, &p.key_len);
    BIO_free(bc); BIO_free(bk); X509_free(x); EVP_PKEY_free(key);
    return p;
}

static long ctx_serial(SSL_CTX *ctx) {
    X509 *x = SSL_CTX_get0_certificate(ctx);
    return x ? ASN1_INTEGER_get(X509_get0_serialNumber(x)) : -1;
}

static void write_file(const char *path, const char *data, size_t n) {
    FILE *f = fopen(path, "wb");
    CHECK(f, "fopen for write");
    CHECK(fwrite(data, 1, n, f) == n, "fwrite");
    fclose(f);
}

static pair_t A, B, EXPIRED;

static void t_install_ok(void) {
    g_case = "install_ok";
    char err[256] = "";
    CHECK(mts_slot_acquire() == NULL, "slot not empty at start");
    CHECK(mts_slot_install_pem(A.cert, A.cert_len, A.key, A.key_len, 0, err, sizeof err) == 0, err);
    CHECK(mts_slot_generation() == 1, "generation != 1");
    SSL_CTX *c = mts_slot_acquire();
    CHECK(c != NULL, "acquire NULL after install");
    CHECK(ctx_serial(c) == A.serial, "served cert is not A");
    SSL_CTX_free(c);
    printf("ok %s\n", g_case);
}

static void t_mismatch_refused_old_kept(void) {
    g_case = "mismatch_refused_old_kept";
    char err[256] = "";
    CHECK(mts_slot_install_pem(A.cert, A.cert_len, B.key, B.key_len, 0, err, sizeof err) != 0,
          "mismatched pair accepted");
    CHECK(err[0] != '\0', "no error text");
    CHECK(mts_slot_generation() == 1, "generation moved on refusal");
    SSL_CTX *c = mts_slot_acquire();
    CHECK(c && ctx_serial(c) == A.serial, "old cert not kept");
    SSL_CTX_free(c);
    printf("ok %s\n", g_case);
}

static void t_expired_refused_on_reload(void) {
    g_case = "expired_refused_on_reload";
    char err[256] = "";
    SSL_CTX *out = NULL;
    CHECK(mts_ctx_from_pem(EXPIRED.cert, EXPIRED.cert_len, EXPIRED.key, EXPIRED.key_len,
                           0, &out, err, sizeof err) != 0, "expired accepted with allow_expired=0");
    CHECK(strstr(err, "expired") != NULL, "error does not say expired");
    CHECK(out == NULL, "out set on failure");
    err[0] = '\0';
    CHECK(mts_ctx_from_pem(EXPIRED.cert, EXPIRED.cert_len, EXPIRED.key, EXPIRED.key_len,
                           1, &out, err, sizeof err) == 0, "expired refused with allow_expired=1");
    CHECK(out != NULL, "no ctx");
    SSL_CTX_free(out);
    CHECK(mts_slot_generation() == 1, "ctx_from_pem touched the slot");
    printf("ok %s\n", g_case);
}

static void t_garbage_pem_refused(void) {
    g_case = "garbage_pem_refused";
    char err[256] = "";
    SSL_CTX *out = NULL;
    CHECK(mts_ctx_from_pem("not a cert", 10, "not a key", 9, 1, &out, err, sizeof err) != 0,
          "garbage accepted");
    CHECK(err[0] != '\0', "no error text");
    printf("ok %s\n", g_case);
}

static int  g_consumer_calls;
static char g_consumer_cert[8192];
static char g_consumer_key[8192];
static void consumer(const char *cert, size_t cl, const char *key, size_t kl, void *arg) {
    CHECK(arg == (void *)&g_consumer_calls, "consumer arg");
    g_consumer_calls++;
    memcpy(g_consumer_cert, cert, cl); g_consumer_cert[cl] = '\0';
    memcpy(g_consumer_key, key, kl);   g_consumer_key[kl] = '\0';
}

static void t_consumer_notified(void) {
    g_case = "consumer_notified";
    char err[256] = "";
    mts_slot_add_consumer(consumer, &g_consumer_calls);
    CHECK(mts_slot_install_pem(B.cert, B.cert_len, B.key, B.key_len, 0, err, sizeof err) == 0, err);
    CHECK(g_consumer_calls == 1, "consumer not called exactly once");
    CHECK(strcmp(g_consumer_cert, B.cert) == 0 && strcmp(g_consumer_key, B.key) == 0,
          "consumer did not get B's exact PEM");
    CHECK(mts_slot_generation() == 2, "generation != 2");
    printf("ok %s\n", g_case);
}

static void t_old_ctx_survives_swap(void) {
    g_case = "old_ctx_survives_swap";
    char err[256] = "";
    SSL_CTX *old = mts_slot_acquire();            /* B, +1 */
    CHECK(old && ctx_serial(old) == B.serial, "acquire B");
    CHECK(mts_slot_install_pem(A.cert, A.cert_len, A.key, A.key_len, 0, err, sizeof err) == 0, err);
    SSL *ssl = SSL_new(old);
    CHECK(ssl != NULL, "SSL_new on swapped-out ctx");
    CHECK(ctx_serial(old) == B.serial, "old ctx changed");
    SSL_free(ssl);
    SSL_CTX_free(old);
    SSL_CTX *now = mts_slot_acquire();
    CHECK(now && ctx_serial(now) == A.serial, "slot not A after swap");
    SSL_CTX_free(now);
    printf("ok %s\n", g_case);
}

static void t_poll_sequence(void) {
    g_case = "poll_sequence";
    char err[256];
    char dir[] = "/tmp/march_tls_server_XXXXXX";
    CHECK(mkdtemp(dir), "mkdtemp");
    char cp[512], kp[512];
    snprintf(cp, sizeof cp, "%s/cert.pem", dir);
    snprintf(kp, sizeof kp, "%s/key.pem", dir);
    pair_t C = make_pair(30, 3600), D = make_pair(40, 3600);
    write_file(cp, C.cert, C.cert_len);
    write_file(kp, C.key, C.key_len);
    mts_poller_set_paths(cp, kp);
    uint64_t g0 = mts_slot_generation();

    CHECK(mts_poll_once(err, sizeof err) == MTS_POLL_INSTALLED, "first poll not INSTALLED");
    CHECK(mts_slot_generation() == g0 + 1, "generation after install");
    CHECK(mts_poll_once(err, sizeof err) == MTS_POLL_UNCHANGED, "second poll not UNCHANGED");

    write_file(kp, D.key, D.key_len);            /* cert C + key D: mismatch */
    CHECK(mts_poll_once(err, sizeof err) == MTS_POLL_REFUSED, "mismatch not REFUSED");
    CHECK(err[0] != '\0', "no refusal reason");
    CHECK(mts_poll_once(err, sizeof err) == MTS_POLL_UNCHANGED, "refused content retried");
    CHECK(mts_slot_generation() == g0 + 1, "generation moved on refusal");

    write_file(cp, D.cert, D.cert_len);          /* cert D + key D: renewal done */
    CHECK(mts_poll_once(err, sizeof err) == MTS_POLL_INSTALLED, "matching pair not INSTALLED");
    SSL_CTX *c = mts_slot_acquire();
    CHECK(c && ctx_serial(c) == D.serial, "D not served");
    SSL_CTX_free(c);

    unlink(cp); unlink(kp); rmdir(dir);
    uint64_t g = mts_slot_generation();
    CHECK(mts_poll_once(err, sizeof err) == MTS_POLL_MISSING, "missing files not MISSING");
    CHECK(mts_slot_generation() == g, "generation moved on missing");
    printf("ok %s\n", g_case);
}

static void t_registry(void) {
    g_case = "registry";
    march_tls_session_t *s = (march_tls_session_t *)(uintptr_t)0x1234;  /* stored, never dereferenced */
    mts_registry_put(7, s);
    CHECK(mts_registry_get(7) == s, "get after put");
    CHECK(mts_registry_take(7) == s, "take");
    CHECK(mts_registry_get(7) == NULL, "get after take");
    CHECK(mts_registry_get(123456) == NULL, "get of never-put fd");
    mts_registry_put(70000, s);
    CHECK(mts_registry_get(70000) == s, "large fd");
    CHECK(mts_registry_take(70000) == s, "take large fd");
    printf("ok %s\n", g_case);
}

int main(void) {
    A = make_pair(10, 3600);
    B = make_pair(20, 3600);
    EXPIRED = make_pair(99, -86400);
    t_install_ok();
    t_mismatch_refused_old_kept();
    t_expired_refused_on_reload();
    t_garbage_pem_refused();
    t_consumer_notified();
    t_old_ctx_survives_swap();
    t_poll_sequence();
    t_registry();
    printf("all tls server tests passed\n");
    return 0;
}
