/* lib/eval/ffi_marshal.c — interpreter ↔ march_value bridge.
 *
 * Resolves march_* functions from the dlopened runtime (via RTLD_DEFAULT,
 * which finds them after _ffi_get_handle() has loaded the runtime .so with
 * RTLD_GLOBAL) and exposes them as OCaml externals for eval.ml's marshal layer.
 *
 * All heap-allocating functions (str_new, make_variant, …) go through the
 * runtime's reference-counted allocator.  Scalar ops (make_int, make_float,
 * none, some) are implemented inline — their formulas are stable ABI and need
 * no dlsym.
 *
 * For `raises` externs the interpreter allocates a C-heap sentinel whose
 * layout matches struct march_env { int64_t raised; int64_t err; }.
 */
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <stdint.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

/* march_slice mirrors the runtime's struct { const uint8_t *ptr; size_t len; } */
typedef struct { const uint8_t *ptr; size_t len; } ffi_slice;

/* ── Function pointer cache ─────────────────────────────────────────────── */
static int64_t (*p_str_new)(const uint8_t *, size_t)              = NULL;
static int64_t (*p_bytes_new)(const uint8_t *, size_t)            = NULL;
static ffi_slice (*p_str_borrow)(int64_t)                         = NULL;
static ffi_slice (*p_bytes_borrow)(int64_t)                       = NULL;
static int64_t (*p_none_boxed)(void)                              = NULL;
static int64_t (*p_some_boxed)(int64_t)                           = NULL;
static int64_t (*p_ok)(int64_t)                                   = NULL;
static int64_t (*p_err)(int64_t)                                  = NULL;
static int32_t (*p_variant_tag)(int64_t)                          = NULL;
static int64_t (*p_variant_field)(int64_t, int32_t)               = NULL;
static int64_t (*p_make_variant)(int32_t, int32_t, const int64_t*) = NULL;
static int64_t (*p_record_field)(int64_t, int32_t)                = NULL;
static int64_t (*p_make_record)(const char *, int32_t, const int64_t*) = NULL;
static int64_t (*p_dup)(int64_t)                                  = NULL;
static void    (*p_drop)(int64_t)                                 = NULL;
static int     (*p_is_heap)(int64_t)                              = NULL;

static int g_initialized = 0;

#define RESOLVE(var, name) do { \
    var = dlsym(RTLD_DEFAULT, name); \
    if (!var) caml_failwith("march FFI marshal: " name " not found — runtime not loaded"); \
} while(0)

static void lazy_init(void) {
    if (g_initialized) return;
    RESOLVE(p_str_new,       "march_str_new");
    RESOLVE(p_bytes_new,     "march_bytes_new");
    RESOLVE(p_str_borrow,    "march_str_borrow");
    RESOLVE(p_bytes_borrow,  "march_bytes_borrow");
    RESOLVE(p_none_boxed,    "march_none_boxed");
    RESOLVE(p_some_boxed,    "march_some_boxed");
    RESOLVE(p_ok,            "march_ok");
    RESOLVE(p_err,           "march_err");
    RESOLVE(p_variant_tag,   "march_variant_tag");
    RESOLVE(p_variant_field, "march_variant_field");
    RESOLVE(p_make_variant,  "march_make_variant");
    RESOLVE(p_record_field,  "march_record_field");
    RESOLVE(p_make_record,   "march_make_record");
    RESOLVE(p_dup,           "march_dup");
    RESOLVE(p_drop,          "march_drop");
    RESOLVE(p_is_heap,       "march_is_heap");
    g_initialized = 1;
}

/* Reset the pointer cache (called when a new runtime .so is loaded). */
CAMLprim value march_ffi_marshal_reset(value unit) {
    CAMLparam1(unit);
    g_initialized = 0;
    CAMLreturn(Val_unit);
}

/* ── Inline scalar implementations (stable ABI, no dlsym) ───────────────── */

/* Int/Bool: tagged word (n<<1)|1 */
CAMLprim value march_ffi_make_int(value n_v) {
    CAMLparam1(n_v);
    int64_t n = Int64_val(n_v);
    CAMLreturn(caml_copy_int64((n << 1) | 1));
}
CAMLprim value march_ffi_get_int(value v_v) {
    CAMLparam1(v_v);
    int64_t v = Int64_val(v_v);
    CAMLreturn(caml_copy_int64(v >> 1));  /* arithmetic shift */
}

/* Float: bitcast double ↔ int64 */
CAMLprim value march_ffi_make_float(value f_v) {
    CAMLparam1(f_v);
    double f = Double_val(f_v);
    int64_t bits; memcpy(&bits, &f, 8);
    CAMLreturn(caml_copy_int64(bits));
}
CAMLprim value march_ffi_get_float(value v_v) {
    CAMLparam1(v_v);
    int64_t bits = Int64_val(v_v);
    double f; memcpy(&f, &bits, 8);
    CAMLreturn(caml_copy_double(f));
}

/* None (niche): 0 */
CAMLprim value march_ffi_none(value unit) {
    CAMLparam1(unit);
    CAMLreturn(caml_copy_int64(0));
}
/* Some (niche): identity — Some(x) = x */
CAMLprim value march_ffi_some(value v_v) {
    CAMLparam1(v_v);
    CAMLreturn(v_v);  /* int64 → int64 identity */
}

/* Heap pointer: (v & 1) == 0 && v != 0 */
CAMLprim value march_ffi_is_heap_inline(value v_v) {
    CAMLparam1(v_v);
    int64_t v = Int64_val(v_v);
    CAMLreturn(Val_bool(v != 0 && (v & 1) == 0));
}

/* ── Heap operations (require dlopened runtime) ──────────────────────────── */

CAMLprim value march_ffi_str_new(value s_v) {
    CAMLparam1(s_v);
    lazy_init();
    int64_t r = p_str_new((const uint8_t *)String_val(s_v), caml_string_length(s_v));
    CAMLreturn(caml_copy_int64(r));
}

CAMLprim value march_ffi_bytes_new(value s_v) {
    CAMLparam1(s_v);
    lazy_init();
    int64_t r = p_bytes_new((const uint8_t *)String_val(s_v), caml_string_length(s_v));
    CAMLreturn(caml_copy_int64(r));
}

/* Borrow a march String/Bytes and return a copy as an OCaml string. */
CAMLprim value march_ffi_str_borrow_copy(value v_v) {
    CAMLparam1(v_v);
    CAMLlocal1(result);
    lazy_init();
    ffi_slice s = p_str_borrow(Int64_val(v_v));
    result = caml_alloc_string(s.len);
    memcpy(Bytes_val(result), s.ptr, s.len);
    CAMLreturn(result);
}

CAMLprim value march_ffi_bytes_borrow_copy(value v_v) {
    CAMLparam1(v_v);
    CAMLlocal1(result);
    lazy_init();
    ffi_slice s = p_bytes_borrow(Int64_val(v_v));
    result = caml_alloc_string(s.len);
    memcpy(Bytes_val(result), s.ptr, s.len);
    CAMLreturn(result);
}

CAMLprim value march_ffi_none_boxed(value unit) {
    CAMLparam1(unit);
    lazy_init();
    CAMLreturn(caml_copy_int64(p_none_boxed()));
}
CAMLprim value march_ffi_some_boxed(value v_v) {
    CAMLparam1(v_v);
    lazy_init();
    CAMLreturn(caml_copy_int64(p_some_boxed(Int64_val(v_v))));
}
CAMLprim value march_ffi_ok(value v_v) {
    CAMLparam1(v_v);
    lazy_init();
    CAMLreturn(caml_copy_int64(p_ok(Int64_val(v_v))));
}
CAMLprim value march_ffi_err(value v_v) {
    CAMLparam1(v_v);
    lazy_init();
    CAMLreturn(caml_copy_int64(p_err(Int64_val(v_v))));
}

CAMLprim value march_ffi_variant_tag(value v_v) {
    CAMLparam1(v_v);
    lazy_init();
    CAMLreturn(Val_int(p_variant_tag(Int64_val(v_v))));
}
CAMLprim value march_ffi_variant_field(value v_v, value i_v) {
    CAMLparam2(v_v, i_v);
    lazy_init();
    CAMLreturn(caml_copy_int64(p_variant_field(Int64_val(v_v), Int_val(i_v))));
}
CAMLprim value march_ffi_record_field(value v_v, value i_v) {
    CAMLparam2(v_v, i_v);
    lazy_init();
    CAMLreturn(caml_copy_int64(p_record_field(Int64_val(v_v), Int_val(i_v))));
}

/* make_variant(tag, fields_array) — fields is an int64 array */
CAMLprim value march_ffi_make_variant(value tag_v, value fields_v) {
    CAMLparam2(tag_v, fields_v);
    lazy_init();
    int n = (int)Wosize_val(fields_v);
    int64_t *fs = n ? alloca(n * sizeof(int64_t)) : NULL;
    for (int i = 0; i < n; i++) fs[i] = Int64_val(Field(fields_v, i));
    int64_t r = p_make_variant(Int_val(tag_v), n, (const int64_t *)fs);
    CAMLreturn(caml_copy_int64(r));
}

/* make_record(desc, fields_array) */
CAMLprim value march_ffi_make_record(value desc_v, value fields_v) {
    CAMLparam2(desc_v, fields_v);
    lazy_init();
    int n = (int)Wosize_val(fields_v);
    int64_t *fs = n ? alloca(n * sizeof(int64_t)) : NULL;
    for (int i = 0; i < n; i++) fs[i] = Int64_val(Field(fields_v, i));
    int64_t r = p_make_record(String_val(desc_v), n, (const int64_t *)fs);
    CAMLreturn(caml_copy_int64(r));
}

CAMLprim value march_ffi_dup(value v_v) {
    CAMLparam1(v_v);
    lazy_init();
    p_dup(Int64_val(v_v));
    CAMLreturn(Val_unit);
}
CAMLprim value march_ffi_drop(value v_v) {
    CAMLparam1(v_v);
    lazy_init();
    p_drop(Int64_val(v_v));
    CAMLreturn(Val_unit);
}

/* ── `raises` sentinel  ──────────────────────────────────────────────────── */
/* Layout must match struct march_env { int64_t raised; int64_t err; }. */

CAMLprim value march_ffi_alloc_env(value unit) {
    CAMLparam1(unit);
    int64_t *p = calloc(2, sizeof(int64_t));
    if (!p) caml_failwith("march_ffi_alloc_env: out of memory");
    CAMLreturn(caml_copy_nativeint((intnat)p));
}
CAMLprim value march_ffi_free_env(value ptr_v) {
    CAMLparam1(ptr_v);
    free((void *)Nativeint_val(ptr_v));
    CAMLreturn(Val_unit);
}
CAMLprim value march_ffi_env_raised(value ptr_v) {
    CAMLparam1(ptr_v);
    int64_t *p = (int64_t *)Nativeint_val(ptr_v);
    CAMLreturn(Val_bool(p[0] != 0));
}
CAMLprim value march_ffi_env_err(value ptr_v) {
    CAMLparam1(ptr_v);
    int64_t *p = (int64_t *)Nativeint_val(ptr_v);
    CAMLreturn(caml_copy_int64(p[1]));  /* .err at offset 8 */
}
/* Address of the sentinel as int64 — to prepend as the first GP arg. */
CAMLprim value march_ffi_env_ptr_i64(value ptr_v) {
    CAMLparam1(ptr_v);
    CAMLreturn(caml_copy_int64((int64_t)Nativeint_val(ptr_v)));
}
