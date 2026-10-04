/* dd12 repro: the operator's LEGIT patch (what the signed cas_hash names). */
#include <stdint.h>
static uint32_t g_epoch;
void __march_init(uint32_t epoch) { g_epoch = epoch; }
int64_t test_fn_epoch(void) { return 42 + (int64_t)g_epoch * 0; }
