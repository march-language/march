/* pqc.c — one translation unit over the vendored mlkem-native and
 * mldsa-native monobuilds (runtime/third_party/{mlkem,mldsa}-native), exposing
 * the small deterministic API in pqc.h. Like tweetnacl.c it has no March
 * runtime dependency: it is also compiled into the OCaml library lib/pqc that
 * gives the interpreter parity. March's builtins over it are march_pqc.c.
 *
 * Configuration: the portable C backend only (no assembly, no CPU dispatch),
 * the deterministic API only (no randombytes() needed), every internal symbol
 * static, and the upstream config headers for the rest. */
#include "pqc.h"

/* Some internal helpers go unused under this configuration. */
#pragma GCC diagnostic ignored "-Wunused-function"

/* ---- ML-KEM-768 ---- */
#define MLK_CONFIG_PARAMETER_SET 768
#define MLK_CONFIG_NAMESPACE_PREFIX pqc_mlk768
#define MLK_CONFIG_NO_RANDOMIZED_API
#define MLK_CONFIG_INTERNAL_API_QUALIFIER static
#define MLK_CONFIG_EXTERNAL_API_QUALIFIER static
/* Resolved relative to mlkem/src/common.h, which includes it. */
#define MLK_CONFIG_FILE "../mlkem_native_config.h"
#include "third_party/mlkem-native/mlkem/mlkem_native.c"

int pqc_mlkem768_keypair_derand(uint8_t *pk, uint8_t *sk, const uint8_t *coins) {
    return pqc_mlk768_keypair_derand(pk, sk, coins);
}

int pqc_mlkem768_enc_derand(uint8_t *ct, uint8_t *ss, const uint8_t *pk,
                            const uint8_t *coins) {
    return pqc_mlk768_enc_derand(ct, ss, pk, coins);
}

int pqc_mlkem768_dec(uint8_t *ss, const uint8_t *ct, const uint8_t *sk) {
    return pqc_mlk768_dec(ss, ct, sk);
}

/* ---- ML-DSA-65 ---- */
#define MLD_CONFIG_PARAMETER_SET 65
#define MLD_CONFIG_NAMESPACE_PREFIX pqc_mld65
#define MLD_CONFIG_NO_RANDOMIZED_API
#define MLD_CONFIG_CORE_API_ONLY
#define MLD_CONFIG_INTERNAL_API_QUALIFIER static
#define MLD_CONFIG_EXTERNAL_API_QUALIFIER static
#define MLD_CONFIG_FILE "../mldsa_native_config.h"
#include "third_party/mldsa-native/mldsa/mldsa_native.c"

/* FIPS 204 pure-ML-DSA message prefix for an empty context: 0 || len(ctx). */
static const uint8_t pqc_mldsa_empty_ctx[2] = {0, 0};

int pqc_mldsa65_keypair_internal(uint8_t *pk, uint8_t *sk, const uint8_t *seed) {
    return pqc_mld65_keypair_internal(pk, sk, seed);
}

int pqc_mldsa65_sign(uint8_t *sig, const uint8_t *m, size_t mlen,
                     const uint8_t *rnd, const uint8_t *sk) {
    return pqc_mld65_signature_internal(sig, m, mlen, pqc_mldsa_empty_ctx, 2,
                                        rnd, sk, 0);
}

int pqc_mldsa65_verify(const uint8_t *sig, const uint8_t *m, size_t mlen,
                       const uint8_t *pk) {
    return pqc_mld65_verify_internal(sig, m, mlen, pqc_mldsa_empty_ctx, 2, pk, 0);
}
