/* dd12 repro: ATTACKER bytes uploaded under the operator's cas_hash.
 * It carries the identity markers (plain public strings, linked in from
 * runtime/march_hcr_identity.c exactly like a real patch) and runs code from
 * a constructor at dlopen time, before any check the server makes after
 * dlopen. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
__attribute__((constructor)) static void pwn(void) {
    const char *m = getenv("DD12_MARKER");
    if (m) {
        FILE *f = fopen(m, "w");
        if (f) { fputs("attacker constructor ran\n", f); fclose(f); }
    }
}
void __march_init(uint32_t epoch) { (void)epoch; }
int64_t test_fn_epoch(void) { return 1337; }
