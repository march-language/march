/* test_float_box.c — boxed-Float runtime API (float-boxing design, stage 1).
 *
 * Exercises the additive box API that stage 2 will emit into erased slots:
 * round-trip, value-equality of distinct boxes, and — the load-bearing case —
 * that march_poly_compare orders NEGATIVE floats correctly. Raw IEEE-754 bits
 * in an erased slot integer-compare backwards for negatives (a hardened
 * IS_HEAP_PTR stops the crash but leaves this wrong: -1.25 sorted before
 * -9.0), so a box + value-aware compare is the only fix — this test pins it.
 */
#include "../runtime/march_runtime.h"
#include <stdio.h>
#include <string.h>

static int g_failed = 0;

#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

static void test_roundtrip(void) {
    double xs[] = { 0.0, 3.5, -1.25, -9.0, 1e300, -1e-300 };
    for (unsigned i = 0; i < sizeof(xs)/sizeof(xs[0]); i++) {
        void *b = march_alloc_float(xs[i]);
        CHECK(b != NULL, "alloc returned NULL");
        CHECK(((march_float_box *)b)->tag == MARCH_FLOAT_TAG, "wrong tag");
        CHECK(march_unbox_float(b) == xs[i], "unbox != original");
        /* Boxes are heap ptrs (even, non-null) — RC-safe, unlike raw bits. */
        CHECK(((uintptr_t)b & 1u) == 0, "box is not a heap ptr (odd)");
    }
}

static void test_poly_eq_by_value(void) {
    void *a = march_alloc_float(3.5);
    void *b = march_alloc_float(3.5);   /* distinct box, same value */
    void *c = march_alloc_float(3.6);
    CHECK(a != b, "boxes should be distinct pointers");
    CHECK(march_poly_eq(a, b) == 1, "equal-valued boxes must be poly_eq");
    CHECK(march_poly_eq(a, c) == 0, "unequal-valued boxes must not be poly_eq");
    CHECK(march_poly_eq(a, a) == 1, "identity");
}

static void test_poly_compare_negatives(void) {
    /* The exact case a hardened IS_HEAP_PTR cannot fix. Ascending order of
     * [3.5, -1.25, 2.75, 0.5, -9.0, 4.5] puts -9.0 first: -9.0 < -1.25. */
    void *n9   = march_alloc_float(-9.0);
    void *n125 = march_alloc_float(-1.25);
    void *p35  = march_alloc_float(3.5);
    CHECK(march_poly_compare(n9, n125) == -1, "-9.0 must compare LESS than -1.25");
    CHECK(march_poly_compare(n125, n9) == 1,  "-1.25 must compare GREATER than -9.0");
    CHECK(march_poly_compare(n9, n9)   == 0,  "reflexive");
    CHECK(march_poly_compare(n125, p35) == -1, "-1.25 < 3.5");
}

static void test_poly_compare_tagged_ints(void) {
    /* Tagged int immediates: (n<<1)|1. poly_compare untags and int-compares. */
    void *five = (void *)(uintptr_t)((5 << 1) | 1);
    void *two  = (void *)(uintptr_t)((2 << 1) | 1);
    CHECK(march_poly_compare(two, five) == -1, "2 < 5 tagged");
    CHECK(march_poly_compare(five, two) == 1,  "5 > 2 tagged");
    CHECK(march_poly_compare(five, five) == 0, "reflexive tagged");
}

static void test_value_to_string(void) {
    void *b = march_alloc_float(4.5);
    void *s = march_value_to_string(b);   /* must render the value, not #<tag:-3> */
    march_string *ms = (march_string *)s;
    CHECK(ms->len >= 3, "float box should render a numeric string");
    CHECK(ms->data[0] == '4', "expected 4.5 to start with '4'");
    CHECK(strchr(ms->data, '#') == NULL, "must not render #<tag:...>");
}

int main(void) {
    printf("test_float_box:\n");
    test_roundtrip();
    test_poly_eq_by_value();
    test_poly_compare_negatives();
    test_poly_compare_tagged_ints();
    test_value_to_string();
    if (g_failed) { printf("  %d check(s) FAILED\n", g_failed); return 1; }
    printf("  all checks passed\n");
    return 0;
}
