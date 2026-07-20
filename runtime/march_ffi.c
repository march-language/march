/* runtime/march_ffi.c — implementation of the March FFI ABI (march_ffi.h). */
#include "march_ffi.h"
#include "march_runtime.h"  /* march_incrc / march_decrc */
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdatomic.h>

/* From the scheduler: cooperatively yield the green thread (no-op outside a
 * scheduler context).  Declared here to avoid pulling the whole scheduler API. */
void march_sched_yield(void);

int32_t march_ffi_abi_version(void) { return MARCH_FFI_ABI_VERSION; }

void march_fatal(const char *msg) {
    fprintf(stderr, "march: FFI fatal: %s\n", msg ? msg : "(null)");
    abort();
}

/* Per-call context for `raises` bindings.  Layout MUST match the wrapper the
 * compiler emits (llvm_emit.ml): { i64 raised; i64 err } — raised != 0 means an
 * error was raised; err holds the error march_value.  Allocated (zeroed) by the
 * wrapper on the stack; only `err` is read, and only when `raised`. */
struct march_env { int64_t raised; march_value err; };

void march_raise(march_env *env, march_value e) {
    if (env && !env->raised) { env->raised = 1; env->err = e; }
}

march_value march_make_int(int64_t n)     { return ((march_value)n << 1) | 1; }
int64_t     march_get_int(march_value v)  { return v >> 1; }
march_value march_make_bool(int b)        { return ((march_value)(b ? 1 : 0) << 1) | 1; }
int         march_get_bool(march_value v) { return (int)(v >> 1) != 0; }

/* Float-boxing (Stage 2): a Float carried in a march_value (erased) slot — an
 * Option/Result payload, a generic record/variant field — is now a heap
 * march_float_box (tag -3), NOT raw bitcast bits.  march_make_float BOXES and
 * march_get_float UNBOXES so a Float that the C side stuffs into a generic slot
 * matches how compiled March reads it back (coerce ("ptr","double") =
 * march_unbox_float).  Direct primitive Float args/returns still pass as a bare
 * `double` and never touch these. */
march_value march_make_float(double f) {
    return march_from_ptr(march_alloc_float(f));
}
double march_get_float(march_value v) {
    return march_unbox_float(march_as_ptr(v));
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
/* ── Variants (ADTs) & records ───────────────────────────────────────────────
 * Both are heap cells: [rc][tag@8][pad@12][field0@16][field1@24]…  A variant's
 * `tag` is its constructor index; a record's `pad` is its interned shape id and
 * fields are stored in canonical (name-sorted) order.  Read accessors return a
 * BORROWED field (the cell owns it); the make_* constructors TAKE OWNERSHIP of
 * the field values (they are moved into the new cell, which March later drops). */
int32_t march_record_shape_intern(const char *desc);  /* from march_extras.c */

int32_t     march_variant_tag(march_value v)            { return ((march_hdr *)march_as_ptr(v))->tag; }
march_value march_variant_field(march_value v, int32_t i){ return ((int64_t *)march_as_ptr(v))[2 + i]; }
march_value march_record_field(march_value v, int32_t i) { return ((int64_t *)march_as_ptr(v))[2 + i]; }

march_value march_make_variant(int32_t tag, int32_t nfields, const march_value *fields) {
    void *p = march_alloc(16 + (int64_t)(nfields < 0 ? 0 : nfields) * 8);
    ((march_hdr *)p)->tag = tag;
    for (int32_t i = 0; i < nfields; i++) ((int64_t *)p)[2 + i] = fields[i];
    return march_from_ptr(p);
}

march_value march_make_record(const char *desc, int32_t nfields, const march_value *fields) {
    void *p = march_alloc(16 + (int64_t)(nfields < 0 ? 0 : nfields) * 8);
    ((march_hdr *)p)->pad = march_record_shape_intern(desc);  /* shape id @ offset 12 */
    for (int32_t i = 0; i < nfields; i++) ((int64_t *)p)[2 + i] = fields[i];
    return march_from_ptr(p);
}

/* ── List (Nil | Cons(head, tail)) ──────────────────────────────────────────*/
march_value march_list_nil(void) {
    return march_make_variant(0, 0, (const march_value *)0);
}
march_value march_list_cons(march_value head, march_value tail) {
    march_value f[2] = { head, tail };
    return march_make_variant(1, 2, f);
}
int32_t march_list_length(march_value v) {
    int32_t n = 0;
    while (march_variant_tag(v) == 1) { v = march_variant_field(v, 1); n++; }
    return n;
}
march_value march_list_nth(march_value v, int32_t i) {
    while (i-- > 0) v = march_variant_field(v, 1);
    return march_variant_field(v, 0);
}

march_value march_none(void)          { return 0; }
march_value march_some(march_value v) { return v; }
march_value march_ok(march_value v)   { return mk_cell1(0, v); }
march_value march_err(march_value e)  { return mk_cell1(1, e); }

/* Boxed Some, for Option(Float)/Option(Unit) and any non-niche-eligible payload:
 * the compiler stores these as a heap Some cell (tag 1, payload at offset 16),
 * NOT the niche form, because a 0-bit payload (0.0 / unit) would alias None=0.
 * None stays 0 (march_none) even for these.  For a Float payload pass
 * march_make_float(f); the bits land at offset 16 where March reads them back. */
march_value march_some_boxed(march_value payload) { return mk_cell1(1, payload); }

/* Boxed None, paired with march_some_boxed: when Some is boxed (Float/Unit
 * payloads), the WHOLE Option is matched by reading the cell tag, so None must
 * also be a heap cell (tag 0, no fields) rather than the niche 0. */
march_value march_none_boxed(void) {
    void *p = march_alloc(16);
    ((march_hdr *)p)->tag = 0;
    return march_from_ptr(p);
}

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

/* ── Blocking FFI dispatch (Phase 6) ─────────────────────────────────────────
 * A `blocking` extern is run on a dedicated OS thread while the calling green
 * thread cooperatively yields, so other green threads keep running instead of
 * the whole scheduler worker stalling for the duration of the C call.
 * Fixed-arity GP-register trampolines (Int/ptr args); separate int64/double
 * return shapes — same constraints as the interpreter trampoline. */
static int64_t blk_call_i(void *fn, const int64_t *a, int n) {
    switch (n) {
        case 0: return ((int64_t(*)(void))fn)();
        case 1: return ((int64_t(*)(int64_t))fn)(a[0]);
        case 2: return ((int64_t(*)(int64_t,int64_t))fn)(a[0],a[1]);
        case 3: return ((int64_t(*)(int64_t,int64_t,int64_t))fn)(a[0],a[1],a[2]);
        case 4: return ((int64_t(*)(int64_t,int64_t,int64_t,int64_t))fn)(a[0],a[1],a[2],a[3]);
        case 5: return ((int64_t(*)(int64_t,int64_t,int64_t,int64_t,int64_t))fn)(a[0],a[1],a[2],a[3],a[4]);
        default:return ((int64_t(*)(int64_t,int64_t,int64_t,int64_t,int64_t,int64_t))fn)(a[0],a[1],a[2],a[3],a[4],a[5]);
    }
}
static double blk_call_d(void *fn, const int64_t *a, int n) {
    switch (n) {
        case 0: return ((double(*)(void))fn)();
        case 1: return ((double(*)(int64_t))fn)(a[0]);
        case 2: return ((double(*)(int64_t,int64_t))fn)(a[0],a[1]);
        case 3: return ((double(*)(int64_t,int64_t,int64_t))fn)(a[0],a[1],a[2]);
        case 4: return ((double(*)(int64_t,int64_t,int64_t,int64_t))fn)(a[0],a[1],a[2],a[3]);
        case 5: return ((double(*)(int64_t,int64_t,int64_t,int64_t,int64_t))fn)(a[0],a[1],a[2],a[3],a[4]);
        default:return ((double(*)(int64_t,int64_t,int64_t,int64_t,int64_t,int64_t))fn)(a[0],a[1],a[2],a[3],a[4],a[5]);
    }
}
typedef struct {
    void *fn; const int64_t *args; int n; int is_double;
    int64_t ri; double rd; _Atomic int done;
} march_blk_call;
static void *march_blk_thread(void *p) {
    march_blk_call *b = (march_blk_call *)p;
    if (b->is_double) b->rd = blk_call_d(b->fn, b->args, b->n);
    else              b->ri = blk_call_i(b->fn, b->args, b->n);
    atomic_store_explicit(&b->done, 1, memory_order_release);
    return NULL;
}
static void march_run_blocking(march_blk_call *b) {
    pthread_t t;
    if (pthread_create(&t, NULL, march_blk_thread, b) != 0) {
        /* Can't offload — run inline (still correct, just stalls this worker). */
        march_blk_thread(b);
        return;
    }
    /* Cooperatively yield while the C call runs on the OS thread. */
    while (!atomic_load_explicit(&b->done, memory_order_acquire))
        march_sched_yield();
    pthread_join(t, NULL);
}
int64_t march_run_blocking_i(void *fn, const int64_t *args, int n) {
    march_blk_call b = { fn, args, n, 0, 0, 0.0, 0 };
    march_run_blocking(&b);
    return b.ri;
}
double march_run_blocking_d(void *fn, const int64_t *args, int n) {
    march_blk_call b = { fn, args, n, 1, 0, 0.0, 0 };
    march_run_blocking(&b);
    return b.rd;
}

/* ── Native → March upcalls ───────────────────────────────────────────────────
 * Invoke a March closure value (received as an extern parameter) from a binding.
 * A closure cell holds its apply-fn pointer in field 0 (offset 16); the apply
 * convention is apply(clo, args…).  Args are march_values (build with
 * march_make_int / march_str_new / …); the result is a march_value (read it by
 * the closure's known return type).  Up to 5 args (the closure ptr occupies the
 * 6th GP-register slot).  Borrow semantics: the closure and args are not dropped
 * here — March owns them across the call. */
march_value march_call(march_value closure, int32_t nargs, const march_value *args) {
    void *clo = march_as_ptr(closure);
    void *fn  = *(void **)((char *)clo + 16);   /* field 0 = apply fn ptr */
    if (nargs < 0) nargs = 0;
    if (nargs > 5) march_fatal("march_call: too many arguments (max 5)");
    int64_t a[6];
    a[0] = (int64_t)(intptr_t)clo;              /* apply(clo, args…) */
    for (int32_t i = 0; i < nargs; i++) a[1 + i] = (int64_t)args[i];
    return (march_value)blk_call_i(fn, a, nargs + 1);
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
/* CONSUMES h: reads the total, then drops the resource itself (the binding owns
 * it).  Must be declared `consume h` so March does NOT also drop it. */
int64_t ffi_acc_finish(march_value h) {
    int64_t total = ((TestAcc *)march_resource_get(h, ffi_acc_tid()))->acc;
    march_drop(h);
    return total;
}

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

/* Variant round-trip: build a Shape (Circle(r)=tag 0 | Rect(w,h)=tag 1) and
 * read one back (area). Slots hold March's NATIVE per-field representation —
 * a concrete Int field is a RAW machine int, not a tagged value word. */
march_value ffi_test_mk_circle(int64_t r) {
    march_value f[1] = { r };                    /* raw Int slot */
    return march_make_variant(0, 1, f);
}
march_value ffi_test_mk_rect(int64_t w, int64_t h) {
    march_value f[2] = { w, h };                 /* raw Int slots */
    return march_make_variant(1, 2, f);
}
int64_t ffi_test_shape_area(march_value s) {
    switch (march_variant_tag(s)) {
        case 0: { int64_t r = march_variant_field(s, 0); return 3 * r * r; }
        default: { int64_t w = march_variant_field(s, 0);
                   int64_t h = march_variant_field(s, 1); return w * h; }
    }
}

/* Record round-trip: build a Point {x,y} and read its fields back (raw Ints). */
march_value ffi_test_mk_point(int64_t x, int64_t y) {
    march_value f[2] = { x, y };                 /* sorted: x, y (raw Int slots) */
    return march_make_record("x:i;y:i;", 2, f);
}
int64_t ffi_test_point_sum(march_value p) {
    return march_record_field(p, 0) + march_record_field(p, 1);
}

/* Fallible: a single ASCII digit → Ok(Int), else Err(String). Result built
 * directly via march_ok/march_err (no env needed). */
march_value ffi_test_parse(march_value s) {
    march_slice v = march_str_borrow(s);
    if (v.len == 1 && v.ptr[0] >= '0' && v.ptr[0] <= '9')
        return march_ok(march_make_int(v.ptr[0] - '0'));
    return march_err(march_str_new((const uint8_t *)"nan", 3));
}

/* `raises` variant: returns the bare Ok payload (Int) on success and raises an
 * Err(String) out-of-band via march_env — the compiler wraps it into Ok/Err. */
int64_t ffi_raise_parse(march_env *env, march_value s) {
    march_slice v = march_str_borrow(s);
    if (v.len == 1 && v.ptr[0] >= '0' && v.ptr[0] <= '9')
        return v.ptr[0] - '0';                  /* bare Int Ok payload */
    march_raise(env, march_str_new((const uint8_t *)"bad int", 7));
    return 0;
}

/* `raises` with a Float Ok payload: a / b, or raise on b == 0. The bare return
 * is a double; the wrapper boxes it into Ok via march_make_float. */
double ffi_raise_fdiv(march_env *env, double a, double b) {
    if (b == 0.0) {
        march_raise(env, march_str_new((const uint8_t *)"div by zero", 11));
        return 0.0;
    }
    return a / b;
}

/* Option(Float): Some(x/2) for x >= 0, else None. Uses the boxed-Some path
 * (a Float payload can't use the niche form). */
march_value ffi_maybe_half(double x) {
    if (x < 0.0) return march_none_boxed();
    return march_some_boxed(march_make_float(x / 2.0));
}

/* Option(Unit): Some(()) when flag != 0, else None — Unit is also non-niche, so
 * BOTH arms must be boxed (like ffi_maybe_half): the compiler represents
 * Option(Unit) as a heap cell (None=tag 0, Some=tag 1) and its match reads the
 * cell tag, so a raw niche None (0) would be dereferenced as a null cell and
 * segfault. Pair march_some_boxed with march_none_boxed, never march_none. */
march_value ffi_maybe_unit(int64_t flag) {
    return flag ? march_some_boxed(0) : march_none_boxed();
}

/* Upcall: apply a March closure f : (Int) -> Int to x, return f(x).
 * Args are in NATIVE slot rep (Int = raw machine int, NOT march_make_int); the
 * result is the GENERIC tagged word (read Int with march_get_int). */
int64_t ffi_apply1(march_value f, int64_t x) {
    march_value arg = (march_value)x;                 /* raw Int slot */
    return march_get_int(march_call(f, 1, &arg));     /* tagged Int result */
}

/* Upcall: count how many of [1..n] satisfy a March predicate (Int) -> Bool. */
int64_t ffi_count_matching(march_value pred, int64_t n) {
    int64_t count = 0;
    for (int64_t i = 1; i <= n; i++) {
        march_value arg = (march_value)i;             /* raw Int slot */
        if (march_get_bool(march_call(pred, 1, &arg))) count++;
    }
    return count;
}
