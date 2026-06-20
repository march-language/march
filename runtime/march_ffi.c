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

/* String/Bytes share the march_string layout {rc;tag;pad;len;data[]}. */
march_slice march_str_borrow(march_value s) {
    march_string *str = (march_string *)march_as_ptr(s);
    march_slice out = { (const uint8_t *)str->data, (size_t)str->len };
    return out;
}
march_slice march_bytes_borrow(march_value b) { return march_str_borrow(b); }

int march_utf8_valid(const uint8_t *p, size_t len) {
    size_t i = 0;
    while (i < len) {
        uint8_t c = p[i];
        size_t n;          /* number of continuation bytes */
        uint32_t cp;       /* accumulated code point, for range checks */
        if (c < 0x80)            { i += 1; continue; }
        else if ((c & 0xE0) == 0xC0) { n = 1; cp = c & 0x1F; }
        else if ((c & 0xF0) == 0xE0) { n = 2; cp = c & 0x0F; }
        else if ((c & 0xF8) == 0xF0) { n = 3; cp = c & 0x07; }
        else return 0;                       /* invalid leading byte */
        if (i + n >= len) return 0;          /* truncated: not enough continuation bytes */
        for (size_t k = 1; k <= n; k++) {
            uint8_t cc = p[i + k];
            if ((cc & 0xC0) != 0x80) return 0;  /* bad continuation */
            cp = (cp << 6) | (cc & 0x3F);
        }
        /* reject overlong encodings and out-of-range/surrogate code points */
        if (n == 1 && cp < 0x80) return 0;
        if (n == 2 && cp < 0x800) return 0;
        if (n == 3 && cp < 0x10000) return 0;
        if (cp > 0x10FFFF) return 0;
        if (cp >= 0xD800 && cp <= 0xDFFF) return 0;
        i += n + 1;
    }
    return 1;
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
