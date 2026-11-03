/* pqc.h — the post-quantum primitives runtime/pqc.c exposes: ML-KEM-768
 * (FIPS 203) and ML-DSA-65 (FIPS 204), from the vendored mlkem-native and
 * mldsa-native (runtime/third_party/, see their UPSTREAM.md).
 *
 * Only the deterministic ("derand"/"internal") entry points are built: every
 * random input (key seed, encapsulation coins, signing rnd) is passed in by
 * the caller, so the library needs no RNG and the same bytes give the same
 * result on every backend (compiled runtime, interpreter via lib/pqc, JIT).
 * All functions return 0 on success. */
#ifndef MARCH_PQC_H
#define MARCH_PQC_H

#include <stddef.h>
#include <stdint.h>

#define PQC_MLKEM768_PUBLICKEYBYTES   1184
#define PQC_MLKEM768_SECRETKEYBYTES   2400
#define PQC_MLKEM768_CIPHERTEXTBYTES  1088
#define PQC_MLKEM768_SSBYTES            32
#define PQC_MLKEM768_KEYPAIR_SEEDBYTES  64   /* d || z */
#define PQC_MLKEM768_ENC_COINBYTES      32

#define PQC_MLDSA65_PUBLICKEYBYTES    1952
#define PQC_MLDSA65_SECRETKEYBYTES    4032
#define PQC_MLDSA65_SIGBYTES          3309
#define PQC_MLDSA65_SEEDBYTES           32
#define PQC_MLDSA65_RNDBYTES            32

int pqc_mlkem768_keypair_derand(uint8_t *pk, uint8_t *sk, const uint8_t *coins);
int pqc_mlkem768_enc_derand(uint8_t *ct, uint8_t *ss, const uint8_t *pk,
                            const uint8_t *coins);
int pqc_mlkem768_dec(uint8_t *ss, const uint8_t *ct, const uint8_t *sk);

int pqc_mldsa65_keypair_internal(uint8_t *pk, uint8_t *sk, const uint8_t *seed);
/* Pure ML-DSA (FIPS 204 Algorithm 2/3) with an EMPTY context string. */
int pqc_mldsa65_sign(uint8_t *sig, const uint8_t *m, size_t mlen,
                     const uint8_t *rnd, const uint8_t *sk);
int pqc_mldsa65_verify(const uint8_t *sig, const uint8_t *m, size_t mlen,
                       const uint8_t *pk);

#endif
