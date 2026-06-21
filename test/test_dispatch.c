/* test_dispatch.c — HCR versioned dispatch table (runtime/march_dispatch.c).
 *
 * Tests
 * ─────
 *  1. first publish becomes current; enter pins it and returns its fn_ptr
 *  2. leave drops the refcount back to zero
 *  3. a second publish advances current; enter sees the new version
 *  4. a caller pinned to the old version stays pinned across a publish, and
 *     leave targets that old version (not current)
 *  5. publish fails (-1) when no non-current ring slot is reclaimable, and
 *     succeeds again once the blocking caller leaves
 *  6. impl_hash is stored per version and retrievable
 *  7. out-of-range name_id is handled safely
 */
#include "../runtime/march_dispatch.h"
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int g_failed = 0;

#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

/* distinct fake code pointers — never called, just compared */
static void *FN1 = (void *)0x1111;
static void *FN2 = (void *)0x2222;
static void *FN3 = (void *)0x3333;

static const char *H1 = "1111111111111111111111111111111111111111111111111111111111111111";
static const char *H2 = "2222222222222222222222222222222222222222222222222222222222222222";

static void test_first_publish_and_enter(void) {
    march_dispatch_init(4);
    int idx = march_dispatch_publish(0, FN1, H1, MARCH_NATIVE);
    CHECK(idx == 0, "first publish uses ring index 0");
    CHECK(march_dispatch_current(0) == 0, "current is 0 after first publish");

    uint32_t v = 99;
    void *fn = march_dispatch_enter(0, &v);
    CHECK(fn == FN1, "enter returns the published fn_ptr");
    CHECK(v == 0, "enter reports the pinned version index");
    CHECK(march_dispatch_refs(0, 0) == 1, "refs incremented to 1 after enter");
    march_dispatch_leave(0, v);
    march_dispatch_shutdown();
}

static void test_leave_drops_refs(void) {
    march_dispatch_init(4);
    march_dispatch_publish(0, FN1, H1, MARCH_NATIVE);
    uint32_t v;
    march_dispatch_enter(0, &v);
    march_dispatch_leave(0, v);
    CHECK(march_dispatch_refs(0, 0) == 0, "refs back to 0 after leave");
    march_dispatch_shutdown();
}

static void test_second_publish_advances_current(void) {
    march_dispatch_init(4);
    march_dispatch_publish(0, FN1, H1, MARCH_NATIVE);
    int idx2 = march_dispatch_publish(0, FN2, H2, MARCH_NATIVE);
    CHECK(idx2 == 1, "second publish uses the other ring slot");
    CHECK(march_dispatch_current(0) == 1, "current advanced to 1");
    uint32_t v;
    void *fn = march_dispatch_enter(0, &v);
    CHECK(fn == FN2, "enter now returns the new version");
    CHECK(v == 1, "pinned version is the new one");
    march_dispatch_leave(0, v);
    march_dispatch_shutdown();
}

static void test_old_version_stays_pinned(void) {
    march_dispatch_init(4);
    march_dispatch_publish(0, FN1, H1, MARCH_NATIVE);
    uint32_t vold;
    void *fnold = march_dispatch_enter(0, &vold);   /* pin v0 */
    CHECK(fnold == FN1, "old caller entered v0");

    march_dispatch_publish(0, FN2, H2, MARCH_NATIVE); /* current -> 1 */
    uint32_t vnew;
    void *fnnew = march_dispatch_enter(0, &vnew);    /* pin v1 */
    CHECK(fnnew == FN2, "new caller entered v1");
    CHECK(vnew == 1, "new caller pinned v1");
    CHECK(march_dispatch_refs(0, 0) == 1, "old version still pinned (refs 1)");
    CHECK(march_dispatch_refs(0, 1) == 1, "new version pinned (refs 1)");

    march_dispatch_leave(0, vold);                   /* unpin the OLD version */
    CHECK(march_dispatch_refs(0, 0) == 0, "old version unpinned");
    CHECK(march_dispatch_refs(0, 1) == 1, "new version untouched by old leave");
    march_dispatch_leave(0, vnew);
    march_dispatch_shutdown();
}

static void test_publish_blocked_then_unblocked(void) {
    march_dispatch_init(4);
    march_dispatch_publish(0, FN1, H1, MARCH_NATIVE); /* v0, current 0 */
    uint32_t v0;
    march_dispatch_enter(0, &v0);                     /* pin v0 */
    march_dispatch_publish(0, FN2, H2, MARCH_NATIVE); /* v1, current 1 */

    /* Cap is 2; both ring slots are now occupied: slot 1 is current, slot 0 is
       pinned. A third publish has no reclaimable slot -> -1. */
    int idx3 = march_dispatch_publish(0, FN3, H1, MARCH_NATIVE);
    CHECK(idx3 == -1, "publish blocked while old version pinned");
    CHECK(march_dispatch_current(0) == 1, "current unchanged after blocked publish");

    march_dispatch_leave(0, v0);                      /* free slot 0 */
    int idx3b = march_dispatch_publish(0, FN3, H1, MARCH_NATIVE);
    CHECK(idx3b == 0, "publish reclaims the freed slot");
    CHECK(march_dispatch_current(0) == 0, "current advanced to reclaimed slot");
    march_dispatch_shutdown();
}

static void test_impl_hash_stored(void) {
    march_dispatch_init(4);
    march_dispatch_publish(2, FN1, H1, MARCH_NATIVE);
    CHECK(strcmp(march_dispatch_impl_hash(2, 0), H1) == 0, "impl_hash stored per version");
    march_dispatch_shutdown();
}

static void test_out_of_range_is_safe(void) {
    march_dispatch_init(2);
    CHECK(march_dispatch_publish(5, FN1, H1, MARCH_NATIVE) == -1, "publish out of range -> -1");
    uint32_t v;
    CHECK(march_dispatch_enter(5, &v) == NULL, "enter out of range -> NULL");
    march_dispatch_leave(5, 0); /* must not crash */
    march_dispatch_shutdown();
}

int main(void) {
    test_first_publish_and_enter();
    test_leave_drops_refs();
    test_second_publish_advances_current();
    test_old_version_stays_pinned();
    test_publish_blocked_then_unblocked();
    test_impl_hash_stored();
    test_out_of_range_is_safe();
    if (g_failed == 0) { printf("test_dispatch: all checks passed\n"); return 0; }
    fprintf(stderr, "test_dispatch: %d check(s) failed\n", g_failed);
    return 1;
}
