/* test_blake3_agreement.c — cross-implementation BLAKE3 agreement check.
 *
 * The compiler's cap_root (Phase5C-A) is computed with March_cas.Blake3
 * (lib/cas/blake3_stubs.c, OCaml FFI over libblake3). The reload server
 * (runtime/march_reload.c, Phase5C-C.3) recomputes cap_root server-side
 * using the pure-C runtime/march_blake3.c helper over the *same* libblake3
 * API and the *same* hex-encoding loop. If the two ever diverged, every
 * cap_root tamper check would silently break (server would compute a
 * different digest than the signed one, and either falsely reject honest
 * artifacts or — worse — accept a forged cap set that happens to collide
 * under the server's differently-encoded digest).
 *
 * This test asserts runtime march_blake3_hex(FIXTURE) equals a hex literal
 * that was independently produced by March_cas.Blake3.hash_string(FIXTURE)
 * on the OCaml side (see test/test_cas.ml's "cross-impl agreement" case,
 * which asserts the same literal against the OCaml implementation). A
 * single literal can only satisfy both assertions if the two
 * implementations agree bit-for-bit; if either implementation's hashing or
 * hex-encoding changes, one side's test fails immediately. */
#include "../runtime/march_blake3.h"
#include <stdio.h>
#include <string.h>

static int g_failed = 0;

#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

/* Kept byte-for-byte identical to the OCaml-side fixture in test_cas.ml. */
#define FIXTURE "march-hcr-blake3-agreement-fixture"
/* Independently computed via March_cas.Blake3.hash_string FIXTURE. */
#define FIXTURE_EXPECTED_HEX "24b435176d98631a620c35d049975df9e07dd4d761d89593f1e6b55fe3767717"

static void test_fixture_matches_ocaml_blake3(void) {
    char out[65];
    march_blake3_hex((const unsigned char *)FIXTURE, strlen(FIXTURE), out);
    CHECK(strlen(out) == 64, "runtime BLAKE3 hex digest is 64 chars");
    CHECK(strcmp(out, FIXTURE_EXPECTED_HEX) == 0,
          "runtime march_blake3_hex(FIXTURE) matches March_cas.Blake3.hash_string(FIXTURE)");
    printf("PASS: test_fixture_matches_ocaml_blake3 (%s)\n", out);
}

/* Known-answer test independent of the OCaml side: BLAKE3 of the empty
 * string, from the official BLAKE3 test vectors (also asserted OCaml-side
 * in test_cas.ml's test_blake3_known_vector). Confirms the runtime
 * implementation is a correct BLAKE3, not merely self-consistent with a
 * possibly-shared bug. */
static void test_empty_input_known_vector(void) {
    char out[65];
    march_blake3_hex((const unsigned char *)"", 0, out);
    const char *expected = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";
    CHECK(strcmp(out, expected) == 0, "runtime BLAKE3 of empty input matches known vector");
    printf("PASS: test_empty_input_known_vector (%s)\n", out);
}

static void test_different_inputs_different_hashes(void) {
    char out1[65], out2[65];
    march_blake3_hex((const unsigned char *)"hello", 5, out1);
    march_blake3_hex((const unsigned char *)"world", 5, out2);
    CHECK(strcmp(out1, out2) != 0, "different inputs hash differently");
    printf("PASS: test_different_inputs_different_hashes\n");
}

static void test_same_input_same_hash(void) {
    char out1[65], out2[65];
    march_blake3_hex((const unsigned char *)"hello", 5, out1);
    march_blake3_hex((const unsigned char *)"hello", 5, out2);
    CHECK(strcmp(out1, out2) == 0, "same input hashes identically");
    printf("PASS: test_same_input_same_hash\n");
}

int main(void) {
    test_fixture_matches_ocaml_blake3();
    test_empty_input_known_vector();
    test_different_inputs_different_hashes();
    test_same_input_same_hash();
    if (g_failed == 0) { printf("test_blake3_agreement: all checks passed\n"); return 0; }
    fprintf(stderr, "test_blake3_agreement: %d check(s) failed\n", g_failed);
    return 1;
}
