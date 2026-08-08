#include "march_runtime.h"
#include "march_scheduler.h"
#include "march_dispatch.h"
#include "march_monitor_registry.h"
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
#include <sys/time.h>
#include <errno.h>
#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>
#include <setjmp.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <signal.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <execinfo.h>
#include <pthread.h>

/* Optional OOM forensics: set MARCH_DEBUG_OOM=1 to print the requested size
 * and a backtrace when march_alloc/march_string_alloc fail.  A failure with a
 * huge/bogus size is the signature of a corrupted heap value's length header
 * being read as pointer garbage rather than real memory pressure; the
 * backtrace pinpoints which allocation call site observed the corruption.
 * Off by default (no-op, no overhead) so this never affects production
 * behavior unless explicitly enabled for debugging. */
static int march_debug_oom_enabled(void) {
    static int v = -1;
    if (v == -1) {
        const char *e = getenv("MARCH_DEBUG_OOM");
        v = (e && *e && strcmp(e, "0") != 0) ? 1 : 0;
    }
    return v;
}
static void march_debug_report_oom(const char *where, int64_t requested) {
    if (!march_debug_oom_enabled()) return;
    fprintf(stderr, "\n=== march DEBUG OOM in %s ===\n", where);
    fprintf(stderr, "  requested size: %lld (0x%llx)\n",
            (long long)requested, (unsigned long long)requested);
    fprintf(stderr, "  pthread_self:   %p\n", (void *)pthread_self());
    void *bt[64];
    int n = backtrace(bt, 64);
    fprintf(stderr, "  backtrace (%d frames):\n", n);
    backtrace_symbols_fd(bt, n, 2 /* stderr */);
    fprintf(stderr, "=== end DEBUG OOM ===\n\n");
    fflush(stderr);
}

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

/* ── String statistics (MARCH_STRING_STATS=1) ────────────────────────────
 * Opt-in profiling counters for the phase 1 string measurement — see
 * specs/2026-07-26-string-performance-design.md.  They exist to answer one
 * question with data instead of intuition: whether march_string's single
 * contiguous representation should grow a small-string optimisation, a
 * borrowed-view variant, or neither.
 *
 * OFF by default.  When off the cost is one predictable branch inside
 * functions that are already calling malloc or memcpy; `--verify-overhead`
 * in bench/run_string_bench.sh asserts that stays under 2%.
 *
 * Relaxed atomics throughout, mirroring march_live_alloc_count: these are a
 * profiling aid, not a synchronisation mechanism, and stronger ordering
 * would distort the very timings being measured. */
static pthread_mutex_t str_stats_mutex = PTHREAD_MUTEX_INITIALIZER;
static int str_stats_state = 0;  /* 0 = uninit, 1 = on, -1 = off */

#define MARCH_STR_NBUCKETS 7
static _Atomic int64_t str_alloc_count;
static _Atomic int64_t str_alloc_bytes;
static _Atomic int64_t str_free_count;
static _Atomic int64_t str_copy_bytes;
static _Atomic int64_t str_live_bytes;
static _Atomic int64_t str_peak_bytes;
static _Atomic int64_t str_hist[MARCH_STR_NBUCKETS];
/* Non-string heap objects (march_alloc): cons cells, tuples, ADT payloads.
 * Needed because the cost of a list-returning string operation lives almost
 * entirely here, NOT in the string counters — String.split allocates one
 * string AND one cons cell per field, but the cons cell goes through
 * march_alloc and is invisible to str_alloc_count.  Without this,
 * bench/string_split_large and bench/string_slice_walk report near-identical
 * `allocs` (measured: 9_000_126 vs 9_000_006) and the pair cannot attribute
 * cost to the list structure at all — which is the comparison they exist to
 * make. */
static _Atomic int64_t obj_alloc_count;
static _Atomic int64_t obj_alloc_bytes;

static const char *str_hist_names[MARCH_STR_NBUCKETS] = {
    "hist_le7", "hist_le15", "hist_le23", "hist_le31",
    "hist_le63", "hist_le255", "hist_gt255"
};

/* Bucket bounds chosen for the SSO decision: 23 bytes is what would fit
 * inline in the footprint the 24-byte march_string header already occupies,
 * so the <=23 buckets are exactly the strings an SSO could make free. */
static inline int str_bucket(int64_t len) {
    if (len <=   7) return 0;
    if (len <=  15) return 1;
    if (len <=  23) return 2;
    if (len <=  31) return 3;
    if (len <=  63) return 4;
    if (len <= 255) return 5;
    return 6;
}

static void str_stats_dump(void) {
    fprintf(stderr, "march_string_stats allocs %lld\n",
            (long long)atomic_load_explicit(&str_alloc_count, memory_order_relaxed));
    fprintf(stderr, "march_string_stats alloc_bytes %lld\n",
            (long long)atomic_load_explicit(&str_alloc_bytes, memory_order_relaxed));
    fprintf(stderr, "march_string_stats frees %lld\n",
            (long long)atomic_load_explicit(&str_free_count, memory_order_relaxed));
    fprintf(stderr, "march_string_stats copy_bytes %lld\n",
            (long long)atomic_load_explicit(&str_copy_bytes, memory_order_relaxed));
    fprintf(stderr, "march_string_stats peak_live_bytes %lld\n",
            (long long)atomic_load_explicit(&str_peak_bytes, memory_order_relaxed));
    fprintf(stderr, "march_string_stats obj_allocs %lld\n",
            (long long)atomic_load_explicit(&obj_alloc_count, memory_order_relaxed));
    fprintf(stderr, "march_string_stats obj_alloc_bytes %lld\n",
            (long long)atomic_load_explicit(&obj_alloc_bytes, memory_order_relaxed));
    for (int i = 0; i < MARCH_STR_NBUCKETS; i++)
        fprintf(stderr, "march_string_stats %s %lld\n", str_hist_names[i],
                (long long)atomic_load_explicit(&str_hist[i], memory_order_relaxed));
}

static void str_stats_init_locked(void) {
    const char *e = getenv("MARCH_STRING_STATS");
    if (e && *e && strcmp(e, "0") != 0) {
        str_stats_state = 1;
        atexit(str_stats_dump);
    } else {
        str_stats_state = -1;
    }
}

/* Lazy single-check, same shape as gc_trace_on. */
static inline int str_stats_on(void) {
    if (__builtin_expect(str_stats_state != 0, 1)) return str_stats_state > 0;
    pthread_mutex_lock(&str_stats_mutex);
    if (str_stats_state == 0) str_stats_init_locked();
    pthread_mutex_unlock(&str_stats_mutex);
    return str_stats_state > 0;
}

/* Tally one string allocation of [len] payload bytes, maintaining the running
 * peak of live string bytes with a CAS loop (relaxed: the peak is a report,
 * not a synchronisation point, so a racing under-observation is acceptable). */
static void str_stats_alloc(int64_t len) {
    atomic_fetch_add_explicit(&str_alloc_count, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&str_alloc_bytes, len, memory_order_relaxed);
    atomic_fetch_add_explicit(&str_hist[str_bucket(len)], 1, memory_order_relaxed);
    int64_t live = atomic_fetch_add_explicit(&str_live_bytes, len,
                                             memory_order_relaxed) + len;
    int64_t peak = atomic_load_explicit(&str_peak_bytes, memory_order_relaxed);
    while (live > peak &&
           !atomic_compare_exchange_weak_explicit(
               &str_peak_bytes, &peak, live,
               memory_order_relaxed, memory_order_relaxed)) { }
}

static void str_stats_free(int64_t len) {
    atomic_fetch_add_explicit(&str_free_count, 1, memory_order_relaxed);
    atomic_fetch_sub_explicit(&str_live_bytes, len, memory_order_relaxed);
}

/* memcpy with opt-in byte accounting.  Every string-BUILDING copy in this
 * file routes through here, so copy_bytes measures exactly the work a
 * borrowed-view representation could eliminate.  Copies outside the string
 * operations (scheduler, HTTP, actor mailboxes) deliberately keep plain
 * memcpy: counting them would make the number mean nothing.
 *
 * Called once per operation, never per byte — a per-byte call would put the
 * str_stats_on() branch inside the copy loop and break the <2% off-path
 * budget that bench/run_string_bench.sh --verify-overhead enforces. */
static inline void march_str_copy(void *dst, const void *src, size_t n) {
    memcpy(dst, src, n);
    if (str_stats_on())
        atomic_fetch_add_explicit(&str_copy_bytes, (int64_t)n,
                                  memory_order_relaxed);
}

/* Tally [n] bytes moved by a hand-written byte loop rather than a memcpy.
 * to_lowercase/to_uppercase/reverse transform while they copy, so they cannot
 * call march_str_copy — but they move exactly as many bytes, and a view
 * representation would not help them either way.  Leaving them out made
 * bench/string_case report ~1MB copied for 400MB of actual work, which would
 * have understated the copy total by two orders of magnitude in precisely the
 * benchmark built to measure transform cost. */
static inline void str_stats_copied(int64_t n) {
    if (str_stats_on())
        atomic_fetch_add_explicit(&str_copy_bytes, n, memory_order_relaxed);
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

/* Net count of live march objects (alloc +, free-on-rc=0 -).  An FFI/test
 * leak gauge exposed via march_live_allocs(); relaxed atomics keep the hot
 * RC paths cheap.  See specs/2026-06-19-c-ffi-abi-design.md §14.4. */
static _Atomic int64_t march_live_alloc_count = 0;
int64_t march_live_allocs(void) {
    return atomic_load_explicit(&march_live_alloc_count, memory_order_relaxed);
}
#define MARCH_ALLOC_BUMP() atomic_fetch_add_explicit(&march_live_alloc_count, 1, memory_order_relaxed)
#define MARCH_FREE_BUMP()  atomic_fetch_sub_explicit(&march_live_alloc_count, 1, memory_order_relaxed)

/* If [p] is an FFI resource cell (MARCH_RESOURCE_TAG), run its destructor on
 * the wrapped native pointer before the cell itself is freed.  Called from
 * every RC free-on-zero path.  Cell layout: native_ptr@16, dtor@24. */
static inline void march_run_resource_dtor(void *p) {
    if (((march_hdr *)p)->tag == MARCH_RESOURCE_TAG) {
        void (*dtor)(void *) = *(void (**)(void *))((char *)p + 24);
        void *native = *(void **)((char *)p + 16);
        if (dtor) dtor(native);
    }
}

void *march_alloc(int64_t sz) {
    void *p = calloc(1, (size_t)sz);
    if (!p) {
        march_debug_report_oom("march_alloc", sz);
        fputs("march: out of memory\n", stderr); exit(1);
    }
    /* Initialize rc=1, tag=0, pad=0 */
    march_hdr *h = (march_hdr *)p;
    h->rc  = 1;
    h->tag = 0;
    h->pad = 0;
    MARCH_ALLOC_BUMP();
    if (str_stats_on()) {
        atomic_fetch_add_explicit(&obj_alloc_count, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&obj_alloc_bytes, sz, memory_order_relaxed);
    }
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
        /* Read ->len while the object is still alive. */
        if (tag == MARCH_STRING_TAG && str_stats_on())
            str_stats_free(((march_string *)p)->len);
        march_run_resource_dtor(p);
        MARCH_FREE_BUMP();
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
    if (prev == 1) {
        /* Sibling of march_decrc's free path — must tally too, or frees are
         * undercounted and peak_live_bytes is inflated. */
        if (tag == MARCH_STRING_TAG && str_stats_on())
            str_stats_free(((march_string *)p)->len);
        march_run_resource_dtor(p); MARCH_FREE_BUMP(); free(p); return 1;
    }
    if (prev < 1) {
        /* RC underflow: decrement-on-zero (or worse) detected.  Without this
         * guard we'd silently double-free.  Mirror march_decrc's behaviour. */
        fprintf(stderr,
                "march: RC underflow in march_decrc_freed (rc was %lld) at %p — aborting\n",
                (long long)prev, p);
        abort();
    }
    return 0;
}

void march_free(void *p) {
    /* Immortal cells (compiled-in string literals) belong to the program
     * image and are shared by every evaluation of their literal site, so the
     * unconditional free below must not reach them.  Defensive rather than a
     * fix for a known reproducer: the RC paths can't free an immortal cell
     * (its count never reaches zero), but march_free bypasses the count
     * entirely — Perceus emits EFree instead of a decrement for a dead
     * LINEAR/AFFINE binding (perceus.ml), and the shapes that produce such a
     * binding are not obviously closed to a value that came from a literal.
     * One predictable branch on an already-cold path is worth not risking a
     * free() of static-lifetime memory that every later evaluation of that
     * literal site still hands out. */
    if (IS_HEAP_PTR(p) && ((march_hdr *)p)->rc >= MARCH_RC_IMMORTAL) return;
    if (gc_trace_on() && IS_HEAP_PTR(p))
        gc_emit("free", p, 0, 0, ((march_hdr *)p)->tag);
    free(p);
}

/* Non-atomic reference counting — for values provably local to one thread.
 * These must NOT be called on values that may be concurrently accessed from
 * another actor.  The callers (Perceus-generated code) guarantee this.
 *
 * Per-process arena bookkeeping (audit M4): march_alloc currently uses
 * plain calloc, so there is no per-process march_heap_t to update.  When
 * the per-process arena (runtime/march_heap.c) becomes the default
 * allocator, march_decrc_local's free-on-rc=0 path needs to call
 * march_heap_record_death(owning_heap, sizeof(*p)) so march_heap_should_gc
 * sees the dead bytes — without that the GC trigger never fires.  Tracked
 * by march_heap_record_death's existence; this comment is the marker for
 * where the call needs to land. */
/* Set on OS threads that run compiled March code OUTSIDE the scheduler
 * (e.g. HTTP thread-pool workers in runtime/march_http.c).  When set, the
 * "local" refcount ops below take the atomic path so values shared across
 * those threads (the pipeline closure, module-level string constants) are not
 * raced.  Without it, concurrent pool workers corrupt the heap (use-after-free,
 * SIGSEGV in march_string_concat). */
_Thread_local int march_tls_concurrent_rc = 0;
void march_rc_set_thread_concurrent(int on) { march_tls_concurrent_rc = on; }

void march_incrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    /* When called from a scheduler worker thread, multiple tasks may share the
     * same heap object (e.g. an Array backing parallel chunks).  Use atomic
     * increment to avoid a data race on the RC field.  Same for non-scheduler
     * threads explicitly flagged as running March code concurrently. */
    if (march_sched_in_scheduler() || march_tls_concurrent_rc) {
        march_incrc(p);
        return;
    }
    ((march_hdr *)p)->rc++;
    if (gc_trace_on())
        gc_emit("inc_ref", p, 0, ((march_hdr *)p)->rc, ((march_hdr *)p)->tag);
}

void march_decrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    /* Matching atomic path for the scheduler context (see march_incrc_local). */
    if (march_sched_in_scheduler() || march_tls_concurrent_rc) {
        march_decrc(p);
        return;
    }
    march_hdr *h = (march_hdr *)p;
    h->rc--;
    if (gc_trace_on())
        gc_emit(h->rc <= 0 ? "free" : "dec_ref", p, 0, h->rc, h->tag);
    if (h->rc <= 0) {
        if (h->rc < 0) {
            fprintf(stderr, "march: local RC underflow at %p — aborting\n", p);
            abort();
        }
        march_run_resource_dtor(p);
        MARCH_FREE_BUMP();
        free(p);
        /* TODO(audit-M4): when per-process arena becomes the default
         * allocator, plumb the owning march_heap_t* through to here and
         * call march_heap_record_death(heap, sz). */
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

/* march_string layout: [rc:i64][tag:i32][pad:i32][len:i64][data:char[]]
 * The tag word (offset 8) carries MARCH_STRING_TAG so the cell is
 * distinguishable from ADT/tuple/record cells in the type-erased
 * march_value_to_string path. */
void *march_string_alloc(int64_t len) {
    march_string *s = malloc(sizeof(march_string) + (size_t)len + 1);
    if (!s) {
        march_debug_report_oom("march_string_alloc", len);
        fputs("march: out of memory\n", stderr); exit(1);
    }
    s->rc  = 1;
    s->tag = MARCH_STRING_TAG;
    s->pad = 0;
    s->len = len;
    MARCH_ALLOC_BUMP();
    if (str_stats_on()) str_stats_alloc(len);
    return s;
}

void *march_string_lit(const char *utf8, int64_t len) {
    march_string *s = march_string_alloc(len);
    march_str_copy(s->data, utf8, (size_t)len);
    s->data[len] = '\0';
    return s;
}

/* Get-or-create the single immortal march_string for one literal site.
 * See march_runtime.h for why literals must not allocate per evaluation.
 * Thread-safe: two threads reaching a cold cell both build a string, the
 * CAS loser frees its copy and adopts the winner's, so every caller
 * observes the same pointer. */
void *march_string_lit_static(const char *utf8, int64_t len, void **cell) {
    _Atomic(void *) *slot = (_Atomic(void *) *)cell;
    void *cached = atomic_load_explicit(slot, memory_order_acquire);
    if (cached) return cached;
    march_string *s = march_string_alloc(len);
    memcpy(s->data, utf8, (size_t)len);
    s->data[len] = '\0';
    s->rc = MARCH_RC_IMMORTAL;
    void *winner = NULL;
    if (atomic_compare_exchange_strong_explicit(
            slot, &winner, (void *)s, memory_order_acq_rel, memory_order_acquire))
        return s;
    MARCH_FREE_BUMP();
    free(s);
    return winner;
}

void *march_int_to_string(int64_t n) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)n);
    return march_string_lit(buf, len);
}

void *march_float_to_string(double f) {
    /* Byte-for-byte reproduce the interpreter's OCaml `string_of_float`
     * (eval.ml), which is `valid_float_lexem (format_float "%.12g" f)`:
     *   - `%.12g` gives the same 12-significant-digit form as OCaml's
     *     format_float (both defer to the platform libc);
     *   - valid_float_lexem appends a bare '.' when every character is a
     *     digit or leading '-', so a whole number prints "1." not "1"/"1.0".
     * The old `%g` (6 sig-figs, and no trailing dot) diverged from the
     * interpreter on both precision and whole numbers — the golden oracle
     * (specs/lang/golden/g09_float_show.march) now pins the agreement. */
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%.12g", f);
    int bare_int = 1;
    for (int i = 0; i < len; i++) {
        char c = buf[i];
        if (!((c >= '0' && c <= '9') || c == '-')) { bare_int = 0; break; }
    }
    if (bare_int && len > 0 && len < (int)sizeof(buf) - 1) {
        buf[len++] = '.';
        buf[len] = '\0';
    }
    return march_string_lit(buf, len);
}

/* Checked float division.  Unlike integer sdiv, LLVM's fdiv follows IEEE 754
 * and returns ±infinity or NaN on division by zero — no hardware trap.
 * The compiled backend calls this helper instead of emitting a raw fdiv so
 * that `1.0 / 0.0` and `1.0 /. 0.0` behave consistently with the interpreter
 * (which raises "division by zero").
 *
 * NOTE: We check for exact 0.0 (bit-for-bit), matching OCaml's `b <> 0.0`
 * guard in eval.ml.  Subnormal divisors are allowed through intentionally. */
double march_checked_fdiv(double a, double b) {
    if (b == 0.0) {
        fputs("march: runtime error: division by zero\n", stderr);
        exit(1);
    }
    return a / b;
}

void *march_bool_to_string(int64_t b) {
    return b ? march_string_lit("true", 4) : march_string_lit("false", 5);
}

void *march_string_concat(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    int64_t total;
    /* Bug fix: sa->len + sb->len can overflow int64_t for very large strings,
     * wrapping to a small value and causing the subsequent malloc to allocate
     * far less memory than the memcpy writes.  Abort cleanly instead. */
    if (__builtin_add_overflow(sa->len, sb->len, &total)) {
        fputs("march: runtime error: string too large (concat overflow)\n", stderr); exit(1);
    }
    march_string *s = march_string_alloc(total);
    march_str_copy(s->data, sa->data, (size_t)sa->len);
    march_str_copy(s->data + sa->len, sb->data, (size_t)sb->len);
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

/* ── Boxed Float (float-boxing design, stage 1 — additive) ─────────────── */

/* Heap-box a Float for storage in a type-erased (ptr) slot: a 24-byte cell
 * tagged MARCH_FLOAT_TAG, discriminable from tagged ints (odd) and ADT/record
 * cells (tag >= 0). Perceus treats it as an ordinary heap value. Nothing emits
 * this yet — the codegen flip that populates erased slots with boxes is
 * stage 2 (specs/plans/2026-07-13-float-boxing-design.md). */
void *march_alloc_float(double v) {
    march_float_box *b = (march_float_box *)march_alloc(sizeof(march_float_box));
    b->tag = MARCH_FLOAT_TAG;
    b->val = v;
    return b;
}

double march_unbox_float(void *p) {
    return ((march_float_box *)p)->val;
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

/* All hashes are masked to 62 bits (non-negative, <= 2^62-1). The
 * tree-walking interpreter's Int is a 63-bit OCaml native int, so a full
 * uint64 hash cannot be represented there identically; masking to 62 bits
 * lands the value in a range BOTH backends represent exactly, giving
 * cross-backend hash() equality (the interpreter reimplements these same
 * algorithms + mask in lib/eval/eval.ml). Hash values are never persisted
 * or wire-serialized (in-memory hashtable use only) and stdlib masks
 * further to 30 bits, so narrowing the range is harmless. */
#define MARCH_HASH_MASK UINT64_C(0x3FFFFFFFFFFFFFFF)

int64_t march_hash_int(int64_t x) {
    /* Finalizer from splitmix64 */
    uint64_t v = (uint64_t)x;
    v ^= v >> 30; v *= UINT64_C(0xbf58476d1ce4e5b9);
    v ^= v >> 27; v *= UINT64_C(0x94d049bb133111eb);
    v ^= v >> 31;
    return (int64_t)(v & MARCH_HASH_MASK);
}

int64_t march_hash_float(double x) {
    uint64_t bits;
    memcpy(&bits, &x, sizeof(bits));
    /* march_hash_int already masks. */
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
    return (int64_t)(h & MARCH_HASH_MASK);
}

int64_t march_hash_bool(int64_t b) { return b; }

int64_t march_string_eq(void *a, void *b) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    return sa->len == sb->len && memcmp(sa->data, sb->data, (size_t)sa->len) == 0 ? 1 : 0;
}

/* Equality for a value of statically-unknown (generic / TVar) type, as stored
 * in a polymorphic slot.  Used by structural-eq codegen for generic ADT fields,
 * where the static type gives no comparison strategy.  Dispatch on the runtime
 * shape:
 *   - identical bits (same pointer or same tagged immediate) -> equal;
 *   - any tagged immediate (low bit set) or non-heap value -> compare by value
 *     (handled by the identity check above; differing immediates are not equal);
 *   - two heap strings (MARCH_STRING_TAG) -> compare by content;
 *   - other heap values (nested ADTs/records reached through an erased slot) ->
 *     fall back to identity, since a full structural compare needs static type
 *     info unavailable here.  This is no worse than the previous pointer compare
 *     and fixes the common case of generic containers of strings. */
int64_t march_poly_eq(void *a, void *b) {
    if (a == b) return 1;
    if (!IS_HEAP_PTR(a) || !IS_HEAP_PTR(b)) return 0;
    int32_t ta = ((march_hdr *)a)->tag, tb = ((march_hdr *)b)->tag;
    if (ta == MARCH_STRING_TAG && tb == MARCH_STRING_TAG)
        return march_string_eq(a, b);
    /* Boxed floats compare by VALUE, not box identity — two distinct boxes of
     * 3.5 are equal (float-boxing design). Also fixes the historical hazard
     * where two distinct raw-float-bit patterns got dereferenced here. */
    if (ta == MARCH_FLOAT_TAG && tb == MARCH_FLOAT_TAG)
        return march_unbox_float(a) == march_unbox_float(b) ? 1 : 0;
    return 0;
}

/* Ordered generic compare for erased-slot operands (-1/0/1). See the header
 * doc. Nothing calls this yet — the fallback_cmp codegen wiring is stage 2. */
int64_t march_poly_compare(void *a, void *b) {
    if (a == b) return 0;
    /* Tagged immediates (odd low bit) → untag and integer-compare. A raw heap
     * ptr on one side and a tagged int on the other cannot be ordered
     * meaningfully; the tagged-vs-tagged case is the real one. */
    int a_imm = ((uintptr_t)a & 1u) != 0;
    int b_imm = ((uintptr_t)b & 1u) != 0;
    if (a_imm && b_imm) {
        int64_t ia = (intptr_t)a >> 1, ib = (intptr_t)b >> 1;
        return march_compare_int(ia, ib);
    }
    if (!IS_HEAP_PTR(a) || !IS_HEAP_PTR(b)) return 0;
    int32_t ta = ((march_hdr *)a)->tag, tb = ((march_hdr *)b)->tag;
    if (ta == MARCH_FLOAT_TAG && tb == MARCH_FLOAT_TAG)
        return march_compare_float(march_unbox_float(a), march_unbox_float(b));
    if (ta == MARCH_STRING_TAG && tb == MARCH_STRING_TAG)
        return march_compare_string(a, b);
    return 0;  /* structural order needs static type info unavailable here */
}

int64_t march_string_byte_length(void *s) {
    return s ? ((march_string *)s)->len : 0;
}

/* Random access to a single byte, as 0..255.
 *
 * Exists so that a scanner (JSON, TOML, YAML, XML ...) can inspect the input
 * one byte at a time WITHOUT allocating.  The alternative available in March
 * before this — string_split(s, "") or string_slice(s, i, 1) — allocates a
 * heap string per byte inspected, which is what made Json.parse allocate
 * ~2 strings per input byte regardless of how many strings the document
 * actually contained.
 *
 * Out-of-range (negative, or >= len) returns -1 rather than trapping: a
 * scanner's natural loop condition is "read until something that isn't part of
 * this token", and -1 is not a valid byte, so end-of-input falls out of the
 * same comparison as any other terminator with no separate length check. */
int64_t march_string_byte_at(void *s, int64_t i) {
    march_string *ss = (march_string *)s;
    if (!ss || i < 0 || i >= ss->len) return -1;
    return (int64_t)(unsigned char)ss->data[i];
}

int64_t march_string_is_empty(void *s) {
    return (!s || ((march_string *)s)->len == 0) ? 1 : 0;
}

/* Returns Option(Int) using the niche representation: None=0, Some(n)=(n<<1)|1.
 *
 * March integers are 63-bit (the low bit is the immediate tag), so the valid
 * range is [-2^62, 2^62-1].  We must reject anything outside that range BEFORE
 * the (n<<1)|1 tag, otherwise the shift overflows the sign bit and silently
 * returns a corrupt Some(garbage) — e.g. "4611686018427387904" (2^62) would
 * come back as Some(-4611686018427387904).  The interpreter (int_of_string,
 * 63-bit OCaml int) rejects these as None, so we match it here. */
#define MARCH_INT_MAX 4611686018427387903LL    /* 2^62 - 1 */
#define MARCH_INT_MIN (-4611686018427387904LL) /* -2^62 */
void *march_string_to_int(void *s) {
    march_string *str = (march_string *)s;
    char *end;
    errno = 0;
    long long n = strtoll(str->data, &end, 10);
    if (end == str->data || *end != '\0')
        return (void *)0;  /* None: not a valid integer */
    if (errno == ERANGE || n > MARCH_INT_MAX || n < MARCH_INT_MIN)
        return (void *)0;  /* None: out of March's 63-bit integer range */
    return (void *)(((int64_t)n << 1) | 1);  /* Some(n) */
}

/* Returns a new String by joining all String elements of a March List(String)
 * with the given separator.
 *
 * March List(String) layout:
 *   Nil  tag=0, no fields → 16 bytes
 *   Cons tag=1, 2 ptr fields at offsets 16 (head String) and 24 (tail List)
 */
/* Three-way concat: sum the lengths, allocate once, copy once.
 *
 * A left-deep `++` chain re-copies the growing prefix at every link, so k parts
 * cost k-1 allocations and O(k^2) bytes copied.  Folding the chain in groups of
 * three (desugar.ml) brings that to ceil((k-1)/2) allocations, halving both the
 * allocation count and the intermediate copying at k=3 and k=5.
 *
 * Fixed arity rather than a variadic n-ary form on purpose: March builtin
 * signatures are fixed-arity `Mono (TArrow ...)`, and the only variable-length
 * alternative -- taking a List(String), i.e. march_string_join -- has to
 * materialize cons cells first, which measured at 59% of its cost at k=5.
 *
 * All three operands are borrowed: this neither retains nor releases them. */
void *march_string_concat3(void *a, void *b, void *c) {
    march_string *sa = (march_string *)a;
    march_string *sb = (march_string *)b;
    march_string *sc = (march_string *)c;
    int64_t total = sa->len + sb->len + sc->len;
    march_string *r = march_string_alloc(total);
    march_str_copy(r->data, sa->data, (size_t)sa->len);
    march_str_copy(r->data + sa->len, sb->data, (size_t)sb->len);
    march_str_copy(r->data + sa->len + sb->len, sc->data, (size_t)sc->len);
    r->data[total] = '\0';
    return r;
}

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
    march_string *result = march_string_alloc(total);
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
            march_str_copy(dst, sep_s->data, (size_t)sep_len);
            dst += sep_len;
        }
        march_str_copy(dst, hs->data, (size_t)hs->len);
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
    write(1, ms->data, (size_t)ms->len);
}

void march_println(void *s) {
    march_string *ms = (march_string *)s;
    /* Emit the payload AND its trailing newline in a single writev(2) syscall so
     * the whole line is atomic against concurrent green threads. Two separate
     * write() calls let another thread's println interleave between the data and
     * the '\n', tearing lines together (and stranding a lone newline) — visible
     * in multi-node/multi-actor programs run with >1 OS scheduler thread. A
     * single vectored write to a regular file/pipe is atomic (POSIX). */
    struct iovec iov[2];
    iov[0].iov_base = ms->data;
    iov[0].iov_len  = (size_t)ms->len;
    iov[1].iov_base = (void *)"\n";
    iov[1].iov_len  = 1;
    ssize_t rc = writev(1, iov, 2);
    (void)rc;
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

/* Reads directly off fd 0 via read(2), bypassing stdio's buffer -- unlike
 * march_io_read_line above, which reads through fgets/stdin's own buffer.
 * Do not interleave read_byte and read_line in the same compiled program:
 * fgets may have already buffered bytes past the last line it returned,
 * and those bytes are invisible to this function's direct read(0, ...). */
int64_t march_io_read_byte(void) {
    unsigned char c;
    ssize_t n = read(0, &c, 1);
    if (n <= 0) return -1;  /* EOF (n==0) or error (n<0) both surface as -1 */
    return (int64_t)c;
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

/* ── March call stack (for backtraces) ───────────────────────────────────── */

/* Thread-local pointer to the top of the current thread's March call stack.
 * NULL when the stack is empty (program entry or after full unwind). */
static _Thread_local march_frame_t *march_call_stack_top = NULL;

/* Called at every March function entry (before the body executes).
 * frame must be a pointer to a stack-allocated march_frame_t in the caller. */
void march_frame_push(march_frame_t *frame) {
    frame->prev = march_call_stack_top;
    march_call_stack_top = frame;
}

/* Called at every March function exit (before ret). */
void march_frame_pop(void) {
    if (march_call_stack_top)
        march_call_stack_top = march_call_stack_top->prev;
}

/* Reset the call stack (used in test mode between test runs). */
void march_frame_reset(void) {
    march_call_stack_top = NULL;
}

/* Print the current call stack to stderr.
 * Stdlib frames (file starting with "stdlib/") are hidden unless
 * MARCH_BACKTRACE=full is set. */
static void march_print_backtrace(void) {
    /* Cache getenv on first call so it is safe even if called from a
       signal handler in future (getenv is not async-signal-safe). */
    static int show_full = -1;
    if (show_full < 0) {
        const char *env = getenv("MARCH_BACKTRACE");
        show_full = (env && strcmp(env, "full") == 0) ? 1 : 0;
    }
    march_frame_t *f = march_call_stack_top;
    if (!f) return;
    /* Defer printing the header until we know at least one frame is visible,
       so an all-stdlib stack produces no output when show_full is 0. */
    int printed = 0;
    int i = 0;
    while (f) {
        int is_stdlib = strncmp(f->file, "stdlib/", 7) == 0;
        if (show_full || !is_stdlib) {
            if (!printed) {
                fprintf(stderr, "\nStack trace (most recent call first):\n");
                printed = 1;
            }
            fprintf(stderr, "  [%d] %-24s %s:%d\n", i++, f->fn_name, f->file, f->line);
        }
        f = f->prev;
    }
    if (printed && !show_full)
        fprintf(stderr, "\nnote: set MARCH_BACKTRACE=full for all frames including stdlib\n");
}

/* ── Panic ───────────────────────────────────────────────────────────────── */

/* Forward declaration so march_panic_ext / march_todo_ext can call march_panic
 * which is defined just below. */
void march_panic(void *s);

/* Forward declaration: do_actor_death (defined further below, after the
 * restart strategies) is called from actor_green_thread's crash-recovery
 * branch (below) and from march_kill / the restart helpers, both of which
 * are also defined earlier in the file than do_actor_death itself. */
static void do_actor_death(void *actor);

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
        /* Reset the call stack so it doesn't bleed into the next test. */
        march_frame_reset();
        int len = (int)ms->len < (int)sizeof(march_test_fail_buf) - 1
                  ? (int)ms->len : (int)sizeof(march_test_fail_buf) - 1;
        memcpy(march_test_fail_buf, ms->data, (size_t)len);
        march_test_fail_buf[len] = '\0';
        longjmp(march_test_jmp_buf, 1);
    }
    /* Compiled actor supervision: a panic inside a supervised child's
     * message handler longjmp's back into actor_green_thread instead of
     * exit(1)-ing the whole process (see march_proc.crash_jmp's doc
     * comment in march_scheduler.h for why this is stored on the proc,
     * not a _Thread_local — this scheduler is work-stealing across
     * multiple OS threads, so the currently-running proc can migrate). */
    march_proc *cur_proc = march_sched_current();
    if (cur_proc && cur_proc->crash_jmp) {
        longjmp(*cur_proc->crash_jmp, 1);
    }
    fprintf(stderr, "panic: ");
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
    fputc('\n', stderr);
    march_print_backtrace();
    fflush(stderr);
    exit(1);
}

/* ── Checked integer division / remainder ────────────────────────────────── */
/*
 * The compiled backend lowers int_div / int_mod / int_mod_euclid /
 * int_div_euclid through these helpers instead of emitting a raw
 * sdiv/srem/urem so that a zero
 * divisor traps via march_panic — matching the interpreter, which raises
 * "<op>: division by zero" (see eval.ml).  Raw hardware division by zero is
 * undefined (SIGFPE on x86, garbage on some ARM paths); pre-fix, compiled
 * code silently returned a junk value and kept running, and the property
 * runner reported a crashing property as passing.
 *
 * march_panic longjmps back to the test harness when inside a test (so
 * __try_call / the property runner catches it); otherwise it prints and
 * exits 1.  The message text matches the interpreter byte-for-byte so the
 * two backends agree under the oracle.
 *
 * Non-zero behaviour: idiv/imod use signed C operators (matching sdiv/srem);
 * ediv/emod implement signed Euclidean division/remainder (non-negative
 * remainder), mirroring eval.ml's int_div_euclid/int_mod_euclid. */
static int64_t march_div_by_zero(const char *op) {
    char buf[64];
    int  n = snprintf(buf, sizeof buf, "%s: division by zero", op);
    march_panic(march_string_lit(buf, (int64_t)n));
    return 0; /* unreachable: march_panic does not return */
}

int64_t march_checked_idiv(int64_t a, int64_t b) {
    if (b == 0) return march_div_by_zero("int_div");
    return a / b;
}

int64_t march_checked_imod(int64_t a, int64_t b) {
    if (b == 0) return march_div_by_zero("int_mod");
    return a % b;
}

/* Euclidean remainder (int_mod_euclid): the remainder is always non-negative
 * and strictly less than |b|. Mirrors eval.ml byte-for-byte:
 *   r = a mod b; if r < 0 then r + abs b else r
 * The previous lowering used unsigned `%`, which agrees with this only when the
 * divisor is positive; for a NEGATIVE divisor it diverged from the interpreter
 * (e.g. int_mod_euclid(-7, -3) → -7 unsigned vs. 2 Euclidean). Signed `%` gives
 * a remainder with the dividend's sign, so the correction adds |b| when it is
 * negative. (abs(b) for b == INT64_MIN is unrepresentable, matching eval.ml's
 * own OCaml `abs min_int` edge — not defended here, no caller reaches it.) */
int64_t march_checked_emod(int64_t a, int64_t b) {
    if (b == 0) return march_div_by_zero("int_mod_euclid");
    int64_t r = a % b;
    if (r < 0) return r + (b < 0 ? -b : b);
    return r;
}

/* Euclidean division (int_div_euclid): the quotient q such that the Euclidean
 * remainder a - q*b is always non-negative. Mirrors eval.ml byte-for-byte:
 *   q = a / b; r = a - q*b; if r < 0 then (b > 0 ? q-1 : q+1) else q
 * C's `/` truncates toward zero like OCaml's, so the correction step is what
 * turns truncated division into Euclidean division. Signed throughout, the
 * div-side pair of march_checked_emod above. */
int64_t march_checked_ediv(int64_t a, int64_t b) {
    if (b == 0) return march_div_by_zero("int_div_euclid");
    int64_t q = a / b;
    int64_t r = a - q * b;
    if (r < 0) return (b > 0) ? q - 1 : q + 1;
    return q;
}

/* The `/` and `%` infix operators (is_int_arith in llvm_emit.ml) lower to these
 * instead of march_checked_idiv/imod because the interpreter raises the BARE
 * messages "division by zero" / "modulo by zero" for the operator forms — with
 * no "int_div:" / "int_mod:" prefix (see eval.ml base_env entries for "/" and
 * "%").  The oracle compares stdout via __try_call, so the text must match the
 * interpreter byte-for-byte. */
int64_t march_checked_div_op(int64_t a, int64_t b) {
    if (b == 0) { march_panic(march_string_lit("division by zero", 16)); return 0; }
    return a / b;
}

int64_t march_checked_mod_op(int64_t a, int64_t b) {
    if (b == 0) { march_panic(march_string_lit("modulo by zero", 14)); return 0; }
    return a % b;
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

/* ── Crash-trapping test mode (MARCH_TEST_TRAP_SIGNALS=1) ────────────────
   Converts hardware faults (SIGSEGV/SIGBUS/SIGILL/SIGFPE) and abort()
   (SIGABRT — e.g. the RC-underflow guard) that occur INSIDE a test into
   ordinary recorded failures via the existing march_test_jmp_buf panic
   path, so one suite run reports EVERY crashing test instead of dying at
   the first.  This is an inventory tool for compiler bug hunts: after a
   caught SIGSEGV the heap may be inconsistent, so subsequent results are
   advisory.  Off by default — no behavior change unless the env var is
   set.  Faults outside a test, or on a thread other than the test-runner
   thread (longjmp across threads is UB), re-raise with the default
   handler so real crashes still crash. */
static pthread_t march_test_trap_thread;
static void march_test_signal_handler(int sig) {
    if (march_test_in_test
        && pthread_equal(pthread_self(), march_test_trap_thread)) {
        const char *nm =
            sig == SIGSEGV ? "SIGSEGV" :
            sig == SIGBUS  ? "SIGBUS"  :
            sig == SIGILL  ? "SIGILL"  :
            sig == SIGFPE  ? "SIGFPE"  :
            sig == SIGABRT ? "SIGABRT" : "signal";
        snprintf(march_test_fail_buf, sizeof(march_test_fail_buf),
                 "CRASH: %s — trapped by MARCH_TEST_TRAP_SIGNALS; "
                 "subsequent test results are advisory", nm);
        longjmp(march_test_jmp_buf, 1);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void march_test_install_traps(void) {
    static int done = 0;
    if (done) return;
    done = 1;
    const char *v = getenv("MARCH_TEST_TRAP_SIGNALS");
    if (!v || !v[0] || strcmp(v, "0") == 0) return;
    march_test_trap_thread = pthread_self();
    int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT };
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++)
        signal(sigs[i], march_test_signal_handler);
}

/* Run a single test function, with optional per-test setup.
   name is a NUL-terminated C string (from the LLVM constant). */
void march_test_run(void (*fn)(void), const char *name, void (*setup)(void)) {
    /* Apply filter (case-sensitive substring match). */
    if (test_filter[0] != '\0' && strstr(name, test_filter) == NULL)
        return;
    march_test_install_traps();

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
    fflush(stderr);
    /* Exit immediately with the test result.  A test may have spawned an actor,
       lazily starting the background scheduler thread (sched_bg_entry); letting
       main return would run libc teardown that can join/race that thread,
       hanging the runner (uninterruptible) or crashing it (exit 255) even when
       every test passed.  _exit skips atexit/destructors/thread-joins so the
       runner always terminates with the correct code. */
    int32_t code = test_failed > 0 ? 1 : 0;
    _exit(code);
    return code;
}

/* ── __try_call ──────────────────────────────────────────────────────────── */
/*
 * __try_call : (Bool -> Bool) -> Result(Bool, String)
 *
 * Invokes the compiled March closure [thunk] with a dummy Bool argument and
 * returns Ok(result) on success or Err(msg) if the call panics (march_panic,
 * a failing assert, division by zero, match failure, etc.).
 *
 * The thunk MUST return an immediate (Bool) — the Ok field is stored in the
 * uniform low-bit-tagged representation ((n << 1) | 1), matching how
 * compiled March reads polymorphic ADT fields.  The Bool-only contract is
 * enforced by the typechecker signature; widening it back to a generic
 * (Bool -> a) would require distinguishing immediate from heap results here.
 *
 * The closure is a "fn _ -> body" workaround for (Unit -> a): the argument
 * is ignored by the lambda body, so we pass 1 (true).
 *
 * Used by Check.try_prop in stdlib/check.march so the property runner can
 * shrink a failing input instead of aborting the whole binary on the first
 * panic.  Supports nesting by save/restoring the global longjmp state used
 * by the test harness.
 *
 * Closure layout (see march_thunk_trampoline):
 *   offset  0: int64_t  rc         — reference count
 *   offset  8: int32_t  tag        — 0 for closures
 *   offset 12: int32_t  pad
 *   offset 16: void    *apply_fn   — int64_t apply(void *clo, int64_t arg)
 *   offset 24+: captured environment fields
 *
 * Result(a, String) layout (24 bytes):
 *   offset  0..15: march_hdr         — tag=0 → Ok, tag=1 → Err
 *   offset 16..23: value field       — (intptr_t)a for Ok, march_string* for Err
 *
 * RC contract: consumes one reference to [thunk] (march_decrc after use).
 * Matches Perceus's ownership-transfer convention for last-use args.  If
 * the apply panics we still decref the thunk via the cleanup path.
 */
void *__try_call(void *thunk) {
    typedef int64_t (*apply_fn_t)(void *, int64_t);
    apply_fn_t apply = *(apply_fn_t *)((char *)thunk + 16);

    /* Save outer panic-handler state so nested __try_call works correctly
       (e.g. a property runner called from within another property). */
    jmp_buf saved_jmp;
    char    saved_fail[sizeof(march_test_fail_buf)];
    int     saved_in_test = march_test_in_test;
    memcpy(&saved_jmp, &march_test_jmp_buf, sizeof(jmp_buf));
    memcpy(saved_fail, march_test_fail_buf, sizeof(march_test_fail_buf));

    march_test_fail_buf[0] = '\0';
    march_test_in_test     = 1;

    int64_t ok_result = 0;
    int     panicked  = 0;

    if (setjmp(march_test_jmp_buf) == 0) {
        ok_result = apply(thunk, 1);   /* 1 = dummy Bool argument */
    } else {
        panicked = 1;
    }

    /* Capture the panic message before restoring the outer fail buffer. */
    void *err_str = NULL;
    if (panicked) {
        const char *msg = march_test_fail_buf[0]
            ? march_test_fail_buf : "property panicked";
        err_str = march_string_lit(msg, (int64_t)strlen(msg));
    }

    /* Restore the outer panic handler. */
    memcpy(&march_test_jmp_buf, &saved_jmp, sizeof(jmp_buf));
    memcpy(march_test_fail_buf, saved_fail, sizeof(march_test_fail_buf));
    march_test_in_test = saved_in_test;

    /* No march_decrc(thunk) here. Like the task_spawn trampoline (see its
     * comment), a CAPTURING thunk's own apply function now releases its one
     * reference to $clo internally — and it does so as the FIRST thing the
     * function does, immediately after extracting its captures and before
     * any of the actual body runs (lib/tir/perceus.ml's
     * insert_apply_fn_clo_drop splices right after the fv-extraction
     * prefix). That means the drop has already fired by the time apply()
     * either returns normally OR longjmps out via a panic — both paths are
     * covered by the same unconditional removal, no panicked/!panicked
     * split needed. Decrementing again here double-consumed that reference;
     * confirmed flaky (heap-layout-dependent) with a single-capture thunk:
     * "RC underflow" on 6/30 runs before this fix, 0/30 after. A
     * CAPTURE-FREE thunk's apply function does not drop $clo at all (see
     * the fv-extraction guard in insert_apply_fn_clo_drop), so removing
     * this decrc is inert for that case exactly as for task_spawn. */

    /* Build Result(a, String): 16-byte header + 8-byte field. */
    char      *result = (char *)march_alloc(24);
    march_hdr *hdr    = (march_hdr *)result;
    void     **field  = (void **)(result + 16);
    if (!panicked) {
        hdr->tag = 0;                              /* Ok */
        /* The Ok field is a polymorphic ADT slot, so immediates must use the
           uniform low-bit tag representation ((n << 1) | 1) that compiled
           March emits when reading it back (ptrtoint + ashr 1).  The thunk
           returns a raw Bool (0/1) — __try_call's March type is
           (Bool -> Bool) -> Result(Bool, String), enforced by the
           typechecker, so the result here is ALWAYS an immediate; storing a
           heap pointer through this path would corrupt it. */
        *field   = (void *)((((intptr_t)ok_result) << 1) | 1);
    } else {
        hdr->tag = 1;                              /* Err */
        *field   = err_str;
    }
    return result;
}

/* ── __try_call_val ──────────────────────────────────────────────────────── */
/*
 * __try_call_val : (Bool -> a) -> Result(a, String)
 *
 * Value-carrying sibling of __try_call.  The thunk's March return type is the
 * type variable `a`, so the compiled thunk returns its result in the *uniform*
 * representation (heap pointers raw, immediates low-bit-tagged).  We therefore
 * store ok_result into the Ok field VERBATIM — no `<<1 | 1` retag — exactly as
 * the Err path below stores the heap march_string raw.  This lets a heap result
 * (e.g. a nested Result(v, String)) round-trip without the pointer corruption
 * that the Bool-only __try_call guards against.
 *
 * Ownership: the thunk transfers ownership of its result to us (Perceus return
 * convention); storing it raw into the Ok field forwards that ownership to the
 * returned Result, which the caller then owns.  No extra incrc/decrc is needed.
 * On the panic path the thunk did not return, so there is no value to manage
 * (any heap captured before the panic may leak — acceptable, as for __try_call).
 *
 * RC contract, closure layout, and Result layout are identical to __try_call.
 */
void *__try_call_val(void *thunk) {
    typedef int64_t (*apply_fn_t)(void *, int64_t);
    apply_fn_t apply = *(apply_fn_t *)((char *)thunk + 16);

    jmp_buf saved_jmp;
    char    saved_fail[sizeof(march_test_fail_buf)];
    int     saved_in_test = march_test_in_test;
    memcpy(&saved_jmp, &march_test_jmp_buf, sizeof(jmp_buf));
    memcpy(saved_fail, march_test_fail_buf, sizeof(march_test_fail_buf));

    march_test_fail_buf[0] = '\0';
    march_test_in_test     = 1;

    int64_t ok_result = 0;
    int     panicked  = 0;

    if (setjmp(march_test_jmp_buf) == 0) {
        ok_result = apply(thunk, 1);   /* 1 = dummy Bool argument */
    } else {
        panicked = 1;
    }

    void *err_str = NULL;
    if (panicked) {
        const char *msg = march_test_fail_buf[0]
            ? march_test_fail_buf : "call panicked";
        err_str = march_string_lit(msg, (int64_t)strlen(msg));
    }

    memcpy(&march_test_jmp_buf, &saved_jmp, sizeof(jmp_buf));
    memcpy(march_test_fail_buf, saved_fail, sizeof(march_test_fail_buf));
    march_test_in_test = saved_in_test;

    /* No march_decrc(thunk) — see the identical comment in __try_call above. */

    char      *result = (char *)march_alloc(24);
    march_hdr *hdr    = (march_hdr *)result;
    void     **field  = (void **)(result + 16);
    if (!panicked) {
        hdr->tag = 0;                              /* Ok */
        /* Uniform-repr value stored verbatim — see header comment. */
        *field   = (void *)ok_result;
    } else {
        hdr->tag = 1;                              /* Err */
        *field   = err_str;
    }
    return result;
}

/* ── march_try_finally ───────────────────────────────────────────────────── */
/*
 * try_finally : (Bool -> a) -> (Bool -> b) -> a
 *
 * Runs action(), then cleanup(), and returns action's result.  If action
 * panics, cleanup STILL runs, and the panic is then re-raised (so it
 * reaches whatever handler is outermost — test harness, supervised actor,
 * or the default print-and-exit).  A panic raised by cleanup itself is
 * swallowed, matching the interpreter builtin (lib/eval/eval.ml's
 * "try_finally": `try ignore (cleanup ()) with _ -> ()`).
 *
 * This is the primitive behind stdlib resource wrappers (File.with_lines /
 * File.with_chunks close their fd here; Logger pops its context stack), so
 * the panic path is the whole point: without it a panicking callback leaks
 * the resource.
 *
 * Panic capture reuses the test-harness longjmp channel exactly like
 * __try_call / __try_call_val above (save/restore of march_test_jmp_buf +
 * march_test_fail_buf + march_test_in_test supports nesting); see their
 * header comments for the closure layout and for why there is NO
 * march_decrc of either closure here (a capturing closure's apply function
 * releases its own $clo reference as its first action, on both the
 * normal-return and the longjmp path).
 *
 * The March return type is the type variable `a`, so like __try_call_val
 * the action's result is returned in the *uniform* representation, verbatim
 * (heap pointers raw, immediates low-bit-tagged) — the compiled call site
 * declares `ptr @march_try_finally` and the consumer coerces.  Ownership of
 * the result transfers straight through (Perceus return convention).
 * cleanup's result is discarded WITHOUT a decrc: for a Unit-returning
 * cleanup (the overwhelmingly common case) the apply's return slot is not
 * a meaningful uniform value, so blindly decrc'ing it could corrupt a
 * stranger's heap object.  A heap-returning cleanup therefore leaks one
 * reference — same accepted trade-off as __try_call's panic path.
 */
void *march_try_finally(void *action, void *cleanup) {
    typedef int64_t (*apply_fn_t)(void *, int64_t);
    apply_fn_t apply_action  = *(apply_fn_t *)((char *)action + 16);
    apply_fn_t apply_cleanup = *(apply_fn_t *)((char *)cleanup + 16);

    jmp_buf saved_jmp;
    char    saved_fail[sizeof(march_test_fail_buf)];
    int     saved_in_test = march_test_in_test;
    memcpy(&saved_jmp, &march_test_jmp_buf, sizeof(jmp_buf));
    memcpy(saved_fail, march_test_fail_buf, sizeof(march_test_fail_buf));

    march_test_fail_buf[0] = '\0';
    march_test_in_test     = 1;

    int64_t result   = 0;
    int     panicked = 0;

    if (setjmp(march_test_jmp_buf) == 0) {
        result = apply_action(action, 1);   /* 1 = dummy Bool argument */
    } else {
        panicked = 1;
    }

    /* Capture action's panic message before cleanup can clobber the buffer. */
    void *err_str = NULL;
    if (panicked) {
        const char *msg = march_test_fail_buf[0]
            ? march_test_fail_buf : "panic";
        err_str = march_string_lit(msg, (int64_t)strlen(msg));
    }

    /* Run cleanup under its own guard: its panic must neither mask action's
       panic nor escape a successful action. */
    march_test_fail_buf[0] = '\0';
    if (setjmp(march_test_jmp_buf) == 0) {
        (void)apply_cleanup(cleanup, 1);
    }
    /* else: cleanup panicked — swallowed. */

    /* Restore the outer panic handler BEFORE re-raising, so the re-raise
       lands in the caller's handler, not back in our own (stale) setjmp. */
    memcpy(&march_test_jmp_buf, &saved_jmp, sizeof(jmp_buf));
    memcpy(march_test_fail_buf, saved_fail, sizeof(march_test_fail_buf));
    march_test_in_test = saved_in_test;

    if (panicked) {
        march_panic(err_str);   /* does not return */
    }
    return (void *)result;
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
 * This word order is not incidental: it is guaranteed by lower_actor's
 * $d_dispatch/$e_alive/$f_state field-name sort-prefix contract — the
 * TIR-side struct fields are named so that an alphabetical sort ($d < $e
 * < $f < any user field name) reproduces exactly this word order. See
 * lib/tir/tir_names.ml (actor_dispatch_field/actor_alive_field/
 * actor_state_field) for the producer contract these hardcoded a[2]/a[3]/
 * a[4] reads on the C side mirror; changing that sort prefix without
 * updating these indices (or vice versa) desyncs the two sides silently.
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

/* One entry per child declared in a `supervise do ... end` block. Set once
 * at initial spawn time (march_actor_register_child) and read by every
 * restart (compiled actor supervision, Task 4/5). */
typedef struct {
    /* <ActorName>_spawn, referenced as a first-class value from
     * lower_actor.ml — the compiler ALWAYS represents a bare top-level
     * function reference this way (a heap-allocated March closure cell
     * whose offset-16 word holds a $clo_wrap function pointer; see how
     * $d_dispatch is stored/consumed for actors, and how do_actor_death's
     * cleanup callbacks are invoked), never a raw C function pointer.
     * march_respawn_child unwraps it the same way. Called fresh on every
     * restart. */
    void *spawn_clo;
    int64_t word_idx;         /* position among this supervisor's alphabetically-sorted
                                  state fields; this child's Int-encoded pid lives at
                                  ((int64_t*)supervisor)[4 + word_idx] */
} march_sup_child;

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
    /* Phase 5: non-zero for actors compiled with --hot-reload.
     * Holds the dispatch-table NAME_ID of the actor's _dispatch function.
     * Used by actor_green_thread for dispatch-table lookup (enabling function
     * hot-swap) and by march_actor_broadcast_migrate to target only the right actors. */
    uint32_t                    dispatch_name_id;
    /* Global tag of this actor's FIRST message constructor (the F19
     * memory-safety fix gives actor _Msg ctors globally-unique tags,
     * base 0x0100_0000 — see lib/tir/llvm_toplevel.ml build_ctor_info).
     * march_actor_call adds the caller's sentinel ctor INDEX to this base
     * to address the handler positionally; 0 = unregistered (fall back to
     * the sentinel's raw tag). Stamped at actor-record alloc via
     * march_actor_set_call_base, so supervisor respawns (which re-run the
     * March-level spawn closure) re-stamp it on the fresh record. */
    int64_t                     call_tag_base;
    /* Set on a CHILD when it is spawned by a supervisor; NULL for every
     * other actor, including a supervisor's own meta. */
    void                        *supervisor;
    int                          sup_child_index;
    /* Set on a SUPERVISOR (an actor that itself declares `supervise do ... end`);
     * NULL/0 for every other actor, including its own children. */
    march_sup_child             *sup_children;
    int                          sup_num_children;
    /* Restart-history timestamps (seconds), for max_restarts-within-window
     * throttling; valid only when this actor IS a supervisor. */
    double                      *sup_restart_ts;
    int                          sup_restart_len;
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

/* Process-wide: an inline march_sched_run() is executing on some thread.
 * (g_in_scheduler is _Thread_local — a re-entrancy guard only — so foreign
 * threads cannot see it; without this flag they would start a second,
 * concurrent scheduler set over the same g_scheds globals.) */
static _Atomic int g_sched_inline_running = 0;

/* Lazy initialization flag for the green thread scheduler.
 * _Atomic so concurrent first-spawns don't double-init via a plain read-write
 * race on a non-atomic int. */
static _Atomic int g_sched_initialized = 0;

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
 * Idempotent: the CAS ensures at most one background thread is created.
 * No-op when called from within the scheduler (tl_sched != NULL) — the
 * inline scheduler loop is already handling all green threads. */
static void march_ensure_sched_started(void) {
    if (march_sched_in_scheduler()) return;  /* already inside the scheduler — no background thread needed */
    if (atomic_load_explicit(&g_sched_inline_running, memory_order_acquire))
        return;  /* inline scheduler already running — it runs all green threads */
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

/* Green-thread trampoline for the main() entrypoint.
 * arg is a no-arg void function pointer cast to void *. */
static void main_fn_green_thread(void *arg) {
    typedef void (*main_fn_t)(void);
    main_fn_t fn = (main_fn_t)(uintptr_t)arg;
    fn();
}

/* Spawn the March main() function as a green thread so it runs inside the
 * scheduler and can use actor_call / task_await without blocking the OS thread.
 * Call this before march_run_scheduler(); the scheduler loop picks it up. */

/* ── Self-imposed capability sandbox (opt-in via `march --cap-sandbox`) ──
 *
 * Lives HERE rather than in its own translation unit on purpose: march_spawn_main
 * calls it unconditionally, and every harness that links the runtime keeps its
 * own source list (bin/main.ml, test/dune x4, test/test_helpers.ml, the REPL's
 * JIT .so builder). A separate file has to be added to all of them or the link
 * breaks — which it did, taking out `march repl` and 33 tests.
 *
 * The compiler embeds MARCH_CAP_PROFILE, an SBPL profile derived from the
 * module's own capabilities. Defense in depth, not a new guarantee: whoever
 * builds the binary chooses whether to compile it in, and the profile grants
 * exactly what the program does, so it constrains escalation beyond the
 * program's behaviour rather than the behaviour itself. Externally imposed
 * enforcement (`forge cap run --allow-only`) is the stronger mechanism. */
#ifdef MARCH_CAP_PROFILE
#if defined(__APPLE__)
extern int sandbox_init(const char *profile, uint64_t flags, char **errorbuf);
extern void sandbox_free_error(char *errorbuf);
void march_sandbox_install(void) {
    char *err = NULL;
    if (sandbox_init(MARCH_CAP_PROFILE, 0, &err) != 0) {
        /* Fail CLOSED: a sandbox that silently fails to install is worse than
         * none, because the operator believes the process is contained. */
        fprintf(stderr,
                "march: capability sandbox failed to install (%s); refusing to "
                "run uncontained\n", err ? err : "unknown error");
        if (err) sandbox_free_error(err);
        exit(70);
    }
}
#elif defined(__linux__)

/* Linux: an in-process seccomp-bpf filter, installed unprivileged via
 * PR_SET_NO_NEW_PRIVS.  Denied syscalls return EPERM rather than killing the
 * process, matching the macOS behaviour where a withheld capability surfaces
 * as a March `Err` the program can handle instead of a crash.
 *
 * The compiler passes one -D per WITHHELD capability class (MARCH_CAP_DENY_*),
 * derived from the same own-capability set as the macOS profile.
 *
 * What is enforced here, and what is not:
 *   IO.Network    -> socket/socketpair denied            ENFORCED
 *   IO.Process    -> execve/execveat denied              ENFORCED
 *                    (NOT clone/fork: the scheduler needs threads)
 *   IO.FileWrite  -> openat with write flags, plus the
 *                    unambiguous mutators, denied        ENFORCED
 *   IO.FileRead   -> NOT enforced: seccomp filters syscall numbers and
 *                    scalar args, never pointer contents, so it cannot tell
 *                    which PATH is being opened.  Path scoping needs
 *                    Landlock; until then read stays advisory here, exactly
 *                    as it is on macOS (where dyld forces it).  Do not claim
 *                    otherwise.
 */
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <sys/prctl.h>
#include <sys/syscall.h>

#if defined(__x86_64__)
#define MARCH_AUDIT_ARCH AUDIT_ARCH_X86_64
#elif defined(__aarch64__)
#define MARCH_AUDIT_ARCH AUDIT_ARCH_AARCH64
#else
#define MARCH_AUDIT_ARCH 0
#endif

/* seccomp_data: nr@0, arch@4, ip@8, args[6]@16 (8 bytes each, LE). */
#define SD_NR   offsetof(struct seccomp_data, nr)
#define SD_ARCH offsetof(struct seccomp_data, arch)
#define SD_ARG2 (offsetof(struct seccomp_data, args) + 2 * 8)

/* O_WRONLY|O_RDWR|O_CREAT|O_TRUNC|O_APPEND — any of these makes an open a
 * write.  Spelled numerically: the values are identical on x86_64 and
 * aarch64, and pulling in fcntl.h here would fight the runtime's own
 * _GNU_SOURCE ordering. */
#define MARCH_O_WRITE_MASK (01 | 02 | 0100 | 01000 | 02000)

#define MAX_FILTER 96

void march_sandbox_install(void) {
    struct sock_filter f[MAX_FILTER];
    size_t n = 0;

    /* Refuse to run on a foreign arch rather than installing a filter whose
     * syscall numbers mean something else. */
    if (MARCH_AUDIT_ARCH == 0) {
        fprintf(stderr,
                "march: --cap-sandbox: unsupported architecture; refusing to "
                "run uncontained\n");
        exit(70);
    }

    /* arch guard: a mismatch (e.g. a 32-bit compat call) is denied, not
     * allowed — allowing it would let a caller re-enter through the other
     * syscall table. */
    f[n++] = (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS, SD_ARCH);
    f[n++] = (struct sock_filter)BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K,
                                          MARCH_AUDIT_ARCH, 1, 0);
    f[n++] = (struct sock_filter)BPF_STMT(
        BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA));
    f[n++] = (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS, SD_NR);

/* Two instructions per denied syscall: "if nr == X fall through to the
 * ERRNO return, else skip it". Fixed offsets, so no second pass. */
#define DENY_NR(nr_)                                                          \
    do {                                                                      \
        f[n++] = (struct sock_filter)BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K,       \
                                              (nr_), 0, 1);                    \
        f[n++] = (struct sock_filter)BPF_STMT(                                 \
            BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA));  \
    } while (0)

#ifdef MARCH_CAP_DENY_NET
    DENY_NR(__NR_socket);
    DENY_NR(__NR_socketpair);
#endif

#ifdef MARCH_CAP_DENY_EXEC
    DENY_NR(__NR_execve);
#ifdef __NR_execveat
    DENY_NR(__NR_execveat);
#endif
#endif

#ifdef MARCH_CAP_DENY_WRITE
    /* Unambiguous mutators.  Legacy numbers exist only on some arches
     * (aarch64 has no open/unlink/rename/mkdir/rmdir/chmod), hence the
     * per-syscall guards. */
#ifdef __NR_unlink
    DENY_NR(__NR_unlink);
#endif
    DENY_NR(__NR_unlinkat);
#ifdef __NR_rename
    DENY_NR(__NR_rename);
#endif
#ifdef __NR_renameat
    DENY_NR(__NR_renameat);
#endif
    DENY_NR(__NR_renameat2);
#ifdef __NR_mkdir
    DENY_NR(__NR_mkdir);
#endif
    DENY_NR(__NR_mkdirat);
#ifdef __NR_rmdir
    DENY_NR(__NR_rmdir);
#endif
#ifdef __NR_truncate
    DENY_NR(__NR_truncate);
#endif
    DENY_NR(__NR_ftruncate);
#ifdef __NR_chmod
    DENY_NR(__NR_chmod);
#endif
    DENY_NR(__NR_fchmodat);
#endif /* MARCH_CAP_DENY_WRITE */

#undef DENY_NR

#ifdef MARCH_CAP_DENY_WRITE
    /* openat is both the read and the write path, so it is filtered on its
     * flags argument rather than its number.  Placed LAST so the accumulator
     * can be clobbered without reloading nr for later checks. */
    f[n++] = (struct sock_filter)BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K,
                                          __NR_openat, 0, 3);
    f[n++] = (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS, SD_ARG2);
    f[n++] = (struct sock_filter)BPF_JUMP(BPF_JMP | BPF_JSET | BPF_K,
                                          MARCH_O_WRITE_MASK, 0, 1);
    f[n++] = (struct sock_filter)BPF_STMT(
        BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA));
#endif

    f[n++] = (struct sock_filter)BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW);

    struct sock_fprog prog = { .len = (unsigned short)n, .filter = f };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 ||
        prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog) != 0) {
        /* Fail CLOSED.  Installation genuinely can fail — seccomp is
         * unavailable under qemu user emulation, and a restrictive outer
         * profile can reject the prctl — and running uncontained after the
         * operator asked for containment is the worst outcome. */
        fprintf(stderr,
                "march: capability sandbox failed to install (%s); refusing to "
                "run uncontained\n",
                strerror(errno));
        exit(70);
    }
}

#else
void march_sandbox_install(void) {
    fprintf(stderr,
            "march: --cap-sandbox is not implemented on this platform; use "
            "`forge cap run --allow-only ...` for external enforcement\n");
    exit(70);
}
#endif
#else
void march_sandbox_install(void) { /* not built with --cap-sandbox */ }
#endif

void march_spawn_main(void (*fn)(void)) {
    /* Drop privileges before the scheduler starts and before any user code
     * runs.  No-op unless built with --cap-sandbox. */
    march_sandbox_install();
    int expected = 0;
    if (atomic_compare_exchange_strong_explicit(
            &g_sched_initialized, &expected, 1,
            memory_order_acq_rel, memory_order_acquire)) {
        march_sched_init();
    }
    march_sched_spawn(main_fn_green_thread, (void *)(uintptr_t)fn);
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

/* Shared by march_is_cap_valid, march_pid_of_int, and the restart-strategy
 * code below: locate an actor's meta entry by its sequential spawn index —
 * the value a compiled Int field uses to encode a Pid (see
 * march_actor_register_child). Returns NULL if no actor was ever assigned
 * this index. */
static march_actor_meta *find_meta_by_pid_index(int64_t pid_index) {
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

    /* self is THIS green thread's own proc — march_sched_current() reads
     * tl_sched->current, which correctly names "whatever proc this OS
     * thread's scheduler is running right now" regardless of which OS
     * thread that happens to be (see march_proc.crash_jmp's doc comment
     * in march_scheduler.h for why the trap pointer lives on the proc,
     * not a _Thread_local — this scheduler steals procs across OS
     * threads, so a raw thread-local would go stale after a migration). */
    march_proc *self = march_sched_current();
    jmp_buf crash_jmp;
    jmp_buf *saved_jmp = self ? self->crash_jmp : NULL;
    /* Read meta->supervisor once, under g_tbl_mu, and cache it in a local —
     * march_actor_register_child (called by the supervisor, on a DIFFERENT
     * thread, right after this child's march_spawn already started this
     * green thread running) writes meta->supervisor under the same lock.
     * Without this, an unlocked read here races with that write (confirmed
     * via ThreadSanitizer): reading stale NULL just misses installing the
     * crash trap for that specific child on that specific timing window —
     * not memory-unsafe, but silently defeats supervision for it. Caching
     * one snapshot also avoids a TOCTOU between the two "meta->supervisor"
     * checks below (register_child could run in between two separate reads). */
    pthread_mutex_lock(&g_tbl_mu);
    int has_supervisor = meta->supervisor != NULL;
    pthread_mutex_unlock(&g_tbl_mu);
    if (has_supervisor && self) {
        /* Only a supervised child gets crash-isolated — an unsupervised
         * actor's panic keeps today's exit(1) behavior (see march_panic). */
        self->crash_jmp = &crash_jmp;
    }
    if (has_supervisor && self && setjmp(crash_jmp) != 0) {
        /* march_panic longjmp'd here instead of exit(1)-ing the process.
         * do_actor_death mirrors what march_kill would have done, and
         * (since this actor has a supervisor) triggers a restart — kill/
         * crash-notify parity with the interpreter's kill = crash_actor. */
        self->crash_jmp = saved_jmp;
        do_actor_death(actor);
        pthread_mutex_lock(&g_tbl_mu);
        meta->green_thread = NULL;
        pthread_mutex_unlock(&g_tbl_mu);
        return;
    }

    while (a[3]) {  /* while alive */
        void *msg = march_sched_recv();
        if (msg == MARCH_RECV_NO_MSG) break;  /* woken without message (killed) */

        /* ── Phase 5: detect system migrate message ──────────────────────────
         * Check BEFORE the alive gate so the message is always freed even if
         * the actor died between injection and receipt.
         * The migrate message is malloc'd (not march-heap), so free with free().
         * Gates, in order:
         *   - dispatch_name_id: march_actor_broadcast_migrate only ever
         *     targets hot-reload actors (it filters on this id), so regular
         *     actors must skip the check entirely — both for speed and so a
         *     user message whose word 1 happens to equal MARCH_MIGRATE_TAG
         *     can never be misread as a migrate message.
         *   - IS_HEAP_PTR: niche/newtype-optimized messages are immediates —
         *     zero-arg constructors (e.g. Probe()) arrive as NULL and unary
         *     scalar constructors (e.g. Inc(10)) arrive as odd tagged values.
         *     Dereferencing those SIGSEGVs; a real migrate message is always
         *     a malloc'd struct, which IS_HEAP_PTR accepts. */
        if (meta->dispatch_name_id
                && IS_HEAP_PTR(msg)
                && ((int64_t *)msg)[1] == MARCH_MIGRATE_TAG) {
            march_migrate_msg_t *mm = (march_migrate_msg_t *)msg;
            if (a[3] && mm->migrate_fn) {
                /* a[4] is the state record pointer (state indirection layout).
                 * migrate_fn receives the old state ptr and returns the new one. */
                void *new_state = mm->migrate_fn((void *)(uintptr_t)a[4]);
                a[4] = (int64_t)(uintptr_t)new_state;
            }
            free(mm);
            march_sched_tick();
            continue;
        }

        if (!a[3]) {
            march_decrc(msg);
            break;
        }

        uint32_t tbl_version = 0;

        int64_t saved_rc = a[0];
        a[0] = 1;  /* FBIP: force RC=1 for in-place reuse */

        if (meta->dispatch_name_id) {
            /* Hot-reload actor: the dispatch fn is a bare 2-arg function
             * Counter_dispatch(actor, msg) — NOT a closure wrapper.
             * Call it directly without a closure env arg. */
            typedef void (*dispatch_fn_t)(void *, void *);
            void *fn_raw = march_dispatch_enter(meta->dispatch_name_id, &tbl_version);
            dispatch_fn_t dispatch_fn;
            memcpy(&dispatch_fn, &fn_raw, sizeof(dispatch_fn));
            dispatch_fn(actor, msg);
        } else {
            /* Regular actor: indirect via closure wrapper (3-arg: closure, actor, msg).
             *
             * RC contract: a[2] is a LONG-LIVED reference held by the actor's
             * own fields, called once per inbound message for the actor's
             * entire lifetime — never transferred per-call, matching
             * march_signal_drain's watcher contract (see its comment) rather
             * than the map/fold builtins' transfer-once-consume-once one.
             * If this closure wrapper ever captured a free variable,
             * insert_apply_fn_clo_drop (lib/tir/perceus.ml) would make it
             * release its $clo reference on the FIRST message and every
             * later message would dispatch through freed memory.
             * march_incrc(closure) would balance that per-call drop the same
             * way march_signal_drain's incrc does.
             *
             * CONFIRMED UNREACHABLE today, not just defensive: a[2] is always
             * populated by lower_actor.ml's spawn function via
             * EAlloc(Name_Actor, [AVar dispatch_fn_ptr_var, ...]), where
             * dispatch_fn_ptr_var references dispatch_fn — a fn_def declared
             * at the SAME top level as the spawn function, never nested
             * inside another function's scope. A top-level function
             * referenced as a value can have no free variables to capture by
             * construction (it isn't a lift_lambda-produced closure at all),
             * so insert_apply_fn_clo_drop's fv-extraction guard can never
             * fire for it — there is no drop for this incrc to balance.
             * Natively it doesn't even reach this incrc as a real
             * allocation: a top-level function materialized as a value is
             * exactly llvm_emit.ml's [intern_static_closure] shape, so a[2]
             * is the immortal `@Name_dispatch$static_clo` global, on which
             * march_incrc is unconditionally a no-op by design (see
             * MARCH_RC_IMMORTAL).
             *
             * Left in place as cheap (IS_HEAP_PTR-guarded, one branch)
             * defense-in-depth against a FUTURE actor-lowering change that
             * introduces genuine closures over local scope (e.g. a
             * parameterized/nested actor definition) — if that ever happens,
             * this comment is the pointer back to why it matters, rather
             * than requiring the bug to be rediscovered from a crash. */
            typedef void (*closure_fn_t)(void *, void *, void *);
            char *closure = (char *)(uintptr_t)a[2];
            closure_fn_t fn = *(closure_fn_t *)(closure + 16);
            march_incrc(closure);
            fn((void *)(uintptr_t)a[2], actor, msg);
        }

        a[0] = saved_rc;

        if (meta->dispatch_name_id) {
            march_dispatch_leave(meta->dispatch_name_id, tbl_version);
        }

        march_sched_tick();
    }

    /* The loop has exited (actor killed, or woken without a message at
     * scheduler shutdown) and this proc is about to die and be freed by
     * sched_loop.  Clear the meta handle so march_kill / march_send observe
     * NULL instead of waking or enqueueing on a freed proc (use-after-free). */
    if (self) self->crash_jmp = saved_jmp;
    pthread_mutex_lock(&g_tbl_mu);
    meta->green_thread = NULL;
    pthread_mutex_unlock(&g_tbl_mu);
}

/* ── Public actor API ────────────────────────────────────────────── */

/* Returns 1 (and appends `now` to sup_meta's restart history) if a restart
 * is currently permitted under its max_restarts-within-window budget;
 * returns 0 (budget exceeded — caller must crash the supervisor itself)
 * otherwise. Mirrors the identical window-check inlined in all three of
 * eval.ml's one_for_one_restart / one_for_all_restart / rest_for_one_restart. */
static int march_restart_budget_ok(march_actor_meta *sup_meta) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    double now = (double)tv.tv_sec + (double)tv.tv_usec / 1e6;
    double window = (double)sup_meta->supervisor_window_secs;
    int kept = 0;
    for (int i = 0; i < sup_meta->sup_restart_len; i++) {
        if (now - sup_meta->sup_restart_ts[i] < window) {
            sup_meta->sup_restart_ts[kept++] = sup_meta->sup_restart_ts[i];
        }
    }
    sup_meta->sup_restart_len = kept;
    if (kept >= sup_meta->supervisor_max_restarts) return 0;
    sup_meta->sup_restart_ts = realloc(sup_meta->sup_restart_ts,
                                        (size_t)(kept + 1) * sizeof(double));
    sup_meta->sup_restart_ts[kept] = now;
    sup_meta->sup_restart_len = kept + 1;
    return 1;
}

/* Spawn a fresh replacement for sup_children[child_idx], link it to the
 * supervisor in that SAME slot (never appends — march_actor_register_child
 * is only for a child's initial spawn), inherit the crashed child's
 * epoch+1 (matching eval.ml spawn_child_actor's stale-capability-detection
 * inheritance), and write the new pid_index into the supervisor's state. */
static void *march_respawn_child(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    march_sup_child *child = &sup_meta->sup_children[child_idx];
    int64_t old_pid_index = ((int64_t *)supervisor)[4 + child->word_idx];
    march_actor_meta *old_meta = find_meta_by_pid_index(old_pid_index);
    int64_t inherited_epoch = old_meta ? old_meta->epoch + 1 : 0;

    /* spawn_clo is a March closure cell (offset-16 word = $clo_wrap function
     * pointer), NOT a raw C function pointer — see march_sup_child's field
     * comment. <ActorName>_spawn is a zero-arg function, so its wrapper's
     * only parameter is the closure cell itself (contrast the 2-arg
     * cleanup-closure convention in do_actor_death, whose underlying
     * function is Unit -> Unit). */
    typedef void *(*spawn_clo_fn_t)(void *);
    void **clo_fields = (void **)((char *)child->spawn_clo + 16);
    spawn_clo_fn_t fn_ptr = (spawn_clo_fn_t)(*clo_fields);
    void *raw = fn_ptr(child->spawn_clo);
    void *new_child = march_spawn(raw);
    march_actor_meta *new_meta = find_or_create_meta(new_child);
    new_meta->supervisor = supervisor;
    new_meta->sup_child_index = child_idx;
    new_meta->epoch = inherited_epoch;
    ((int64_t *)supervisor)[4 + child->word_idx] = new_meta->pid_index;
    return new_child;
}

/* one_for_one: only the crashed child is respawned; siblings untouched.
 * Mirrors eval.ml:1588-1637. */
static void march_one_for_one_restart(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    if (child_idx < 0 || child_idx >= sup_meta->sup_num_children) return;
    if (!march_restart_budget_ok(sup_meta)) {
        do_actor_death(supervisor);
        return;
    }
    march_respawn_child(supervisor, sup_meta, child_idx);
}

/* one_for_all: every child is killed and respawned when any one crashes.
 * Mirrors eval.ml:1640-1687. child_idx (which one originally crashed) is
 * unused here — ALL children are affected identically. */
static void march_one_for_all_restart(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    (void)child_idx;
    if (!march_restart_budget_ok(sup_meta)) {
        do_actor_death(supervisor);
        return;
    }
    int n = sup_meta->sup_num_children;
    if (n == 0) return;
    void *live_children[n];
    for (int i = 0; i < n; i++) {
        live_children[i] = NULL;
        int64_t stored_pid_index = ((int64_t *)supervisor)[4 + sup_meta->sup_children[i].word_idx];
        march_actor_meta *cm = find_meta_by_pid_index(stored_pid_index);
        /* The originally-crashed child is already dead at this point (Task 4's
         * do_actor_death ran on it before calling march_supervisor_notify) —
         * march_is_alive is false for it, so it's correctly skipped here and
         * only respawned (not double-killed) in the loop below. */
        if (cm && march_is_alive(cm->actor)) {
            live_children[i] = cm->actor;
            cm->supervisor = NULL;
        }
    }
    for (int i = 0; i < n; i++) {
        if (live_children[i]) do_actor_death(live_children[i]);
    }
    for (int i = 0; i < n; i++) {
        march_respawn_child(supervisor, sup_meta, i);
    }
}

/* rest_for_one: the crashed child and every child declared AFTER it (in
 * sup_children array order, which matches sc_order — Task 3's field
 * injection walks sc.sc_fields in declaration order) are killed and
 * respawned; earlier siblings are untouched. Mirrors eval.ml:1691-1761. */
static void march_rest_for_one_restart(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    if (child_idx < 0 || child_idx >= sup_meta->sup_num_children) return;
    if (!march_restart_budget_ok(sup_meta)) {
        do_actor_death(supervisor);
        return;
    }
    int n = sup_meta->sup_num_children;
    void *live_children[n];
    for (int i = 0; i < n; i++) live_children[i] = NULL;
    for (int i = child_idx + 1; i < n; i++) {
        int64_t stored_pid_index = ((int64_t *)supervisor)[4 + sup_meta->sup_children[i].word_idx];
        march_actor_meta *cm = find_meta_by_pid_index(stored_pid_index);
        if (cm && march_is_alive(cm->actor)) {
            live_children[i] = cm->actor;
            cm->supervisor = NULL;
        }
    }
    for (int i = child_idx + 1; i < n; i++) {
        if (live_children[i]) do_actor_death(live_children[i]);
    }
    for (int i = child_idx; i < n; i++) {
        march_respawn_child(supervisor, sup_meta, i);
    }
}

static void march_supervisor_notify(void *supervisor, march_actor_meta *crashed_meta) {
    march_actor_meta *sup_meta = find_meta(supervisor);
    if (!sup_meta) return;
    int child_idx = crashed_meta->sup_child_index;
    switch (sup_meta->supervisor_strategy) {
        case 0: march_one_for_one_restart(supervisor, sup_meta, child_idx); break;
        case 1: march_one_for_all_restart(supervisor, sup_meta, child_idx); break;
        case 2: march_rest_for_one_restart(supervisor, sup_meta, child_idx); break;
        default: break;
    }
}

/* Mark `actor` dead, run its cleanup callbacks and monitor Down-notifications,
 * wake its green thread — and, notify its supervisor (if it has one) for a
 * possible restart. The ONE place that does this, called both by an
 * explicit kill() and by a panic inside a supervised actor's handler
 * (the crash trap in actor_green_thread below) — mirrors the interpreter's
 * kill = crash_actor unification (eval.ml:3004-3006). */
static void do_actor_death(void *actor) {
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

    /* Deliver Down notifications to all local watchers. */
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

    /* Fire MONITOR_FIRE to any remote (cross-node) watchers of this pid. */
    if (meta) {
        march_dist_monitor_fire_pid(meta->pid_index,
                                     MARCH_DIST_REASON_NORMAL, NULL);
    }

    fields[3] = 0;   /* $alive flag at byte offset 24 */

    /* Wake the actor's green thread so it can notice death and exit. */
    if (meta && meta->green_thread) {
        march_sched_wake(meta->green_thread);
    }

    if (meta && meta->supervisor) {
        march_supervisor_notify(meta->supervisor, meta);
    }
}

void march_kill(void *actor) {
    do_actor_death(actor);
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
    int expected = 0;
    if (atomic_compare_exchange_strong_explicit(
            &g_sched_initialized, &expected, 1,
            memory_order_acq_rel, memory_order_acquire)) {
        march_sched_init();
    }
    /* Daemon: an actor recv loop parks forever unless killed; it must not
     * keep the scheduler (and thus the process) alive once main and all
     * task procs have finished — see wake_idle_daemons in march_scheduler.c. */
    meta->green_thread = march_sched_spawn_daemon(actor_green_thread, meta);
    /* Start the scheduler in a background thread so actor green threads run
     * even when the main thread is blocked inside the HTTP event loop.
     * For non-HTTP programs this is harmless: march_run_scheduler() joins
     * the background thread before returning. */
    march_ensure_sched_started();
    return actor;
}

void march_actor_set_dispatch_id(void *actor, uint32_t name_id) {
    /* Called before march_spawn, so find_or_create_meta to ensure the entry
     * exists; march_spawn will find the same entry and attach the green thread. */
    march_actor_meta *meta = find_or_create_meta(actor);
    meta->dispatch_name_id = name_id;
}

void march_actor_set_call_base(void *actor, int64_t base) {
    /* Emitted by codegen right after the actor record's alloc (same timing
     * as march_actor_set_dispatch_id): before march_spawn, so
     * find_or_create_meta creates the entry the spawn will reuse. */
    march_actor_meta *meta = find_or_create_meta(actor);
    meta->call_tag_base = base;
}

#define MARCH_MIGRATE_SNAPSHOT 2048

void march_actor_broadcast_migrate(uint32_t dispatch_name_id,
                                   void *(*migrate_fn)(void *)) {
    if (!dispatch_name_id) return;

    /* Phase 1: snapshot matching actors under lock.
     * We incrc each actor so it stays alive while we hold the snapshot.
     * The lock is released before injecting messages to avoid holding
     * g_tbl_mu while calling march_sched_send (which may block). */
    march_actor_meta *snaps[MARCH_MIGRATE_SNAPSHOT];
    int n = 0;

    pthread_mutex_lock(&g_tbl_mu);
    for (int b = 0; b < MARCH_SCHED_BUCKETS && n < MARCH_MIGRATE_SNAPSHOT; b++) {
        for (march_actor_meta *m = g_actor_tbl[b];
             m && n < MARCH_MIGRATE_SNAPSHOT;
             m = m->tbl_next) {
            if (m->dispatch_name_id == dispatch_name_id && m->actor && m->green_thread) {
                march_incrc(m->actor);
                snaps[n++] = m;
            }
        }
    }
    pthread_mutex_unlock(&g_tbl_mu);

    /* Phase 2: inject migrate messages outside the lock. */
    for (int i = 0; i < n; i++) {
        march_migrate_msg_t *mm = (march_migrate_msg_t *)malloc(sizeof(*mm));
        if (mm) {
            mm->_rc        = 1;
            mm->_tag       = MARCH_MIGRATE_TAG;
            mm->migrate_fn = migrate_fn;
            march_sched_send(snaps[i]->green_thread, mm);
        }
        march_decrc(snaps[i]->actor);
    }
}

/* ── Lightweight task spawn ──────────────────────────────────────────────── */

/* Forward declarations for Result helpers defined later in this file. */
static void *mk_ok(void *value);
static void *mk_err_cstr(const char *msg);

/* Wrapper struct passed to the trampoline so it can access both the closure
 * and the Task heap object (to store the result on completion). */
typedef struct {
    void     *clo;   /* thunk closure pointer (ownership transferred from caller) */
    int64_t  *task;  /* Task heap object (weak ref — Task outlives the thread) */
} march_thunk_arg;

/* Green-thread trampoline for task_spawn thunk closures.
 * A March thunk closure has layout:
 *   offset  0..7 : ref count (i64)
 *   offset  8..11: tag (i32)
 *   offset 12..15: padding
 *   offset 16..23: apply fn ptr (fn(closure_ptr, i64) -> result_ptr)
 *
 * Called from the green-thread entry via march_sched_spawn.
 *
 * The Task object layout (48 bytes):
 *   word 0 (offset  0): ref count  (i64)
 *   word 1 (offset  8): tag+pad    (i32+i32)
 *   word 2 (offset 16): march_proc* handle  (field 0, for cancel)
 *   word 3 (offset 24): result ptr  (field 1, written on completion)
 *   word 4 (offset 32): done flag   (_Atomic int64_t, 0=running, 1=done)
 *   word 5 (offset 40): in-scheduler waiter (_Atomic march_proc*, 0=none) —
 *                        see task_wait_done / march_thunk_trampoline below.
 *
 * Completion signalling: we write result to word 3 then release-store 1
 * into word 4, then wake any registered waiter (word 5).
 * march_task_await acquire-loads word 4, never dereferencing
 * the proc ptr (word 2) after the proc may have been freed by sched_loop.
 */
/* Foreign-thread task_await support: green threads park-and-wait (they must
 * never block an OS scheduler thread), but foreign threads (evloop pthreads)
 * previously busy-spun with sched_yield, burning a core per in-flight
 * request.  A single global condvar is broadcast on every task completion;
 * foreign waiters do a timed wait and re-check their own done flag, so a
 * broadcast that fires before a waiter registers is harmless (50ms bound). */
static pthread_mutex_t g_task_done_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_task_done_cv = PTHREAD_COND_INITIALIZER;

static void task_wait_done(int64_t *task) {
    if (march_sched_in_scheduler()) {
        /* Register ourselves as the task's waiter (word 5), then re-check
         * the done flag before parking — the standard check/register/
         * recheck sequence that closes the lost-wakeup race against
         * march_thunk_trampoline's completion store (see its comment).
         * Without the fast-path check up front, an already-done task would
         * still pay a park/wake round trip; without the recheck after
         * registering, a task that completes between our first check and
         * registering would park us with nobody left to wake us.
         *
         * Supersedes an earlier spin-then-sleep backoff here (wall-clock
         * CLOCK_MONOTONIC grace period before falling back to nanosleep):
         * that cut wasted CPU on a stalled wait but, A/B-tested against a
         * fork-join workload that crosses March's task-count scaling cliff
         * (~14K-22K concurrent task_spawns), didn't fix the underlying
         * throughput collapse — a LIFO local-deque starvation bug in
         * sched_loop kept genuine sibling work from ever being dispatched.
         * Parking properly (rather than periodically re-polling) removes
         * this proc from the dispatch loop entirely until there's an actual
         * reason to run it again, which addresses both issues at once. */
        march_proc *self = march_sched_current();
        for (;;) {
            if (atomic_load_explicit((_Atomic int64_t *)&task[4],
                                     memory_order_acquire) != 0)
                return;
            /* SEQ_CST ON THE NEXT TWO OPERATIONS IS THE WHOLE FIX for the
             * long-standing ~1-in-20 missed-wakeup deadlock (specs/todos.md
             * "Scheduler fork-join").  This store-then-load and the
             * trampoline's mirror-image store(task[4])-then-load(task[5])
             * form a Dekker / store-buffering pair, and release/acquire does
             * NOT order a store before a subsequent load of a DIFFERENT
             * location.  Concretely, on ARMv8.3+ (Apple Silicon) clang
             * compiles memory_order_acquire to LDAPR — an RCpc load that is
             * architecturally allowed to complete before an earlier STLR
             * drains from the store buffer.  Both sides could therefore read
             * stale values simultaneously: we saw done==0 and parked forever
             * while the trampoline saw waiter==NULL and woke nobody — task
             * complete, waiter parked, exactly the lldb hang state.  This is
             * also why every prior analysis missed it: interleaving-based
             * reasoning implicitly assumes sequential consistency, TSan's
             * instrumentation strengthens the ordering enough to suppress
             * it, and MARCH_NUM_SCHEDULERS=1 removes the second thread.
             * seq_cst forces LDAR (RCsc), which cannot hoist above an
             * earlier STLR, closing the window on both sides.  (A
             * LockSupport-style wake permit in march_sched_wake was tried
             * first and measured useless — under this reordering the
             * trampoline never CALLS march_sched_wake at all, so no permit
             * scheme can help.) */
            atomic_store_explicit((_Atomic int64_t *)&task[5],
                                  (int64_t)(uintptr_t)self,
                                  memory_order_seq_cst);
            if (atomic_load_explicit((_Atomic int64_t *)&task[4],
                                     memory_order_seq_cst) != 0) {
                atomic_store_explicit((_Atomic int64_t *)&task[5], 0,
                                      memory_order_relaxed);
                return;
            }
            march_sched_park_self();
            /* Resumed via march_sched_wake from the trampoline (or, in
             * principle, a spurious wake) — loop back and recheck rather
             * than assuming completion. */
        }
    }
    pthread_mutex_lock(&g_task_done_mu);
    while (atomic_load_explicit((_Atomic int64_t *)&task[4],
                                memory_order_acquire) == 0) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);          /* cond waits use REALTIME */
        ts.tv_nsec += 50 * 1000000L;                  /* 50ms re-check bound */
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec += 1; ts.tv_nsec -= 1000000000L; }
        pthread_cond_timedwait(&g_task_done_cv, &g_task_done_mu, &ts);
    }
    pthread_mutex_unlock(&g_task_done_mu);
}

static void march_thunk_trampoline(void *arg) {
    march_thunk_arg *wa = (march_thunk_arg *)arg;
    void *clo = wa->clo;
    int64_t *task = wa->task;
    free(wa);  /* free the small wrapper; clo and task are separately managed */
    /* Record our own proc handle in task[2] NOW, before executing the closure.
     * This closes the race where the spawning thread writes task[2] = p only
     * AFTER march_sched_spawn returns — a work-stealing scheduler can run
     * (and complete) this proc before the spawner gets CPU back. */
    if (task) {
        task[2] = (int64_t)(uintptr_t)march_sched_current();
    }
    typedef void *(*apply_fn_t)(void *, int64_t);
    apply_fn_t apply = *(apply_fn_t *)((char *)clo + 16);
    void *result = apply(clo, (int64_t)0);
    if (task) {
        /* Tag the result for the uniform March value convention: scalars (Int,
         * Bool, Unit) are returned as raw i64 by the apply function, but the
         * Ok(n) destructure path loads the field as ptr and applies a conditional
         * ashr-1 untag.  Tag all results as (raw << 1) | 1 so the untag recovers
         * the original value.  Heap pointers fit in 63 bits on all supported
         * targets (ARM64/x86-64 use ≤48-bit user-space addresses), so the shift
         * is lossless. */
        int64_t raw = (int64_t)(uintptr_t)result;
        task[3] = (raw << 1) | (int64_t)1;     /* tagged result at offset 24 */
        /* SEQ_CST store + SEQ_CST load: this store(task[4])-then-load(task[5])
         * is one half of a Dekker / store-buffering pair with task_wait_done's
         * store(task[5])-then-load(task[4]) — see the long comment there.
         * The previous release/acquire pair allowed BOTH sides' loads to read
         * stale values on ARMv8.3+ (clang's acquire = LDAPR, an RCpc load
         * that may complete before an earlier STLR drains), which is the
         * ~1-in-20 missed-wakeup deadlock: we read waiter==NULL and woke
         * nobody while the waiter read done==0 and parked forever.  The
         * comment that used to live here — "a missed wake here is harmless
         * because the waiter's recheck catches done=1" — was the bug in
         * prose form: that recheck reasoning only holds under sequential
         * consistency, which release/acquire does not provide for a
         * store-then-load pair on different addresses.  seq_cst (STLR + LDAR,
         * RCsc) restores exactly the ordering the reasoning assumed, and the
         * store still carries the task[3]-before-done publication the release
         * store provided (seq_cst is a superset).  march_sched_wake remains a
         * safe no-op if the waiter is NULL or not yet parked. */
        atomic_store_explicit((_Atomic int64_t *)&task[4], 1,
                              memory_order_seq_cst);
        march_proc *waiter = (march_proc *)(uintptr_t)atomic_load_explicit(
            (_Atomic int64_t *)&task[5], memory_order_seq_cst);
        if (waiter) march_sched_wake(waiter);
        /* Wake any foreign (non-scheduler) threads parked in task_wait_done's
         * timed wait.  Touches no task fields, so it is safe to do before or
         * after the decrc below; placed here to keep the "signal completion"
         * steps together. */
        pthread_mutex_lock(&g_task_done_mu);
        pthread_cond_broadcast(&g_task_done_cv);
        pthread_mutex_unlock(&g_task_done_mu);
        /* Drop the trampoline's RC hold taken at spawn time (see incrc in
         * march_task_spawn_thunk).  If the caller already dropped their handle
         * (fire-and-forget), this is the last reference and frees the object.
         * If the caller still holds the handle, this drops RC from 2 → 1. */
        march_decrc(task);
    }
    /* No march_decrc(clo) here. lib/tir/perceus.ml's insert_apply_fn_clo_drop
     * (see lib/tir/borrow.ml's $clo-ownership pin) now makes a CAPTURING
     * thunk's own apply function release its one reference to $clo
     * internally, as the last thing it does before returning. Decrementing
     * it again here double-consumed that single reference — confirmed via a
     * single-capture task_spawn thunk called through this trampoline,
     * SIGABRT("RC underflow") on every run before this fix, clean after.
     * A CAPTURE-FREE thunk's apply function does NOT drop $clo (see the
     * fv-extraction guard in insert_apply_fn_clo_drop) because natively its
     * closure is llvm_emit's immortal static global, where a decrement was
     * always a no-op — so removing this decrc changes nothing for that case
     * either. (Under the REPL/JIT a capture-free closure is a real
     * allocation and this removal does leave it unreleased when spawned via
     * task_spawn from a fragment — a narrow, documented leak, not a crash;
     * see specs/todos.md.) */
    march_sched_exit();
}

/* Spawn a thunk closure (fn () -> T) as an async green thread.
 *
 * Layout of the returned Task object (48 bytes):
 *   offset  0..7 : ref count (i64)
 *   offset  8..11: tag = 0 (i32)
 *   offset 12..15: padding
 *   offset 16..23: field 0 = march_proc* (green thread handle, for cancel)
 *   offset 24..31: field 1 = result ptr (written by trampoline on exit)
 *   offset 32..39: done flag (atomic, 0=running, 1=done)
 *   offset 40..47: in-scheduler waiter (atomic march_proc*, 0=none)
 *
 * The caller can pass this to task_await / kill. */
void *march_task_spawn_thunk(void *clo_ptr) {
    int expected = 0;
    if (atomic_compare_exchange_strong_explicit(
            &g_sched_initialized, &expected, 1,
            memory_order_acq_rel, memory_order_acquire)) {
        march_sched_init();
    }
    /* Perceus treats task_spawn as a consuming call: the caller transfers its
     * reference to the task.  No IncRC needed here; the closure's existing
     * rc=1 is the task's reference, released by march_decrc in the trampoline. */
    march_ensure_sched_started();   /* start background scheduler if needed */
    /* Allocate Task at 48 bytes (header + proc ptr + result ptr + done flag
     * + in-scheduler waiter — see task_wait_done). */
    int64_t *task = (int64_t *)march_alloc(48);
    /* Extra RC hold for the trampoline's wa->task raw pointer.  The caller
     * owns RC=1; this bumps to RC=2 so a fire-and-forget drop (RC→1) doesn't
     * free the object before the trampoline writes the result. */
    if (task) march_incrc(task);
    march_thunk_arg *wa = (march_thunk_arg *)malloc(sizeof(march_thunk_arg));
    if (!wa) { return (void *)task; }
    wa->clo  = clo_ptr;
    wa->task = task;
    /* Publish the proc LAST.  Once march_sched_spawn returns, a work-stealing
     * scheduler on another OS thread may already be running march_thunk_trampoline
     * for this proc — which writes task[2] (proc handle), task[3] (result) and
     * task[4] (done flag).  Any store to the task object here, AFTER the spawn,
     * therefore races the trampoline with no synchronization between them and
     * can clobber a completed result/done flag back to zero (confirmed by
     * ThreadSanitizer: march_runtime.c:1833 write vs this site).  There is
     * nothing to write: march_alloc() zero-initialises the whole object (so
     * result/done start at 0) and the trampoline records task[2] itself as its
     * first action (see march_thunk_trampoline).  Leave the task untouched. */
    (void)march_sched_spawn(march_thunk_trampoline, wa);
    return (void *)task;
}

/* Wait for a task to complete and return Ok(result).
 *
 * Spins on the task-embedded done flag (word 4) until the trampoline
 * release-stores 1 into it.  We never dereference the proc ptr (word 2)
 * after the proc may have been freed by sched_loop — doing so caused a
 * use-after-free where calloc reuse zeroed the freed memory, making
 * p->status read as PROC_RUNNABLE (0) forever. */
void *march_task_await(void *task_obj) {
    if (!task_obj) return mk_err_cstr("task_await: null task");
    int64_t *task = (int64_t *)task_obj;
    task_wait_done(task);
    void *result = (void *)(uintptr_t)task[3];
    return mk_ok(result);
}

/* Like march_task_await, but returns the tagged result value directly
 * (no Ok wrapper).  Used by task_await_unwrap to avoid allocating an
 * intermediate Ok object.  The caller (LLVM emit) applies the conditional
 * ashr untag to recover the original scalar or heap-pointer value. */
void *march_task_await_value(void *task_obj) {
    if (!task_obj) return (void *)1; /* tagged Unit/null */
    int64_t *task = (int64_t *)task_obj;
    task_wait_done(task);
    return (void *)(uintptr_t)task[3]; /* tagged result */
}

/* Spawn a thunk closure with an associated cancel token.
 * If tok is non-NULL, its cancellation is checked at yield points inside the
 * green thread.  Behaves like march_task_spawn_thunk otherwise. */
void *march_task_spawn_with_cancel_thunk(void *clo_ptr, void *tok_ptr) {
    int expected = 0;
    if (atomic_compare_exchange_strong_explicit(
            &g_sched_initialized, &expected, 1,
            memory_order_acq_rel, memory_order_acquire)) {
        march_sched_init();
    }
    march_ensure_sched_started();
    int64_t *task = (int64_t *)march_alloc(48);  /* see march_task_spawn_thunk layout */
    if (task) march_incrc(task);  /* trampoline's RC hold — see march_task_spawn_thunk */
    march_thunk_arg *wa = (march_thunk_arg *)malloc(sizeof(march_thunk_arg));
    if (!wa) { return (void *)task; }
    wa->clo  = clo_ptr;
    wa->task = task;
    march_cancel_token *tok = (march_cancel_token *)tok_ptr;
    /* Publish the proc LAST — see march_task_spawn_thunk for why storing into
     * the task object after the spawn races the trampoline.  march_alloc zeroed
     * the object and the trampoline records task[2] itself. */
    (void)march_sched_spawn_with_cancel(march_thunk_trampoline, wa, tok);
    return (void *)task;
}

/* Cancel the task identified by task_obj by marking its green thread DEAD.
 * This is a best-effort cooperative cancellation: if the thread is currently
 * running it will be stopped at the next yield point.
 *
 * We write a cancellation sentinel into task[3] (the result field) BEFORE
 * setting PROC_DEAD.  Without this, march_task_await sees PROC_DEAD and reads
 * task[3] = null, boxing it as Ok(null_ptr) instead of signalling cancellation. */
void march_task_cancel_by_id(void *task_obj) {
    if (!task_obj) return;
    int64_t *task = (int64_t *)task_obj;
    march_proc *p = (march_proc *)(uintptr_t)task[2];
    if (!p) return;
    /* Store the cancelled sentinel before the status flip so the await side
     * always sees a valid error result when it observes PROC_DEAD. */
    task[3] = (int64_t)(uintptr_t)mk_err_cstr("task cancelled");
    atomic_store_explicit(&p->status, PROC_DEAD, memory_order_release);
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
        /* Signal workers to stop accepting new work, then join. */
        march_sched_request_shutdown();
        pthread_join(g_sched_bg_thread, NULL);
        atomic_store_explicit(&g_sched_bg_started, 0, memory_order_relaxed);
        atomic_store_explicit(&g_sched_initialized, 0, memory_order_release);
        return;
    }
    if (g_in_scheduler) return;
    g_in_scheduler = 1;
    /* Publish that an inline scheduler is running BEFORE march_sched_run()
     * starts workers.  Ordering: this store happens-before the workers start,
     * which happens-before the main green thread runs, which happens-before
     * any evloop pthread exists — so evloop-origin march_ensure_sched_started
     * calls always observe the flag.  A theoretical window exists only for
     * foreign threads created before march_run_scheduler() is entered, which
     * do not occur in compiled-program startup (main itself is the first
     * green thread). */
    atomic_store_explicit(&g_sched_inline_running, 1, memory_order_release);
    march_sched_request_shutdown();
    march_sched_run();
    atomic_store_explicit(&g_sched_inline_running, 0, memory_order_release);
    g_in_scheduler = 0;
    atomic_store_explicit(&g_sched_initialized, 0, memory_order_release);
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
 *   4. Wait for the reply: timeout_ms <= 0 blocks forever via
 *      march_sched_recv(); a positive timeout_ms does a deadline-bounded
 *      yield-poll and returns Err("actor_call: timeout") past the deadline.
 *   5. Return Ok(reply_value).
 *
 * RC contract: we consume one reference to inner_msg (via march_decrc after
 * reading the tag) and transfer ownership of the new call_msg to the actor.
 */
void *march_actor_call(void *actor, void *inner_msg, int64_t timeout_ms) {
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
    int32_t msg_tag;
    if (IS_HEAP_PTR(inner_msg)) {
        msg_tag = ((march_hdr *)inner_msg)->tag;
        march_decrc(inner_msg);
    } else {
        /* Enum-shaped sentinel types (several nullary ctors) compile to
         * immediates: odd tagged ints carrying the ctor index. Decode
         * instead of dereferencing (which would fault). */
        int64_t raw = (int64_t)(intptr_t)inner_msg;
        msg_tag = (raw & 1) ? (int32_t)(raw >> 1) : 0;
    }

    /* Positional dispatch: the sentinel's per-type tag IS the handler
     * index. The actor's dispatch switch matches GLOBAL msg tags (F19:
     * base 0x0100_0000 + declaration index, unique across actors), so
     * translate index → global tag via the base stamped at alloc time.
     * Without this every call message falls to the dispatch default arm
     * and is silently dropped — the caller blocks forever (or times out).
     *
     * Only rebase a tag BELOW the F19 global floor: a caller may also pass
     * the actor's OWN _Msg constructor (e.g. actor_call(pool, Checkout(0)))
     * whose tag is ALREADY global — rebasing it again would double-add the
     * base and misroute (the erased_option_niche_fbip_codegen regression). */
    if (meta->call_tag_base && msg_tag < 0x01000000)
        msg_tag = (int32_t)(meta->call_tag_base + msg_tag);

    /* Build the augmented call message: same tag, field 0 = caller proc ptr.
     * Layout: 16-byte header + 8-byte ptr field = 24 bytes. */
    void *call_msg = march_alloc(24);
    MARCH_SET_TAG(call_msg, msg_tag);
    MARCH_FIELD(call_msg, 0) = (int64_t)(uintptr_t)caller;

    march_sched_send(meta->green_thread, call_msg);

    if (timeout_ms <= 0) {
        /* Preserve wait-forever semantics for callers that opt out. */
        void *result = march_sched_recv();
        if (result == MARCH_RECV_NO_MSG)
            return mk_err_cstr("no reply (timeout or unhandled Call)");
        return mk_ok(result);
    }

    /* Timed wait: poll the mailbox with cooperative yields until the
     * deadline.  A parked-with-deadline mechanism needs timer support the
     * scheduler doesn't have; replies are normally immediate, so the yield
     * loop only spins for the (rare) slow-actor case, bounded by timeout_ms.
     *
     * The Err payloads match the interpreter's no-reply message exactly so
     * both backends surface the same value.
     *
     * Known limitation: on timeout, a late reply still lands in the
     * caller's mailbox. Safe for per-call task green threads (the thread
     * exits and sends to dead procs are dropped); a long-lived green thread
     * mixing Actor.call and raw receive could observe a stale reply after
     * a timeout. */
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int64_t deadline_ms = (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000
                          + timeout_ms;
    for (;;) {
        void *msg = NULL;
        if (march_sched_try_recv2(&msg)) {
            if (msg == MARCH_RECV_NO_MSG)
                return mk_err_cstr("no reply (timeout or unhandled Call)");
            return mk_ok(msg);
        }
        clock_gettime(CLOCK_MONOTONIC, &ts);
        int64_t now_ms = (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
        if (now_ms >= deadline_ms)
            return mk_err_cstr("no reply (timeout or unhandled Call)");
        march_sched_yield();
    }
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

/* Helper: None = raw 0 in the niche representation. */
static void *make_none(void) {
    return (void *)0;
}

/* Helper: Some(int) = tagged immediate (val<<1)|1.
 * march_alloc never returns 0 or an odd-bit pointer, so niche None=0 and
 * Some(int)=odd are unambiguous against any heap pointer payload. */
static void *make_some_i64(int64_t val) {
    return (void *)(((int64_t)val << 1) | 1);
}

/* Helper: Some(ptr) = the raw pointer (heap ptr is always nonzero). */
static void *make_some_ptr(void *val) {
    return val;
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

/* Substring search shared by every string search site in this file.
 *
 * Two stages: memchr finds candidate first bytes, memcmp confirms.  libc's
 * memchr is SIMD-optimised on every platform we target, so this gets vector
 * scanning with no intrinsics and no per-architecture code — the same reasoning
 * that keeps runtime/march_http_parse_simd.c's scalar fallback rather than
 * requiring SSE4.2 everywhere.  The previous implementation called memcmp at
 * every byte offset, which measured at roughly 0.5 GB/s.
 *
 * march_string is LENGTH-COUNTED and may contain NUL bytes, so nothing here may
 * use strstr/strchr or treat NUL as a terminator.
 *
 * On a failed candidate the scan resumes at hit + 1, NOT hit + nlen: needles
 * can overlap, and skipping the whole needle would miss the match in
 * ("aaaa", "aa") starting at index 1.
 *
 * Returns a pointer into [hay], or NULL when there is no match. */
static const char *march_memmem(const char *hay, int64_t haylen,
                                const char *needle, int64_t nlen) {
    if (nlen == 0) return hay;
    if (nlen > haylen) return NULL;
    const char first = needle[0];
    const char *p = hay;
    int64_t remaining = haylen;
    while (remaining >= nlen) {
        /* Only the first (remaining - nlen + 1) bytes can start a match; a hit
         * beyond that could not be followed by a full needle. */
        const char *hit =
            (const char *)memchr(p, first, (size_t)(remaining - nlen + 1));
        if (!hit) return NULL;
        if (memcmp(hit, needle, (size_t)nlen) == 0) return hit;
        remaining -= (hit - p) + 1;
        p = hit + 1;
    }
    return NULL;
}

int64_t march_string_contains(void *s, void *sub) {
    march_string *ss = (march_string *)s;
    march_string *su = (march_string *)sub;
    if (su->len == 0) return 1;
    if (ss->len < su->len) return 0;
    return march_memmem(ss->data, ss->len, su->data, su->len) != NULL;
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
    /* memmem walk rather than a memcmp at every offset.  Separators are found
     * by the SIMD-optimised memchr fast path; the emitted parts and the
     * empty-field behaviour for adjacent separators are unchanged. */
    while (start <= ss->len - sp->len) {
        const char *hit = march_memmem(ss->data + start, ss->len - start,
                                       sp->data, sp->len);
        if (!hit) break;
        int64_t i = hit - ss->data;
        if (count >= cap) { cap *= 2; parts = realloc(parts, sizeof(void *) * (size_t)cap); }
        parts[count++] = march_string_lit(ss->data + start, i - start);
        start = i + sp->len;
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
    march_string *r = march_string_alloc(total);
    int64_t off = 0;
    cur = lst;
    while (1) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break; /* Nil */
        march_string *ch = *(march_string **)((char *)cur + 16);
        march_str_copy(r->data + off, ch->data, (size_t)ch->len);
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
    const char *hit = march_memmem(ss->data, ss->len, so->data, so->len);
    if (hit) {
        int64_t i = hit - ss->data;
        int64_t newlen = ss->len - so->len + sn->len;
        march_string *r = march_string_alloc(newlen);
        march_str_copy(r->data, ss->data, (size_t)i);
        march_str_copy(r->data + i, sn->data, (size_t)sn->len);
        march_str_copy(r->data + i + sn->len, ss->data + i + so->len, (size_t)(ss->len - i - so->len));
        r->data[newlen] = '\0';
        return r;
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
    /* Jump between matches and bulk-copy the span in front of each, rather than
     * testing and copying one byte at a time.  The old loop paid a memcmp per
     * input byte in the common no-match case AND copied the literal text a byte
     * at a time; this pays one memchr-driven search per match and one memcpy
     * per span. */
    while (i <= ss->len - so->len) {
        const char *hit = march_memmem(ss->data + i, ss->len - i, so->data, so->len);
        if (!hit) break;
        int64_t at   = hit - ss->data;
        int64_t span = at - i;                 /* literal bytes before the match */
        while (out + span + sn->len + 1 >= cap) { cap *= 2; buf = realloc(buf, (size_t)cap); }
        march_str_copy(buf + out, ss->data + i, (size_t)span);
        out += span;
        march_str_copy(buf + out, sn->data, (size_t)sn->len);
        out += sn->len;
        i = at + so->len;
    }
    /* Copy the remaining tail in one go. */
    {
        int64_t rest = ss->len - i;
        while (out + rest + 1 >= cap) { cap *= 2; buf = realloc(buf, (size_t)cap); }
        march_str_copy(buf + out, ss->data + i, (size_t)rest);
        out += rest;
    }
    void *result = march_string_lit(buf, out);
    free(buf);
    return result;
}

/* ASCII-only case mapping, deliberately NOT ctype.h's tolower/toupper.
 *
 * Two reasons, one correctness and one speed:
 *
 * 1. ctype.h is LOCALE-SENSITIVE, and March strings are UTF-8. Under a
 *    single-byte locale, tolower rewrites bytes >= 0x80 — measured on macOS,
 *    en_US.ISO8859-1 maps 0xC3 to 0xE3, and 0xC3 is the lead byte of every
 *    2-byte UTF-8 sequence. That silently corrupts the encoding. March never
 *    calls setlocale, but any linked library or embedding application can, and
 *    then these functions change behaviour underneath it. Depending on global
 *    process state for string semantics is not a defensible contract.
 *
 * 2. The unsigned-wrap comparison is branch-free and lets the compiler
 *    vectorize the surrounding loop, where a call to tolower cannot be.
 *
 * Scope is unchanged: ASCII only. Non-ASCII bytes pass through untouched,
 * which is what the previous implementation effectively did in the "C" locale
 * and what the stdlib docs describe. Full Unicode case mapping is a different
 * feature (it is not byte-wise — it changes string length). */
static inline char march_ascii_lower(char c) {
    unsigned char u = (unsigned char)c;
    return (char)((unsigned char)(u - 'A') < 26u ? (unsigned char)(u + 32) : u);
}
static inline char march_ascii_upper(char c) {
    unsigned char u = (unsigned char)c;
    return (char)((unsigned char)(u - 'a') < 26u ? (unsigned char)(u - 32) : u);
}

void *march_string_to_lowercase(void *s) {
    march_string *ss = (march_string *)s;
    march_string *r = march_string_alloc(ss->len);
    for (int64_t i = 0; i < ss->len; i++) {
        r->data[i] = march_ascii_lower(ss->data[i]);
    }
    r->data[ss->len] = '\0';
    str_stats_copied(ss->len);
    return r;
}

void *march_string_to_uppercase(void *s) {
    march_string *ss = (march_string *)s;
    march_string *r = march_string_alloc(ss->len);
    for (int64_t i = 0; i < ss->len; i++) {
        r->data[i] = march_ascii_upper(ss->data[i]);
    }
    r->data[ss->len] = '\0';
    str_stats_copied(ss->len);
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
    int64_t total;
    /* Bug fix: ss->len * n silently overflows when both values are large,
     * producing a tiny allocation that the memcpy loop then overflows.
     * Example: len=500_000_000, n=5 wraps to a negative total. */
    if (__builtin_mul_overflow(ss->len, n, &total)) {
        fputs("march: runtime error: string too large (repeat overflow)\n", stderr); exit(1);
    }
    march_string *r = march_string_alloc(total);
    for (int64_t i = 0; i < n; i++) {
        march_str_copy(r->data + i * ss->len, ss->data, (size_t)ss->len);
    }
    r->data[total] = '\0';
    return r;
}

void *march_string_reverse(void *s) {
    march_string *ss = (march_string *)s;
    march_string *r = march_string_alloc(ss->len);
    for (int64_t i = 0; i < ss->len; i++) {
        r->data[i] = ss->data[ss->len - 1 - i];
    }
    r->data[ss->len] = '\0';
    str_stats_copied(ss->len);
    return r;
}

void *march_string_pad_left(void *s, int64_t width, void *fill) {
    march_string *ss = (march_string *)s;
    march_string *sf = (march_string *)fill;
    if (ss->len >= width) return march_string_lit(ss->data, ss->len);
    int64_t pad = width - ss->len;
    int64_t total = width;
    march_string *r = march_string_alloc(total);
    char fc = (sf->len > 0) ? sf->data[0] : ' ';
    memset(r->data, fc, (size_t)pad);
    march_str_copy(r->data + pad, ss->data, (size_t)ss->len);
    r->data[total] = '\0';
    return r;
}

void *march_string_pad_right(void *s, int64_t width, void *fill) {
    march_string *ss = (march_string *)s;
    march_string *sf = (march_string *)fill;
    if (ss->len >= width) return march_string_lit(ss->data, ss->len);
    int64_t pad = width - ss->len;
    int64_t total = width;
    march_string *r = march_string_alloc(total);
    march_str_copy(r->data, ss->data, (size_t)ss->len);
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
    const char *hit = march_memmem(ss->data, ss->len, su->data, su->len);
    return hit ? make_some_i64(hit - ss->data) : make_none();
}

/* index_of starting at a byte offset.  Returns Option(Int).
 *
 * The index is in S's OWN coordinates, not relative to [start], so a caller can
 * feed the result straight back in as the next start when tokenizing.  Without
 * this entry point the only way to find the next separator is to slice off the
 * tail and search that, which re-copies the remaining bytes at every step and
 * makes a full tokenize O(n^2) — bench/string_slice_walk and
 * bench/string_parallel_scan both had to be written around exactly that.
 *
 * Clamping mirrors march_string_index_of: an empty needle matches immediately
 * (here, at the clamped start), a negative start is treated as 0, and a start
 * past the end finds nothing. */
void *march_string_index_of_from(void *s, void *sub, int64_t start) {
    march_string *ss = (march_string *)s;
    march_string *su = (march_string *)sub;
    if (start < 0) start = 0;
    if (start > ss->len) return make_none();
    if (su->len == 0) return make_some_i64(start);
    if (su->len > ss->len - start) return make_none();
    const char *hit = march_memmem(ss->data + start, ss->len - start,
                                   su->data, su->len);
    return hit ? make_some_i64(hit - ss->data) : make_none();
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

/* Returns Option(Float). Option(Float) stays BOXED (0.0 == raw 0, not niche-safe).
 * None is a heap cell with tag=0; cannot use make_none() which returns raw 0. */
void *march_string_to_float(void *s) {
    march_string *str = (march_string *)s;
    char *end;
    double f = strtod(str->data, &end);
    if (end == str->data || *end != '\0') {
        return march_alloc(16);  /* boxed None: tag stays 0 */
    }
    /* Some(f): tag=1, one ptr field at offset 16 holding a march_alloc_float
     * box — NOT the raw double. The compiler's generic Boxed-ADT ctor
     * convention treats every ctor field slot as pointer-width and, for a
     * Float field, loads it as `ptr` then calls march_unbox_float(ptr) to
     * recover the double (see native_float_arr_to_list's identical
     * float-boxing convention above and the compiled `List(Float)` fix this
     * mirrors). Storing the raw double bits here instead made
     * march_unbox_float dereference the float's own bit pattern as a heap
     * pointer — SIGSEGV. */
    void *some = march_alloc(16 + 8);
    int32_t *tp = (int32_t *)((char *)some + 8);
    tp[0] = 1;
    void **fp = (void **)((char *)some + 16);
    fp[0] = march_alloc_float(f);
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

/* file_read_line / file_read_chunk : Int -> Option(String).
 *
 * Option(String) is NICHE-encoded in compiled March (Some's payload is the
 * value itself, None is raw NULL — see the csv_next_row note in
 * lib/typecheck/typecheck.ml for the same convention), so these MUST return
 * the march_string directly or NULL.  They historically returned mk_ok /
 * mk_err Result cells like the rest of the file family — under the niche
 * read, every return (including the EOF Err) looked like Some(<Result
 * cell>), so a compiled read-to-EOF loop never terminated and any use of
 * the "line" crashed on the misread cell.  Unreachable until try_finally
 * gained a native implementation (nothing fd-based would link), which is
 * why it survived: the interpreter (lib/eval/eval.ml) always had the
 * Some/None contract these now match.  Non-EOF read errors fold into None
 * (end of stream), mirroring the interpreter's End_of_file handling — the
 * Option type has no error channel. */
void *march_file_read_line(void *handle_ptr) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    if (!f) return NULL;                                   /* None */
    char buf[4096];
    if (!fgets(buf, sizeof(buf), f)) return NULL;          /* None: EOF/error */
    size_t len = strlen(buf);
    /* Strip trailing newline */
    if (len > 0 && buf[len-1] == '\n') { buf[--len] = '\0'; }
    if (len > 0 && buf[len-1] == '\r') { buf[--len] = '\0'; }
    return march_string_lit(buf, (int64_t)len);            /* Some(line) */
}

void *march_file_read_chunk(void *handle_ptr, int64_t size) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    if (!f || size <= 0) return NULL;                      /* None */
    char *buf = (char *)malloc((size_t)size);
    if (!buf) return NULL;                                 /* None */
    size_t n = fread(buf, 1, (size_t)size, f);
    if (n == 0) { free(buf); return NULL; }                /* None: EOF/error */
    void *s = march_string_lit(buf, (int64_t)n);
    free(buf);
    return s;                                              /* Some(chunk) */
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

/* dns_resolve(host) → Result(List(String), String) */
void *dns_resolve(void *host_ptr) {
    march_string *hs = (march_string *)host_ptr;
    char hostname[1024];
    size_t copy_len = (size_t)hs->len < sizeof(hostname) - 1 ? (size_t)hs->len : sizeof(hostname) - 1;
    memcpy(hostname, hs->data, copy_len);
    hostname[copy_len] = '\0';

    struct addrinfo hints, *res, *rp;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    int rc = getaddrinfo(hostname, NULL, &hints, &res);
    if (rc != 0) {
        const char *msg = gai_strerror(rc);
        return mk_err_cstr(msg);
    }

    /* Collect unique IP strings into a temporary array. */
    char addrs[64][INET6_ADDRSTRLEN];
    int n = 0;
    for (rp = res; rp != NULL && n < 64; rp = rp->ai_next) {
        char buf[INET6_ADDRSTRLEN];
        void *addr_ptr;
        if (rp->ai_family == AF_INET)
            addr_ptr = &((struct sockaddr_in  *)rp->ai_addr)->sin_addr;
        else if (rp->ai_family == AF_INET6)
            addr_ptr = &((struct sockaddr_in6 *)rp->ai_addr)->sin6_addr;
        else continue;
        if (!inet_ntop(rp->ai_family, addr_ptr, buf, sizeof(buf))) continue;
        /* Deduplicate */
        int dup = 0;
        for (int i = 0; i < n; i++) if (strcmp(addrs[i], buf) == 0) { dup = 1; break; }
        if (!dup) { strncpy(addrs[n], buf, INET6_ADDRSTRLEN - 1); addrs[n][INET6_ADDRSTRLEN-1]='\0'; n++; }
    }
    freeaddrinfo(res);

    /* Build List(String) in reverse (build_string_list handles it). */
    char *ptrs[64];
    for (int i = 0; i < n; i++) ptrs[i] = addrs[i];
    void *list = build_string_list(ptrs, n);
    return mk_ok(list);
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

/* ── Async process management ───────────────────────────────────────── */

/* Global fd-to-FILE* registry for live processes.
   Each entry: slot → {pid, stdout FILE*, stdin FILE*}
   Keyed by the stream_id stored in LiveProcess(pid, stream_id). */
#define LIVE_PROC_MAX 64
static struct { int used; pid_t pid; FILE *fp; FILE *write_fp; } live_proc_reg[LIVE_PROC_MAX];
static int live_proc_next = 0;

/* process_spawn_async(command, args) → Result(LiveProcess(pid,id), String) */
void *march_process_spawn_async(void *cmd_obj, void *args_list) {
    march_string *cmd_s = (march_string *)cmd_obj;
    /* Build argv */
    int extra = 0;
    void *tmp = args_list;
    while (((march_hdr *)tmp)->tag == 1) { extra++; tmp = MARCH_FIELD_PTR(tmp, 1); }
    int argc = 1 + extra;
    char **argv = (char **)malloc((size_t)(argc + 1) * sizeof(char *));
    argv[0] = (char *)malloc((size_t)(cmd_s->len + 1));
    memcpy(argv[0], cmd_s->data, (size_t)cmd_s->len); argv[0][cmd_s->len] = '\0';
    int i = 1; tmp = args_list;
    while (((march_hdr *)tmp)->tag == 1) {
        march_string *a = (march_string *)MARCH_FIELD_PTR(tmp, 0);
        argv[i] = (char *)malloc((size_t)(a->len + 1));
        memcpy(argv[i], a->data, (size_t)a->len); argv[i][a->len] = '\0';
        i++; tmp = MARCH_FIELD_PTR(tmp, 1);
    }
    argv[argc] = NULL;
    /* Pipes for stdin (write) and stdout (read) */
    int stdin_pfd[2], stdout_pfd[2];
    if (pipe(stdin_pfd) != 0) {
        for (int j = 0; j < argc; j++) free(argv[j]); free(argv);
        return mk_err_cstr("pipe failed (stdin)");
    }
    if (pipe(stdout_pfd) != 0) {
        close(stdin_pfd[0]); close(stdin_pfd[1]);
        for (int j = 0; j < argc; j++) free(argv[j]); free(argv);
        return mk_err_cstr("pipe failed (stdout)");
    }
    pid_t pid = fork();
    if (pid == 0) {
        close(stdin_pfd[1]);   /* child closes write end of stdin pipe */
        close(stdout_pfd[0]);  /* child closes read end of stdout pipe */
        dup2(stdin_pfd[0],  STDIN_FILENO);  close(stdin_pfd[0]);
        dup2(stdout_pfd[1], STDOUT_FILENO); close(stdout_pfd[1]);
        execvp(argv[0], argv); _exit(127);
    }
    close(stdin_pfd[0]);   /* parent closes read end of stdin pipe */
    close(stdout_pfd[1]);  /* parent closes write end of stdout pipe */
    for (int j = 0; j < argc; j++) free(argv[j]); free(argv);
    if (pid < 0) {
        close(stdin_pfd[1]); close(stdout_pfd[0]);
        return mk_err_cstr("fork failed");
    }
    /* Register */
    int id = live_proc_next++ % LIVE_PROC_MAX;
    if (live_proc_reg[id].fp)       { fclose(live_proc_reg[id].fp);       live_proc_reg[id].fp = NULL; }
    if (live_proc_reg[id].write_fp) { fclose(live_proc_reg[id].write_fp); live_proc_reg[id].write_fp = NULL; }
    live_proc_reg[id].used     = 1;
    live_proc_reg[id].pid      = pid;
    live_proc_reg[id].fp       = fdopen(stdout_pfd[0], "r");
    live_proc_reg[id].write_fp = fdopen(stdin_pfd[1],  "w");
    /* Build LiveProcess(pid, id): tag=0, 2 int64 fields */
    void *lp = march_alloc(16 + 16);
    MARCH_FIELD(lp, 0) = (int64_t)pid;
    MARCH_FIELD(lp, 1) = (int64_t)id;
    return mk_ok(lp);
}

/* process_read_line(lp) → Option(String) */
void *march_process_read_line(void *lp_obj) {
    int64_t id = MARCH_FIELD(lp_obj, 1);
    if (id < 0 || id >= LIVE_PROC_MAX || !live_proc_reg[id].used || !live_proc_reg[id].fp)
        return make_none();
    char buf[4096]; char *line = fgets(buf, sizeof(buf), live_proc_reg[id].fp);
    if (!line) return make_none();
    size_t len = strlen(line);
    if (len > 0 && line[len-1] == '\n') len--;  /* strip newline */
    return make_some_ptr(march_string_lit(line, (int64_t)len));
}

/* process_write(lp, data) → () — write raw bytes to the process's stdin */
int64_t march_process_write(void *lp_obj, void *data_obj) {
    int64_t id = MARCH_FIELD(lp_obj, 1);
    if (id < 0 || id >= LIVE_PROC_MAX || !live_proc_reg[id].used || !live_proc_reg[id].write_fp)
        return 0;
    march_string *s = (march_string *)data_obj;
    fwrite(s->data, 1, (size_t)s->len, live_proc_reg[id].write_fp);
    fflush(live_proc_reg[id].write_fp);
    return 0;
}

/* process_kill_proc(lp) → () */
int64_t march_process_kill_proc(void *lp_obj) {
    int64_t pid = MARCH_FIELD(lp_obj, 0);
    kill((pid_t)pid, SIGTERM);
    return 0;
}

/* process_wait_proc(lp) → Int (exit code) */
int64_t march_process_wait_proc(void *lp_obj) {
    int64_t pid = MARCH_FIELD(lp_obj, 0);
    int64_t id  = MARCH_FIELD(lp_obj, 1);
    if (id >= 0 && id < LIVE_PROC_MAX && live_proc_reg[id].used) {
        if (live_proc_reg[id].fp)       { fclose(live_proc_reg[id].fp);       live_proc_reg[id].fp = NULL; }
        if (live_proc_reg[id].write_fp) { fclose(live_proc_reg[id].write_fp); live_proc_reg[id].write_fp = NULL; }
        live_proc_reg[id].used = 0;
    }
    int status = 0;
    waitpid((pid_t)pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
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
    /* csv_next_row's March return type is the niche-shaped ADT
       `CsvRow = CsvEof | Row(List(String))`: one nullary ctor + one
       single-field ctor, whose payload (List(String)) is heap-pointer-shaped
       and therefore niche-safe (see Repr.niche_repr_of_concrete / rc_types).
       The compiler represents this WITHOUT a wrapper box: CsvEof = NULL,
       Row(fields) = the fields-list pointer itself. A separate `march_alloc`
       wrapper here (as an earlier version of this function did) doesn't
       match that representation: the compiled match's non-null branch binds
       the scrutinee pointer directly as the payload, so a wrapper box got
       bound as `fields` instead of the actual list, and Perceus/FBIP treat
       the scrutinee as owning no allocation of its own (niche values have no
       separate header), corrupting the wrapper's memory once it's dec_rc'd. */
    return fields_list;
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

/* Called once per declared supervise-block child, from the generated
 * Name_spawn() body, right after BOTH the child and the supervisor itself
 * have been spawned (march_spawn already ran on both). Links parent->child
 * (for the crash trap to find "is this actor supervised, and by whom") and
 * records enough for a later restart: which March closure respawns this
 * child (spawn_clo — a reference to <ActorName>_spawn as a first-class
 * value, NOT a raw C function pointer; see march_sup_child's field
 * comment), and which Int-typed state-field slot of the supervisor holds
 * its encoded pid (word_idx, see march_sup_child above). spawn_clo arrives
 * with ownership transferred from the caller (the normal convention for a
 * non-borrowed argument) and is held here permanently — never decref'd —
 * so it stays valid for every future restart, exactly like a cleanup
 * closure stored on meta->cleanup_head. */
void march_actor_register_child(void *supervisor, void *child,
                                 void *spawn_clo, int64_t word_idx) {
    march_actor_meta *sup_meta = find_or_create_meta(supervisor);
    march_actor_meta *child_meta = find_or_create_meta(child);
    /* The child's green thread is already running by this point (march_spawn
     * started it before this registration call) and reads meta->supervisor
     * at its own startup under the same g_tbl_mu (see actor_green_thread) —
     * confirmed via ThreadSanitizer as an unsynchronized publish otherwise. */
    pthread_mutex_lock(&g_tbl_mu);
    child_meta->supervisor = supervisor;
    pthread_mutex_unlock(&g_tbl_mu);
    child_meta->sup_child_index = sup_meta->sup_num_children;
    int idx = sup_meta->sup_num_children;
    sup_meta->sup_children = realloc(sup_meta->sup_children,
                                      (size_t)(idx + 1) * sizeof(march_sup_child));
    sup_meta->sup_children[idx].spawn_clo = spawn_clo;
    sup_meta->sup_children[idx].word_idx = word_idx;
    sup_meta->sup_num_children = idx + 1;
}

/* pid_index_of: the Int a compiled supervisor stores in its own state field
 * to represent a just-spawned child's Pid (see march_pid_of_int for the
 * reverse direction). */
int64_t march_pid_index_of(void *actor) {
    return find_or_create_meta(actor)->pid_index;
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

/* run_until_idle: flush the async message queue.
 *
 * Compiled main() runs as a green thread inside the scheduler
 * (march_spawn_main), so the common case is the in-scheduler one: yield
 * cooperatively until no other proc is runnable and no mailbox is non-empty.
 * The old unconditional march_run_scheduler() call was a silent NO-OP here —
 * its g_in_scheduler re-entrancy guard returned immediately, so pending
 * messages were NOT drained and a following kill() raced the handlers.
 *
 * From outside the scheduler (REPL/JIT main thread with the background
 * scheduler running), fall through to march_run_scheduler, which requests
 * shutdown and joins the background thread. */
void march_run_until_idle(void) {
    if (march_sched_in_scheduler()) {
        march_sched_wait_idle();
        return;
    }
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

/* Intern an atom name to its i64 value: FNV-1a 64-bit of the (colon-less)
 * name, with bit63 forced equal to bit62 so the value survives generic-slot
 * tag round-trips.  MUST match the compiler's Llvm_ctx.atom_hash exactly —
 * runtime-produced atoms (:ok / :error from the capability plane) compare
 * equal to the same atom literals in March source only through this hash. */
static int64_t march_atom_of_name(const char *name) {
    uint64_t h = UINT64_C(14695981039346656037);
    for (const char *p = name; *p; p++) {
        h ^= (uint8_t)*p;
        h *= UINT64_C(1099511628211);
    }
    uint64_t bit62 = (h >> 62) & 1;
    h = (h & UINT64_C(0x7FFFFFFFFFFFFFFF)) | (bit62 << 63);
    return (int64_t)h;
}

/* get_cap: get the capability associated with an actor pid.
 *
 * Option(Cap) is NICHE-encoded (Cap is a heap pointer type): None = NULL,
 * Some(cap) = the cap pointer itself.  The previous stub returned a boxed
 * 16-byte tag-0 cell, which the niche decode read as Some(garbage-cap) for
 * EVERY pid, live or dead — making the whole compiled epoch-Cap plane
 * non-functional (send_checked validated that empty cell's zeroed
 * pid_index/epoch against real metas, failed, and silently dropped).
 *
 * Cap object layout (see march_send_checked below):
 *   word[0..1] = march_hdr (rc/tag, filled by march_alloc)
 *   word[2]    = actor ptr
 *   word[3]    = pid_index
 *   word[4]    = epoch
 */
void *march_get_cap(void *pid) {
    if (!pid || !IS_HEAP_PTR(pid)) return NULL;       /* no actor -> None */
    int64_t *a = (int64_t *)pid;
    if (!a[3]) return NULL;                            /* dead actor -> None */
    march_actor_meta *meta = find_or_create_meta(pid);
    if (!meta) return NULL;
    void *cap = march_alloc(40);
    int64_t *w = (int64_t *)cap;
    w[2] = (int64_t)(uintptr_t)pid;
    w[3] = meta->pid_index;
    w[4] = meta->epoch;
    return cap;
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

/* Add (pid_index, epoch) to the revocation table.  Idempotent. */
static void revoc_add(int64_t pid_index, int64_t epoch) {
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

/* revoke_cap(cap): revoke the capability.  Takes the March-level Cap object
 * (layout documented at march_get_cap) and returns the :ok atom, matching the
 * interpreter's `revoke_cap : Cap(a) -> Atom`.  A null/non-heap cap (e.g. the
 * root_cap null sentinel) is a no-op returning :error. */
int64_t march_revoke_cap(void *cap) {
    if (!cap || !IS_HEAP_PTR(cap)) return march_atom_of_name("error");
    int64_t *w = (int64_t *)cap;
    revoc_add(w[3], w[4]);
    return march_atom_of_name("ok");
}

/* is_cap_valid(cap): return 1 if the capability is valid, 0 otherwise.
 * A capability is invalid if it is in the revocation table, the actor is dead,
 * or the actor's current epoch differs.  Takes the March-level Cap object,
 * matching the interpreter's `is_cap_valid : Cap(a) -> Bool`. */
int64_t march_is_cap_valid(void *cap) {
    if (!cap || !IS_HEAP_PTR(cap)) return 0;
    int64_t *w = (int64_t *)cap;
    int64_t pid_index = w[3];
    int64_t epoch     = w[4];
    if (revoc_contains(pid_index, epoch)) return 0;
    march_actor_meta *m = find_meta_by_pid_index(pid_index);
    if (!m || !march_is_alive(m->actor)) return 0;
    if (m->epoch != epoch) return 0;
    return 1;
}

/* send_checked: send a message to an actor with capability check.
 * Validates liveness, epoch match, and revocation before enqueuing.
 *
 * Cap object layout (compiled VCap heap object):
 *   word[0] = rc (int64)
 *   word[1] = tag/pad (int64)
 *   word[2] = actor ptr (stored as int64, reinterpret as void*)
 *   word[3] = pid_index (int64)
 *   word[4] = epoch (int64)
 *
 * If cap is not a heap pointer (e.g. None/null), silently drop the message.
 */
int64_t march_send_checked(void *cap, void *msg) {
    /* Returns the :ok atom on delivery, :error on any validation failure —
     * matching the interpreter's `send_checked : Cap(a) -> a -> Atom`
     * (previously returned void; the call site then read garbage as the
     * atom, so the result compared equal to neither :ok nor :error). */
    if (!cap || !IS_HEAP_PTR(cap)) {
        march_decrc(msg);
        return march_atom_of_name("error");
    }
    int64_t *cap_words = (int64_t *)cap;
    void    *actor     = (void *)(uintptr_t)cap_words[2];
    int64_t  pidx      = cap_words[3];
    int64_t  epoch     = cap_words[4];
    if (revoc_contains(pidx, epoch)) {
        march_decrc(msg);
        return march_atom_of_name("error");
    }
    march_actor_meta *meta = find_meta(actor);
    if (!meta || meta->pid_index != pidx || meta->epoch != epoch
        || !march_is_alive(actor)) {
        march_decrc(msg);
        return march_atom_of_name("error");
    }
    void *result = march_send(actor, msg);
    march_decrc(result);
    return march_atom_of_name("ok");
}

/* march_pid_of_int(n) is an escape hatch: March code that stores a child's
 * pid as a plain Int (e.g. a supervisor's Int-typed state field, see Task 3)
 * converts it back to a usable Pid via this call. When n does not name any
 * actor this process has spawned (a stale/garbage index), march_send /
 * march_kill / march_is_alive all read their `actor` argument's $e_alive
 * flag (word index 3) UNCONDITIONALLY with no NULL check — returning NULL
 * here would crash every one of them. Instead return a pointer to a static,
 * already-"dead" actor struct: same header/dispatch/alive word layout as a
 * real actor, with $e_alive already 0, so every caller's EXISTING
 * "actor already dead" early-return path (march_kill's `if (!fields[3])
 * return;`, march_send's `if (!a[3]) { ...none...; return; }`,
 * march_is_alive's plain read) handles it exactly like any other actor
 * that was already killed — no new code path, nothing to get wrong.
 * rc starts at a billion: no realistic amount of incrc/decrc traffic on a
 * Pid value approaches that within one process's lifetime, so this static
 * object is never freed. */
static struct { march_hdr hdr; int64_t dispatch; int64_t alive; }
    march_dead_actor_sentinel = { .hdr = { .rc = 1000000000, .tag = 0, .pad = 0 },
                                   .dispatch = 0, .alive = 0 };

void *march_pid_of_int(int64_t n) {
    march_actor_meta *m = find_meta_by_pid_index(n);
    if (m) return m->actor;
    return &march_dead_actor_sentinel;
}

/* ── Value pretty-printing ───────────────────────────────────────────── */

/* Format a March value as a human-readable string.
   Handles tagged immediates (low bit == 1), actor Pids, and heap objects. */
void *march_value_to_string(void *v) {
    if (!v) return march_string_lit("nil", 3);
    /* Tagged immediate: low bit == 1 → extract integer value via arithmetic
     * right-shift of the raw pointer bits (sign-preserving). */
    if (((uintptr_t)v & 1u) != 0) {
        int64_t n = (intptr_t)v >> 1;
        return march_int_to_string(n);
    }
    /* Check if this pointer is a registered actor → display as Pid(n) */
    march_actor_meta *meta = find_meta(v);
    if (meta) {
        char buf[64];
        int n = snprintf(buf, sizeof(buf), "Pid(%lld)", (long long)meta->pid_index);
        return march_string_lit(buf, n);
    }
    march_hdr *h = (march_hdr *)v;
    int32_t tag = h->tag;
    /* String heap cell: every march_string carries MARCH_STRING_TAG at the
     * tag word, so to_string on a value whose static type erased to a TVar but
     * actually holds a string returns the string verbatim (identity), matching
     * the interpreter — instead of misreading the layout (len-as-tag) and
     * printing "#<tag:len>".  Result is +1: alias the borrowed input. */
    if (tag == MARCH_STRING_TAG) { march_incrc(v); return v; }
    /* Boxed float in an erased slot: render the value, not "#<tag:-3>"
     * (float-boxing design; also closes a cousin of the to_string-on-erased
     * divergence). */
    if (tag == MARCH_FLOAT_TAG) return march_float_to_string(march_unbox_float(v));
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
 * Each element slot is 8 bytes — can hold i64, double (bitcast), or ptr.
 *
 * SAFETY INVARIANTS (maintained by all functions below):
 *   1. All index arguments must satisfy 0 <= i < len (checked at entry).
 *   2. len*8 must not overflow int64_t (checked in typed_array_alloc).
 *   3. Closure arguments to map/filter/fold must be non-NULL; callers are
 *      responsible for passing a valid March closure object.
 *
 * Closure layout assumed by map/filter/fold:
 *   offset  0: i64  rc / tag word
 *   offset  8: ptr  function pointer (called as fn(closure, arg, ...))
 *   offset 16+: captured environment fields
 * The compiler always emits closures with this layout via lower.ml. */
#define TYPED_ARRAY_HDR_SIZE (16 + 8 + 8)  /* hdr + len + cap */

static void *typed_array_alloc(int64_t len) {
    /* Bug fix: len * 8 can overflow int64_t for len > INT64_MAX/8, producing a
     * tiny allocation whose writes later corrupt adjacent heap objects. */
    int64_t body;
    if (__builtin_mul_overflow(len, (int64_t)8, &body)) {
        fputs("march: runtime error: array too large (allocation overflow)\n", stderr); exit(1);
    }
    size_t sz = (size_t)(TYPED_ARRAY_HDR_SIZE + body);
    void *arr = march_alloc((int64_t)sz);
    *(int64_t *)((char *)arr + 16) = len;   /* len field */
    *(int64_t *)((char *)arr + 24) = len;   /* cap field */
    return arr;
}

/* Index bounds check shared by get/set.  Aborts with a clear message rather
 * than silently reading or writing adjacent heap memory. */
static void typed_array_check_bounds(int64_t i, int64_t len) {
    if (i < 0 || i >= len) {
        fprintf(stderr,
            "march: runtime error: array index out of bounds (index %lld, length %lld)\n",
            (long long)i, (long long)len);
        exit(1);
    }
}

/* Dispatch a 1-argument closure stored in a March closure object.
 * Layout: fn ptr at byte offset +16 of the closure (field[0]; see
 * march_hdr's 16-byte header ahead of the closure's own fields — the same
 * offset clo_apply_ptr below uses); closure is passed as the first argument
 * so the function can access its captured environment. */
static inline void *call_closure_1(void *clo, void *arg) {
    void *(*fn)(void*, void*) = *(void *(**)(void*, void*))((char *)clo + 16);
    return fn(clo, arg);
}

static inline int64_t call_closure_1_int(void *clo, void *arg) {
    int64_t (*fn)(void*, void*) = *(int64_t (**)(void*, void*))((char *)clo + 16);
    return fn(clo, arg);
}

static inline void *call_closure_2(void *clo, void *a, void *b) {
    void *(*fn)(void*, void*, void*) = *(void *(**)(void*, void*, void*))((char *)clo + 16);
    return fn(clo, a, b);
}

/* ── Signal.watch: deferred signal dispatch (compiled runtime) ──────────
 * One watcher closure per stable signal code 0-4 (Term Int Hup Usr1 Usr2 —
 * see stdlib/signal.march, which translates the `Sig` enum to these codes and
 * wraps the handler in a 1-arg discard thunk, so the watcher is a standard
 * 1-arg closure invoked via call_closure_1 with a dummy argument).
 *
 * The OS handler `march_signal_dispatch` runs in async-signal context and does
 * ONLY atomic flag stores — no allocation, no March code.  A drain point in
 * the scheduler / HTTP loops calls `march_signal_drain`, which runs the March
 * closure inline on a normal stack (never a guard-paged green-thread stack:
 * we install plain handlers, mirroring http_signal_handler, and the drain runs
 * from the loop body, not the signal handler).
 *
 * Code 3 (Usr1) is RESERVED for the scheduler's green-thread preemption
 * (SIGUSR1, march_scheduler.c) and therefore cannot be watched in compiled
 * programs — march_signal_watch refuses it.  Term/Int (0/1) suppress the
 * default graceful shutdown on the first delivery while watched, and escape to
 * shutdown (g_http_shutdown) on the second. */
static void *_Atomic g_signal_handlers[5] = { NULL, NULL, NULL, NULL, NULL };
static _Atomic int   g_signal_pending[5]  = { 0, 0, 0, 0, 0 };
static _Atomic int   g_signal_seen[5]     = { 0, 0, 0, 0, 0 };

/* Graceful-shutdown flag.  The strong definition lives in march_http.c; this
 * WEAK definition provides the symbol for the REPL/JIT runtime-only build, where
 * march_http.c is absent (the JIT compiles march_runtime.c standalone, and the
 * signal dispatcher below references this flag).  When both TUs are linked (the
 * normal full build), march_http.c's strong definition overrides this one — no
 * duplicate symbol.  Set by the unwatched Term/Int path and by the
 * watched-signal second-delivery escape hatch. */
__attribute__((weak)) _Atomic int g_http_shutdown = 0;

static int march_signal_os_of_code(int code) {
    switch (code) {
        case 0: return SIGTERM; case 1: return SIGINT; case 2: return SIGHUP;
        case 3: return SIGUSR1; case 4: return SIGUSR2; default: return -1;
    }
}
static int march_signal_code_of_os(int sig) {
    switch (sig) {
        case SIGTERM: return 0; case SIGINT: return 1; case SIGHUP: return 2;
        case SIGUSR1: return 3; case SIGUSR2: return 4; default: return -1;
    }
}

/* Async-signal-safe: only atomic stores; no alloc, no March code. */
static void march_signal_dispatch(int sig) {
    int code = march_signal_code_of_os(sig);
    if (code < 0) return;
    if (atomic_load_explicit(&g_signal_handlers[code], memory_order_acquire)) {
        /* Watched: defer to the drain.  Term/Int escape to graceful shutdown
         * only on a second delivery (the Ctrl-C-twice escape hatch). */
        if ((code == 0 || code == 1)
                && atomic_load_explicit(&g_signal_seen[code], memory_order_relaxed))
            atomic_store_explicit(&g_http_shutdown, 1, memory_order_relaxed);
        atomic_store_explicit(&g_signal_pending[code], 1, memory_order_relaxed);
        atomic_store_explicit(&g_signal_seen[code], 1, memory_order_relaxed);
    } else if (code == 0 || code == 1) {
        /* Unwatched Term/Int → graceful shutdown (matches http_signal_handler). */
        atomic_store_explicit(&g_http_shutdown, 1, memory_order_relaxed);
    }
}

/* Run all pending watchers on the current (normal) stack.  Called from the
 * scheduler loop and the HTTP event loops — NEVER from signal context.  The
 * atomic exchange coalesces repeated pre-drain deliveries into one call. */
void march_signal_drain(void) {
    for (int code = 0; code < 5; code++) {
        if (atomic_exchange_explicit(&g_signal_pending[code], 0,
                                     memory_order_acq_rel)) {
            void *clo = atomic_load_explicit(&g_signal_handlers[code],
                                             memory_order_acquire);
            if (clo) {
                /* March closure ABI (see march_thunk_trampoline): the apply fn
                 * ptr lives at byte offset +16 and takes (closure, int64 arg).
                 * The watcher is a 1-arg discard thunk, so the arg is a dummy.
                 * Calling does not consume the closure — the watcher stays
                 * registered for the next delivery.
                 *
                 * RC contract: this is DIFFERENT from the map/fold builtins'
                 * transfer-once-consume-once contract (native_int_arr_map et
                 * al.) — [clo] is a LONG-LIVED reference held in
                 * g_signal_handlers, called an unbounded number of times
                 * (once per delivery, across the program's whole lifetime),
                 * and released only by march_signal_watch's replace/unwatch
                 * decrc, never here. But since insert_apply_fn_clo_drop
                 * (lib/tir/perceus.ml) makes a CAPTURING watcher's apply
                 * function release its $clo reference on every call, this
                 * call would free the closure on the FIRST delivery and the
                 * table would hold a dangling pointer for the second —
                 * reproduced with a watcher closing over a captured value,
                 * raised twice: clean SIGSEGV on delivery 2, every run.
                 * march_incrc balances that per-call drop, leaving the
                 * table's one held reference untouched no matter how many
                 * times this fires. */
                typedef void *(*apply_fn_t)(void *, int64_t);
                apply_fn_t apply = *(apply_fn_t *)((char *)clo + 16);
                march_incrc(clo);
                apply(clo, (int64_t)0);
            }
        }
    }
}

/* Register a watcher.  The closure is passed OWNED (Perceus: the borrow pass
 * marks this call site as consuming), so we keep its reference in the table
 * and release it on replace / unwatch. */
void march_signal_watch(int64_t code, void *clo) {
    if (code < 0 || code > 4) { if (clo) march_decrc(clo); return; }
    if (code == 3) {
        fprintf(stderr,
            "march: Signal.watch(Usr1) is unsupported in compiled programs — "
            "SIGUSR1 is reserved for the scheduler's green-thread preemption; "
            "the watcher is ignored.\n");
        if (clo) march_decrc(clo);
        return;
    }
    void *old = atomic_exchange_explicit(&g_signal_handlers[code], clo,
                                         memory_order_acq_rel);
    if (old) march_decrc(old);
    atomic_store_explicit(&g_signal_seen[code], 0, memory_order_relaxed);
    atomic_store_explicit(&g_signal_pending[code], 0, memory_order_relaxed);
    /* Install a plain handler (no SA_ONSTACK), mirroring http_signal_handler;
     * overrides any prior Term/Int shutdown handler with the watcher-aware one. */
    signal(march_signal_os_of_code((int)code), march_signal_dispatch);
}

/* Remove a watcher, restoring the signal's default disposition. */
void march_signal_unwatch(int64_t code) {
    if (code < 0 || code > 4 || code == 3) return;
    void *old = atomic_exchange_explicit(&g_signal_handlers[code], NULL,
                                         memory_order_acq_rel);
    if (old) march_decrc(old);
    atomic_store_explicit(&g_signal_pending[code], 0, memory_order_relaxed);
    atomic_store_explicit(&g_signal_seen[code], 0, memory_order_relaxed);
    signal(march_signal_os_of_code((int)code), SIG_DFL);
}

/* Send a signal to our own process (Signal.raise) — the symmetric trigger,
 * useful for self-scheduled work and for testing watchers. */
void march_signal_raise_self(int64_t code) {
    int os = march_signal_os_of_code((int)code);
    if (os >= 0) kill(getpid(), os);
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
    int64_t len = march_typed_array_length(arr);
    typed_array_check_bounds(i, len);
    return *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8);
}

void *march_typed_array_set(void *arr, int64_t i, void *val) {
    int64_t len = march_typed_array_length(arr);
    typed_array_check_bounds(i, len);
    void *new_arr = typed_array_alloc(len);
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

/* RC contract: [f] arrives as ONE transferred (owned) reference — Perceus
 * inserts an EIncRC at the March call site iff the caller still needs [f]
 * afterward (confirmed via TIR: `inc_rc closure; NativeArray.map_int(a1,
 * closure)` when `closure` is called again later), meaning a last-use call
 * site transfers its only reference here with no extra protection.
 *
 * But [f]'s apply function is called ONCE PER ELEMENT here, and — since
 * lib/tir/perceus.ml's insert_apply_fn_clo_drop — a CAPTURING closure's
 * apply function releases $clo internally on every single call.  Without
 * the march_incrc below, element 0's call already frees [f] (if the
 * caller's reference was the only one) and every subsequent element calls
 * through freed memory: SIGABRT/SIGTRAP, reproduced by
 * test/native/native_arr_map_inline_capture.march.  march_incrc(f) before
 * each call balances that call's internal drop, and the final
 * march_decrc(f) releases the one reference this function was transferred
 * — net effect over the whole loop is identical to the pre-drop behaviour,
 * where calling never touched f's rc at all. */
void *march_typed_array_map(void *arr, void *f) {
    int64_t len = march_typed_array_length(arr);
    void *new_arr = typed_array_alloc(len);
    for (int64_t i = 0; i < len; i++) {
        void *elem = *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8);
        march_incrc(f);
        void *result = call_closure_1(f, elem);
        *(void **)((char *)new_arr + TYPED_ARRAY_HDR_SIZE + i * 8) = result;
    }
    march_decrc(f);
    return new_arr;
}

/* typed_array_filter(arr, mask): keep elements of arr where the parallel
 * TypedArray(Bool) mask is true.  Bool elements are tagged scalars:
 * true=(1<<1)|1=3, false=(0<<1)|1=1; raw >> 1 gives the actual boolean. */
void *march_typed_array_filter(void *arr, void *mask) {
    int64_t len  = march_typed_array_length(arr);
    int64_t mlen = march_typed_array_length(mask);
    if (len != mlen) {
        fprintf(stderr,
            "march: typed_array_filter: array length %lld != mask length %lld\n",
            (long long)len, (long long)mlen); exit(1);
    }
    int64_t body;
    if (__builtin_mul_overflow(len, (int64_t)8, &body)) {
        fputs("march: runtime error: array too large (filter overflow)\n", stderr); exit(1);
    }
    void **temp = malloc((size_t)body);
    if (!temp && len > 0) { fputs("march: out of memory\n", stderr); exit(1); }
    int64_t count = 0;
    for (int64_t i = 0; i < len; i++) {
        int64_t raw_bool = *(int64_t *)((char *)mask + TYPED_ARRAY_HDR_SIZE + i * 8);
        if (raw_bool >> 1)
            temp[count++] = *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8);
    }
    void *new_arr = typed_array_alloc(count);
    memcpy((char *)new_arr + TYPED_ARRAY_HDR_SIZE, temp, (size_t)(count * 8));
    free(temp);
    return new_arr;
}

/* RC contract identical to march_typed_array_map above: [f] is one
 * transferred reference, called once per element, march_incrc before each
 * call balances that call's internal $clo drop, final march_decrc releases
 * the transferred reference. */
void *march_typed_array_fold(void *arr, void *acc, void *f) {
    int64_t len = march_typed_array_length(arr);
    void *result = acc;
    for (int64_t i = 0; i < len; i++) {
        void *elem = *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8);
        march_incrc(f);
        result = call_closure_2(f, result, elem);
    }
    march_decrc(f);
    return result;
}

/* ── Native int/float arrays ────────────────────────────────────────── */
/* Layout: march_hdr(16) + int64_t len(8) + elements(len*8)             */
#define NATIVE_ARR_HDR 24

static void *native_arr_alloc(int64_t len) {
    if (len < 0) { fputs("march: native array: negative length\n", stderr); exit(1); }
    int64_t body;
    if (__builtin_mul_overflow(len, (int64_t)8, &body)) {
        fputs("march: native array: array too large\n", stderr); exit(1);
    }
    void *arr = march_alloc(NATIVE_ARR_HDR + body);
    *(int64_t *)((char *)arr + 16) = len;
    return arr;
}

/* Closure calling helpers (fn_ptr at field[0] = offset 16 from object).
 *
 * All March closures — including a bare `fn x -> ...` lambda — present the
 * uniform erased-ptr ABI documented at llvm_calls.ml's clo_wrap_define /
 * is_apply_fn: the fn pointer takes/returns `ptr`, with scalars (Int/Bool)
 * wire-tagged `(n<<1)|1` and Float args/returns boxed via
 * march_alloc_float/march_unbox_float. There is no native-typed variant to
 * call into — a closure is never compiled with a `double(void*,double)` or
 * raw `int64_t(void*,int64_t)` signature.
 *
 * Reinterpreting the fn pointer as such a native signature (the previous
 * implementation here) happened to limp along for ints, because a raw
 * untagged int64 and a tagged wire value both occupy one GPR-width slot at
 * the C ABI level — silently wrong for odd inputs/outputs, since the callee
 * unconditionally treats the low bit as the tag. For doubles it is not even
 * register-compatible: floats pass in FP/vector registers while the wire
 * ABI expects a boxed pointer in a GPR, so the argument and return value are
 * both total garbage — this is what crashed native_float_arr_map. */
static inline void *clo_apply_ptr(void *clo, void *arg) {
    void *(*fn)(void*, void*) = *(void *(**)(void*, void*))((char *)clo + 16);
    return fn(clo, arg);
}
static inline int64_t clo_call_int_int(void *clo, int64_t x) {
    void *wire_arg = (void *)(intptr_t)((x << 1) | 1);
    void *wire_ret = clo_apply_ptr(clo, wire_arg);
    return (int64_t)(intptr_t)wire_ret >> 1;
}
static inline double clo_call_dbl_dbl(void *clo, double x) {
    void *wire_ret = clo_apply_ptr(clo, march_alloc_float(x));
    return march_unbox_float(wire_ret);
}

/* Two-argument variants for native_{int,float}_arr_map2 (a genuine 2-param
 * March lambda, e.g. `fn (a, b) -> a + b`, compiles to a 3-param apply fn:
 * ($clo, a, b) -- confirmed via -emit-llvm, not a tuple-destructured
 * single param). Same wire-tagged/boxed ABI as the 1-arg helpers above. */
static inline void *clo_apply_ptr2(void *clo, void *arg1, void *arg2) {
    void *(*fn)(void*, void*, void*) = *(void *(**)(void*, void*, void*))((char *)clo + 16);
    return fn(clo, arg1, arg2);
}
static inline int64_t clo_call_int_int_int(void *clo, int64_t x, int64_t y) {
    void *wire_x = (void *)(intptr_t)((x << 1) | 1);
    void *wire_y = (void *)(intptr_t)((y << 1) | 1);
    void *wire_ret = clo_apply_ptr2(clo, wire_x, wire_y);
    return (int64_t)(intptr_t)wire_ret >> 1;
}
static inline double clo_call_dbl_dbl_dbl(void *clo, double x, double y) {
    void *wire_ret = clo_apply_ptr2(clo, march_alloc_float(x), march_alloc_float(y));
    return march_unbox_float(wire_ret);
}

/* Uninitialized allocation for llvm_emit's inline map loop (native_map_inline.ml):
 * every slot is written by the loop before any read, so leaving them
 * uninitialized (unlike native_int_arr_make/native_float_arr_make, which
 * fill with a default) is safe and avoids a redundant full pass. */
void *native_int_arr_alloc_raw(int64_t len) { return native_arr_alloc(len); }
void *native_float_arr_alloc_raw(int64_t len) { return native_arr_alloc(len); }

void *native_int_arr_make(int64_t len, int64_t def) {
    void *arr = native_arr_alloc(len);
    for (int64_t i = 0; i < len; i++)
        *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8) = def;
    return arr;
}

int64_t native_int_arr_length(void *arr) {
    return *(int64_t *)((char *)arr + 16);
}

int64_t native_int_arr_get(void *arr, int64_t i) {
    return *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
}

/* FBIP in-place update at unique ownership.
 *
 * [arr] is passed under the owned/consumed convention — native_int_arr_set is
 * absent from borrow.ml's extern_borrow_table, so Perceus transfers one
 * reference into this call and emits no dec_rc after it. This function
 * therefore owns exactly one reference to [arr] and is responsible for
 * releasing it.
 *
 * When that reference is the ONLY one (rc == 1, the same unique-ownership
 * predicate LLVM-generated FBIP `reuse … as …` uses, which also reads ->rc as
 * a plain non-atomic load — safe precisely because a unique owner has no
 * concurrent observer), we mutate the backing array in place and hand our
 * reference straight to the result: O(1), no allocation, no copy, no free.
 * That is what keeps a threaded-forward set_int accumulator flat in RSS
 * instead of leaking (or churning) a fresh 8-element copy on every call.
 *
 * When the array is SHARED (rc > 1) an alias may still observe it, so
 * copy-on-write MUST be preserved: allocate a fresh array, copy, write the new
 * value, then release our owned reference (march_decrc drops our count; the
 * alias keeps its own). The rc == 1 gate also excludes interned/immortal
 * arrays (rc >= MARCH_RC_IMMORTAL), which are never mutated in place. */
void *native_int_arr_set(void *arr, int64_t i, int64_t val) {
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8) = val;
        return arr;
    }
    int64_t len = native_int_arr_length(arr);
    void *new_arr = native_arr_alloc(len);
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR, (size_t)(len * 8));
    *(int64_t *)((char *)new_arr + NATIVE_ARR_HDR + i * 8) = val;
    march_decrc(arr);
    return new_arr;
}

int64_t native_int_arr_sum(void *arr) {
    int64_t len = native_int_arr_length(arr), s = 0;
    for (int64_t i = 0; i < len; i++)
        s += *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
    return s;
}

/* Caller (DataFrame.col_native_min_max) guarantees len >= 1; empty arrays
 * never reach this loop. */
int64_t native_int_arr_min(void *arr) {
    int64_t len = native_int_arr_length(arr);
    int64_t m = *(int64_t *)((char *)arr + NATIVE_ARR_HDR);
    for (int64_t i = 1; i < len; i++) {
        int64_t v = *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
        if (v < m) m = v;
    }
    return m;
}

int64_t native_int_arr_max(void *arr) {
    int64_t len = native_int_arr_length(arr);
    int64_t m = *(int64_t *)((char *)arr + NATIVE_ARR_HDR);
    for (int64_t i = 1; i < len; i++) {
        int64_t v = *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
        if (v > m) m = v;
    }
    return m;
}

/* Sum of squared deviations from a precomputed mean — the stable second pass
 * of the standard two-pass variance algorithm. int elements promote to
 * double for the deviation. */
double native_int_arr_sumsq_dev(void *arr, double mean) {
    int64_t len = native_int_arr_length(arr);
    double s = 0.0;
    for (int64_t i = 0; i < len; i++) {
        double v = (double)(*(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8));
        double d = v - mean;
        s += d * d;
    }
    return s;
}

/* RC contract: see march_typed_array_map's doc comment — [f] is one
 * transferred reference, march_incrc before each per-element call balances
 * that call's internal $clo drop (insert_apply_fn_clo_drop,
 * lib/tir/perceus.ml), final march_decrc releases the transferred
 * reference. Without this, a capturing closure map callback frees itself on
 * the first element and every later element calls through freed memory —
 * reproduced by test/native/native_arr_map_inline_capture.march. */
void *native_int_arr_map(void *arr, void *f) {
    int64_t len = native_int_arr_length(arr);
    void *new_arr = native_arr_alloc(len);
    for (int64_t i = 0; i < len; i++) {
        int64_t x = *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
        march_incrc(f);
        *(int64_t *)((char *)new_arr + NATIVE_ARR_HDR + i * 8) = clo_call_int_int(f, x);
    }
    march_decrc(f);
    return new_arr;
}

/* Elementwise binary op over two same-length int arrays -- the two-array
 * counterpart to native_int_arr_map, for DataFrame.col_add_col-shaped
 * column-column arithmetic. Caller (stdlib) checks the length match; a
 * mismatch here is a genuine caller bug (both callers already validate),
 * so it's an assert rather than a Result -- matching native_int_arr_min/max's
 * "caller guarantees" convention above, not a new error-handling contract. */
/* RC contract identical to native_int_arr_map above. */
void *native_int_arr_map2(void *arr1, void *arr2, void *f) {
    int64_t len = native_int_arr_length(arr1);
    if (len != native_int_arr_length(arr2)) {
        fputs("march: native_int_arr_map2: array length mismatch\n", stderr); exit(1);
    }
    void *new_arr = native_arr_alloc(len);
    for (int64_t i = 0; i < len; i++) {
        int64_t x = *(int64_t *)((char *)arr1 + NATIVE_ARR_HDR + i * 8);
        int64_t y = *(int64_t *)((char *)arr2 + NATIVE_ARR_HDR + i * 8);
        march_incrc(f);
        *(int64_t *)((char *)new_arr + NATIVE_ARR_HDR + i * 8) = clo_call_int_int_int(f, x, y);
    }
    march_decrc(f);
    return new_arr;
}

/* Length-mismatch panic shared by the compiled map2 INLINE loop
 * (lib/tir/native_map_inline.ml / llvm_emit.ml's emit_native_map2_inline_loop).
 * That loop bypasses native_int_arr_map2/native_float_arr_map2 entirely
 * (calls the lifted apply fn directly instead of going through this file),
 * so it needs its own length check to preserve the "panics on length
 * mismatch" contract documented on NativeArray.map2_int/map2_float. */
void native_arr_map2_check_len(int64_t len1, int64_t len2) {
    if (len1 != len2) {
        fputs("march: native_arr_map2: array length mismatch\n", stderr); exit(1);
    }
}

/* Widen an int array to float, elementwise -- used by col_add_col's mixed
 * Int/Float branches to bring both sides to Float before native_float_arr_map2,
 * instead of round-tripping through List(Value). Pure conversion, no
 * closure -- should auto-vectorize (int64->double SIMD convert) same as
 * native_int_arr_sum already does for the reduction case. */
void *native_int_arr_to_float_arr(void *arr) {
    int64_t len = native_int_arr_length(arr);
    void *new_arr = native_arr_alloc(len);
    for (int64_t i = 0; i < len; i++) {
        int64_t x = *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
        double d = (double)x;
        memcpy((char *)new_arr + NATIVE_ARR_HDR + i * 8, &d, 8);
    }
    return new_arr;
}

void *native_int_arr_from_list(void *lst) {
    int64_t n = 0;
    void *tmp = lst;
    while (*(int32_t *)((char *)tmp + 8) == 1) { n++; tmp = *(void **)((char *)tmp + 24); }
    void *arr = native_arr_alloc(n);
    void *cur = lst;
    for (int64_t i = 0; i < n; i++) {
        /* List Cons cells store Int elements as tagged ptrs: (n<<1)|1. Untag. */
        int64_t raw = *(int64_t *)((char *)cur + 16);
        *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8) = (raw & 1) ? (raw >> 1) : raw;
        cur = *(void **)((char *)cur + 24);
    }
    return arr;
}

void *native_int_arr_to_list(void *arr) {
    int64_t len = native_int_arr_length(arr);
    void *lst = make_nil();
    for (int64_t i = len - 1; i >= 0; i--) {
        int64_t v = *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
        void *cons = march_alloc(32);
        *(int32_t *)((char *)cons + 8) = 1;
        /* Tag as (n<<1)|1 so pattern-match untagging on the March side recovers v. */
        *(int64_t *)((char *)cons + 16) = (v << 1) | 1;
        *(void **)((char *)cons + 24) = lst;
        lst = cons;
    }
    return lst;
}

void *native_float_arr_make(int64_t len, double def) {
    void *arr = native_arr_alloc(len);
    for (int64_t i = 0; i < len; i++)
        memcpy((char *)arr + NATIVE_ARR_HDR + i * 8, &def, 8);
    return arr;
}

int64_t native_float_arr_length(void *arr) {
    return *(int64_t *)((char *)arr + 16);
}

double native_float_arr_get(void *arr, int64_t i) {
    double v; memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8); return v;
}

/* In-place-at-rc==1 FBIP update — see native_int_arr_set above for the full
 * ownership contract (identical: owned/consumed arg, unique-owner mutates in
 * place, shared array copies-on-write then releases our reference). */
void *native_float_arr_set(void *arr, int64_t i, double val) {
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        memcpy((char *)arr + NATIVE_ARR_HDR + i * 8, &val, 8);
        return arr;
    }
    int64_t len = native_float_arr_length(arr);
    void *new_arr = native_arr_alloc(len);
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR, (size_t)(len * 8));
    memcpy((char *)new_arr + NATIVE_ARR_HDR + i * 8, &val, 8);
    march_decrc(arr);
    return new_arr;
}

double native_float_arr_sum(void *arr) {
    int64_t len = native_float_arr_length(arr);
    double s = 0.0;
    /* Strict IEEE 754 forbids the compiler from reassociating float adds, which
     * blocks auto-vectorization of this reduction (LLVM emits vector loads but
     * scalar fadds). Scope reassociation to just this loop -- not a blanket
     * -ffast-math -- so it vectorizes to packed NEON/SSE fadds; the multi-lane
     * (effectively pairwise) summation order this produces changes rounding in
     * the last bit vs. strict left-to-right but is no less accurate. */
    {
#pragma clang fp reassociate(on)
        for (int64_t i = 0; i < len; i++) { double v; memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8); s += v; }
    }
    return s;
}

/* Caller (DataFrame.col_native_min_max) guarantees len >= 1; empty arrays
 * never reach this loop. */
double native_float_arr_min(void *arr) {
    int64_t len = native_float_arr_length(arr);
    double m; memcpy(&m, (char *)arr + NATIVE_ARR_HDR, 8);
    for (int64_t i = 1; i < len; i++) {
        double v; memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8);
        if (v < m) m = v;
    }
    return m;
}

double native_float_arr_max(void *arr) {
    int64_t len = native_float_arr_length(arr);
    double m; memcpy(&m, (char *)arr + NATIVE_ARR_HDR, 8);
    for (int64_t i = 1; i < len; i++) {
        double v; memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8);
        if (v > m) m = v;
    }
    return m;
}

/* Sum of squared deviations from a precomputed mean — the stable second pass
 * of the standard two-pass variance algorithm. */
double native_float_arr_sumsq_dev(void *arr, double mean) {
    int64_t len = native_float_arr_length(arr);
    double s = 0.0;
    for (int64_t i = 0; i < len; i++) {
        double v; memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8);
        double d = v - mean;
        s += d * d;
    }
    return s;
}

/* RC contract identical to native_int_arr_map above. */
void *native_float_arr_map(void *arr, void *f) {
    int64_t len = native_float_arr_length(arr);
    void *new_arr = native_arr_alloc(len);
    for (int64_t i = 0; i < len; i++) {
        double x; memcpy(&x, (char *)arr + NATIVE_ARR_HDR + i * 8, 8);
        march_incrc(f);
        double r = clo_call_dbl_dbl(f, x);
        memcpy((char *)new_arr + NATIVE_ARR_HDR + i * 8, &r, 8);
    }
    march_decrc(f);
    return new_arr;
}

/* Elementwise binary op over two same-length float arrays -- see
 * native_int_arr_map2's doc comment (same two-array shape, Float instead
 * of Int). Both sides must already be Float; col_add_col's mixed-type
 * cases widen the Int side via native_int_arr_to_float_arr first. */
/* RC contract identical to native_int_arr_map above. */
void *native_float_arr_map2(void *arr1, void *arr2, void *f) {
    int64_t len = native_float_arr_length(arr1);
    if (len != native_float_arr_length(arr2)) {
        fputs("march: native_float_arr_map2: array length mismatch\n", stderr); exit(1);
    }
    void *new_arr = native_arr_alloc(len);
    for (int64_t i = 0; i < len; i++) {
        double x, y;
        memcpy(&x, (char *)arr1 + NATIVE_ARR_HDR + i * 8, 8);
        memcpy(&y, (char *)arr2 + NATIVE_ARR_HDR + i * 8, 8);
        march_incrc(f);
        double r = clo_call_dbl_dbl_dbl(f, x, y);
        memcpy((char *)new_arr + NATIVE_ARR_HDR + i * 8, &r, 8);
    }
    march_decrc(f);
    return new_arr;
}

void *native_float_arr_from_list(void *lst) {
    int64_t n = 0;
    void *tmp = lst;
    while (*(int32_t *)((char *)tmp + 8) == 1) { n++; tmp = *(void **)((char *)tmp + 24); }
    void *arr = native_arr_alloc(n);
    void *cur = lst;
    for (int64_t i = 0; i < n; i++) {
        /* List(Float) elements are BOXED (see native_float_arr_to_list): the
         * Cons element slot holds a march_alloc_float pointer, so unbox it
         * rather than reading the slot as a raw double. */
        void *boxed = *(void **)((char *)cur + 16);
        double v = march_unbox_float(boxed);
        memcpy((char *)arr + NATIVE_ARR_HDR + i * 8, &v, 8);
        cur = *(void **)((char *)cur + 24);
    }
    return arr;
}

void *native_float_arr_to_list(void *arr) {
    int64_t len = native_float_arr_length(arr);
    void *lst = make_nil();
    for (int64_t i = len - 1; i >= 0; i--) {
        /* List(Float) elements are BOXED in compiled code — the Cons element
         * slot (offset 16) is a uniform pointer-width word, and a raw IEEE-754
         * double stored there would later be dereferenced by march_unbox_float
         * as a heap-float pointer (SIGSEGV at the float's bit pattern + 16).
         * Box each element with march_alloc_float so the produced list matches
         * the compiler's representation. Mirrors native_int_arr_to_list's
         * tagged-immediate storage — floats can't be tagged, so they box. */
        double v;
        memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8);
        void *boxed = march_alloc_float(v);
        void *cons = march_alloc(32);
        *(int32_t *)((char *)cons + 8) = 1;
        *(void **)((char *)cons + 16) = boxed;
        *(void **)((char *)cons + 24) = lst;
        lst = cons;
    }
    return lst;
}

/* native_int_arr_filter_mask / native_float_arr_filter_mask:
 * Keep elements where the parallel TypedArray(Bool) mask is true.
 * TypedArray Bool elements are tagged scalars: true=(1<<1)|1=3, false=(0<<1)|1=1.
 * Raw >> 1 gives the actual boolean (1 for true, 0 for false). */
void *native_int_arr_filter_mask(void *arr, void *mask) {
    int64_t len = *(int64_t *)((char *)arr  + 16);
    int64_t mlen = *(int64_t *)((char *)mask + 16);
    if (len != mlen) {
        fprintf(stderr,
            "march: native_int_arr_filter_mask: array length %lld != mask length %lld\n",
            (long long)len, (long long)mlen); exit(1);
    }
    void *tmp = malloc((size_t)(len * 8));
    if (!tmp && len > 0) { fputs("march: out of memory\n", stderr); exit(1); }
    int64_t count = 0;
    for (int64_t i = 0; i < len; i++) {
        int64_t raw_bool = *(int64_t *)((char *)mask + TYPED_ARRAY_HDR_SIZE + i * 8);
        if (raw_bool >> 1)
            ((int64_t *)tmp)[count++] = *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
    }
    void *out = native_arr_alloc(count);
    memcpy((char *)out + NATIVE_ARR_HDR, tmp, (size_t)(count * 8));
    free(tmp);
    return out;
}

void *native_float_arr_filter_mask(void *arr, void *mask) {
    int64_t len = *(int64_t *)((char *)arr  + 16);
    int64_t mlen = *(int64_t *)((char *)mask + 16);
    if (len != mlen) {
        fprintf(stderr,
            "march: native_float_arr_filter_mask: array length %lld != mask length %lld\n",
            (long long)len, (long long)mlen); exit(1);
    }
    void *tmp = malloc((size_t)(len * 8));
    if (!tmp && len > 0) { fputs("march: out of memory\n", stderr); exit(1); }
    int64_t count = 0;
    for (int64_t i = 0; i < len; i++) {
        int64_t raw_bool = *(int64_t *)((char *)mask + TYPED_ARRAY_HDR_SIZE + i * 8);
        if (raw_bool >> 1) {
            double v; memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8);
            memcpy((char *)tmp + count * 8, &v, 8);
            count++;
        }
    }
    void *out = native_arr_alloc(count);
    memcpy((char *)out + NATIVE_ARR_HDR, tmp, (size_t)(count * 8));
    free(tmp);
    return out;
}

/* ── RingBuf: mutable fixed-capacity circular buffer ──────────────────────
 * Compiled backend for stdlib/ring_buf.march.  Mirrors the interpreter
 * (lib/eval/eval.ml ring_create/ring_push/ring_get/ring_pop_oldest).  RingBuf
 * is a single-owner primitive (the typechecker rejects it in send() payloads),
 * so there is no cross-heap-copy or concurrent-alias concern.
 *
 * A RingBuf(a) value is a resource cell (MARCH_RESOURCE_TAG, 40-byte layout
 *   [rc@0][tag@8][pad@12][native_ptr@16][dtor@24][type_id@32])
 * whose native_ptr points at a separately-calloc'd backing store and whose
 * dtor (march_ring_dtor) decrefs any live elements and frees the store when the
 * cell's refcount hits 0 — so dropping the buffer releases its contents.  The
 * backing store is deliberately NOT march_alloc'd: it is freed manually by the
 * dtor, so keeping it off the RC / live-alloc ledger stays symmetric.
 *
 * Elements are stored as uniform march_value words (heap ptr as-is, Int as
 * (n<<1)|1).  march_incrc/march_decrc are IS_HEAP_PTR-guarded, so immediates
 * are refcount-free.  Ownership discipline (mirrors NativeArray's element RC):
 *   - push transfers one reference into a slot (owned arg, no incref);
 *     overwriting a full slot decrefs the displaced oldest element.
 *   - pop moves a reference out (slot cleared, no decref).
 *   - get / peek / to_list alias a COPY out (march_incrc first — the buffer
 *     keeps its own reference).
 *   - the dtor decrefs every still-occupied slot.
 * clear only resets the cursors (matches the interpreter: the backing array is
 * not zeroed), so its stale references are released later by overwrite or drop.
 *
 * Backing store: { int64 cap, head, size; int64 slots[cap] }.  head = next
 * write position; the logical index convention (0 = oldest) matches the March
 * API.  Occupancy is driven entirely by head/size, never by slot nullness. */
typedef struct { int64_t cap; int64_t head; int64_t size; int64_t slots[]; } march_ring;

static void march_ring_dtor(void *p) {
    march_ring *r = (march_ring *)p;
    if (!r) return;
    for (int64_t i = 0; i < r->cap; i++)
        if (r->slots[i]) march_decrc((void *)(uintptr_t)r->slots[i]);
    free(r);
}

static inline march_ring *ring_of(void *cell) {
    return (march_ring *)*(void **)((char *)cell + 16);
}

/* Physical slot index for logical position [i] (0 = oldest). Caller guarantees
 * 0 <= i < size. Oldest lives at head-size; C's signed % can go negative, so
 * normalise with (+cap)%cap. */
static inline int64_t ring_slot_idx(march_ring *r, int64_t i) {
    return (((r->head - r->size + i) % r->cap) + r->cap) % r->cap;
}

void *ring_buf_make(int64_t cap) {
    if (cap <= 0) {
        fprintf(stderr, "march: ring_buf_make: capacity must be > 0, got %lld\n",
                (long long)cap);
        exit(1);
    }
    march_ring *r = (march_ring *)calloc(1, sizeof(march_ring) + (size_t)cap * 8);
    if (!r) { fputs("march: out of memory\n", stderr); exit(1); }
    r->cap = cap; r->head = 0; r->size = 0;
    void *cell = march_alloc(40);
    ((march_hdr *)cell)->tag = MARCH_RESOURCE_TAG;
    *(void **)((char *)cell + 16) = r;
    *(void (**)(void *))((char *)cell + 24) = march_ring_dtor;
    /* type_id@32 stays 0; ring cells never go through march_resource_get. */
    return cell;
}

/* push(rb, x): x arrives as a uniform march_value word. Owned — stored without
 * an incref. Overwriting a full slot decrefs the displaced oldest element. */
void ring_buf_push(void *cell, void *x) {
    march_ring *r = ring_of(cell);
    int64_t old = r->slots[r->head];
    if (old) march_decrc((void *)(uintptr_t)old);
    r->slots[r->head] = (int64_t)(uintptr_t)x;
    r->head = (r->head + 1) % r->cap;
    if (r->size < r->cap) r->size++;
}

/* pop(rb): remove and return the oldest element as Option(a) (niche: None=0,
 * Some(v)=v). Ownership moves to the caller; the slot is cleared without a
 * decref. */
void *ring_buf_pop(void *cell) {
    march_ring *r = ring_of(cell);
    if (r->size == 0) return (void *)0;
    int64_t idx = ring_slot_idx(r, 0);
    void *v = (void *)(uintptr_t)r->slots[idx];
    r->slots[idx] = 0;
    r->size--;
    return v;
}

/* get(rb, i): element at logical index i (0 = oldest) as Option(a). The buffer
 * keeps its reference, so the aliased-out copy is incref'd. */
void *ring_buf_get(void *cell, int64_t i) {
    march_ring *r = ring_of(cell);
    if (i < 0 || i >= r->size) return (void *)0;
    void *v = (void *)(uintptr_t)r->slots[ring_slot_idx(r, i)];
    march_incrc(v);
    return v;
}

void *ring_buf_peek_oldest(void *cell) {
    return ring_buf_get(cell, 0);
}

void *ring_buf_peek_newest(void *cell) {
    march_ring *r = ring_of(cell);
    return ring_buf_get(cell, r->size - 1);
}

int64_t ring_buf_size(void *cell) { return ring_of(cell)->size; }
int64_t ring_buf_cap(void *cell)  { return ring_of(cell)->cap; }

/* clear(rb): reset cursors only. Matches the interpreter — the backing array is
 * not zeroed, so any stale references remain owned by the buffer and are
 * released on a later overwrite or when the buffer is dropped. */
void ring_buf_clear(void *cell) {
    march_ring *r = ring_of(cell);
    r->head = 0;
    r->size = 0;
}

/* to_list(rb): snapshot oldest-to-newest as List(a). Each aliased element is
 * incref'd (the list gets its own references; the buffer keeps its copies). */
void *ring_buf_to_list(void *cell) {
    march_ring *r = ring_of(cell);
    void *lst = make_nil();
    for (int64_t i = r->size - 1; i >= 0; i--) {
        void *v = (void *)(uintptr_t)r->slots[ring_slot_idx(r, i)];
        march_incrc(v);
        lst = make_cons(v, lst);
    }
    return lst;
}

/* ── UUID v7 ──────────────────────────────────────────────────────────── */
#include <sys/time.h>

static void uuid_v7_bytes(uint8_t bytes[16], int64_t ts_ms) {
#if defined(__APPLE__)
    arc4random_buf(bytes, 16);
#else
    {
        ssize_t n;
        int fd = open("/dev/urandom", O_RDONLY);
        if (fd >= 0) { n = read(fd, bytes, 16); close(fd); }
        (void)n;
    }
#endif
    bytes[0] = (uint8_t)(ts_ms >> 40);
    bytes[1] = (uint8_t)(ts_ms >> 32);
    bytes[2] = (uint8_t)(ts_ms >> 24);
    bytes[3] = (uint8_t)(ts_ms >> 16);
    bytes[4] = (uint8_t)(ts_ms >>  8);
    bytes[5] = (uint8_t)(ts_ms      );
    bytes[6] = (uint8_t)((bytes[6] & 0x0f) | 0x70);  /* version 7 */
    bytes[8] = (uint8_t)((bytes[8] & 0x3f) | 0x80);  /* variant 10xx */
}

void *uuid_v7_at(int64_t ts_ms) {
    uint8_t b[16]; uuid_v7_bytes(b, ts_ms);
    char buf[37];
    snprintf(buf, sizeof(buf),
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        b[0],b[1],b[2],b[3], b[4],b[5], b[6],b[7], b[8],b[9],
        b[10],b[11],b[12],b[13],b[14],b[15]);
    return march_string_lit(buf, 36);
}

void *uuid_v7(void) {
    struct timeval tv; gettimeofday(&tv, NULL);
    int64_t ts_ms = (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
    return uuid_v7_at(ts_ms);
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

/* ── Logger v2 builtins (structured fields + appenders) ──────────────── */

static void *logger_v2_field_stack = NULL;  /* List(LogField), head = most recent */

static int64_t logger_v2_depth(void *lst) {
    int64_t n = 0;
    while (*(int32_t *)((char *)lst + 8) != 0) {
        lst = *(void **)((char *)lst + 24);
        n++;
    }
    return n;
}

static void logvalue_print(void *lv) {
    if (!lv) { fputs("null", stderr); return; }
    int32_t tag = *(int32_t *)((char *)lv + 8);
    switch (tag) {
    case 0: { void *s = *(void **)((char *)lv + 16); march_string *ms = (march_string *)s;
              fwrite(ms->data, 1, (size_t)ms->len, stderr); break; }
    case 1: { int64_t n = *(int64_t *)((char *)lv + 16); fprintf(stderr, "%" PRId64, n); break; }
    case 2: { double f; memcpy(&f, (char *)lv + 16, 8); fprintf(stderr, "%g", f); break; }
    case 3: { int64_t b = *(int64_t *)((char *)lv + 16); fputs(b ? "true" : "false", stderr); break; }
    default: fputs("null", stderr); break;
    }
}

static void logger_v2_print_fields(void *lst) {
    int first = 1;
    while (*(int32_t *)((char *)lst + 8) != 0) {
        void *field = *(void **)((char *)lst + 16);
        lst         = *(void **)((char *)lst + 24);
        void *k = *(void **)((char *)field + 16);
        void *v = *(void **)((char *)field + 24);
        if (!first) fputs(", ", stderr);
        march_string *ks = (march_string *)k;
        fwrite(ks->data, 1, (size_t)ks->len, stderr);
        fputc('=', stderr);
        logvalue_print(v);
        first = 0;
    }
}

void *logger_add_field(void *key, void *value) {
    pthread_mutex_lock(&march_logger_mutex);
    if (!logger_v2_field_stack) logger_v2_field_stack = logger_nil();
    void *field = march_alloc(32);  /* LogField(key,value): hdr(16)+key(8)+value(8) */
    *(void **)((char *)field + 16) = key;
    *(void **)((char *)field + 24) = value;
    logger_v2_field_stack = logger_cons(field, logger_v2_field_stack);
    pthread_mutex_unlock(&march_logger_mutex);
    return logger_nil();
}

int64_t logger_field_count(void) {
    pthread_mutex_lock(&march_logger_mutex);
    void *lst = logger_v2_field_stack ? logger_v2_field_stack : logger_nil();
    int64_t n = logger_v2_depth(lst);
    pthread_mutex_unlock(&march_logger_mutex);
    return n;
}

void *logger_get_fields(void) {
    pthread_mutex_lock(&march_logger_mutex);
    void *lst = logger_v2_field_stack ? logger_v2_field_stack : logger_nil();
    pthread_mutex_unlock(&march_logger_mutex);
    return lst;
}

void *logger_pop_to_depth(int64_t depth) {
    pthread_mutex_lock(&march_logger_mutex);
    if (!logger_v2_field_stack) logger_v2_field_stack = logger_nil();
    while (logger_v2_depth(logger_v2_field_stack) > depth)
        logger_v2_field_stack = *(void **)((char *)logger_v2_field_stack + 24);
    pthread_mutex_unlock(&march_logger_mutex);
    return logger_nil();
}

void *logger_dispatch(void *level_str, void *msg, void *module_name, void *fields) {
    (void)module_name;
    pthread_mutex_lock(&march_logger_mutex);
    march_string *ls = (march_string *)level_str;
    march_string *ms = (march_string *)msg;
    fputc('[', stderr);
    fwrite(ls->data, 1, (size_t)ls->len, stderr);
    fputs("] ", stderr);
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
    int has_fields = fields && *(int32_t *)((char *)fields + 8) != 0;
    int has_ctx    = logger_v2_field_stack && *(int32_t *)((char *)logger_v2_field_stack + 8) != 0;
    if (has_fields || has_ctx) {
        fputs(" {", stderr);
        if (has_fields)  logger_v2_print_fields(fields);
        if (has_fields && has_ctx) fputs(", ", stderr);
        if (has_ctx)     logger_v2_print_fields(logger_v2_field_stack);
        fputc('}', stderr);
    }
    fputc('\n', stderr);
    pthread_mutex_unlock(&march_logger_mutex);
    return logger_nil();
}

void *logger_register_appender(void *name, void *cb) { (void)name; (void)cb; return logger_nil(); }
void *logger_remove_appender(void *name)              { (void)name; return logger_nil(); }
void *logger_clear_appenders(void)                    { return logger_nil(); }
void *logger_appender_names(void)                     { return logger_nil(); /* Nil list */ }
void *logger_set_module_level(void *mod, int64_t lv)  { (void)mod; (void)lv; return logger_nil(); }
void *logger_clear_module_level(void *mod)            { (void)mod; return logger_nil(); }
int64_t logger_module_level(void *mod)                { (void)mod; return march_logger_level_val; }
