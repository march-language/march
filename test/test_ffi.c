/* test/test_ffi.c — hermetic unit test for the March FFI ABI accessors.
 *
 * march_ffi.c references march_incrc/march_decrc (defined in march_runtime.c).
 * We stub them here with call counters so the test stays self-contained and
 * can also assert that dup/drop touch the refcount ONLY for heap values. */
#include "../runtime/march_ffi.h"
#include <assert.h>
#include <stdio.h>

static int inc_calls = 0;
static int dec_calls = 0;
void march_incrc(void *p) { (void)p; inc_calls++; }
void march_decrc(void *p) { (void)p; dec_calls++; }

int main(void) {
    /* version handshake */
    assert(march_ffi_abi_version() == MARCH_FFI_ABI_VERSION);

    /* int tag layout (1 -> 3, 2 -> 5 — matches the codegen convention) */
    assert(march_make_int(1) == 3);
    assert(march_make_int(2) == 5);
    assert(march_get_int(march_make_int(42)) == 42);
    assert(march_get_int(march_make_int(-7)) == -7);
    assert(march_get_int(march_make_int(0)) == 0);

    /* bool */
    assert(march_get_bool(march_make_bool(1)) == 1);
    assert(march_get_bool(march_make_bool(0)) == 0);

    /* float bitcast round-trip (untagged) */
    double f = 3.14159265358979;
    assert(march_get_float(march_make_float(f)) == f);
    assert(march_get_float(march_make_float(-0.0)) == -0.0);

    /* heap detection */
    assert(!march_is_heap(march_make_int(5)));
    assert(!march_is_heap(march_from_ptr(NULL)));
    int dummy;
    march_value hv = march_from_ptr(&dummy);
    assert(march_is_heap(hv));
    assert(march_as_ptr(hv) == &dummy);

    /* dup/drop: no-op on tagged ints, refcount op on heap values */
    inc_calls = dec_calls = 0;
    march_value ti = march_make_int(9);
    assert(march_dup(ti) == ti);   /* returns the value unchanged */
    march_drop(ti);
    assert(inc_calls == 0 && dec_calls == 0);  /* tagged: never touched RC */

    assert(march_dup(hv) == hv);
    march_drop(hv);
    assert(inc_calls == 1 && dec_calls == 1);  /* heap: exactly one each */

    printf("test_ffi: OK\n");
    return 0;
}
