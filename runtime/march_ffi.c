/* runtime/march_ffi.c — implementation of the March FFI ABI (march_ffi.h). */
#include "march_ffi.h"
#include "march_runtime.h"  /* march_incrc / march_decrc */
#include <string.h>

int32_t march_ffi_abi_version(void) { return MARCH_FFI_ABI_VERSION; }

march_value march_make_int(int64_t n)     { return ((march_value)n << 1) | 1; }
int64_t     march_get_int(march_value v)  { return v >> 1; }
march_value march_make_bool(int b)        { return ((march_value)(b ? 1 : 0) << 1) | 1; }
int         march_get_bool(march_value v) { return (int)(v >> 1) != 0; }

march_value march_make_float(double f) {
    march_value w;
    memcpy(&w, &f, sizeof w);
    return w;
}
double march_get_float(march_value v) {
    double f;
    memcpy(&f, &v, sizeof f);
    return f;
}

int         march_is_heap(march_value v)  { return v != 0 && (v & 1) == 0; }
void       *march_as_ptr(march_value v)   { return (void *)(intptr_t)v; }
march_value march_from_ptr(void *p)       { return (march_value)(intptr_t)p; }

march_value march_dup(march_value v) {
    if (march_is_heap(v)) march_incrc(march_as_ptr(v));
    return v;
}
void march_drop(march_value v) {
    if (march_is_heap(v)) march_decrc(march_as_ptr(v));
}

/* Test-only helper, always linked. Bound from March via `fn dbl(n: Int): Int
 * = "ffi_test_dbl"` to exercise primitive marshalling end to end. */
int64_t ffi_test_dbl(int64_t n) { return n * 2; }
