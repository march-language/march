/* runtime/march_ffi.h — March External Function Interface, stable ABI.
 *
 * Native bindings include ONLY this header; runtime internals stay private.
 * This is the C-language analog of BEAM's erl_nif.h.  See the design spec
 * specs/2026-06-19-c-ffi-abi-design.md §4 for the full rationale.
 *
 * Value representation (do not manipulate raw bits — use the accessors):
 *   - Int / Bool : tagged word  (n << 1) | 1   (untag = arithmetic >> 1)
 *   - Float      : raw IEEE-754 bits bitcast to int64 (UNTAGGED)
 *   - heap object: an even, non-zero pointer word used verbatim
 * Because a Float word may be either even or odd, there is NO universal
 * runtime discriminator: access every value by its STATIC type.
 */
#ifndef MARCH_FFI_H
#define MARCH_FFI_H

#include <stdint.h>
#include <stddef.h>

#define MARCH_FFI_ABI_VERSION 1

/* Every compiled binding object exports this so the loader can reject skew. */
int32_t march_ffi_abi_version(void); /* returns MARCH_FFI_ABI_VERSION */

typedef int64_t march_value;         /* opaque tagged value word */

/* Per-call context, threaded as a hidden first parameter into `raises`
 * bindings.  Opaque to bindings — manipulate only via march_raise. */
typedef struct march_env march_env;

/* Fatal, unrecoverable error from a binding (programmer error): aborts. */
void march_fatal(const char *msg);

/* ── Error protocol (`raises` bindings) ──────────────────────────────────────
 * A binding for an extern declared `raises fn … : Result(T, E)` receives a
 * hidden `march_env *env` first parameter and returns the bare Ok payload (T's
 * natural C type) on success.  To fail, it builds the error value `e` (a
 * march_value of type E) and calls march_raise(env, e), then returns any value.
 * The compiler-emitted wrapper materializes Ok(payload) or Err(e).  Calling
 * march_raise more than once keeps the first error. */
void march_raise(march_env *env, march_value e);

/* ── Primitive accessors (access by static type) ─────────────────────────── */
march_value march_make_int(int64_t n);    /* (n << 1) | 1 */
int64_t     march_get_int(march_value v); /* v >> 1 (arithmetic) */
march_value march_make_bool(int b);
int         march_get_bool(march_value v);
march_value march_make_float(double f);   /* bitcast, untagged */
double      march_get_float(march_value v);

/* ── Heap pointer bridging ───────────────────────────────────────────────── */
int         march_is_heap(march_value v); /* even && non-zero */
void       *march_as_ptr(march_value v);  /* heap pointer, verbatim */
march_value march_from_ptr(void *p);      /* wrap a heap pointer, verbatim */

/* ── Strings & bytes (borrow tier) ───────────────────────────────────────────
 * A borrowed view into a March String/Bytes value, valid for the duration of
 * the call only.  `ptr` is NOT NUL-terminated — honor `len`.  String data is
 * UTF-8; Bytes is raw octets. */
typedef struct { const uint8_t *ptr; size_t len; } march_slice;
march_slice march_str_borrow(march_value s);    /* borrow a String's UTF-8 bytes */
march_slice march_bytes_borrow(march_value b);  /* borrow a Bytes value's octets */

/* Validate that [p..p+len) is well-formed UTF-8.  Returns 1 if valid, 0 if not. */
int march_utf8_valid(const uint8_t *p, size_t len);

/* Construct an owned (rc=1) String/Bytes by copying len bytes. */
march_value march_str_new(const uint8_t *utf8, size_t len);
march_value march_bytes_new(const uint8_t *data, size_t len);

/* ── Variants (ADTs) & records ───────────────────────────────────────────────
 * These move a field SLOT verbatim; a slot holds March's NATIVE per-field
 * representation, which you must match by the field's STATIC type:
 *   - Int / Bool  : a RAW machine int (NOT a tagged value word — do not use
 *                   march_make_int / march_get_int on a slot).
 *   - Float       : raw IEEE-754 bits (march_make_float / march_get_float).
 *   - String/Bytes/heap/Option-niche : the value word itself (march_str_new to
 *                   build, march_str_borrow to read).
 * Read: tag / field by index (borrowed — the cell owns heap fields).
 * Construct: make_variant / make_record take ownership of heap field words.
 * Record fields are in canonical (name-sorted) order; `desc` is the shape
 * descriptor "name:k;name:k;…" with k in {i,f,p,g} (i=Int/Bool, f=Float,
 * p=String/heap, g=generic), names sorted ascending. */
int32_t     march_variant_tag(march_value v);
march_value march_variant_field(march_value v, int32_t i);
march_value march_record_field(march_value v, int32_t i);
march_value march_make_variant(int32_t tag, int32_t nfields, const march_value *fields);
march_value march_make_record(const char *desc, int32_t nfields, const march_value *fields);

/* ── List (Nil | Cons(T, List(T))) ───────────────────────────────────────────
 * March lists are singly-linked: Nil = variant tag 0 (no fields), Cons =
 * variant tag 1 (field 0 = head, field 1 = tail).  Use march_list_length
 * + march_list_nth only for small lists; prefer a single-pass scan otherwise. */
march_value march_list_nil(void);
march_value march_list_cons(march_value head, march_value tail);
int32_t     march_list_length(march_value v);   /* O(n) spine traversal */
march_value march_list_nth(march_value v, int32_t i); /* O(i) */

/* ── Option / Result constructors (each takes ownership of its payload) ──────*/
march_value march_none(void);           /* Option None  (tag 0) */
march_value march_some(march_value v);  /* Option Some  (niche: Some(x)=x) */
/* Boxed Some for Option(Float)/Option(Unit) (non-niche payloads): a heap Some
 * cell whose payload would otherwise alias None=0.  Pass march_make_float(f) for
 * a Float payload; None still uses march_none(). */
march_value march_some_boxed(march_value payload);
/* Boxed None, paired with march_some_boxed (Float/Unit Options are matched by
 * cell tag, so None must be a heap cell too — not the niche 0). */
march_value march_none_boxed(void);
march_value march_ok(march_value v);    /* Result Ok    (tag 0) */
march_value march_err(march_value e);   /* Result Err   (tag 1) */

/* ── Resources (opaque native handles with destructors) ──────────────────────
 * A resource wraps a native pointer behind an opaque March value.  When March
 * drops the value to rc=0, the runtime runs the registered destructor on the
 * native pointer.  Register a type once (idempotent by name), then mint values
 * with march_resource_new and read the native pointer back with
 * march_resource_get (type-checked). */
typedef void (*march_destructor)(void *native_ptr);

/* Register (or look up) a resource type by name; returns a stable type id.
 * Idempotent: the same name returns the same id (the first dtor wins). */
int32_t     march_resource_type(const char *name, march_destructor dtor);

/* Wrap [native_ptr] as an owned (rc=1) March resource value of [type_id]. */
march_value march_resource_new(int32_t type_id, void *native_ptr);

/* Borrow the native pointer back. Aborts if [v] is not a resource of [type_id]. */
void       *march_resource_get(march_value v, int32_t type_id);

/* ── Blocking dispatch ───────────────────────────────────────────────────────
 * Run a `blocking` extern (`fn` with `args` of int64/ptr) on a pool OS thread
 * while the calling green thread cooperatively yields.  Two return shapes
 * (int64 / double).  Emitted by codegen for `blocking` extern calls. */
int64_t march_run_blocking_i(void *fn, const int64_t *args, int n);
double  march_run_blocking_d(void *fn, const int64_t *args, int n);

/* Blocking-pool diagnostics (tests): worker threads ever spawned, and blocking
 * calls ever submitted.  The pool reuses threads, so spawned should stay far
 * below calls; one-thread-per-call would make them equal. */
int64_t march_blocking_threads_spawned(void);
int64_t march_blocking_calls(void);
/* Test hook: trivial body, declared `blocking` by tests to drive the pool. */
int64_t march_test_blocking_nap(int64_t us);

/* ── Native → March upcalls ───────────────────────────────────────────────────
 * Invoke a March closure value (received as an extern parameter of a function
 * type) from a binding: reads the closure's apply-fn pointer and calls it.
 * Up to 5 arguments. The closure/args are borrowed — March owns them across the
 * call.
 *
 * Representation (asymmetric — match each by static type):
 *   - ARGUMENTS use the NATIVE slot rep, exactly like variant/record fields:
 *     Int/Bool = a RAW machine int (NOT march_make_int), Float = raw IEEE-754
 *     bits (march_make_float), String/Bytes/heap = the value word itself.
 *   - The RESULT is the GENERIC tagged word: read Int with march_get_int, Bool
 *     with march_get_bool, Float with march_get_float, heap/String verbatim. */
march_value march_call(march_value closure, int32_t nargs, const march_value *args);

/* ── Reference counting (tag-aware) ──────────────────────────────────────────
 * Safe to call on Int/Bool/heap value words: tagged words are a no-op, heap
 * words adjust the refcount.  NEVER call on a Float word — its bit pattern may
 * masquerade as a heap pointer. */
march_value march_dup(march_value v);  /* heap: incref; tagged: no-op; returns v */
void        march_drop(march_value v); /* heap: decref (may free); tagged: no-op */

#endif /* MARCH_FFI_H */
