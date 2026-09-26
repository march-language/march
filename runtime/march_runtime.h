#pragma once
#include <stdint.h>
#include <setjmp.h>
#include <stdio.h>   /* march_sso_selftest formats its failure message */

/* Object header layout (16 bytes):
 *   offset  0: int64_t  rc   (reference count)
 *   offset  8: int32_t  tag  (constructor tag)
 *   offset 12: int32_t  pad  (alignment)
 * Fields start at offset 16, each 8 bytes.
 * TInt fields stored as int64_t, TFloat as double, all others as pointer. */
typedef struct { int64_t rc; int32_t tag; int32_t pad; } march_hdr;

/* ── What the header pad word means ───────────────────────────────────
 *
 * `pad` is multiplexed, decided by SIGN and by tag:
 *   > 0   record shape id (march_record_shape_intern, tag 0 cells), or the
 *         SIMD lane kind (under MARCH_SIMD_TAG).
 *   == 0  nothing known.  march_alloc zeroes it, and every cell the C runtime
 *         builds itself (make_cons & friends, the message copier's strings,
 *         C-built results) reads as this.
 *   < 0   a boxed ADT TYPE ID: -(1 + (fnv1a32(type_name) & 0x3FFFFFFF)),
 *         stamped by the compiler at every constructor header store
 *         (lib/tir/llvm_data.ml emit_store_tag, incl. FBIP reuse and stack
 *         cells) so a value reaching a renderer through an ERASED slot can
 *         still be told apart from another type with the same tag.  The
 *         runtime resolves it through the constructor-name table
 *         (march_ctor_table_ensure) and treats a hash collision as
 *         "unknown", never as a guess.  Negative so it can never be mistaken
 *         for one of the positive users above; march_record_shape's reader
 *         already rejects id <= 0.  Kept in lockstep with
 *         Llvm_ctx.type_id_of_name; specs/progress/2026-09-11-boxed-adt-type-id.md.
 *
 * Two runtime sites compare the whole 64-bit tag+pad word against
 * MARCH_MIGRATE_TAG (a C-built struct, pad 0); a stamped cell cannot collide
 * with it because ordinary constructor tags are bounded by
 * MARCH_ORDINARY_CTOR_TAG_LIMIT, far below that value's low word. */
static inline int32_t march_hdr_type_id(const void *p) {
    int32_t pad = ((const march_hdr *)p)->pad;
    return pad < 0 ? pad : 0;
}
/* The id the compiler stamps for a type named [name] (march_extras.c). */
int32_t march_type_id_of_name(const char *name);
/* `~H` hole on an ERASED value: flattens iff the header id says IOList,
 * otherwise renders by name and escapes (march_extras.c). */
void   *march_html_auto_escape_dyn(void *v);
/* Same decision under a context escaper id (march_extras.c). */
void   *march_html_escape_ctx_dyn(int64_t escaper_id, void *v);
/* Installed by march_ctor_table_ensure: renders a heap cell by its header
 * type id, or returns NULL when the id is unknown/ambiguous.  NULL until a
 * descriptor is registered, so the WASM runtime and binaries with no erased
 * render site never pay for it.  [repr] selects the nested-string convention
 * (see march_value_to_string_mode). */
extern void *(*march_render_dyn_hook)(void *v, int repr);

/* Heap allocation: allocates sz bytes zeroed, returns a pointer. */
void *march_alloc(int64_t sz);

/* Net count of live march objects (alloc + / free-on-rc=0 -). FFI/test leak
   gauge; see specs/2026-06-19-c-ffi-abi-design.md §14.4. */
int64_t march_live_allocs(void);

/* Reference counting (atomic — safe for cross-thread shared values). */
void  march_incrc(void *p);
void  march_decrc(void *p);
/* Decrement RC and return 1 if the object was freed (RC hit 0), 0 if still alive.
   Used when pattern-matching to conditionally IncRC extracted child pointers. */
int64_t march_decrc_freed(void *p);
/* Decrement RC with march_decrc_local's atomicity policy and return 1 if the
   object was freed, 0 otherwise (0 also for a non-heap pointer). */
int64_t march_decrc_local_freed(void *p);

/* Non-atomic reference counting — only safe for values provably owned by a
   single thread (no actor send in their lifetime).  Faster than atomic ops
   because they avoid memory barriers; the compiler may also optimize them
   into register increments. */
void  march_incrc_local(void *p);
void  march_decrc_local(void *p);

/* Flag the calling OS thread as running compiled March code outside the
 * scheduler (e.g. an HTTP thread-pool worker), forcing atomic "local"
 * refcount ops on that thread.  See march_rc_set_thread_concurrent in
 * march_runtime.c. */
void  march_rc_set_thread_concurrent(int on);

void  march_free(void *p);

/* Pending-drop list of a flattened tail-call loop (self- or mutual-TCO).
   A tail call that forwards an owned value to a BORROWED parameter is followed
   by a release of that value, which under real recursion runs only once the
   nested call has returned.  The loop has no such "after": the back edge
   records (release fn, value) here instead, and every return of the loop
   function runs the recorded releases, newest first -- the order the
   recursion's frames would have unwound in.  [buf] is NULL until the first
   push; push returns the (possibly moved) buffer.  Drain accepts NULL and
   frees the buffer.  See lib/tir/llvm_emit_tcoarm.ml. */
void *march_tco_defer_push(void *buf, void (*release)(void *), void *v);
void  march_tco_defer_drain(void *buf);

/* I/O builtins. */
void  march_print(void *s);
void  march_println(void *s);
void  march_print_stderr(void *s);
void *march_io_read_line(void);
int64_t march_io_read_byte(void);
int64_t march_int_pow(int64_t base, int64_t exp);

/* Panic/todo primitive variants (return ptr so they satisfy polymorphic `a`). */
void *march_panic_ext(void *s);
void *march_todo_ext(void *s);

/* Call-stack frame table (used by compiled binaries for backtraces).
 * march_frame_t is stack-allocated at each March function's entry. */
typedef struct march_frame_t {
    const char         *fn_name;
    const char         *file;
    int                 line;
    struct march_frame_t *prev;
} march_frame_t;

void march_frame_push(march_frame_t *frame);
void march_frame_pop(void);
void march_frame_reset(void);

/* UTF-8 codepoint builtins. */
void *march_string_to_codepoints(void *s);
void *march_string_from_codepoint(int64_t cp);

/* Time builtins. */
double  march_unix_time(void);
int64_t march_unix_time_ms(void);

/* Process self-inspection: peak RSS in bytes, both platforms. */
int64_t march_peak_rss_bytes(void);

/* TypedArray builtins. */
void   *march_typed_array_from_list(void *list);
void   *march_typed_array_to_list(void *arr);
int64_t march_typed_array_length(void *arr);
void   *march_typed_array_get(void *arr, int64_t i);
void   *march_typed_array_set(void *arr, int64_t i, void *val);
void   *march_typed_array_create(int64_t len, void *default_val);
void   *march_typed_array_map(void *arr, void *f);
void   *march_typed_array_slice(void *arr, int64_t start, int64_t len);
void   *march_typed_array_filter(void *arr, void *f);
void   *march_typed_array_fold(void *arr, void *acc, void *f);

/* Logger builtins. */
void   *march_logger_set_level(int64_t level);
int64_t march_logger_get_level(void);
void   *march_logger_add_context(void *key, void *value);
void   *march_logger_clear_context(void);
void   *march_logger_get_context(void);
void   *march_logger_write(void *level_str, void *msg, void *ctx, void *extra);
/* Logger v2: field stack, appenders, per-module levels.  Unprefixed
 * `logger_*` (identity-fallthrough) C functions until 2026-09-26. */
void   *march_logger_add_field(void *key, void *value);
int64_t march_logger_field_count(void);
void   *march_logger_get_fields(void);
void   *march_logger_pop_to_depth(int64_t depth);
void   *march_logger_dispatch(void *level_str, void *msg, void *module_name, void *fields);
void   *march_logger_register_appender(void *name, void *cb);
void   *march_logger_remove_appender(void *name);
void   *march_logger_clear_appenders(void);
void   *march_logger_appender_names(void);
void   *march_logger_set_module_level(void *mod, int64_t lv);
void   *march_logger_clear_module_level(void *mod);
int64_t march_logger_module_level(void *mod);

/* __try_call / __try_call_val: run a (Bool -> a) thunk, catching a panic as
 * Err(msg).  Unprefixed `__try_call` / `__try_call_val` until 2026-09-26. */
void   *march_try_call(void *thunk);
void   *march_try_call_val(void *thunk);

/* String builtins.
 *
 * march_string shares the 16-byte march_hdr prefix (rc/tag/pad) so that a
 * string heap cell is DISCRIMINABLE from an ADT/tuple/record cell by its tag
 * word at offset 8 — every string carries the reserved MARCH_STRING_TAG.
 * This lets march_value_to_string (the type-erased to_string path, hit when
 * the static type is a TVar that actually holds a string) recognize a string
 * and return it verbatim instead of misreading the layout and printing
 * "#<tag:len>".  len moves to offset 16 and data to offset 24; all access is
 * through the struct members, so recompilation keeps every offset correct.
 * Compiled code never bakes in the layout — it builds strings via
 * march_string_lit — so this is a runtime-only change. */
#define MARCH_STRING_TAG ((int32_t)-1) /* 0xFFFFFFFF — reserved sentinel, never a ctor index (ADT tags are >= 0). Matches the long-standing cross-heap copy convention in march_message.c. */
/* FFI resource cell (opaque native handle). Distinct reserved tag so the
 * RC free path can run the destructor. Layout: [rc][tag][pad][native_ptr@16]
 * [dtor@24][type_id@32] (40 bytes). See runtime/march_ffi.c. */
#define MARCH_RESOURCE_TAG ((int32_t)-2)
/* Boxed Float. The stage-2 target of the float-boxing design
 * (specs/plans/2026-07-13-float-boxing-design.md): a Float that flows through
 * a type-ERASED (ptr) slot is heap-boxed so it is discriminable from a tagged
 * int (odd) and a heap object (ADT tag >= 0), instead of the current raw-bits
 * bitcast that IS_HEAP_PTR accidentally accepts (→ RC-on-raw-bits SIGSEGV and
 * generic-compare-on-raw-bits silent wrong answers). Reserved negative tag,
 * joining the string/resource sentinels. Layout: [rc][tag][pad][val@16] (24
 * bytes). Concrete `double` fields and REPL/static Float slots stay unboxed;
 * only erased slots box. Introduced additive (nothing emits it yet) — the
 * codegen flip that populates erased slots with these is stage 2. */
#define MARCH_FLOAT_TAG ((int32_t)-3)
typedef struct { int64_t rc; int32_t tag; int32_t pad; double val; } march_float_box;
/* Allocate a boxed Float (rc=1, tag=MARCH_FLOAT_TAG). */
void   *march_alloc_float(double v);
/* Read the double out of a boxed Float. Undefined if [p] is not a float box. */
double  march_unbox_float(void *p);

/* 128-bit SIMD vector box: march_hdr(16) + 16-byte payload = 32 bytes,
 * payload 16-aligned. kind lives in the hdr pad slot (byte offset 12):
 * 0=f32x4 1=f64x2 2=i32x4 3=i64x2 4=u8x16. Leaf cell — no interior
 * pointers, freed by the ordinary rc==0 path with no walk. */
#define MARCH_SIMD_TAG ((int32_t)-4)
/* Allocate a 32-byte SIMD vector box (rc=1, tag=MARCH_SIMD_TAG, kind in pad). */
void   *march_simd_alloc(int64_t kind);
/* Report an out-of-bounds SIMD load/store index and terminate. Noreturn. */
void    march_simd_bounds_panic(int64_t i, int64_t lanes, int64_t len);
void    march_simd_lane_panic(int64_t i, int64_t lanes);
typedef struct { int64_t rc; int32_t tag; int32_t pad; int64_t len; char data[]; } march_string;

/* send_after/cancel_timer cancellation token (specs/progress/2026-08-12-
 * language-level-timers.md). An ordinary march_alloc'd, RC'd heap value —
 * NOT a bespoke malloc'd struct like march_cancel_token (runtime/
 * march_scheduler.h) — specifically so Perceus's normal, type-driven
 * inc_rc/dec_rc insertion (needs_rc(TCon _) = true; see lib/tir/
 * rc_types.ml) operates correctly on it without any special-casing: any
 * TimerRef held/copied more than once (e.g. checked for cancellation and
 * then discarded) gets a real inc_rc against a real march_hdr, unlike a raw
 * malloc'd struct where that would corrupt whatever bytes happen to sit at
 * the assumed rc offset. Layout: [rc][tag][pad][cancelled@16] (24 bytes);
 * cancelled is 0/1, mutated with atomic ops by march_timer_cancel and read
 * the same way by the scheduler's registered is_cancelled callback (see
 * march_sched_set_timer_token_ops in runtime/march_scheduler.h). Two owners
 * across its lifetime: the timer heap entry (from march_send_after's push
 * until the entry is popped, fired or not) and the March-level TimerRef
 * binding returned to the caller — ordinary RC, no leak, no cancel-after-
 * fire UAF (the object only dies once BOTH release it). */
#define MARCH_TIMER_TOKEN_TAG ((int32_t)-5)
/* Native arrays (NativeU8Arr and friends) carry their own sentinel so a
 * generic walker can tell a flat byte/word buffer from an ADT cell. Without
 * it every walker fell through to the ADT case, read n_fields out of
 * alloc_meta and scanned the PAYLOAD for pointers -- which is why native
 * arrays were barred from actor messages (GAPS.md G44) rather than copied.
 * See native_arr_alloc, which sets it, and march_message.c's copy_value. */
#define MARCH_NATIVE_ARR_TAG ((int32_t)-6)
/* The 48-byte Task object returned by march_task_spawn_thunk /
 * march_task_spawn_with_cancel_thunk. It used to carry tag 0, which made it
 * indistinguishable from an ADT cell, so no free path could release what it
 * owns. It owns the reference to a Float result's march_alloc_float box in
 * task[3] (task_await_unwrap unboxes without consuming, since a task may be
 * awaited twice); march_run_resource_dtor releases it when the Task dies. */
#define MARCH_TASK_TAG ((int32_t)-7)

/* send_after(pid, msg, delay_ms) : TimerRef — schedule msg for delivery to
 * the actor `actor` after delay_ms milliseconds. RC contract matches
 * march_send: receives exactly one owned reference to msg (transferred into
 * the timer heap until delivery or disposal). Returns a new TimerRef (see
 * MARCH_TIMER_TOKEN_TAG above), one reference transferred to the caller. */
void   *march_send_after(void *actor, void *msg, int64_t delay_ms);

/* cancel_timer(ref) — cancel a pending send_after timer. Consumes (and
 * releases) the one reference to `tok` it receives, matching the RC
 * contract of any builtin that takes ownership of its argument. Safe to
 * call at any time, including after the timer has already fired (no-op) or
 * been cancelled already (no-op) — the token's own RC keeps it alive for as
 * long as the caller holds a valid TimerRef, by construction. */
void    march_timer_cancel(void *tok);

/* Reserved constructor-tag ABI for runtime-originated local-monitor values.
 * Keep in sync with lib/tir/llvm_builtins.ml. Ordinary constructors and the
 * two compiler global-tag allocators are bounded below this range. */
#define MARCH_ORDINARY_CTOR_TAG_LIMIT 0x01000000
#define MARCH_ACTOR_MSG_TAG_BASE      0x01000000
#define MARCH_ACTOR_MSG_TAG_LIMIT     0x02000000
#define MARCH_COLLISION_TAG_BASE      0x02000000
#define MARCH_COLLISION_TAG_LIMIT     0x03000000
#define MARCH_DOWN_TAG                0x7F000000
#define MARCH_DOWN_NORMAL_TAG         0x7F000001
#define MARCH_DOWN_KILLED_TAG         0x7F000002
#define MARCH_DOWN_CRASH_TAG          0x7F000003
#define MARCH_RESERVED_CTOR_TAG_LIMIT 0x7F000004

#if MARCH_ORDINARY_CTOR_TAG_LIMIT > MARCH_ACTOR_MSG_TAG_BASE || \
    MARCH_ACTOR_MSG_TAG_LIMIT > MARCH_COLLISION_TAG_BASE || \
    MARCH_COLLISION_TAG_LIMIT > MARCH_DOWN_TAG || \
    MARCH_DOWN_CRASH_TAG >= MARCH_RESERVED_CTOR_TAG_LIMIT
#error "March constructor tag ranges overlap the reserved monitor ABI"
#endif

/* Polymorphic containers store scalars via tagged integers: the low bit of the
 * pointer is set to 1 for immediate scalar values (integers, booleans, chars).
 * Heap pointers from march_alloc (backed by calloc) are always 8-byte aligned,
 * so their low bit is always 0.  This uniform tagging scheme lets the runtime
 * discriminate between heap pointers and immediates without dereferencing.
 *
 * Tag scheme:
 *   immediate integer n  → stored as ptr = (n << 1) | 1  (low bit = 1)
 *   heap pointer p       → stored as ptr = p             (low bit = 0)
 *
 * Guards (in order, short-circuit):
 *   1. low bit == 0: any value with bit 0 set is an immediate — reject fast.
 *   2. addresses below one page (4096) are never valid heap allocations —
 *      defense-in-depth for uninitialised fields and NULL.
 *   3. values with the sign bit set (intptr_t < 0) are never valid heap
 *      pointers on any supported 64-bit ABI: user-space mallocs live in the
 *      lower canonical half (bit 47 clear on x86-64, bit 48 on AArch64). */
#define IS_HEAP_PTR(p) \
    (((uintptr_t)(p) & 1u) == 0 && (uintptr_t)(p) >= 4096u && (intptr_t)(p) > 0)

/* ── The closure-call convention, from C ──────────────────────────────────
 *
 * Calling a March closure CONSUMES each heap argument, except a boxed Float
 * (the callee unboxes it in its prologue and never releases the box). Every
 * compiled caller follows that, and so must the runtime: a helper passing a
 * value it keeps using, or that something else owns (an array element, the
 * previous accumulator it still needs), hands the callee its own reference
 * first. See lib/tir/clo_flags.ml for the compiler side. */
static inline void march_clo_arg_retain(void *arg) {
    if (IS_HEAP_PTR(arg) && ((march_hdr *)arg)->tag != MARCH_FLOAT_TAG)
        march_incrc(arg);
}

/* Moved here from march_runtime.c: the inline-string encoding below is safe
 * only BECAUSE of this predicate's exact definition — an inline string sets the
 * sign bit and so fails guard 3 — and march_sso_selftest asserts exactly that.
 * Keeping the two in one file means they cannot drift apart silently. */

/* ── Small-string optimization: inline strings of <= 7 bytes ──────────────
 *
 * A string of at most MARCH_SSO_MAX bytes is stored IN THE VALUE, with no
 * allocation and no refcount:
 *
 *   [63] = 1  |  [62:59] = length 0..7  |  [58:3] = payload  |  [2:0] = 0
 *
 * WHY THIS ENCODING IS SAFE — the correctness argument for the whole scheme.
 * March already carries two tagged forms, and this is unreachable by both:
 *
 *   heap pointer    bit63 = 0, low bit = 0, value >= 4096
 *   immediate int   (n << 1) | 1  — low bit ALWAYS 1, for any n incl. negative
 *   inline string   bit63 = 1, low bit = 0                      <- distinct
 *
 * An inline string sets bit63, so it fails IS_HEAP_PTR's `(intptr_t)p > 0`
 * test and can never be mistaken for a pointer.  It clears the low bit, so it
 * can never be mistaken for an immediate integer, whose encoding forces that
 * bit set regardless of sign.
 *
 * The consequence that makes this cheap: march_incrc and march_decrc both open
 * with `if (!IS_HEAP_PTR(p)) return;`, so inline strings are refcount-free with
 * NO change to the RC hot path.  They are never freed, never counted, never
 * shared — copying one is copying a register.
 *
 * Bytes are little-endian within the payload; the empty string is length 0.
 * See specs/plans/2026-07-27-string-sso.md. */
#define MARCH_SSO_MAX 7
#define MARCH_SSO_BIT (1ULL << 63)

static inline int march_str_is_inline(const void *p) {
    return ((uintptr_t)p & MARCH_SSO_BIT) != 0 && ((uintptr_t)p & 1u) == 0;
}

static inline int64_t march_str_len(const void *p) {
    if (march_str_is_inline(p)) return (int64_t)(((uintptr_t)p >> 59) & 0xF);
    return ((const march_string *)p)->len;
}

/* Returns a pointer to the string's bytes, NUL-terminated.
 *
 * For an inline string the bytes are unpacked into [scratch], which the CALLER
 * owns and which MUST be at least MARCH_SSO_MAX + 1 bytes — the returned
 * pointer is valid only as long as [scratch] is.  A heap string returns its own
 * data and ignores [scratch].  Callers that keep the pointer beyond the
 * scratch buffer's lifetime are wrong; that is the one hazard this accessor
 * introduces and the reason it takes the buffer explicitly rather than using a
 * static. */
static inline const char *march_str_data(const void *p, char *scratch) {
    if (march_str_is_inline(p)) {
        uint64_t bits = (uint64_t)(uintptr_t)p >> 3;
        int64_t n = march_str_len(p);
        for (int64_t i = 0; i < n; i++)
            scratch[i] = (char)((bits >> (i * 8)) & 0xFF);
        scratch[n] = '\0';
        return scratch;
    }
    return ((const march_string *)p)->data;
}

/* Pack [n] <= MARCH_SSO_MAX bytes into an inline string value. */
static inline void *march_str_make_inline(const char *s, int64_t n) {
    uint64_t bits = 0;
    for (int64_t i = 0; i < n; i++)
        bits |= (uint64_t)(unsigned char)s[i] << (i * 8);
    return (void *)(uintptr_t)(MARCH_SSO_BIT | ((uint64_t)n << 59) | (bits << 3));
}

/* Self-test for the inline-string encoding (see march_runtime.h).
 *
 * Checks the three properties the representation depends on:
 *   1. round-trip: every length 0..MARCH_SSO_MAX recovers its exact bytes,
 *      including embedded NULs and high bytes (march_string is length-counted,
 *      so 0x00 and 0xFF are ordinary data);
 *   2. non-collision with immediate integers, whose encoding (n << 1) | 1
 *      forces the low bit set for every n including negatives;
 *   3. non-collision with heap pointers, i.e. IS_HEAP_PTR rejects every inline
 *      value — which is what makes the RC path need no changes.
 *
 * Returns "ok" or the first failure. */
static inline const char *march_sso_selftest(void) {
    static char msg[128];
    char scratch[MARCH_SSO_MAX + 1];

    /* 1. Round-trip every length, with a byte pattern that includes 0x00 and
     *    0xFF so a NUL-terminator assumption or a sign-extension bug shows up. */
    for (int64_t n = 0; n <= MARCH_SSO_MAX; n++) {
        char src[MARCH_SSO_MAX];
        for (int64_t i = 0; i < n; i++)
            src[i] = (char)(i == 0 ? 0x00 : (i == 1 ? 0xFF : 'a' + i));
        void *v = march_str_make_inline(src, n);
        if (!march_str_is_inline(v)) {
            snprintf(msg, sizeof msg, "len %lld: not recognised as inline", (long long)n);
            return msg;
        }
        if (march_str_len(v) != n) {
            snprintf(msg, sizeof msg, "len %lld: read back %lld",
                     (long long)n, (long long)march_str_len(v));
            return msg;
        }
        const char *d = march_str_data(v, scratch);
        for (int64_t i = 0; i < n; i++) {
            if (d[i] != src[i]) {
                snprintf(msg, sizeof msg, "len %lld: byte %lld is 0x%02x, expected 0x%02x",
                         (long long)n, (long long)i,
                         (unsigned char)d[i], (unsigned char)src[i]);
                return msg;
            }
        }
        if (d[n] != '\0') {
            snprintf(msg, sizeof msg, "len %lld: not NUL-terminated", (long long)n);
            return msg;
        }
        /* 3. An inline value must never look like a heap pointer. */
        if (IS_HEAP_PTR(v)) {
            snprintf(msg, sizeof msg, "len %lld: IS_HEAP_PTR accepted an inline value", (long long)n);
            return msg;
        }
    }

    /* 2. No immediate integer can be mistaken for an inline string. */
    {
        int64_t probes[] = { 0, 1, -1, -2, 42, -42,
                             (int64_t)1 << 40, -((int64_t)1 << 40),
                             INT64_MAX / 2, INT64_MIN / 2 };
        for (size_t i = 0; i < sizeof probes / sizeof probes[0]; i++) {
            void *imm = (void *)(uintptr_t)(((uint64_t)probes[i] << 1) | 1u);
            if (march_str_is_inline(imm)) {
                snprintf(msg, sizeof msg,
                         "immediate int %lld misread as an inline string",
                         (long long)probes[i]);
                return msg;
            }
        }
    }

    return "ok";
}

/* Allocate an uninitialised-data march_string of byte length [len], with the
 * header (rc=1, tag=MARCH_STRING_TAG, pad=0, len) filled in.  Callers fill
 * data[0..len] and the NUL terminator.  Centralises header init so no string
 * site can leave the discriminator tag unset. */
void *march_string_alloc(int64_t len);
void *march_string_lit(const char *utf8, int64_t len);
/* Native int/float/u8 array layout (ALL element widths share it — phase C's
 * vector loads depend on elem_kind and the 16-byte data alignment):
 *   march_hdr(16) + int64_t len(8) + uint8_t elem_kind(1) + pad(7)
 *   + elements(len * elem_size), data 16-byte aligned.
 * elem_kind: 0=i64, 1=f64, 2=f32, 3=i32, 4=u8.
 * Declared here (single definition) so cross-file callers such as
 * march_extras.c never re-#define a second copy — that's exactly how layout
 * drift starts. */
#define NATIVE_ARR_HDR 32
/* The value 32 is HARD-CODED on the codegen side too: lib/tir/llvm_emit.ml
 * emits `arr + 32 + i*elem_size` GEPs directly rather than reading this
 * header, so the two can silently diverge. This assert makes a change here
 * a compile error, at which point the emitter's three NATIVE_ARR_HDR=32
 * comments point at the sites that must be updated in lockstep. */
_Static_assert(NATIVE_ARR_HDR == 32,
               "NATIVE_ARR_HDR is hard-coded as 32 in lib/tir/llvm_emit.ml's "
               "native-array GEPs; update both or the emitted IR is wrong");
#define NATIVE_ELEM_I64 0
#define NATIVE_ELEM_F64 1
#define NATIVE_ELEM_F32 2
#define NATIVE_ELEM_I32 3
#define NATIVE_ELEM_U8  4
/* Allocate a fresh, uninitialised NativeU8Arr of [len] bytes. Non-static so
 * march_extras.c can build one directly instead of duplicating
 * native_arr_alloc (which stays static/private to this file). */
void *native_u8_arr_alloc_raw(int64_t len);
/* An "immortal" refcount: a starting rc so far above any reachable reference
 * count that no sequence of decrements can drive the cell to zero, so it is
 * never freed and never mistaken for uniquely-owned.  Used for cells that
 * belong to the program image rather than to any March binding — currently
 * only compiled-in string literals (march_string_lit_static).  Chosen so
 * that (a) the free-on-zero paths in march_decrc/march_decrc_local can never
 * be reached, (b) the `rc == 1` uniqueness test the FBIP reuse path emits
 * (llvm_emit.ml) is always false, so an immortal cell is never reused in
 * place, and (c) it stays far from INT64_MAX so ordinary increments cannot
 * overflow it. */
#define MARCH_RC_IMMORTAL (INT64_C(1) << 40)
/* One shared, never-freed march_string per compiled-in string literal SITE.
 * [cell] points at a per-site static `void *` slot (emitted as an LLVM global
 * initialised to null); the first call fills it with an immortal string built
 * from [utf8]/[len] and every later call returns that same cell.
 *
 * This exists because a string literal is a CONSTANT in the TIR ownership
 * model: Perceus gives `EAtom (ALit _)` no RC obligation at all (same as a
 * global ADefRef), so codegen must not hand back a fresh rc=1 allocation per
 * evaluation — nothing owns it and nothing ever drops it.  Returning a fresh
 * cell leaked one string per evaluation, so `let s = buf ++ "xyz"` inside a
 * loop grew RSS linearly with the iteration count. */
void *march_string_lit_static(const char *utf8, int64_t len, void **cell);
void *march_int_to_string(int64_t n);
void *march_float_to_string(double f);
void  march_print_int(int64_t n);
void  march_print_float(double f);
int64_t march_char_is_alpha(void *c);
int64_t march_char_is_uppercase(void *c);
int64_t march_char_is_lowercase(void *c);
void *march_char_to_uppercase(void *c);
void *march_char_to_lowercase(void *c);
void *march_bool_to_string(int64_t b);
void *march_string_concat(void *a, void *b);
int64_t march_string_eq(void *a, void *b);
int64_t march_poly_eq(void *a, void *b);
/* Ordered compare (-1/0/1) for two values in type-ERASED (ptr) slots, when
 * the static type gives no strategy. Dispatches on runtime shape: tagged
 * ints, boxed floats (MARCH_FLOAT_TAG), and strings each compare by value;
 * other heap values fall back to 0 (a full structural order needs static
 * type info unavailable here). The generic-compare half of the float-boxing
 * design — must be wired at the codegen fallback_cmp site in the same stage
 * that boxes floats, else box-only turns wrong-int-compare into
 * wrong-pointer-compare. */
int64_t march_poly_compare(void *a, void *b);
/* Extended string builtins used by the compiled stdlib. */
int64_t march_string_byte_length(void *s);
int64_t march_string_byte_at(void *s, int64_t i);
int64_t march_string_is_empty(void *s);
void   *march_string_to_int(void *s);
void   *march_string_join(void *list, void *sep);
void   *march_codepoint_to_utf8(int64_t cp);  /* Encode codepoint as UTF-8, returns Some(string) or None */

/* Terminal actor reason shared by every compiled death path and the local
 * monitor Down ABI. Crash carries its text separately. */
typedef enum {
    MARCH_DEATH_NORMAL = 0,
    MARCH_DEATH_KILLED = 1,
    MARCH_DEATH_CRASH  = 2,
} march_death_reason;

/* Graceful shutdown. march_actor_stop marks the actor draining (new sends are
   refused), lets its green thread finish the queued messages until the mailbox
   empties or timeout_ms elapses, then ends it with MARCH_DEATH_NORMAL. A
   negative timeout waits indefinitely; 0 discards whatever is queued once the
   current handler returns. A supervisor stops its children first, in reverse
   declaration order, each with its own `shutdown` budget from the child spec.
   Contrast march_kill, which is immediate and drops the mailbox. */
int64_t march_actor_stop(void *actor, int64_t timeout_ms);
/* An actor type's `on_stop` callback (its terminate), keyed by the dispatch
   closure every record of that type holds in word 2. Emitted by the spawn
   glue of an actor that declares `on_stop do ... end`; idempotent. The
   callback runs on the actor's own green thread after a graceful drain
   (march_actor_stop) and before the NORMAL death; never after a kill. */
void    march_register_actor_on_stop(void *dispatch_clo, void *on_stop_clo);
/* The `receive()` builtin: march_sched_recv, but a stop ends the proc
 * (an actor: through its stop_jmp) instead of returning the no-message
 * sentinel to user code.  See actor_green_thread. */
void   *march_actor_recv(void);

/* Process enumeration: List(Int) of every live actor's pid index, ascending.
   Lock-free (same bucket walk as find_meta); a snapshot, so inherently racy.
   March turns these back into Pids with pid_of_int. */
void *march_actor_pid_indices(void);
int64_t march_actor_is_draining(void *actor);

/* register_supervisor: record an actor as a supervisor with a given restart
   strategy (0=one_for_one, 1=one_for_all, 2=rest_for_one), max_restarts, and
   time window in seconds.  Children are registered separately via
   march_actor_register_child. */
void    march_register_supervisor(void *supervisor, int64_t strategy,
                                   int64_t max_restarts, int64_t window_secs,
                                   int64_t backoff_base_ms,
                                   int64_t backoff_cap_ms,
                                   int64_t backoff_jitter_pct);

/* ── Phase 5: Actor state migration ─────────────────────────────────── */

/* Tag value for system migrate messages.  Chosen to be far outside the range
 * of normal March ADT constructor tags (which start at 0 and are bounded by
 * the number of constructors per type, typically < 1000). */
#define MARCH_MIGRATE_TAG ((int64_t)0x4D494752L)   /* "MIGR" */

/* System message injected into an actor's mailbox to trigger state migration.
 * Layout: standard 16-byte march object header (rc at 0, tag at 8) so that
 * actor_green_thread can detect it by checking ((int64_t*)msg)[1].
 * Allocated with malloc() by march_actor_publish_migrating /
 * march_actor_broadcast_migrate; freed with free() (NOT march_decrc) by
 * actor_green_thread after handling.
 *
 * Legacy (march_actor_broadcast_migrate / march_actor_inject_migrate_msg):
 * deploys use epoch markers, which are mailbox-node flags (march_mbox_node.
 * marker), not messages.  [meta] and [pin] are unused, always NULL/0. */
typedef struct {
    int64_t  _rc;              /* always 1 (not reference-counted) */
    int64_t  _tag;             /* MARCH_MIGRATE_TAG */
    void    *(*migrate_fn)(void *);  /* migrate_fn(old_state_ptr) → new_state_ptr, or NULL */
    void    *meta;             /* target's march_actor_meta, or NULL */
    uint32_t pin;              /* pinned ring version + 1, or 0 */
} march_migrate_msg_t;

/* Set the dispatch-table NAME_ID for a hot-reload actor.  Must be called
 * immediately after march_spawn().  name_id is the slot ID registered for
 * the actor's _dispatch function.  No-op if actor has no meta entry. */
void march_actor_set_dispatch_id(void *actor, uint32_t name_id);

/* Register the global tag of the actor's FIRST message constructor (its
 * "call tag base").  Emitted by codegen right after the actor record's
 * alloc; march_actor_call adds the sentinel's ctor index to this base to
 * address the handler positionally under F19's globally-unique msg tags. */
void march_actor_set_call_tags(void *actor, const int32_t *tags, int64_t n);

/* ── The unified epoch model: activation, markers, holds, drains ─────────
 * specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md, II.4.
 *
 * One activated function of a deploy.  [migrate_fn]: the actor's
 * __migrate_<Actor> (state, old -> new), or NULL.  [migrate_msg_fn]: its
 * __migrate_msg_<Actor> wrapper, called as fn(old_msg, sentinel) and
 * returning the converted message, or [sentinel] for None.  [state_changed] /
 * [msgs_changed]: what the deploy's schema diff says changed for this
 * actor.  [handle]: the dlopen handle the version will own (NULL in tests).
 * [ring_idx] is filled in. */
typedef struct {
    uint32_t    slot;
    void       *fn;
    const char *impl_hash;
    const char *sig_hash;
    uint8_t     kind;
    void     *(*migrate_fn)(void *);
    void     *(*migrate_msg_fn)(void *, void *);
    int         state_changed;
    int         msgs_changed;
    void       *handle;
    int         ring_idx;
} march_hcr_unit;

/* Why an activation could not proceed yet (MARCH_HCR_WAIT): the oldest
 * pinned epoch, its pinned units, and the hard drain deadline covering it in
 * ms from now (-1 = none armed). */
typedef struct {
    uint32_t epoch;
    int64_t  pins;
    int64_t  deadline_ms;
    int      table_full;   /* 1: the epoch pin table has no free entry */
} march_hcr_wait;

#define MARCH_HCR_WAIT  (-1)
#define MARCH_HCR_ERROR (-2)

/* Activate [n] functions as ONE deploy (II.4.6): stage each into its slot
 * (live = 0), commit them all (live, current), advance the current epoch to
 * the deploy's epoch (march_epoch_next(requested_epoch)), then put an epoch
 * marker in EVERY live actor's user mailbox.  Each actor runs whatever it
 * already had queued at its own (old) epoch and moves at its marker,
 * applying the state migrations of every deploy it passes, in order.
 * Afterwards a soft drain of the older epochs is armed ([soft_ms]/[hard_ms];
 * < 0 = $MARCH_HCR_DRAIN_MS / $MARCH_HCR_HARD_DRAIN_MS, else the defaults;
 * 0 = none).  Returns the deploy's epoch (> 0), MARCH_HCR_WAIT with [wait]
 * filled when some slot has no reclaimable version or the pin table is
 * full (nothing changed), or MARCH_HCR_ERROR (nothing changed). */
int march_hcr_activate(march_hcr_unit *units, int n, uint32_t requested_epoch,
                       int64_t soft_ms, int64_t hard_ms, march_hcr_wait *wait);

/* A one-function migrating activation (the #564 entry point, kept for
 * tests): march_hcr_activate with state_changed = 1.  Returns the ring index,
 * or -1 (waiting or failed; nothing changed). */
#define MARCH_HCR_DRAIN_MS_DEFAULT 5000
int march_actor_publish_migrating(uint32_t dispatch_name_id, void *fn_ptr,
                                  const char *impl_hash, const char *sig_hash,
                                  uint8_t kind, uint32_t epoch,
                                  void *(*migrate_fn)(void *), int64_t drain_ms);

/* Drain every epoch <= [upto] (II.4.7, the DRAIN verb): at the soft deadline
 * each actor still pinned there with no epoch holds advances at once (a
 * forced marker; its remaining old-format messages take the migrate_msg path
 * or are dropped and counted); at the hard deadline every actor pinned there
 * is killed (its supervisor restarts it at the current epoch) and every other
 * proc pinned there is told to stop.  0 ms = that deadline is not armed. */
void march_hcr_drain(uint32_t upto, int64_t soft_ms, int64_t hard_ms);
/* 1 iff [epoch] is covered by an armed drain (SessionNode reads this to start
 * its D27 loop-boundary drains). */
int  march_hcr_epoch_draining(uint32_t epoch);

/* Epoch holds (D28, II.4.4) on the current proc; see march_proc.epoch_holds.
 * Called through the stdlib-only builtins epoch_hold()/epoch_release(). */
void     march_epoch_hold(void);
void     march_epoch_release(void);
uint32_t march_epoch_holds(void);
/* D27: 1 iff the running proc's code epoch is draining (stdlib-only builtin
 * epoch_draining(), read by SessionNode at a loop-boundary delivery). */
int64_t  march_epoch_draining(void);
int64_t  march_epoch_holds_i64(void);
/* Follow-up 1: the hook the actor loop calls when it drops a REMOTE delivery
 * (stdlib-only delivery_failed_watch(f): f(conn, seq, reason)), and how many
 * drops it has reported.  The origin builtins are march_sched_delivery_origin_*
 * (march_scheduler.h). */
void     march_delivery_failed_watch(void *clo);
int64_t  march_delivery_failed_reported(void);
/* Drain every epoch up to the current one (stdlib-only epoch_drain). */
void     march_epoch_drain(int64_t soft_ms, int64_t hard_ms);

/* Process-wide counters, reported by the reload server's PINS verb. */
typedef struct {
    int64_t deferred;     /* newer-format messages a held actor set aside */
    int64_t converted;    /* old-format messages migrate_msg converted */
    int64_t dropped;      /* old messages dropped (no migrate_msg, or None) */
    int64_t killed;       /* actors killed at a hard drain deadline */
    int64_t stopped;      /* other procs told to stop at a hard deadline */
    int64_t advances;     /* actor epoch advances (markers, early, forced) */
    int64_t early;        /* of which D30 early advances */
    int64_t forced;       /* of which soft-deadline forced markers */
    int64_t markers_lost; /* markers that could not be enqueued (OOM) */
} march_hcr_counters;
void march_hcr_counters_get(march_hcr_counters *out);

/* Old messages dropped (a drain, or an old-format message with no
 * migrate_msg), process-wide.  Kept under its #564 name. */
int64_t march_hcr_drain_dropped(void);

/* Test seam: when set, march_hcr_activate calls it after advancing the
 * current epoch and BEFORE it marks the actors -- the window in which a
 * sender that already runs at the new epoch can put a message ahead of a
 * receiver's marker (D30).  NULL in production. */
extern void (*march_hcr_test_before_mark)(uint32_t epoch);

/* Test seam: march_send with the message stamped [epoch], as a sender
 * pinned to that epoch would send it. */
void *march_hcr_test_send_stamped(void *actor, void *msg, uint32_t epoch);

/* Epoch markers enqueued and not yet consumed or disposed.  0 at rest. */
int64_t march_hcr_markers_live(void);

/* Walk all live actors whose dispatch_name_id equals [dispatch_name_id] and
 * inject a MARCH_MIGRATE_TAG message so each actor migrates its state on
 * the next turn.  migrate_fn may be NULL (skip state transform).
 *
 * Legacy, no ordering guarantee: an ordinary user message, not an epoch
 * marker, and it moves no epoch.  A deploy must use march_hcr_activate. */
void march_actor_broadcast_migrate(uint32_t dispatch_name_id,
                                   void *(*migrate_fn)(void *));

/* Phase 2 of march_actor_broadcast_migrate for ONE target: malloc a migrate
 * message, march_sched_send it to [green_thread] (a march_proc*), and free
 * it again if the send reports MARCH_SEND_DEAD (the only status on which the
 * caller keeps ownership). Returns the send status, or -1 on malloc failure.
 * Exposed so the leak regression test can drive the real code path. */
int march_actor_inject_migrate_msg(void *green_thread,
                                   void *(*migrate_fn)(void *));

/* Number of migrate messages allocated and not yet disposed on any of their
 * disposal paths (DEAD-send free, receive-loop free, reap-time dispose).
 * Zero at rest; a leak leaves it positive. */
int64_t march_migrate_msgs_live(void);

/* Test-only seam: bind [actor]'s meta green_thread to [proc] (a march_proc*)
 * without spawning an actor green thread. Not used by generated code. */
void march_test_actor_bind_green_thread(void *actor, void *proc);
/* Test seam: the record address pid index [n] named, live or dead, from its
 * tombstone, WITHOUT taking a reference (NULL if no actor was given [n]).
 * Dereferenceable only by a caller that holds its own reference to that
 * record (march_ffi.c's ffi_test_actor_rc). */
void *march_test_actor_addr_of_pid(int64_t n);

/* Actor builtins.
 * Actor object layout (on top of the standard 16-byte header):
 *   offset 16: ptr     dispatch fn  (field 0, stored as closure struct)
 *   offset 24: int64_t alive flag   (field 1; 1=alive, 0=dead)
 *   offset 32+: state fields        (fields 2+, alphabetical order)
 *   -- in --hot-reload builds only:
 *   offset 32: ptr     state record (field 2, $f_state ptr, replaces inline fields)
 * As int64_t array: [0]=rc [1]=tag+pad [2]=dispatch [3]=alive [4+]=state
 *   (hot-reload: [4]=ptr-to-state-record instead of inline state fields) */
void    march_kill(void *actor);
int64_t march_is_alive(void *actor);
void    march_dist_monitor_register_pid(int64_t target_pid, void *node_str, int64_t watcher_pid, int64_t fd);
void   *march_actor_terminal_reason(int64_t pid_index);
void   *march_dist_monitor_pending(void);
void    march_dist_monitor_ack_pid(int64_t target_pid, int64_t watcher_pid);
int64_t march_dist_monitor_forget_node_str(void *node_str);
/* Register an actor with the scheduler; returns actor unchanged. */
void    march_set_actor_caps(void *actor, void *caps);
void   *march_actor_caps(void *actor);
void   *march_spawn(void *actor);
/* Internal compiler/runtime handshake for supervise-block children: assign a
 * Pid/meta now, but do not schedule the actor loop until register_child has
 * published its supervisor and restart slot. */
void   *march_spawn_supervised(void *actor);
/* Read word at int64_t index from actor struct (0=rc,1=tag,2=dispatch,...). */
int64_t march_actor_get_int(void *actor, int64_t index);
/* Send a message (takes ownership of msg's RC).
 * Returns Option(Unit): None (tag 0) if dead, Some(()) (tag 1) if enqueued. */
void   *march_send(void *actor, void *msg);
/* Process all actors in the run queue (called automatically by march_send). */
void    march_run_scheduler(void);
/* Named process registry (named-registry plan, Task 3). Forward table is a
 * runtime-owned Vault table; reverse index lives on march_actor_meta.
 * See the design comment above registry_init_once in march_runtime.c. */
int64_t march_actor_register(void *name_str, void *actor);   /* 1 ok, 0 taken/dead */
int64_t march_actor_unregister(void *name_str);               /* 1 removed, 0 absent */
void   *march_actor_whereis(void *name_str);   /* Option(actor): niche-encoded */
void   *march_actor_registered(void);          /* List(String) of live names */
/* do_actor_death (Task 5) calls this on a dying actor to drop every name it
 * still holds from the forward table (compare-and-drop: only if the table
 * still maps the name to THIS actor — see the definition in
 * march_runtime.c). Exported so a C-level test can exercise the Critical
 * fix-up (stale-overwrite vs. retire ordering) directly. */
void    registry_retire_actor(void *actor);
/* Spawn a no-arg C function as a green thread (for the main entrypoint). */
/* Self-imposed capability sandbox (opt-in, --cap-sandbox). No-op unless
 * MARCH_CAP_PROFILE was defined at build time. See runtime/march_sandbox.c. */
void    march_sandbox_install(void);
void    march_spawn_main(void (*fn)(void));
/* --pin-main: run `main` only on scheduler 0 (the process main thread),
   without depending on MARCH_PIN_MAIN being set in the environment. */
void march_spawn_main_pinned(void (*fn)(void));
/* Signal.watch (stdlib/signal.march): register/remove a deferred OS-signal
 * watcher (closure passed OWNED), send a signal to self, and drain pending
 * watchers from a scheduler / event-loop body (never from signal context). */
void    march_signal_watch(int64_t code, void *clo);
void    march_signal_unwatch(int64_t code);
void    march_signal_raise_self(int64_t code);
void    march_signal_drain(void);
/* sigaction(SA_ONSTACK|SA_RESTART) for a handler that may fire on a green
 * thread's small stack — never plain signal(); see its definition. */
void    march_install_async_signal(int sig, void (*handler)(int));
/* Spawn a March thunk closure (fn () -> T) as an async green thread.
 * Returns a boxed Task handle (32 bytes: header + proc ptr + result ptr). */
void   *march_task_spawn_thunk(void *clo_ptr);
/* Wait for a task to complete; returns Ok(result) or Err(msg). */
void   *march_task_await(void *task_obj);
/* Spawn a thunk closure with a cancel token; yields cancel checks. */
void   *march_task_spawn_with_cancel_thunk(void *clo_ptr, void *tok_ptr);
/* Mark a task's green thread as DEAD (cooperative cancel). */
void    march_task_cancel_by_id(void *task_obj);
/* Tasks a hard drain deadline cancelled through their handle (follow-up 4). */
int64_t march_tasks_cancelled(void);

/* Float builtins. */
double  march_float_abs(double f);
int64_t march_float_ceil(double f);
int64_t march_float_floor(double f);
int64_t march_float_round(double f);
int64_t march_float_truncate(double f);
double  march_int_to_float(int64_t n);

/* Math builtins. */
double march_math_sin(double f);
double march_math_cos(double f);
double march_math_tan(double f);
double march_math_asin(double f);
double march_math_acos(double f);
double march_math_atan(double f);
double march_math_atan2(double y, double x);
double march_math_sinh(double f);
double march_math_cosh(double f);
double march_math_tanh(double f);
double march_math_sqrt(double f);
double march_math_cbrt(double f);
double march_math_exp(double f);
double march_math_exp2(double f);
double march_math_log(double f);
double march_math_log2(double f);
double march_math_log10(double f);
double march_math_pow(double b, double e);

/* Extended string builtins. */
int64_t march_string_contains(void *s, void *sub);
int64_t march_string_starts_with(void *s, void *prefix);
int64_t march_string_ends_with(void *s, void *suffix);
void   *march_string_slice(void *s, int64_t start, int64_t len);
void   *march_string_split(void *s, void *sep);
void   *march_string_split_first(void *s, void *sep);
void   *march_string_replace(void *s, void *old, void *new_);
void   *march_string_replace_all(void *s, void *old, void *new_);
void   *march_string_to_lowercase(void *s);
void   *march_string_to_uppercase(void *s);
void   *march_string_trim(void *s);
void   *march_string_trim_start(void *s);
void   *march_string_trim_end(void *s);
void   *march_string_repeat(void *s, int64_t n);
void   *march_string_reverse(void *s);
void   *march_string_pad_left(void *s, int64_t width, void *fill);
void   *march_string_pad_right(void *s, int64_t width, void *fill);
int64_t march_string_grapheme_count(void *s);
void   *march_string_index_of(void *s, void *sub);
void   *march_string_last_index_of(void *s, void *sub);
void   *march_string_to_float(void *s);

/* List builtins. */
void *march_list_append(void *a, void *b);
void *march_list_concat(void *lists);

/* File/Dir builtins. */
int64_t march_file_exists(void *s);
int64_t march_dir_exists(void *s);
void   *march_file_open(void *path);
int64_t march_file_close(void *handle);
void   *march_file_read(void *path);
void   *march_file_read_line(void *handle);
void   *march_file_read_chunk(void *handle, int64_t size);
void   *march_file_write(void *path, void *data);
void   *march_file_append(void *path, void *data);
void   *march_file_delete(void *path);
void   *march_file_copy(void *src, void *dst);
void   *march_file_rename(void *src, void *dst);
void   *march_file_stat(void *path);

/* CSV builtins. */
void   *march_csv_open(void *path, void *delim, void *mode);
void   *march_csv_next_row(void *handle);
int64_t march_csv_close(void *handle);

/* Resource ownership. */
void    march_own(void *pid, void *value);

/* Capability revocation (Phase 3).  All three take the March-level Cap heap
 * object (words: hdr, hdr, actor ptr, pid_index, epoch — built by
 * march_get_cap), matching the interpreter's Cap(a)-typed builtins. */
/* Explicitly revoke a capability.  After this call, march_send_checked and
 * march_is_cap_valid reject the cap.  Idempotent.  Returns the :ok atom
 * (:error for a null/non-heap cap such as the root_cap sentinel). */
int64_t march_revoke_cap(void *cap);
/* Check whether cap is still valid:
 * returns 1 if valid (actor alive, epoch matches, not revoked), 0 otherwise. */
int64_t march_is_cap_valid(void *cap);
/* Capability-checked send: validates liveness, epoch, and revocation before
 * enqueuing msg.  Returns the :ok atom on delivery, :error otherwise. */
int64_t march_send_checked(void *cap, void *msg);

/* Value pretty-printing.  Two conventions, differing ONLY in how a string
 * NESTED inside a rendered constructor is printed (a top-level String is
 * returned verbatim by both):
 *   show (repr == 0)  the interpreter's `to_string`/Show: a nested string is
 *                     bare inside List/Option/Result (their Show impls call
 *                     show on the element), quoted inside any other
 *                     constructor or record (no Show impl -> repr fallback).
 *   repr (repr == 1)  the interpreter's value_to_string, which `~H` holes
 *                     use: every nested string is quoted.
 * [march_value_to_string] is the show form -- it is the erased `to_string`
 * and Show$String.show. */
void *march_value_to_string(void *v);
void *march_value_to_string_repr(void *v);
void *march_value_to_string_mode(void *v, int repr);

/* Constructor-name metadata for compiled `to_string` on a user ADT.
 * [march_ctor_table_ensure] registers one compilation unit's descriptor
 * string (grammar and field-token alphabet documented at the implementation
 * in runtime/march_extras.c, written by lib/tir/llvm_ctor_desc.ml) and
 * returns the base index its types were appended at; [cache] memoizes
 * base+1.  [march_value_to_string_typed] renders [v] as the type with that
 * (already rebased) id, falling back to [march_value_to_string] for any
 * shape the table cannot describe. */
int32_t march_ctor_table_ensure(const char *desc, int32_t *cache);
void *march_value_to_string_typed(void *v, int32_t type_id);

/* Process builtins */
void  march_process_argv_init(int argc, char **argv);
void *march_process_argv(void);

/* Vault builtins (march_extras.c). */
void   *march_vault_new(void *name);
void   *march_vault_whereis(void *name);
void   *march_vault_set(void *table, void *key, void *value);
void   *march_vault_set_ttl(void *table, void *key, void *value, int64_t ttl_secs);
void   *march_vault_get(void *table, void *key);
void   *march_vault_drop(void *table, void *key);
void   *march_vault_update(void *table, void *key, void *f);
int64_t march_vault_size(void *table);
void   *march_vault_keys(void *table);
/* String-namespace helpers: accept a String name, auto-create/find vault. */
void   *march_vault_ns_set(void *ns, void *key, void *value);
void   *march_vault_ns_get(void *ns, void *key);
void   *march_vault_ns_drop(void *ns, void *key);

/* Crypto builtins (march_extras.c). */
void   *march_sha256(void *data);          /* String -> hex String */
void   *march_sha256_of_bytes(void *b);    /* Bytes  -> hex String */
void   *march_sha512(void *data);
void   *march_hmac_sha256(void *key, void *msg);
/* ed25519 / X25519 over the vendored TweetNaCl (runtime/march_nacl.c). */
void   *march_ed25519_seed_keypair(void *seed);
void   *march_ed25519_sign(void *sk, void *msg);
int64_t march_ed25519_verify(void *pk, void *msg, void *sig);
void   *march_x25519(void *scalar, void *point);
void   *march_pbkdf2_sha256(void *pass, void *salt, int64_t iters, int64_t dklen);
void   *march_base64_encode(void *input);
void   *march_base64_decode(void *str);
void   *march_random_bytes(int64_t n);
void   *march_uuid_v4(void);
void   *march_uuid_v7(void);
void   *march_uuid_v7_at(int64_t ts_ms);
/* DNS lookup (march_runtime.c): Result(List(String), String); borrows host. */
void   *march_dns_resolve(void *host);

/* System introspection builtins (march_extras.c). */
int64_t march_sys_uptime_ms(void);
int64_t march_sys_cpu_count(void);
int64_t march_sys_heap_bytes(void);
int64_t march_sys_word_size(void);
int64_t march_sys_minor_gcs(void);
int64_t march_sys_major_gcs(void);
int64_t march_sys_actor_count(void);
void   *march_sys_os(void);
void   *march_sys_arch(void);

/* Session-typed channel builtins (binary). */
void   *march_chan_new(void *proto_name);
void   *march_chan_send(void *ep, void *val);
void   *march_chan_recv(void *ep);
int64_t march_chan_close(void *ep);
void   *march_chan_choose(void *ep, void *label);
void   *march_chan_offer(void *ep);

/* Multi-party session type (MPST) builtins. */
void   *march_mpst_new(void *proto_name, int64_t n_roles, void *roles_csv);
void   *march_mpst_send(void *ep, void *target_role_str, void *val);
void   *march_mpst_recv(void *ep, void *source_role_str);
int64_t march_mpst_close(void *ep);

/* Test harness — used by --test compiled binaries. */
extern jmp_buf  march_test_jmp_buf;
extern int      march_test_in_test;
extern char     march_test_fail_buf[4096];
void    march_test_init(int32_t argc, char **argv);
void    march_test_setup_all(void (*fn)(void));
void    march_test_run(void (*fn)(void), const char *name, void (*setup)(void));
int32_t march_test_report(void);
