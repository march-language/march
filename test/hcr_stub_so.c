/* hcr_stub_so.c -- a minimal hot-patch shared object for the reload
 * server's end-to-end epoch test (test_reload_activate4.c, "epoch model").
 * It exports what march_reload.c dlsym's from a real --compile-so patch: the
 * activated function and __march_init.  No runtime dependencies.
 *
 * Built twice (test/dune): hcr_stub.so, and with -DHCR_STUB_EVIL
 * hcr_evil.so, the attacker's bytes of the dd12 review's CAS-substitution
 * repro (specs/reviews/dd12/): the same exports and identity markers, a
 * different answer, and a constructor that runs at dlopen time and leaves
 * a marker file ($MARCH_TEST_EVIL_MARKER) behind, so the test can tell
 * whether any of its code was ever mapped. */
#include <stdint.h>
#ifdef HCR_STUB_EVIL
#include <stdio.h>
#include <stdlib.h>
#endif

static uint32_t g_epoch;

void __march_init(uint32_t epoch) { g_epoch = epoch; }

#ifdef HCR_STUB_EVIL
__attribute__((constructor)) static void evil_ctor(void) {
    const char *m = getenv("MARCH_TEST_EVIL_MARKER");
    FILE *f = m ? fopen(m, "w") : NULL;
    if (f) { fputs("attacker constructor ran\n", f); fclose(f); }
}
int64_t test_fn_epoch(void) { return 1337 + (int64_t)g_epoch * 0; }
int64_t test_fn_digest(void) { return 1337; }
#else
int64_t test_fn_epoch(void) { return 42 + (int64_t)g_epoch * 0; }
int64_t test_fn_digest(void) { return 42; }
#endif
