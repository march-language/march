/* march_blake3.c — BLAKE3 hex-digest helper for the C runtime.
 *
 * Calls libblake3 directly (blake3_hasher_init/_update/_finalize) and hex-
 * encodes the 32-byte digest exactly the way lib/cas/blake3_stubs.c does
 * (march_blake3_hash, the OCaml-FFI stub used by March_cas.Blake3), so the
 * two implementations agree byte-for-byte on the same input. See
 * test/test_blake3_agreement.c for the cross-implementation proof and
 * march_blake3.h for why this matters (server-side cap_root recompute). */
#include "march_blake3.h"
#include <blake3.h>

void march_blake3_hex(const unsigned char *buf, size_t len, char out[65]) {
    uint8_t digest[BLAKE3_OUT_LEN];

    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, buf, len);
    blake3_hasher_finalize(&hasher, digest, BLAKE3_OUT_LEN);

    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < BLAKE3_OUT_LEN; i++) {
        out[i * 2]     = hex[(digest[i] >> 4) & 0xf];
        out[i * 2 + 1] = hex[digest[i] & 0xf];
    }
    out[BLAKE3_OUT_LEN * 2] = '\0';
}
