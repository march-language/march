/* march_pqc.c — March builtins over the vendored post-quantum primitives
 * (runtime/pqc.c: mlkem-native and mldsa-native), for stdlib/ml_kem.march and
 * stdlib/ml_dsa.march.
 *
 *   mlkem768_keypair(seed : Bytes) : Bytes             64-byte seed (d || z) ->
 *                                                     2400-byte decapsulation key;
 *                                                     the 1184-byte encapsulation
 *                                                     key is bytes 1152..2336 of it
 *   mlkem768_encaps(pk : Bytes, coins : Bytes) : Bytes 32 coins -> ciphertext (1088)
 *                                                     || shared secret (32)
 *   mlkem768_decaps(sk : Bytes, ct : Bytes) : Bytes    shared secret (32)
 *   mldsa65_keypair(seed : Bytes) : Bytes              32-byte seed -> sk (4032) || pk (1952)
 *   mldsa65_sign(sk : Bytes, msg : Bytes, rnd : Bytes) : Bytes   3309-byte signature
 *   mldsa65_verify(pk : Bytes, msg : Bytes, sig : Bytes) : Bool
 *
 * Every random input is an argument (the stdlib draws it from
 * Crypto.random_bytes), so these are deterministic and the interpreter
 * (lib/pqc) gives the same bytes. Same failure convention as march_nacl.c: a
 * wrong-length argument, or a key the library rejects (ML-KEM's FIPS 203
 * input checks), gives EMPTY Bytes and verify gives false; never an abort.
 * Decapsulating a ciphertext that was not made for this key is NOT a failure:
 * ML-KEM's implicit rejection returns a pseudorandom secret.
 *
 * Arguments are borrowed (lib/tir/borrow.ml); results are owned. */
#include "march_runtime.h"
#include "pqc.h"
#include <stdlib.h>
#include <string.h>

/* Bytes(payload): the one-field boxed cell, the payload a march_string at +16
 * (the same shape march_nacl.c reads and builds). */
static const uint8_t *pqc_bytes_data(void *b, size_t *len) {
    march_string *s = b ? *(march_string **)((char *)b + 16) : NULL;
    *len = s ? (size_t)s->len : 0;
    return s ? (const uint8_t *)s->data : (const uint8_t *)"";
}

static void *pqc_bytes_new(const uint8_t *data, size_t len) {
    void *s = march_string_lit(data ? (const char *)data : "", (int64_t)len);
    void *b = march_alloc(16 + 8);
    *(void **)((char *)b + 16) = s;
    return b;
}

static void *pqc_empty(void) { return pqc_bytes_new(NULL, 0); }

void *march_mlkem768_keypair(void *seed) {
    size_t n;
    const uint8_t *sd = pqc_bytes_data(seed, &n);
    if (n != PQC_MLKEM768_KEYPAIR_SEEDBYTES) return pqc_empty();
    uint8_t pk[PQC_MLKEM768_PUBLICKEYBYTES], sk[PQC_MLKEM768_SECRETKEYBYTES];
    if (pqc_mlkem768_keypair_derand(pk, sk, sd) != 0) return pqc_empty();
    void *out = pqc_bytes_new(sk, sizeof sk);
    memset(sk, 0, sizeof sk);
    return out;
}

void *march_mlkem768_encaps(void *pk, void *coins) {
    size_t pn, cn;
    const uint8_t *p = pqc_bytes_data(pk, &pn);
    const uint8_t *c = pqc_bytes_data(coins, &cn);
    if (pn != PQC_MLKEM768_PUBLICKEYBYTES || cn != PQC_MLKEM768_ENC_COINBYTES)
        return pqc_empty();
    uint8_t out[PQC_MLKEM768_CIPHERTEXTBYTES + PQC_MLKEM768_SSBYTES];
    if (pqc_mlkem768_enc_derand(out, out + PQC_MLKEM768_CIPHERTEXTBYTES, p, c) != 0)
        return pqc_empty();
    void *r = pqc_bytes_new(out, sizeof out);
    memset(out, 0, sizeof out);
    return r;
}

void *march_mlkem768_decaps(void *sk, void *ct) {
    size_t sn, cn;
    const uint8_t *s = pqc_bytes_data(sk, &sn);
    const uint8_t *c = pqc_bytes_data(ct, &cn);
    if (sn != PQC_MLKEM768_SECRETKEYBYTES || cn != PQC_MLKEM768_CIPHERTEXTBYTES)
        return pqc_empty();
    uint8_t ss[PQC_MLKEM768_SSBYTES];
    if (pqc_mlkem768_dec(ss, c, s) != 0) return pqc_empty();
    void *r = pqc_bytes_new(ss, sizeof ss);
    memset(ss, 0, sizeof ss);
    return r;
}

void *march_mldsa65_keypair(void *seed) {
    size_t n;
    const uint8_t *sd = pqc_bytes_data(seed, &n);
    if (n != PQC_MLDSA65_SEEDBYTES) return pqc_empty();
    /* sk || pk, one buffer: the result layout. */
    uint8_t *kp = malloc(PQC_MLDSA65_SECRETKEYBYTES + PQC_MLDSA65_PUBLICKEYBYTES);
    if (!kp) return pqc_empty();
    void *r;
    if (pqc_mldsa65_keypair_internal(kp + PQC_MLDSA65_SECRETKEYBYTES, kp, sd) != 0)
        r = pqc_empty();
    else
        r = pqc_bytes_new(kp, PQC_MLDSA65_SECRETKEYBYTES + PQC_MLDSA65_PUBLICKEYBYTES);
    memset(kp, 0, PQC_MLDSA65_SECRETKEYBYTES);
    free(kp);
    return r;
}

void *march_mldsa65_sign(void *sk, void *msg, void *rnd) {
    size_t kn, mn, rn;
    const uint8_t *k = pqc_bytes_data(sk, &kn);
    const uint8_t *m = pqc_bytes_data(msg, &mn);
    const uint8_t *r = pqc_bytes_data(rnd, &rn);
    if (kn != PQC_MLDSA65_SECRETKEYBYTES || rn != PQC_MLDSA65_RNDBYTES)
        return pqc_empty();
    uint8_t sig[PQC_MLDSA65_SIGBYTES];
    if (pqc_mldsa65_sign(sig, m, mn, r, k) != 0) return pqc_empty();
    return pqc_bytes_new(sig, sizeof sig);
}

int64_t march_mldsa65_verify(void *pk, void *msg, void *sig) {
    size_t pn, mn, sn;
    const uint8_t *p = pqc_bytes_data(pk, &pn);
    const uint8_t *m = pqc_bytes_data(msg, &mn);
    const uint8_t *s = pqc_bytes_data(sig, &sn);
    if (pn != PQC_MLDSA65_PUBLICKEYBYTES || sn != PQC_MLDSA65_SIGBYTES) return 0;
    return pqc_mldsa65_verify(s, m, mn, p) == 0 ? 1 : 0;
}
