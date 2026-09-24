/* hcr_stub_so.c -- a minimal hot-patch shared object for the reload
 * server's end-to-end epoch test (test_reload_activate4.c, "epoch model").
 * It exports what march_reload.c dlsym's from a real --compile-so patch: the
 * activated function and __march_init.  No runtime dependencies. */
#include <stdint.h>

static uint32_t g_epoch;

void __march_init(uint32_t epoch) { g_epoch = epoch; }

int64_t test_fn_epoch(void) { return 42 + (int64_t)g_epoch * 0; }
