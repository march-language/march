/* test/test_ffi.c — unit test for the March FFI ABI accessors and constructors.
 * Links the real runtime (march_runtime.c + deps) so march_alloc / RC / the
 * live-allocation gauge are the genuine implementations. */
#include "../runtime/march_ffi.h"
#include "../runtime/march_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/* Resource destructor for the resources test: frees the native allocation and
 * records that it ran (so the test can assert dtor-on-drop). */
static int res_dtor_calls = 0;
static void test_res_dtor(void *p) { res_dtor_calls++; free(p); }

/* march_make_record interns a shape via march_record_shape_intern (defined in
 * march_extras.c). This test now links march_extras.c for real (the named
 * registry, Task 3, made march_runtime.c itself depend on march_extras.c's
 * Vault C API, so every test rule linking march_runtime.c must link
 * march_extras.c too) — no local stub needed any more; the real
 * implementation runs, and its id is only stored in the header pad word,
 * still not exercised by this test. */


/* ── multi-threaded live-gauge harness ────────────────────────────────────
 * The gauge is a process-wide net count, but allocation and freeing are not
 * thread-affine: an object allocated on one scheduler thread is routinely
 * freed on another, and the threads that did the allocating may have exited
 * by the time the gauge is read.  A per-thread counter implementation is only
 * correct if (a) it sums across all live threads and (b) an exiting thread
 * folds its residual into a process-wide total instead of dropping it.
 *
 * MT_THREADS allocator threads each allocate MT_PER_THREAD objects into their
 * own slot of mt_cells and then EXIT.  A second, disjoint set of threads then
 * frees them, each freeing a slot it did not allocate (rotate by one), so
 * every participating thread ends with a non-zero net count of its own — one
 * positive, one negative — and only the sum is meaningful. */
#define MT_THREADS    8
#define MT_PER_THREAD 512
static void *mt_cells[MT_THREADS][MT_PER_THREAD];

static void *mt_alloc_thread(void *arg) {
    long id = (long)arg;
    for (int i = 0; i < MT_PER_THREAD; i++) mt_cells[id][i] = march_alloc(16);
    return NULL;
}

static void *mt_free_thread(void *arg) {
    long id = (long)arg;                       /* frees the PREVIOUS slot */
    long src = (id + MT_THREADS - 1) % MT_THREADS;
    for (int i = 0; i < MT_PER_THREAD; i++)
        march_drop(march_from_ptr(mt_cells[src][i]));
    return NULL;
}

static void mt_run(void *(*fn)(void *)) {
    pthread_t th[MT_THREADS];
    for (long i = 0; i < MT_THREADS; i++) pthread_create(&th[i], NULL, fn, (void *)i);
    for (int i = 0; i < MT_THREADS; i++) pthread_join(th[i], NULL);
}

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
        /* Option uses the niche representation: Some(x) = x, None = 0. */
        assert(march_some(march_make_int(7)) == march_make_int(7));
        assert(march_none() == 0);

        /* Result stays boxed: Ok = tag 0, Err = tag 1, payload at offset 16. */
        march_value ok = march_ok(march_make_int(1));
        assert(((int32_t *)march_as_ptr(ok))[2] == 0);     /* Ok tag */
        march_drop(ok);

        march_value err = march_err(march_make_int(2));
        assert(((int32_t *)march_as_ptr(err))[2] == 1);    /* Err tag */
        march_drop(err);

        /* Boxed Some/None (for Float/Unit Options): Some = heap cell tag 1 with
         * the payload at offset 16; None = heap cell tag 0. */
        march_value sb = march_some_boxed(march_make_float(4.5));
        assert(march_variant_tag(sb) == 1);
        assert(march_get_float(march_variant_field(sb, 0)) == 4.5);
        march_drop(sb);

        march_value nb = march_none_boxed();
        assert(march_is_heap(nb) && march_variant_tag(nb) == 0);
        march_drop(nb);
    }

    /* ── resources: opaque native handle with destructor on drop ───────── */
    {
        int32_t tid = march_resource_type("TestRes", test_res_dtor);
        assert(tid >= 0);
        assert(march_resource_type("TestRes", test_res_dtor) == tid);  /* idempotent */

        long *native = malloc(sizeof(long));
        *native = 99;
        int64_t base = march_live_allocs();
        march_value r = march_resource_new(tid, native);
        assert(march_live_allocs() == base + 1);      /* the resource cell is counted */
        assert(march_is_heap(r));
        assert(march_resource_get(r, tid) == native); /* borrow native ptr back */
        assert(*(long *)march_resource_get(r, tid) == 99);

        res_dtor_calls = 0;
        march_drop(r);                                /* rc 1->0: dtor runs, cell freed */
        assert(res_dtor_calls == 1);                  /* destructor ran exactly once */
        assert(march_live_allocs() == base);          /* cell freed (native freed by dtor) */
    }

    /* ── variants (ADTs) & records: make + read round-trip ─────────────────
     * Slots store March's native per-field word verbatim (raw Int here), so the
     * round-trip is word-for-word: deposit N, read N back. */
    {
        march_value fs[2] = { 7, 8 };
        march_value v = march_make_variant(2, 2, fs);   /* ctor tag 2, two fields */
        assert(march_variant_tag(v) == 2);
        assert(march_variant_field(v, 0) == 7);
        assert(march_variant_field(v, 1) == 8);
        march_drop(v);

        march_value v0 = march_make_variant(5, 0, NULL); /* nullary ctor */
        assert(march_variant_tag(v0) == 5);
        march_drop(v0);

        march_value rf[2] = { 3, 4 };
        march_value r = march_make_record("x:i;y:i;", 2, rf);
        assert(march_record_field(r, 0) == 3);
        assert(march_record_field(r, 1) == 4);
        march_drop(r);
    }

    /* ── blocking dispatch runs the call on an OS thread, returns result ── */
    {
        extern int64_t ffi_test_dbl(int64_t);
        int64_t a1[1] = { 21 };
        assert(march_run_blocking_i((void *)ffi_test_dbl, a1, 1) == 42);
        int64_t a0[1] = { 0 };
        assert(march_run_blocking_i((void *)march_live_allocs, a0, 0)
               == march_live_allocs());  /* 0-arg blocking call */
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

    /* ── leak gauge sums across threads, including exited ones ────────── */
    {
        int64_t base = march_live_allocs();
        mt_run(mt_alloc_thread);   /* allocating threads exit before the read */
        assert(march_live_allocs() == base + (int64_t)MT_THREADS * MT_PER_THREAD);
        mt_run(mt_free_thread);    /* each frees another thread's objects */
        assert(march_live_allocs() == base);
    }

    printf("test_ffi: OK\n");
    return 0;
}
