/* test/test_ffi.c — unit test for the March FFI ABI accessors and constructors.
 * Links the real runtime (march_runtime.c + deps) so march_alloc / RC / the
 * live-allocation gauge are the genuine implementations. */
#include "../runtime/march_ffi.h"
#include "../runtime/march_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    /* ── version handshake ─────────────────────────────────────────────── */
    assert(march_ffi_abi_version() == MARCH_FFI_ABI_VERSION);

    /* ── primitives ────────────────────────────────────────────────────── */
    assert(march_make_int(1) == 3);            /* (1<<1)|1 */
    assert(march_make_int(2) == 5);
    assert(march_get_int(march_make_int(42)) == 42);
    assert(march_get_int(march_make_int(-7)) == -7);
    assert(march_get_bool(march_make_bool(1)) == 1);
    assert(march_get_bool(march_make_bool(0)) == 0);
    double f = 3.14159265358979;
    assert(march_get_float(march_make_float(f)) == f);
    assert(march_get_float(march_make_float(-0.0)) == -0.0);

    /* ── heap detection ────────────────────────────────────────────────── */
    assert(!march_is_heap(march_make_int(5)));
    assert(!march_is_heap(march_from_ptr(NULL)));

    /* ── dup/drop via the real live-allocation gauge ───────────────────── */
    {
        int64_t base = march_live_allocs();
        void *p = march_alloc(16);              /* rc=1, count +1 */
        assert(march_live_allocs() == base + 1);
        march_value v = march_from_ptr(p);
        assert(march_is_heap(v));
        march_dup(v);                           /* rc 1->2 */
        march_drop(v);                          /* rc 2->1, not freed */
        assert(march_live_allocs() == base + 1);
        march_drop(v);                          /* rc 1->0, freed, count -1 */
        assert(march_live_allocs() == base);
        /* dup/drop are no-ops on tagged ints */
        march_drop(march_make_int(9));
        assert(march_live_allocs() == base);
    }

    /* ── string borrow + construct ─────────────────────────────────────── */
    {
        march_value s = march_str_new((const uint8_t *)"the quick brown fox", 19);
        march_slice sl = march_str_borrow(s);
        assert(sl.len == 19 && memcmp(sl.ptr, "the quick brown fox", 19) == 0);
        int64_t *hdr = (int64_t *)march_as_ptr(s);
        assert(hdr[0] == 1);                     /* rc */
        assert(((int32_t *)hdr)[2] == -1);       /* MARCH_STRING_TAG */
        march_drop(s);
    }
    /* embedded NUL survives length-based borrow */
    {
        const uint8_t raw[3] = { 'a', 0, 'b' };
        march_value s = march_bytes_new(raw, 3);
        march_slice e = march_bytes_borrow(s);
        assert(e.len == 3 && e.ptr[0] == 'a' && e.ptr[1] == 0 && e.ptr[2] == 'b');
        march_drop(s);
    }

    /* ── UTF-8 validation ──────────────────────────────────────────────── */
    assert(march_utf8_valid((const uint8_t *)"hello", 5));
    assert(march_utf8_valid((const uint8_t *)"caf\xC3\xA9", 5));        /* café */
    assert(march_utf8_valid((const uint8_t *)"\xF0\x9F\x98\x80", 4));   /* 😀 */
    assert(!march_utf8_valid((const uint8_t *)"\xFF", 1));              /* invalid lead */
    assert(!march_utf8_valid((const uint8_t *)"\xC3", 1));              /* truncated */
    assert(!march_utf8_valid((const uint8_t *)"\xC0\xAF", 2));          /* overlong */
    assert(!march_utf8_valid((const uint8_t *)"\xED\xA0\x80", 3));      /* surrogate */

    /* ── Option / Result constructors ──────────────────────────────────── */
    {
        march_value some = march_some(march_make_int(7));
        assert(((int32_t *)march_as_ptr(some))[2] == 1);   /* Some tag */
        assert(((int64_t *)march_as_ptr(some))[2] == march_make_int(7));
        march_drop(some);

        march_value none = march_none();
        assert(((int32_t *)march_as_ptr(none))[2] == 0);   /* None tag */
        march_drop(none);

        march_value ok = march_ok(march_make_int(1));
        assert(((int32_t *)march_as_ptr(ok))[2] == 0);     /* Ok tag */
        march_drop(ok);

        march_value err = march_err(march_make_int(2));
        assert(((int32_t *)march_as_ptr(err))[2] == 1);    /* Err tag */
        march_drop(err);
    }

    /* ── leak gauge balances across constructor churn ──────────────────── */
    {
        int64_t base = march_live_allocs();
        for (int i = 0; i < 1000; i++) {
            march_value s = march_str_new((const uint8_t *)"x", 1);
            march_drop(s);
            march_value o = march_some(march_make_int(i));
            march_drop(o);
        }
        assert(march_live_allocs() == base);   /* no leak */
    }

    printf("test_ffi: OK\n");
    return 0;
}
