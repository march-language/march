/* march_nacl.c — March builtins over the vendored TweetNaCl (tweetnacl.c):
 * ed25519 signatures and X25519 key agreement, for node certificates and the
 * cluster handshake (stdlib/node_cert.march, stdlib/net_kernel.march).
 *
 *   ed25519_seed_keypair(seed : Bytes) : Bytes       64-byte sk = seed || pk
 *   ed25519_sign(sk : Bytes, msg : Bytes) : Bytes    64-byte detached signature
 *   ed25519_verify(pk : Bytes, msg : Bytes, sig : Bytes) : Bool
 *   x25519(scalar : Bytes, point : Bytes) : Bytes    32 bytes
 *
 * A wrong-length argument never aborts: the Bytes-returning builtins return
 * EMPTY Bytes and verify returns false, and the stdlib checks for that. x25519
 * also returns empty Bytes for an all-zero result (a low-order peer point,
 * RFC 7748 section 6.1), so a caller cannot derive a key everyone knows.
 *
 * Arguments are borrowed (lib/tir/borrow.ml); results are owned.
 * Kept out of tweetnacl.c because that file is also compiled standalone into
 * the OCaml ed25519 library (lib/ed25519) and C test harnesses, which have no
 * March runtime to link against. */
#include "march_runtime.h"
#include "tweetnacl.h"
#include <stdlib.h>
#include <string.h>

/* Bytes(payload): the one-field boxed cell, the payload a march_string at +16
 * (the shape march_extras.c's bytes_wrap builds and repr.ml relies on). */
static const uint8_t *nacl_bytes_data(void *b, size_t *len) {
    march_string *s = b ? *(march_string **)((char *)b + 16) : NULL;
    *len = s ? (size_t)s->len : 0;
    return s ? (const uint8_t *)s->data : (const uint8_t *)"";
}

static void *nacl_bytes_new(const uint8_t *data, size_t len) {
    void *s = march_string_lit(data ? (const char *)data : "", (int64_t)len);
    void *b = march_alloc(16 + 8);
    *(void **)((char *)b + 16) = s;
    return b;
}

void *march_ed25519_seed_keypair(void *seed) {
    size_t n;
    const uint8_t *sd = nacl_bytes_data(seed, &n);
    if (n != 32) return nacl_bytes_new(NULL, 0);
    uint8_t pk[32], sk[64];
    crypto_sign_seed_keypair(pk, sk, sd);
    return nacl_bytes_new(sk, 64);
}

void *march_ed25519_sign(void *sk, void *msg) {
    size_t kn, mn;
    const uint8_t *k = nacl_bytes_data(sk, &kn);
    const uint8_t *m = nacl_bytes_data(msg, &mn);
    if (kn != 64) return nacl_bytes_new(NULL, 0);
    uint8_t *sm = malloc(mn + 64);
    if (!sm) return nacl_bytes_new(NULL, 0);
    unsigned long long smlen = 0;
    crypto_sign(sm, &smlen, m, (unsigned long long)mn, k);
    void *out = nacl_bytes_new(sm, 64);
    free(sm);
    return out;
}

int64_t march_ed25519_verify(void *pk, void *msg, void *sig) {
    size_t pn, mn, sn;
    const uint8_t *p = nacl_bytes_data(pk, &pn);
    const uint8_t *m = nacl_bytes_data(msg, &mn);
    const uint8_t *s = nacl_bytes_data(sig, &sn);
    if (pn != 32 || sn != 64) return 0;
    uint8_t *sm = malloc(mn + 64);
    uint8_t *out = malloc(mn + 64);
    if (!sm || !out) { free(sm); free(out); return 0; }
    memcpy(sm, s, 64);
    if (mn > 0) memcpy(sm + 64, m, mn);
    unsigned long long olen = 0;
    int rc = crypto_sign_open(out, &olen, sm, (unsigned long long)(mn + 64), p);
    free(sm); free(out);
    return rc == 0 ? 1 : 0;
}

void *march_x25519(void *scalar, void *point) {
    size_t kn, un;
    const uint8_t *k = nacl_bytes_data(scalar, &kn);
    const uint8_t *u = nacl_bytes_data(point, &un);
    if (kn != 32 || un != 32) return nacl_bytes_new(NULL, 0);
    uint8_t q[32];
    crypto_scalarmult(q, k, u);
    uint8_t acc = 0;
    for (int i = 0; i < 32; i++) acc |= q[i];
    if (acc == 0) return nacl_bytes_new(NULL, 0);
    return nacl_bytes_new(q, 32);
}
