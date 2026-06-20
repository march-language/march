/* runtime/march_ffi.c — implementation of the March FFI ABI (march_ffi.h). */
#include "march_ffi.h"
#include "march_runtime.h"  /* march_incrc / march_decrc */
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

int32_t march_ffi_abi_version(void) { return MARCH_FFI_ABI_VERSION; }

void march_fatal(const char *msg) {
    fprintf(stderr, "march: FFI fatal: %s\n", msg ? msg : "(null)");
    abort();
}

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

/* ── String/Bytes constructors ───────────────────────────────────────────── */
march_value march_str_new(const uint8_t *utf8, size_t len) {
    march_string *s = (march_string *)march_string_alloc((int64_t)len);
    if (len) memcpy(s->data, utf8, len);
    return march_from_ptr(s);
}
march_value march_bytes_new(const uint8_t *data, size_t len) {
    return march_str_new(data, len);
}

/* ── Option / Result constructors ────────────────────────────────────────────
 * ADT cell = 16-byte header {rc;tag;pad} + 8-byte fields at offset 16.
 * march_alloc sets rc=1, tag=0; we overwrite tag and (for 1-field cells) field0. */
static march_value mk_cell1(int32_t tag, march_value field0) {
    void *p = march_alloc(24);
    ((march_hdr *)p)->tag = tag;
    ((int64_t *)p)[2] = field0;          /* field0 at byte offset 16 */
    return march_from_ptr(p);
}
/* Option uses the compiler's NICHE representation for niche-eligible payloads
 * (Int/Bool/String/Bytes and any heap type): None = 0, Some(x) = x — no heap
 * cell.  This matches make_some/make_none in march_extras.c.  (Option(Float)
 * and Option(Unit) stay boxed in the compiler and are NOT supported by these
 * bare constructors yet — they would need the kind-aware boxed path.)
 *
 * Result is NOT niche-shaped (two single-field constructors), so it stays a
 * boxed cell: Ok=tag 0, Err=tag 1, payload at offset 16. */
march_value march_none(void)          { return 0; }
march_value march_some(march_value v) { return v; }
march_value march_ok(march_value v)   { return mk_cell1(0, v); }
march_value march_err(march_value e)  { return mk_cell1(1, e); }

/* ── Resources ───────────────────────────────────────────────────────────────
 * Type registry: a small fixed table of (name, dtor) indexed by type id.
 * Idempotent registration by name.  Resource cell layout (40 bytes):
 *   [rc@0][tag=MARCH_RESOURCE_TAG@8][pad@12][native_ptr@16][dtor@24][type_id@32]
 * The RC free path (march_run_resource_dtor in march_runtime.c) reads dtor@24
 * and native_ptr@16. */
#define MARCH_FFI_MAX_RESOURCE_TYPES 256
static const char    *res_type_names[MARCH_FFI_MAX_RESOURCE_TYPES];
static march_destructor res_type_dtors[MARCH_FFI_MAX_RESOURCE_TYPES];
static int32_t          res_type_count = 0;

int32_t march_resource_type(const char *name, march_destructor dtor) {
    for (int32_t i = 0; i < res_type_count; i++)
        if (res_type_names[i] && strcmp(res_type_names[i], name) == 0)
            return i;                         /* idempotent: first registration wins */
    if (res_type_count >= MARCH_FFI_MAX_RESOURCE_TYPES) march_fatal("too many FFI resource types");
    int32_t id = res_type_count++;
    res_type_names[id] = name;
    res_type_dtors[id] = dtor;
    return id;
}

march_value march_resource_new(int32_t type_id, void *native_ptr) {
    if (type_id < 0 || type_id >= res_type_count) march_fatal("march_resource_new: bad type id");
    void *p = march_alloc(40);                 /* 16 header + native_ptr + dtor + type_id */
    ((march_hdr *)p)->tag = MARCH_RESOURCE_TAG;
    *(void **)((char *)p + 16) = native_ptr;
    *(march_destructor *)((char *)p + 24) = res_type_dtors[type_id];
    *(int64_t *)((char *)p + 32) = type_id;
    return march_from_ptr(p);
}

void *march_resource_get(march_value v, int32_t type_id) {
    if (!march_is_heap(v)) march_fatal("march_resource_get: not a heap value");
    void *p = march_as_ptr(v);
    if (((march_hdr *)p)->tag != MARCH_RESOURCE_TAG) march_fatal("march_resource_get: not a resource");
    if (*(int64_t *)((char *)p + 32) != type_id) march_fatal("march_resource_get: resource type mismatch");
    return *(void **)((char *)p + 16);
}

march_value march_dup(march_value v) {
    if (march_is_heap(v)) march_incrc(march_as_ptr(v));
    return v;
}
void march_drop(march_value v) {
    if (march_is_heap(v)) march_decrc(march_as_ptr(v));
}

/* Test-only helpers, always linked. Exercise marshalling end to end. */
int64_t ffi_test_dbl(int64_t n) { return n * 2; }

/* Borrows the String (reads its length) and must NOT drop it — the caller
 * retains ownership.  Used by the RC-leak gate: with borrow semantics the
 * caller frees the arg after the call, so a churn loop stays flat. */
int64_t ffi_test_slen(march_value s) { return (int64_t)march_str_borrow(s).len; }

/* Resource example: an incremental accumulator behind an opaque March handle.
 * Exercises register/new/get and destructor-on-drop end to end. */
typedef struct { int64_t acc; } TestAcc;
static void ffi_acc_dtor(void *p) { free(p); }
static int32_t ffi_acc_tid(void) { return march_resource_type("TestAcc", ffi_acc_dtor); }
march_value ffi_acc_new(void)               { TestAcc *a = malloc(sizeof *a); a->acc = 0;
                                              return march_resource_new(ffi_acc_tid(), a); }
int64_t ffi_acc_push(march_value h, int64_t n) { TestAcc *a = march_resource_get(h, ffi_acc_tid());
                                                 a->acc += n; return 0; }
int64_t ffi_acc_total(march_value h)         { return ((TestAcc *)march_resource_get(h, ffi_acc_tid()))->acc; }

/* Owned return: build a fresh copy of the borrowed String (rc=1). */
march_value ffi_test_sdup(march_value s) {
    march_slice v = march_str_borrow(s);
    return march_str_new(v.ptr, v.len);
}

/* Returns Some(n) for n >= 0, else None — exercises Option marshalling
 * end-to-end (must match the compiler's niche representation). */
march_value ffi_test_maybe(int64_t n) {
    return n >= 0 ? march_some(march_make_int(n)) : march_none();
}

/* Fallible: a single ASCII digit → Ok(Int), else Err(String). Result built
 * directly via march_ok/march_err (no env needed). */
march_value ffi_test_parse(march_value s) {
    march_slice v = march_str_borrow(s);
    if (v.len == 1 && v.ptr[0] >= '0' && v.ptr[0] <= '9')
        return march_ok(march_make_int(v.ptr[0] - '0'));
    return march_err(march_str_new((const uint8_t *)"nan", 3));
}
