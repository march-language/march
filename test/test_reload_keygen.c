/* test_reload_keygen.c — generates one ed25519 keypair for the ACTIVATE4
 * end-to-end test (test_reload_activate4.c).
 *
 * march_reload.c's signature verification key is baked in at *compile time*
 * via the MARCH_SIGNING_PUBKEY_HEX macro (mirrors the real compiler's
 * --signing-pubkey flow, bin/main.ml). To exercise that path in a test we
 * need the public key hex available before compiling the test binary, and
 * the secret key available at test run time to actually sign ACTIVATE4
 * messages. This tiny helper runs once at build time (see test/dune),
 * printing "<pubkey_hex>\n<sk_hex>\n" to stdout; the dune rule captures the
 * first line into a -D flag for the real test and the test binary re-reads
 * the full file at run time to get the secret key.
 */
#include "tweetnacl.h"
#include <stdio.h>

static void to_hex(const unsigned char *buf, int len, char *out) {
    static const char hc[] = "0123456789abcdef";
    for (int i = 0; i < len; i++) {
        out[2*i]   = hc[(buf[i] >> 4) & 0xf];
        out[2*i+1] = hc[buf[i] & 0xf];
    }
    out[2*len] = '\0';
}

int main(void) {
    unsigned char pk[32], sk[64];
    if (crypto_sign_keypair(pk, sk) != 0) {
        fprintf(stderr, "test_reload_keygen: crypto_sign_keypair failed\n");
        return 1;
    }
    char pk_hex[65], sk_hex[129];
    to_hex(pk, 32, pk_hex);
    to_hex(sk, 64, sk_hex);
    printf("%s\n%s\n", pk_hex, sk_hex);
    return 0;
}
