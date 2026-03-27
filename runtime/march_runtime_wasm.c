/**
 * march_runtime_wasm.c — Minimal March runtime for wasm32-unknown-unknown.
 *
 * This is a stripped-down runtime for browser WASM targets.  It provides:
 *   - Bump allocator (linear memory, no free)
 *   - Reference counting (no-ops in single-threaded WASM)
 *   - String operations (lit, concat, eq, conversion, etc.)
 *   - Math builtins (delegates to libm or wasm intrinsics)
 *   - Panic (calls __wasm_unreachable)
 *   - No actors, no networking, no file I/O, no threads
 *
 * Compiled with: clang --target=wasm32-unknown-unknown -nostdlib -DMARCH_WASM
 */

#include <stdint.h>
#include <stddef.h>

/* ── Memory management ──────────────────────────────────────────────── */

/* Simple bump allocator over WASM linear memory.
   WASM pages are 64KB.  We grow as needed via __builtin_wasm_memory_grow. */

static unsigned char *heap_ptr = 0;
static unsigned char *heap_end = 0;

static void ensure_heap(size_t needed) {
    if (heap_ptr == 0) {
        /* First allocation: start at 1MB offset to avoid collisions with stack/data */
        int pages = __builtin_wasm_memory_size(0);
        heap_ptr = (unsigned char *)(pages * 65536);
        heap_end = heap_ptr;
    }
    while ((size_t)(heap_end - heap_ptr) + needed > (size_t)(heap_end - (unsigned char*)0)) {
        /* Simplified: just grow by enough pages */
        int grow_pages = (needed / 65536) + 2;
        int old = __builtin_wasm_memory_grow(0, grow_pages);
        if (old < 0) __builtin_trap();  /* OOM */
        heap_end = (unsigned char *)((old + grow_pages) * 65536);
    }
}

/* Bump allocator — allocated memory is never freed (GC TBD for WASM). */
void *march_alloc(int64_t sz) {
    size_t align_sz = (((size_t)sz + 7) & ~(size_t)7);  /* 8-byte align */
    if (heap_ptr == 0 || heap_ptr + align_sz > heap_end) {
        int grow_pages = (align_sz / 65536) + 2;
        int old_pages = __builtin_wasm_memory_size(0);
        int result = __builtin_wasm_memory_grow(0, grow_pages);
        if (result < 0) __builtin_trap();
        if (heap_ptr == 0) {
            heap_ptr = (unsigned char *)(old_pages * 65536);
        }
        heap_end = (unsigned char *)((old_pages + grow_pages) * 65536);
    }
    unsigned char *p = heap_ptr;
    heap_ptr += align_sz;
    /* Zero-initialize (RC = 0, tag = 0, fields = 0) */
    for (size_t i = 0; i < align_sz; i++) p[i] = 0;
    return p;
}

/* RC ops are no-ops in single-threaded WASM */
void  march_incrc(void *p) { (void)p; }
void  march_decrc(void *p) { (void)p; }
int64_t march_decrc_freed(void *p) { (void)p; return 0; }
void  march_incrc_local(void *p) { (void)p; }
void  march_decrc_local(void *p) { (void)p; }
void  march_free(void *p) { (void)p; /* no-op bump alloc */ }

/* ── String representation ──────────────────────────────────────────── */

/* March strings: 16-byte heap header + 8-byte length slot + 8-byte data ptr slot.
   This matches the object layout: offset 0 = RC (i64), offset 8 = tag (i32) + pad,
   offset 16 = field[0] (length as i64), offset 24 = field[1] (ptr to chars).

   For WASM island boundary, the JS glue uses a simpler 4-byte-prefix format
   for passing strings across the WASM/JS boundary.  The runtime strings are
   the internal representation; the island exports handle conversion. */

typedef struct {
    int64_t rc;
    int32_t tag;
    int32_t pad;
    int64_t length;
    char   *data;
} march_string;

void *march_string_lit(const char *s, int64_t len) {
    march_string *str = (march_string *)march_alloc(sizeof(march_string));
    str->length = len;
    str->data = (char *)s;  /* string literals live in static data segment */
    return str;
}

int64_t march_string_eq(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    if (sa->length != sb->length) return 0;
    for (int64_t i = 0; i < sa->length; i++) {
        if (sa->data[i] != sb->data[i]) return 0;
    }
    return 1;
}

void *march_string_concat(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    int64_t new_len = sa->length + sb->length;
    char *buf = (char *)march_alloc(new_len + 1);
    for (int64_t i = 0; i < sa->length; i++) buf[i] = sa->data[i];
    for (int64_t i = 0; i < sb->length; i++) buf[sa->length + i] = sb->data[i];
    buf[new_len] = '\0';
    march_string *result = (march_string *)march_alloc(sizeof(march_string));
    result->length = new_len;
    result->data = buf;
    return result;
}

int64_t march_string_byte_length(void *s) {
    return ((march_string *)s)->length;
}

int64_t march_string_is_empty(void *s) {
    return ((march_string *)s)->length == 0 ? 1 : 0;
}

/* ── Numeric → String conversion ────────────────────────────────────── */

/* Minimal int-to-string without libc sprintf */
static int i64_to_buf(int64_t n, char *buf) {
    if (n == 0) { buf[0] = '0'; return 1; }
    int neg = 0;
    uint64_t v;
    if (n < 0) { neg = 1; v = (uint64_t)(-n); } else { v = (uint64_t)n; }
    char tmp[21];
    int len = 0;
    while (v > 0) { tmp[len++] = '0' + (char)(v % 10); v /= 10; }
    int pos = 0;
    if (neg) buf[pos++] = '-';
    for (int i = len - 1; i >= 0; i--) buf[pos++] = tmp[i];
    return pos;
}

void *march_int_to_string(int64_t n) {
    char buf[22];
    int len = i64_to_buf(n, buf);
    char *data = (char *)march_alloc(len + 1);
    for (int i = 0; i < len; i++) data[i] = buf[i];
    data[len] = '\0';
    march_string *s = (march_string *)march_alloc(sizeof(march_string));
    s->length = len;
    s->data = data;
    return s;
}

void *march_float_to_string(double f) {
    /* Minimal float formatting — integer part + up to 6 decimal places */
    char buf[64];
    int pos = 0;
    if (f < 0) { buf[pos++] = '-'; f = -f; }
    int64_t ipart = (int64_t)f;
    double fpart = f - (double)ipart;
    pos += i64_to_buf(ipart, buf + pos);
    buf[pos++] = '.';
    for (int d = 0; d < 6; d++) {
        fpart *= 10.0;
        int digit = (int)fpart;
        buf[pos++] = '0' + digit;
        fpart -= digit;
    }
    /* Trim trailing zeros (keep at least one decimal) */
    while (pos > 2 && buf[pos-1] == '0' && buf[pos-2] != '.') pos--;
    char *data = (char *)march_alloc(pos + 1);
    for (int i = 0; i < pos; i++) data[i] = buf[i];
    data[pos] = '\0';
    march_string *s = (march_string *)march_alloc(sizeof(march_string));
    s->length = pos;
    s->data = data;
    return s;
}

void *march_bool_to_string(int64_t b) {
    if (b) return march_string_lit("true", 4);
    return march_string_lit("false", 5);
}

/* ── String search/manipulation stubs ───────────────────────────────── */

void *march_string_to_int(void *s) {
    march_string *str = (march_string *)s;
    int64_t result = 0;
    int neg = 0;
    int64_t i = 0;
    if (str->length > 0 && str->data[0] == '-') { neg = 1; i = 1; }
    for (; i < str->length; i++) {
        char c = str->data[i];
        if (c < '0' || c > '9') break;
        result = result * 10 + (c - '0');
    }
    if (neg) result = -result;
    /* Return Some(result) — allocate a variant with tag 1 (Some) */
    void *box = march_alloc(24);  /* header(16) + 1 field(8) */
    *(int32_t *)((char *)box + 8) = 1;  /* tag = Some */
    *(int64_t *)((char *)box + 16) = result;
    return box;
}

void *march_string_join(void *list, void *sep) {
    /* Simplified: walk Cons list, concat with separator */
    march_string *sep_s = (march_string *)sep;
    void *result = march_string_lit("", 0);
    int first = 1;
    void *cur = list;
    while (1) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break;  /* Nil */
        void *head = *(void **)((char *)cur + 16);
        void *tail = *(void **)((char *)cur + 24);
        if (!first && sep_s->length > 0) {
            result = march_string_concat(result, sep);
        }
        result = march_string_concat(result, head);
        first = 0;
        cur = tail;
    }
    return result;
}

/* Extended string builtins — minimal implementations */
int64_t march_string_contains(void *s, void *sub) {
    march_string *str = (march_string *)s;
    march_string *sub_s = (march_string *)sub;
    if (sub_s->length == 0) return 1;
    if (sub_s->length > str->length) return 0;
    for (int64_t i = 0; i <= str->length - sub_s->length; i++) {
        int match = 1;
        for (int64_t j = 0; j < sub_s->length; j++) {
            if (str->data[i+j] != sub_s->data[j]) { match = 0; break; }
        }
        if (match) return 1;
    }
    return 0;
}

int64_t march_string_starts_with(void *s, void *prefix) {
    march_string *str = (march_string *)s;
    march_string *pre = (march_string *)prefix;
    if (pre->length > str->length) return 0;
    for (int64_t i = 0; i < pre->length; i++) {
        if (str->data[i] != pre->data[i]) return 0;
    }
    return 1;
}

int64_t march_string_ends_with(void *s, void *suffix) {
    march_string *str = (march_string *)s;
    march_string *suf = (march_string *)suffix;
    if (suf->length > str->length) return 0;
    int64_t off = str->length - suf->length;
    for (int64_t i = 0; i < suf->length; i++) {
        if (str->data[off + i] != suf->data[i]) return 0;
    }
    return 1;
}

/* Remaining string stubs — return empty or identity for now */
void *march_string_slice(void *s, int64_t start, int64_t len) {
    march_string *str = (march_string *)s;
    if (start >= str->length || len <= 0) return march_string_lit("", 0);
    if (start + len > str->length) len = str->length - start;
    char *data = (char *)march_alloc(len + 1);
    for (int64_t i = 0; i < len; i++) data[i] = str->data[start + i];
    data[len] = '\0';
    march_string *result = (march_string *)march_alloc(sizeof(march_string));
    result->length = len;
    result->data = data;
    return result;
}

void *march_string_split(void *s, void *sep) { (void)s; (void)sep; return march_alloc(24); /* Nil */ }
void *march_string_split_first(void *s, void *sep) { (void)sep; return s; }
void *march_string_replace(void *s, void *old, void *new_) { (void)old; (void)new_; return s; }
void *march_string_replace_all(void *s, void *old, void *new_) { (void)old; (void)new_; return s; }
void *march_string_to_lowercase(void *s) { return s; }
void *march_string_to_uppercase(void *s) { return s; }
void *march_string_trim(void *s) { return s; }
void *march_string_trim_start(void *s) { return s; }
void *march_string_trim_end(void *s) { return s; }
void *march_string_repeat(void *s, int64_t n) { (void)n; return s; }
void *march_string_reverse(void *s) { return s; }
void *march_string_pad_left(void *s, int64_t w, void *f) { (void)w; (void)f; return s; }
void *march_string_pad_right(void *s, int64_t w, void *f) { (void)w; (void)f; return s; }
int64_t march_string_grapheme_count(void *s) { return ((march_string *)s)->length; }
void *march_string_index_of(void *s, void *sub) { (void)s; (void)sub; return march_alloc(24); /* None */ }
void *march_string_last_index_of(void *s, void *sub) { (void)s; (void)sub; return march_alloc(24); /* None */ }
void *march_string_to_float(void *s) { (void)s; return march_alloc(24); /* None */ }

/* ── Comparison / hash builtins ─────────────────────────────────────── */

int64_t march_compare_int(int64_t x, int64_t y) {
    return x < y ? -1 : x > y ? 1 : 0;
}
int64_t march_compare_float(double x, double y) {
    return x < y ? -1 : x > y ? 1 : 0;
}
int64_t march_compare_string(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    int64_t min = sa->length < sb->length ? sa->length : sb->length;
    for (int64_t i = 0; i < min; i++) {
        if (sa->data[i] < sb->data[i]) return -1;
        if (sa->data[i] > sb->data[i]) return 1;
    }
    return march_compare_int(sa->length, sb->length);
}

int64_t march_hash_int(int64_t x) {
    uint64_t v = (uint64_t)x;
    v ^= v >> 33; v *= 0xff51afd7ed558ccdULL;
    v ^= v >> 33; v *= 0xc4ceb9fe1a85ec53ULL;
    v ^= v >> 33;
    return (int64_t)v;
}
int64_t march_hash_float(double x) { union { double d; int64_t i; } u; u.d = x; return march_hash_int(u.i); }
int64_t march_hash_string(void *s) {
    march_string *str = (march_string *)s;
    uint64_t h = 14695981039346656037ULL;
    for (int64_t i = 0; i < str->length; i++) {
        h ^= (uint64_t)(unsigned char)str->data[i];
        h *= 1099511628211ULL;
    }
    return (int64_t)h;
}
int64_t march_hash_bool(int64_t b) { return b ? 1 : 0; }

/* ── Float builtins ─────────────────────────────────────────────────── */

/* WASM has native f64 instructions for most of these */
double march_float_abs(double f) { return f < 0 ? -f : f; }
int64_t march_float_ceil(double f) { return (int64_t)__builtin_ceil(f); }
int64_t march_float_floor(double f) { return (int64_t)__builtin_floor(f); }
int64_t march_float_round(double f) { return (int64_t)__builtin_round(f); }
int64_t march_float_truncate(double f) { return (int64_t)__builtin_trunc(f); }
double march_int_to_float(int64_t n) { return (double)n; }

/* ── Math builtins ──────────────────────────────────────────────────── */

double march_math_sin(double f)  { return __builtin_sin(f); }
double march_math_cos(double f)  { return __builtin_cos(f); }
double march_math_tan(double f)  { return __builtin_tan(f); }
double march_math_asin(double f) { return __builtin_asin(f); }
double march_math_acos(double f) { return __builtin_acos(f); }
double march_math_atan(double f) { return __builtin_atan(f); }
double march_math_atan2(double y, double x) { return __builtin_atan2(y, x); }
double march_math_sinh(double f) { return __builtin_sinh(f); }
double march_math_cosh(double f) { return __builtin_cosh(f); }
double march_math_tanh(double f) { return __builtin_tanh(f); }
double march_math_sqrt(double f) { return __builtin_sqrt(f); }
double march_math_cbrt(double f) { return __builtin_cbrt(f); }
double march_math_exp(double f)  { return __builtin_exp(f); }
double march_math_exp2(double f) { return __builtin_exp2(f); }
double march_math_log(double f)  { return __builtin_log(f); }
double march_math_log2(double f) { return __builtin_log2(f); }
double march_math_log10(double f){ return __builtin_log10(f); }
double march_math_pow(double b, double e) { return __builtin_pow(b, e); }

/* ── List builtins ──────────────────────────────────────────────────── */

void *march_list_append(void *a, void *b) {
    /* Walk list a, rebuild with b as tail */
    int32_t tag = *(int32_t *)((char *)a + 8);
    if (tag == 0) return b;  /* Nil */
    void *head = *(void **)((char *)a + 16);
    void *tail = *(void **)((char *)a + 24);
    void *new_tail = march_list_append(tail, b);
    void *cell = march_alloc(32);  /* header(16) + 2 fields(8+8) */
    *(int32_t *)((char *)cell + 8) = 1;  /* tag = Cons */
    *(void **)((char *)cell + 16) = head;
    *(void **)((char *)cell + 24) = new_tail;
    return cell;
}

void *march_list_concat(void *lists) {
    int32_t tag = *(int32_t *)((char *)lists + 8);
    if (tag == 0) return march_alloc(24);  /* Nil */
    void *head = *(void **)((char *)lists + 16);
    void *tail = *(void **)((char *)lists + 24);
    return march_list_append(head, march_list_concat(tail));
}

/* ── Print / Panic ──────────────────────────────────────────────────── */

/* In WASM browser target, print is a no-op (or could call imported console.log) */
void march_print(void *s) { (void)s; }
void march_println(void *s) { (void)s; }

void march_panic(void *s) {
    (void)s;
    __builtin_trap();
}

/* ── Scheduler stubs ────────────────────────────────────────────────── */

int64_t march_tls_reductions = 0;
void march_yield_from_compiled(void) {}
void march_run_scheduler(void) {}

/* ── LLVM intrinsic ─────────────────────────────────────────────────── */

/* llvm.ctpop.i64 is lowered by LLVM directly, but declare a fallback */
