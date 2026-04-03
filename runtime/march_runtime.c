#include "march_runtime.h"
#include "march_scheduler.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <math.h>
#include <ctype.h>
#include <stdatomic.h>
#include <pthread.h>
#include <sys/stat.h>
#include <time.h>
#include <errno.h>
#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>
#include <setjmp.h>
#include <sys/wait.h>

/* ── GC/RC Tracing (Phase 5) ─────────────────────────────────────────── */
/*
 * Enabled by setting MARCH_TRACE_GC=1 in the environment before running a
 * compiled March binary.  Events are written as newline-delimited JSON to
 * trace/gc/gc.jsonl in the current working directory.
 *
 * Event format:
 *   {"event":"alloc",   "addr":"0x…","size":N,"rc":1,"tag":0,"ts_ns":N}
 *   {"event":"free",    "addr":"0x…","size":0,"rc":0,"tag":N,"ts_ns":N}
 *   {"event":"inc_ref", "addr":"0x…","size":0,"rc":N,"tag":N,"ts_ns":N}
 *   {"event":"dec_ref", "addr":"0x…","size":0,"rc":N,"tag":N,"ts_ns":N}
 */

static FILE            *gc_trace_file  = NULL;
static pthread_mutex_t  gc_trace_mutex = PTHREAD_MUTEX_INITIALIZER;
/* 0 = not yet checked, 1 = enabled, -1 = disabled */
static int              gc_trace_state = 0;

static void gc_trace_init_locked(void) {
    if (getenv("MARCH_TRACE_GC") == NULL) { gc_trace_state = -1; return; }
    mkdir("trace",    0755);
    mkdir("trace/gc", 0755);
    gc_trace_file  = fopen("trace/gc/gc.jsonl", "w");
    gc_trace_state = (gc_trace_file != NULL) ? 1 : -1;
    if (gc_trace_state < 0)
        fputs("march: warning: MARCH_TRACE_GC=1 but could not open trace/gc/gc.jsonl\n",
              stderr);
}

/* Lazy single-check: fast path avoids the mutex once state is known. */
static inline int gc_trace_on(void) {
    if (__builtin_expect(gc_trace_state != 0, 1)) return gc_trace_state > 0;
    pthread_mutex_lock(&gc_trace_mutex);
    if (gc_trace_state == 0) gc_trace_init_locked();
    pthread_mutex_unlock(&gc_trace_mutex);
    return gc_trace_state > 0;
}

static inline int64_t gc_ts_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

static void gc_emit(const char *ev, void *addr,
                    int64_t size, int64_t rc, int32_t tag) {
    pthread_mutex_lock(&gc_trace_mutex);
    fprintf(gc_trace_file,
            "{\"event\":\"%s\",\"addr\":\"%p\","
            "\"size\":%lld,\"rc\":%lld,\"tag\":%d,\"ts_ns\":%lld}\n",
            ev, addr,
            (long long)size, (long long)rc, (int)tag,
            (long long)gc_ts_ns());
    pthread_mutex_unlock(&gc_trace_mutex);
}

/* Called automatically at program exit to flush and close the trace file. */
static void gc_trace_atexit(void) {
    if (gc_trace_file) { fflush(gc_trace_file); fclose(gc_trace_file); }
}

/* ── Allocation ──────────────────────────────────────────────────────── */

void *march_alloc(int64_t sz) {
    void *p = calloc(1, (size_t)sz);
    if (!p) { fputs("march: out of memory\n", stderr); exit(1); }
    /* Initialize rc=1, tag=0, pad=0 */
    march_hdr *h = (march_hdr *)p;
    h->rc  = 1;
    h->tag = 0;
    h->pad = 0;
    if (gc_trace_on()) gc_emit("alloc", p, sz, 1, 0);
    return p;
}

/* ── Reference counting ──────────────────────────────────────────────── */
/*
 * RC operations use C11 atomics to be safe under concurrent access.
 *
 * ABA fix: we use atomic_fetch_sub and check the RETURNED previous value.
 * This avoids the race where thread A loads rc=1, thread B increments to 2,
 * thread A stores rc=0 and frees.  With fetch_sub the decrement is atomic
 * with the value read, so only the thread that observes prev==1 calls free.
 *
 * The fields in march_hdr / march_string are plain int64_t (not _Atomic) so
 * that LLVM-generated FBIP code can access them without atomic semantics.
 * We cast to _Atomic int64_t * at the RC call sites; this is safe because
 * _Atomic int64_t has the same size and alignment as int64_t on all targets.
 */

/* Polymorphic containers store scalars via inttoptr (e.g. List(Int) stores
 * integers as pointers).  When code-generated pattern-match shared-paths emit
 * march_incrc/decrc on extracted fields whose compile-time type is still a
 * type variable, the value may be a small integer, not a heap pointer.
 * Guard against this: addresses below one page (4096) are never valid heap
 * allocations on any modern platform. */
#define IS_HEAP_PTR(p) ((uintptr_t)(p) >= 4096u)

void march_incrc(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    /* Relaxed: caller already holds a reference so the object is alive. */
    int64_t prev = atomic_fetch_add_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_relaxed);
    if (gc_trace_on())
        gc_emit("inc_ref", p, 0, prev + 1, ((march_hdr *)p)->tag);
}

void march_decrc(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    /* acq_rel: release our writes before decrement; acquire before free so
     * we see all other threads' writes to the object. */
    int32_t tag  = ((march_hdr *)p)->tag;
    int64_t prev = atomic_fetch_sub_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_acq_rel);
    if (gc_trace_on())
        gc_emit(prev == 1 ? "free" : "dec_ref", p, 0, prev - 1, tag);
    if (prev == 1) {
        free(p);
    } else if (prev < 1) {
        /* RC underflow: double-decrement detected — abort to surface the bug
         * rather than silently double-freeing and corrupting the heap. */
        fprintf(stderr, "march: RC underflow (rc was %lld) at %p — aborting\n",
                (long long)prev, p);
        abort();
    }
}

int64_t march_decrc_freed(void *p) {
    if (!IS_HEAP_PTR(p)) return 1;
    int32_t tag  = ((march_hdr *)p)->tag;
    int64_t prev = atomic_fetch_sub_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_acq_rel);
    if (gc_trace_on())
        gc_emit(prev <= 1 ? "free" : "dec_ref", p, 0, prev - 1, tag);
    if (prev <= 1) { free(p); return 1; }
    return 0;
}

void march_free(void *p) {
    if (gc_trace_on() && IS_HEAP_PTR(p))
        gc_emit("free", p, 0, 0, ((march_hdr *)p)->tag);
    free(p);
}

/* Non-atomic reference counting — for values provably local to one thread.
 * These must NOT be called on values that may be concurrently accessed from
 * another actor.  The callers (Perceus-generated code) guarantee this. */
void march_incrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    ((march_hdr *)p)->rc++;
    if (gc_trace_on())
        gc_emit("inc_ref", p, 0, ((march_hdr *)p)->rc, ((march_hdr *)p)->tag);
}

void march_decrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    march_hdr *h = (march_hdr *)p;
    h->rc--;
    if (gc_trace_on())
        gc_emit(h->rc <= 0 ? "free" : "dec_ref", p, 0, h->rc, h->tag);
    if (h->rc <= 0) {
        if (h->rc < 0) {
            fprintf(stderr, "march: local RC underflow at %p — aborting\n", p);
            abort();
        }
        free(p);
    }
}

/* ── IOList hash ─────────────────────────────────────────────────────── */

/* IOList variant tags (must match iolist.march stdlib):
     0 = Empty
     1 = Str(String)          field[0] at offset 16
     2 = Segments(List(IOList)) field[0] at offset 16
   List variant tags:
     0 = Nil
     1 = Cons(head, tail)     head at offset 16, tail at offset 24 */
static uint64_t piolist_hash_walk(void *iol, uint64_t h) {
    static const uint64_t FNV_PRIME  = UINT64_C(1099511628211);
    static const uint64_t FNV_OFFSET = UINT64_C(14695981039346656037);
    if (!h) h = FNV_OFFSET; /* unused — caller passes offset */
    if (!iol) return h;
    int32_t tag = *(int32_t *)((char *)iol + 8);
    if (tag == 1) { /* Str(String) */
        march_string *s = *(march_string **)((char *)iol + 16);
        if (s) {
            for (int64_t i = 0; i < s->len; i++) {
                h ^= (uint64_t)(unsigned char)s->data[i];
                h *= FNV_PRIME;
            }
        }
    } else if (tag == 2) { /* Segments(List(IOList)) */
        void *list = *(void **)((char *)iol + 16);
        while (list) {
            int32_t ltag = *(int32_t *)((char *)list + 8);
            if (ltag != 1) break; /* Nil */
            void *head = *(void **)((char *)list + 16);
            list       = *(void **)((char *)list + 24);
            h = piolist_hash_walk(head, h);
        }
    }
    /* tag == 0 (Empty) — nothing to hash */
    return h;
}

void *march_iolist_hash_fnv1a(void *iol) {
    static const uint64_t FNV_OFFSET = UINT64_C(14695981039346656037);
    uint64_t h = piolist_hash_walk(iol, FNV_OFFSET);
    char buf[17];
    snprintf(buf, sizeof(buf), "%016" PRIx64, h);
    return march_string_lit(buf, 16);
}

/* ── Strings ─────────────────────────────────────────────────────────── */

/* march_string layout: [rc:i64][len:i64][data:char*] */
void *march_string_lit(const char *utf8, int64_t len) {
    march_string *s = malloc(sizeof(march_string) + (size_t)len + 1);
    if (!s) { fputs("march: out of memory\n", stderr); exit(1); }
    s->rc  = 1;
    s->len = len;
    memcpy(s->data, utf8, (size_t)len);
    s->data[len] = '\0';
    return s;
}

void *march_int_to_string(int64_t n) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)n);
    return march_string_lit(buf, len);
}

void *march_float_to_string(double f) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%g", f);
    return march_string_lit(buf, len);
}

void *march_bool_to_string(int64_t b) {
    return b ? march_string_lit("true", 4) : march_string_lit("false", 5);
}

void *march_string_concat(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    int64_t total = sa->len + sb->len;
    march_string *s = malloc(sizeof(march_string) + (size_t)total + 1);
    if (!s) { fputs("march: out of memory\n", stderr); exit(1); }
    s->rc  = 1;
    s->len = total;
    memcpy(s->data, sa->data, (size_t)sa->len);
    memcpy(s->data + sa->len, sb->data, (size_t)sb->len);
    s->data[total] = '\0';
    return s;
}

/* ── Ord: compare — returns -1 / 0 / 1 ─────────────────────────────────── */

int64_t march_compare_int(int64_t x, int64_t y) {
    return (x > y) - (x < y);
}

int64_t march_compare_float(double x, double y) {
    return (x > y) - (x < y);
}

int64_t march_compare_string(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    size_t min_len = sa->len < sb->len ? (size_t)sa->len : (size_t)sb->len;
    int cmp = memcmp(sa->data, sb->data, min_len);
    if (cmp != 0) return cmp > 0 ? 1 : -1;
    if (sa->len < sb->len) return -1;
    if (sa->len > sb->len) return 1;
    return 0;
}

/* ── Hash ────────────────────────────────────────────────────────────────── */

int64_t march_hash_int(int64_t x) {
    /* Finalizer from splitmix64 */
    uint64_t v = (uint64_t)x;
    v ^= v >> 30; v *= UINT64_C(0xbf58476d1ce4e5b9);
    v ^= v >> 27; v *= UINT64_C(0x94d049bb133111eb);
    v ^= v >> 31;
    return (int64_t)v;
}

int64_t march_hash_float(double x) {
    uint64_t bits;
    memcpy(&bits, &x, sizeof(bits));
    return march_hash_int((int64_t)bits);
}

int64_t march_hash_string(void *s) {
    march_string *ms = (march_string *)s;
    /* FNV-1a 64-bit */
    uint64_t h = UINT64_C(14695981039346656037);
    for (int64_t i = 0; i < ms->len; i++) {
        h ^= (uint8_t)ms->data[i];
        h *= UINT64_C(1099511628211);
    }
    return (int64_t)h;
}

int64_t march_hash_bool(int64_t b) { return b; }

int64_t march_string_eq(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    return sa->len == sb->len && memcmp(sa->data, sb->data, (size_t)sa->len) == 0 ? 1 : 0;
}

int64_t march_string_byte_length(void *s) {
    return s ? ((march_string *)s)->len : 0;
}

int64_t march_string_is_empty(void *s) {
    return (!s || ((march_string *)s)->len == 0) ? 1 : 0;
}

/* Returns Option(Int): None(tag=0) on failure, Some(n)(tag=1,field=n) on success.
 * Option follows declaration order: type Option = None | Some('a)
 * Heap layout for Some(n): [rc:i64][tag=1:i32][pad:i32][n:i64] = 24 bytes. */
void *march_string_to_int(void *s) {
    march_string *str = (march_string *)s;
    char *end;
    long long n = strtoll(str->data, &end, 10);
    /* None if no digits consumed or trailing non-digit characters */
    if (end == str->data || *end != '\0') {
        void *none = march_alloc(16);   /* tag stays 0 = None */
        return none;
    }
    void *some = march_alloc(16 + 8);  /* 24 bytes: header + one i64 field */
    int32_t *tp = (int32_t *)((char *)some + 8);
    tp[0] = 1;                         /* tag = 1 = Some */
    int64_t *fp = (int64_t *)((char *)some + 16);
    fp[0] = (int64_t)n;
    return some;
}

/* Returns a new String by joining all String elements of a March List(String)
 * with the given separator.
 *
 * March List(String) layout:
 *   Nil  tag=0, no fields → 16 bytes
 *   Cons tag=1, 2 ptr fields at offsets 16 (head String) and 24 (tail List)
 */
void *march_string_join(void *list, void *sep) {
    march_string *sep_s = (march_string *)sep;
    int64_t sep_len = sep_s ? sep_s->len : 0;
    /* First pass: count elements and total byte length */
    int64_t total = 0;
    int64_t count = 0;
    void *cur = list;
    while (cur) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break;           /* Nil */
        void *head = *(void **)((char *)cur + 16);
        total += ((march_string *)head)->len;
        count++;
        cur = *(void **)((char *)cur + 24);
    }
    if (count > 1) total += sep_len * (count - 1);
    /* Allocate result string */
    march_string *result = malloc(sizeof(march_string) + (size_t)total + 1);
    if (!result) { fputs("march: out of memory\n", stderr); exit(1); }
    result->rc  = 1;
    result->len = total;
    /* Second pass: fill */
    char *dst = result->data;
    int64_t first = 1;
    cur = list;
    while (cur) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break;
        void *head = *(void **)((char *)cur + 16);
        march_string *hs = (march_string *)head;
        if (!first && sep_len > 0) {
            memcpy(dst, sep_s->data, (size_t)sep_len);
            dst += sep_len;
        }
        memcpy(dst, hs->data, (size_t)hs->len);
        dst += hs->len;
        first = 0;
        cur = *(void **)((char *)cur + 24);
    }
    *dst = '\0';
    return result;
}

/* ── I/O ─────────────────────────────────────────────────────────────── */

void march_print(void *s) {
    march_string *ms = (march_string *)s;
    fwrite(ms->data, 1, (size_t)ms->len, stdout);
}

void march_println(void *s) {
    march_string *ms = (march_string *)s;
    fwrite(ms->data, 1, (size_t)ms->len, stdout);
    putchar('\n');
}

void march_print_stderr(void *s) {
    march_string *ms = (march_string *)s;
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
    fputc('\n', stderr);
}

void *march_io_read_line(void) {
    char buf[4096];
    if (!fgets(buf, sizeof(buf), stdin)) {
        return march_string_lit("", 0);
    }
    size_t len = strlen(buf);
    if (len > 0 && buf[len-1] == '\n') { buf[--len] = '\0'; }
    if (len > 0 && buf[len-1] == '\r') { buf[--len] = '\0'; }
    return march_string_lit(buf, (int64_t)len);
}

/* ── Integer math helpers ────────────────────────────────────────────────── */

int64_t march_int_pow(int64_t base, int64_t exp) {
    if (exp < 0) return 0;
    int64_t result = 1;
    while (exp > 0) {
        if (exp & 1) result *= base;
        base *= base;
        exp >>= 1;
    }
    return result;
}

/* ── Panic ───────────────────────────────────────────────────────────────── */

/* Forward declaration so march_panic_ext / march_todo_ext can call march_panic
 * which is defined just below. */
void march_panic(void *s);

/* panic_ / todo_ / unreachable_: internal runtime primitives called by the
 * March prelude's panic/todo/unreachable wrappers.  They call march_panic and
 * return NULL (unreachable, but needed to satisfy the polymorphic return type
 * the compiler assigns to expressions of type `a`). */
void *march_panic_ext(void *s) {
    march_panic(s);
    return NULL;
}

void *march_todo_ext(void *s) {
    march_panic(s);
    return NULL;
}

void march_panic(void *s) {
    march_string *ms = (march_string *)s;
    /* In test mode, capture the message and longjmp back to the test runner
       instead of terminating the process. */
    if (march_test_in_test) {
        int len = (int)ms->len < (int)sizeof(march_test_fail_buf) - 1
                  ? (int)ms->len : (int)sizeof(march_test_fail_buf) - 1;
        memcpy(march_test_fail_buf, ms->data, (size_t)len);
        march_test_fail_buf[len] = '\0';
        longjmp(march_test_jmp_buf, 1);
    }
    fprintf(stderr, "panic: ");
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
    fputc('\n', stderr);
    fflush(stderr);
    exit(1);
}

/* ── Test harness ────────────────────────────────────────────────────────── */

/* State used by the test runner.  These are process-global because test
   binaries are single-threaded during test execution. */
jmp_buf  march_test_jmp_buf;
int      march_test_in_test  = 0;
char     march_test_fail_buf[4096];

static int  test_verbose    = 0;
static char test_filter[256] = "";

/* Counters across all march_test_run calls */
static int test_total   = 0;
static int test_failed  = 0;

/* Failure list — stored as a flat array of (name, msg) string pairs.
   At most 2048 failures recorded to avoid unbounded allocation. */
#define MARCH_TEST_MAX_FAILURES 2048
static char *test_failure_names[MARCH_TEST_MAX_FAILURES];
static char *test_failure_msgs[MARCH_TEST_MAX_FAILURES];
static int   test_failure_count = 0;

/* Parse --verbose / -v and --filter=... from argv. */
void march_test_init(int32_t argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--verbose") == 0 || strcmp(argv[i], "-v") == 0) {
            test_verbose = 1;
        } else if (strncmp(argv[i], "--filter=", 9) == 0) {
            strncpy(test_filter, argv[i] + 9, sizeof(test_filter) - 1);
            test_filter[sizeof(test_filter) - 1] = '\0';
        }
    }
}

/* Run the setup_all function once before any tests. */
void march_test_setup_all(void (*fn)(void)) {
    if (fn) fn();
}

/* Run a single test function, with optional per-test setup.
   name is a NUL-terminated C string (from the LLVM constant). */
void march_test_run(void (*fn)(void), const char *name, void (*setup)(void)) {
    /* Apply filter (case-sensitive substring match). */
    if (test_filter[0] != '\0' && strstr(name, test_filter) == NULL)
        return;

    test_total++;
    if (setup) setup();

    march_test_fail_buf[0] = '\0';
    march_test_in_test = 1;
    int jmp_rc = setjmp(march_test_jmp_buf);
    if (jmp_rc == 0) {
        fn();
        march_test_in_test = 0;
        /* Test passed */
        if (test_verbose) {
            printf("  \xe2\x9c\x93 %s\n", name);
            fflush(stdout);
        } else {
            printf(".");
            fflush(stdout);
        }
    } else {
        march_test_in_test = 0;
        /* Test failed (panic / assertion) */
        if (test_verbose) {
            printf("  \xe2\x9c\x97 %s\n    %s\n", name, march_test_fail_buf);
            fflush(stdout);
        } else {
            printf("F");
            fflush(stdout);
        }
        if (test_failure_count < MARCH_TEST_MAX_FAILURES) {
            test_failure_names[test_failure_count] = strdup(name);
            test_failure_msgs[test_failure_count]  = strdup(
                march_test_fail_buf[0] ? march_test_fail_buf : "assertion failed");
            test_failure_count++;
        }
        test_failed++;
    }
}

/* Print the final summary and return an exit code (0 = all pass, 1 = failures). */
int32_t march_test_report(void) {
    if (!test_verbose) printf("\n");
    if (test_failed > 0 && !test_verbose) {
        printf("\n%d failure(s):\n\n", test_failure_count);
        for (int i = 0; i < test_failure_count; i++) {
            printf("FAIL: \"%s\"\n  %s\n\n",
                   test_failure_names[i], test_failure_msgs[i]);
            free(test_failure_names[i]);
            free(test_failure_msgs[i]);
        }
    }
    printf("Finished: %d test%s, %d failure%s\n",
           test_total,  test_total  == 1 ? "" : "s",
           test_failed, test_failed == 1 ? "" : "s");
    fflush(stdout);
    return test_failed > 0 ? 1 : 0;
}

/* ── Actor runtime — green thread based ──────────────────────────────────── */
/*
 * Design overview
 * ───────────────
 * Each actor runs as a green thread (march_proc) on the cooperative scheduler
 * in march_scheduler.c.  The green thread loop (actor_green_thread) calls
 * march_sched_recv() to block until a message arrives, dispatches it via the
 * actor's $dispatch closure, then calls march_sched_tick() for cooperative
 * preemption.
 *
 * Actor struct layout (as int64_t[]):
 *   [0] rc         (reference count)
 *   [1] tag+pad
 *   [2] dispatch   ($dispatch field — closure struct ptr, see llvm_emit.ml)
 *   [3] alive      ($alive field   — 1 = alive, 0 = dead)
 *   [4+] state fields (alphabetical order)
 *
 * RC / FBIP contract
 * ──────────────────
 * march_send does NOT call march_incrc on the message.  Perceus at the call
 * site either transfers ownership (no extra incrc) or has already incremented
 * (if msg is used after the send).  Either way we receive exactly one
 * reference.  The dispatch function's own Perceus instrumentation decrements
 * after unpacking.
 *
 * Scheduling
 * ──────────
 * march_send delegates to march_sched_send which enqueues the message into
 * the green thread's mailbox and wakes the thread if it was blocked on recv.
 * march_run_scheduler delegates to march_sched_run which runs all green
 * threads until they complete.  A re-entrancy guard (g_in_scheduler) prevents
 * nested scheduler invocations.
 */

#define MARCH_SCHED_BUCKETS  256  /* Power-of-2 hash table size              */

/* Cleanup node: stores a (value, drop_fn closure) pair for register_resource. */
typedef struct march_cleanup_node {
    void                      *cleanup_fn;  /* March closure: Unit -> Unit */
    struct march_cleanup_node *next;
} march_cleanup_node;

/* Monitor node: one (watcher, ref) entry registered on a target actor. */
typedef struct march_monitor_node {
    void                       *watcher;   /* watcher actor ptr */
    int64_t                     mon_ref;   /* monitor reference ID */
    struct march_monitor_node  *next;
} march_monitor_node;

/* Per-actor scheduler metadata.  Stored in a side table keyed by actor
 * pointer so the actor object layout (and codegen) are unaffected. */
typedef struct march_actor_meta {
    void                      *actor;
    march_proc                *green_thread;  /* Green thread running this actor's loop */
    struct march_actor_meta    *tbl_next;   /* Hash-table chain                */
    int64_t                     pid_index;  /* Sequential spawn index for Pid(n) display */
    march_cleanup_node         *cleanup_head; /* Cleanup callbacks (most recent first) */
    march_monitor_node         *monitor_head; /* Monitors watching this actor   */
    _Atomic int64_t             down_count;   /* Down messages received (watcher side) */
    /* Supervision metadata (set by march_register_supervisor): */
    int                         supervisor_strategy;    /* 0=one_for_one, 1=one_for_all, 2=rest_for_one */
    int64_t                     supervisor_max_restarts;
    int64_t                     supervisor_window_secs;
    /* Capability revocation (used by march_is_cap_valid): */
    int64_t                     epoch;    /* Current epoch; incremented on revocation */
} march_actor_meta;

/* Global side table: actor ptr → march_actor_meta */
static march_actor_meta  *g_actor_tbl[MARCH_SCHED_BUCKETS];
static pthread_mutex_t    g_tbl_mu = PTHREAD_MUTEX_INITIALIZER;

/* Sequential Pid index counter: each spawned actor gets a unique integer. */
static _Atomic int64_t g_next_pid_index = 0;

/* Sequential monitor ref counter. */
static _Atomic int64_t g_next_monitor_ref = 0;

/* Re-entrancy guard: handlers that call march_send must not recurse into
 * the scheduler; the outer loop will pick up newly-queued actors. */
static _Thread_local int g_in_scheduler = 0;

/* Lazy initialization flag for the green thread scheduler. */
static int g_sched_initialized = 0;

/* Background scheduler thread — started automatically by march_spawn() so
 * that actor green threads run even when the main thread is blocked in the
 * HTTP event loop (which never calls march_run_scheduler()).
 *
 * Invariant: g_sched_bg_started transitions 0→1 exactly once per program
 * execution, guarded by a CAS.  march_run_scheduler() joins the thread if
 * it was started, ensuring orderly shutdown for non-HTTP programs. */
static pthread_t       g_sched_bg_thread;
static _Atomic int     g_sched_bg_started = 0;

static void *sched_bg_entry(void *arg) {
    (void)arg;
    march_sched_run();
    return NULL;
}

/* Start the scheduler in a background OS thread if not already running.
 * Idempotent: the CAS ensures at most one background thread is created. */
static void march_ensure_sched_started(void) {
    int expected = 0;
    if (!atomic_compare_exchange_strong_explicit(
            &g_sched_bg_started, &expected, 1,
            memory_order_acq_rel, memory_order_relaxed))
        return;  /* already started */
    if (pthread_create(&g_sched_bg_thread, NULL, sched_bg_entry, NULL) != 0) {
        /* Fall back: reset flag so march_run_scheduler() runs inline. */
        atomic_store_explicit(&g_sched_bg_started, 0, memory_order_relaxed);
    }
}

/* Forward declarations */
int64_t march_monitor(void *watcher, void *target);

/* ── Side-table helpers ──────────────────────────────────────────── */

static unsigned int actor_bucket(void *actor) {
    return (unsigned int)(((uintptr_t)actor >> 4) % MARCH_SCHED_BUCKETS);
}

/* Look up meta entry for an actor without creating (returns NULL if not found). */
static march_actor_meta *find_meta(void *actor) {
    if (!IS_HEAP_PTR(actor)) return NULL;
    unsigned int b = actor_bucket(actor);
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *m = g_actor_tbl[b];
    while (m) {
        if (m->actor == actor) { pthread_mutex_unlock(&g_tbl_mu); return m; }
        m = m->tbl_next;
    }
    pthread_mutex_unlock(&g_tbl_mu);
    return NULL;
}

/* Look up or lazily create the meta entry for an actor. */
static march_actor_meta *find_or_create_meta(void *actor) {
    unsigned int b = actor_bucket(actor);
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *m = g_actor_tbl[b];
    while (m) {
        if (m->actor == actor) { pthread_mutex_unlock(&g_tbl_mu); return m; }
        m = m->tbl_next;
    }
    m = (march_actor_meta *)calloc(1, sizeof(march_actor_meta));
    if (!m) { fputs("march: out of memory (actor meta)\n", stderr); exit(1); }
    m->actor = actor;
    atomic_init(&m->down_count, 0);
    m->tbl_next = g_actor_tbl[b];
    g_actor_tbl[b] = m;
    pthread_mutex_unlock(&g_tbl_mu);
    return m;
}

/* ── Actor green thread loop ─────────────────────────────────────── */

/* Each actor runs as a green thread that loops on recv→dispatch.
 * The thread parks (PROC_WAITING) when no messages are available and
 * is woken by march_sched_send when a message arrives. */
static void actor_green_thread(void *arg) {
    march_actor_meta *meta = (march_actor_meta *)arg;
    void *actor = meta->actor;
    int64_t *a = (int64_t *)actor;

    while (a[3]) {  /* while alive */
        void *msg = march_sched_recv();
        if (!msg) break;  /* woken without message (killed) */

        if (!a[3]) {
            march_decrc(msg);
            break;
        }

        char *closure = (char *)(uintptr_t)a[2];
        typedef void (*closure_fn_t)(void *, void *, void *);
        closure_fn_t fn = *(closure_fn_t *)(closure + 16);

        int64_t saved_rc = a[0];
        a[0] = 1;  /* FBIP: force RC=1 for in-place reuse */
        fn(closure, actor, msg);
        a[0] = saved_rc;

        march_sched_tick();
    }
}

/* ── Public actor API ────────────────────────────────────────────── */

void march_kill(void *actor) {
    int64_t *fields = (int64_t *)actor;
    if (!fields[3]) return;   /* Already dead */

    /* Run cleanup callbacks in reverse acquisition order (cleanup_head is
     * most recently registered → already LIFO order). */
    march_actor_meta *meta = find_meta(actor);
    if (meta && meta->cleanup_head) {
        /* The cleanup function is a March closure: fn(_ : Unit) : Unit.
         * Call it via the closure dispatch convention:
         *   closure[16] = function pointer, called as fn(closure, unit_arg) */
        march_cleanup_node *node = meta->cleanup_head;
        while (node) {
            march_cleanup_node *next = node->next;
            void *clo = node->cleanup_fn;
            if (clo && IS_HEAP_PTR(clo)) {
                typedef void *(*clo_fn_t)(void *, void *);
                void **clo_fields = (void **)((char *)clo + 16);
                clo_fn_t fn_ptr = (clo_fn_t)(*(clo_fields));
                if (fn_ptr) {
                    /* Allocate a Unit argument */
                    void *unit_arg = march_alloc(16);
                    fn_ptr(clo, unit_arg);
                    march_decrc(unit_arg);
                }
            }
            free(node);
            node = next;
        }
        meta->cleanup_head = NULL;
    }

    /* Deliver Down notifications to all watchers. */
    if (meta && meta->monitor_head) {
        march_monitor_node *mn = meta->monitor_head;
        while (mn) {
            march_monitor_node *next_mn = mn->next;
            march_actor_meta *watcher_meta = find_meta(mn->watcher);
            if (watcher_meta) {
                atomic_fetch_add_explicit(&watcher_meta->down_count, 1,
                                          memory_order_relaxed);
            }
            free(mn);
            mn = next_mn;
        }
        meta->monitor_head = NULL;
    }

    fields[3] = 0;   /* $alive flag at byte offset 24 */

    /* Wake the actor's green thread so it can notice death and exit. */
    if (meta && meta->green_thread) {
        march_sched_wake(meta->green_thread);
    }
}

int64_t march_is_alive(void *actor) {
    return ((int64_t *)actor)[3];
}

/* Register an actor with the scheduler and return it unchanged.
 * Called from generated ActorName_spawn() wrappers:
 *   let $raw = ActorName_spawn()
 *   march_spawn($raw)            -- returns $raw */
void *march_spawn(void *actor) {
    march_actor_meta *meta = find_or_create_meta(actor);
    meta->pid_index = atomic_fetch_add_explicit(&g_next_pid_index, 1,
                                                memory_order_relaxed);
    /* Initialize scheduler lazily. */
    if (!g_sched_initialized) {
        march_sched_init();
        g_sched_initialized = 1;
    }
    meta->green_thread = march_sched_spawn(actor_green_thread, meta);
    /* Start the scheduler in a background thread so actor green threads run
     * even when the main thread is blocked inside the HTTP event loop.
     * For non-HTTP programs this is harmless: march_run_scheduler() joins
     * the background thread before returning. */
    march_ensure_sched_started();
    return actor;
}

/* Read an int64 state field by 0-based index from an actor struct.
 *
 * The March programmer passes index 0 for the first state field, 1 for the
 * second, etc. (same as the eval interpreter).  The compiled actor struct
 * layout adds a 4-word header before the state fields:
 *
 *   word 0: rc          (reference count — from march_hdr)
 *   word 1: tag+pad     (GC tag — from march_hdr)
 *   word 2: $dispatch   (TIR field index 0 — closure ptr for message dispatch)
 *   word 3: $alive      (TIR field index 1 — 1=alive, 0=dead)
 *   word 4+: state fields in alphabetical order (TIR field indices 2+)
 *
 * We therefore add 4 to translate the caller's 0-based state-field index
 * into the correct word offset in memory. */
int64_t march_actor_get_int(void *actor, int64_t index) {
    return ((int64_t *)actor)[index + 4];
}

/* Delegate to the green thread scheduler.  Runs all spawned green threads
 * until they all complete (all actors have exited their loops).
 *
 * If march_spawn() already started a background scheduler thread (the common
 * case when the main thread is blocked in the HTTP event loop), we join that
 * thread instead of running the scheduler inline.  This ensures orderly
 * shutdown: the background thread drives all actors to completion, then the
 * join returns and the program exits normally. */
void march_run_scheduler(void) {
    if (atomic_load_explicit(&g_sched_bg_started, memory_order_acquire)) {
        /* Background thread is/was running — join it so actors finish. */
        pthread_join(g_sched_bg_thread, NULL);
        atomic_store_explicit(&g_sched_bg_started, 0, memory_order_relaxed);
        g_sched_initialized = 0;
        return;
    }
    if (g_in_scheduler) return;
    g_in_scheduler = 1;
    march_sched_run();
    g_in_scheduler = 0;
    g_sched_initialized = 0;
}

/* Send a message to an actor.
 *
 * RC contract: we do NOT call march_incrc on msg.  Perceus at the call site
 * either transfers ownership (msg not used after send → no extra incrc) or
 * has already incremented (msg used after send → incrc before the call).
 * Either way we receive exactly one reference.  The dispatch function's own
 * Perceus instrumentation decrements it after unpacking.
 *
 * Returns Option(Unit): None (tag=0) if actor is dead, Some(()) (tag=1) if
 * the message was enqueued.
 */
void *march_send(void *actor, void *msg) {
    int64_t *a = (int64_t *)actor;

    if (!a[3]) {
        /* Actor dead: release the reference we were given. */
        march_decrc(msg);
        void *none = march_alloc(16);
        return none;
    }

    march_actor_meta *meta = find_or_create_meta(actor);
    if (!meta->green_thread) {
        march_decrc(msg);
        void *none = march_alloc(16);
        return none;
    }

    march_sched_send(meta->green_thread, msg);

    /* Return Some(()). */
    void *some = march_alloc(16 + 8);
    int32_t *hdr = (int32_t *)((char *)some + 8);
    hdr[0] = 1;
    int64_t *fld = (int64_t *)((char *)some + 16);
    fld[0] = 0;
    return some;
}

/* ── Heap layout helpers (used by actor_call and file I/O) ────────────── */
/* Header layout: rc(8) | tag(4) | pad(4) | fields... */
#define MARCH_FIELD(obj, i) (((int64_t *)(obj))[2 + (i)])
#define MARCH_FIELD_PTR(obj, i) ((void *)MARCH_FIELD(obj, i))
#define MARCH_SET_TAG(obj, t) (((march_hdr *)(obj))->tag = (int32_t)(t))

static void *mk_ok(void *value);
static void *mk_err_cstr(const char *msg);

/* ── Actor.call / Actor.reply (synchronous messaging) ────────────────── */
/*
 * march_actor_call: synchronous call — builds a wrapped message containing the
 * calling green-thread pointer as the reply channel (field 0), then sends it to
 * the actor and blocks until the actor calls march_actor_reply.
 *
 * Protocol:
 *   1. Read the tag from inner_msg (the zero-arg constructor like GetCount).
 *   2. Build a new heap struct with the same tag + one extra field: the calling
 *      proc pointer (the "reply channel").  The actor handler receives this as
 *      its first parameter (e.g., `on GetCount(reply_to)`).
 *   3. Send the augmented message to the actor's green thread.
 *   4. Block via march_sched_recv() until the actor calls march_actor_reply.
 *   5. Return Ok(reply_value).
 *
 * RC contract: we consume one reference to inner_msg (via march_decrc after
 * reading the tag) and transfer ownership of the new call_msg to the actor.
 */
void *march_actor_call(void *actor, void *inner_msg, int64_t timeout_ms) {
    (void)timeout_ms;  /* timeout not yet enforced; accepted for API compat */

    int64_t *a = (int64_t *)actor;
    if (!a[3]) {
        march_decrc(inner_msg);
        return mk_err_cstr("actor not alive");
    }

    march_actor_meta *meta = find_or_create_meta(actor);
    if (!meta->green_thread) {
        march_decrc(inner_msg);
        return mk_err_cstr("actor not found");
    }

    march_proc *caller = march_sched_current();
    if (!caller) {
        march_decrc(inner_msg);
        return mk_err_cstr("actor_call: not in scheduler context");
    }

    /* Read the tag from inner_msg so we can reproduce it on the augmented msg.
     * inner_msg is assumed to be a zero-arg constructor (16 bytes: header only).
     * We decrc it now — the caller owned one reference. */
    int32_t msg_tag = ((march_hdr *)inner_msg)->tag;
    march_decrc(inner_msg);

    /* Build the augmented call message: same tag, field 0 = caller proc ptr.
     * Layout: 16-byte header + 8-byte ptr field = 24 bytes. */
    void *call_msg = march_alloc(24);
    MARCH_SET_TAG(call_msg, msg_tag);
    MARCH_FIELD(call_msg, 0) = (int64_t)(uintptr_t)caller;

    march_sched_send(meta->green_thread, call_msg);

    /* Block until the actor calls actor_reply. */
    void *result = march_sched_recv();
    if (!result) return mk_err_cstr("actor_call: no reply");

    return mk_ok(result);
}

/*
 * march_actor_reply: send a reply back to the caller blocked in actor_call.
 *
 * ref_ptr is the calling green-thread proc pointer that was injected as field 0
 * of the call message.  We cast it back to march_proc * and enqueue result in
 * that proc's mailbox, waking it from march_sched_recv().
 *
 * RC contract: march_actor_reply does NOT incrc result; it transfers the
 * caller's reference (the handler's Perceus instrumentation already owns it).
 */
void march_actor_reply(void *ref_ptr, void *result) {
    march_proc *caller = (march_proc *)ref_ptr;
    march_sched_send(caller, result);
}

/* ── Float builtins ──────────────────────────────────────────────────── */

double march_float_abs(double f) { return fabs(f); }
int64_t march_float_ceil(double f) { return (int64_t)ceil(f); }
int64_t march_float_floor(double f) { return (int64_t)floor(f); }
int64_t march_float_round(double f) { return (int64_t)round(f); }
int64_t march_float_truncate(double f) { return (int64_t)f; }
double march_int_to_float(int64_t n) { return (double)n; }

/* ── Math builtins ───────────────────────────────────────────────────── */

double march_math_sin(double f)   { return sin(f); }
double march_math_cos(double f)   { return cos(f); }
double march_math_tan(double f)   { return tan(f); }
double march_math_asin(double f)  { return asin(f); }
double march_math_acos(double f)  { return acos(f); }
double march_math_atan(double f)  { return atan(f); }
double march_math_atan2(double y, double x) { return atan2(y, x); }
double march_math_sinh(double f)  { return sinh(f); }
double march_math_cosh(double f)  { return cosh(f); }
double march_math_tanh(double f)  { return tanh(f); }
double march_math_sqrt(double f)  { return sqrt(f); }
double march_math_cbrt(double f)  { return cbrt(f); }
double march_math_exp(double f)   { return exp(f); }
double march_math_exp2(double f)  { return exp2(f); }
double march_math_log(double f)   { return log(f); }
double march_math_log2(double f)  { return log2(f); }
double march_math_log10(double f) { return log10(f); }
double march_math_pow(double b, double e) { return pow(b, e); }

/* ── Extended string builtins ────────────────────────────────────────── */

/* Helper: allocate a None (tag=0, no fields). */
static void *make_none(void) {
    return march_alloc(16);
}

/* Helper: allocate Some(val) where val is an i64 stored at offset 16. */
static void *make_some_i64(int64_t val) {
    void *some = march_alloc(16 + 8);
    int32_t *tp = (int32_t *)((char *)some + 8);
    tp[0] = 1;  /* tag = Some */
    int64_t *fp = (int64_t *)((char *)some + 16);
    fp[0] = val;
    return some;
}

/* Helper: allocate Some(ptr) where ptr is stored at offset 16. */
static void *make_some_ptr(void *val) {
    void *some = march_alloc(16 + 8);
    int32_t *tp = (int32_t *)((char *)some + 8);
    tp[0] = 1;  /* tag = Some */
    void **fp = (void **)((char *)some + 16);
    fp[0] = val;
    return some;
}

/* Helper: allocate a Nil list node (tag=0). */
static void *make_nil(void) {
    return march_alloc(16);
}

/* Helper: allocate a Cons(head, tail) list node (tag=1). */
static void *make_cons(void *head, void *tail) {
    void *cons = march_alloc(16 + 16);  /* header + 2 ptr fields */
    int32_t *tp = (int32_t *)((char *)cons + 8);
    tp[0] = 1;  /* tag = Cons */
    void **fp = (void **)((char *)cons + 16);
    fp[0] = head;
    fp[1] = tail;
    return cons;
}

/* Helper: allocate a 2-element tuple (tag=0, 2 ptr fields). */
static void *make_tuple2(void *a, void *b) {
    void *tup = march_alloc(16 + 16);
    /* tag stays 0 */
    void **fp = (void **)((char *)tup + 16);
    fp[0] = a;
    fp[1] = b;
    return tup;
}

int64_t march_string_contains(void *s, void *sub) {
    march_string *ss = (march_string *)s;
    march_string *su = (march_string *)sub;
    if (su->len == 0) return 1;
    if (ss->len < su->len) return 0;
    for (int64_t i = 0; i <= ss->len - su->len; i++) {
        if (memcmp(ss->data + i, su->data, (size_t)su->len) == 0) return 1;
    }
    return 0;
}

int64_t march_string_starts_with(void *s, void *prefix) {
    march_string *ss = (march_string *)s;
    march_string *sp = (march_string *)prefix;
    if (ss->len < sp->len) return 0;
    return memcmp(ss->data, sp->data, (size_t)sp->len) == 0 ? 1 : 0;
}

int64_t march_string_ends_with(void *s, void *suffix) {
    march_string *ss = (march_string *)s;
    march_string *su = (march_string *)suffix;
    if (ss->len < su->len) return 0;
    return memcmp(ss->data + ss->len - su->len, su->data, (size_t)su->len) == 0 ? 1 : 0;
}

void *march_string_slice(void *s, int64_t start, int64_t len) {
    march_string *ss = (march_string *)s;
    int64_t slen = ss->len;
    if (start < 0) start = 0;
    if (start > slen) start = slen;
    if (len < 0) len = 0;
    if (start + len > slen) len = slen - start;
    return march_string_lit(ss->data + start, len);
}

/* Char builtins */
void *march_char_from_int(int64_t n) {
    char c = (char)(n & 0xFF);
    return march_string_lit(&c, 1);
}

int64_t march_char_to_int(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return 0;
    return (int64_t)(unsigned char)sc->data[0];
}

int64_t march_char_is_digit(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return 0;
    unsigned char ch = (unsigned char)sc->data[0];
    return (ch >= '0' && ch <= '9') ? 1 : 0;
}

int64_t march_char_is_alphanumeric(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return 0;
    unsigned char ch = (unsigned char)sc->data[0];
    return ((ch >= '0' && ch <= '9') ||
            (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z')) ? 1 : 0;
}

int64_t march_char_is_whitespace(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return 0;
    unsigned char ch = (unsigned char)sc->data[0];
    return (ch == ' ' || ch == '\t' || ch == '\n' ||
            ch == '\r' || ch == '\f' || ch == '\v') ? 1 : 0;
}

/* Float/Int conversion */
int64_t march_float_to_int(double f) {
    return (int64_t)f;
}

/* Returns List(String). */
void *march_string_chars(void *s) {
    march_string *ss = (march_string *)s;
    void *list = make_nil();
    for (int64_t i = ss->len - 1; i >= 0; i--) {
        void *ch = march_string_lit(ss->data + i, 1);
        list = make_cons(ch, list);
    }
    return list;
}

void *march_string_split(void *s, void *sep) {
    march_string *ss = (march_string *)s;
    march_string *sp = (march_string *)sep;
    if (sp->len == 0) {
        /* Split into individual characters. */
        void *list = make_nil();
        for (int64_t i = ss->len - 1; i >= 0; i--) {
            void *ch = march_string_lit(ss->data + i, 1);
            list = make_cons(ch, list);
        }
        return list;
    }
    /* Collect parts in forward order using a temporary array. */
    int64_t cap = 16;
    int64_t count = 0;
    void **parts = malloc(sizeof(void *) * (size_t)cap);
    int64_t start = 0;
    for (int64_t i = 0; i <= ss->len - sp->len; i++) {
        if (memcmp(ss->data + i, sp->data, (size_t)sp->len) == 0) {
            if (count >= cap) { cap *= 2; parts = realloc(parts, sizeof(void *) * (size_t)cap); }
            parts[count++] = march_string_lit(ss->data + start, i - start);
            start = i + sp->len;
            i = start - 1;  /* loop will increment */
        }
    }
    if (count >= cap) { cap *= 2; parts = realloc(parts, sizeof(void *) * (size_t)cap); }
    parts[count++] = march_string_lit(ss->data + start, ss->len - start);
    /* Build list from back to front. */
    void *list = make_nil();
    for (int64_t i = count - 1; i >= 0; i--) {
        list = make_cons(parts[i], list);
    }
    free(parts);
    return list;
}

/* Returns Option(Tuple(String, String)). */
void *march_string_split_first(void *s, void *sep) {
    march_string *ss = (march_string *)s;
    march_string *sp = (march_string *)sep;
    if (sp->len == 0) return make_none();
    for (int64_t i = 0; i + sp->len <= ss->len; i++) {
        if (memcmp(ss->data + i, sp->data, (size_t)sp->len) == 0) {
            void *head = march_string_lit(ss->data, i);
            void *tail = march_string_lit(ss->data + i + sp->len, ss->len - i - sp->len);
            void *tup = make_tuple2(head, tail);
            return make_some_ptr(tup);
        }
    }
    return make_none();
}

/* Join a List of strings (single-char or multi-char) into one string. */
void *march_string_from_chars(void *lst) {
    /* First pass: compute total length. */
    int64_t total = 0;
    void *cur = lst;
    while (1) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break; /* Nil */
        march_string *ch = *(march_string **)((char *)cur + 16);
        total += ch->len;
        cur = *(void **)((char *)cur + 24);
    }
    march_string *r = malloc(sizeof(march_string) + (size_t)total + 1);
    if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
    r->rc = 1; r->len = total;
    int64_t off = 0;
    cur = lst;
    while (1) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break; /* Nil */
        march_string *ch = *(march_string **)((char *)cur + 16);
        memcpy(r->data + off, ch->data, (size_t)ch->len);
        off += ch->len;
        cur = *(void **)((char *)cur + 24);
    }
    r->data[total] = '\0';
    return r;
}

/* Replace first occurrence. */
void *march_string_replace(void *s, void *old, void *new_) {
    march_string *ss = (march_string *)s;
    march_string *so = (march_string *)old;
    march_string *sn = (march_string *)new_;
    if (so->len == 0) {
        /* Return a copy. */
        return march_string_lit(ss->data, ss->len);
    }
    for (int64_t i = 0; i + so->len <= ss->len; i++) {
        if (memcmp(ss->data + i, so->data, (size_t)so->len) == 0) {
            int64_t newlen = ss->len - so->len + sn->len;
            march_string *r = malloc(sizeof(march_string) + (size_t)newlen + 1);
            if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
            r->rc = 1; r->len = newlen;
            memcpy(r->data, ss->data, (size_t)i);
            memcpy(r->data + i, sn->data, (size_t)sn->len);
            memcpy(r->data + i + sn->len, ss->data + i + so->len, (size_t)(ss->len - i - so->len));
            r->data[newlen] = '\0';
            return r;
        }
    }
    return march_string_lit(ss->data, ss->len);
}

/* Replace all occurrences. */
void *march_string_replace_all(void *s, void *old, void *new_) {
    march_string *ss = (march_string *)s;
    march_string *so = (march_string *)old;
    march_string *sn = (march_string *)new_;
    if (so->len == 0) {
        return march_string_lit(ss->data, ss->len);
    }
    /* Build result in a growable buffer. */
    int64_t cap = ss->len + 64;
    char *buf = malloc((size_t)cap);
    int64_t out = 0;
    int64_t i = 0;
    while (i <= ss->len - so->len) {
        if (memcmp(ss->data + i, so->data, (size_t)so->len) == 0) {
            /* Ensure capacity. */
            while (out + sn->len >= cap) { cap *= 2; buf = realloc(buf, (size_t)cap); }
            memcpy(buf + out, sn->data, (size_t)sn->len);
            out += sn->len;
            i += so->len;
        } else {
            if (out + 1 >= cap) { cap *= 2; buf = realloc(buf, (size_t)cap); }
            buf[out++] = ss->data[i++];
        }
    }
    /* Copy remaining bytes. */
    while (i < ss->len) {
        if (out + 1 >= cap) { cap *= 2; buf = realloc(buf, (size_t)cap); }
        buf[out++] = ss->data[i++];
    }
    void *result = march_string_lit(buf, out);
    free(buf);
    return result;
}

void *march_string_to_lowercase(void *s) {
    march_string *ss = (march_string *)s;
    march_string *r = malloc(sizeof(march_string) + (size_t)ss->len + 1);
    if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
    r->rc = 1; r->len = ss->len;
    for (int64_t i = 0; i < ss->len; i++) {
        r->data[i] = (char)tolower((unsigned char)ss->data[i]);
    }
    r->data[ss->len] = '\0';
    return r;
}

void *march_string_to_uppercase(void *s) {
    march_string *ss = (march_string *)s;
    march_string *r = malloc(sizeof(march_string) + (size_t)ss->len + 1);
    if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
    r->rc = 1; r->len = ss->len;
    for (int64_t i = 0; i < ss->len; i++) {
        r->data[i] = (char)toupper((unsigned char)ss->data[i]);
    }
    r->data[ss->len] = '\0';
    return r;
}

static int is_ws(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

void *march_string_trim(void *s) {
    march_string *ss = (march_string *)s;
    int64_t start = 0, end = ss->len;
    while (start < end && is_ws(ss->data[start])) start++;
    while (end > start && is_ws(ss->data[end - 1])) end--;
    return march_string_lit(ss->data + start, end - start);
}

void *march_string_trim_start(void *s) {
    march_string *ss = (march_string *)s;
    int64_t start = 0;
    while (start < ss->len && is_ws(ss->data[start])) start++;
    return march_string_lit(ss->data + start, ss->len - start);
}

void *march_string_trim_end(void *s) {
    march_string *ss = (march_string *)s;
    int64_t end = ss->len;
    while (end > 0 && is_ws(ss->data[end - 1])) end--;
    return march_string_lit(ss->data, end);
}

void *march_string_repeat(void *s, int64_t n) {
    march_string *ss = (march_string *)s;
    if (n <= 0) return march_string_lit("", 0);
    int64_t total = ss->len * n;
    march_string *r = malloc(sizeof(march_string) + (size_t)total + 1);
    if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
    r->rc = 1; r->len = total;
    for (int64_t i = 0; i < n; i++) {
        memcpy(r->data + i * ss->len, ss->data, (size_t)ss->len);
    }
    r->data[total] = '\0';
    return r;
}

void *march_string_reverse(void *s) {
    march_string *ss = (march_string *)s;
    march_string *r = malloc(sizeof(march_string) + (size_t)ss->len + 1);
    if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
    r->rc = 1; r->len = ss->len;
    for (int64_t i = 0; i < ss->len; i++) {
        r->data[i] = ss->data[ss->len - 1 - i];
    }
    r->data[ss->len] = '\0';
    return r;
}

void *march_string_pad_left(void *s, int64_t width, void *fill) {
    march_string *ss = (march_string *)s;
    march_string *sf = (march_string *)fill;
    if (ss->len >= width) return march_string_lit(ss->data, ss->len);
    int64_t pad = width - ss->len;
    int64_t total = width;
    march_string *r = malloc(sizeof(march_string) + (size_t)total + 1);
    if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
    r->rc = 1; r->len = total;
    char fc = (sf->len > 0) ? sf->data[0] : ' ';
    memset(r->data, fc, (size_t)pad);
    memcpy(r->data + pad, ss->data, (size_t)ss->len);
    r->data[total] = '\0';
    return r;
}

void *march_string_pad_right(void *s, int64_t width, void *fill) {
    march_string *ss = (march_string *)s;
    march_string *sf = (march_string *)fill;
    if (ss->len >= width) return march_string_lit(ss->data, ss->len);
    int64_t pad = width - ss->len;
    int64_t total = width;
    march_string *r = malloc(sizeof(march_string) + (size_t)total + 1);
    if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
    r->rc = 1; r->len = total;
    memcpy(r->data, ss->data, (size_t)ss->len);
    char fc = (sf->len > 0) ? sf->data[0] : ' ';
    memset(r->data + ss->len, fc, (size_t)pad);
    r->data[total] = '\0';
    return r;
}

int64_t march_string_grapheme_count(void *s) {
    march_string *ss = (march_string *)s;
    int64_t count = 0;
    for (int64_t i = 0; i < ss->len; i++) {
        /* UTF-8 continuation bytes are 0x80..0xBF; skip them. */
        if ((ss->data[i] & 0xC0) != 0x80) count++;
    }
    return count;
}

/* Returns Option(Int). */
void *march_string_index_of(void *s, void *sub) {
    march_string *ss = (march_string *)s;
    march_string *su = (march_string *)sub;
    if (su->len == 0) return make_some_i64(0);
    if (su->len > ss->len) return make_none();
    for (int64_t i = 0; i + su->len <= ss->len; i++) {
        if (memcmp(ss->data + i, su->data, (size_t)su->len) == 0) {
            return make_some_i64(i);
        }
    }
    return make_none();
}

/* Returns Option(Int). */
void *march_string_last_index_of(void *s, void *sub) {
    march_string *ss = (march_string *)s;
    march_string *su = (march_string *)sub;
    if (su->len == 0) return make_some_i64(ss->len);
    if (su->len > ss->len) return make_none();
    for (int64_t i = ss->len - su->len; i >= 0; i--) {
        if (memcmp(ss->data + i, su->data, (size_t)su->len) == 0) {
            return make_some_i64(i);
        }
    }
    return make_none();
}

/* Returns Option(Float). */
void *march_string_to_float(void *s) {
    march_string *str = (march_string *)s;
    char *end;
    double f = strtod(str->data, &end);
    if (end == str->data || *end != '\0') {
        return make_none();
    }
    /* Some(f): tag=1, one double field at offset 16. */
    void *some = march_alloc(16 + 8);
    int32_t *tp = (int32_t *)((char *)some + 8);
    tp[0] = 1;
    double *fp = (double *)((char *)some + 16);
    fp[0] = f;
    return some;
}

/* ── List builtins ───────────────────────────────────────────────────── */

/* list_append(a, b): append list b to list a. Returns new List. */
void *march_list_append(void *a, void *b) {
    int32_t tag = *(int32_t *)((char *)a + 8);
    if (tag == 0) return b;  /* Nil ++ b = b */
    /* Cons: head at offset 16, tail at offset 24. */
    void *head = *(void **)((char *)a + 16);
    void *tail = *(void **)((char *)a + 24);
    void *new_tail = march_list_append(tail, b);
    return make_cons(head, new_tail);
}

/* list_concat(list_of_lists): flatten List(List(a)) into List(a). */
void *march_list_concat(void *lists) {
    int32_t tag = *(int32_t *)((char *)lists + 8);
    if (tag == 0) return make_nil();  /* Nil */
    void *head = *(void **)((char *)lists + 16);
    void *tail = *(void **)((char *)lists + 24);
    void *rest = march_list_concat(tail);
    return march_list_append(head, rest);
}

/* ── File/Dir builtins ───────────────────────────────────────────────── */

int64_t march_file_exists(void *s) {
    march_string *ss = (march_string *)s;
    struct stat st;
    if (stat(ss->data, &st) != 0) return 0;
    return S_ISREG(st.st_mode) ? 1 : 0;
}

int64_t march_dir_exists(void *s) {
    march_string *ss = (march_string *)s;
    struct stat st;
    if (stat(ss->data, &st) != 0) return 0;
    return S_ISDIR(st.st_mode) ? 1 : 0;
}

/* ── File/Dir/CSV I/O helpers ────────────────────────────────────────── */

/* Create Result(Ok=0,Err=1) values; all file/dir/csv fns return Result. */
static void *mk_ok(void *value) {
    void *r = march_alloc(24); /* tag=0 by default */
    MARCH_FIELD(r, 0) = (int64_t)value;
    return r;
}
static void *mk_ok_unit(void) {
    /* Ok(()) — unit value is null/0 */
    void *r = march_alloc(24);
    MARCH_FIELD(r, 0) = 0;
    return r;
}
static void *mk_err(void *msg_str) {
    void *r = march_alloc(24);
    MARCH_SET_TAG(r, 1);
    MARCH_FIELD(r, 0) = (int64_t)msg_str;
    return r;
}
static void *mk_err_cstr(const char *msg) {
    return mk_err(march_string_lit(msg, (int64_t)strlen(msg)));
}
static void *mk_err_errno(void) {
    return mk_err_cstr(strerror(errno));
}

/* Build a March List(String) from an array of strings. */
static void *build_string_list(char **strs, int n) {
    /* Nil = alloc 16 bytes, tag=0 */
    void *lst = march_alloc(16); /* Nil */
    for (int i = n - 1; i >= 0; i--) {
        void *s = march_string_lit(strs[i], (int64_t)strlen(strs[i]));
        void *cons = march_alloc(32); /* Cons: header(16)+head(8)+tail(8) */
        MARCH_SET_TAG(cons, 1);
        MARCH_FIELD(cons, 0) = (int64_t)s;
        MARCH_FIELD(cons, 1) = (int64_t)lst;
        lst = cons;
    }
    return lst;
}

/* ── File I/O builtins ───────────────────────────────────────────────── */

void *march_file_read(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    FILE *f = fopen(ps->data, "rb");
    if (!f) return mk_err_errno();
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len < 0) { fclose(f); return mk_err_cstr("ftell failed"); }
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) { fclose(f); return mk_err_cstr("out of memory"); }
    size_t n = fread(buf, 1, (size_t)len, f);
    fclose(f);
    buf[n] = '\0';
    void *s = march_string_lit(buf, (int64_t)n);
    free(buf);
    return mk_ok(s);
}

void *march_file_write(void *path_ptr, void *data_ptr) {
    march_string *ps = (march_string *)path_ptr;
    march_string *ds = (march_string *)data_ptr;
    FILE *f = fopen(ps->data, "wb");
    if (!f) return mk_err_errno();
    size_t w = fwrite(ds->data, 1, (size_t)ds->len, f);
    fclose(f);
    if ((int64_t)w != ds->len) return mk_err_cstr("write failed");
    return mk_ok_unit();
}

void *march_file_append(void *path_ptr, void *data_ptr) {
    march_string *ps = (march_string *)path_ptr;
    march_string *ds = (march_string *)data_ptr;
    FILE *f = fopen(ps->data, "ab");
    if (!f) return mk_err_errno();
    size_t w = fwrite(ds->data, 1, (size_t)ds->len, f);
    fclose(f);
    if ((int64_t)w != ds->len) return mk_err_cstr("write failed");
    return mk_ok_unit();
}

void *march_file_delete(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    if (remove(ps->data) != 0) return mk_err_errno();
    return mk_ok_unit();
}

void *march_file_copy(void *src_ptr, void *dst_ptr) {
    march_string *src = (march_string *)src_ptr;
    march_string *dst = (march_string *)dst_ptr;
    FILE *in = fopen(src->data, "rb");
    if (!in) return mk_err_errno();
    FILE *out = fopen(dst->data, "wb");
    if (!out) { fclose(in); return mk_err_errno(); }
    char buf[8192];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0)
        fwrite(buf, 1, n, out);
    fclose(in);
    fclose(out);
    return mk_ok_unit();
}

void *march_file_rename(void *src_ptr, void *dst_ptr) {
    march_string *src = (march_string *)src_ptr;
    march_string *dst = (march_string *)dst_ptr;
    if (rename(src->data, dst->data) != 0) return mk_err_errno();
    return mk_ok_unit();
}

/* FileKind tags: RegularFile=0, Directory=1, Symlink=2, OtherKind=3 */
void *march_file_stat(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    struct stat st;
    if (stat(ps->data, &st) != 0) return mk_err_errno();
    int kind_tag = S_ISREG(st.st_mode) ? 0 :
                   S_ISDIR(st.st_mode) ? 1 :
                   S_ISLNK(st.st_mode) ? 2 : 3;
    void *kind = march_alloc(16); /* FileKind variant, no fields */
    MARCH_SET_TAG(kind, kind_tag);
    /* FileStat(size, kind, modified, accessed) — 4 fields, 48 bytes total */
    void *fs = march_alloc(48);
    MARCH_FIELD(fs, 0) = (int64_t)st.st_size;
    MARCH_FIELD(fs, 1) = (int64_t)kind;
    MARCH_FIELD(fs, 2) = (int64_t)st.st_mtime;
    MARCH_FIELD(fs, 3) = (int64_t)st.st_atime;
    return mk_ok(fs);
}

/* File handle: heap object with tag=0, field[0] = FILE* as int64_t */
void *march_file_open(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    FILE *f = fopen(ps->data, "rb");
    if (!f) return mk_err_errno();
    void *handle = march_alloc(24);
    MARCH_FIELD(handle, 0) = (int64_t)(uintptr_t)f;
    return mk_ok(handle);
}

void *march_file_close(void *handle_ptr) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    if (f) fclose(f);
    return mk_ok_unit();
}

void *march_file_read_line(void *handle_ptr) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    if (!f) return mk_err_cstr("file not open");
    char buf[4096];
    if (!fgets(buf, sizeof(buf), f)) {
        if (feof(f)) return mk_err_cstr("eof");
        return mk_err_errno();
    }
    size_t len = strlen(buf);
    /* Strip trailing newline */
    if (len > 0 && buf[len-1] == '\n') { buf[--len] = '\0'; }
    if (len > 0 && buf[len-1] == '\r') { buf[--len] = '\0'; }
    return mk_ok(march_string_lit(buf, (int64_t)len));
}

void *march_file_read_chunk(void *handle_ptr, int64_t size) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    if (!f || size <= 0) return mk_err_cstr("file not open");
    char *buf = (char *)malloc((size_t)size);
    if (!buf) return mk_err_cstr("out of memory");
    size_t n = fread(buf, 1, (size_t)size, f);
    void *s = march_string_lit(buf, (int64_t)n);
    free(buf);
    if (n == 0 && feof(f)) return mk_err_cstr("eof");
    return mk_ok(s);
}

/* ── Directory builtins ─────────────────────────────────────────────── */

void *march_dir_list(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    DIR *dir = opendir(ps->data);
    if (!dir) return mk_err_errno();
    /* Collect entries into a dynamic array */
    char **names = NULL;
    int n = 0, cap = 0;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;
        if (n >= cap) {
            cap = cap ? cap * 2 : 16;
            names = (char **)realloc(names, (size_t)cap * sizeof(char *));
        }
        names[n++] = strdup(ent->d_name);
    }
    closedir(dir);
    void *lst = build_string_list(names, n);
    for (int i = 0; i < n; i++) free(names[i]);
    free(names);
    return mk_ok(lst);
}

static int mkdir_p(const char *path) {
    char *p = strdup(path);
    for (char *s = p + 1; *s; s++) {
        if (*s == '/') {
            *s = '\0';
            mkdir(p, 0755);
            *s = '/';
        }
    }
    int r = mkdir(p, 0755);
    free(p);
    return r;
}

void *march_dir_mkdir(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    if (mkdir(ps->data, 0755) != 0 && errno != EEXIST) return mk_err_errno();
    return mk_ok_unit();
}

void *march_dir_mkdir_p(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    if (mkdir_p(ps->data) != 0 && errno != EEXIST) return mk_err_errno();
    return mk_ok_unit();
}

void *march_dir_rmdir(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    if (rmdir(ps->data) != 0) return mk_err_errno();
    return mk_ok_unit();
}

static int rm_rf(const char *path) {
    struct stat st;
    if (lstat(path, &st) != 0) return -1;
    if (!S_ISDIR(st.st_mode)) return remove(path);
    DIR *dir = opendir(path);
    if (!dir) return -1;
    struct dirent *ent;
    char buf[4096];
    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;
        snprintf(buf, sizeof(buf), "%s/%s", path, ent->d_name);
        rm_rf(buf);
    }
    closedir(dir);
    return rmdir(path);
}

void *march_dir_rm_rf(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    if (rm_rf(ps->data) != 0) return mk_err_errno();
    return mk_ok_unit();
}

/* ── Process builtins ──────────────────────────────────────────────── */

static int    g_argc = 0;
static char **g_argv = NULL;

void march_process_argv_init(int argc, char **argv) {
    g_argc = argc;
    g_argv = argv;
    /* Register GC trace flush once — safe to call multiple times (atexit dedup). */
    if (gc_trace_on()) atexit(gc_trace_atexit);
}

/* Returns List(String) of argv entries. */
void *march_process_argv(void) {
    void *list = make_nil();
    for (int i = g_argc - 1; i >= 0; i--) {
        void *s = march_string_lit(g_argv[i], (int64_t)strlen(g_argv[i]));
        list = make_cons(s, list);
    }
    return list;
}

/* ── Process builtins ──────────────────────────────────────────────── */

/* process_env(name) → Option(String) */
void *march_process_env(void *name_obj) {
    march_string *s = (march_string *)name_obj;
    char key[4096];
    size_t klen = s->len < (int64_t)sizeof(key) - 1 ? (size_t)s->len : sizeof(key) - 1;
    memcpy(key, s->data, klen);
    key[klen] = '\0';
    char *val = getenv(key);
    if (val == NULL) {
        return make_none();
    }
    void *str = march_string_lit(val, (int64_t)strlen(val));
    return make_some_ptr(str);
}

/* process_set_env(name, value) → Unit (returns i64 0) */
int64_t march_process_set_env(void *name_obj, void *value_obj) {
    march_string *n = (march_string *)name_obj;
    march_string *v = (march_string *)value_obj;
    char key[4096], val[65536];
    size_t kl = n->len < (int64_t)sizeof(key)-1 ? (size_t)n->len : sizeof(key)-1;
    size_t vl = v->len < (int64_t)sizeof(val)-1 ? (size_t)v->len : sizeof(val)-1;
    memcpy(key, n->data, kl); key[kl] = '\0';
    memcpy(val, v->data, vl); val[vl] = '\0';
    setenv(key, val, 1);
    return 0; /* Unit = i64 0 */
}

/* process_cwd() → String */
void *march_process_cwd(void) {
    char buf[4096];
    if (getcwd(buf, sizeof(buf)) == NULL) {
        return march_string_lit("", 0);
    }
    return march_string_lit(buf, (int64_t)strlen(buf));
}

/* process_exit(code) → Unit */
int64_t march_process_exit(int64_t code) {
    exit((int)code);
    return 0; /* unreachable */
}

/* process_pid() → Int */
int64_t march_process_pid(void) {
    return (int64_t)getpid();
}

/* process_spawn_sync(command, args) → Result(ProcessResult, String)
   ProcessResult = ProcessResult(Int, String, String) (exit_code, stdout, stderr) */
void *march_process_spawn_sync(void *cmd_obj, void *args_list) {
    march_string *cmd_s = (march_string *)cmd_obj;
    /* Count args */
    int extra = 0;
    void *tmp = args_list;
    while (((march_hdr *)tmp)->tag == 1) { extra++; tmp = MARCH_FIELD_PTR(tmp, 1); }
    int argc = 1 + extra;
    char **argv = (char **)malloc((size_t)(argc + 1) * sizeof(char *));
    /* argv[0] = command */
    argv[0] = (char *)malloc((size_t)(cmd_s->len + 1));
    memcpy(argv[0], cmd_s->data, (size_t)cmd_s->len);
    argv[0][cmd_s->len] = '\0';
    /* argv[1..] = args */
    int i = 1;
    tmp = args_list;
    while (((march_hdr *)tmp)->tag == 1) {
        march_string *a = (march_string *)MARCH_FIELD_PTR(tmp, 0);
        argv[i] = (char *)malloc((size_t)(a->len + 1));
        memcpy(argv[i], a->data, (size_t)a->len);
        argv[i][a->len] = '\0';
        i++;
        tmp = MARCH_FIELD_PTR(tmp, 1);
    }
    argv[argc] = NULL;
    /* Execute via fork+exec */
    int stdout_pipe[2], stderr_pipe[2];
    if (pipe(stdout_pipe) != 0 || pipe(stderr_pipe) != 0) {
        for (int j = 0; j < argc; j++) free(argv[j]);
        free(argv);
        return mk_err_cstr("pipe failed");
    }
    pid_t pid = fork();
    if (pid == 0) {
        close(stdout_pipe[0]); close(stderr_pipe[0]);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[1]); close(stderr_pipe[1]);
        execvp(argv[0], argv);
        _exit(127);
    }
    close(stdout_pipe[1]); close(stderr_pipe[1]);
    for (int j = 0; j < argc; j++) free(argv[j]);
    free(argv);
    if (pid < 0) return mk_err_cstr("fork failed");
    /* Read stdout and stderr */
    char out_buf[65536]; size_t out_len = 0;
    char err_buf[16384]; size_t err_len = 0;
    ssize_t nr;
    while (out_len < sizeof(out_buf) &&
           (nr = read(stdout_pipe[0], out_buf + out_len, sizeof(out_buf) - out_len)) > 0)
        out_len += (size_t)nr;
    while (err_len < sizeof(err_buf) &&
           (nr = read(stderr_pipe[0], err_buf + err_len, sizeof(err_buf) - err_len)) > 0)
        err_len += (size_t)nr;
    close(stdout_pipe[0]); close(stderr_pipe[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    /* Build ProcessResult(exit_code, stdout, stderr): tag=0, 3 fields */
    void *out_str = march_string_lit(out_buf, (int64_t)out_len);
    void *err_str = march_string_lit(err_buf, (int64_t)err_len);
    void *pr = march_alloc(16 + 24); /* header(16) + 3 fields * 8 */
    MARCH_FIELD(pr, 0) = exit_code;
    MARCH_FIELD(pr, 1) = (int64_t)out_str;
    MARCH_FIELD(pr, 2) = (int64_t)err_str;
    return mk_ok(pr);
}

/* process_spawn_lines(command, args) → Result(Seq(String), String) */
void *march_process_spawn_lines(void *cmd_obj, void *args_list) {
    /* Run command and return Ok(stdout_string) — caller can split lines */
    void *result = march_process_spawn_sync(cmd_obj, args_list);
    /* If Ok(ProcessResult), extract stdout and return Ok(stdout) */
    if (((march_hdr *)result)->tag == 0) {
        void *pr = MARCH_FIELD_PTR(result, 0);
        void *out_str = MARCH_FIELD_PTR(pr, 1);
        return mk_ok(out_str);
    }
    return result; /* Err case: pass through */
}

/* ── CSV builtins ───────────────────────────────────────────────────── */

/* CSV handle: heap object with fields:
   [0] = FILE* (as int64_t)
   [1] = delimiter char code (int64_t)
   [2] = mode (0=simple, 1=rfc4180) */
typedef struct {
    FILE *f;
    char delim;
    int rfc4180;
} csv_handle;

static void *csv_row_result(void *fields_list) {
    /* Row(fields) — constructor tag 0, 1 field */
    void *row = march_alloc(24);
    /* tag=0 for Row (first/only constructor) */
    MARCH_FIELD(row, 0) = (int64_t)fields_list;
    return row;
}

/* Parse one CSV row from f according to delimiter/mode.
   Returns a March List(String) or NULL on EOF. */
static void **csv_parse_row_fields(FILE *f, char delim, int rfc4180,
                                   int *out_n) {
    int cap = 8, n = 0;
    void **fields = (void **)malloc((size_t)cap * sizeof(void *));
    char buf[65536];
    int buf_len = 0;
    int in_quote = 0, at_eof = 0;

    while (1) {
        int c = fgetc(f);
        if (c == EOF) { at_eof = 1; break; }
        if (rfc4180 && c == '"') {
            if (!in_quote) { in_quote = 1; continue; }
            int next = fgetc(f);
            if (next == '"') { if (buf_len < 65535) buf[buf_len++] = '"'; }
            else { in_quote = 0; ungetc(next, f); }
            continue;
        }
        if (!in_quote && c == delim) {
            /* End of field */
            if (n >= cap) { cap *= 2; fields = (void **)realloc(fields, (size_t)cap * sizeof(void *)); }
            fields[n++] = march_string_lit(buf, buf_len);
            buf_len = 0;
            continue;
        }
        if (!in_quote && (c == '\n' || c == '\r')) {
            if (c == '\r') { int next = fgetc(f); if (next != '\n') ungetc(next, f); }
            break; /* End of row */
        }
        if (buf_len < 65535) buf[buf_len++] = (char)c;
    }

    /* Last field */
    if (!at_eof || buf_len > 0 || n > 0) {
        if (n >= cap) { cap *= 2; fields = (void **)realloc(fields, (size_t)cap * sizeof(void *)); }
        fields[n++] = march_string_lit(buf, buf_len);
    }
    if (at_eof && n == 0) { free(fields); *out_n = 0; return NULL; }
    *out_n = n;
    return fields;
}

void *march_csv_open(void *path_ptr, void *delim_ptr, void *mode_ptr) {
    (void)mode_ptr; /* mode stored but we always use rfc4180 for now */
    march_string *ps = (march_string *)path_ptr;
    march_string *ds = (march_string *)delim_ptr;
    FILE *f = fopen(ps->data, "rb");
    if (!f) return mk_err_errno();
    char delim = (ds->len > 0) ? ds->data[0] : ',';
    /* handle: 3 fields: FILE*, delim, mode */
    void *h = march_alloc(40);
    MARCH_FIELD(h, 0) = (int64_t)(uintptr_t)f;
    MARCH_FIELD(h, 1) = (int64_t)(uint8_t)delim;
    MARCH_FIELD(h, 2) = 1; /* rfc4180 */
    return mk_ok(h);
}

void *march_csv_close(void *handle_ptr) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    if (f) { fclose(f); MARCH_FIELD(handle_ptr, 0) = 0; }
    return mk_ok_unit();
}

/* Returns Row(List(String)) or :eof (null) */
void *march_csv_next_row(void *handle_ptr) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    char delim = (char)(uint8_t)MARCH_FIELD(handle_ptr, 1);
    int rfc4180 = (int)MARCH_FIELD(handle_ptr, 2);
    if (!f) return NULL; /* eof = null = atom */
    int n = 0;
    void **fields = csv_parse_row_fields(f, delim, rfc4180, &n);
    if (!fields) return NULL; /* EOF → :eof (null) */
    /* Build List(String) from fields */
    void *lst = march_alloc(16); /* Nil, tag=0 */
    for (int i = n - 1; i >= 0; i--) {
        void *cons = march_alloc(32);
        MARCH_SET_TAG(cons, 1);
        MARCH_FIELD(cons, 0) = (int64_t)fields[i];
        MARCH_FIELD(cons, 1) = (int64_t)lst;
        lst = cons;
    }
    free(fields);
    return csv_row_result(lst);
}

/* ── Capability builtins ─────────────────────────────────────────────── */

/* cap_narrow: attenuates a capability to a sub-capability.
   In compiled mode, capabilities are opaque pointers (just pass through). */
void *march_cap_narrow(void *cap) {
    return cap;
}

/* ── Monitor/supervision builtins ────────────────────────────────────── */

/* demonitor: cancel a monitor subscription. Removes the entry from the
   target actor's monitor_head list (best-effort; no-op if ref not found). */
void march_demonitor(int64_t ref) {
    /* Scan all actor meta entries looking for the ref. */
    pthread_mutex_lock(&g_tbl_mu);
    for (int b = 0; b < MARCH_SCHED_BUCKETS; b++) {
        march_actor_meta *m = g_actor_tbl[b];
        while (m) {
            march_monitor_node **pp = &m->monitor_head;
            while (*pp) {
                if ((*pp)->mon_ref == ref) {
                    march_monitor_node *dead = *pp;
                    *pp = dead->next;
                    free(dead);
                    pthread_mutex_unlock(&g_tbl_mu);
                    return;
                }
                pp = &(*pp)->next;
            }
            m = m->tbl_next;
        }
    }
    pthread_mutex_unlock(&g_tbl_mu);
}

/* link: establish a bidirectional crash-propagation link.
   Implemented as two one-way monitors; when either actor dies, the other
   gets a Down notification (and the default behaviour is to crash too —
   supervision should be used if restart is desired).
   No-op if either pointer is not a valid heap actor. */
void march_link(void *actor_a, void *actor_b) {
    if (!IS_HEAP_PTR(actor_a) || !IS_HEAP_PTR(actor_b)) return;
    /* Two one-way monitors: a watches b and b watches a. */
    march_monitor(actor_a, actor_b);
    march_monitor(actor_b, actor_a);
}

/* unlink: cancel the bidirectional link between two actors.
   Best-effort: scans for and removes both one-way monitor nodes. */
void march_unlink(void *actor_a, void *actor_b) {
    if (!IS_HEAP_PTR(actor_a) || !IS_HEAP_PTR(actor_b)) return;
    /* Scan actor_b's monitor list for a node watching actor_a. */
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *mb = g_actor_tbl[actor_bucket(actor_b)];
    while (mb && mb->actor != actor_b) mb = mb->tbl_next;
    if (mb) {
        march_monitor_node **pp = &mb->monitor_head;
        while (*pp) {
            if ((*pp)->watcher == actor_a) {
                march_monitor_node *dead = *pp;
                *pp = dead->next;
                free(dead);
                break;
            }
            pp = &(*pp)->next;
        }
    }
    /* Scan actor_a's monitor list for a node watching actor_b. */
    march_actor_meta *ma = g_actor_tbl[actor_bucket(actor_a)];
    while (ma && ma->actor != actor_a) ma = ma->tbl_next;
    if (ma) {
        march_monitor_node **pp = &ma->monitor_head;
        while (*pp) {
            if ((*pp)->watcher == actor_b) {
                march_monitor_node *dead = *pp;
                *pp = dead->next;
                free(dead);
                break;
            }
            pp = &(*pp)->next;
        }
    }
    pthread_mutex_unlock(&g_tbl_mu);
}

/* register_supervisor: record supervision metadata for an actor.
   strategy: 0=one_for_one, 1=one_for_all, 2=rest_for_one.
   The actor must already be registered via march_spawn.
   This is a metadata call; actual restart logic is driven by Down events. */
void march_register_supervisor(void *supervisor, int64_t strategy,
                                int64_t max_restarts, int64_t window_secs) {
    if (!IS_HEAP_PTR(supervisor)) return;
    march_actor_meta *meta = find_or_create_meta(supervisor);
    meta->supervisor_strategy  = (int)strategy;
    meta->supervisor_max_restarts = max_restarts;
    meta->supervisor_window_secs  = window_secs;
}

/* monitor: establish a monitor link from watcher to target.
   Returns a unique monitor ref.  If target is already dead,
   delivers Down immediately by incrementing watcher's down_count. */
int64_t march_monitor(void *watcher, void *target) {
    int64_t ref = atomic_fetch_add_explicit(&g_next_monitor_ref, 1,
                                             memory_order_relaxed);
    if (!IS_HEAP_PTR(target)) {
        /* Target is an integer/non-heap ptr — treat as dead. */
        march_actor_meta *wm = find_or_create_meta(watcher);
        atomic_fetch_add_explicit(&wm->down_count, 1, memory_order_relaxed);
        return ref;
    }
    int64_t *tfields = (int64_t *)target;
    int target_alive = (int)tfields[3];
    if (!target_alive) {
        /* Target already dead — deliver Down immediately. */
        march_actor_meta *wm = find_or_create_meta(watcher);
        atomic_fetch_add_explicit(&wm->down_count, 1, memory_order_relaxed);
        return ref;
    }
    /* Register on target's monitor list. */
    march_monitor_node *node = (march_monitor_node *)malloc(sizeof(march_monitor_node));
    if (!node) return ref;
    node->watcher = watcher;
    node->mon_ref = ref;
    march_actor_meta *tm = find_or_create_meta(target);
    pthread_mutex_lock(&g_tbl_mu);
    node->next = tm->monitor_head;
    tm->monitor_head = node;
    pthread_mutex_unlock(&g_tbl_mu);
    return ref;
}

/* mailbox_size: return count of Down messages delivered to this actor's
   "down_count" (watcher side only — regular actor messages are not counted). */
int64_t march_mailbox_size(void *pid) {
    if (!IS_HEAP_PTR(pid)) return 0;
    march_actor_meta *meta = find_meta(pid);
    if (!meta) return 0;
    return atomic_load_explicit(&meta->down_count, memory_order_relaxed);
}

/* run_until_idle: flush the async message queue by running the scheduler. */
void march_run_until_idle(void) {
    march_run_scheduler();
}

/* register_resource: register a cleanup callback for an actor.
 * cleanup is a March closure of type Unit -> Unit.
 * Callbacks run in reverse acquisition order when kill() is called. */
void march_register_resource(void *pid, void *name, void *cleanup) {
    (void)name;  /* Name is for documentation only */
    if (!IS_HEAP_PTR(pid)) return;
    march_actor_meta *meta = find_meta(pid);
    if (!meta) return;
    march_cleanup_node *node = (march_cleanup_node *)malloc(sizeof(march_cleanup_node));
    if (!node) return;
    node->cleanup_fn = cleanup;
    /* Prepend: most recently registered is at head → LIFO on kill */
    node->next = meta->cleanup_head;
    meta->cleanup_head = node;
    march_incrc(cleanup);  /* Keep closure alive */
}

/* get_cap: get the capability associated with an actor pid.
   Returns None (tag=0) — capability enforcement is compile-time only. */
void *march_get_cap(void *pid) {
    (void)pid;
    void *none = march_alloc(16);
    /* tag 0 = None, already zeroed by march_alloc */
    return none;
}

/* ── Capability revocation table ──────────────────────────────────────── */
/* Each revoked capability is stored as a (pid_index, epoch) pair in a
 * singly-linked list protected by a single mutex.  The table is small in
 * practice (revocations are rare) so linear search is acceptable. */

typedef struct march_revoc_entry {
    int64_t                  pid_index;
    int64_t                  epoch;
    struct march_revoc_entry *next;
} march_revoc_entry;

static march_revoc_entry *g_revoc_head = NULL;
static pthread_mutex_t    g_revoc_mu   = PTHREAD_MUTEX_INITIALIZER;

/* Check whether (pid_index, epoch) appears in the revocation table.
 * Caller must NOT hold g_revoc_mu. */
static int revoc_contains(int64_t pid_index, int64_t epoch) {
    pthread_mutex_lock(&g_revoc_mu);
    march_revoc_entry *e = g_revoc_head;
    while (e) {
        if (e->pid_index == pid_index && e->epoch == epoch) {
            pthread_mutex_unlock(&g_revoc_mu);
            return 1;
        }
        e = e->next;
    }
    pthread_mutex_unlock(&g_revoc_mu);
    return 0;
}

/* revoke_cap(pid_index, epoch): add (pid_index, epoch) to the revocation table.
 * Idempotent — does nothing if already revoked. */
void march_revoke_cap(int64_t pid_index, int64_t epoch) {
    if (revoc_contains(pid_index, epoch)) return;
    march_revoc_entry *e = malloc(sizeof(march_revoc_entry));
    if (!e) return;
    e->pid_index = pid_index;
    e->epoch     = epoch;
    pthread_mutex_lock(&g_revoc_mu);
    e->next      = g_revoc_head;
    g_revoc_head = e;
    pthread_mutex_unlock(&g_revoc_mu);
}

/* is_cap_valid(pid_index, epoch): return 1 if the capability is valid, 0 otherwise.
 * A capability is invalid if it is in the revocation table, the actor is dead,
 * or the actor's current epoch differs. */
int64_t march_is_cap_valid(int64_t pid_index, int64_t epoch) {
    if (revoc_contains(pid_index, epoch)) return 0;
    /* Look up actor by pid_index to check liveness and current epoch. */
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *m = NULL;
    for (int i = 0; i < MARCH_SCHED_BUCKETS; i++) {
        march_actor_meta *cur = g_actor_tbl[i];
        while (cur) {
            if (cur->pid_index == pid_index) { m = cur; break; }
            cur = cur->tbl_next;
        }
        if (m) break;
    }
    pthread_mutex_unlock(&g_tbl_mu);
    if (!m || !march_is_alive(m->actor)) return 0;
    if (m->epoch != epoch) return 0;
    return 1;
}

/* send_checked: send a message to an actor with capability check.
 * Validates liveness, epoch match, and revocation before enqueuing. */
void march_send_checked(void *cap, void *msg) {
    (void)cap; (void)msg;
    /* TODO(Phase 3 compiled): extract pid_index and epoch from cap object,
     * call march_is_cap_valid, then march_send on success.
     * The interpreter path (eval.ml) fully implements this; the compiled
     * path is pending TIR lowering of VCap values. */
}

/* pid_of_int: cast an integer to a Pid (unsafe, for supervisor state fields). */
void *march_pid_of_int(int64_t n) {
    return (void *)(intptr_t)n;
}

/* get_actor_field: retrieve a named field from an actor's state. Stub: returns None. */
void *march_get_actor_field(void *pid, void *name) {
    (void)pid; (void)name;
    void *none = march_alloc(16);
    /* tag 0 = None, already zeroed by march_alloc */
    return none;
}

/* ── Value pretty-printing ───────────────────────────────────────────── */

/* Format a March value as a human-readable string.
   If v is a registered actor (Pid), prints Pid(n).
   Otherwise prints #<tag:N> for heap objects. */
void *march_value_to_string(void *v) {
    if (!v) return march_string_lit("nil", 3);
    /* Check if this pointer is a registered actor → display as Pid(n) */
    march_actor_meta *meta = find_meta(v);
    if (meta) {
        char buf[64];
        int n = snprintf(buf, sizeof(buf), "Pid(%lld)", (long long)meta->pid_index);
        return march_string_lit(buf, n);
    }
    march_hdr *h = (march_hdr *)v;
    int32_t tag = h->tag;
    char buf[128];
    int n = snprintf(buf, sizeof(buf), "#<tag:%d>", tag);
    return march_string_lit(buf, n);
}

/* ── Resource ownership ──────────────────────────────────────────────── */

/* own(pid, value): register a linear resource with an actor for cleanup.
 * Compiled stub — full implementation requires Drop trait dispatch at runtime. */
void march_own(void *pid, void *value) {
    (void)pid; (void)value;
    /* TODO: look up Drop impl for value's type and call register_resource */
}

/* ── Time builtins ───────────────────────────────────────────────────── */

double march_unix_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* ── TypedArray builtins ─────────────────────────────────────────────── */
/* TypedArray is a heap object with layout:
 *   [rc:i64][tag:i32][pad:i32][len:i64][cap:i64][elements: void*[]]
 * Each element slot is 8 bytes — can hold i64, double (bitcast), or ptr. */
#define TYPED_ARRAY_HDR_SIZE (16 + 8 + 8)  /* hdr + len + cap */

static void *typed_array_alloc(int64_t len) {
    size_t sz = (size_t)(TYPED_ARRAY_HDR_SIZE + len * 8);
    void *arr = march_alloc((int64_t)sz);
    *(int64_t *)((char *)arr + 16) = len;   /* len field */
    *(int64_t *)((char *)arr + 24) = len;   /* cap field */
    return arr;
}

void *march_typed_array_from_list(void *list) {
    /* Count list length first */
    int64_t n = 0;
    void *tmp = list;
    while (*(int32_t *)((char *)tmp + 8) == 1) {
        n++;
        tmp = *(void **)((char *)tmp + 24);
    }
    void *arr = typed_array_alloc(n);
    void *cur = list;
    for (int64_t i = 0; i < n; i++) {
        void *elem = *(void **)((char *)cur + 16);
        *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8) = elem;
        cur = *(void **)((char *)cur + 24);
    }
    return arr;
}

void *march_typed_array_to_list(void *arr) {
    int64_t len = *(int64_t *)((char *)arr + 16);
    /* Build list in reverse order, then it's correct */
    void *lst = make_nil();
    for (int64_t i = len - 1; i >= 0; i--) {
        void *elem = *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8);
        lst = make_cons(elem, lst);
    }
    return lst;
}

int64_t march_typed_array_length(void *arr) {
    return *(int64_t *)((char *)arr + 16);
}

void *march_typed_array_get(void *arr, int64_t i) {
    return *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8);
}

void *march_typed_array_set(void *arr, int64_t i, void *val) {
    void *new_arr = march_alloc((int64_t)(TYPED_ARRAY_HDR_SIZE + march_typed_array_length(arr) * 8));
    int64_t len = march_typed_array_length(arr);
    *(int64_t *)((char *)new_arr + 16) = len;
    *(int64_t *)((char *)new_arr + 24) = len;
    memcpy((char *)new_arr + TYPED_ARRAY_HDR_SIZE,
           (char *)arr + TYPED_ARRAY_HDR_SIZE,
           (size_t)(len * 8));
    *(void **)((char *)new_arr + TYPED_ARRAY_HDR_SIZE + i * 8) = val;
    return new_arr;
}

void *march_typed_array_create(int64_t len, void *default_val) {
    void *arr = typed_array_alloc(len);
    for (int64_t i = 0; i < len; i++)
        *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8) = default_val;
    return arr;
}

void *march_typed_array_map(void *arr, void *f) {
    int64_t len = march_typed_array_length(arr);
    void *new_arr = typed_array_alloc(len);
    for (int64_t i = 0; i < len; i++) {
        void *elem = march_typed_array_get(arr, i);
        /* Call closure: load fn ptr from field 0, call f(f_clo, elem) */
        void *fn_ptr_loc = (char *)f + 8;
        void (*fn)(void) = *(void (**)(void))fn_ptr_loc;
        void *(*fn_typed)(void*, void*) = (void *(*)(void*, void*))fn;
        void *result = fn_typed(f, elem);
        *(void **)((char *)new_arr + TYPED_ARRAY_HDR_SIZE + i * 8) = result;
    }
    return new_arr;
}

void *march_typed_array_filter(void *arr, void *f) {
    int64_t len = march_typed_array_length(arr);
    void **temp = malloc((size_t)(len * 8));
    int64_t count = 0;
    for (int64_t i = 0; i < len; i++) {
        void *elem = march_typed_array_get(arr, i);
        void *fn_ptr_loc = (char *)f + 8;
        void (*fn)(void) = *(void (**)(void))fn_ptr_loc;
        int64_t (*fn_typed)(void*, void*) = (int64_t (*)(void*, void*))fn;
        if (fn_typed(f, elem)) temp[count++] = elem;
    }
    void *new_arr = typed_array_alloc(count);
    memcpy((char *)new_arr + TYPED_ARRAY_HDR_SIZE, temp, (size_t)(count * 8));
    free(temp);
    return new_arr;
}

void *march_typed_array_fold(void *arr, void *acc, void *f) {
    int64_t len = march_typed_array_length(arr);
    void *result = acc;
    for (int64_t i = 0; i < len; i++) {
        void *elem = march_typed_array_get(arr, i);
        void *fn_ptr_loc = (char *)f + 8;
        void (*fn)(void) = *(void (**)(void))fn_ptr_loc;
        void *(*fn_typed)(void*, void*, void*) = (void *(*)(void*, void*, void*))fn;
        result = fn_typed(f, result, elem);
    }
    return result;
}

/* ── Logger builtins ─────────────────────────────────────────────────── */

static int64_t march_logger_level_val = 0;   /* Debug=0, Info=1, Warn=2, Error=3 */
static void   *march_logger_ctx_list  = NULL; /* March List((String,String)) or NULL (init on first use) */
static pthread_mutex_t march_logger_mutex = PTHREAD_MUTEX_INITIALIZER;

static void *logger_nil(void) {
    return march_alloc(16);
}

static void *logger_cons(void *head, void *tail) {
    void *cons = march_alloc(32);
    *(int32_t *)((char *)cons + 8) = 1;
    void **fp = (void **)((char *)cons + 16);
    fp[0] = head;
    fp[1] = tail;
    return cons;
}

static void *logger_tuple2(void *a, void *b) {
    void *tup = march_alloc(32);
    /* tag stays 0 */
    void **fp = (void **)((char *)tup + 16);
    fp[0] = a;
    fp[1] = b;
    return tup;
}

/* Print a March List((String,String)) as  key=val, key2=val2 */
static void logger_print_pairs(void *lst) {
    int first = 1;
    while (1) {
        int32_t tag = *(int32_t *)((char *)lst + 8);
        if (tag == 0) break;  /* Nil */
        void *tup  = *(void **)((char *)lst + 16);
        lst        = *(void **)((char *)lst + 24);
        void *k    = *(void **)((char *)tup + 16);
        void *v    = *(void **)((char *)tup + 24);
        march_string *ks = (march_string *)k;
        march_string *vs = (march_string *)v;
        if (!first) fputs(", ", stderr);
        fwrite(ks->data, 1, (size_t)ks->len, stderr);
        fputc('=', stderr);
        fwrite(vs->data, 1, (size_t)vs->len, stderr);
        first = 0;
    }
}

void *march_logger_set_level(int64_t level) {
    pthread_mutex_lock(&march_logger_mutex);
    march_logger_level_val = level;
    pthread_mutex_unlock(&march_logger_mutex);
    return logger_nil();
}

int64_t march_logger_get_level(void) {
    return march_logger_level_val;
}

void *march_logger_add_context(void *key, void *value) {
    pthread_mutex_lock(&march_logger_mutex);
    if (!march_logger_ctx_list) march_logger_ctx_list = logger_nil();
    void *tup = logger_tuple2(key, value);
    march_logger_ctx_list = logger_cons(tup, march_logger_ctx_list);
    pthread_mutex_unlock(&march_logger_mutex);
    return logger_nil();
}

void *march_logger_clear_context(void) {
    pthread_mutex_lock(&march_logger_mutex);
    march_logger_ctx_list = logger_nil();
    pthread_mutex_unlock(&march_logger_mutex);
    return logger_nil();
}

void *march_logger_get_context(void) {
    pthread_mutex_lock(&march_logger_mutex);
    void *ctx = march_logger_ctx_list ? march_logger_ctx_list : logger_nil();
    pthread_mutex_unlock(&march_logger_mutex);
    return ctx;
}

/* logger_write(level_str, msg, ctx, extra) → unit
 * Writes:  [LEVEL] message {ctx_key=val, extra_key=val}  to stderr. */
void *march_logger_write(void *level_str, void *msg, void *ctx, void *extra) {
    march_string *ls = (march_string *)level_str;
    march_string *ms = (march_string *)msg;
    fputc('[', stderr);
    fwrite(ls->data, 1, (size_t)ls->len, stderr);
    fputs("] ", stderr);
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
    /* Check if either ctx or extra has any entries */
    int32_t ctx_tag   = *(int32_t *)((char *)ctx   + 8);
    int32_t extra_tag = *(int32_t *)((char *)extra  + 8);
    if (ctx_tag != 0 || extra_tag != 0) {
        fputs(" {", stderr);
        logger_print_pairs(ctx);
        /* If both non-empty, separate with comma */
        if (ctx_tag != 0 && extra_tag != 0) fputs(", ", stderr);
        logger_print_pairs(extra);
        fputc('}', stderr);
    }
    fputc('\n', stderr);
    return logger_nil();
}
