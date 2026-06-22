/* test_remote_registry.c — function-by-identity registry
 * (runtime/march_remote_registry.c).
 *
 * Tests
 * ─────
 *  1. a registered target is found by its impl_hash; its sig_hash is retrievable
 *  2. an unknown impl_hash misses (NULL stub, NULL sig_hash, has == 0)
 *  3. distinct identities coexist; count reflects the number enrolled
 *  4. re-registering the same impl_hash replaces the stub + sig_hash in place
 *     (idempotent on identity — no duplicate entry, count unchanged)
 *  5. NULL impl_hash / NULL stub are rejected (-1) and don't enroll
 *  6. init clears the table; lookups miss afterward
 *  7. collisions in the same bucket are chained and independently resolvable
 */
#include "../runtime/march_remote_registry.h"
#include <stdio.h>
#include <string.h>

static int g_failed = 0;

#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

/* distinct fake stub pointers — never called, only compared */
static void *STUB1 = (void *)0x1111;
static void *STUB2 = (void *)0x2222;
static void *STUB3 = (void *)0x3333;

static const char *IMPL1 = "impl-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
static const char *IMPL2 = "impl-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
static const char *SIG1  = "sig-1111111111111111111111111111111111111111111111";
static const char *SIG2  = "sig-2222222222222222222222222222222222222222222222";

static void test_register_and_lookup(void) {
    march_remote_init();
    int rc = march_remote_register(IMPL1, SIG1, STUB1);
    CHECK(rc == 0, "register succeeds");
    CHECK(march_remote_lookup(IMPL1) == STUB1, "lookup returns the stub");
    CHECK(march_remote_has(IMPL1) == 1, "has reports enrolled");
    CHECK(march_remote_sig_hash(IMPL1) != NULL &&
          strcmp(march_remote_sig_hash(IMPL1), SIG1) == 0, "sig_hash retrievable");
    CHECK(march_remote_count() == 1, "count is 1");
}

static void test_unknown_misses(void) {
    march_remote_init();
    march_remote_register(IMPL1, SIG1, STUB1);
    CHECK(march_remote_lookup(IMPL2) == NULL, "unknown impl misses");
    CHECK(march_remote_sig_hash(IMPL2) == NULL, "unknown sig_hash is NULL");
    CHECK(march_remote_has(IMPL2) == 0, "has reports absent");
}

static void test_distinct_identities(void) {
    march_remote_init();
    march_remote_register(IMPL1, SIG1, STUB1);
    march_remote_register(IMPL2, SIG2, STUB2);
    CHECK(march_remote_count() == 2, "two enrolled");
    CHECK(march_remote_lookup(IMPL1) == STUB1, "first resolves");
    CHECK(march_remote_lookup(IMPL2) == STUB2, "second resolves");
    CHECK(strcmp(march_remote_sig_hash(IMPL2), SIG2) == 0, "second sig_hash");
}

static void test_reregister_replaces(void) {
    march_remote_init();
    march_remote_register(IMPL1, SIG1, STUB1);
    int rc = march_remote_register(IMPL1, SIG2, STUB3);
    CHECK(rc == 0, "re-register succeeds");
    CHECK(march_remote_count() == 1, "no duplicate entry");
    CHECK(march_remote_lookup(IMPL1) == STUB3, "stub replaced");
    CHECK(strcmp(march_remote_sig_hash(IMPL1), SIG2) == 0, "sig_hash replaced");
}

static void test_null_rejected(void) {
    march_remote_init();
    CHECK(march_remote_register(NULL, SIG1, STUB1) == -1, "NULL impl rejected");
    CHECK(march_remote_register(IMPL1, SIG1, NULL) == -1, "NULL stub rejected");
    CHECK(march_remote_count() == 0, "nothing enrolled");
    CHECK(march_remote_lookup(NULL) == NULL, "NULL lookup is NULL");
}

static void test_init_clears(void) {
    march_remote_init();
    march_remote_register(IMPL1, SIG1, STUB1);
    march_remote_register(IMPL2, SIG2, STUB2);
    march_remote_init();
    CHECK(march_remote_count() == 0, "init clears count");
    CHECK(march_remote_lookup(IMPL1) == NULL, "init clears entries");
}

/* Force same-bucket chaining: register many keys, confirm each resolves. */
static void test_chaining(void) {
    march_remote_init();
    char key[64];
    for (int i = 0; i < 200; i++) {
        snprintf(key, sizeof(key), "impl-collide-%d", i);
        int rc = march_remote_register(key, SIG1, (void *)(long)(i + 1));
        CHECK(rc == 0, "bulk register succeeds");
    }
    CHECK(march_remote_count() == 200, "all 200 enrolled");
    for (int i = 0; i < 200; i++) {
        snprintf(key, sizeof(key), "impl-collide-%d", i);
        CHECK(march_remote_lookup(key) == (void *)(long)(i + 1), "each resolves");
    }
    march_remote_init();
}

int main(void) {
    printf("test_remote_registry: function-by-identity registry\n");
    test_register_and_lookup();
    test_unknown_misses();
    test_distinct_identities();
    test_reregister_replaces();
    test_null_rejected();
    test_init_clears();
    test_chaining();
    march_remote_shutdown();
    if (g_failed) {
        fprintf(stderr, "FAILED: %d check(s)\n", g_failed);
        return 1;
    }
    printf("  all checks passed\n");
    return 0;
}
