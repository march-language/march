/* test/test_ffi.c — hermetic unit test for the March FFI ABI accessors.
 *
 * march_ffi.c references march_incrc/march_decrc (defined in march_runtime.c).
 * We stub them here with call counters so the test stays self-contained and
 * can also assert that dup/drop touch the refcount ONLY for heap values. */
#include "../runtime/march_ffi.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int inc_calls = 0;
static int dec_calls = 0;
void march_incrc(void *p) { (void)p; inc_calls++; }
void march_decrc(void *p) { (void)p; dec_calls++; }

/* Build a heap value with the march_string layout {rc;tag;pad;len;data[]} so
 * we can exercise march_str_borrow without linking the whole runtime. */
static march_value make_test_string(const char *s) {
    size_t len = strlen(s);
    /* 24-byte header (rc:8, tag:4, pad:4, len:8) + data */
    char *buf = malloc(24 + len);
    *(int64_t *)(buf + 0)  = 1;        /* rc  */
    *(int32_t *)(buf + 8)  = -1;       /* tag = MARCH_STRING_TAG */
    *(int32_t *)(buf + 12) = 0;        /* pad */
    *(int64_t *)(buf + 16) = (int64_t)len;
    memcpy(buf + 24, s, len);
    return march_from_ptr(buf);
}

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

    /* string borrow: ptr + length view into march_string data */
    march_value s = make_test_string("the quick brown fox");
    march_slice sl = march_str_borrow(s);
    assert(sl.len == 19);
    assert(memcmp(sl.ptr, "the quick brown fox", 19) == 0);
    /* borrowing must not touch the refcount */
    inc_calls = dec_calls = 0;
    (void)march_str_borrow(s);
    assert(inc_calls == 0 && dec_calls == 0);
    free(march_as_ptr(s));

    /* embedded NUL: length-based borrow keeps both halves (strlen would stop at NUL) */
    {
        char *buf = malloc(24 + 3);
        *(int64_t *)(buf + 0) = 1; *(int32_t *)(buf + 8) = -1;
        *(int32_t *)(buf + 12) = 0; *(int64_t *)(buf + 16) = 3;
        buf[24] = 'a'; buf[25] = '\0'; buf[26] = 'b';
        march_slice e = march_str_borrow(march_from_ptr(buf));
        assert(e.len == 3 && e.ptr[0] == 'a' && e.ptr[1] == '\0' && e.ptr[2] == 'b');
        free(buf);
    }

    /* UTF-8 validation */
    assert(march_utf8_valid((const uint8_t *)"hello", 5));
    assert(march_utf8_valid((const uint8_t *)"caf\xC3\xA9", 5));        /* café */
    assert(march_utf8_valid((const uint8_t *)"\xF0\x9F\x98\x80", 4));   /* 😀 */
    assert(!march_utf8_valid((const uint8_t *)"\xFF", 1));              /* invalid lead */
    assert(!march_utf8_valid((const uint8_t *)"\xC3", 1));              /* truncated */
    assert(!march_utf8_valid((const uint8_t *)"\xC0\xAF", 2));          /* overlong */
    assert(!march_utf8_valid((const uint8_t *)"\xED\xA0\x80", 3));      /* surrogate */

    printf("test_ffi: OK\n");
    return 0;
}
