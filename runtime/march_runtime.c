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

/* Defined next to march_actor_broadcast_migrate; used by the actor receive
 * loop and march_actor_msg_dispose, both of which precede it in this file. */
static void migrate_msg_free(void *mm);
#include <pthread.h>
#include <sys/stat.h>
#include <time.h>
#include <sys/time.h>
#include <sys/resource.h>
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
/* <execinfo.h> (backtrace/backtrace_symbols_fd) is a glibc/BSD/Darwin
 * extension, not POSIX; musl does not ship it, so an unconditional include
 * breaks `march --compile` of the bundled runtime on Alpine and every other
 * musl distro.  glibc defines __GLIBC__ via <features.h>, which the <stdio.h>
 * above has already pulled in, so this test is decided by the time we get
 * here.  On musl the only casualty is the symbolic C backtrace in the opt-in
 * MARCH_DEBUG_OOM forensics below; March's own call-stack backtrace
 * (march_print_backtrace) is built from our own frame table and is
 * unaffected. */
#if !defined(__linux__) || defined(__GLIBC__)
#define MARCH_HAVE_EXECINFO 1
#include <execinfo.h>
#endif
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
#ifdef MARCH_HAVE_EXECINFO
    void *bt[64];
    int n = backtrace(bt, 64);
    fprintf(stderr, "  backtrace (%d frames):\n", n);
    backtrace_symbols_fd(bt, n, 2 /* stderr */);
#else
    fprintf(stderr, "  backtrace:      unavailable (no <execinfo.h> on this libc)\n");
#endif
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
    /* Exact live-object gauge: MARCH_ALLOC_BUMP/MARCH_FREE_BUMP keep this in
     * step with every heap alloc and free, so it is a deterministic leak
     * signal -- unlike peak RSS, it does not move with machine load or
     * allocator behaviour.  A leak makes it scale with the program's iteration
     * count; nothing else does.  Used by the aggregate-RC leak fixtures, which
     * run the same program at two sizes and require this number to match. */
    fprintf(stderr, "march_string_stats live_objs %lld\n",
            (long long)march_live_allocs());
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
 * leak gauge exposed via march_live_allocs(); see
 * specs/2026-06-19-c-ffi-abi-design.md §14.4.
 *
 * PER-THREAD slots, summed on read.  This gauge is always on -- not behind a
 * debug flag -- so it sits on the two hottest paths in the runtime
 * (march_alloc, and every RC free-on-zero branch).  A single process-wide
 * atomic made every scheduler thread read-modify-write ONE cache line there,
 * which is enough on its own to make allocation-heavy parallel code scale
 * negatively: on an M3 Max, a List.pmap_n over 64 cons-allocating tasks ran
 * ~3x SLOWER on 14 scheduler threads than on 1, where the same code without
 * the counter sped up ~3.4x.
 *
 * Each thread writes only its own slot, with a relaxed load/store pair rather
 * than an atomic RMW -- a plain ldr/str, no bus lock, no sharing.  The slot is
 * _Atomic solely so the reader's concurrent load is defined behaviour instead
 * of a data race.
 *
 * Allocation and freeing are NOT thread-affine: an object allocated on one
 * scheduler thread is routinely freed on another, so an individual slot can go
 * arbitrarily negative or positive and only the SUM is meaningful.  For the
 * sum to stay correct across thread lifetimes, an exiting thread folds its
 * residual into march_live_residual (via a pthread_key_t destructor) and
 * releases its slot for reuse; the reader walks the slot list and adds the
 * residual.  Slots are never freed, so the walk is lock-free.
 *
 * Exactness under concurrency is neither required nor previously provided --
 * the gauge is read between frames by FFI/leak tests, and memory_order_relaxed
 * already gave no ordering guarantee. */
typedef struct march_live_slot {
    _Atomic int64_t count;                   /* owner-written, anyone-read */
    _Atomic int in_use;                      /* 0 = free for a new thread   */
    struct march_live_slot *_Atomic next;
} march_live_slot;

static march_live_slot *_Atomic march_live_slot_head = NULL;
static _Atomic int64_t march_live_residual = 0;   /* folded from exited threads */
static _Thread_local march_live_slot *march_live_self = NULL;
static pthread_key_t march_live_key;
static pthread_once_t march_live_once = PTHREAD_ONCE_INIT;

/* Thread-exit: move this thread's net count into the process-wide residual and
 * hand the slot back.  The exchange makes the move atomic with respect to a
 * concurrent reader, so the count is never seen twice nor lost. */
static void march_live_slot_release(void *arg) {
    march_live_slot *s = (march_live_slot *)arg;
    int64_t n = atomic_exchange_explicit(&s->count, 0, memory_order_relaxed);
    if (n) atomic_fetch_add_explicit(&march_live_residual, n, memory_order_relaxed);
    march_live_self = NULL;
    atomic_store_explicit(&s->in_use, 0, memory_order_release);
}

static void march_live_key_init(void) {
    pthread_key_create(&march_live_key, march_live_slot_release);
}

/* Claim a free slot (a thread that has since exited), else push a new one. */
static march_live_slot *march_live_slot_acquire(void) {
    pthread_once(&march_live_once, march_live_key_init);
    for (march_live_slot *s = atomic_load_explicit(&march_live_slot_head, memory_order_acquire);
         s; s = atomic_load_explicit(&s->next, memory_order_acquire)) {
        int expected = 0;
        if (atomic_compare_exchange_strong_explicit(&s->in_use, &expected, 1,
                memory_order_acq_rel, memory_order_relaxed)) {
            march_live_self = s;
            pthread_setspecific(march_live_key, s);
            return s;
        }
    }
    march_live_slot *s = (march_live_slot *)calloc(1, sizeof *s);
    if (!s) { fputs("march: out of memory\n", stderr); exit(1); }
    atomic_store_explicit(&s->in_use, 1, memory_order_relaxed);
    march_live_slot *head = atomic_load_explicit(&march_live_slot_head, memory_order_relaxed);
    do {
        atomic_store_explicit(&s->next, head, memory_order_relaxed);
    } while (!atomic_compare_exchange_weak_explicit(&march_live_slot_head, &head, s,
                 memory_order_release, memory_order_relaxed));
    march_live_self = s;
    pthread_setspecific(march_live_key, s);
    return s;
}

static inline void march_live_bump(int64_t d) {
    march_live_slot *s = march_live_self;
    if (__builtin_expect(s == NULL, 0)) s = march_live_slot_acquire();
    atomic_store_explicit(&s->count,
        atomic_load_explicit(&s->count, memory_order_relaxed) + d,
        memory_order_relaxed);
}

int64_t march_live_allocs(void) {
    int64_t total = atomic_load_explicit(&march_live_residual, memory_order_relaxed);
    for (march_live_slot *s = atomic_load_explicit(&march_live_slot_head, memory_order_acquire);
         s; s = atomic_load_explicit(&s->next, memory_order_acquire))
        total += atomic_load_explicit(&s->count, memory_order_relaxed);
    return total;
}
#define MARCH_ALLOC_BUMP() march_live_bump(1)
#define MARCH_FREE_BUMP()  march_live_bump(-1)

/* If [p] is an FFI resource cell (MARCH_RESOURCE_TAG), run its destructor on
 * the wrapped native pointer before the cell itself is freed.  Called from
 * every RC free-on-zero path.  Cell layout: native_ptr@16, dtor@24. */
void march_decrc(void *p);
static inline void march_run_resource_dtor(void *p) {
    int32_t tag = ((march_hdr *)p)->tag;
    if (tag == MARCH_RESOURCE_TAG) {
        void (*dtor)(void *) = *(void (**)(void *))((char *)p + 24);
        void *native = *(void **)((char *)p + 16);
        if (dtor) dtor(native);
    } else if (tag == MARCH_TASK_TAG) {
        /* A Task owns the box of a Float result. The trampoline stores
         * task[3] = (raw << 1) | 1; for a Float task raw is the
         * march_alloc_float box the apply fn returned, and task_await_unwrap
         * reads the double out of it WITHOUT consuming it (awaiting twice is
         * legal), so until now the box outlived the Task: one leaked box per
         * awaited Float task.
         *
         * Release only that case. An untagged task[3] (0 = never finished, or
         * the cancel path's Err cell) is skipped; a tagged scalar untags to an
         * odd value and fails IS_HEAP_PTR; a heap result of any other tag is
         * handed to the caller by the await paths, which account for it, so it
         * is not ours to release. */
        int64_t slot = ((int64_t *)p)[3];
        if (slot & 1) {
            void *raw = (void *)(intptr_t)(slot >> 1);
            if (IS_HEAP_PTR(raw) && ((march_hdr *)raw)->tag == MARCH_FLOAT_TAG)
                march_decrc(raw);
        }
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

/* Sibling of march_decrc_local that reports whether the release freed the
 * object, for a caller that has work to do only on the path where it did
 * (Drop.run's closure-capture releases).
 *
 * It exists rather than reusing march_decrc_freed because the two differ in
 * ATOMICITY POLICY, not just in the return value: march_decrc_freed is
 * unconditionally atomic, while the "local" ops take a non-atomic fast path
 * off the scheduler.  Substituting one for the other at a site the compiler
 * previously emitted as march_decrc_local leaves that object decremented
 * atomically at one site and non-atomically at another, and a read-modify-write
 * pair split that way loses updates in both directions — a premature free.
 * Measured: swapping in march_decrc_freed at the closure-environment release,
 * with no other change and no child releases at all, took
 * test/native/node_discovery.march from 0 crashes in 60 runs to 21 in 40.
 * Mirror march_decrc_local's branch structure exactly; only the report is new.
 *
 * Returns 0 for a non-heap pointer — the opposite of march_decrc_freed, and
 * deliberately: "nothing was freed" is the answer that makes a caller skip its
 * child releases, which is the safe direction for a stack-promoted or
 * tagged-scalar value. */
int64_t march_decrc_local_freed(void *p) {
    if (!IS_HEAP_PTR(p)) return 0;
    if (march_sched_in_scheduler() || march_tls_concurrent_rc)
        return march_decrc_freed(p);
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
        return 1;
    }
    return 0;
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

/* Byte-for-byte reproduce the interpreter's OCaml `string_of_float`
 * (eval.ml), which is `valid_float_lexem (format_float "%.12g" f)`:
 *   - `%.12g` gives the same 12-significant-digit form as OCaml's
 *     format_float (both defer to the platform libc);
 *   - valid_float_lexem appends a bare '.' when every character is a
 *     digit or leading '-', so a whole number prints "1." not "1"/"1.0".
 * The old `%g` (6 sig-figs, and no trailing dot) diverged from the
 * interpreter on both precision and whole numbers — the golden oracle
 * (specs/lang/golden/g09_float_show.march) now pins the agreement.
 * Shared by march_float_to_string and march_print_float so the two cannot
 * drift. Writes into [buf] (64 bytes) and returns the length. */
static int march_format_float_ocaml(char *buf, double f) {
    int len = snprintf(buf, 64, "%.12g", f);
    if (len < 0) len = 0;
    if (len > 63) len = 63;
    int bare_int = 1;
    for (int i = 0; i < len; i++) {
        char c = buf[i];
        if (!((c >= '0' && c <= '9') || c == '-')) { bare_int = 0; break; }
    }
    if (bare_int && len > 0 && len < 63) {
        buf[len++] = '.';
        buf[len] = '\0';
    }
    return len;
}

void *march_float_to_string(double f) {
    char buf[64];
    int len = march_format_float_ocaml(buf, f);
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

/* `compare` on Float (and the `compare_float` builtin): a total preorder that
 * matches the interpreter (OCaml's Float.compare). NaN equals NaN and is LESS
 * than every non-NaN value; otherwise the IEEE order, so -0.0 and +0.0 compare
 * equal. A plain `(x > y) - (x < y)` returned 0 for any NaN operand, making NaN
 * "equal" to everything and breaking sorts / Map keys built on compare.
 * `==` / `<` stay IEEE (they are lowered inline with fcmp, not through here). */
int64_t march_compare_float(double x, double y) {
    int xn = x != x, yn = y != y;
    if (xn || yn) return yn - xn;
    return (x > y) - (x < y);
}

/* IEEE three-way compare (0 when either operand is NaN): the ordering the
 * erased relational operators (`<`/`<=`/`>`/`>=` via [march_poly_compare])
 * and SIMD lane ordering have always used. Kept separate from
 * [march_compare_float] so the NaN-total `compare` fix does not turn an
 * erased `nan < 1.0` true. */
static int64_t march_ieee_compare_double(double x, double y) {
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

/* ── Boxed SIMD vector (128-bit) ─────────────────────────────────────── */

/* Heap-box a 128-bit SIMD vector for storage in a type-erased (ptr) slot: a
 * 32-byte leaf cell tagged MARCH_SIMD_TAG with the vector kind in the hdr pad
 * slot and the 16-byte payload at offset 16 (16-aligned). No interior
 * pointers, so the ordinary rc==0 free path (march_decrc / march_free) frees
 * it with no special-case walk — see those functions' tag switches, which
 * handle MARCH_STRING_TAG/MARCH_RESOURCE_TAG specially but need no case for
 * MARCH_SIMD_TAG. */
void *march_simd_alloc(int64_t kind) {
    void *p = march_alloc(32);
    march_hdr *h = (march_hdr *)p;
    h->tag = MARCH_SIMD_TAG;
    h->pad = (int32_t)kind;
    return p;
}

void march_simd_bounds_panic(int64_t i, int64_t lanes, int64_t len) {
    fprintf(stderr,
        "march: runtime error: simd load/store out of bounds (index %lld, lanes %lld, length %lld)\n",
        (long long)i, (long long)lanes, (long long)len);
    exit(1);
}

/* Lane-index panic for extract/replace with a DYNAMIC index the refinement
 * checker could not prove in range (an unprovable obligation is silently
 * Skipped, so it is not a backstop). Separate from
 * march_simd_bounds_panic because the load/store message's (index, lanes,
 * length) triple would describe the wrong rule here: the lane rule is
 * simply 0 <= i < lanes. The interpreter raises its own error for the
 * same case (eval.ml's simd_*_extract/replace arms). */
void march_simd_lane_panic(int64_t i, int64_t lanes) {
    fprintf(stderr,
        "march: runtime error: simd lane index out of bounds (index %lld, lanes %lld)\n",
        (long long)i, (long long)lanes);
    exit(1);
}

/* SIMD vector kind byte (see MARCH_SIMD_TAG's doc comment): 0=f32x4 1=f64x2
 * 2=i32x4 3=i64x2 4=u8x16, stored in the hdr pad slot. Shared by
 * [march_poly_eq]/[march_poly_compare] (generic erased-slot compare) below
 * and any other tag-dispatched consumer that needs to interpret a SIMD
 * box's 16-byte payload (offset 16) by lane. */

/* Lane-wise equality by kind. Floats use the native `==` operator so a NaN
 * lane compares unequal (matches the interpreter's OCaml `<>` on VF32x4/
 * VF64x2 arrays) and +0.0/-0.0 compare equal (IEEE `==`, not bit-identity —
 * matches [impl Eq(F32x4)]'s per-lane `simd_f32x4_extract(...) ==
 * simd_f32x4_extract(...)` chain, itself ordinary Float `==`). Integer
 * kinds compare exactly (a plain memcmp would also work for them, but the
 * explicit per-lane loop keeps every kind's comparator shaped the same). */
static int64_t march_simd_eq(void *a, void *b) {
    int32_t ka = ((march_hdr *)a)->pad, kb = ((march_hdr *)b)->pad;
    if (ka != kb) return 0;
    const char *pa = (const char *)a + 16, *pb = (const char *)b + 16;
    switch (ka) {
        case 0: { /* f32x4 */
            float fa[4], fb[4];
            memcpy(fa, pa, sizeof(fa)); memcpy(fb, pb, sizeof(fb));
            for (int i = 0; i < 4; i++) if (fa[i] != fb[i]) return 0;
            return 1;
        }
        case 1: { /* f64x2 */
            double da[2], db[2];
            memcpy(da, pa, sizeof(da)); memcpy(db, pb, sizeof(db));
            for (int i = 0; i < 2; i++) if (da[i] != db[i]) return 0;
            return 1;
        }
        case 2: /* i32x4 */
        case 3: /* i64x2 */
        case 4: /* u8x16 */
            return memcmp(pa, pb, 16) == 0 ? 1 : 0;
        default: return 0;
    }
}

/* Ordered lane-wise compare by kind, for [march_poly_compare]'s total-order
 * contract: different kinds order by kind index (arbitrary but total and
 * stable); same kind orders lexicographically lane 0..N-1, each lane via
 * [march_compare_int]/[march_ieee_compare_double] ("0 for unordered/equal,
 * else sign of difference" — a NaN lane compares as 0/unordered against
 * everything, including itself, same as [march_poly_compare]'s boxed-float
 * arm; NOT the NaN-total [march_compare_float] that `compare` uses). */
static int64_t march_simd_compare(void *a, void *b) {
    int32_t ka = ((march_hdr *)a)->pad, kb = ((march_hdr *)b)->pad;
    if (ka != kb) return march_compare_int(ka, kb);
    const char *pa = (const char *)a + 16, *pb = (const char *)b + 16;
    switch (ka) {
        case 0: { /* f32x4 */
            float fa[4], fb[4];
            memcpy(fa, pa, sizeof(fa)); memcpy(fb, pb, sizeof(fb));
            for (int i = 0; i < 4; i++) {
                int64_t c = march_ieee_compare_double((double)fa[i], (double)fb[i]);
                if (c != 0) return c;
            }
            return 0;
        }
        case 1: { /* f64x2 */
            double da[2], db[2];
            memcpy(da, pa, sizeof(da)); memcpy(db, pb, sizeof(db));
            for (int i = 0; i < 2; i++) {
                int64_t c = march_ieee_compare_double(da[i], db[i]);
                if (c != 0) return c;
            }
            return 0;
        }
        case 2: { /* i32x4 */
            int32_t ia[4], ib[4];
            memcpy(ia, pa, sizeof(ia)); memcpy(ib, pb, sizeof(ib));
            for (int i = 0; i < 4; i++) {
                int64_t c = march_compare_int(ia[i], ib[i]);
                if (c != 0) return c;
            }
            return 0;
        }
        case 3: { /* i64x2 */
            int64_t ia[2], ib[2];
            memcpy(ia, pa, sizeof(ia)); memcpy(ib, pb, sizeof(ib));
            for (int i = 0; i < 2; i++) {
                int64_t c = march_compare_int(ia[i], ib[i]);
                if (c != 0) return c;
            }
            return 0;
        }
        case 4: { /* u8x16 */
            const uint8_t *ua = (const uint8_t *)pa, *ub = (const uint8_t *)pb;
            for (int i = 0; i < 16; i++) {
                int64_t c = march_compare_int((int64_t)ua[i], (int64_t)ub[i]);
                if (c != 0) return c;
            }
            return 0;
        }
        default: return 0;
    }
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
    /* Boxed SIMD vectors (MARCH_SIMD_TAG, march_simd_alloc): compare by lane
     * VALUE, not box identity — without this arm two distinct boxes holding
     * the same lanes fell through to the `return 0` default (silently
     * "not equal" for content that IS equal), and worse, a compiled generic
     * comparison of two DIFFERENT vectors could read as equal via whatever
     * the caller's fallback happened to be. See march_simd_eq's doc comment
     * for the exact lane-compare semantics (NaN != NaN, +0.0 == -0.0). */
    if (ta == MARCH_SIMD_TAG && tb == MARCH_SIMD_TAG)
        return march_simd_eq(a, b);
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
        return march_ieee_compare_double(march_unbox_float(a), march_unbox_float(b));
    if (ta == MARCH_STRING_TAG && tb == MARCH_STRING_TAG)
        return march_compare_string(a, b);
    /* Boxed SIMD vectors: same rationale as march_poly_eq's arm above — a
     * lane-wise total order (kind, then lexicographic by lane) instead of
     * meaningless box-identity comparison. See march_simd_compare. */
    if (ta == MARCH_SIMD_TAG && tb == MARCH_SIMD_TAG)
        return march_simd_compare(a, b);
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

/* N-ary concat: sum the lengths of `n` parts, allocate once, copy once.
 *
 * `parts` is a caller-owned array of n march_string* -- codegen builds it with
 * an alloca in the calling frame, so there is no heap allocation for the
 * spread and nothing here to free.  A C variadic (`..., ...`) would have done
 * the same job, but an explicit array keeps the ABI identical on every target
 * (arm64 passes variadic arguments differently from fixed ones) and makes the
 * function callable from tests.
 *
 * This is what makes interpolation linear.  The march_string_concat3 fold is
 * fine for a handful of short operands, but it re-copies the accumulated
 * prefix at every link, so k parts cost O(k^2) bytes copied -- with 4KB
 * operands that is the difference between 0.5s and 0.03s at k=32.  Desugar
 * therefore emits concat3 for k<=3 (where a single concat3 IS a single
 * allocate-and-copy, so there is nothing to improve) and this for k>=4.
 *
 * All parts are borrowed: this neither retains nor releases them. */
void *march_string_concat_n(int64_t n, void **parts) {
    int64_t total = 0;
    for (int64_t i = 0; i < n; i++)
        total += ((march_string *)parts[i])->len;
    march_string *r = march_string_alloc(total);
    char *w = r->data;
    for (int64_t i = 0; i < n; i++) {
        march_string *p = (march_string *)parts[i];
        march_str_copy(w, p->data, (size_t)p->len);
        w += p->len;
    }
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

/* `print_int(n)` / `print_float(f)`: the interpreter writes `string_of_int n`
 * / `string_of_float f` with no newline (eval_builtins.ml).  Format on the
 * stack and issue the same single write(2) march_print does, so there is no
 * intermediate heap string to allocate and release. */
void march_print_int(int64_t n) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)n);
    if (len > 0) write(1, buf, (size_t)len);
}

void march_print_float(double f) {
    char buf[64];
    int len = march_format_float_ocaml(buf, f);
    if (len > 0) write(1, buf, (size_t)len);
}

/* Serialises march_println against itself across OS threads.  See the comment
 * in march_println for why the writev alone is not enough.
 *
 * Held only across the one writev(2) below, and march_println is never reached
 * from a signal handler (the preempt handler does two volatile scalar stores;
 * the SIGSEGV/SIGBUS stack-growth handler does not print), so this cannot
 * self-deadlock.  march_print — no newline, one write(2), one buffer — has
 * nothing to tear between and stays lock-free. */
static pthread_mutex_t march_stdout_mu = PTHREAD_MUTEX_INITIALIZER;

void march_println(void *s) {
    march_string *ms = (march_string *)s;
    /* Emit the payload AND its trailing newline in a single writev(2) syscall.
     * Two separate write() calls let another thread's println interleave
     * between the data and the '\n', tearing lines together (and stranding a
     * lone newline) — visible in multi-node/multi-actor programs run with >1 OS
     * scheduler thread.
     *
     * The single writev is necessary but NOT sufficient, and the comment that
     * used to sit here claimed otherwise ("a single vectored write to a regular
     * file/pipe is atomic (POSIX)").  POSIX says no such thing about competing
     * writers, and darwin 25.5.0/arm64 demonstrably splits it: with four green
     * threads spread over the scheduler pool printing a fixed 32-byte payload,
     * EVERY run of 1200 lines tore, ~140 lines per run, always between the two
     * iovecs — one thread's iov[0], then another thread's whole line, then the
     * first thread's iov[1].  That is what produces the two signature shapes,
     * a doubled line and a stranded empty one.  Reproduced to a regular file
     * and to a pipe.
     *
     * So take a lock as well.  The lock is what actually provides the
     * guarantee; the writev stays because halving the syscall count is worth
     * keeping and because it keeps the critical section to one syscall.
     * (specs/progress/2026-08-21-println-writev-not-atomic-across-threads.md) */
    struct iovec iov[2];
    iov[0].iov_base = ms->data;
    iov[0].iov_len  = (size_t)ms->len;
    iov[1].iov_base = (void *)"\n";
    iov[1].iov_len  = 1;
    pthread_mutex_lock(&march_stdout_mu);
    ssize_t rc = writev(1, iov, 2);
    pthread_mutex_unlock(&march_stdout_mu);
    (void)rc;
}

/* Writes the String verbatim, NO newline, like the interpreter's print_stderr.
 * Every caller (IO.warn, Logger.appender_stderr) appends its own "\n"; the
 * newline this used to add doubled each of them in compiled programs. */
void march_print_stderr(void *s) {
    march_string *ms = (march_string *)s;
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
}

/* One whole line (no 4096-byte cap: a longer line used to come back in
 * pieces, one per call, where the interpreter returns it whole), minus its
 * trailing "\n" and "\r". */
void *march_io_read_line(void) {
    char *buf = NULL;
    size_t cap = 0;
    ssize_t n = getline(&buf, &cap, stdin);
    if (n <= 0) {
        free(buf);
        return march_string_lit("", 0);
    }
    size_t len = (size_t)n;
    if (len > 0 && buf[len-1] == '\n') { buf[--len] = '\0'; }
    if (len > 0 && buf[len-1] == '\r') { buf[--len] = '\0'; }
    void *r = march_string_lit(buf, (int64_t)len);
    free(buf);
    return r;
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
static void do_actor_death(void *actor, march_death_reason reason,
                           const char *message, size_t message_len);

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
        size_t len = (size_t)ms->len;
        char *copy = (char *)malloc(len + 1);
        if (!copy) {
            fputs("march: out of memory copying actor crash reason\n", stderr);
            exit(1);
        }
        memcpy(copy, ms->data, len);
        copy[len] = '\0';
        free(cur_proc->crash_message);
        cur_proc->crash_message = copy;
        cur_proc->crash_message_len = len;
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
 * try_finally : (() -> a) -> (() -> b) -> a   (typecheck_builtins.ml)
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
 * march_sched_recv_user() to block until a user message arrives, dispatches it
 * via the actor's $dispatch closure, then calls march_sched_tick() for
 * cooperative preemption. Runtime control values remain queued for explicit
 * language-level receive().
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
     * restart.  For a child declared with `init` arguments (`Worker w(e)`,
     * D24) the compiler passes a CAPTURING closure instead of the static
     * reference: its environment holds the evaluated arguments, so every
     * restart re-supplies the values the first spawn got.  Ownership of the
     * cell transfers to this slot at registration (see
     * march_actor_register_child); nothing here ever frees it. */
    void *spawn_clo;
    int64_t word_idx;         /* position among this supervisor's alphabetically-sorted
                                  state fields; this child's Int-encoded pid lives at
                                  ((int64_t*)supervisor)[4 + word_idx] */
    /* Task 16: exponential restart backoff. Zeroed at registration
     * (march_actor_register_child — sup_children grows via realloc, which
     * does NOT zero new memory, so these two fields are set explicitly
     * there). Both are only ever touched from march_supervisor_notify,
     * which Task 16 serializes with g_supervise_mu — see that function's
     * comment for the concurrent-crash race this closes. */
    /* Restart policy for this child: 0 permanent, 1 transient, 2 temporary.
     * Set once at registration and never mutated, so unlike the two backoff
     * fields below it needs no g_supervise_mu protection to read. Like them,
     * it MUST be assigned explicitly at registration — sup_children grows via
     * realloc, which does not zero the new memory. */
    int32_t restart_type;
    /* How long march_actor_stop waits for this child to drain when the tree
     * is stopped: -1 infinity, 0 brutal (kill at once), otherwise a
     * millisecond budget after which the child is killed outright. Set once at
     * registration, alongside restart_type and for the same realloc reason. */
    int64_t shutdown_ms;
    int32_t crash_streak;     /* consecutive crashes without surviving a full
                                  supervisor_window_secs window */
    int64_t last_crash_ms;    /* march_now_ms() at the most recent crash; 0
                                  means "never crashed yet" */
    /* What a dead incarnation of this slot hands to its replacement: the
     * names it had registered and its spawn-site capability.  Stashed when
     * the child dies on the way to a restart (stash_child_for_restart), and
     * taken by march_respawn_child.  They live on the restart's slot, not on
     * the dead child's meta, because that meta is freed once its death is
     * processed, and a delayed restart runs up to the backoff cap later.
     * Guarded by g_supervise_mu; zeroed explicitly at registration (realloc). */
    char  **pending_names;
    int     pending_name_count;
    void   *pending_spawn_cap;
} march_sup_child;

/* march_actor_meta.drain_deadline_ms while a stop is claimed but not yet
 * armed. Distinct from every real deadline (which is a march_now_ms() value,
 * or -1 for `shutdown infinity`) so the receiving loop can tell "a stop is in
 * progress, keep working" from "your deadline has passed, stop now". */
#define MARCH_DRAIN_NOT_ARMED INT64_MIN

/* What a pid still names after its actor is dead: the TOMBSTONE, ~56 B,
 * allocated with the meta and never freed (specs/progress/2026-09-23-proc-
 * struct-reclamation-metas.md, "Chosen mechanism" step 3).  A dead pid is an Int that can
 * be asked for its terminal reason, printed, or checked as a capability at
 * any later time, so this part outlives the meta.  Reached by pid index
 * through g_pid_chunks (dense, grow-only) and, for a dead actor, by record
 * address through g_tomb (a cold table only lookup misses consult).
 *
 * [addr] is a KEY only and is never dereferenced: the record it names may be
 * freed and its memory reused.  That is what closes the `m->actor`
 * use-after-free sites the survey found (a meta found by pid index handing
 * out a pointer to a freed record). */
struct march_actor_meta;
typedef struct march_pid_entry {
    void                              *addr;
    /* The meta while it is linked in g_actor_tbl (from its creation, which
     * for a supervisor is before its own spawn: the supervise glue links its
     * children to it first); NULL from the death claim on.  Written under
     * g_tbl_mu (release), read lock-free (acquire) inside a critical section. */
    _Atomic(struct march_actor_meta *) live;
    /* -1 until march_spawn_common assigns it; read through pe_pid(). */
    _Atomic int64_t                    pid_index;
    /* Capability epoch: incremented across a supervised respawn (the
     * replacement's entry starts at the dead incarnation's + 1). */
    _Atomic int64_t                    epoch;
    /* Claimed once, under g_tbl_mu, by do_actor_death; the reason and message
     * are written before the release store of terminal_set, so a reader that
     * acquire-loads it set sees them. */
    _Atomic int                        terminal_set;
    march_death_reason                 terminal_reason;
    char                              *terminal_message; /* Crash bytes + NUL */
    size_t                             terminal_message_len;
} march_pid_entry;

/* Per-actor scheduler metadata.  Stored in a side table keyed by actor
 * pointer so the actor object layout (and codegen) are unaffected.
 *
 * LIFETIME (specs/progress/2026-09-23-proc-struct-reclamation-metas.md, metas PR).
 * A meta is reclaimed, and it is counted:
 *   - g_actor_tbl holds one reference while the meta is linked.  The death
 *     claim (do_actor_death, under g_tbl_mu) unlinks it, and the claimant
 *     inherits that reference and drops it when the death is processed.
 *   - The actor's green thread holds one from activation to its last access.
 *   - A cold holder that must keep the meta across a context switch or a
 *     wait (supervision, stop, hot-reload markers) pins one with meta_tryget
 *     inside a critical section, and drops it with meta_put.
 * The last meta_put retires it to march_reclaim, which frees it after its
 * grace period.  So THE RULE for every other reader:
 *
 *   A meta found by lookup (find_meta, march_pid_entry.live) is valid ONLY
 *   inside the reader's critical section (march_reclaim_enter/exit), never
 *   across a context switch, unless the reader pinned it.
 *
 * And its [actor] may be dereferenced only by a caller that holds its own
 * counted reference to that record, or under g_tbl_mu while the meta is
 * linked (then the live actor's own reference is still held: it is dropped
 * only after the death claim).  Nothing a dead pid still needs lives here;
 * that is the march_pid_entry above. */
typedef struct march_actor_meta {
    void                      *actor;
    /* Green thread running this actor's loop.  Published by
     * activate_actor_green_thread (compare-exchange from NULL) and set to
     * MARCH_GT_EXITED by that thread itself before its proc can die, never
     * back to NULL, so a late activation store cannot republish a dead proc.
     * Read through meta_gt(), which maps MARCH_GT_EXITED to NULL.  A proc
     * loaded from here is valid ONLY inside the reader's critical section,
     * never across a context switch: the proc is freed after its grace
     * period (march_proc's LIFETIME comment). */
    _Atomic(march_proc *)      green_thread;
    /* Hash-table chain (by actor ptr).  _Atomic: an unlink rewrites a
     * predecessor's link while lock-free readers walk it. */
    _Atomic(struct march_actor_meta *) tbl_next;
    /* References (see LIFETIME above); the last meta_put retires the meta. */
    _Atomic int64_t              refs;
    /* 1 while linked in g_actor_tbl.  Read and written under g_tbl_mu. */
    int                          linked;
    /* This incarnation's tombstone, allocated with the meta (meta_new_locked;
     * compiled code creates the meta before the spawn, to set
     * dispatch_name_id and call_tags), given its pid index by
     * march_spawn_common.  Never NULL, never freed. */
    march_pid_entry             *pe;
    /* Graceful shutdown (march_actor_stop). [draining] is set by whichever
     * thread called stop; the actor's own green thread reads it at the top of
     * every receive iteration and exits once the mailbox is empty or the
     * deadline has passed. Both are _Atomic because writer and reader are
     * always different threads; the deadline is published BEFORE draining so
     * an acquire-load of draining implies a visible deadline. A negative
     * deadline means `shutdown infinity`: drain to empty however long it
     * takes. See specs/todos/2026-08-12-graceful-shutdown-and-drain.md. */
    _Atomic int                  draining;
    /* MARCH_DRAIN_NOT_ARMED until march_actor_stop has finished tearing down
     * this actor's children and computed its own deadline. The receive loop
     * must NOT exit while it reads that value — see the gate there. */
    _Atomic int64_t              drain_deadline_ms;
    march_cleanup_node         *cleanup_head; /* Cleanup callbacks (most recent first) */
    march_monitor_node         *monitor_head; /* Monitors watching this actor   */
    /* Supervision metadata (set by march_register_supervisor): */
    int                         supervisor_strategy;    /* 0=one_for_one, 1=one_for_all, 2=rest_for_one */
    int64_t                     supervisor_max_restarts;
    int64_t                     supervisor_window_secs;
    /* Restart-backoff curve, from the supervise block's optional
     * `backoff base N cap N jitter N%` clause. Defaulted by the parser to
     * 25 / 5000 / 25 — the constants march_supervisor_notify used to spell
     * inline — so an absent clause reproduces the previous delays exactly.
     * Written once at registration, read only by march_supervisor_notify. */
    int64_t                     backoff_base_ms;
    int64_t                     backoff_cap_ms;
    int64_t                     backoff_jitter_pct;
    /* Capability-passing (--test builds only): the capability captured at the
     * SPAWN site, so that an actor handler can dispatch through its dictionary.
     *
     * A handler is entered from the scheduler, not from an elaborated caller,
     * so there is nobody to thread a capability parameter from — the dispatch
     * function's arity is frozen because the actor record holds it as
     * $d_dispatch.  The spawn site DOES have the capability in scope, so it is
     * captured here and read back by the dispatch.
     *
     * Kept on the meta rather than as a field on the actor record on purpose:
     * the record's layout is pinned by the C runtime's hardcoded word indices
     * (a[2]=dispatch, a[3]=alive) AND is what migrate_state, hot reload and
     * @compat all reason about.  The meta is runtime-internal and none of them
     * see it.
     *
     * NULL — the overwhelming case, every release build — means "no captured
     * capability", which reads back as the plain sentinel and takes the
     * ambient path. _Atomic for the same reason as green_thread: written on
     * the spawning thread, read on the actor's own. */
    _Atomic(void *)             spawn_cap;
    /* Phase 5: non-zero for actors compiled with --hot-reload.
     * Holds the dispatch-table NAME_ID of the actor's _dispatch function.
     * Used by actor_green_thread for dispatch-table lookup (enabling function
     * hot-swap) and by march_actor_broadcast_migrate to target only the right actors. */
    uint32_t                    dispatch_name_id;
    /* The epoch model (plan II.4.4-II.4.6).  The actor's code epoch is its
     * proc's (march_proc.code_epoch); these fields are the actor loop's
     * bookkeeping around it, touched only by the actor's own green thread
     * except hcr_lost_epoch (written by an activation).
     *
     * hcr_pending_epoch: a marker consumed while the proc held an epoch
     *   (epoch_holds > 0); it keeps that marker's pin and fires when the last
     *   hold is released.  0 = none.
     * hcr_lost_epoch: the newest epoch whose marker could not be enqueued
     *   (out of memory).  The #564 fallback, kept as belt and braces: the
     *   actor advances to it at its next message boundary.  Unreachable
     *   unless malloc fails.
     * hcr_def_*: the deferred queue -- newer-format messages a held actor
     *   could neither advance for nor dispatch, replayed in order when it
     *   advances.
     * hcr_dropped: old messages this actor dropped since it last advanced
     *   (reported on stderr at the advance). */
    uint32_t                    hcr_pending_epoch;
    _Atomic(uint32_t)           hcr_lost_epoch;
    struct hcr_deferred        *hcr_def_head;
    struct hcr_deferred        *hcr_def_tail;
    int64_t                     hcr_def_n;
    int64_t                     hcr_dropped;
    /* This actor type's message-constructor tags in HANDLER ORDER: entry i
     * is the tag of its i-th handler's constructor (the F19 memory-safety
     * fix gives actor _Msg ctors globally-unique tags, a stable hash of the
     * qualified constructor name — see lib/tir/llvm_toplevel.ml
     * actor_msg_tag_table — so they are NOT contiguous).  march_actor_call
     * maps the caller's sentinel ctor INDEX through it to address the handler
     * positionally; NULL = unregistered (fall back to the sentinel's raw
     * tag).  Stamped at actor-record alloc via march_actor_set_call_tags, so
     * supervisor respawns (which re-run the March-level spawn closure)
     * re-stamp it on the fresh record.  Interned by the runtime (never
     * freed, see call_tags_intern): the codegen's copy may live in a hot
     * patch that is dlclosed while this actor still runs. */
    const struct march_call_tags *call_tags;
    /* Set on a CHILD when it is spawned by a supervisor: the SUPERVISOR's
     * tombstone, so the supervisor is found by incarnation (sup_pin), never
     * by a record address that may since have been freed and reused.  NULL
     * for every other actor, including a supervisor's own meta, and for a
     * child being torn down by its supervisor (a batch restart's sweep, a
     * stop).  Read and written under g_tbl_mu. */
    march_pid_entry             *sup_pe;
    int                          sup_child_index;
    /* Set on a SUPERVISOR (an actor that itself declares `supervise do ... end`);
     * NULL/0 for every other actor, including its own children. */
    march_sup_child             *sup_children;
    int                          sup_num_children;
    /* Restart-history timestamps (seconds), for max_restarts-within-window
     * throttling; valid only when this actor IS a supervisor. */
    double                      *sup_restart_ts;
    int                          sup_restart_len;
    /* Task 16 fix-up (Important 2): set (under g_supervise_mu) when a
     * one_for_all/rest_for_one delayed batch restart has been scheduled but
     * not yet run, cleared by delayed_restart_thread immediately before it
     * runs the strategy. While set, a DIFFERENT child of this supervisor
     * crashing (whether its own first crash or a repeat) must not schedule
     * or run another batch restart — the pending one is widened (see
     * pending_min_child_idx below) to cover every child that crashed during
     * the pending window, including this newly-crashed one, once it fires.
     * Never touched for one_for_one (a dead slot can't re-crash, so there's
     * nothing to double-restart). Zeroed by calloc at meta creation. */
    int                          delayed_batch_pending;
    /* Set for the entire in-flight duration of a SYNCHRONOUS batch restart
     * (one_for_all / rest_for_one, streak == 1, delay == 0), so a second
     * first-time crash of a DIFFERENT child cannot call a strategy function
     * concurrently against the same sup_children array. delayed_batch_pending
     * does not cover this: a streak==1 crash never claims it (by design —
     * round 1 kept every first crash on the original synchronous path), so
     * two first crashes both observed "not pending" and both ran a strategy.
     * Mutated only under g_supervise_mu; zeroed by calloc. */
    int                          batch_restart_in_flight;
    /* Task 16 fix-up (review round 2): the lowest sup_children index among
     * all crashes that occurred while a batch restart was pending —
     * initialized to the index that CLAIMED delayed_batch_pending, then
     * lowered (never raised) by every crash that arrives while it's set.
     * one_for_all ignores this (it always restarts every child regardless
     * of index); rest_for_one's restart window is [child_idx, n), so a
     * lower-index intervening crash MUST widen the eventual restart down to
     * its own index or that child is silently skipped by the batch
     * restart's index range and, since a dead slot never crashes again on
     * its own, stays dead forever. Read (and reset) by delayed_restart_
     * thread under the same leaf-lock section that clears
     * delayed_batch_pending, immediately before running the strategy.
     * Meaningless while both delayed_batch_pending and
     * batch_restart_in_flight are 0; zeroed by calloc. The synchronous
     * in-flight path (batch_restart_in_flight) seeds, widens and absorbs
     * through this exact same field pair. */
    int                          pending_min_child_idx;
    /* Task 16 fix-up (review round 3): incremented under g_supervise_mu on
     * EVERY crash dropped via skip_due_to_pending while a batch restart is
     * pending — not just ones that lower pending_min_child_idx. A crash of
     * a slot at an index >= the index the in-flight strategy pass is
     * about to use (e.g. a freshly-respawned sibling from an EARLIER pass
     * of the SAME in-flight restart, crashing again before the flag is
     * cleared) is a real drop that needs its own follow-up pass, but it
     * does NOT lower pending_min_child_idx — the min-idx-only absorb check
     * missed exactly this case (that incarnation stayed dead forever,
     * uncovered by any restart window, the same symptom class the
     * min-idx widening fixed, just at same/higher indexes). delayed_
     * restart_thread snapshots this counter before each strategy pass and
     * compares it after; any advance means loop again. The synchronous
     * batch_restart_in_flight path runs the identical absorb loop inline
     * in march_supervisor_notify. Meaningless while both
     * delayed_batch_pending and batch_restart_in_flight are 0; zeroed by
     * calloc. */
    int64_t                      pending_drop_count;
    /* Named-registry reverse index (Task 3): every name currently registered
     * to THIS actor, as plain strdup'd C strings — NOT a March List(String),
     * see the design comment above registry_init_once for why. Grown one at
     * a time via realloc (a handful of names per actor, not a hot path).
     * Walked by registry_retire_actor (Task 5) so a dying actor's names are
     * dropped from the forward table in O(names held) rather than a full
     * table scan. Zeroed by calloc at meta creation. */
    char                       **reg_names;
    int                          reg_name_count;
} march_actor_meta;

static void activate_actor_green_thread(march_actor_meta *meta);

/* The public alive word is shared by kill/monitor/registry/send paths on
 * different scheduler threads. Keep every runtime access atomic; generated
 * code initializes it before the actor is published and thereafter only the
 * runtime mutates it. */
static inline int64_t actor_alive_load(void *actor) {
    return __atomic_load_n(&((int64_t *)actor)[3], __ATOMIC_ACQUIRE);
}

static inline void actor_alive_store(void *actor, int64_t alive) {
    __atomic_store_n(&((int64_t *)actor)[3], alive, __ATOMIC_RELEASE);
}

/* Global side table: actor ptr → march_actor_meta, LIVE metas only.
 * A meta is linked here from its creation until its actor's death claim
 * (do_actor_death, under g_tbl_mu), which unlinks it.  So a chain is
 * O(live actors / MARCH_SCHED_BUCKETS) long, not O(actors ever spawned):
 * before the metas PR every meta stayed linked forever, and march_send's
 * find_meta walked 60x slower after 200k churned actors (the todo's
 * "Analysis, 2026-09-22").
 *
 * Readers walk lock-free, inside a critical section: acquire-load the head,
 * then each tbl_next.  Insertion writes a node's tbl_next before the release
 * store that publishes it.  An unlink (under g_tbl_mu) swings the
 * predecessor's link past the node with a release store and leaves the
 * node's own tbl_next intact, so a reader standing on it walks on; the node
 * is freed only after its grace period.  Every walker that also touches
 * mutable per-meta fields (find_or_create_meta, the hot-reload snapshot,
 * demonitor) holds g_tbl_mu. */
static _Atomic(march_actor_meta *) g_actor_tbl[MARCH_SCHED_BUCKETS];
static pthread_mutex_t    g_tbl_mu = PTHREAD_MUTEX_INITIALIZER;

/* Sequential Pid index counter: each spawned actor gets a unique integer. */
static _Atomic int64_t g_next_pid_index = 0;

/* pid_index -> march_pid_entry: dense and grow-only, the same shape and
 * accepted cost as the scheduler's g_registry (pid_index is a dense
 * counter).  Two levels so it never moves: a fixed top array of chunk
 * pointers (zero pages until touched) and 4096-entry chunks allocated on
 * first use.  Chunks and entries are never freed; a slot is written once,
 * by march_spawn_common under g_tbl_mu, with a release store, and read
 * lock-free with acquire loads. */
#define MARCH_PID_CHUNK_BITS 12
#define MARCH_PID_CHUNK      ((int64_t)1 << MARCH_PID_CHUNK_BITS)
#define MARCH_PID_CHUNKS     ((int64_t)1 << 18)       /* 2^30 pids */
static _Atomic(_Atomic(march_pid_entry *) *) g_pid_chunks[MARCH_PID_CHUNKS];

static inline int64_t pe_pid(march_pid_entry *pe) {
    return atomic_load_explicit(&pe->pid_index, memory_order_relaxed);
}

/* A pid index for display and for the Int a program stores: 0 for a record
 * not spawned yet, as before tombstones existed. */
static inline int64_t pe_pid_or_0(march_pid_entry *pe) {
    int64_t p = pe ? pe_pid(pe) : 0;
    return p < 0 ? 0 : p;
}

/* The tombstone for [pid_index], or NULL if no actor was ever given it. */
static march_pid_entry *pid_entry(int64_t pid_index) {
    if (pid_index < 0 || pid_index >= MARCH_PID_CHUNK * MARCH_PID_CHUNKS)
        return NULL;
    _Atomic(march_pid_entry *) *chunk = atomic_load_explicit(
        &g_pid_chunks[pid_index >> MARCH_PID_CHUNK_BITS], memory_order_acquire);
    if (!chunk) return NULL;
    return atomic_load_explicit(&chunk[pid_index & (MARCH_PID_CHUNK - 1)],
                                memory_order_acquire);
}

/* Caller holds g_tbl_mu (the only writer). */
static void pid_entry_publish_locked(march_pid_entry *pe) {
    int64_t pid_index = pe_pid(pe);
    int64_t ci = pid_index >> MARCH_PID_CHUNK_BITS;
    if (ci >= MARCH_PID_CHUNKS) {
        fputs("march: pid index space exhausted\n", stderr);
        exit(1);
    }
    _Atomic(march_pid_entry *) *chunk =
        atomic_load_explicit(&g_pid_chunks[ci], memory_order_relaxed);
    if (!chunk) {
        chunk = (_Atomic(march_pid_entry *) *)calloc((size_t)MARCH_PID_CHUNK,
                                                     sizeof *chunk);
        if (!chunk) { fputs("march: out of memory (pid table)\n", stderr); exit(1); }
        atomic_store_explicit(&g_pid_chunks[ci], chunk, memory_order_release);
    }
    atomic_store_explicit(&chunk[pid_index & (MARCH_PID_CHUNK - 1)], pe,
                          memory_order_release);
}

/* Dead actor, by record address -> its tombstone.  The cold path: consulted
 * only after a g_actor_tbl miss, by the readers that need a DEAD actor's
 * identity from a record the caller still holds (Pid(n) display, a monitor
 * on an already-dead target, pid_index_of).  One link per distinct address,
 * repointed at the newest tombstone when a later incarnation at the same
 * address dies: a caller holding a counted reference to a dead record is
 * always asking about the newest incarnation there, because the address
 * cannot be reused while the record is held.  So the table is bounded by
 * the distinct addresses dead actors have occupied (roughly peak heap), not
 * by churn.
 *
 * Written under g_tbl_mu.  Grows by rebuilding into a new table with new
 * links, publishing it, and retiring the old one to march_reclaim; readers
 * walk it inside a critical section. */
typedef struct march_tomb_link {
    void                               *addr;
    _Atomic(march_pid_entry *)          pe;
    _Atomic(struct march_tomb_link *)   next;
} march_tomb_link;

typedef struct {
    size_t                               nb;      /* power of two */
    size_t                               count;
    _Atomic(march_tomb_link *)           b[];
} march_tomb_tbl;

static _Atomic(march_tomb_tbl *) g_tomb = NULL;

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

#ifdef MARCH_CAP_WRITE_SCOPES
#include <limits.h>
/* Scoped IO.FileWrite grants as the compiler normalized them: LEXICALLY,
 * because the build machine's filesystem is not the deployment machine's.
 * Seatbelt matches a subpath against the path AFTER symlink resolution, so a
 * lexical "/tmp/x" would match nothing on macOS (/tmp -> /private/tmp) and
 * deny every in-scope write.  The scopes are therefore resolved HERE, on the
 * machine that runs the program, and their subpath clauses appended to the
 * compile-time profile before sandbox_init. */
static const char *const march_cap_write_scopes[] = { MARCH_CAP_WRITE_SCOPES, NULL };

/* Append one path component to the absolute path in out (capacity outsz),
 * resolving "." and ".." lexically.  Returns 0 on overflow. */
static int march_scope_push(char *out, size_t outsz, const char *comp, size_t n) {
    if (n == 0 || (n == 1 && comp[0] == '.')) return 1;
    if (n == 2 && comp[0] == '.' && comp[1] == '.') {
        char *slash = strrchr(out, '/');
        if (slash == out) out[1] = '\0';        /* never above "/" */
        else if (slash) *slash = '\0';
        return 1;
    }
    size_t len = strlen(out);
    int need_sep = !(len > 0 && out[len - 1] == '/');
    if (len + (size_t)need_sep + n + 1 > outsz) return 0;
    if (need_sep) out[len++] = '/';
    memcpy(out + len, comp, n);
    out[len + n] = '\0';
    return 1;
}

/* Resolve a scope against THIS filesystem.  The scope itself may not exist
 * yet -- writing a new file or directory under a scope is the common case --
 * so realpath() the LONGEST EXISTING PREFIX and re-append the remaining
 * components lexically.  A scope that is itself a symlink resolves to its
 * target.  Falls back to the lexical text if nothing resolves (cannot happen
 * for an absolute path: "/" always exists) or the result would not fit. */
static void march_scope_resolve(const char *scope, char *out, size_t outsz) {
    char prefix[PATH_MAX];
    char resolved[PATH_MAX];
    size_t len = strlen(scope);
    size_t cut;
    const char *p;
    if (len == 0 || scope[0] != '/' || len >= sizeof prefix) goto lexical;
    memcpy(prefix, scope, len + 1);
    cut = len;                                  /* prefix = scope[0, cut) */
    for (;;) {
        prefix[cut] = '\0';
        if (realpath(cut == 0 ? "/" : prefix, resolved)) break;
        if (cut == 0) goto lexical;
        while (cut > 0 && prefix[cut - 1] != '/') cut--;
        if (cut > 0) cut--;                     /* drop the separator too */
    }
    if (strlen(resolved) + 1 > outsz) goto lexical;
    strcpy(out, resolved);
    p = scope + cut;
    while (*p) {
        const char *e;
        while (*p == '/') p++;
        e = p;
        while (*e && *e != '/') e++;
        if (!march_scope_push(out, outsz, p, (size_t)(e - p))) goto lexical;
        p = e;
    }
    return;
lexical:
    snprintf(out, outsz, "%s", scope);
}
#endif

void march_sandbox_install(void) {
    char *err = NULL;
    const char *profile = MARCH_CAP_PROFILE;
#ifdef MARCH_CAP_WRITE_SCOPES
    /* Worst case per scope: the clause text plus every path byte escaped. */
    size_t nscopes = 0, cap, n;
    char *built;
    for (const char *const *sp = march_cap_write_scopes; *sp; sp++) nscopes++;
    cap = strlen(MARCH_CAP_PROFILE) + 1 + nscopes * (64 + 2 * PATH_MAX);
    built = malloc(cap);
    if (!built) {
        fprintf(stderr, "march: capability sandbox: out of memory; refusing to "
                        "run uncontained\n");
        exit(70);
    }
    n = (size_t)snprintf(built, cap, "%s", MARCH_CAP_PROFILE);
    for (const char *const *sp = march_cap_write_scopes; *sp; sp++) {
        char res[PATH_MAX];
        march_scope_resolve(*sp, res, sizeof res);
        n += (size_t)snprintf(built + n, cap - n, "(allow file-write* (subpath \"");
        for (const char *c = res; *c; c++) {    /* SBPL string escapes */
            if (*c == '"' || *c == '\\') built[n++] = '\\';
            built[n++] = *c;
        }
        n += (size_t)snprintf(built + n, cap - n, "\"))");
    }
    profile = built;   /* installed for the life of the process; never freed */
#endif
    if (sandbox_init(profile, 0, &err) != 0) {
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
 *   IO.NetListen  -> bind/listen denied                  ENFORCED
 *                    (separate from IO.Network: holding only IO.NetConnect
 *                    allows socket() for connect(), which is also the first
 *                    step of a listener, so bind/listen need their own deny)
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

#ifdef MARCH_CAP_DENY_LISTEN
    /* A NetConnect-only program (an HTTP client) needs socket() + connect();
     * without these two it could also accept connections.  bind() covers
     * AF_UNIX as well, which is correct: a Unix-domain listener is still a
     * listener.  Threads created BEFORE this call (the hot-reload server,
     * started in @main ahead of march_spawn_main) are not covered, since
     * PR_SET_SECCOMP filters only the calling thread and its later
     * children. */
    DENY_NR(__NR_bind);
    DENY_NR(__NR_listen);
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

/* Forward declaration: defined below (near march_actor_msg_dispose /
 * march_timer_token_is_cancelled / march_timer_token_release), called from
 * BOTH scheduler-lazy-init sites below that guard on g_sched_initialized's
 * 0->1 CAS (this function itself, and march_spawn_common's) — see this
 * function's own definition for why a single call site is not enough. */
static void march_register_sched_callbacks(void);

static void spawn_main_impl(void (*fn)(void), int force_pin) {
    /* Drop privileges before the scheduler starts and before any user code
     * runs.  No-op unless built with --cap-sandbox. */
    march_sandbox_install();
    int expected = 0;
    if (atomic_compare_exchange_strong_explicit(
            &g_sched_initialized, &expected, 1,
            memory_order_acq_rel, memory_order_acquire)) {
        march_sched_init();
        /* march_spawn_main is the FIRST lazy-init site to actually run in a
         * normal compiled program: the emitted @main calls it (via
         * march_spawn_main(@march_main), llvm_toplevel.ml) unconditionally,
         * strictly before user code -- including the first actor spawn --
         * ever executes. That means it, not march_spawn_common's block
         * below, wins the g_sched_initialized 0->1 CAS in practice, so the
         * scheduler callback registrations MUST also happen here or they
         * never run in a compiled program at all: march_spawn_common's own
         * registration call is dead code once this branch has already
         * flipped the flag. Discovered while wiring send_after/cancel_timer
         * (specs/progress/2026-08-12-language-level-timers.md) -- cancel_timer
         * silently never took effect because march_sched_set_timer_token_ops
         * was never called, which on inspection turned out to be true of
         * march_sched_set_msg_dtor too (Task 14's DROP_NEW/DROP_OLD/dead-
         * proc-reap message disposal), pre-existing and unrelated to this
         * feature. Both are registered from the same helper so neither can
         * drift out of sync with the other again. */
        march_register_sched_callbacks();
    }
    /* MARCH_PIN_MAIN=1: run `main` only on scheduler 0, which lives on this
     * OS thread (the process main thread).  Needed by libraries that demand
     * the main thread (Cocoa/GLFW window creation) while the other scheduler
     * workers keep running Tasks/pmap.  Opt-in: an unpinned main can be
     * dispatched by any worker, which is the better default for servers and
     * lets the yielded-main / steal-from-others fairness logic stay as is.
     * Tasks spawned by main are not pinned (see march_sched_spawn_pinned). */
    const char *pin = getenv("MARCH_PIN_MAIN");
    int want_pin = force_pin
                   || (pin && *pin && strcmp(pin, "0") != 0);
    /* The env var can only turn pinning ON, never off a build that asked for
       it: a program compiled --pin-main needs the main thread to run at all
       (Cocoa/GLFW), so honouring MARCH_PIN_MAIN=0 there would break it in a
       way the user cannot diagnose from the message they would not get. */
    /* `main` is the one unit that follows the current code version instead
     * of pinning an epoch (march_proc.code_epoch): it runs for the process
     * lifetime and never reaches a marker, so a pinned main would keep its
     * epoch alive for ever and no version it uses could ever be retired. */
    march_sched_spawn_main(main_fn_green_thread, (void *)(uintptr_t)fn,
                           want_pin);
}

/* The ordinary entry: `main` may be dispatched by any worker, which is the
   right default for servers and keeps the yielded-main / steal-from-others
   fairness logic as is. MARCH_PIN_MAIN=1 still opts in at run time. */
void march_spawn_main(void (*fn)(void)) { spawn_main_impl(fn, 0); }

/* The --pin-main entry: the compiled program itself carries the requirement,
   so a GUI binary that must own the process main thread no longer depends on
   being launched with an environment variable set -- which a double-clickable
   app cannot rely on. The runtime is compiled once into a cached .so, so a
   per-program -D define does not work; the choice has to live in the emitted
   entry point, which is why this is a second symbol rather than a flag.
   specs/progress/2026-09-17-pin-main-compiler-switch.md */
void march_spawn_main_pinned(void (*fn)(void)) { spawn_main_impl(fn, 1); }

/* Forward declarations */
int64_t march_monitor(void *watcher, void *target);

/* ── Side-table helpers ──────────────────────────────────────────── */

static unsigned int actor_bucket(void *actor) {
    return (unsigned int)(((uintptr_t)actor >> 4) % MARCH_SCHED_BUCKETS);
}

/* green_thread once the actor's own thread has finished with its proc.
 * Never a dereferenceable pointer; meta_gt() maps it to NULL. */
#define MARCH_GT_EXITED ((march_proc *)(uintptr_t)1)

/* The proc running [m]'s loop, or NULL (not activated yet, or exited).
 * Caller is inside a critical section; the proc is valid only inside it. */
static inline march_proc *meta_gt(march_actor_meta *m) {
    march_proc *gt = atomic_load_explicit(&m->green_thread, memory_order_acquire);
    return gt == MARCH_GT_EXITED ? NULL : gt;
}

/* Look up the LIVE meta for an actor (NULL if it was never spawned, or has
 * died).  Lock-free; the CALLER MUST BE INSIDE A CRITICAL SECTION, and the
 * result is valid only inside it unless pinned (meta_tryget).  See
 * g_actor_tbl for why the walk is safe against a concurrent unlink. */
static march_actor_meta *find_meta(void *actor) {
    if (!IS_HEAP_PTR(actor)) return NULL;
    unsigned int b = actor_bucket(actor);
    for (march_actor_meta *m = atomic_load_explicit(&g_actor_tbl[b],
                                                     memory_order_acquire);
         m; m = atomic_load_explicit(&m->tbl_next, memory_order_acquire)) {
        if (m->actor == actor) return m;
    }
    return NULL;
}

static void meta_free(void *p) {
    march_actor_meta *m = (march_actor_meta *)p;
    atomic_fetch_add_explicit(&march_stat_counters[MARCH_STAT_METAS_FREED], 1,
                              memory_order_relaxed);
    for (int i = 0; i < m->reg_name_count; i++) free(m->reg_names[i]);
    free(m->reg_names);
    for (int i = 0; i < m->sup_num_children; i++) {
        march_sup_child *c = &m->sup_children[i];
        for (int k = 0; k < c->pending_name_count; k++) free(c->pending_names[k]);
        free(c->pending_names);
        /* The slot's owned reference (march_actor_register_child). */
        march_decrc(c->spawn_clo);
    }
    free(m->sup_children);
    free(m->sup_restart_ts);
    /* Both lists are detached at the death claim; a meta that never died (a
     * C-test stand-in) has nothing here that anything else still owns. */
    for (march_cleanup_node *c = m->cleanup_head, *n; c; c = n) { n = c->next; free(c); }
    for (march_monitor_node *mn = m->monitor_head, *n; mn; mn = n) { n = mn->next; free(mn); }
    free(m);
}

/* Drop one reference; the last one retires the meta. */
static void meta_put(march_actor_meta *m) {
    if (!m) return;
    int64_t prev = atomic_fetch_sub_explicit(&m->refs, 1, memory_order_acq_rel);
    if (prev == 1) {
        atomic_fetch_add_explicit(&march_stat_counters[MARCH_STAT_METAS_RETIRED],
                                  1, memory_order_relaxed);
        march_reclaim_retire(m, meta_free);
    }
    else if (prev <= 0) {
        fprintf(stderr, "march: actor meta reference underflow (%lld)\n",
                (long long)prev);
        abort();
    }
}

/* Take a reference on a meta found by lookup.  Inside a critical section
 * (so [m] cannot be freed under us); fails once the count has reached zero,
 * i.e. once the meta is retired.  A pinned meta may be kept across context
 * switches and waits until meta_put. */
static int meta_tryget(march_actor_meta *m) {
    int64_t r = atomic_load_explicit(&m->refs, memory_order_relaxed);
    while (r > 0) {
        if (atomic_compare_exchange_weak_explicit(&m->refs, &r, r + 1,
                memory_order_acq_rel, memory_order_relaxed))
            return 1;
    }
    return 0;
}

/* Unlink [m] from g_actor_tbl.  Caller holds g_tbl_mu.  The table's
 * reference passes to the caller.  m's own tbl_next is left intact for any
 * reader standing on it. */
static void meta_unlink_locked(march_actor_meta *m) {
    if (!m->linked) return;
    unsigned int b = actor_bucket(m->actor);
    _Atomic(march_actor_meta *) *pp = &g_actor_tbl[b];
    for (march_actor_meta *cur = atomic_load_explicit(pp, memory_order_relaxed);
         cur; cur = atomic_load_explicit(pp, memory_order_relaxed)) {
        if (cur == m) {
            atomic_store_explicit(pp,
                atomic_load_explicit(&m->tbl_next, memory_order_relaxed),
                memory_order_release);
            break;
        }
        pp = &cur->tbl_next;
    }
    m->linked = 0;
}

static size_t tomb_hash(void *addr, size_t nb) {
    return (size_t)(((uintptr_t)addr >> 4) * UINT64_C(0x9E3779B97F4A7C15) >> 20)
           & (nb - 1);
}

static void tomb_tbl_free(void *p) {
    march_tomb_tbl *t = (march_tomb_tbl *)p;
    for (size_t i = 0; i < t->nb; i++) {
        march_tomb_link *l = atomic_load_explicit(&t->b[i], memory_order_relaxed);
        while (l) {
            march_tomb_link *n = atomic_load_explicit(&l->next, memory_order_relaxed);
            free(l);
            l = n;
        }
    }
    free(t);
}

static march_tomb_tbl *tomb_tbl_new(size_t nb) {
    march_tomb_tbl *t = (march_tomb_tbl *)calloc(1, sizeof *t + nb * sizeof t->b[0]);
    if (!t) { fputs("march: out of memory (tombstone table)\n", stderr); exit(1); }
    t->nb = nb;
    return t;
}

static march_tomb_link *tomb_link_new(void *addr, march_pid_entry *pe,
                                      march_tomb_link *next) {
    march_tomb_link *l = (march_tomb_link *)malloc(sizeof *l);
    if (!l) { fputs("march: out of memory (tombstone link)\n", stderr); exit(1); }
    l->addr = addr;
    atomic_init(&l->pe, pe);
    atomic_init(&l->next, next);
    return l;
}

/* Record [pe] as the tombstone for its address.  Caller holds g_tbl_mu. */
static void tomb_insert_locked(march_pid_entry *pe) {
    march_tomb_tbl *t = atomic_load_explicit(&g_tomb, memory_order_relaxed);
    if (!t) {
        t = tomb_tbl_new(1024);
        atomic_store_explicit(&g_tomb, t, memory_order_release);
    }
    size_t h = tomb_hash(pe->addr, t->nb);
    for (march_tomb_link *l = atomic_load_explicit(&t->b[h], memory_order_relaxed);
         l; l = atomic_load_explicit(&l->next, memory_order_relaxed)) {
        if (l->addr == pe->addr) {
            atomic_store_explicit(&l->pe, pe, memory_order_release);
            return;
        }
    }
    if (t->count + 1 > t->nb * 2) {
        /* Rebuild into a table twice the size with fresh links (readers may
         * be walking the old ones), publish it, retire the old one. */
        march_tomb_tbl *n = tomb_tbl_new(t->nb * 2);
        for (size_t i = 0; i < t->nb; i++) {
            for (march_tomb_link *l = atomic_load_explicit(&t->b[i], memory_order_relaxed);
                 l; l = atomic_load_explicit(&l->next, memory_order_relaxed)) {
                size_t nh = tomb_hash(l->addr, n->nb);
                march_tomb_link *c = tomb_link_new(l->addr,
                    atomic_load_explicit(&l->pe, memory_order_relaxed),
                    atomic_load_explicit(&n->b[nh], memory_order_relaxed));
                atomic_store_explicit(&n->b[nh], c, memory_order_relaxed);
            }
        }
        n->count = t->count;
        atomic_store_explicit(&g_tomb, n, memory_order_release);
        march_reclaim_retire(t, tomb_tbl_free);
        t = n;
        h = tomb_hash(pe->addr, t->nb);
    }
    march_tomb_link *l = tomb_link_new(pe->addr, pe,
        atomic_load_explicit(&t->b[h], memory_order_relaxed));
    atomic_store_explicit(&t->b[h], l, memory_order_release);
    t->count++;
}

/* The tombstone of the newest DEAD actor at [addr], or NULL.  Caller is
 * inside a critical section (the table may be retired under a grower); the
 * entry itself is never freed. */
static march_pid_entry *tomb_lookup(void *addr) {
    march_tomb_tbl *t = atomic_load_explicit(&g_tomb, memory_order_acquire);
    if (!t) return NULL;
    for (march_tomb_link *l = atomic_load_explicit(&t->b[tomb_hash(addr, t->nb)],
                                                   memory_order_acquire);
         l; l = atomic_load_explicit(&l->next, memory_order_acquire)) {
        if (l->addr == addr) return atomic_load_explicit(&l->pe, memory_order_acquire);
    }
    return NULL;
}

/* The tombstone of the actor at [actor], live or dead, or NULL if it never
 * had a meta.  Caller is inside a critical section. */
static march_pid_entry *pid_entry_of_addr(void *actor) {
    march_actor_meta *m = find_meta(actor);
    if (m) return m->pe;
    return IS_HEAP_PTR(actor) ? tomb_lookup(actor) : NULL;
}

/* A new meta for [actor], with its tombstone (pid index -1 until the spawn
 * assigns it), linked at the head of its bucket.  Caller holds g_tbl_mu. */
static march_actor_meta *meta_new_locked(void *actor) {
    unsigned int b = actor_bucket(actor);
    march_actor_meta *m = (march_actor_meta *)calloc(1, sizeof(march_actor_meta));
    march_pid_entry *pe = (march_pid_entry *)calloc(1, sizeof *pe);
    if (!m || !pe) { fputs("march: out of memory (actor meta)\n", stderr); exit(1); }
    pe->addr = actor;
    atomic_init(&pe->pid_index, -1);
    atomic_init(&pe->live, m);
    m->actor = actor;
    m->pe = pe;
    atomic_init(&m->green_thread, NULL);
    atomic_init(&m->refs, 1);          /* the table's */
    m->linked = 1;
    /* tbl_next is written BEFORE the release store below publishes `m` as
     * the new bucket head, so any lock-free find_meta reader that observes
     * `m` via the acquire load also observes a fully-initialized node. */
    atomic_init(&m->tbl_next, atomic_load_explicit(&g_actor_tbl[b],
                                                   memory_order_relaxed));
    atomic_store_explicit(&g_actor_tbl[b], m, memory_order_release);
    return m;
}

/* Look up, or lazily create, the LIVE meta for an actor record.  Returns
 * NULL for a record that has already died: under g_tbl_mu a spawned record's
 * alive word is 0 only once its death is claimed (and its meta unlinked), and
 * compiled code allocates a record with alive = true, so creating here would
 * link a meta nobody will ever unlink.  Caller is inside a critical section
 * (the result is valid only inside it). */
static march_actor_meta *find_or_create_meta(void *actor) {
    unsigned int b = actor_bucket(actor);
    pthread_mutex_lock(&g_tbl_mu);
    for (march_actor_meta *m = atomic_load_explicit(&g_actor_tbl[b],
                                                     memory_order_relaxed);
         m; m = atomic_load_explicit(&m->tbl_next, memory_order_relaxed)) {
        if (m->actor == actor) { pthread_mutex_unlock(&g_tbl_mu); return m; }
    }
    if (!actor_alive_load(actor)) { pthread_mutex_unlock(&g_tbl_mu); return NULL; }
    march_actor_meta *m = meta_new_locked(actor);
    pthread_mutex_unlock(&g_tbl_mu);
    return m;
}

/* A pinned meta plus a counted reference to its record: what a cold holder
 * needs to keep using an actor across context switches (supervision, stop).
 * Taken under g_tbl_mu while the meta is linked, which is what makes the
 * record reference safe to take (see march_actor_meta's LIFETIME). */
typedef struct { march_actor_meta *m; void *actor; } meta_pin;

static meta_pin meta_pin_locked(march_actor_meta *m) {
    meta_pin p = { NULL, NULL };
    if (!m || !m->linked || !meta_tryget(m)) return p;
    march_incrc(m->actor);
    p.m = m;
    p.actor = m->actor;
    return p;
}

static meta_pin meta_pin_pe(march_pid_entry *pe) {
    meta_pin p = { NULL, NULL };
    if (!pe) return p;
    pthread_mutex_lock(&g_tbl_mu);
    p = meta_pin_locked(atomic_load_explicit(&pe->live, memory_order_relaxed));
    pthread_mutex_unlock(&g_tbl_mu);
    return p;
}

static void meta_unpin(meta_pin p) {
    if (!p.m) return;
    march_decrc(p.actor);
    meta_put(p.m);
}

/* ── Named process registry ───────────────────────────────────────────────
 * Forward mapping (name -> actor) lives in a Vault table the RUNTIME owns, so
 * it inherits Vault's concurrent reads and is inspectable by the same tooling
 * as any other table — and so `Actor.whereis` needs no capability, since no
 * March-level naming call happens.
 *
 * The reverse index (actor -> its names) is the march_actor_meta.reg_names
 * array above, NOT a second Vault table: it exists only so death cleanup is
 * O(names held) instead of a full table walk per death (the churn scenario
 * kills 40k actors), no user inspects it, and building/refcounting a
 * List(String) from C to store as a Vault value is real machinery for no
 * gain.
 *
 * march_vault_get returns a NICHE-encoded Option(ptr): None = NULL,
 * Some(v) = v itself, incrc'd by the callee (see march_vault_get / the
 * march_vault_update comment on the same convention). Every use below that
 * receives a non-NULL result therefore owns exactly one extra reference that
 * must be either handed onward (as a return value) or explicitly decrc'd. */
#define MARCH_REGISTRY_TABLE_NAME "$actor_registry"

static void *g_registry_tbl = NULL;
static pthread_once_t g_registry_once = PTHREAD_ONCE_INIT;

static void registry_init_once(void) {
    g_registry_tbl = march_vault_new(march_string_lit(MARCH_REGISTRY_TABLE_NAME,
                                                        (int64_t)strlen(MARCH_REGISTRY_TABLE_NAME)));
    /* registry table itself is never released for the process lifetime. */
    march_incrc(g_registry_tbl);
}
static void *registry_tbl(void) {
    pthread_once(&g_registry_once, registry_init_once);
    return g_registry_tbl;
}

/* Serializes march_actor_register, march_actor_unregister, and
 * registry_retire_actor — the three operations that mutate a reg_names
 * array (realloc/free) or need register's get-then-set to be atomic
 * (otherwise two threads racing to register the same absent name can both
 * observe "absent" and both return 1, leaving two LIVE actors both
 * believing they hold the name — see the Task 3 review's Critical/
 * Important fix-up). A STRICT LEAF LOCK: everything called while it is
 * held — Vault ops (march_vault_get/set/drop, all pure C per Task 1's
 * invariant), malloc/strdup/free — is plain C that cannot park a green
 * thread, so this never nests under or interleaves with a scheduler
 * yield. Same shape as g_supervise_mu serializing sup_children (another
 * realloc-grown per-meta array). march_actor_whereis and
 * march_actor_registered are reads and stay OUTSIDE this lock on purpose,
 * to keep Vault's own striped-read concurrency (Task 1) intact for the
 * hot lookup path. */
static pthread_mutex_t g_registry_mu = PTHREAD_MUTEX_INITIALIZER;

/* Append a strdup'd copy of [name] to [m]'s reverse index. */
static void meta_add_name(march_actor_meta *m, const char *name) {
    m->reg_names = (char **)realloc(m->reg_names,
                                     sizeof(char *) * (size_t)(m->reg_name_count + 1));
    if (!m->reg_names) { fputs("march: out of memory (registry)\n", stderr); exit(1); }
    m->reg_names[m->reg_name_count++] = strdup(name);
}

/* Remove [name] from [m]'s reverse index, if present (order not preserved). */
static void meta_remove_name(march_actor_meta *m, const char *name) {
    for (int i = 0; i < m->reg_name_count; i++) {
        if (strcmp(m->reg_names[i], name) == 0) {
            free(m->reg_names[i]);
            m->reg_names[i] = m->reg_names[m->reg_name_count - 1];
            m->reg_name_count--;
            return;
        }
    }
}

/* march_actor_register(name, actor) -> 1 on success, 0 if the name is held
 * by a LIVE actor, or if [actor] itself is dead. A stale entry left behind
 * by a dead actor is silently overwritten (that's what makes the name
 * reusable after the incarnation that held it dies) — and the whole
 * get-then-set-then-reindex sequence runs under g_registry_mu so the
 * overwrite is atomic with respect to a second racing register AND with
 * respect to registry_retire_actor running for the stale actor. Critically,
 * the overwrite path also removes the name from the STALE actor's own
 * reverse index before handing it to the new actor: without that, the
 * stale actor's eventual retire would still find the name in its index and
 * drop it from the table out from under the new (live) actor that now
 * legitimately owns it — see the Task 3 review's Critical fix-up. */
int64_t march_actor_register(void *name_str, void *actor) {
    if (!IS_HEAP_PTR(actor) || !actor_alive_load(actor)) return 0;   /* dead/invalid */

    pthread_mutex_lock(&g_registry_mu);

    void *existing = march_vault_get(registry_tbl(), name_str);
    if (existing != NULL) {
        int taken = IS_HEAP_PTR(existing) && actor_alive_load(existing);
        if (taken) {
            march_decrc(existing);
            pthread_mutex_unlock(&g_registry_mu);
            return 0;
        }
        /* stale entry for a dead actor: retire it from ITS OWN reverse
         * index first (belt), then fall through and overwrite the table
         * entry. registry_retire_actor's compare-and-drop (braces) is the
         * other half of closing this race for any path that isn't this
         * one. */
        march_reclaim_enter();   /* stale_m: resolved and used inside */
        march_actor_meta *stale_m = find_meta(existing);
        if (stale_m) {
            char stale_scratch[MARCH_SSO_MAX + 1];
            meta_remove_name(stale_m, march_str_data(name_str, stale_scratch));
        }
        march_reclaim_exit();
        march_decrc(existing);
    }

    /* The meta is resolved (and, for a record not yet spawned -- a C-level
     * stand-in -- created) BEFORE the forward entry is written: NULL means
     * [actor] died since the liveness check above, and a dead actor gets no
     * name.  meta_add_name happens under g_registry_mu, which the dying
     * actor's registry_retire_meta also takes, so either the retire sees
     * this name or this register sees the meta already unlinked. */
    march_reclaim_enter();   /* m: resolved and used inside */
    march_actor_meta *m = find_or_create_meta(actor);
    if (!m) {
        march_reclaim_exit();
        pthread_mutex_unlock(&g_registry_mu);
        return 0;
    }
    march_vault_set(registry_tbl(), name_str, actor);
    char scratch[MARCH_SSO_MAX + 1];
    meta_add_name(m, march_str_data(name_str, scratch));
    march_reclaim_exit();

    pthread_mutex_unlock(&g_registry_mu);
    return 1;
}

/* march_actor_unregister(name) -> 1 if a mapping was removed, 0 otherwise.
 * Removes the forward-table entry regardless of the owning actor's
 * liveness, and drops the name from that actor's reverse index if it still
 * has one. Runs under g_registry_mu: without it, the get-then-drop here
 * could race a concurrent register's get-then-set on the same name (TOCTOU
 * — see the Task 3 review's Important fix-up). */
int64_t march_actor_unregister(void *name_str) {
    pthread_mutex_lock(&g_registry_mu);

    void *existing = march_vault_get(registry_tbl(), name_str);
    if (existing == NULL) {
        pthread_mutex_unlock(&g_registry_mu);
        return 0;
    }

    if (IS_HEAP_PTR(existing)) {
        march_reclaim_enter();   /* m: resolved and used inside */
        march_actor_meta *m = find_meta(existing);
        if (m) {
            char scratch[MARCH_SSO_MAX + 1];
            meta_remove_name(m, march_str_data(name_str, scratch));
        }
        march_reclaim_exit();
    }
    march_decrc(existing);   /* release our extra ref from march_vault_get */

    march_vault_drop(registry_tbl(), name_str);
    pthread_mutex_unlock(&g_registry_mu);
    return 1;
}

/* march_actor_whereis(name) -> Some(actor) if registered AND alive, else
 * None. Liveness is checked here (not just table membership) because
 * cleanup and lookup race by nature — a stale entry for an actor that died
 * without deregistering must resolve to None, not a dangling handle. */
void *march_actor_whereis(void *name_str) {
    void *val = march_vault_get(registry_tbl(), name_str);
    if (val != NULL && IS_HEAP_PTR(val) && actor_alive_load(val)) {
        return val;   /* Some(actor): niche encoding, ref transferred to caller */
    }
    if (val != NULL) march_decrc(val);
    return NULL;   /* None */
}

/* march_actor_registered() -> List(String) of every currently-live
 * registered name. Walks the forward table's keys and filters to entries
 * whose actor is still alive, discarding stale ones (does not clean them
 * up — that's registry_retire_actor's job, driven by actual death). */
void *march_actor_registered(void) {
    void *keys = march_vault_keys(registry_tbl());   /* owned List(String) */
    void *result = march_alloc(16);                  /* Nil */

    void *p = keys;
    while (p && ((march_hdr *)p)->tag == 1) {
        void *next = *(void **)((char *)p + 24);
        void *key  = *(void **)((char *)p + 16);

        void *val = march_vault_get(registry_tbl(), key);
        int live = val != NULL && IS_HEAP_PTR(val) && actor_alive_load(val);
        if (val != NULL) march_decrc(val);

        if (live) {
            /* Reuse this Cons cell as the new head of [result] — we already
             * own both it and [key] from march_vault_keys, so no
             * incrc/decrc needed, just relink the tail. */
            *(void **)((char *)p + 24) = result;
            result = p;
        } else {
            march_decrc(key);
            march_decrc(p);
        }
        p = next;
    }
    return result;
}

/* Walk [m]'s reverse index (m belongs to [actor]), drop each name from the
 * forward table, and free the index.
 *
 * COMPARE-AND-DROP: a name is only dropped if the table's CURRENT value
 * for it is still [actor]. Ownership of a name can move to a different
 * (live) actor between this actor's death and retire actually running —
 * march_actor_register's stale-overwrite path — and blindly dropping by
 * name alone would then delete the NEW live actor's mapping out from under
 * it (see the Task 3 review's Critical fix-up; register's belt-side fix
 * removes the name from the stale actor's index at overwrite time, this is
 * the braces-side fix for every other path, including any future one).
 *
 * do_actor_death calls this with the meta it unlinked and still owns. */
static void registry_retire_meta(march_actor_meta *m, void *actor) {
    pthread_mutex_lock(&g_registry_mu);
    for (int i = 0; i < m->reg_name_count; i++) {
        void *key = march_string_lit(m->reg_names[i], (int64_t)strlen(m->reg_names[i]));
        void *cur = march_vault_get(registry_tbl(), key);
        if (cur == actor) march_vault_drop(registry_tbl(), key);
        if (cur != NULL) march_decrc(cur);
        march_decrc(key);   /* release our own ref from march_string_lit */
        free(m->reg_names[i]);
    }
    free(m->reg_names);   /* no-op if NULL */
    m->reg_names = NULL;
    m->reg_name_count = 0;
    pthread_mutex_unlock(&g_registry_mu);
}

/* The same, by actor pointer, for a C-level test that has no access to
 * march_actor_meta's layout (test/test_actor_registry.c).  No-op if [actor]
 * has no live meta.  Exported for that reason alone. */
void registry_retire_actor(void *actor) {
    march_reclaim_enter();   /* m: resolved and used inside */
    march_actor_meta *m = find_meta(actor);
    if (m) registry_retire_meta(m, actor);
    march_reclaim_exit();
}

/* Task 6: carry a supervised child's registered names, and its spawn-site
 * capability, across its restart.  Snapshots [m]'s reg_names (under
 * g_registry_mu: register/unregister/retire realloc or free the array on
 * other threads) and installs the copy on the restart's slot,
 * [sup]->sup_children[idx], under g_supervise_mu, replacing (and freeing)
 * any earlier stash.  march_respawn_child takes it.
 *
 * Two callers, each while it still knows for certain the child is about to
 * be restarted, and each strictly BEFORE registry_retire_meta frees the
 * original:
 *   - do_actor_death, for an actor dying with sup_pe still set (a
 *     directly-crashed/killed supervised actor, including the
 *     originally-crashed child of a one_for_all/rest_for_one batch).
 *   - march_one_for_all_restart / march_rest_for_one_restart, for each LIVE
 *     SIBLING they are about to kill and respawn.  They clear the sibling's
 *     sup_pe right after, purely to suppress the recursive
 *     march_supervisor_notify its death would otherwise fire, so
 *     do_actor_death's own gate is false for it (round-1 review finding:
 *     without this, a non-crashed sibling's name was lost on every
 *     one_for_all restart).
 *
 * The stash lives on the slot, not on the dead child's meta, because that
 * meta is freed once its death is processed and a delayed restart runs up
 * to the backoff cap later.  A stash that is never taken (restart budget
 * exhausted, the supervisor dies first) is freed with the supervisor's meta. */
static pthread_mutex_t g_supervise_mu;   /* defined with its contract below */

static void stash_child_for_restart(march_actor_meta *m,
                                    march_actor_meta *sup, int idx) {
    if (idx < 0 || idx >= sup->sup_num_children) return;
    char **names = NULL;
    int n = 0;
    pthread_mutex_lock(&g_registry_mu);
    if (m->reg_name_count > 0) {
        names = (char **)malloc(sizeof(char *) * (size_t)m->reg_name_count);
        if (!names) {
            fputs("march: out of memory (registry carry-forward)\n", stderr);
            exit(1);
        }
        for (int i = 0; i < m->reg_name_count; i++)
            names[i] = strdup(m->reg_names[i]);
        n = m->reg_name_count;
    }
    pthread_mutex_unlock(&g_registry_mu);
    void *cap = atomic_load_explicit(&m->spawn_cap, memory_order_acquire);

    pthread_mutex_lock(&g_supervise_mu);
    march_sup_child *c = &sup->sup_children[idx];
    char **old = c->pending_names;
    int old_n = c->pending_name_count;
    c->pending_names = names;
    c->pending_name_count = n;
    c->pending_spawn_cap = cap;
    pthread_mutex_unlock(&g_supervise_mu);
    for (int i = 0; i < old_n; i++) free(old[i]);
    free(old);
}

/* ── Actor green thread loop ─────────────────────────────────────── */

/* Each actor runs as a green thread that loops on recv→dispatch.
 * The thread parks (PROC_WAITING) when no messages are available and
 * is woken by march_sched_send when a message arrives. */
/* ── The epoch model in the actor loop (plan II.4.4-II.4.7) ────────────
 *
 * An actor runs at its proc's code epoch (march_proc.code_epoch): its own
 * dispatch function and every boundary call it makes resolve to the newest
 * version at or before that epoch (march_dispatch_enter_unit).  A deploy puts
 * an epoch MARKER (a flagged mailbox node, march_mbox_node.marker) behind
 * whatever the actor already has queued; the actor ADVANCES when it reaches
 * it: it applies the state migration of every deploy it passes (from the
 * activation log below, in epoch order), moves its epoch pin, and carries on
 * on the new code.  Messages ahead of the marker run on the old code against
 * the old state (D10).
 *
 * Per dequeued node (II.4.6), in the loop further down:
 *   - marker: advance, or, with epoch holds, remember it as pending;
 *   - a message stamped newer than the actor, whose message type changed in
 *     between (D30): advance now, then dispatch (a held actor defers it);
 *   - a message stamped older than the actor's last message-type change:
 *     migrate_msg, else drop and count;
 *   - otherwise dispatch at the actor's own epoch. */

static void march_actor_msg_dispose(void *msg);

typedef struct hcr_deferred {
    void                *msg;
    uint32_t             epoch;
    struct hcr_deferred *next;
} hcr_deferred;

static _Atomic int64_t g_hcr_drain_dropped = 0;
static _Atomic int64_t g_hcr_deferred_n    = 0;
static _Atomic int64_t g_hcr_converted     = 0;
static _Atomic int64_t g_hcr_killed        = 0;
static _Atomic int64_t g_hcr_stopped       = 0;
static _Atomic int64_t g_hcr_advances      = 0;
static _Atomic int64_t g_hcr_early         = 0;
static _Atomic int64_t g_hcr_forced        = 0;
static _Atomic int64_t g_hcr_markers_lost  = 0;
static _Atomic int64_t g_hcr_markers_live  = 0;

int64_t march_hcr_drain_dropped(void) {
    return atomic_load_explicit(&g_hcr_drain_dropped, memory_order_relaxed);
}

int64_t march_hcr_markers_live(void) {
    return atomic_load_explicit(&g_hcr_markers_live, memory_order_acquire);
}

void march_hcr_counters_get(march_hcr_counters *o) {
    o->deferred     = atomic_load(&g_hcr_deferred_n);
    o->converted    = atomic_load(&g_hcr_converted);
    o->dropped      = atomic_load(&g_hcr_drain_dropped);
    o->killed       = atomic_load(&g_hcr_killed);
    o->stopped      = atomic_load(&g_hcr_stopped);
    o->advances     = atomic_load(&g_hcr_advances);
    o->early        = atomic_load(&g_hcr_early);
    o->forced       = atomic_load(&g_hcr_forced);
    o->markers_lost = atomic_load(&g_hcr_markers_lost);
}

/* A marker left the mailbox by some path other than being consumed as one
 * (its proc died with it queued): give back the pin it held.  Registered
 * with the scheduler as the marker dtor. */
static void hcr_marker_dtor(void *msg, uint32_t epoch) {
    (void)msg;   /* markers carry no payload */
    march_epoch_unpin(epoch);
    atomic_fetch_sub_explicit(&g_hcr_markers_live, 1, memory_order_relaxed);
}

/* ── The activation log ───────────────────────────────────────────────────
 * One record per deploy: for each activated slot, which ring version holds
 * it and what the deploy's schema diff changed.  An actor advancing across
 * several deploys applies each one's state migration, in order; the message
 * path finds the migrate_msg of the deploy that changed the message type.
 * The function pointers live in the deploy's .so: callers pin that ring
 * version (march_dispatch_enter_version) and check its epoch before calling,
 * and a version that carries a migration is kept while any older epoch is
 * pinned (march_dispatch_set_keep_for_older).  Records are a few dozen bytes
 * per deploy and are never freed: an old-stamped message can outlive every
 * unit of its epoch, and the message path must still see the type change. */
typedef struct {
    uint32_t slot;
    int      ring_idx;
    void  *(*migrate_fn)(void *);
    void  *(*migrate_msg_fn)(void *, void *);
    uint8_t  state_changed, msgs_changed;
} hcr_log_entry;

typedef struct hcr_log_rec {
    uint32_t            epoch;
    int                 n;
    hcr_log_entry      *e;
    struct hcr_log_rec *next;
} hcr_log_rec;

static hcr_log_rec    *g_hcr_log_head = NULL, *g_hcr_log_tail = NULL;
static pthread_mutex_t g_hcr_log_mu = PTHREAD_MUTEX_INITIALIZER;

static void hcr_log_append(uint32_t epoch, const march_hcr_unit *u, int n) {
    hcr_log_rec *r = (hcr_log_rec *)calloc(1, sizeof(*r));
    hcr_log_entry *e = (hcr_log_entry *)calloc((size_t)(n ? n : 1), sizeof(*e));
    if (!r || !e) { fputs("march: out of memory (hot-reload log)\n", stderr); exit(1); }
    for (int i = 0; i < n; i++) {
        e[i].slot           = u[i].slot;
        e[i].ring_idx       = u[i].ring_idx;
        e[i].migrate_fn     = u[i].migrate_fn;
        e[i].migrate_msg_fn = u[i].migrate_msg_fn;
        e[i].state_changed  = (uint8_t)(u[i].state_changed != 0);
        e[i].msgs_changed   = (uint8_t)(u[i].msgs_changed != 0);
    }
    r->epoch = epoch; r->n = n; r->e = e;
    pthread_mutex_lock(&g_hcr_log_mu);
    if (g_hcr_log_tail) g_hcr_log_tail->next = r; else g_hcr_log_head = r;
    g_hcr_log_tail = r;
    pthread_mutex_unlock(&g_hcr_log_mu);
}

typedef struct {
    uint32_t epoch;
    int      ring_idx;
    void  *(*state_fn)(void *);
    void  *(*msg_fn)(void *, void *);
} hcr_mig;

/* The state migrations for [slot] of every deploy in (from, to], in epoch
 * order.  Returns the count; *out is malloc'd (caller frees) or NULL. */
static int hcr_log_state_migrations(uint32_t slot, uint32_t from, uint32_t to,
                                    hcr_mig **out) {
    int n = 0, cap = 0;
    hcr_mig *m = NULL;
    pthread_mutex_lock(&g_hcr_log_mu);
    for (hcr_log_rec *r = g_hcr_log_head; r; r = r->next) {
        if (r->epoch <= from || r->epoch > to) continue;
        for (int i = 0; i < r->n; i++) {
            if (r->e[i].slot != slot || !r->e[i].state_changed
                    || !r->e[i].migrate_fn) continue;
            if (n == cap) {
                cap = cap ? cap * 2 : 4;
                hcr_mig *g = (hcr_mig *)realloc(m, (size_t)cap * sizeof(*m));
                if (!g) { fputs("march: out of memory (hot-reload log)\n", stderr); exit(1); }
                m = g;
            }
            m[n].epoch = r->epoch; m[n].ring_idx = r->e[i].ring_idx;
            m[n].state_fn = r->e[i].migrate_fn; m[n].msg_fn = NULL;
            n++;
        }
    }
    pthread_mutex_unlock(&g_hcr_log_mu);
    *out = m;
    return n;
}

/* How many deploys in (from, to] changed [slot]'s message type; with
 * [last] non-NULL, the newest one's migrate_msg entry is written there. */
static int hcr_log_msg_changes(uint32_t slot, uint32_t from, uint32_t to,
                               hcr_mig *last) {
    int n = 0;
    pthread_mutex_lock(&g_hcr_log_mu);
    for (hcr_log_rec *r = g_hcr_log_head; r; r = r->next) {
        if (r->epoch <= from || r->epoch > to) continue;
        for (int i = 0; i < r->n; i++) {
            if (r->e[i].slot != slot || !r->e[i].msgs_changed) continue;
            n++;
            if (last) {
                last->epoch = r->epoch; last->ring_idx = r->e[i].ring_idx;
                last->state_fn = NULL; last->msg_fn = r->e[i].migrate_msg_fn;
            }
        }
    }
    pthread_mutex_unlock(&g_hcr_log_mu);
    return n;
}

/* ── Drains (II.4.7) ─────────────────────────────────────────────────────── */

typedef struct {
    uint32_t upto;
    int64_t  soft_at, hard_at;   /* march_now_ms() deadlines; 0 = not armed */
    uint64_t gen;
    int      hard_fired;
} hcr_drain_ent;

#define HCR_MAX_DRAINS 8
static hcr_drain_ent   g_hcr_drains[HCR_MAX_DRAINS];
static int             g_hcr_ndrains = 0;
static uint64_t        g_hcr_drain_gen = 0;
static pthread_mutex_t g_hcr_drain_mu = PTHREAD_MUTEX_INITIALIZER;
static _Atomic int     g_hcr_drain_active = 0;

/* Drop drains with nothing left to drain (no epoch at or below them is
 * pinned).  Under g_hcr_drain_mu. */
static void hcr_drains_prune_locked(void) {
    int k = 0;
    for (int i = 0; i < g_hcr_ndrains; i++)
        if (march_epoch_pinned_in(1, g_hcr_drains[i].upto + 1))
            g_hcr_drains[k++] = g_hcr_drains[i];
    g_hcr_ndrains = k;
    atomic_store_explicit(&g_hcr_drain_active, k > 0, memory_order_release);
}

/* 1 iff a soft deadline covering [epoch] has passed. */
static int hcr_soft_due(uint32_t epoch) {
    int due = 0;
    int64_t now = march_now_ms();
    pthread_mutex_lock(&g_hcr_drain_mu);
    for (int i = 0; i < g_hcr_ndrains && !due; i++)
        due = epoch <= g_hcr_drains[i].upto && g_hcr_drains[i].soft_at
              && now >= g_hcr_drains[i].soft_at;
    pthread_mutex_unlock(&g_hcr_drain_mu);
    return due;
}

int march_hcr_epoch_draining(uint32_t epoch) {
    if (!epoch || !atomic_load_explicit(&g_hcr_drain_active, memory_order_acquire))
        return 0;
    int yes = 0;
    pthread_mutex_lock(&g_hcr_drain_mu);
    for (int i = 0; i < g_hcr_ndrains && !yes; i++)
        yes = epoch <= g_hcr_drains[i].upto;
    pthread_mutex_unlock(&g_hcr_drain_mu);
    return yes;
}

/* The hard deadline covering [epoch], in ms from now; -1 = none. */
static int64_t hcr_hard_deadline_in(uint32_t epoch) {
    int64_t best = -1, now = march_now_ms();
    pthread_mutex_lock(&g_hcr_drain_mu);
    for (int i = 0; i < g_hcr_ndrains; i++) {
        if (epoch > g_hcr_drains[i].upto || !g_hcr_drains[i].hard_at) continue;
        int64_t in = g_hcr_drains[i].hard_at - now;
        if (in < 0) in = 0;
        if (best < 0 || in < best) best = in;
    }
    pthread_mutex_unlock(&g_hcr_drain_mu);
    return best;
}

static void hcr_hard_kill(uint32_t upto);

typedef struct { uint64_t gen; int64_t at; } hcr_hard_arg;

/* The hard deadline's timer: a green proc parked until the deadline (the
 * delayed_restart_thread pattern), not an OS thread -- march_hcr_drain can be
 * called from a green thread, and an ASAN build of the actor harness died
 * whenever a pthread was created from one (the thread itself did nothing).
 * A daemon and unpinned: it neither keeps the process alive nor holds an
 * epoch, and a drain never stops it. */
static void hcr_hard_proc(void *arg) {
    hcr_hard_arg h = *(hcr_hard_arg *)arg;
    free(arg);
    while (march_now_ms() < h.at)
        march_sched_park_self_until(h.at);
    uint32_t upto = 0;
    pthread_mutex_lock(&g_hcr_drain_mu);
    for (int i = 0; i < g_hcr_ndrains; i++)
        if (g_hcr_drains[i].gen == h.gen && !g_hcr_drains[i].hard_fired) {
            g_hcr_drains[i].hard_fired = 1;
            upto = g_hcr_drains[i].upto;
        }
    pthread_mutex_unlock(&g_hcr_drain_mu);
    if (upto) hcr_hard_kill(upto);
}

void march_hcr_drain(uint32_t upto, int64_t soft_ms, int64_t hard_ms) {
    if (!upto) return;
    int64_t now = march_now_ms();
    uint64_t gen;
    pthread_mutex_lock(&g_hcr_drain_mu);
    hcr_drains_prune_locked();
    int slot = -1;
    for (int i = 0; i < g_hcr_ndrains; i++)
        if (g_hcr_drains[i].upto == upto) slot = i;
    if (slot < 0) {
        if (g_hcr_ndrains == HCR_MAX_DRAINS) {
            /* Full: the oldest-covering drain is subsumed by this one's
             * range only if it is lower, so replace the lowest. */
            slot = 0;
            for (int i = 1; i < g_hcr_ndrains; i++)
                if (g_hcr_drains[i].upto < g_hcr_drains[slot].upto) slot = i;
        } else {
            slot = g_hcr_ndrains++;
        }
    }
    gen = ++g_hcr_drain_gen;
    g_hcr_drains[slot].upto       = upto;
    g_hcr_drains[slot].soft_at    = soft_ms > 0 ? now + soft_ms : 0;
    g_hcr_drains[slot].hard_at    = hard_ms > 0 ? now + hard_ms : 0;
    g_hcr_drains[slot].gen        = gen;
    g_hcr_drains[slot].hard_fired = 0;
    atomic_store_explicit(&g_hcr_drain_active, 1, memory_order_release);
    pthread_mutex_unlock(&g_hcr_drain_mu);
    if (hard_ms > 0) {
        hcr_hard_arg *h = (hcr_hard_arg *)malloc(sizeof(*h));
        if (!h) return;
        h->gen = gen; h->at = now + hard_ms;
        if (!march_sched_spawn_daemon_unpinned(hcr_hard_proc, h)) free(h);
    }
}

/* ── Holds (D28, II.4.4) ─────────────────────────────────────────────────── */

void march_epoch_hold(void) {
    march_proc *p = march_sched_current();
    if (p) atomic_fetch_add_explicit(&p->epoch_holds, 1, memory_order_relaxed);
}

void march_epoch_release(void) {
    march_proc *p = march_sched_current();
    if (!p) return;
    uint32_t h = atomic_load_explicit(&p->epoch_holds, memory_order_relaxed);
    while (h > 0 && !atomic_compare_exchange_weak_explicit(
                        &p->epoch_holds, &h, h - 1,
                        memory_order_relaxed, memory_order_relaxed)) { }
    /* A pending marker fires at the actor loop's next message boundary,
     * which is right after the handler that made this call returns. */
}

uint32_t march_epoch_holds(void) {
    march_proc *p = march_sched_current();
    return p ? atomic_load_explicit(&p->epoch_holds, memory_order_relaxed) : 0;
}

/* ── Advancing ───────────────────────────────────────────────────────────── */

/* Move this actor from its epoch to [target] (> current): apply the state
 * migration of every deploy in between, then move the pin.  [have_pin]: the
 * caller already holds a pin on [target] (a marker's), which the actor takes
 * over; otherwise one is taken here, and a target that has lost every holder
 * is replaced by the current epoch. */
__attribute__((noinline))
static void hcr_advance(march_actor_meta *meta, int64_t *a, march_proc *self,
                        uint32_t target, int have_pin, int alive) {
    uint32_t cur = atomic_load_explicit(&self->code_epoch, memory_order_relaxed);
    if (target <= cur) {
        if (have_pin) march_epoch_unpin(target);
        return;
    }
    if (!have_pin && march_epoch_pin(target) != 0) {
        for (;;) {
            target = march_epoch_current();
            if (target <= cur) return;
            if (march_epoch_pin(target) == 0) break;
        }
    }
    uint32_t slot = meta->dispatch_name_id;
    if (alive && slot) {
        hcr_mig *m = NULL;
        int k = hcr_log_state_migrations(slot, cur, target, &m);
        for (int i = 0; i < k; i++) {
            uint32_t v;
            void *held = march_dispatch_enter_version(
                slot, (uint32_t)m[i].ring_idx, &v);
            if (held && march_dispatch_epoch(slot, (uint32_t)m[i].ring_idx)
                        == m[i].epoch) {
                /* a[4] is the state record (state indirection layout). */
                a[4] = (int64_t)(uintptr_t)m[i].state_fn((void *)(uintptr_t)a[4]);
                march_dispatch_leave(slot, v);
            } else {
                if (held) march_dispatch_leave(slot, v);
                fprintf(stderr, "[hcr] migrate: slot %u lost the epoch-%u "
                        "version before its migration ran\n", slot, m[i].epoch);
            }
        }
        free(m);
    }
    atomic_store_explicit(&self->code_epoch, target, memory_order_release);
    march_epoch_unpin(cur);
    if (meta->hcr_pending_epoch && meta->hcr_pending_epoch <= target) {
        march_epoch_unpin(meta->hcr_pending_epoch);
        meta->hcr_pending_epoch = 0;
    }
    atomic_fetch_add_explicit(&g_hcr_advances, 1, memory_order_relaxed);
    if (meta->hcr_dropped) {
        fprintf(stderr, "[hcr] migrate: actor on dispatch slot %u dropped %lld "
                "old message(s) before reaching epoch %u\n",
                slot, (long long)meta->hcr_dropped, target);
        meta->hcr_dropped = 0;
    }
}

/* The actor dequeued a marker for [epoch]. */
__attribute__((noinline))
static void hcr_on_marker(march_actor_meta *meta, int64_t *a, march_proc *self,
                          uint32_t epoch, int alive) {
    atomic_fetch_sub_explicit(&g_hcr_markers_live, 1, memory_order_relaxed);
    if (atomic_load_explicit(&self->epoch_holds, memory_order_relaxed) > 0) {
        /* Held: remember the newest marker (and keep its pin). */
        if (epoch > meta->hcr_pending_epoch) {
            if (meta->hcr_pending_epoch) march_epoch_unpin(meta->hcr_pending_epoch);
            meta->hcr_pending_epoch = epoch;
        } else {
            march_epoch_unpin(epoch);
        }
        return;
    }
    hcr_advance(meta, a, self, epoch, 1, alive);
}

/* A forced marker (the soft drain deadline): take every marker still queued,
 * in order, as if it were at the front, then catch up to current. */
__attribute__((noinline))
static void hcr_force_advance(march_actor_meta *meta, int64_t *a,
                              march_proc *self, int alive) {
    void *msgs[64]; uint32_t eps[64];
    int n;
    do {
        n = march_sched_take_markers(UINT32_MAX, msgs, eps, 64);
        for (int i = 0; i < n; i++) {
            atomic_fetch_sub_explicit(&g_hcr_markers_live, 1, memory_order_relaxed);
            hcr_advance(meta, a, self, eps[i], 1, alive);
        }
    } while (n == 64);
    if (meta->hcr_pending_epoch) {
        uint32_t p = meta->hcr_pending_epoch;
        meta->hcr_pending_epoch = 0;
        hcr_advance(meta, a, self, p, 1, alive);
    }
    uint32_t cur = march_epoch_current();
    if (atomic_load_explicit(&self->code_epoch, memory_order_relaxed) < cur)
        hcr_advance(meta, a, self, cur, 0, alive);
    atomic_fetch_add_explicit(&g_hcr_forced, 1, memory_order_relaxed);
}

/* At every message boundary, before the next receive.  Cheap when the actor
 * is at the current epoch (the steady state). */
static void hcr_boundary_slow(march_actor_meta *meta, int64_t *a,
                              march_proc *self, int alive);

static inline void hcr_boundary(march_actor_meta *meta, int64_t *a,
                                march_proc *self, int alive) {
    uint32_t cur = atomic_load_explicit(&self->code_epoch, memory_order_relaxed);
    if (!cur) return;
    if (cur >= march_epoch_current() && !meta->hcr_pending_epoch) return;
    hcr_boundary_slow(meta, a, self, alive);
}

__attribute__((noinline))
static void hcr_boundary_slow(march_actor_meta *meta, int64_t *a,
                              march_proc *self, int alive) {
    uint32_t cur;
    if (atomic_load_explicit(&self->epoch_holds, memory_order_relaxed) > 0) return;
    if (meta->hcr_pending_epoch) {
        uint32_t p = meta->hcr_pending_epoch;
        meta->hcr_pending_epoch = 0;
        hcr_advance(meta, a, self, p, 1, alive);
    }
    uint32_t lost = atomic_exchange_explicit(&meta->hcr_lost_epoch, 0,
                                             memory_order_acq_rel);
    if (lost) hcr_advance(meta, a, self, lost, 0, alive);
    cur = atomic_load_explicit(&self->code_epoch, memory_order_relaxed);
    if (cur < march_epoch_current()
            && atomic_load_explicit(&g_hcr_drain_active, memory_order_acquire)
            && hcr_soft_due(cur))
        hcr_force_advance(meta, a, self, alive);
}

__attribute__((noinline))
static void hcr_defer(march_actor_meta *meta, void *msg, uint32_t epoch) {
    hcr_deferred *d = (hcr_deferred *)malloc(sizeof(*d));
    if (!d) { fputs("march: out of memory (hot-reload defer)\n", stderr); exit(1); }
    d->msg = msg; d->epoch = epoch; d->next = NULL;
    if (meta->hcr_def_tail) meta->hcr_def_tail->next = d; else meta->hcr_def_head = d;
    meta->hcr_def_tail = d;
    meta->hcr_def_n++;
    atomic_fetch_add_explicit(&g_hcr_deferred_n, 1, memory_order_relaxed);
}

/* The next deferred message, once the actor may run it (no holds). */
static int hcr_take_deferred(march_actor_meta *meta, march_proc *self,
                             void **msg, uint32_t *epoch) {
    hcr_deferred *d = meta->hcr_def_head;
    if (!d || atomic_load_explicit(&self->epoch_holds, memory_order_relaxed) > 0)
        return 0;
    meta->hcr_def_head = d->next;
    if (!meta->hcr_def_head) meta->hcr_def_tail = NULL;
    meta->hcr_def_n--;
    *msg = d->msg; *epoch = d->epoch;
    free(d);
    return 1;
}

/* Returned as migrate_msg's None: an immortal cell no real message can be. */
static int64_t g_hcr_none_cell[3] __attribute__((aligned(16))) = {
    MARCH_RC_IMMORTAL, 0, 0 };

#define HCR_DISPATCH 0
#define HCR_CONSUMED 1

/* Apply II.4.6's message rules to a dequeued user message stamped
 * [mepoch].  HCR_DISPATCH: dispatch *msgp (possibly converted) at the
 * actor's epoch; HCR_CONSUMED: deferred, or dropped. */
static int hcr_route_slow(march_actor_meta *meta, int64_t *a, march_proc *self,
                          void **msgp, uint32_t mepoch, int alive,
                          uint32_t slot, uint32_t cur);

/* The cold helpers above and hcr_route_slow are noinline on purpose: inlined
 * into actor_green_thread (an ASAN -O1 build does it) their locals -- the
 * forced marker's two 64-entry arrays among them -- grew the actor loop's
 * frame past a green thread's initial stack, so every actor paid a stack
 * growth for a path that runs once per deploy. */
static inline int hcr_route(march_actor_meta *meta, int64_t *a, march_proc *self,
                            void **msgp, uint32_t mepoch, int alive) {
    uint32_t slot = meta->dispatch_name_id;
    uint32_t cur = atomic_load_explicit(&self->code_epoch, memory_order_relaxed);
    if (!slot || !cur || mepoch == cur) return HCR_DISPATCH;
    return hcr_route_slow(meta, a, self, msgp, mepoch, alive, slot, cur);
}

__attribute__((noinline))
static int hcr_route_slow(march_actor_meta *meta, int64_t *a, march_proc *self,
                          void **msgp, uint32_t mepoch, int alive,
                          uint32_t slot, uint32_t cur) {
    uint32_t mse = march_dispatch_msg_schema_epoch(slot);
    if (mepoch > cur) {
        /* D30: a sender that has already advanced, and a message type that
         * changed in between: this message is in a format the actor's code
         * cannot read.  Move now (the marker, when it comes, is a no-op). */
        if (mse <= cur || !hcr_log_msg_changes(slot, cur, mepoch, NULL))
            return HCR_DISPATCH;
        if (atomic_load_explicit(&self->epoch_holds, memory_order_relaxed) > 0) {
            hcr_defer(meta, *msgp, mepoch);
            return HCR_CONSUMED;
        }
        hcr_advance(meta, a, self, mepoch, 0, alive);
        atomic_fetch_add_explicit(&g_hcr_early, 1, memory_order_relaxed);
        cur = atomic_load_explicit(&self->code_epoch, memory_order_relaxed);
        if (mepoch >= cur) return HCR_DISPATCH;
    }
    /* An old-format message after the actor moved past a message-type
     * change (D10): convert it with that deploy's migrate_msg, or drop it. */
    if (mse <= mepoch) return HCR_DISPATCH;
    hcr_mig mm;
    int changes = hcr_log_msg_changes(slot, mepoch, cur, &mm);
    if (changes == 0) return HCR_DISPATCH;
    if (changes == 1 && mm.msg_fn) {
        uint32_t v;
        if (march_dispatch_enter_version(slot, (uint32_t)mm.ring_idx, &v)) {
            if (march_dispatch_epoch(slot, (uint32_t)mm.ring_idx) == mm.epoch) {
                void *out = mm.msg_fn(*msgp, (void *)g_hcr_none_cell);
                march_dispatch_leave(slot, v);
                if (out != (void *)g_hcr_none_cell) {
                    *msgp = out;
                    atomic_fetch_add_explicit(&g_hcr_converted, 1, memory_order_relaxed);
                    return HCR_DISPATCH;
                }
                /* None: dropped on purpose; migrate_msg consumed it. */
                meta->hcr_dropped++;
                atomic_fetch_add_explicit(&g_hcr_drain_dropped, 1, memory_order_relaxed);
                return HCR_CONSUMED;
            }
            march_dispatch_leave(slot, v);
        }
    }
    /* No migrate_msg (or two message-type changes in between, which one
     * conversion cannot bridge): drop and count. */
    march_actor_msg_dispose(*msgp);
    meta->hcr_dropped++;
    atomic_fetch_add_explicit(&g_hcr_drain_dropped, 1, memory_order_relaxed);
    return HCR_CONSUMED;
}

/* The actor is dying: give back the pending marker's pin and dispose of the
 * deferred queue.  (The proc's own epoch pin is dropped at the reap.) */
__attribute__((noinline))
static void hcr_actor_exit(march_actor_meta *meta) {
    if (meta->hcr_pending_epoch) {
        march_epoch_unpin(meta->hcr_pending_epoch);
        meta->hcr_pending_epoch = 0;
    }
    atomic_store_explicit(&meta->hcr_lost_epoch, 0, memory_order_relaxed);
    hcr_deferred *d = meta->hcr_def_head;
    meta->hcr_def_head = meta->hcr_def_tail = NULL;
    meta->hcr_def_n = 0;
    while (d) {
        hcr_deferred *next = d->next;
        march_actor_msg_dispose(d->msg);
        free(d);
        d = next;
    }
    meta->hcr_dropped = 0;
}

/* ── on_stop (terminate) callbacks ─────────────────────────────────────
 * specs/lang/actors.md, "on_stop". One entry per actor TYPE that declares
 * `on_stop do ... end`, keyed by that type's dispatch closure — the value
 * lower_actor's spawn glue stores in word 2 of every record it allocates, so
 * a record identifies its type without any layout change. Registered from
 * the spawn glue (which a supervisor restart re-runs), before march_spawn
 * creates the record's metadata; looked up once, at a graceful death. A
 * handful of actor types per program at most, so a locked linear table. */
typedef struct { void *dispatch; void *on_stop; } march_on_stop_entry;
static march_on_stop_entry *g_on_stop_tbl = NULL;
static int g_on_stop_len = 0, g_on_stop_cap = 0;
static pthread_mutex_t g_on_stop_mu = PTHREAD_MUTEX_INITIALIZER;

void march_register_actor_on_stop(void *dispatch_clo, void *on_stop_clo) {
    pthread_mutex_lock(&g_on_stop_mu);
    for (int i = 0; i < g_on_stop_len; i++) {
        if (g_on_stop_tbl[i].dispatch == dispatch_clo) {
            pthread_mutex_unlock(&g_on_stop_mu);
            return;
        }
    }
    if (g_on_stop_len == g_on_stop_cap) {
        int ncap = g_on_stop_cap ? g_on_stop_cap * 2 : 8;
        march_on_stop_entry *n = realloc(g_on_stop_tbl, (size_t)ncap * sizeof *n);
        if (!n) {
            pthread_mutex_unlock(&g_on_stop_mu);
            fputs("march: out of memory registering an on_stop callback\n", stderr);
            exit(1);
        }
        g_on_stop_tbl = n;
        g_on_stop_cap = ncap;
    }
    g_on_stop_tbl[g_on_stop_len].dispatch = dispatch_clo;
    g_on_stop_tbl[g_on_stop_len].on_stop = on_stop_clo;
    g_on_stop_len++;
    pthread_mutex_unlock(&g_on_stop_mu);
}

static void *on_stop_lookup(void *dispatch_clo) {
    void *cb = NULL;
    pthread_mutex_lock(&g_on_stop_mu);
    for (int i = 0; i < g_on_stop_len; i++) {
        if (g_on_stop_tbl[i].dispatch == dispatch_clo) {
            cb = g_on_stop_tbl[i].on_stop;
            break;
        }
    }
    pthread_mutex_unlock(&g_on_stop_mu);
    return cb;
}

/* Run [actor]'s on_stop callback [clo] on its own green thread [self].
 *
 * A panic inside it is LOGGED and the death proceeds as if it had returned
 * (decided 2026-09-22, on OTP's terminate/2): the actor is dying anyway, and
 * a broken terminate must neither wedge a shutdown nor turn a NORMAL death
 * into a crash a supervisor would restart. So the callback gets its own crash
 * trap for its duration — for EVERY actor, not only supervised ones, whose
 * handler panics are otherwise process-fatal.
 *
 * The stop deadline is enforced from outside: march_actor_stop's waiter kills
 * the actor when it passes. A callback parked in `receive()` then leaves
 * through the actor loop's stop_jmp (march_actor_recv), which lands at
 * actor_green_thread's `stopped:` — still live below this frame — and that
 * path restores crash_jmp. */
static void actor_run_on_stop(march_proc *self, void *actor, void *clo) {
    jmp_buf on_stop_jmp;
    jmp_buf *saved_crash = self->crash_jmp;
    self->crash_jmp = &on_stop_jmp;
    if (setjmp(on_stop_jmp) == 0) {
        /* Same closure convention (and the same immortal static closure) as
         * the dispatch call in actor_green_thread: fn(closure, actor). */
        typedef void (*on_stop_fn_t)(void *, void *);
        on_stop_fn_t fn = *(on_stop_fn_t *)((char *)clo + 16);
        march_incrc(clo);
        fn(clo, actor);
    } else {
        const char *m = self->crash_message ? self->crash_message : "panic";
        size_t mlen = self->crash_message ? self->crash_message_len
                                          : sizeof("panic") - 1;
        fprintf(stderr, "march: actor on_stop callback failed (the actor still"
                " stops): panic: %.*s\n", (int)mlen, m);
        free(self->crash_message);
        self->crash_message = NULL;
        self->crash_message_len = 0;
    }
    self->crash_jmp = saved_crash;
}

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
    /* Publish the actor this proc is running, so `self` in a handler body can
     * find it (march_self, in march_scheduler.c). */
    if (self) self->actor = actor;
    /* [meta] is this thread's own: activate_actor_green_thread took the
     * reference it holds, released by the meta_put on each exit below. */
    jmp_buf crash_jmp;
    jmp_buf *saved_jmp = self ? self->crash_jmp : NULL;
    /* Supervise-block children reach this function only after deferred spawn
     * registration has published meta->sup_pe and its restart slot.
     * Keep the locked snapshot so the trap decision is race-free and fixed
     * for this proc's lifetime. Ordinary march_spawn actors retain NULL and
     * therefore preserve process-fatal unsupervised panic semantics. */
    pthread_mutex_lock(&g_tbl_mu);
    int has_supervisor = meta->sup_pe != NULL;
    pthread_mutex_unlock(&g_tbl_mu);

    /* The hot-reload dispatch pin, hoisted above the setjmp so the crash
     * branch can release a pin the longjmp jumped over — see that branch.
     * `volatile` is load-bearing, not decoration: an automatic object
     * modified between setjmp and longjmp has an INDETERMINATE value in the
     * branch the longjmp lands in unless it is volatile (C17 7.13.2.1p3),
     * and these are written on every message of a hot-reload actor. */
    volatile uint32_t  pinned_version  = 0;
    volatile int       dispatch_pinned = 0;

    /* The stop trap, for every actor: a nested `receive()` told to stop
     * lands here (march_actor_recv) and the actor dies the normal way.  The
     * setjmp is placed before the crash trap's so a longjmp from either
     * frame finds its own buffer; both restore their saved pointer on exit. */
    jmp_buf stop_jmp;
    jmp_buf *saved_stop = self ? self->stop_jmp : NULL;
    if (self) self->stop_jmp = &stop_jmp;
    if (self && setjmp(stop_jmp) != 0) {
        if (dispatch_pinned) {
            march_dispatch_leave(meta->dispatch_name_id, pinned_version);
            dispatch_pinned = 0;
        }
        goto stopped;
    }
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
        self->stop_jmp = saved_stop;

        /* Release the code-version pin the longjmp jumped over, BEFORE
         * do_actor_death and the restart it triggers run.  A hot-reload
         * actor's dispatch is bracketed by march_dispatch_enter /
         * march_dispatch_leave, which hold a refs count on one ring slot so
         * a concurrent publish cannot dlclose the code being executed.  A
         * panic out of the middle of that handler skips the leave, leaving
         * refs permanently above zero: that version's slot can never be
         * reclaimed, and a crash-looping hot-reload actor burns one slot per
         * crash until the ring is exhausted.  Unlike an ordinary leak this
         * one is not reachable-and-forgotten memory — it is a live counter
         * that blocks a runtime mechanism, so it is repaired here rather
         * than accepted.
         *
         * dispatch_pinned is the "the leave never ran" flag: a panic can
         * also longjmp here from OUTSIDE the dispatch call (e.g. out of a
         * migrate_fn), and a non-hot-reload actor never pins at all.
         *
         * Not repaired here: the message itself.  The dispatch function
         * owns and consumes msg, and a longjmp out of its middle leaves no
         * way to know whether it already did — so msg is leaked on this
         * path rather than risking a double free.
         *
         * Nothing else needs undoing: this loop deliberately no longer
         * clobbers the actor's refcount around a dispatch (see the "NO RC
         * CLOBBER HERE" comment below for why that is load-bearing), so a
         * crash cannot leave a[0] lying about its owner count.  Before that
         * clobber was removed, this longjmp also skipped its `a[0] =
         * saved_rc` restore, which left a live multiply-owned record
         * claiming a single owner — the next drop by any other owner freed
         * it, and the damage surfaced as an EXC_BAD_ACCESS inside an
         * unrelated malloc.  test/native/actor_crash_rc_restore.march pins
         * that a crash leaves the refcount untouched, so reintroducing a
         * clobber here fails a test instead of corrupting a heap. */
        if (dispatch_pinned) {
            march_dispatch_leave(meta->dispatch_name_id, pinned_version);
            dispatch_pinned = 0;
        }

        char *crash_message = self->crash_message;
        size_t crash_message_len = self->crash_message_len;
        self->crash_message = NULL;
        self->crash_message_len = 0;
        do_actor_death(actor, MARCH_DEATH_CRASH,
                       crash_message ? crash_message : "panic",
                       crash_message ? crash_message_len : sizeof("panic") - 1);
        free(crash_message);
        /* Unpublish this proc (release, paired with the acquire loads in
         * march_send / march_actor_call / do_actor_death / mailbox_size /
         * set_mbox_limit).  EXITED, not NULL: see green_thread's comment. */
        atomic_store_explicit(&meta->green_thread, MARCH_GT_EXITED,
                              memory_order_release);
        /* A dead actor keeps no pending marker or deferred message. */
        hcr_actor_exit(meta);
        /* The live actor's own reference (taken in march_spawn_common):
         * nothing on this thread touches the record after this. */
        march_decrc(actor);
        meta_put(meta);   /* this thread's; nothing here touches it after */
        return;
    }

    while (actor_alive_load(actor)) {  /* while alive */
        /* Graceful shutdown (march_actor_stop): keep serving the queue, but
         * stop taking new work and leave once the queue is empty or the
         * deadline passes. Checked HERE, at the top of the iteration, rather
         * than in the recv path, so an actor that was mid-handler when stop
         * arrived finishes that handler and then drains the rest.
         *
         * An actor parked in recv with an empty mailbox never reaches this
         * check at all -- march_actor_stop's request_stop wakes it, recv
         * returns MARCH_RECV_NO_MSG, and the loop breaks below into the same
         * normal death. Same outcome, one iteration earlier. */
        if (self && atomic_load_explicit(&meta->draining, memory_order_acquire)) {
            int64_t deadline = atomic_load_explicit(&meta->drain_deadline_ms,
                                                    memory_order_relaxed);
            /* A claimed-but-not-yet-armed stop means march_actor_stop is still
             * stopping this actor's CHILDREN, and it yields while doing so, so
             * this loop really does get to run in that window. Exiting here
             * would be wrong twice over: the queue this stop exists to drain
             * would be discarded on an empty-mailbox check that has not been
             * asked for yet, and do_actor_death could free the actor struct
             * that the teardown loop is still reading child pids out of.
             * Keep serving until the deadline is armed. */
            if (deadline == MARCH_DRAIN_NOT_ARMED) {
                /* fall through to the normal receive below */
            } else if (march_sched_mbox_count(self) == 0) {
                break;
            } else if (deadline >= 0 && march_now_ms() >= deadline) {
                if (getenv("MARCH_SUP_TRACE"))
                    fprintf(stderr, "march: drain deadline reached, %lld message(s)"
                            " discarded\n", (long long)march_sched_mbox_count(self));
                break;
            }
        }
        /* The epoch model's per-boundary work: a pending marker whose holds
         * are gone, a lost marker, a soft drain deadline (see hcr_boundary).
         * Only for procs that pin an epoch (actor procs always do). */
        if (self) hcr_boundary(meta, a, self, (int)actor_alive_load(actor));

        /* Deferred newer-format messages replay first, in order, once the
         * actor has advanced and holds nothing (hcr_route). */
        void *msg;
        uint32_t msg_epoch = 0;
        int is_marker = 0;
        if (!(self && hcr_take_deferred(meta, self, &msg, &msg_epoch))) {
            msg = march_sched_recv_actor(&msg_epoch, &is_marker);
            if (msg == MARCH_RECV_NO_MSG) break;  /* woken without message (killed) */
        }

        /* An epoch marker (II.4.6): everything ahead of it ran at this
         * actor's old epoch; advance (or, held, remember it). */
        if (is_marker) {
            if (self)
                hcr_on_marker(meta, a, self, msg_epoch,
                              (int)actor_alive_load(actor));
            else
                hcr_marker_dtor(msg, msg_epoch);
            march_sched_tick();
            continue;
        }

        /* ── Phase 5 legacy: a MARCH_MIGRATE_TAG user message ──────────────
         * (march_actor_broadcast_migrate / march_actor_inject_migrate_msg;
         * deploys use epoch markers instead).  Checked BEFORE the alive gate
         * so the message is always freed.  Gated on dispatch_name_id (only
         * hot-reload actors are targeted, and a regular actor's user message
         * whose word 1 happens to equal the tag is never misread) and on
         * IS_HEAP_PTR (zero-arg constructors arrive as NULL, unary scalar
         * ones as odd tagged values; a real migrate message is malloc'd). */
        if (meta->dispatch_name_id
                && IS_HEAP_PTR(msg)
                && ((int64_t *)msg)[1] == MARCH_MIGRATE_TAG) {
            march_migrate_msg_t *mm = (march_migrate_msg_t *)msg;
            if (mm->migrate_fn && actor_alive_load(actor))
                a[4] = (int64_t)(uintptr_t)mm->migrate_fn((void *)(uintptr_t)a[4]);
            migrate_msg_free(mm);
            march_sched_tick();
            continue;
        }

        if (!actor_alive_load(actor)) {
            march_decrc(msg);
            break;
        }

        /* The epoch model's message rules (early advance, deferral,
         * migrate_msg, drop). */
        if (self && hcr_route(meta, a, self, &msg, msg_epoch, 1) == HCR_CONSUMED) {
            march_sched_tick();
            continue;
        }

        uint32_t tbl_version = 0;

        /* NO RC CLOBBER HERE — deliberately, and load-bearing.
         *
         * This loop used to bracket the dispatch call with
         *     int64_t saved_rc = a[0];
         *     a[0] = 1;              // "FBIP: force RC=1 for in-place reuse"
         *     ...dispatch...
         *     a[0] = saved_rc;
         * to defeat the RC==1 uniqueness check that llvm_emit's generic
         * EReuse path used to apply to the handler's state write-back.
         *
         * That is a use-after-free generator, and the codegen no longer needs
         * it. Two independent reasons it must stay gone:
         *
         * 1. It is not needed. llvm_emit.ml's EReuse arm special-cases actor
         *    structs ([Repr.is_actor_struct_type], gated structurally on field
         *    0 being "$d_dispatch") and ALWAYS mutates the actor in place — no
         *    RC load, no branch, no fresh alloc. Nothing in the emitted
         *    handler reads a[0] at all.
         *
         * 2. It is unsafe. a[0] is the actor record's refcount, shared with
         *    every other thread via the atomic march_incrc/march_decrc. The
         *    plain stores above are not atomic with those, and worse, they
         *    LIE: while the window is open every other thread sees rc == 1.
         *    A concurrent march_incrc is then silently lost by the blind
         *    `a[0] = saved_rc` restore, and — the fatal one — a concurrent
         *    march_decrc observes prev == 1 and FREES an actor record that
         *    still has other live owners.
         *
         *    Observed, not theorized (bench/actors/spawn_churn.march, which
         *    registers each churned actor under a name before killing it):
         *    an actor opened this window with a true rc of 4 on one scheduler
         *    thread while another thread's decrc saw the forced 1 and freed
         *    the record. The registry's forward table (march_vault_set incrc's
         *    the stored actor, so a registered actor's rc is > 1 by
         *    construction) was left pointing at freed memory, and the
         *    subsequent registry_retire_actor read a garbage refcount out of
         *    the reallocated block: "RC underflow (rc was
         *    -6899412650951359789)", SIGBUS, or SIGTRAP, on ~20% of runs.
         *    Single-scheduler runs never failed, because main and the actor's
         *    green thread cannot then overlap.
         *
         * If a future actor lowering ever reintroduces an RC-conditional
         * reuse of the actor record, fix it in llvm_emit by keeping the
         * unconditional in-place store — do NOT reintroduce a refcount lie
         * here. There is no way to make it safe: the window has to publish a
         * false rc to a word other threads are concurrently RMW'ing. */

        if (meta->dispatch_name_id) {
            /* Hot-reload actor: the dispatch fn is a bare 2-arg function
             * Counter_dispatch(actor, msg) — NOT a closure wrapper.
             * Call it directly without a closure env arg. */
            typedef void (*dispatch_fn_t)(void *, void *);
            /* march_dispatch_enter takes a plain uint32_t* out-param, so the
             * pin's version lands in a non-volatile local first and is then
             * published to the volatile copy the crash branch reads. */
            /* D33: this actor's own epoch selects the version, the same rule
             * every compiled boundary call uses. */
            void *fn_raw = march_dispatch_enter_unit(meta->dispatch_name_id,
                                                     &tbl_version);
            pinned_version = tbl_version;
            dispatch_pinned = 1;
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

        if (meta->dispatch_name_id) {
            march_dispatch_leave(meta->dispatch_name_id, tbl_version);
            dispatch_pinned = 0;   /* pin released: nothing for the crash branch to do */
        }

        march_sched_tick();
    }

    /* on_stop: the loop left because a graceful stop finished its drain —
     * still alive, draining, with the deadline armed and not yet passed. Not
     * after a kill (the actor is no longer alive), not at scheduler shutdown
     * (not draining), and not once the deadline has gone: the stopper is
     * about to kill it, so the callback would only race that. */
    if (self && actor_alive_load(actor)
            && atomic_load_explicit(&meta->draining, memory_order_acquire)) {
        int64_t deadline = atomic_load_explicit(&meta->drain_deadline_ms,
                                                memory_order_relaxed);
        if (deadline != MARCH_DRAIN_NOT_ARMED
                && (deadline < 0 || march_now_ms() < deadline)) {
            void *cb = on_stop_lookup((void *)(uintptr_t)a[2]);
            if (cb) {
                /* Consume the stop request that woke this loop. It is a
                 * sticky flag on the proc, so left set it would make the
                 * callback's first blocking receive — a `receive()`, or the
                 * reply wait inside an Actor.call used to flush somewhere —
                 * return "stop" at once instead of blocking until the
                 * deadline. Cleared FIRST and liveness re-checked AFTER: a
                 * kill (the deadline, or anyone's kill) that lands in
                 * between re-sets the flag and is seen here or by the
                 * callback's next receive, never lost. */
                atomic_store_explicit(&self->stop_requested, 0,
                                      memory_order_seq_cst);
                if (actor_alive_load(actor))
                    actor_run_on_stop(self, actor, cb);
            }
        }
    }

    /* The loop has exited (actor killed, or woken without a message at
     * scheduler shutdown -- from its own receive, or from a `receive()`
     * nested in a handler, which longjmp's to `stopped`) and this proc is
     * about to die and be freed by sched_loop.  Clear the meta handle so
     * march_kill / march_send observe NULL instead of waking or enqueueing
     * on a freed proc (use-after-free). */
stopped:
    if (self) { self->crash_jmp = saved_jmp; self->stop_jmp = saved_stop; }
    do_actor_death(actor, MARCH_DEATH_NORMAL, NULL, 0);
    /* Same as the crash-trap exit above. */
    atomic_store_explicit(&meta->green_thread, MARCH_GT_EXITED,
                          memory_order_release);
    hcr_actor_exit(meta);
    /* The live actor's own reference (taken in march_spawn_common). */
    march_decrc(actor);
    meta_put(meta);
}

/* The compiled `receive()` builtin: a blocking mailbox pop from user code,
 * i.e. from INSIDE a handler (the dispatch loop uses march_sched_recv_user
 * directly).  MARCH_RECV_NO_MSG means "you were told to stop" (kill, or the
 * shutdown endgame); it must never reach user code, which would match on
 * the static sentinel and drop it.  An actor lands on its loop's death path
 * through stop_jmp; a task or main simply ends this green thread. */
void *march_actor_recv(void) {
    void *msg = march_sched_recv();
    /* Epoch markers are invisible here (the scheduler skips them and leaves
     * them queued for the actor loop).  A legacy MARCH_MIGRATE_TAG message
     * belongs to the actor loop too and must not reach user code as a
     * value: drop it (it moves no epoch). */
    while (msg != MARCH_RECV_NO_MSG && IS_HEAP_PTR(msg)
            && ((int64_t *)msg)[1] == MARCH_MIGRATE_TAG) {
        migrate_msg_free(msg);
        msg = march_sched_recv();
    }
    if (msg != MARCH_RECV_NO_MSG) return msg;
    march_proc *p = march_sched_current();
    if (p && p->stop_jmp) longjmp(*p->stop_jmp, 1);
    march_sched_exit();
    return MARCH_RECV_NO_MSG;   /* not reached */
}

/* ── Public actor API ────────────────────────────────────────────── */

/* Task 16 (with a Critical fix-up — see the review that produced this
 * comment): serializes ONLY the small handful of shared supervisor fields
 * touched by concurrent crashes — march_restart_budget_ok's sup_restart_ts
 * realloc, march_supervisor_notify's child->crash_streak/last_crash_ms
 * read-modify-write, and sup_meta->delayed_batch_pending. Supervision is
 * control-plane — restarts are rare relative to steady-state message
 * traffic — so a single global mutex here is deliberately simple rather
 * than per-supervisor.
 *
 * LEAF-LOCK CONTRACT — load-bearing, not a style choice: g_supervise_mu
 * must NEVER be held across do_actor_death, march_respawn_child, or any
 * call into a March closure (a supervisor's spawn_clo, a cleanup callback,
 * anything reachable from user code). Every critical section under this
 * mutex must be a short, self-contained read/write of plain C fields with
 * no possibility of the calling green thread yielding (no swapcontext) or
 * re-entering march_supervisor_notify while the lock is held.
 *
 * This contract exists because an earlier version of this mutex (held
 * across the restart-strategy dispatch) was a live deadlock: the restart
 * strategies call do_actor_death (budget-exhaustion kills the supervisor;
 * one_for_all kills live siblings before respawning), and do_actor_death
 * calls march_supervisor_notify AGAIN when the actor being killed is
 * itself supervised (nested supervision — a real, tested configuration) —
 * on the SAME thread, into the SAME non-recursive mutex. do_actor_death
 * also runs arbitrary March cleanup closures; any cleanup that calls
 * kill() on any supervised actor hit the identical self-deadlock. Worse,
 * march_respawn_child's spawn_clo call and any cleanup closure are
 * compiled March code that can yield on cooperative preemption —
 * swapcontext with the mutex held either re-dispatches another crashing
 * actor onto the SAME OS thread (relock deadlock) or migrates this green
 * thread to a DIFFERENT OS thread, so the eventual unlock happens from a
 * non-owner thread (undefined behavior; the mutex ends up permanently
 * wedged either way). Every current use below is a leaf: no do_actor_death,
 * no march_respawn_child, no March closure ever runs while g_supervise_mu
 * is held.
 *
 * PRE-EXISTING HAZARD this closes (was never safe before Task 16 either):
 * do_actor_death calls march_supervisor_notify with no lock held, and
 * do_actor_death can run on the crashing actor's own scheduler thread (the
 * crash trap in actor_green_thread) or on any foreign thread (march_kill
 * from an evloop) — so two children of the SAME supervisor crashing
 * concurrently on different threads could run march_restart_budget_ok's
 * sup_restart_ts realloc concurrently, which is heap corruption. Task 16
 * added child->crash_streak/last_crash_ms writes to that same
 * unsynchronized surface, which is why closing the race landed here.
 *
 * Lock ordering: g_supervise_mu is OUTER, g_tbl_mu is INNER wherever both
 * are used in the same call chain — but per the leaf-lock contract above,
 * nothing that itself takes g_tbl_mu (find_or_create_meta,
 * march_respawn_child) ever runs while g_supervise_mu is held, so in
 * practice the two mutexes are never nested at all. */
static pthread_mutex_t g_supervise_mu = PTHREAD_MUTEX_INITIALIZER;

/* Returns 1 (and appends `now` to sup_meta's restart history) if a restart
 * is currently permitted under its max_restarts-within-window budget;
 * returns 0 (budget exceeded — caller must crash the supervisor itself)
 * otherwise. Mirrors the identical window-check inlined in all three of
 * eval.ml's one_for_one_restart / one_for_all_restart / rest_for_one_restart. */
static int march_restart_budget_ok(march_actor_meta *sup_meta) {
    /* Task 14: march_now_ms() is CLOCK_MONOTONIC-backed (see its definition
     * in march_scheduler.c), unlike gettimeofday's wall clock, which an NTP
     * step or manual clock change can jump backward or forward — either
     * direction corrupts this budget: a backward step makes `now -
     * sup_restart_ts[i]` go negative (never prunes old entries, so the
     * budget can never refill), and a forward step silently discards recent
     * restarts as "outside the window" too early, letting a crash loop
     * through the budget it exists to stop. */
    double now = (double)march_now_ms() / 1000.0;
    double window = (double)sup_meta->supervisor_window_secs;
    /* Task 16 fix-up (Critical 1/2): g_supervise_mu is a LEAF lock — see its
     * declaration comment. This is its only remaining use in the restart
     * path: it protects the sup_restart_ts realloc against two children of
     * the same supervisor crashing concurrently on different threads (the
     * original motivation for the mutex). No user code (no do_actor_death,
     * no march_respawn_child, no March closure) runs under it. */
    pthread_mutex_lock(&g_supervise_mu);
    int kept = 0;
    for (int i = 0; i < sup_meta->sup_restart_len; i++) {
        if (now - sup_meta->sup_restart_ts[i] < window) {
            sup_meta->sup_restart_ts[kept++] = sup_meta->sup_restart_ts[i];
        }
    }
    sup_meta->sup_restart_len = kept;
    if (kept >= sup_meta->supervisor_max_restarts) {
        pthread_mutex_unlock(&g_supervise_mu);
        return 0;
    }
    sup_meta->sup_restart_ts = realloc(sup_meta->sup_restart_ts,
                                        (size_t)(kept + 1) * sizeof(double));
    sup_meta->sup_restart_ts[kept] = now;
    sup_meta->sup_restart_len = kept + 1;
    pthread_mutex_unlock(&g_supervise_mu);
    return 1;
}

/* Spawn a fresh replacement for sup_children[child_idx], link it to the
 * supervisor in that SAME slot (never appends — march_actor_register_child
 * is only for a child's initial spawn), inherit the crashed child's
 * epoch+1 (matching eval.ml spawn_child_actor's stale-capability-detection
 * inheritance), and write the new pid_index into the supervisor's state. */
/* Restart policy encoding, shared with lower_actor.ml's restart_type_int and
 * Ast.restart_type: 0 permanent, 1 transient, 2 temporary. */
#define MARCH_RESTART_PERMANENT 0
#define MARCH_RESTART_TRANSIENT 1
#define MARCH_RESTART_TEMPORARY 2

/* Should a child with policy [restart_type] be brought back after dying for
 * [reason]?  The whole table, in one place, because it is consulted from two
 * unrelated sites (march_supervisor_notify's filter and the batch strategies'
 * respawn loops) and they must not drift:
 *
 *   policy      CRASH   KILLED   NORMAL
 *   permanent   yes     yes      no
 *   transient   yes     no       no
 *   temporary   no      no       no
 *
 * NOTE March's `permanent` is deliberately NOT OTP's: OTP restarts a permanent
 * child even on a normal exit, while do_actor_death has always guarded the
 * notify with `reason != MARCH_DEATH_NORMAL`. Matching OTP here would silently
 * change every supervise block ever written. See
 * specs/2026-09-08-supervise-child-spec-design.md §4. */
static int march_child_should_restart(int32_t restart_type,
                                      march_death_reason reason) {
    if (reason == MARCH_DEATH_NORMAL) return 0;
    switch (restart_type) {
        case MARCH_RESTART_TRANSIENT: return reason == MARCH_DEATH_CRASH;
        case MARCH_RESTART_TEMPORARY: return 0;
        default:                      return 1;   /* permanent */
    }
}

/* The reason [meta] died, as the restart filter should see it. An unset
 * terminal_reason reads as CRASH on purpose: an unknown reason must restart a
 * permanent child (today's behaviour) rather than silently retire it. */
static march_death_reason march_meta_death_reason(march_actor_meta *meta) {
    march_pid_entry *pe = meta ? meta->pe : NULL;
    if (!pe || !atomic_load_explicit(&pe->terminal_set, memory_order_acquire))
        return MARCH_DEATH_CRASH;
    return pe->terminal_reason;
}

/* [supervisor] is the supervisor's record and [sup_meta] its meta, both
 * pinned by the caller (meta_pin) for the whole restart: the spawn closure
 * below is March code, so this can switch threads and wait. */
static void *march_respawn_child(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    march_sup_child *child = &sup_meta->sup_children[child_idx];
    int64_t old_pid_index = ((int64_t *)supervisor)[4 + child->word_idx];
    /* The dead incarnation's TOMBSTONE, not its meta (which is freed once its
     * death is processed): the epoch is all the replacement needs from it,
     * and the tombstone is never freed.  Only THIS supervisor's restarts
     * write this slot's epochs, so a relaxed read suffices. */
    march_pid_entry *old_pe = pid_entry(old_pid_index);
    int64_t inherited_epoch = old_pe ? atomic_load_explicit(&old_pe->epoch,
                                             memory_order_relaxed) + 1 : 0;

    /* spawn_clo is a March closure cell (offset-16 word = $clo_wrap function
     * pointer), NOT a raw C function pointer — see march_sup_child's field
     * comment. The cell is always a ZERO-ARG thunk — the static
     * <ActorName>_spawn reference for a child without `init` arguments, or a
     * lifted lambda that calls <ActorName>_spawn with the captured arguments
     * (D24) — so its wrapper's only parameter is the closure cell itself
     * (contrast the 2-arg cleanup-closure convention in do_actor_death, whose
     * underlying function is Unit -> Unit). */
    typedef void *(*spawn_clo_fn_t)(void *);
    void **clo_fields = (void **)((char *)child->spawn_clo + 16);
    spawn_clo_fn_t fn_ptr = (spawn_clo_fn_t)(*clo_fields);
    /* Every apply function drops the closure it is handed (Perceus's
     * callee-side $clo release), and this cell is called on EVERY respawn of
     * the slot, so keep our reference: without the inc the first respawn
     * frees the cell and the second is a use-after-free.  For the static
     * <Actor>_spawn reference a non-capturing child passes, IS_HEAP_PTR
     * makes this a no-op, exactly as the drop is.  (A heap closure arrives
     * here when the child has `init` arguments — lower_actor.ml's respawn
     * thunk, D24 — and in a --test build when the child is itself a
     * supervisor whose spawn glue carries capabilities; see cap_passing.ml.) */
    march_incrc(child->spawn_clo);
    void *raw = fn_ptr(child->spawn_clo);
    void *new_child = march_spawn_supervised(raw);

    /* Take what the dead incarnation stashed on this slot (its names and its
     * spawn-site capability; stash_child_for_restart). */
    pthread_mutex_lock(&g_supervise_mu);
    char **names = child->pending_names;
    int    n_names = child->pending_name_count;
    void  *cap = child->pending_spawn_cap;
    child->pending_names = NULL;
    child->pending_name_count = 0;
    pthread_mutex_unlock(&g_supervise_mu);

    /* From here to the activation nothing switches (march_actor_register is
     * plain C under leaf locks), so one critical section covers new_meta.
     * The child is not activated yet, so nothing but a kill by pid can end
     * it meanwhile, and then the activation below simply finds it dead. */
    march_reclaim_enter();
    march_actor_meta *new_meta = find_meta(new_child);
    if (new_meta) {
        pthread_mutex_lock(&g_tbl_mu);
        new_meta->sup_pe = sup_meta->pe;
        new_meta->sup_child_index = child_idx;
        atomic_store_explicit(&new_meta->pe->epoch, inherited_epoch,
                              memory_order_release);
        /* Capture-at-spawn (--test builds only ever set it): the replacement
         * inherits the crashed incarnation's captured capability record, so
         * a mock that reached the child reaches its restart.  The record is
         * retained forever (never freed), so sharing the pointer needs no RC. */
        if (cap)
            atomic_store_explicit(&new_meta->spawn_cap, cap, memory_order_release);
        pthread_mutex_unlock(&g_tbl_mu);
        ((int64_t *)supervisor)[4 + child->word_idx] =
            pe_pid_or_0(new_meta->pe);
    }

    /* Task 6: carry the crashed incarnation's registered names forward onto
     * the replacement.  march_actor_register's normal get-then-set contract
     * decides each name individually: if nothing else claimed it while this
     * child was down, the replacement gets it, indistinguishable from the
     * crashed incarnation having held it the whole time; if some OTHER live
     * actor registered that exact name during the gap (a real race, however
     * unlikely inside a restart window), register returns 0 and that name
     * is deliberately DROPPED here rather than stolen back — the name
     * legitimately belongs to whoever holds it now, the same "first live
     * claim wins" rule that governs every other registration. Not logged:
     * this is not an error, just the registry's normal contract playing out. */
    for (int i = 0; i < n_names; i++) {
        void *key = march_string_lit(names[i], (int64_t)strlen(names[i]));
        if (new_meta) march_actor_register(key, new_child);
        march_decrc(key);   /* release our own ref from march_string_lit */
        free(names[i]);
    }
    free(names);

    /* Publication above is complete before this proc can run and install its
     * supervised panic trap. */
    if (new_meta) activate_actor_green_thread(new_meta);
    march_reclaim_exit();

    return new_child;
}

/* one_for_one: only the crashed child is respawned; siblings untouched.
 * Mirrors eval.ml:1588-1637. */
static void march_one_for_one_restart(void *supervisor, march_actor_meta *sup_meta, int child_idx) {
    if (child_idx < 0 || child_idx >= sup_meta->sup_num_children) return;
    if (!march_restart_budget_ok(sup_meta)) {
        do_actor_death(supervisor, MARCH_DEATH_CRASH,
                       "restart intensity exceeded",
                       sizeof("restart intensity exceeded") - 1);
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
        do_actor_death(supervisor, MARCH_DEATH_CRASH,
                       "restart intensity exceeded",
                       sizeof("restart intensity exceeded") - 1);
        return;
    }
    int n = sup_meta->sup_num_children;
    if (n == 0) return;
    meta_pin live_children[n];
    for (int i = 0; i < n; i++) {
        int64_t stored_pid_index = ((int64_t *)supervisor)[4 + sup_meta->sup_children[i].word_idx];
        /* Pinned by pid: a live child's meta and a counted reference to its
         * record, so neither can be freed across the kills below.  The
         * originally-crashed child is already dead at this point (Task 4's
         * do_actor_death ran on it before calling march_supervisor_notify),
         * so it pins as nothing and is only respawned (not double-killed) in
         * the loop below. */
        live_children[i] = meta_pin_pe(pid_entry(stored_pid_index));
        if (live_children[i].m) {
            /* Task 6, round-1 review fix: stash this sibling's registered
             * names BEFORE clearing sup_pe below — we already know for
             * certain it's about to be killed and respawned (the budget check
             * above already passed), but do_actor_death's own stash is gated
             * on sup_pe, which the next line clears purely to suppress a
             * recursive notify. See stash_child_for_restart's comment. */
            stash_child_for_restart(live_children[i].m, sup_meta, i);
            pthread_mutex_lock(&g_tbl_mu);
            live_children[i].m->sup_pe = NULL;
            pthread_mutex_unlock(&g_tbl_mu);
        }
    }
    for (int i = 0; i < n; i++) {
        if (live_children[i].m)
            do_actor_death(live_children[i].actor, MARCH_DEATH_KILLED, NULL, 0);
        meta_unpin(live_children[i]);
    }
    for (int i = 0; i < n; i++) {
        /* A `temporary` sibling swept up by this batch is killed like any
         * other, but must NOT come back — the kill above is internal
         * machinery, the respawn here is the actual restart decision. Missing
         * this is invisible to every single-child test: the child resurrects
         * only when a SIBLING crashes. */
        if (sup_meta->sup_children[i].restart_type == MARCH_RESTART_TEMPORARY)
            continue;
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
        do_actor_death(supervisor, MARCH_DEATH_CRASH,
                       "restart intensity exceeded",
                       sizeof("restart intensity exceeded") - 1);
        return;
    }
    int n = sup_meta->sup_num_children;
    meta_pin live_children[n];
    for (int i = 0; i < n; i++) live_children[i] = (meta_pin){ NULL, NULL };
    for (int i = child_idx + 1; i < n; i++) {
        int64_t stored_pid_index = ((int64_t *)supervisor)[4 + sup_meta->sup_children[i].word_idx];
        live_children[i] = meta_pin_pe(pid_entry(stored_pid_index));
        if (live_children[i].m) {
            /* See march_one_for_all_restart's identical comment — same
             * fix, same reasoning: stash before clearing sup_pe, since
             * do_actor_death's own stash won't see it set by the time it
             * runs for this sibling. */
            stash_child_for_restart(live_children[i].m, sup_meta, i);
            pthread_mutex_lock(&g_tbl_mu);
            live_children[i].m->sup_pe = NULL;
            pthread_mutex_unlock(&g_tbl_mu);
        }
    }
    for (int i = child_idx + 1; i < n; i++) {
        if (live_children[i].m)
            do_actor_death(live_children[i].actor, MARCH_DEATH_KILLED, NULL, 0);
        meta_unpin(live_children[i]);
    }
    for (int i = child_idx; i < n; i++) {
        /* See march_one_for_all_restart's identical skip. */
        if (sup_meta->sup_children[i].restart_type == MARCH_RESTART_TEMPORARY)
            continue;
        march_respawn_child(supervisor, sup_meta, i);
    }
}

typedef struct {
    int64_t sup_pid_index;  /* incarnation-precise identity; see sup_still_live */
    int     child_idx;
    int     strategy;       /* 0/1/2 — mirrors supervisor_strategy */
    int64_t not_before_ms;
} march_delayed_restart;

/* Incarnation-precise liveness of a restart's supervisor, which the caller
 * has pinned (so [sup_meta] is valid memory whatever happened meanwhile).
 * The supervisor is live exactly while its meta is still linked, which its
 * tombstone's `live` field says without touching the record: the death claim
 * clears it under g_tbl_mu.  This replaces two older probes that could be
 * fooled: march_is_alive(supervisor), an ADDRESS probe that a reused address
 * reads as alive (and that dereferenced a possibly-freed record), and an
 * address-keyed find_meta, which could resolve to a newer actor's meta.
 * See specs/progress/2026-08-16-delayed-restart-incarnation-precise.md. */
static int sup_still_live(march_actor_meta *sup_meta) {
    return atomic_load_explicit(&sup_meta->pe->live, memory_order_acquire)
           == sup_meta;
}

/* Runs on its own dedicated green thread (spawned by march_supervisor_notify
 * below), never on the crashing actor's scheduler thread. Parks until the
 * backoff deadline, then re-validates the supervisor is still alive before
 * running the (possibly budget-gated) restart strategy.
 *
 * Critical 1/2 fix-up: g_supervise_mu is never held across
 * march_one_for_one_restart/march_one_for_all_restart/march_rest_for_one_
 * restart, which run March closures (march_respawn_child's spawn_clo) and
 * can call do_actor_death (budget exhaustion, one_for_all's sibling kills)
 * — see g_supervise_mu's leaf-lock contract above march_restart_budget_ok.
 *
 * Review round 3 fix-up (found while validating round 2's widening fix,
 * under MARCH_NUM_SCHEDULERS>1 — this codebase's default, true OS-thread
 * parallelism across actors): an earlier version of this function cleared
 * delayed_batch_pending BEFORE calling the strategy, then called it with
 * the lock released. That opened a real window: a DIFFERENT child crashing
 * on another OS thread, between the clear and the strategy call actually
 * finishing, would see delayed_batch_pending already 0 and — for a
 * first-time (streak==1) crash — take the synchronous immediate-restart
 * path itself, launching a SECOND, fully concurrent, unsynchronized
 * march_one_for_all_restart/march_rest_for_one_restart racing this one.
 * The race itself is established by code-level argument (the window is
 * real and reachable, independent of any specific empirical outcome); the
 * uncaught-panic crashes observed while chasing it down were confounded
 * with a separate, pre-existing bug (see
 * specs/todos/2026-08-12-supervised-child-registration-race.md) that also
 * needs true parallelism to trigger, so they aren't offered as a clean
 * reproduction of THIS race specifically — MARCH_NUM_SCHEDULERS=1 making
 * the crashes disappear is consistent with either bug being the cause,
 * since both require real OS-thread concurrency.
 *
 * Fixed by keeping delayed_batch_pending SET for the entire in-flight
 * duration of the strategy call (batch strategies only), not just up to
 * the moment it starts, and looping: after each strategy call returns,
 * re-check whether any crash was DROPPED (skip_due_to_pending) while the
 * strategy was running — such a crash can only arrive as a drop, never as
 * a competing restart, because the flag never went false during that
 * window. If so, some child was not covered by the pass that just ran, so
 * loop and restart again (no additional delay: the point of backoff is
 * per-crash pacing, already served by the original park). Only once a
 * pass completes with no further drops is the flag finally cleared.
 * one_for_one needs none of this — a dead slot cannot crash again, so
 * there is only ever the one child_idx to restart, no pending flag, and
 * no race to close.
 *
 * Round-3 correction: checking only "did pending_min_child_idx get
 * LOWER" (round 2's original absorb condition) undercounts drops. A
 * sibling at index >= the idx this pass is about to use — e.g. a
 * freshly-respawned incarnation from an EARLIER pass of this SAME
 * in-flight restart, crashing again before the flag is cleared — is
 * dropped via skip_due_to_pending exactly like a lower-index one, but
 * widening pending_min_child_idx against it is a no-op (it's already <=
 * the new index), so the old min-idx-only check saw no change and cleared
 * the flag, stranding that incarnation dead forever — the identical
 * symptom class round 2 fixed, just at same/higher indexes instead of
 * lower ones. sup_meta->pending_drop_count (incremented on EVERY drop,
 * not just ones that lower the min) is what the loop actually compares
 * now: snapshot it before the pass, and after the pass, in the same
 * critical section that would otherwise clear the flag, re-run if it
 * advanced (using whatever pending_min_child_idx reads at that point —
 * the widening logic for the index itself is unchanged). */
static void delayed_restart_thread(void *arg) {
    march_delayed_restart *dr = (march_delayed_restart *)arg;
    while (march_now_ms() < dr->not_before_ms)
        march_sched_park_self_until(dr->not_before_ms);
    int64_t sup_pid_index = dr->sup_pid_index;
    int child_idx = dr->child_idx, strategy = dr->strategy;
    free(dr);
    /* Resolve the supervisor by pid index, never by its (possibly reused)
     * record address, and pin it: the strategies below run March code and
     * can switch threads.  A supervisor that died during the backoff pins as
     * nothing, and the restart is simply dropped with it (its meta, and any
     * flag left set on it, is freed with the supervisor). */
    meta_pin sup = meta_pin_pe(pid_entry(sup_pid_index));
    if (!sup.m) return;
    march_actor_meta *sup_meta = sup.m;
    void *supervisor = sup.actor;

    if (strategy == 0) {
        march_one_for_one_restart(supervisor, sup_meta, child_idx);
        meta_unpin(sup);
        return;
    }

    for (;;) {
        /* Minor 1 (TOCTOU): re-check liveness on every pass, not just the
         * first — the supervisor can die while an earlier pass's strategy
         * call was running. */
        pthread_mutex_lock(&g_supervise_mu);
        int alive = sup_still_live(sup_meta);
        int idx = sup_meta->pending_min_child_idx;
        int64_t drops_before = sup_meta->pending_drop_count;
        pthread_mutex_unlock(&g_supervise_mu);
        if (!alive) break;

        switch (strategy) {
            case 1: march_one_for_all_restart(supervisor, sup_meta, idx); break;
            case 2: march_rest_for_one_restart(supervisor, sup_meta, idx); break;
            default: break;
        }
        if (strategy != 1 && strategy != 2) break;

        /* delayed_batch_pending is STILL SET here — any crash that arrived
         * while the strategy call above was running could only be DROPPED
         * (skip_due_to_pending) and bump pending_drop_count, never start a
         * competing restart of its own. Comparing pending_drop_count
         * (round 3) rather than just pending_min_child_idx (round 2) is
         * required: a drop at an index >= idx widens nothing (the min-idx
         * check alone would see no change and wrongly conclude nothing
         * happened), but it's still a real drop of a child that this pass
         * did not cover — the SAME incarnation this pass may have just
         * respawned, if it crashed again before we get here. Any advance
         * means loop again, using whatever pending_min_child_idx reads now
         * (the widening logic for the index is unchanged from round 2). */
        pthread_mutex_lock(&g_supervise_mu);
        if (sup_meta->pending_drop_count != drops_before) {
            pthread_mutex_unlock(&g_supervise_mu);
            continue;
        }
        sup_meta->delayed_batch_pending = 0;
        pthread_mutex_unlock(&g_supervise_mu);
        break;
    }
    meta_unpin(sup);
}

/* Task 16: exponential backoff with jitter on repeat crashes of the same
 * child slot. The FIRST crash of a slot (crash_streak becomes 1) keeps the
 * pre-Task-16 synchronous, zero-delay restart exactly — this is what keeps
 * every existing supervision golden (examples/supervision_strategies.march,
 * the native supervision tests) byte-identical, since they each crash a
 * given child once. Only a REPEAT crash (streak > 1) takes the delayed
 * green-thread path, delaying the whole batch (one_for_all/rest_for_one
 * included) by the crashed child's streak delay.
 *
 * Important 2 fix-up: for the batch strategies (one_for_all/rest_for_one),
 * sup_meta->delayed_batch_pending prevents a SECOND batch restart —
 * synchronous or delayed — from being scheduled while one is already
 * pending. Without this, a delayed batch restart for child A racing an
 * intervening synchronous (first-crash) restart for child B would let the
 * later-firing one re-kill the freshly-respawned children from the earlier
 * one and double-charge the restart budget. An intervening crash (of
 * either child) while a batch restart is pending simply waits — for
 * one_for_all the pending restart already covers every child regardless.
 * For rest_for_one that is NOT automatically true: its restart window is
 * [child_idx, n), so an intervening crash of a LOWER-index sibling would be
 * silently outside that window and left dead forever (nothing else will
 * ever crash it again to trigger a fresh restart). sup_meta->
 * pending_min_child_idx tracks the lowest index that crashed during the
 * pending window (seeded from the index that claimed the flag, then only
 * ever lowered) and delayed_restart_thread uses it — not the original
 * claimant's own index — as the child_idx it hands to the strategy, so the
 * eventual restart widens down to cover every child that crashed in the
 * window. one_for_one is exempt from all of this — a dead slot cannot
 * crash again, so there is no batch to double and no widening needed. */
/* [sup] is the crashed child's supervisor, pinned by the caller (see
 * do_actor_death) for as long as this runs: the synchronous strategies below
 * run March code and can switch threads. */
static void march_supervisor_notify(meta_pin sup, march_actor_meta *crashed_meta) {
    march_actor_meta *sup_meta = sup.m;
    void *supervisor = sup.actor;
    int child_idx = crashed_meta->sup_child_index;
    if (child_idx < 0 || child_idx >= sup_meta->sup_num_children) return;
    march_sup_child *child = &sup_meta->sup_children[child_idx];

    /* Per-child restart policy (specs/2026-09-08-supervise-child-spec-design.md).
     * Placed HERE, before the g_supervise_mu section below, on purpose: that
     * section does the crash_streak read-modify-write that feeds the restart
     * budget, and a death that will not restart must charge nothing. Filtering
     * after it would let a program that retires N `temporary` children walk a
     * perfectly healthy supervisor toward its max_restarts ceiling. */
    if (!march_child_should_restart(child->restart_type,
                                    march_meta_death_reason(crashed_meta))) {
        if (getenv("MARCH_SUP_TRACE"))
            fprintf(stderr, "march: supervisor child=%d retired"
                    " (restart_type=%d, reason=%d) -- not restarting\n",
                    child_idx, (int)child->restart_type,
                    (int)march_meta_death_reason(crashed_meta));
        return;
    }

    int strategy = sup_meta->supervisor_strategy;
    int is_batch = (strategy == 1 || strategy == 2);

    /* Leaf-lock section: streak/last_crash_ms read-modify-write, the
     * pending-batch check, and (if this crash is the one that will own the
     * delayed restart) claiming delayed_batch_pending — all decided
     * atomically in ONE critical section so two children racing into
     * streak>1 concurrently can't both see "not pending" and both schedule
     * a batch restart. No user code runs here. */
    int64_t now;
    int32_t streak;
    int skip_due_to_pending, claimed_batch, claimed_sync_batch = 0;
    int64_t drops_before = 0;
    pthread_mutex_lock(&g_supervise_mu);
    now = march_now_ms();
    int64_t window_ms = (int64_t)sup_meta->supervisor_window_secs * 1000;
    if (child->last_crash_ms != 0 && now - child->last_crash_ms > window_ms)
        child->crash_streak = 0;           /* survived a full window: healed */
    child->crash_streak++;
    child->last_crash_ms = now;
    streak = child->crash_streak;
    skip_due_to_pending = is_batch && (sup_meta->delayed_batch_pending
                                       || sup_meta->batch_restart_in_flight);
    claimed_batch = 0;
    if (skip_due_to_pending) {
        /* Review round 2 fix: this crash is being dropped (no restart of
         * its own — the pending batch restart will cover it), but for
         * rest_for_one that pending restart's window only reaches down to
         * pending_min_child_idx. Widen it (never narrow) so this child
         * isn't left outside the eventual restart's [idx, n) range. */
        if (child_idx < sup_meta->pending_min_child_idx)
            sup_meta->pending_min_child_idx = child_idx;
        /* Review round 3 fix: EVERY drop counts here, regardless of
         * whether it widened pending_min_child_idx — delayed_restart_
         * thread's absorb loop needs to know a drop happened even when
         * child_idx >= the current min (e.g. a freshly-respawned sibling
         * from an earlier in-flight pass crashing again), since that drop
         * still leaves a child uncovered by the pass that's using the
         * unchanged min. See pending_drop_count's field comment. */
        sup_meta->pending_drop_count++;
    } else if (is_batch && streak > 1) {
        sup_meta->delayed_batch_pending = 1;
        sup_meta->pending_min_child_idx = child_idx;
        claimed_batch = 1;
    } else if (is_batch) {
        /* streak == 1: this crash will take the synchronous delay==0 path
         * below. Claim the in-flight marker HERE, inside the same critical
         * section that decided we are not skipping, so a sibling's
         * first crash arriving on another thread sees it and is deflected
         * into skip_due_to_pending (widening pending_min_child_idx and
         * counting the drop) exactly as it would be for a delayed restart.
         * drops_before is snapshotted in this SAME critical section, not
         * after the unlock, so a sibling deflected in the gap between the
         * unlock and the first strategy call is still absorbed. */
        sup_meta->batch_restart_in_flight = 1;
        sup_meta->pending_min_child_idx = child_idx;
        drops_before = sup_meta->pending_drop_count;
        claimed_sync_batch = 1;
    }
    int64_t delay = 0;
    if (streak > 1) {
        /* Same curve as ever, with the three constants now read from the
         * supervise block (Ast.default_backoff keeps them at 25 / 5000 / 25
         * when no `backoff` clause is written, so every existing program and
         * every supervision golden sees identical delays). Defensive
         * fallbacks: a meta registered before this field existed, or by a C
         * caller that passed nothing, reads 0 here. */
        int64_t base = sup_meta->backoff_base_ms > 0 ? sup_meta->backoff_base_ms : 25;
        int64_t cap  = sup_meta->backoff_cap_ms >= base ? sup_meta->backoff_cap_ms : 5000;
        int64_t jitter_pct = sup_meta->backoff_jitter_pct;
        if (jitter_pct < 0 || jitter_pct > 100) jitter_pct = 25;
        int shift = streak > 8 ? 7 : streak - 1;
        delay = base << shift;             /* 50,100,...,3200 at base 25 */
        if (delay > cap || delay < 0) delay = cap;
        /* +/-jitter_pct of the delay, seeded off a process-wide counter —
         * Math.random is not available here and rand() is process-global
         * anyway; a weak LCG is plenty for de-synchronizing a crash-storm's
         * retries. jitter_pct 0 disables it (the span below collapses to 0,
         * and `s % 1` is 0, so delay is left exactly on the curve). */
        static _Atomic uint32_t jitter_seed = 0x9E3779B9u;
        int64_t half_span = delay * jitter_pct / 100;   /* the +/- radius */
        uint32_t s = atomic_fetch_add_explicit(&jitter_seed, 0x9E3779B9u,
                                               memory_order_relaxed);
        s ^= s >> 16; s *= 0x45d9f3bu; s ^= s >> 16;
        delay += (int64_t)(s % (uint32_t)(2 * half_span + 1)) - half_span;
    }
    if (getenv("MARCH_SUP_TRACE"))
        fprintf(stderr, "march: supervisor backoff child=%d streak=%d delay_ms=%lld%s\n",
                child_idx, streak, (long long)delay,
                skip_due_to_pending
                    ? " (batch restart already pending, skipped)" : "");
    /* The unlock sits AFTER the trace line, not right after the decision
     * above, so trace lines from racing siblings come out in the order the
     * lock decided them: a claimant's line always precedes the line of the
     * sibling it deflected. Printed after the unlock, the deflected thread
     * could win the race to stderr and invert them, which made
     * test/native/supervisor_deflected_crash_absorbed flaky on CI. The delay
     * arithmetic above is lock-free and cheap; the stderr write under the
     * leaf lock only happens with MARCH_SUP_TRACE set. */
    pthread_mutex_unlock(&g_supervise_mu);

    if (skip_due_to_pending) return;

    /* Test seam (specs/todos/2026-08-17-supervision-race-test-seam.md, option
     * 2): MARCH_SUP_TEST_STALL_MS, read once, widens the gap between the
     * leaf-lock release above and the strategy call below from "a few
     * instructions" to a window a second OS thread can reliably land a
     * sibling crash inside. That is the interleaving the in-flight marker +
     * absorb loop exist for, and the only way to force it by construction
     * rather than by luck; test/native/supervisor_deflected_crash_absorbed
     * runs under it. Unset (the default) costs one cached getenv and nothing
     * else. Only the synchronous batch path stalls: a delayed restart already
     * has its backoff window, and a non-batch strategy has no marker to race. */
    if (claimed_sync_batch) {
        static _Atomic int stall_ms = -1;
        int ms = atomic_load_explicit(&stall_ms, memory_order_relaxed);
        if (ms < 0) {
            const char *e = getenv("MARCH_SUP_TEST_STALL_MS");
            ms = e ? atoi(e) : 0;
            if (ms < 0) ms = 0;
            atomic_store_explicit(&stall_ms, ms, memory_order_relaxed);
        }
        if (ms > 0) {
            /* Yield, don't sleep: a blocking usleep would pin this OS worker,
             * and a sibling whose crash is queued on THIS worker's run queue
             * would then only run after the stall — the exact opposite of
             * the interleaving the seam exists to force. Yielding keeps the
             * worker serving other green threads (the sibling included)
             * while this one loiters between the unlock and the strategy. */
            int64_t deadline = march_now_ms() + ms;
            while (march_now_ms() < deadline) {
                if (march_sched_current()) march_sched_yield();
                else usleep(1000);
            }
        }
    }

    if (delay == 0) {
        /* The first pass is unconditional and at child_idx, exactly as the
         * pre-fix code was — that is what keeps the single-crash supervision
         * goldens byte-identical. Everything below only engages when a
         * sibling was actually deflected mid-flight (pending_drop_count
         * advanced), which no golden does. */
        int idx = child_idx;
        for (;;) {
            switch (strategy) { /* today's immediate path */
                case 0: march_one_for_one_restart(supervisor, sup_meta, idx); break;
                case 1: march_one_for_all_restart(supervisor, sup_meta, idx); break;
                case 2: march_rest_for_one_restart(supervisor, sup_meta, idx); break;
                default: break;
            }
            if (!claimed_sync_batch) return;
            /* Absorb loop, mirroring delayed_restart_thread's. batch_restart_
             * in_flight is STILL SET here, so any sibling crash that landed
             * while the strategy above was running could only be DROPPED
             * (skip_due_to_pending), never start a competing restart — but a
             * drop performs no restart of its own, and NOTHING else will ever
             * crash that slot again to trigger one. The synchronous path has
             * no delayed_restart_thread to absorb those drops on its behalf,
             * so it must do it here or trade the race for a permanently dead
             * child. Two distinct ways a drop is left uncovered by the pass
             * that just ran:
             *   - rest_for_one's window is [idx, n): a deflected sibling at a
             *     LOWER index is outside it entirely (this is exactly the
             *     hazard pending_min_child_idx exists for on the delayed
             *     path);
             *   - either batch strategy: a slot this pass already respawned
             *     can crash again before we get here. That drop does not
             *     lower pending_min_child_idx, which is why the condition is
             *     pending_drop_count (round 3's correction), not the min.
             * Only once a pass completes with no further drops is the marker
             * cleared. No extra delay is introduced: streak==1 has none. */
            pthread_mutex_lock(&g_supervise_mu);
            if (sup_meta->pending_drop_count != drops_before) {
                drops_before = sup_meta->pending_drop_count;
                idx = sup_meta->pending_min_child_idx;
                /* The strategy can kill the SUPERVISOR (restart-intensity
                 * exhaustion -> do_actor_death), so re-check liveness before
                 * looping, as delayed_restart_thread does. If it died we
                 * return leaving the marker SET — same deliberate reasoning
                 * as there: clearing it on an orphaned meta would let some
                 * later crash of a child still pointing at this dead
                 * supervisor run a strategy against it. */
                /* Incarnation-precise, like delayed_restart_thread's
                 * recheck: sup_meta is pinned, and it is live exactly while
                 * it is still linked. */
                int alive = sup_still_live(sup_meta);
                pthread_mutex_unlock(&g_supervise_mu);
                if (!alive) return;
                continue;
            }
            sup_meta->batch_restart_in_flight = 0;
            pthread_mutex_unlock(&g_supervise_mu);
            return;
        }
    }
    march_delayed_restart *dr = malloc(sizeof *dr);
    if (!dr) {
        if (getenv("MARCH_SUP_TRACE"))
            fprintf(stderr,
                    "march: supervisor backoff child=%d streak=%d delay_ms=%lld"
                    " -- malloc failed, restart ABANDONED%s\n",
                    child_idx, streak, (long long)delay,
                    claimed_batch
                        ? " (any lower-index siblings that crashed and were"
                          " skipped while this batch restart was pending are"
                          " dropped along with it -- they stay dead until a"
                          " future crash schedules a new restart covering"
                          " their index)"
                        : "");
        /* Minor 2 aside: if this crash claimed delayed_batch_pending above
         * but the restart never actually gets scheduled, nothing would ever
         * clear the flag (delayed_restart_thread, the only clearer, never
         * runs) — every future crash of this supervisor's other children
         * would see skip_due_to_pending forever and the supervisor would
         * stop healing entirely. Roll the claim back so a later crash can
         * retry.
         *
         * Low (review round 2): between this crash claiming
         * delayed_batch_pending (in the earlier, now-released critical
         * section) and this rollback, some OTHER child could have crashed,
         * observed skip_due_to_pending, been dropped (no restart of its
         * own), and widened pending_min_child_idx down to its index — all
         * on the assumption that THIS crash's now-failing restart would
         * cover it. Rolling back loses that widening along with the flag,
         * so that child is stranded dead until some later crash (of any
         * child, anywhere at or below its index) schedules a fresh restart.
         * Under sustained OOM this is already a supervisor in serious
         * trouble; a full fix would mean re-deriving and re-dispatching for
         * every child crashed during the doomed window, which is not a
         * one-line change — documented here and in the trace above rather
         * than implemented, since OOM-at-malloc(sizeof(a few words)) is an
         * extreme, already-degraded scenario. */
        if (claimed_batch || claimed_sync_batch) {
            /* claimed_sync_batch cannot actually reach here today (it is only
             * ever set when streak == 1, which forces delay == 0 and returns
             * above), but rolling it back alongside claimed_batch keeps the
             * two claims symmetric: a stuck marker would silently disable
             * this supervisor's healing forever. */
            pthread_mutex_lock(&g_supervise_mu);
            sup_meta->delayed_batch_pending = 0;
            sup_meta->batch_restart_in_flight = 0;
            pthread_mutex_unlock(&g_supervise_mu);
        }
        return;
    }
    /* -1 for a supervisor not spawned yet (its child crashed during the
     * spawn glue): pid_entry(-1) is NULL, and the restart is dropped. */
    dr->sup_pid_index = pe_pid(sup_meta->pe);
    dr->child_idx = child_idx;
    dr->strategy = strategy;
    dr->not_before_ms = now + delay;
    /* D11: a restart runs the NEW code -- the current epoch, not the
     * epoch of whichever proc noticed the death. */
    march_sched_spawn_current(delayed_restart_thread, dr);
}

static void dispose_monitor_down(void *down) {
    if (!IS_HEAP_PTR(down)) return;
    int64_t *fields = (int64_t *)((char *)down + 16);
    void *target = (void *)(uintptr_t)fields[1];
    void *reason = (void *)(uintptr_t)fields[2];
    if (IS_HEAP_PTR(reason)
            && ((march_hdr *)reason)->tag == MARCH_DOWN_CRASH_TAG) {
        int64_t *reason_fields = (int64_t *)((char *)reason + 16);
        march_decrc((void *)(uintptr_t)reason_fields[0]);
    }
    march_decrc(reason);
    march_decrc(target);
    march_decrc(down);
}

static void deliver_monitor_down(void *watcher, int64_t mon_ref, void *target,
                                 march_death_reason reason,
                                 const char *message, size_t message_len) {
    /* A cheap early out (the watcher is dead or never spawned).  The decisive
     * check is repeated under g_tbl_mu below. */
    march_reclaim_enter();
    march_actor_meta *early = find_meta(watcher);
    int no_watcher = !early || !meta_gt(early);
    march_reclaim_exit();
    if (no_watcher) return;

    void *reason_value = march_alloc(reason == MARCH_DEATH_CRASH ? 24 : 16);
    ((march_hdr *)reason_value)->tag =
        reason == MARCH_DEATH_KILLED ? MARCH_DOWN_KILLED_TAG
      : reason == MARCH_DEATH_CRASH  ? MARCH_DOWN_CRASH_TAG
                                     : MARCH_DOWN_NORMAL_TAG;
    if (reason == MARCH_DEATH_CRASH) {
        const char *text = message ? message : "panic";
        size_t text_len = message ? message_len : sizeof("panic") - 1;
        int64_t *reason_fields = (int64_t *)((char *)reason_value + 16);
        reason_fields[0] = (int64_t)(uintptr_t)
            march_string_lit(text, (int64_t)text_len);
    }

    /* Down owns the target Pid and reason. Scalar fields use the uniform
     * tagged-slot encoding expected by generated boxed-pattern code. */
    void *down = march_alloc(40);
    ((march_hdr *)down)->tag = MARCH_DOWN_TAG;
    int64_t *down_fields = (int64_t *)((char *)down + 16);
    down_fields[0] = (mon_ref << 1) | 1;
    march_incrc(target);
    down_fields[1] = (int64_t)(uintptr_t)target;
    down_fields[2] = (int64_t)(uintptr_t)reason_value;

    /* Actor terminal ownership is claimed under g_tbl_mu (the death claim
     * unlinks the meta there) before the backing green thread reaches
     * PROC_DEAD. Scheduler-level liveness alone can therefore accept a Down
     * after the watcher is already logically dead. So the watcher is
     * resolved, and delivery decided, in the same g_tbl_mu critical section
     * as do_actor_death's claim: if delivery wins, the watcher was live at
     * enqueue ownership; if death wins, find_meta misses and the Down is
     * disposed locally. march_sched_send_control releases the mailbox lock
     * before waking and does not call a message disposer, so this lock order
     * has no inverse.  The meta and gt are resolved and used inside the
     * critical section. */
    int send_result = MARCH_SEND_DEAD;
    march_reclaim_enter();
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *watcher_meta = find_meta(watcher);
    march_proc *gt = watcher_meta ? meta_gt(watcher_meta) : NULL;
    if (gt && actor_alive_load(watcher))
        send_result = march_sched_send_control(gt, down);
    pthread_mutex_unlock(&g_tbl_mu);
    march_reclaim_exit();

    if (send_result != MARCH_SEND_OK)
        dispose_monitor_down(down);
}

/* The death claim, and the meta's unlink.  Caller holds g_tbl_mu and has
 * checked that [actor] is alive and [meta] (if any) still linked.  Publishes
 * death (alive = 0), writes the terminal reason on the tombstone, detaches
 * the monitor and cleanup lists into *monitors / *cleanups, and unlinks the
 * meta: from here on no lookup finds it, and the caller owns the reference
 * g_actor_tbl held.  The tombstone is published for address lookups BEFORE
 * the unlink, so a reader that misses g_actor_tbl finds it. */
static void death_claim_locked(void *actor, march_actor_meta *meta,
                               march_death_reason reason,
                               const char *message, size_t message_len,
                               march_monitor_node **monitors,
                               march_cleanup_node **cleanups) {
    /* Publish death in the initial terminal claim. Any cleanup callback,
     * registry observer, or Down receiver now sees is_alive == false. */
    actor_alive_store(actor, 0);
    if (!meta) return;
    march_pid_entry *pe = meta->pe;
    pe->terminal_reason = reason;
    if (reason == MARCH_DEATH_CRASH) {
        const char *text = message ? message : "panic";
        size_t text_len = message ? message_len : sizeof("panic") - 1;
        pe->terminal_message = malloc(text_len + 1);
        if (!pe->terminal_message) {
            pthread_mutex_unlock(&g_tbl_mu);
            fputs("march: out of memory storing actor crash reason\n", stderr);
            exit(1);
        }
        memcpy(pe->terminal_message, text, text_len);
        pe->terminal_message[text_len] = '\0';
        pe->terminal_message_len = text_len;
    }
    atomic_store_explicit(&pe->terminal_set, 1, memory_order_release);
    *monitors = meta->monitor_head;
    meta->monitor_head = NULL;
    /* Detach the cleanup list under the SAME lock, for the same reason
     * the monitor list is detached here: march_register_resource
     * prepends to meta->cleanup_head under g_tbl_mu (see its own
     * comment), so an unlocked walk-and-free here can race a concurrent
     * prepend and free a node the other thread just linked, or drop a
     * node the other thread is still linking onto what it thinks is the
     * live head. The closures themselves must NOT run under the lock —
     * they are arbitrary March code and can re-enter the runtime and
     * re-acquire g_tbl_mu — so this only detaches the head; the walk
     * runs after unlocking, on a list nothing else can still reach. */
    *cleanups = meta->cleanup_head;
    meta->cleanup_head = NULL;
    tomb_insert_locked(pe);
    atomic_store_explicit(&pe->live, NULL, memory_order_release);
    meta_unlink_locked(meta);
}

/* Mark `actor` dead, run its cleanup callbacks and monitor Down-notifications,
 * and wake its green thread. Non-normal deaths also notify a supervisor (if
 * present) for a possible restart. The ONE place that does this, called by an
 * explicit kill() and by a panic inside a supervised actor's handler
 * (the crash trap in actor_green_thread below) — mirrors the interpreter's
 * kill = crash_actor unification (eval.ml:3004-3006).
 *
 * [actor] must be a record the caller holds (the caller's own, a counted
 * reference, or the dying actor's thread's live reference). */
static void do_actor_death(void *actor, march_death_reason reason,
                           const char *message, size_t message_len) {
    march_monitor_node *monitors = NULL;
    march_cleanup_node *cleanups = NULL;

    /* Claim terminal state, detach the monitor list atomically with
     * demonitor/monitor registration, and unlink the meta.  Cleanup may
     * invoke arbitrary March code, so the table lock is released before any
     * callback runs.  The claim hands this function the table's reference to
     * the meta, which keeps it valid (across switches too) until the
     * meta_put at the end. */
    march_reclaim_enter();
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *meta = find_meta(actor);
    if (!actor_alive_load(actor)) {
        pthread_mutex_unlock(&g_tbl_mu);
        march_reclaim_exit();
        return;
    }
    death_claim_locked(actor, meta, reason, message, message_len,
                       &monitors, &cleanups);
    pthread_mutex_unlock(&g_tbl_mu);
    march_reclaim_exit();
    march_pid_entry *pe = meta ? meta->pe : NULL;

    /* Run cleanup callbacks in reverse acquisition order (cleanup_head was
     * most recently registered → already LIFO order). */
    if (cleanups) {
        /* The cleanup function is a March closure: fn(_ : Unit) : Unit.
         * Call it via the closure dispatch convention:
         *   closure[16] = function pointer, called as fn(closure, unit_arg) */
        march_cleanup_node *node = cleanups;
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
    }

    /* The supervisor, pinned (its meta, and a reference to its record) for
     * the stash below and the notify at the end, IF this actor is supervised
     * and its death is one a restart may follow.  NULL if the supervisor has
     * died itself, in which case nothing will restart this child. */
    meta_pin sup = { NULL, NULL };
    if (meta && reason != MARCH_DEATH_NORMAL) {
        pthread_mutex_lock(&g_tbl_mu);
        march_pid_entry *sup_pe = meta->sup_pe;
        if (sup_pe)
            sup = meta_pin_locked(atomic_load_explicit(&sup_pe->live,
                                                       memory_order_relaxed));
        pthread_mutex_unlock(&g_tbl_mu);
    }

    /* Retire this actor's registered names BEFORE any Down notification
     * fires (below). A watcher woken by a Down that immediately calls
     * whereis/registered must not observe a name still mapped to this dead
     * incarnation — placing the retire here, ahead of the monitor walk,
     * closes that window entirely rather than merely narrowing it (unlike
     * Elixir, which relies on an EXIT signal racing a separate registry
     * process).
     *
     * Task 6: before that retire wipes meta->reg_names, stash them on the
     * restart's slot IF this actor is supervised — only a supervised actor
     * can possibly be respawned, so an unsupervised actor's names are simply
     * dropped as before. This must run strictly before registry_retire_meta:
     * that call is what frees reg_names, so stashing any later would copy
     * nothing. march_respawn_child (which may run synchronously right after
     * this function returns, or up to ~3.2s later on the delayed-restart
     * green thread — see march_supervisor_notify's backoff) is the sole
     * consumer.
     *
     * NOTE this gate only covers an actor dying with its sup_pe still set —
     * a directly-crashed/killed actor, including the originally-crashed
     * child of a one_for_all/rest_for_one batch. A live SIBLING being killed
     * as part of that same batch restart has its sup_pe cleared (to suppress
     * a recursive notify) *before* do_actor_death runs on it, so the
     * strategies stash for it themselves (stash_child_for_restart's
     * comment). */
    if (sup.m) stash_child_for_restart(meta, sup.m, meta->sup_child_index);
    if (meta) registry_retire_meta(meta, actor);

    /* Deliver one owned control value per node after the list is detached. */
    while (monitors) {
        march_monitor_node *next_mn = monitors->next;
        deliver_monitor_down(monitors->watcher, monitors->mon_ref, actor,
                             reason, pe ? pe->terminal_message : message,
                             pe ? pe->terminal_message_len : message_len);
        free(monitors);
        monitors = next_mn;
    }

    /* Fire MONITOR_FIRE to any remote (cross-node) watchers of this pid. */
    if (meta) {
        int dist_reason = reason == MARCH_DEATH_KILLED
            ? MARCH_DIST_REASON_KILLED
            : reason == MARCH_DEATH_CRASH
                ? MARCH_DIST_REASON_CRASH : MARCH_DIST_REASON_NORMAL;
        march_dist_monitor_fire_pid(pe_pid_or_0(pe), dist_reason,
                                    reason == MARCH_DEATH_CRASH
                                        ? pe->terminal_message : NULL);
    }

    /* Wake the actor's green thread so it can notice death and exit. */
    if (meta) {
        march_reclaim_enter();   /* gt: resolved and used inside */
        march_proc *gt = meta_gt(meta);
        /* request_stop, not a bare wake: since the untimed recv re-parks on a
         * wake it cannot attribute to a message (see march_proc.stop_requested),
         * a plain march_sched_wake would leave a killed actor parked forever
         * instead of letting actor_green_thread observe NO_MSG and exit. */
        if (gt) march_sched_request_stop(gt);
        march_reclaim_exit();
    }

    if (sup.m) {
        march_supervisor_notify(sup, meta);
        meta_unpin(sup);
    }
    /* The reference the claim handed us.  If the actor's green thread has
     * already exited (or never started), this is the last one and the meta
     * is retired. */
    meta_put(meta);
}

void march_kill(void *actor) {
    do_actor_death(actor, MARCH_DEATH_KILLED, NULL, 0);
}

/* ── Graceful shutdown: stop, drain, then die ──────────────────────────
 * specs/todos/2026-08-12-graceful-shutdown-and-drain.md.
 *
 * `stop` is the deploy story `kill` cannot tell: kill drops whatever was
 * queued, so rolling a node loses exactly the requests that were waiting.
 * stop instead (1) marks the actor draining, after which march_send refuses
 * new work, (2) lets its own green thread run the receive loop until the
 * mailbox empties or the deadline passes, and (3) ends in an ordinary
 * MARCH_DEATH_NORMAL, which no restart type restarts.
 *
 * The actor drains on ITS OWN thread. Nothing here runs a handler, which is
 * what keeps this safe to call from any thread, including from inside another
 * actor's handler. */

/* Wait for [child] to finish draining, up to [deadline_ms] (absolute; < 0
 * means wait indefinitely). Past the deadline the child is killed outright —
 * OTP's semantics, and the reason `shutdown` is a budget rather than a
 * promise. Returns 1 if the child died on its own, 0 if it had to be killed. */
static int stop_await_death(void *child, int64_t deadline_ms) {
    while (march_is_alive(child)) {
        if (deadline_ms >= 0 && march_now_ms() >= deadline_ms) {
            do_actor_death(child, MARCH_DEATH_KILLED, NULL, 0);
            return 0;
        }
        /* Yield first so a child sharing this scheduler thread can actually
         * run; the sleep bounds the burn when the yield is a no-op (this can
         * be called from a non-green thread) or when the child is parked on
         * another scheduler thread. */
        march_sched_yield();
        struct timespec ts = { 0, 200 * 1000 };   /* 200us */
        nanosleep(&ts, NULL);
    }
    return 1;
}

static int64_t march_actor_stop_pinned(void *actor, march_actor_meta *meta,
                                       int64_t timeout_ms);

/* Stop [actor] gracefully. timeout_ms: < 0 wait forever, 0 stop as soon as the
 * current handler returns (queued messages are discarded), > 0 drain for at
 * most that long. Returns 1 if the actor was live and is now stopping.
 *
 * If [actor] supervises children, they are stopped FIRST and in REVERSE
 * declaration order — the mirror of the order they were started in, and the
 * same order rest_for_one already relies on — each with its own `shutdown`
 * budget from the child spec. A supervisor whose children are still finishing
 * work must outlive them, or their in-flight replies go to a dead parent. */
int64_t march_actor_stop(void *actor, int64_t timeout_ms) {
    if (!IS_HEAP_PTR(actor) || !actor_alive_load(actor)) return 0;
    /* Pinned, not just resolved: the child teardown and the wait below
     * switch threads.  [actor] itself is the caller's. */
    march_reclaim_enter();
    march_actor_meta *meta = find_meta(actor);
    int pinned = meta && meta_tryget(meta);
    march_reclaim_exit();
    if (!pinned) return 0;
    int64_t result = march_actor_stop_pinned(actor, meta, timeout_ms);
    meta_put(meta);
    return result;
}

static int64_t march_actor_stop_pinned(void *actor, march_actor_meta *meta,
                                       int64_t timeout_ms) {

    /* Park the deadline in its not-yet-armed state BEFORE publishing
     * `draining`, so the actor's own loop can never observe a stale 0 (which
     * reads as "your deadline passed") in the window between the claim below
     * and the real deadline being computed after the child teardown. */
    atomic_store_explicit(&meta->drain_deadline_ms, MARCH_DRAIN_NOT_ARMED,
                          memory_order_relaxed);

    /* Claim the transition. A second stop on an actor already draining is a
     * no-op rather than a deadline extension: two callers racing must not be
     * able to push the deadline out indefinitely. */
    int expected = 0;
    if (!atomic_compare_exchange_strong_explicit(&meta->draining, &expected, 1,
                                                 memory_order_acq_rel,
                                                 memory_order_acquire))
        return 0;

    /* Tear the subtree down first, deepest-declared child first. Each child's
     * own stop recurses, so a nested supervisor's grandchildren drain before
     * it does. sup_children is in declaration order (Task 3's field injection
     * walks sc_fields in order), so a reverse index walk IS reverse start
     * order. */
    if (meta->sup_num_children > 0) {
        for (int i = meta->sup_num_children - 1; i >= 0; i--) {
            int64_t stored_pid_index =
                ((int64_t *)actor)[4 + meta->sup_children[i].word_idx];
            /* A live child, pinned (its meta and a counted reference to its
             * record) across the stop and the wait. */
            meta_pin child = meta_pin_pe(pid_entry(stored_pid_index));
            if (!child.m) continue;
            int64_t budget = meta->sup_children[i].shutdown_ms;
            if (getenv("MARCH_SUP_TRACE"))
                fprintf(stderr, "march: stopping supervised child %d"
                        " (shutdown_ms=%lld)\n", i, (long long)budget);
            /* Detach before stopping: this is an orderly teardown, not a
             * crash, so the child's death must not run a restart strategy
             * against a supervisor that is itself on the way out. Same
             * technique the batch strategies use for their sweep kills. */
            pthread_mutex_lock(&g_tbl_mu);
            child.m->sup_pe = NULL;
            pthread_mutex_unlock(&g_tbl_mu);
            if (budget == 0) {
                do_actor_death(child.actor, MARCH_DEATH_KILLED, NULL, 0);
            } else {
                march_actor_stop(child.actor, budget);
                stop_await_death(child.actor,
                                 budget < 0 ? -1 : march_now_ms() + budget);
            }
            meta_unpin(child);
        }
    }

    int64_t deadline = timeout_ms < 0 ? -1 : march_now_ms() + timeout_ms;
    atomic_store_explicit(&meta->drain_deadline_ms, deadline,
                          memory_order_relaxed);
    /* Published AFTER the deadline, and re-stored with release ordering so a
     * green thread that acquire-loads `draining` sees the deadline too. The
     * CAS above already set it; this store is the release fence. */
    atomic_store_explicit(&meta->draining, 1, memory_order_release);

    /* Wake it. request_stop, not a bare wake: an actor parked on an empty
     * mailbox must be able to LEAVE the untimed recv (which otherwise re-parks
     * on a wake it cannot attribute to a message), and an empty mailbox is
     * precisely the case where draining is already finished. */
    /* gt is resolved and used inside the critical section, including the
     * identity test against the current proc: outside it, a freed proc's
     * address could have been reused by the caller's own. */
    march_reclaim_enter();
    march_proc *gt = meta_gt(meta);
    if (gt) march_sched_request_stop(gt);
    int stopping_self = (gt == march_sched_current());
    march_reclaim_exit();

    /* Then WAIT for it, up to the same deadline. `stop` is a synchronous
     * operation on purpose: a deploy sequence's whole point is to know when
     * the in-flight work is finished, and a caller that has to poll is_alive
     * afterwards has been handed the hard half of the problem back. It is
     * also what makes stop behave identically on both backends — the
     * interpreter's eager scheduler drains inline, so an asynchronous
     * compiled stop would give the same program two different observable
     * orderings.
     *
     * Except when the caller IS the actor being stopped: an actor stopping
     * itself cannot wait for its own green thread to finish the queue it is
     * currently standing in. That call marks it draining and returns, and the
     * receive loop does the rest as soon as the handler returns. */
    if (!stopping_self)
        stop_await_death(actor, deadline);
    return 1;
}

/* Is [actor] draining (stopped but not yet dead)? Lets March tell "shutting
 * down" apart from "dead", which `is_alive` alone cannot express. */
int64_t march_actor_is_draining(void *actor) {
    if (!IS_HEAP_PTR(actor)) return 0;
    march_reclaim_enter();   /* meta: resolved and used inside */
    march_actor_meta *meta = find_meta(actor);
    int64_t d = meta && atomic_load_explicit(&meta->draining, memory_order_acquire);
    march_reclaim_exit();
    return d;
}

int64_t march_is_alive(void *actor) {
    return actor_alive_load(actor);
}

/* dist_monitor_register(target_pid, watcher_node, watcher_pid, fd): the March
 * surface of march_dist_monitor_register. The node id arrives as a March
 * string (length-prefixed, not NUL-terminated); the registry wants a C string
 * and strdup()s it, so a bounded copy is made here. */
void march_dist_monitor_register_pid(int64_t target_pid, void *node_str,
                                     int64_t watcher_pid, int64_t fd) {
    if (!node_str) return;
    march_string *s = (march_string *)node_str;
    size_t n = (size_t)s->len;
    char *node = (char *)malloc(n + 1);
    if (!node) return;
    memcpy(node, s->data, n);
    node[n] = 0;
    march_dist_monitor_register(target_pid, node, watcher_pid, (int)fd);
    free(node);
}

/* Dispose an undelivered/overflow-dropped/orphaned actor message. Registered
 * with the scheduler (march_sched_set_msg_dtor) below, at scheduler
 * lazy-init time, so it is called for: MARCH_MBOX_DROP_NEW's rejected
 * message, MARCH_MBOX_DROP_OLD's evicted message, and every message still
 * queued in a proc's mailbox when the scheduler reaps it dead.
 *
 * Two message shapes exist, matching actor_green_thread's receive loop
 * (which performs the identical discrimination — see its Phase 5 comment,
 * just above where it checks `((int64_t *)msg)[1] == MARCH_MIGRATE_TAG`):
 *   - the malloc'd migrate control message (march_migrate_msg_t): a
 *     standard 16-byte march object header shape (rc at word 0, tag at
 *     word 1) but allocated with malloc(), not march-heap-allocated, so it
 *     must be freed with free(), never march_decrc. MARCH_MIGRATE_TAG
 *     (0x4D494752, "MIGR") is chosen far outside the range of real ADT
 *     constructor tags (typically < 1000 — see its definition in
 *     march_runtime.h), so an ordinary march-heap value's tag word can
 *     never collide with it in practice, the same assumption the receive
 *     loop already relies on.
 *   - everything else: an ordinary march-heap value (or a tagged
 *     immediate, which IS_HEAP_PTR rejects, making march_decrc's own
 *     IS_HEAP_PTR guard a safe no-op for it) — disposed via march_decrc.
 *
 * Deliberately narrower than the receive loop's full gate: the receive loop
 * additionally requires `meta->dispatch_name_id` (only hot-reload actors
 * ever receive migrate messages — march_actor_broadcast_migrate only
 * targets them), but this dtor is actor-agnostic (the scheduler calls it
 * with only the message pointer, no actor context) and migrate messages are
 * never sent to non-hot-reload actors in the first place, so omitting that
 * gate here does not admit any message the receive loop's gate would have
 * rejected. */
static void march_actor_msg_dispose(void *msg) {
    if (IS_HEAP_PTR(msg) && ((int64_t *)msg)[1] == MARCH_MIGRATE_TAG) {
        migrate_msg_free(msg);
        return;
    }
    if (IS_HEAP_PTR(msg) && ((march_hdr *)msg)->tag == MARCH_DOWN_TAG) {
        dispose_monitor_down(msg);
        return;
    }
    march_decrc(msg);
}

static void hcr_spawn_marker(march_actor_meta *meta, march_proc *gt);

/* Start [meta]'s green thread.  Caller is inside a critical section (or
 * holds a reference to [meta]).  The thread's reference is taken first, and
 * fails if the actor already died and its meta was retired (a supervised
 * child killed by pid before its activation): then there is nothing to run.
 * The proc is published with a compare-exchange from NULL, so it can never
 * overwrite the MARCH_GT_EXITED of a thread that ran and finished before
 * this store (see green_thread's comment). */
static void activate_actor_green_thread(march_actor_meta *meta) {
    if (atomic_load_explicit(&meta->green_thread, memory_order_acquire)) return;
    if (!meta_tryget(meta)) return;
    march_proc *green_thread = march_sched_spawn_daemon(actor_green_thread, meta);
    if (!green_thread) {
        meta_put(meta);
        static _Atomic int warned = 0;
        if (!atomic_exchange(&warned, 1))
            fprintf(stderr,
                    "march: FAILED to start actor green thread "
                    "(stack allocation) — this actor will drop all "
                    "messages; see Scheduler.stat(3)\n");
        return;
    }
    march_proc *expected = NULL;
    if (atomic_compare_exchange_strong_explicit(&meta->green_thread, &expected,
                                                green_thread, memory_order_acq_rel,
                                                memory_order_acquire))
        hcr_spawn_marker(meta, green_thread);
}

/* Register an actor with the scheduler and return it unchanged.
 * Called from generated ActorName_spawn() wrappers:
 *   let $raw = ActorName_spawn()
 *   march_spawn($raw)            -- returns $raw */
static void *march_spawn_common(void *actor, int defer_activation) {
    march_reclaim_enter();   /* meta: resolved and used inside */
    march_actor_meta *meta = find_or_create_meta(actor);
    if (!meta) {
        /* Spawning a record that is already dead: nothing to run. */
        march_reclaim_exit();
        return actor;
    }
    /* One locked section assigns the pid index and publishes the tombstone
     * by it, so nothing can observe a half-made identity.  A meta whose
     * tombstone already has a pid index belongs to an earlier spawn of this
     * very record (a record is spawned once by the lowering; this is
     * defence, not a path a compiled program takes): the new incarnation
     * gets a fresh meta, and the old one stays linked, as before the metas
     * PR.  dispatch_name_id and call_tags are carried over because
     * compiled code sets them on the record before spawning it. */
    pthread_mutex_lock(&g_tbl_mu);
    if (pe_pid(meta->pe) >= 0) {
        march_actor_meta *m = meta_new_locked(actor);
        m->dispatch_name_id = meta->dispatch_name_id;
        m->call_tags        = meta->call_tags;
        meta = m;
    }
    atomic_store_explicit(&meta->pe->pid_index,
                          atomic_fetch_add_explicit(&g_next_pid_index, 1,
                                                    memory_order_relaxed),
                          memory_order_relaxed);
    pid_entry_publish_locked(meta->pe);
    pthread_mutex_unlock(&g_tbl_mu);
    /* Initialize scheduler lazily. */
    int expected = 0;
    if (atomic_compare_exchange_strong_explicit(
            &g_sched_initialized, &expected, 1,
            memory_order_acq_rel, memory_order_acquire)) {
        march_sched_init();
        /* Reachable when something spawns an actor before march_spawn_main
         * has run (e.g. REPL/JIT, hot-reload, or any other embedding entry
         * point that does not go through the emitted @main -> march_spawn_
         * main path) -- see march_register_sched_callbacks' definition and
         * march_spawn_main's own call to it for why BOTH sites need this. */
        march_register_sched_callbacks();
    }
    /* A normal actor is runnable immediately. A supervise-block child uses
     * the deferred entry point and is activated by register_child only after
     * its supervisor pointer and restart slot are fully published. */
    /* The LIVE actor owns one reference to its own record, released by
     * actor_green_thread at its very last access (both exit paths). Without
     * it the record was kept alive only by whatever pids the program still
     * held: `let a = spawn(W)` with `a` never used again dropped the ONLY
     * reference right after spawn, freeing a running actor whose thread
     * then read and wrote its `alive` word in freed memory (ASAN, 2026-09-14:
     * heap-use-after-free in actor_green_thread / do_actor_death; glibc
     * saw it as `tcache_thread_shutdown(): unaligned tcache chunk` on the
     * ubuntu leg, test/native/actor_enumeration). A pid is a handle to a
     * running actor; the actor's lifetime is its own. */
    march_incrc(actor);
    if (!defer_activation) activate_actor_green_thread(meta);
    march_reclaim_exit();
    /* Start the scheduler in a background thread so actor green threads run
     * even when the main thread is blocked inside the HTTP event loop.
     * For non-HTTP programs this is harmless: march_run_scheduler() joins
     * the background thread before returning. */
    march_ensure_sched_started();
    return actor;
}

/* Capability-passing: attach the spawn-site capability to an actor, and read
 * it back from inside the actor's dispatch.  Both take the ACTOR pointer,
 * which is what march_actor_meta is keyed by and what the spawn lowering has
 * in hand (`let $raw_actor = Name_spawn() in spawn($raw_actor)`).
 *
 * Set is called AFTER march_spawn, because march_spawn is what creates the
 * meta.  Reading an actor with no meta, or one spawned outside a --test build,
 * yields NULL — the plain sentinel — so the ambient path runs. */
void march_set_actor_caps(void *actor, void *caps) {
    march_reclaim_enter();   /* m: resolved and used inside */
    march_actor_meta *m = find_meta(actor);
    if (m) atomic_store_explicit(&m->spawn_cap, caps, memory_order_release);
    march_reclaim_exit();
}

void *march_actor_caps(void *actor) {
    march_reclaim_enter();   /* m: resolved and used inside */
    march_actor_meta *m = find_meta(actor);
    void *caps = m ? atomic_load_explicit(&m->spawn_cap, memory_order_acquire)
                   : NULL;
    march_reclaim_exit();
    return caps;
}

void *march_spawn(void *actor) {
    return march_spawn_common(actor, 0);
}

void *march_spawn_supervised(void *actor) {
    return march_spawn_common(actor, 1);
}

void march_actor_set_dispatch_id(void *actor, uint32_t name_id) {
    /* Called before march_spawn, so find_or_create_meta to ensure the entry
     * exists; march_spawn will find the same entry and attach the green thread. */
    march_reclaim_enter();   /* meta: resolved and used inside */
    march_actor_meta *meta = find_or_create_meta(actor);
    if (meta) meta->dispatch_name_id = name_id;
    march_reclaim_exit();
}

/* Interned handler-tag tables (see march_actor_meta.call_tags).  One per
 * distinct table: a program has one per actor type, and each hot patch that
 * changes an actor's handlers adds one, so the list stays short and is never
 * freed.  Immutable once published; readers need no lock. */
struct march_call_tags {
    struct march_call_tags *next;
    int64_t                 n;
    int32_t                 tags[];
};
static struct march_call_tags *g_call_tags = NULL;
static pthread_mutex_t g_call_tags_mu = PTHREAD_MUTEX_INITIALIZER;

static const struct march_call_tags *call_tags_intern(const int32_t *tags,
                                                      int64_t n) {
    if (!tags || n <= 0) return NULL;
    pthread_mutex_lock(&g_call_tags_mu);
    struct march_call_tags *t = g_call_tags;
    for (; t; t = t->next)
        if (t->n == n && memcmp(t->tags, tags, (size_t)n * sizeof(int32_t)) == 0)
            break;
    if (!t) {
        t = malloc(sizeof *t + (size_t)n * sizeof(int32_t));
        if (t) {
            t->n = n;
            memcpy(t->tags, tags, (size_t)n * sizeof(int32_t));
            t->next = g_call_tags;
            g_call_tags = t;
        }
    }
    pthread_mutex_unlock(&g_call_tags_mu);
    return t;
}

void march_actor_set_call_tags(void *actor, const int32_t *tags, int64_t n) {
    /* Emitted by codegen right after the actor record's alloc (same timing
     * as march_actor_set_dispatch_id): before march_spawn, so
     * find_or_create_meta creates the entry the spawn will reuse. */
    const struct march_call_tags *t = call_tags_intern(tags, n);
    march_reclaim_enter();   /* meta: resolved and used inside */
    march_actor_meta *meta = find_or_create_meta(actor);
    if (meta) meta->call_tags = t;
    march_reclaim_exit();
}

/* Live (allocated, not yet disposed) migrate messages. See
 * march_actor_inject_migrate_msg below. */
static _Atomic int64_t g_migrate_msgs_live = 0;
static void migrate_msg_free(void *mm) {
    atomic_fetch_sub_explicit(&g_migrate_msgs_live, 1, memory_order_relaxed);
    /* A marker holds a reference to its target's meta (hcr_inject_marker),
     * because it is read when the marker is processed or disposed, which can
     * be after the actor has died. */
    meta_put((march_actor_meta *)((march_migrate_msg_t *)mm)->meta);
    free(mm);
}

typedef struct {
    march_actor_meta *meta;
} hcr_target;

/* Every live actor whose dispatch_name_id matches ([dispatch_name_id] ==
 * UINT32_MAX: every live actor), each incrc'd so it stays alive until the
 * caller's matching decrc, and its meta pinned (the caller's meta_put)
 * because the caller keeps it across sends. Heap-grown, so there is no cap:
 * a fixed snapshot array (2048 entries, until 2026-09-21) silently skipped
 * every actor past it. Exits on OOM like find_or_create_meta: a partial
 * snapshot would be
 * that same silent skip. */
static hcr_target *hcr_snapshot(uint32_t dispatch_name_id, size_t *out_n) {
    hcr_target *t = NULL;
    size_t n = 0, cap = 0;
    pthread_mutex_lock(&g_tbl_mu);
    for (int b = 0; b < MARCH_SCHED_BUCKETS; b++) {
        for (march_actor_meta *m = atomic_load_explicit(&g_actor_tbl[b],
                                                         memory_order_relaxed);
             m; m = atomic_load_explicit(&m->tbl_next, memory_order_relaxed)) {
            if ((dispatch_name_id != UINT32_MAX
                     && m->dispatch_name_id != dispatch_name_id)
                    || !m->actor || !meta_gt(m))
                continue;
            if (n == cap) {
                cap = cap ? cap * 2 : 64;
                hcr_target *g = (hcr_target *)realloc(t, cap * sizeof(*t));
                if (!g) {
                    fputs("march: out of memory (hot-reload migrate)\n", stderr);
                    exit(1);
                }
                t = g;
            }
            /* Linked under g_tbl_mu: the table's reference is held, so the
             * pin cannot fail, and the live actor's own reference to its
             * record is still held (march_actor_meta's LIFETIME). */
            meta_tryget(m);
            march_incrc(m->actor);
            t[n].meta = m;
            n++;
        }
    }
    pthread_mutex_unlock(&g_tbl_mu);
    *out_n = n;
    return t;
}

/* Legacy (see march_runtime.h): malloc a MARCH_MIGRATE_TAG message and send
 * it as an ordinary user message.  march_sched_send's contract: only
 * MARCH_SEND_DEAD leaves it with us, so we free it -- with free(), never
 * march_decrc: it is malloc'd, not march-heap. */
static int hcr_inject_marker(march_proc *green_thread,
                             void *(*migrate_fn)(void *)) {
    march_migrate_msg_t *mm = (march_migrate_msg_t *)malloc(sizeof(*mm));
    if (!mm) return -1;
    mm->_rc        = 1;
    mm->_tag       = MARCH_MIGRATE_TAG;
    mm->migrate_fn = migrate_fn;
    mm->meta       = NULL;
    mm->pin        = 0;
    atomic_fetch_add_explicit(&g_migrate_msgs_live, 1, memory_order_relaxed);
    int st = green_thread ? march_sched_send(green_thread, mm) : MARCH_SEND_DEAD;
    if (st == MARCH_SEND_DEAD) migrate_msg_free(mm);
    return st;
}

static int64_t hcr_env_ms(const char *name, int64_t dflt) {
    const char *e = getenv(name);
    if (e && *e) {
        char *end;
        long long v = strtoll(e, &end, 10);
        if (*end == '\0' && v >= 0) return (int64_t)v;
    }
    return dflt;
}

/* Put an epoch marker for [epoch] in [gt]'s user mailbox, if its proc is
 * older than [epoch].  The marker holds one pin on [epoch] until it is
 * consumed (moved to the actor) or disposed (hcr_marker_dtor).  Called inside
 * a reclaim critical section (gt resolved there). */
static void hcr_send_epoch_marker(march_actor_meta *m, march_proc *gt,
                                  uint32_t epoch) {
    if (!gt) return;
    uint32_t ce = atomic_load_explicit(&gt->code_epoch, memory_order_relaxed);
    if (!ce || ce >= epoch) return;
    if (march_epoch_pin(epoch) != 0) {
        /* [epoch] has no holder, so it is not current any more: a newer
         * deploy's marker supersedes this one. */
        return;
    }
    int st = march_sched_send_marker(gt, NULL, epoch);
    if (st == MARCH_SEND_OK) {
        atomic_fetch_add_explicit(&g_hcr_markers_live, 1, memory_order_relaxed);
    } else {
        march_epoch_unpin(epoch);
        (void)m;
    }
}

/* II.4.6 step 4: a marker for every live actor older than [epoch]. */
static void hcr_mark_all(uint32_t epoch) {
    size_t n = 0;
    hcr_target *t = hcr_snapshot(UINT32_MAX, &n);
    for (size_t i = 0; i < n; i++) {
        march_actor_meta *m = t[i].meta;
        march_reclaim_enter();   /* gt: resolved and used inside */
        march_proc *gt = meta_gt(m);
        hcr_send_epoch_marker(m, gt, epoch);
        march_reclaim_exit();
        march_decrc(m->actor);
        meta_put(m);   /* hcr_snapshot's pin */
    }
    free(t);
}

/* The hard drain deadline (II.4.7): kill every actor whose proc is pinned at
 * or below [upto] -- do_actor_death's KILLED path, so a supervisor restarts it
 * (at the current epoch: see hcr_spawn_marker) -- and tell every other proc
 * pinned there to stop. */
static void hcr_hard_kill(uint32_t upto) {
    size_t n = 0;
    hcr_target *t = hcr_snapshot(UINT32_MAX, &n);
    for (size_t i = 0; i < n; i++) {
        march_actor_meta *m = t[i].meta;
        march_reclaim_enter();
        march_proc *gt = meta_gt(m);
        uint32_t ce = gt ? atomic_load_explicit(&gt->code_epoch,
                                                memory_order_relaxed) : 0;
        march_reclaim_exit();
        if (ce && ce <= upto && march_is_alive(m->actor)) {
            fprintf(stderr, "[hcr] drain: hard deadline for epoch <= %u: "
                    "killing actor on dispatch slot %u (epoch %u)\n",
                    upto, m->dispatch_name_id, ce);
            atomic_fetch_add_explicit(&g_hcr_killed, 1, memory_order_relaxed);
            /* A crash with the reason "draining": every supervisor restart
             * type restarts it (a KILLED transient child would stay dead),
             * and a monitor sees Crash("draining") -- SessionNode ends a
             * hosted session as drained on it. */
            do_actor_death(m->actor, MARCH_DEATH_CRASH, "draining",
                           sizeof("draining") - 1);
        }
        march_decrc(m->actor);
        meta_put(m);   /* hcr_snapshot's pin */
    }
    free(t);
    int64_t stopped = march_sched_stop_epoch(upto);
    atomic_fetch_add_explicit(&g_hcr_stopped, stopped, memory_order_relaxed);
}

/* A new actor proc that inherited an epoch older than current (its spawner
 * had not reached its own marker yet, or it was spawned while an activation
 * was marking) gets a marker at once: it runs `init`'s state through the
 * migrations up to current before its first message.  Without this it would
 * never see a marker and would pin its epoch for good. */
static void hcr_spawn_marker(march_actor_meta *meta, march_proc *gt) {
    uint32_t cur = march_epoch_current();
    march_reclaim_enter();
    hcr_send_epoch_marker(meta, gt, cur);
    march_reclaim_exit();
}

void (*march_hcr_test_before_mark)(uint32_t epoch) = NULL;

void *march_hcr_test_send_stamped(void *actor, void *msg, uint32_t epoch) {
    atomic_store(&march_sched_test_stamp, epoch);
    void *r = march_send(actor, msg);
    atomic_store(&march_sched_test_stamp, 0);
    return r;
}

int march_hcr_activate(march_hcr_unit *u, int n, uint32_t requested_epoch,
                       int64_t soft_ms, int64_t hard_ms, march_hcr_wait *wait) {
    if (n <= 0) return MARCH_HCR_ERROR;
    if (soft_ms < 0) soft_ms = hcr_env_ms("MARCH_HCR_DRAIN_MS", MARCH_HCR_DRAIN_MS_DEFAULT);
    if (hard_ms < 0) hard_ms = hcr_env_ms("MARCH_HCR_HARD_DRAIN_MS", 0);

    /* 0. Every slot must have a ring version to stage into, and the pin
     * table room for the new epoch; otherwise nothing changes and the
     * caller waits (D32). */
    int blocked = 0;
    for (int i = 0; i < n && !blocked; i++)
        blocked = !march_dispatch_can_stage(u[i].slot);
    uint32_t epoch = march_epoch_next(requested_epoch);
    int table_full = !blocked && march_epoch_reserve(epoch) != 0;
    if (blocked || table_full) {
        if (wait) {
            uint32_t eps[MARCH_EPOCH_PIN_SLOTS]; int64_t cnt[MARCH_EPOCH_PIN_SLOTS];
            int k = march_epoch_pin_table(eps, cnt, MARCH_EPOCH_PIN_SLOTS);
            uint32_t cur = march_epoch_current();
            wait->epoch = 0; wait->pins = 0; wait->table_full = table_full;
            for (int j = 0; j < k; j++)
                if (eps[j] != cur && (!wait->epoch || eps[j] < wait->epoch)) {
                    wait->epoch = eps[j];
                    wait->pins = cnt[j] - 0;
                }
            wait->deadline_ms = wait->epoch ? hcr_hard_deadline_in(wait->epoch) : -1;
        }
        return MARCH_HCR_WAIT;
    }

    /* 1. Stage every version (live = 0: no reader can select it). */
    for (int i = 0; i < n; i++) {
        u[i].ring_idx = march_dispatch_stage(u[i].slot, u[i].fn, u[i].impl_hash,
                                             u[i].sig_hash, u[i].kind, epoch);
        if (u[i].ring_idx < 0) {
            for (int j = 0; j < i; j++) march_dispatch_unstage(u[j].slot, (uint32_t)u[j].ring_idx);
            march_epoch_unpin(epoch);   /* the reservation */
            return MARCH_HCR_ERROR;
        }
        if (u[i].handle)
            march_dispatch_set_handle(u[i].slot, (uint32_t)u[i].ring_idx, u[i].handle);
        /* The version's .so holds a migration an older actor still has to
         * run: keep it while anything older is pinned. */
        if ((u[i].state_changed && u[i].migrate_fn)
                || (u[i].msgs_changed && u[i].migrate_msg_fn))
            march_dispatch_set_keep_for_older(u[i].slot, (uint32_t)u[i].ring_idx);
    }

    /* 2. The log record and the message-schema epochs, before anything can
     * run at the new epoch. */
    hcr_log_append(epoch, u, n);
    for (int i = 0; i < n; i++)
        if (u[i].msgs_changed)
            march_dispatch_set_msg_schema_epoch(u[i].slot, epoch);

    /* 3. Commit (live, current).  Nothing pinned below [epoch] can select
     * these versions: every pinned unit resolves at or below its own epoch.
     * Only unpinned units (main, proc-less threads) follow current. */
    for (int i = 0; i < n; i++)
        march_dispatch_commit(u[i].slot, (uint32_t)u[i].ring_idx);

    /* 4. Advance: new tasks and sessions now pin [epoch], and the reserved
     * entry becomes the current role's pin. */
    march_epoch_advance(epoch);

    /* 5. A marker in every actor's mailbox, behind what it already has. */
    if (march_hcr_test_before_mark) march_hcr_test_before_mark(epoch);
    hcr_mark_all(epoch);

    /* 6. Drain the older epochs. */
    if (soft_ms > 0 || hard_ms > 0)
        march_hcr_drain(epoch - 1, soft_ms, hard_ms);
    return (int)epoch;
}

int march_actor_publish_migrating(uint32_t dispatch_name_id, void *fn_ptr,
                                  const char *impl_hash, const char *sig_hash,
                                  uint8_t kind, uint32_t epoch,
                                  void *(*migrate_fn)(void *), int64_t drain_ms) {
    march_hcr_unit unit = {
        .slot = dispatch_name_id, .fn = fn_ptr, .impl_hash = impl_hash,
        .sig_hash = sig_hash, .kind = kind, .migrate_fn = migrate_fn,
        .migrate_msg_fn = NULL, .state_changed = 1, .msgs_changed = 0,
        .handle = NULL, .ring_idx = -1 };
    int r = march_hcr_activate(&unit, 1, epoch, drain_ms, 0, NULL);
    return r > 0 ? unit.ring_idx : -1;
}

void march_actor_broadcast_migrate(uint32_t dispatch_name_id,
                                   void *(*migrate_fn)(void *)) {
    if (!dispatch_name_id) return;
    size_t n = 0;
    hcr_target *t = hcr_snapshot(dispatch_name_id, &n);
    for (size_t i = 0; i < n; i++) {
        march_actor_meta *m = t[i].meta;
        march_reclaim_enter();
        march_proc *gt = meta_gt(m);
        hcr_inject_marker(gt, migrate_fn);
        march_reclaim_exit();
        march_decrc(m->actor);
        meta_put(m);   /* hcr_snapshot's pin */
    }
    free(t);
}

/* The per-target send, exposed so test/test_broadcast_migrate_leak.c can
 * drive the real send + conditional-free against an already-dead proc
 * (specs/todos/2026-08-18-broadcast-migrate-no-end-to-end-guard.md, option
 * 2). Returns march_sched_send's status, or -1 if the malloc failed. Every
 * migrate message ever allocated is counted in g_migrate_msgs_live and
 * uncounted at each of its three disposal sites (the DEAD path here, the
 * receive loop, march_actor_msg_dispose), so a leak on any path is a
 * non-zero march_migrate_msgs_live() after the fact. */
int march_actor_inject_migrate_msg(void *green_thread,
                                   void *(*migrate_fn)(void *)) {
    return hcr_inject_marker((march_proc *)green_thread, migrate_fn);
}

int64_t march_migrate_msgs_live(void) {
    return atomic_load_explicit(&g_migrate_msgs_live, memory_order_acquire);
}

/* Test seam: point an actor's meta at a scheduler proc without spawning a
 * real actor green thread, so a C test can put a PROC_DEAD proc where
 * march_actor_broadcast_migrate's Phase 1 filter will snapshot it. Never
 * called by generated code or the runtime itself. */
void march_test_actor_bind_green_thread(void *actor, void *proc) {
    march_reclaim_enter();   /* meta: resolved and used inside */
    march_actor_meta *meta = find_or_create_meta(actor);
    if (meta)
        atomic_store_explicit(&meta->green_thread, (march_proc *)proc,
                              memory_order_release);
    march_reclaim_exit();
}

void *march_test_actor_addr_of_pid(int64_t n) {
    march_pid_entry *pe = pid_entry(n);
    return pe ? pe->addr : NULL;
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
 *   word 2 (offset 16): the task proc's PID, tagged (pid << 1 | 1; 0 = not
 *                        recorded yet) (field 0, for cancel).  A PID, never
 *                        the proc: the program holds a Task as long as it
 *                        likes, far past the proc's death, and a proc is
 *                        freed after its grace period.  Resolved by
 *                        march_task_cancel_by_id inside a critical section.
 *   word 3 (offset 24): result ptr  (field 1, written on completion)
 *   word 4 (offset 32): done flag   (_Atomic int64_t, 0=running, 1=done)
 *   word 5 (offset 40): in-scheduler waiter (_Atomic march_proc*, 0=none) —
 *                        see task_wait_done / march_thunk_trampoline below.
 *                        Bounded by the waiter's wait: it clears the word on
 *                        EVERY exit from task_wait_done, so a waiter that has
 *                        left (and may die) is never named here.
 *
 * Completion signalling: we write result to word 3 then release-store 1
 * into word 4, then wake any registered waiter (word 5).
 * march_task_await acquire-loads word 4 and never touches word 2 (which
 * names the proc by pid precisely because it outlives it).
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
                                     memory_order_acquire) != 0) {
                /* Done: leave word 5 naming nobody.  On the first pass it
                 * holds no registration of ours (compare-exchange, so a
                 * second waiter's own registration is not erased); after a
                 * park it may still name us, and we are about to leave and
                 * may die, so the trampoline must not find us there.  (The
                 * trampoline loads and wakes inside a critical section, so a
                 * wake it already started is covered by the grace period.) */
                int64_t mine = (int64_t)(uintptr_t)self;
                atomic_compare_exchange_strong_explicit(
                    (_Atomic int64_t *)&task[5], &mine, 0,
                    memory_order_acq_rel, memory_order_relaxed);
                return;
            }
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
                int64_t mine = (int64_t)(uintptr_t)self;
                atomic_compare_exchange_strong_explicit(
                    (_Atomic int64_t *)&task[5], &mine, 0,
                    memory_order_acq_rel, memory_order_relaxed);
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
        task[2] = (march_sched_current()->pid << 1) | 1;   /* tagged pid */
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
        /* Load and wake inside one critical section: the waiter may leave
         * task_wait_done (spurious wake, sees done) and die between our load
         * and our wake; the section keeps its proc from being freed until
         * the wake is over. */
        march_reclaim_enter();
        march_proc *waiter = (march_proc *)(uintptr_t)atomic_load_explicit(
            (_Atomic int64_t *)&task[5], memory_order_seq_cst);
        if (waiter) march_sched_wake(waiter);
        march_reclaim_exit();
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
 *   offset 16..23: field 0 = tagged PID of the green thread (for cancel)
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
        /* Every site that can win this CAS must register the callbacks —
         * whichever one wins is the ONLY one that runs, so a site that skips
         * this leaves them unregistered for the life of the process. Reached
         * first whenever a task_spawn precedes both march_spawn_main and any
         * actor spawn, which is exactly what a REPL/JIT session or a
         * --compile-so embedding does (neither emits the @main wrapper that
         * calls march_spawn_main). See march_register_sched_callbacks. */
        march_register_sched_callbacks();
    }
    /* Perceus treats task_spawn as a consuming call: the caller transfers its
     * reference to the task.  No IncRC needed here; the closure's existing
     * rc=1 is the task's reference, released by march_decrc in the trampoline. */
    march_ensure_sched_started();   /* start background scheduler if needed */
    /* Allocate Task at 48 bytes (header + proc ptr + result ptr + done flag
     * + in-scheduler waiter — see task_wait_done). */
    int64_t *task = (int64_t *)march_alloc(48);
    if (task) ((march_hdr *)task)->tag = MARCH_TASK_TAG;  /* see march_run_resource_dtor */
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
 * release-stores 1 into it.  It never looks at the proc (word 2, now a pid):
 * reading a dead proc's status here once caused a use-after-free where
 * calloc reuse zeroed the freed memory, making p->status read as
 * PROC_RUNNABLE (0) forever. */
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
        /* Same reasoning as march_task_spawn_thunk's call just above. */
        march_register_sched_callbacks();
    }
    march_ensure_sched_started();
    int64_t *task = (int64_t *)march_alloc(48);  /* see march_task_spawn_thunk layout */
    if (task) ((march_hdr *)task)->tag = MARCH_TASK_TAG;
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
    int64_t handle = task[2];
    if (!(handle & 1)) return;           /* proc not recorded yet */
    /* Store the cancelled sentinel before the status flip so the await side
     * always sees a valid error result when it observes PROC_DEAD.  (Written
     * whether or not the proc is still around, as it always was.) */
    task[3] = (int64_t)(uintptr_t)mk_err_cstr("task cancelled");
    march_reclaim_enter();
    march_proc *p = march_sched_find(handle >> 1);   /* NULL: already reaped */
    if (p) {
        /* Only from RUNNABLE or RUNNING (compare-exchange, not a blind
         * store).  A blind DEAD landing between a park's PROC_PARKED store
         * and its swapcontext made sched_loop REAP a proc that was still
         * registered as a waiter (Task word 5, a BLOCK waiter list, an
         * fd-wait entry, a timer): with reclaimed procs that is a
         * use-after-free, and before them it already recycled a live
         * stack.  From RUNNABLE the dispatch claim runs the proc to
         * completion as before; from RUNNING its next yield overwrites the
         * DEAD as before. */
        march_proc_status st = atomic_load_explicit(&p->status, memory_order_acquire);
        while ((st == PROC_RUNNABLE || st == PROC_RUNNING)
               && !atomic_compare_exchange_weak_explicit(
                      &p->status, &st, PROC_DEAD,
                      memory_order_acq_rel, memory_order_acquire))
            ;
    }
    march_reclaim_exit();
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
    if (!actor_alive_load(actor)) {
        /* Actor dead: release the reference we were given. */
        march_decrc(msg);
        void *none = march_alloc(16);
        return none;
    }

    /* The hot path's whole reclamation cost: the meta and the proc are
     * resolved, and gt handed to march_sched_send, inside one critical
     * section (a TLS counter on a scheduler thread), and neither is used
     * after it.  A dead target's meta is unlinked (find_meta misses) and its
     * green_thread reads as NULL once it has exited: both are DEAD.
     *
     * find_meta, not find_or_create_meta: a send can only race spawn if the
     * pid escaped before march_spawn returned, which the lowering forbids
     * (march_spawn creates the meta before returning the pid) — so a NULL
     * meta here means the actor was never spawned or has died. This is what
     * keeps march_send off g_tbl_mu entirely. */
    march_reclaim_enter();
    march_actor_meta *meta = find_meta(actor);
    /* A draining actor takes no new work: that is what makes `stop` a
     * shutdown rather than a pause. Rejected here rather than inside
     * march_sched_send so the message is never enqueued and never handed to
     * the mailbox disposer -- MARCH_SEND_DRAINING, distinct at the C level
     * from MARCH_SEND_DEAD and MARCH_SEND_DROPPED. March's `send` returns
     * Option(Unit), so it reports this the way it reports a dead target:
     * None, i.e. "not accepted". */
    if (meta && atomic_load_explicit(&meta->draining, memory_order_acquire)) {
        march_reclaim_exit();
        march_decrc(msg);
        void *none = march_alloc(16);
        return none;
    }
    march_proc *gt = meta ? meta_gt(meta) : NULL;
    int send_rc = gt ? march_sched_send(gt, msg) : MARCH_SEND_DEAD;
    march_reclaim_exit();
    if (send_rc == MARCH_SEND_DEAD) {
        /* Actor died in the window between the checks above and the send;
         * march_sched_send did not enqueue or dispose the message (dead
         * targets are rejected before either happens), so we still own the
         * one reference we were given. */
        march_decrc(msg);
        void *none = march_alloc(16);
        return none;
    }
    /* MARCH_SEND_OK or MARCH_SEND_DROPPED: fire-and-forget semantics are
     * preserved either way — on DROPPED the mailbox's overflow policy already
     * handed the message to march_sched_send's registered disposer (Task 14),
     * so we must NOT decrc it again here. Shedding is observable via
     * Scheduler.dropped_messages(), not via this return value. */

    /* Return Some(()). */
    void *some = march_alloc(16 + 8);
    int32_t *hdr = (int32_t *)((char *)some + 8);
    hdr[0] = 1;
    int64_t *fld = (int64_t *)((char *)some + 16);
    fld[0] = 0;
    return some;
}

/* ── send_after / cancel_timer (specs/progress/2026-08-12-language-level-
   timers.md) ──────────────────────────────────────────────────────────── */
/* A TimerRef's single field: cancelled (0/1), at offset 16 (right after the
 * 16-byte march_hdr) — see MARCH_TIMER_TOKEN_TAG's doc comment in
 * march_runtime.h for the full RC design. Accessed directly (not via the
 * MARCH_FIELD macro, defined just below this point) since this function
 * comes first in file order. */
#define MARCH_TIMER_TOKEN_CANCELLED(tok) (((int64_t *)(tok))[2])

/* Registered with the scheduler below (march_sched_set_timer_token_ops) so
 * march_scheduler.c can check/release a SEND-kind timer entry's token
 * without depending on March's GC internals — same rationale, and same
 * indirection shape, as march_sched_set_msg_dtor / march_actor_msg_dispose
 * just above. */
static int64_t march_timer_token_is_cancelled(void *tok) {
    return atomic_load_explicit((_Atomic int64_t *)&MARCH_TIMER_TOKEN_CANCELLED(tok),
                                 memory_order_acquire);
}
static void march_timer_token_release(void *tok) {
    march_decrc(tok);
}

/* Register every scheduler callback the runtime layer supplies (the message
 * dtor for undelivered/orphaned mailbox messages, Task 14; the timer-token
 * ops for send_after/cancel_timer, this feature) in one place, so no
 * lazy-init call site can register only some of them and silently leave the
 * rest permanently unregistered for the life of the process — exactly the
 * bug this helper replaces: before it, march_spawn_common called
 * march_sched_set_msg_dtor directly, but march_spawn_main (which runs
 * first, and hence wins the CAS, in every normal compiled program) called
 * nothing.
 *
 * ALL FOUR sites that CAS g_sched_initialized 0->1 must call this, because
 * exactly one of them wins and the losers' bodies never run:
 *   - march_spawn_main                    (compiled @main; wins normally)
 *   - march_spawn_common                  (actor spawned before @main)
 *   - march_task_spawn_thunk              (task_spawn before either)
 *   - march_task_spawn_with_cancel_thunk  (ditto, with a cancel token)
 * The last two matter for the REPL/JIT and --compile-so embedding paths,
 * which never emit the @main wrapper that calls march_spawn_main, so a
 * leading task_spawn there is genuinely the first site reached. Adding a
 * fifth CAS site without calling this reintroduces the bug. */
static void march_register_sched_callbacks(void) {
    /* Task 14: give the scheduler a real disposer for messages it never
     * delivers (mailbox-overflow drops, and every message still queued
     * in a proc's mailbox when it is reaped dead) instead of leaking
     * them. See march_actor_msg_dispose's own comment for the two
     * message shapes it discriminates between, and the re-entrancy
     * contract on march_sched_set_msg_dtor for why the scheduler always
     * calls this with no scheduler lock held. */
    march_sched_set_msg_dtor(march_actor_msg_dispose);
    march_sched_set_marker_dtor(hcr_marker_dtor);
    /* send_after/cancel_timer (specs/progress/2026-08-12-language-level-
     * timers.md): give the scheduler's timer heap a way to check/release
     * a SEND-kind entry's TimerRef token without depending on March's GC
     * internals — same rationale as the message dtor just above. */
    march_sched_set_timer_token_ops(march_timer_token_is_cancelled,
                                    march_timer_token_release);
}

/* send_after(pid, msg, delay_ms) : TimerRef — see march_runtime.h's doc
 * comment on the declaration for the RC contract.
 *
 * actor is resolved to its current green thread ONCE, here, exactly like
 * march_send above — NOT re-resolved at fire time. If the actor is
 * respawned (e.g. a supervised restart) before the deadline, this timer
 * still targets the ORIGINAL process instance, which by then reads DEAD;
 * march_sched_send_after/timer_service treat that uniformly with "never
 * spawned" (gt == NULL) and "died before firing" — the message is disposed,
 * never silently redirected to the new instance. This matches march_send's
 * own pid-is-a-process-identity semantics and needs no extra bookkeeping.
 *
 * delay_ms <= 0 fires on the next timer_service tick (deadline = now). */
void *march_send_after(void *actor, void *msg, int64_t delay_ms) {
    void *tok = march_alloc(16 + 8);
    ((march_hdr *)tok)->tag = MARCH_TIMER_TOKEN_TAG;
    MARCH_TIMER_TOKEN_CANCELLED(tok) = 0;
    /* Second reference: the timer heap's own hold, released by
     * march_timer_token_release (via the registered ops) when timer_service
     * pops this entry — fired or not. The first reference (rc=1 from
     * march_alloc) is the one we return to the caller below. */
    march_incrc(tok);

    int64_t deadline = march_now_ms() + (delay_ms > 0 ? delay_ms : 0);
    /* The entry keeps gt's pid, not gt (march_sched_send_after), so gt is
     * needed only inside this critical section. */
    march_reclaim_enter();
    march_actor_meta *meta = find_meta(actor);
    march_proc *gt = meta ? meta_gt(meta) : NULL;
    march_sched_send_after(gt, msg, tok, deadline);
    march_reclaim_exit();
    return tok;
}

/* cancel_timer(ref) — see march_runtime.h's doc comment for the RC
 * contract: consumes (and releases) the one reference to tok it receives. */
void march_timer_cancel(void *tok) {
    if (!tok) return;
    atomic_store_explicit((_Atomic int64_t *)&MARCH_TIMER_TOKEN_CANCELLED(tok),
                          1, memory_order_release);
    march_decrc(tok);
}

/* ── Heap layout helpers (used by actor_call and file I/O) ────────────── */
/* Header layout: rc(8) | tag(4) | pad(4) | fields... */
#define MARCH_FIELD(obj, i) (((int64_t *)(obj))[2 + (i)])
#define MARCH_FIELD_PTR(obj, i) ((void *)MARCH_FIELD(obj, i))
#define MARCH_SET_TAG(obj, t) (((march_hdr *)(obj))->tag = (int32_t)(t))

/* ── Actor.call / Actor.reply (synchronous messaging) ────────────────── */

/* Correlation-checked replies (actor-system hardening, task 4): a call that
 * times out leaves its reply-in-flight — the handler may still deliver a
 * late reply after the caller has moved on to a SECOND call. Without a
 * correlation id, that late reply lands in the (still-live, per-call-owning)
 * caller's mailbox and is handed back as the answer to the unrelated second
 * call. Every reply is now wrapped in an envelope carrying the correlation
 * id minted for that specific march_actor_call invocation, and the receive
 * loop discards any envelope whose corr doesn't match the call it belongs to.
 *
 * Tag choice: 0x00CA11ED sits below the F19 global ctor-tag floor
 * (0x01000000 — see the call_tags comment above) so it can never collide
 * with a real user/stdlib constructor tag, and it doesn't collide with the
 * other reserved sentinel tags either: MARCH_STRING_TAG/-1, MARCH_RESOURCE_TAG/-2,
 * and MARCH_FLOAT_TAG/-3 (all negative int32, checked as literal != this one)
 * or MARCH_MIGRATE_TAG (0x4D494752, a different int64-typed protocol tag on
 * migration messages, not on this struct's int32 header tag field). */
#define MARCH_CALL_REPLY_TAG 0x00CA11ED
static _Atomic int64_t g_next_call_corr = 1;

/* Shared unwrap for march_actor_call's receive loops (both the wait-forever
 * and the deadline-bounded path funnel through here). Returns:
 *   1  -> matched envelope; *out_payload holds the (ref-owned) reply value
 *   0  -> stale/mismatched envelope, already discarded — caller should retry
 *  -1  -> msg is not a reply envelope: an ordinary message to the caller.
 *         It is not this call's answer; the caller keeps it (see
 *         call_held below) and puts it back when the call returns. */
static int march_actor_call_unwrap(void *msg, int64_t corr, void **out_payload) {
    if (IS_HEAP_PTR(msg) && ((march_hdr *)msg)->tag == MARCH_CALL_REPLY_TAG) {
        int64_t got_corr = MARCH_FIELD(msg, 0);
        void *payload = (void *)(uintptr_t)MARCH_FIELD(msg, 1);
        march_decrc(msg);
        if (got_corr != corr) {
            march_decrc(payload);   /* stale reply: drop it, keep waiting */
            return 0;
        }
        *out_payload = payload;
        return 1;
    }
    return -1;
}

/* Messages an Actor.call's wait received that are not its reply, in arrival
 * order, with their mailbox sequence numbers.  The caller's mailbox is also
 * where its ordinary messages arrive: an actor calling from inside a handler
 * gets its own traffic there while it waits.  Those messages used to be
 * returned as the call's answer (and never reached their handler); now the
 * wait holds them and call_held_restore puts them back at the front of the
 * mailbox, in order, before the call returns — a selective receive. */
typedef struct {
    void    **msgs;
    uint64_t *seqs;
    int64_t   n, cap;
} call_held;

static void call_held_push(call_held *h, void *msg, uint64_t seq) {
    if (h->n == h->cap) {
        int64_t cap = h->cap ? h->cap * 2 : 4;
        void **msgs = realloc(h->msgs, (size_t)cap * sizeof *msgs);
        uint64_t *seqs = realloc(h->seqs, (size_t)cap * sizeof *seqs);
        if (!msgs || !seqs) {
            fputs("march: OOM (actor_call held messages)\n", stderr);
            abort();
        }
        h->msgs = msgs;
        h->seqs = seqs;
        h->cap = cap;
    }
    h->msgs[h->n] = msg;
    h->seqs[h->n] = seq;
    h->n++;
}

/* Put the held messages back and return ret (every exit of the wait). */
static void *call_held_restore(call_held *h, void *ret) {
    march_sched_requeue_user_front(h->msgs, h->seqs, h->n);
    free(h->msgs);
    free(h->seqs);
    return ret;
}

/*
 * march_actor_call: synchronous call — builds a wrapped message containing a
 * heap-allocated reply-ref (caller proc + correlation id) as the reply
 * channel (field 0), then sends it to the actor and blocks until the actor
 * calls march_actor_reply.
 *
 * Protocol:
 *   1. Read the tag from inner_msg (the zero-arg constructor like GetCount).
 *   2. Mint a correlation id and build the reply-ref; build a new heap struct
 *      with the same tag + one extra field: the reply-ref.  The actor handler
 *      receives this reply-ref as its first parameter (e.g.,
 *      `on GetCount(reply_to)`) and hands it back verbatim to Actor.reply.
 *   3. Send the augmented message to the actor's green thread.
 *   4. Wait for the reply: timeout_ms <= 0 blocks forever via
 *      march_sched_recv_user_seq(); a positive timeout_ms does a
 *      deadline-bounded park-with-timeout and returns Err("no reply (timeout
 *      or unhandled Call)") past the deadline. Any reply whose correlation
 *      id doesn't match this call's is discarded (see march_actor_call_unwrap
 *      above) instead of being handed back as this call's answer, and any
 *      other message is held and put back at the front of the mailbox when
 *      the call returns (call_held above).
 *   5. Return Ok(reply_value).
 *
 * RC contract: we consume one reference to inner_msg (via march_decrc after
 * reading the tag) and transfer ownership of the new call_msg (and the
 * reply-ref it carries) to the actor. The reply-ref is march-heap-allocated
 * with rc=1; march_actor_reply reads it and march_decrc's it (on the
 * envelope path). If the handler never calls Actor.reply, the reply-ref
 * leaks with the message — same as today's leaked raw result, no new hazard.
 */
void *march_actor_call(void *actor, void *inner_msg, int64_t timeout_ms) {
    if (!actor_alive_load(actor)) {
        march_decrc(inner_msg);
        return mk_err_cstr("actor not alive");
    }

    march_proc *caller = march_sched_current();

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

    int64_t corr = atomic_fetch_add_explicit(&g_next_call_corr, 1,
                                             memory_order_relaxed);
    /* reply-ref: heap obj, field0 = caller PID (tagged), field1 = corr.
     * The PID, not the proc: a handler may keep the ref across turns
     * (march_actor_reply_retain) and the caller may time out and exit, so
     * this holder is unbounded; march_actor_reply resolves it inside a
     * critical section.  Tagged odd so nothing mistakes it for a heap
     * pointer.  Built before the target is resolved, so that the whole
     * resolve-and-send is one critical section: march_alloc never switches. */
    void *reply_ref = NULL, *call_msg = NULL;
    if (caller) {
        reply_ref = march_alloc(16 + 16);
        MARCH_SET_TAG(reply_ref, MARCH_CALL_REPLY_TAG);
        MARCH_FIELD(reply_ref, 0) = (caller->pid << 1) | 1;
        MARCH_FIELD(reply_ref, 1) = corr;
        /* The augmented call message: field 0 = reply-ref (16-byte header +
         * one 8-byte field).  Its tag is set once the target's call base is
         * known, below. */
        call_msg = march_alloc(24);
        MARCH_FIELD(call_msg, 0) = (int64_t)(uintptr_t)reply_ref;
    }

    /* Resolve, send, leave, in one critical section: the meta and gt are
     * valid only inside it, and the waits below park.  find_meta, not
     * find_or_create_meta — same reasoning as march_send: a NULL meta here
     * means the pid was never spawned or has died.  A target that dies
     * between the test and the send is a dead send, as it always was. */
    march_reclaim_enter();
    march_actor_meta *meta = find_meta(actor);
    march_proc *gt = meta ? meta_gt(meta) : NULL;
    if (gt && caller) {
        /* Positional dispatch: the sentinel's per-type tag IS the handler
         * index. The actor's dispatch switch matches GLOBAL msg tags (F19:
         * a stable hash of the qualified constructor name, unique across
         * actors and NOT contiguous), so translate index → global tag via
         * the table stamped at alloc time.  Without this every call message
         * falls to the dispatch default arm and is silently dropped — the
         * caller blocks forever (or times out).
         *
         * Only translate a tag that is a handler index: a caller may also
         * pass the actor's OWN _Msg constructor (e.g.
         * actor_call(pool, Checkout(0))) whose tag is ALREADY global (at or
         * above 0x01000000, far past any index) — translating it would
         * misroute (the erased_option_niche_fbip_codegen regression). */
        const struct march_call_tags *ct = meta->call_tags;
        if (ct && msg_tag >= 0 && (int64_t)msg_tag < ct->n)
            msg_tag = ct->tags[msg_tag];
        MARCH_SET_TAG(call_msg, msg_tag);
        march_sched_send(gt, call_msg);
    }
    march_reclaim_exit();
    if (!gt || !caller) {
        march_decrc(call_msg);   /* march_decrc does not recurse */
        march_decrc(reply_ref);
        return mk_err_cstr(!gt ? "actor not found"
                               : "actor_call: not in scheduler context");
    }

    call_held held = {0};
    uint64_t seq = 0;

    if (timeout_ms <= 0) {
        /* Preserve wait-forever semantics for callers that opt out. Still
         * loop on a mismatched correlation: a wait-forever call can also
         * receive a stale envelope left over from an EARLIER timed-out call
         * on the same green thread. */
        for (;;) {
            void *result = march_sched_recv_user_seq(&seq);
            if (result == MARCH_RECV_NO_MSG)
                return call_held_restore(&held,
                    mk_err_cstr("no reply (timeout or unhandled Call)"));
            void *payload;
            int rc = march_actor_call_unwrap(result, corr, &payload);
            if (rc == 1)
                return call_held_restore(&held, mk_ok(payload));
            if (rc < 0)
                call_held_push(&held, result, seq);
            /* stale envelope (discarded) or held message: keep waiting */
        }
    }

    /* Timed wait: park with a deadline instead of busy yield-polling. The
     * scheduler wakes us early on reply (march_actor_reply's march_sched_send
     * → march_sched_wake) or lets the timer service fire at the deadline, so
     * a pending timed call no longer consumes a dispatch slot every turn.
     *
     * march_sched_recv_until (not march_sched_try_recv2 +
     * march_sched_park_self_until) is deliberate: it holds the mailbox lock
     * across both the emptiness check and the PROC_PARKED store, closing a
     * lost-wakeup window where march_sched_send could observe this proc as
     * still PROC_RUNNING between an unlocked emptiness check and a separate
     * PROC_PARKED store, and skip the wake — deferring delivery of an
     * already-arrived reply until the full timeout elapsed. See
     * march_sched_recv_until's doc comment in march_scheduler.h/.c.
     *
     * The Err payloads match the interpreter's no-reply message exactly so
     * both backends surface the same value.
     *
     * On timeout, a late reply CAN still land in the caller's mailbox (we
     * give up waiting, not the handler up replying) — but it now carries a
     * correlation id that no longer matches any call this green thread is
     * waiting on, so a SUBSEQUENT Actor.call on the same thread discards it
     * via march_actor_call_unwrap above instead of misdelivering it as that
     * later call's answer. (We don't merge this branch with the wait-forever
     * one above into a single march_sched_recv_until(INT64_MAX) path: recv_until
     * registers a timer-heap entry for its deadline, and a deadline of
     * INT64_MAX would never fire and never get removed — one leaked heap
     * slot per wait-forever call, unbounded for a call-heavy long-lived
     * server. Two branches, one shared unwrap helper, is the right split.) */
    int64_t deadline_ms = march_now_ms() + timeout_ms;
    for (;;) {
        void *msg = march_sched_recv_user_until_seq(deadline_ms, &seq);
        if (msg != MARCH_RECV_NO_MSG) {
            void *payload;
            int rc = march_actor_call_unwrap(msg, corr, &payload);
            if (rc == 1)
                return call_held_restore(&held, mk_ok(payload));
            if (rc < 0)
                call_held_push(&held, msg, seq);
            /* stale envelope discarded or message held; the deadline may
             * have passed while we were draining, so re-check before looping. */
            if (march_now_ms() >= deadline_ms)
                return call_held_restore(&held,
                    mk_err_cstr("no reply (timeout or unhandled Call)"));
            continue;
        }
        if (march_now_ms() >= deadline_ms)
            return call_held_restore(&held,
                mk_err_cstr("no reply (timeout or unhandled Call)"));
        /* Woken with an empty mailbox but time remains (spurious, or the
         * no-preempt-daemon degrade-to-yield path) — loop and try again. */
    }
}


/*
 * march_actor_reply: send a reply back to the caller blocked in actor_call.
 *
 * ref_ptr is the reply-ref built by march_actor_call: a heap struct with
 * field0 = caller proc, field1 = correlation id (tag MARCH_CALL_REPLY_TAG).
 * We wrap result in an envelope carrying that corr and send it to the
 * caller's mailbox, waking it from march_sched_recv_user() /
 * march_sched_recv_user_until().
 * The caller's unwrap (march_actor_call_unwrap) compares corr against the
 * one it is waiting on and discards the envelope if they don't match.
 *
 * Legacy path: if ref_ptr isn't one of our envelope-tagged reply-refs (a
 * bare proc pointer), send result directly with no envelope.  Compiled code
 * never takes it (every handler's reply ref is the one march_actor_call
 * built), and a bare value is NOT accepted as a call's answer: a caller
 * waiting in march_actor_call keeps it as an ordinary message.
 *
 * RC contract: march_actor_reply does NOT incrc result; it transfers the
 * caller's reference (the handler's Perceus instrumentation already owns
 * it) into the envelope's field 1. On the envelope path we also consume the
 * reply-ref's own reference via march_decrc(ref_ptr) — march_actor_call
 * handed it off to the actor with rc=1 and this is the only place that
 * reference is ever retired; a handler that never replies simply leaks it
 * along with the unhandled message, same as an unreplied raw result today.
 */
/* march_actor_reply_retain: take a SECOND reference to a reply-ref so a
 * handler may hold it in its state and answer on a LATER turn.  Without
 * this, the ref's only reference is retired with the message envelope when
 * the handler returns, and an Actor.reply from a later turn is a
 * use-after-free (SIGBUS on the scheduler thread; NodeQueue's BlockSender
 * found it).  Balanced by march_actor_reply, which retires one reference
 * per reply -- so a held ref must be replied to exactly once, even after
 * its caller timed out (the mismatched-correlation reply is discarded).
 * A non-ref value (the interpreter-parity raw proc path) is returned as is. */
void *march_actor_reply_retain(void *ref_ptr) {
    if (IS_HEAP_PTR(ref_ptr)
            && ((march_hdr *)ref_ptr)->tag == MARCH_CALL_REPLY_TAG)
        march_incrc(ref_ptr);
    return ref_ptr;
}

void march_actor_reply(void *ref_ptr, void *result) {
    if (!IS_HEAP_PTR(ref_ptr)
            || ((march_hdr *)ref_ptr)->tag != MARCH_CALL_REPLY_TAG) {
        /* Not a reply-ref.  This used to be a "legacy path" that treated the
         * value as a raw march_proc * and sent to it; nothing produces one
         * (march_actor_call builds every reply-ref, and `self` returns the
         * actor, not its proc), and a stored proc pointer is exactly what
         * reclamation forbids.  Nobody can receive this reply: drop it. */
        march_decrc(result);
        return;
    }
    int64_t caller_pid = MARCH_FIELD(ref_ptr, 0) >> 1;
    int64_t corr = MARCH_FIELD(ref_ptr, 1);
    void *env = march_alloc(16 + 16);
    MARCH_SET_TAG(env, MARCH_CALL_REPLY_TAG);
    MARCH_FIELD(env, 0) = corr;
    MARCH_FIELD(env, 1) = (int64_t)(uintptr_t)result;
    march_decrc(ref_ptr);
    /* A caller that has exited (timed out and gone) resolves to NULL: a dead
     * send, exactly as sending to its dead proc was. */
    march_reclaim_enter();
    march_proc *caller = march_sched_find(caller_pid);
    if (caller) march_sched_send(caller, env);
    march_reclaim_exit();
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
/* The other two types this runtime builds cells for itself.  Both are
 * declared with BARE TIR names (the descriptor's `T` lines read `List` and
 * `Result`), and the C builders' tags already match the declaration order the
 * descriptor is keyed by -- Nil=0/Cons=1, Ok=0/Err=1 -- which is what makes
 * the stamp meaningful rather than merely present.
 *
 * Every mk_ok/mk_err/make_cons/make_nil call site in this file builds the
 * type its name says (audited: 14 mk_ok, 3 mk_err, 10 make_cons, 15
 * make_nil), so the id is a property of the helper, not of the caller.  A
 * helper reused for some other shape would print a confidently wrong
 * constructor, which is strictly worse than the "#<tag:N>" being fixed. */
static int32_t list_type_id(void) {
    static int32_t id = 0;
    if (id == 0) id = march_type_id_of_name("List");
    return id;
}
static int32_t result_type_id(void) {
    static int32_t id = 0;
    if (id == 0) id = march_type_id_of_name("Result");
    return id;
}

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
    void *nil = march_alloc(16);
    ((march_hdr *)nil)->pad = list_type_id();
    return nil;
}

/* Helper: allocate a Cons(head, tail) list node (tag=1). */
static void *make_cons(void *head, void *tail) {
    void *cons = march_alloc(16 + 16);  /* header + 2 ptr fields */
    int32_t *tp = (int32_t *)((char *)cons + 8);
    tp[0] = 1;  /* tag = Cons */
    ((march_hdr *)cons)->pad = list_type_id();
    void **fp = (void **)((char *)cons + 16);
    fp[0] = head;
    fp[1] = tail;
    return cons;
}

/* Helper: allocate a 2-element tuple (tag=0, 2 ptr fields). */
/* actor_terminal_reason(pid_index) -> Option((tag, message)): the reason a
 * local actor died, with DistLink's wire tags (0 Normal, 1 Killed, 2 Crash),
 * or None while it is alive or unknown. Looks up the META by pid index and
 * reads only its terminal fields: a MONITOR_REQ for a pid whose record has
 * already been freed must not touch the record (the meta outlives it). */
static void *make_tuple2(void *a, void *b);
static void *make_cons(void *head, void *tail);
static void *make_nil(void);

/* dist_monitor_pending() -> List((target_pid, (watcher_node, (watcher_pid,
 * (reason_tag, reason_msg))))): every fired-but-unacked MONITOR_FIRE, for the
 * March-side resend. Nested pairs because the runtime can build tuples and
 * cons cells but not records. Collected under the registry lock, allocated
 * outside it. */
struct pending_acc { int64_t *tp; char **node; int64_t *wp; int *tag; char **msg; int n, cap; };
static void pending_cb(int64_t target_pid, const char *watcher_node, int64_t watcher_pid,
                       int reason_tag, const char *reason_msg, void *ctx) {
    struct pending_acc *a = (struct pending_acc *)ctx;
    if (a->n == a->cap) {
        int nc = a->cap ? a->cap * 2 : 8;
        a->tp = realloc(a->tp, sizeof(int64_t) * nc); a->node = realloc(a->node, sizeof(char *) * nc);
        a->wp = realloc(a->wp, sizeof(int64_t) * nc); a->tag = realloc(a->tag, sizeof(int) * nc);
        a->msg = realloc(a->msg, sizeof(char *) * nc); a->cap = nc;
    }
    a->tp[a->n] = target_pid; a->node[a->n] = strdup(watcher_node ? watcher_node : "");
    a->wp[a->n] = watcher_pid; a->tag[a->n] = reason_tag;
    a->msg[a->n] = strdup(reason_msg ? reason_msg : ""); a->n++;
}
void *march_dist_monitor_pending(void) {
    struct pending_acc a = {0};
    march_dist_monitor_pending_walk(pending_cb, &a);
    void *list = make_nil();
    for (int i = a.n - 1; i >= 0; i--) {
        void *tagged_tp = (void *)((a.tp[i] << 1) | 1);
        void *tagged_wp = (void *)((a.wp[i] << 1) | 1);
        void *tagged_tag = (void *)(((int64_t)a.tag[i] << 1) | 1);
        void *inner = make_tuple2(tagged_tag, march_string_lit(a.msg[i], (int64_t)strlen(a.msg[i])));
        void *p2 = make_tuple2(tagged_wp, inner);
        void *p1 = make_tuple2(march_string_lit(a.node[i], (int64_t)strlen(a.node[i])), p2);
        list = make_cons(make_tuple2(tagged_tp, p1), list);
        free(a.node[i]); free(a.msg[i]);
    }
    free(a.tp); free(a.node); free(a.wp); free(a.tag); free(a.msg);
    return list;
}

int64_t march_dist_monitor_forget_node_str(void *node_str) {
    if (!node_str) return 0;
    march_string *s = (march_string *)node_str;
    size_t n = (size_t)s->len;
    char *node = (char *)malloc(n + 1);
    if (!node) return 0;
    memcpy(node, s->data, n); node[n] = 0;
    int64_t r = march_dist_monitor_forget_node(node);
    free(node);
    return r;
}

void march_dist_monitor_ack_pid(int64_t target_pid, int64_t watcher_pid) {
    march_dist_monitor_ack(target_pid, watcher_pid);
}

/* Read from the pid's tombstone, which is never freed: a dead pid can be
 * asked for its terminal reason at any later time. */
void *march_actor_terminal_reason(int64_t pid_index) {
    march_pid_entry *pe = pid_entry(pid_index);
    if (!pe || !atomic_load_explicit(&pe->terminal_set, memory_order_acquire))
        return NULL;
    void *tag = (void *)(((int64_t)pe->terminal_reason << 1) | 1);
    const char *m = pe->terminal_message ? pe->terminal_message : "";
    size_t n = pe->terminal_message ? pe->terminal_message_len : 0;
    return make_tuple2(tag, march_string_lit(m, (int64_t)n));
}

static void *make_tuple2(void *a, void *b) {
    void *tup = march_alloc(16 + 16);
    /* tag stays 0 */
    void **fp = (void **)((char *)tup + 16);
    fp[0] = a;
    fp[1] = b;
    return tup;
}

/* ── SIMD first-byte scan for march_memmem ──────────────────────────────
 *
 * march_simd_memchr is a hand-written vector byte-scanner: broadcast the
 * target byte across a 16-byte register, compare it against the buffer in
 * 64-byte chunks (four 16-byte lanes) to get a per-lane equality mask, use a
 * single cheap "did ANY of the 64 bytes match" reduction to skip the whole
 * chunk on a miss, and only when that reduction says yes, find the exact
 * lane and byte position — falling through to a 16-byte loop and then a
 * scalar tail for whatever is left under 64/16 bytes. This is the same
 * "compiled at build time for the target ISA" split as
 * runtime/march_http_parse_simd.c: SSE2 is the x86-64 ABI baseline (always
 * available, no -msse4.2/-mavx flag needed — unlike that file's SSE4.2
 * PCMPESTRI path) and NEON is the AArch64 ABI baseline (always available on
 * both CI platforms, macos-15 arm64 and any aarch64 Linux target; see
 * bin/main.ml's arch_cflags, which passes -msse4.2 only for X86_64/Native
 * and leaves arm64 flag-less with the comment "NEON by default"). Anything
 * else (32-bit ARM without NEON, WASM) falls back to plain libc memchr,
 * which is always correct.
 *
 * Each of the three implementations has IDENTICAL contract to libc memchr:
 * given a starting pointer and byte count, return a pointer to the first
 * occurrence of the target byte in that exact range, or NULL. Because every
 * loop stage's trip count is gated on its own chunk size fitting in what's
 * left (i + 64 <= n, then i + 16 <= n, then plain i < n for the scalar
 * tail), no load ever starts past `n` minus its own width — no
 * out-of-bounds read for any n, including n < 16 (neither vector loop body
 * ever runs then).
 */

#if defined(__SSE2__)
#include <emmintrin.h>
/* Four 16-byte lanes (64 bytes/iteration) so the common "no match in this
 * chunk" case pays one OR + one movemask-and-test across the whole 64 bytes
 * instead of a movemask-and-branch every 16 — libc memchr on both platforms
 * this runtime targets does the equivalent wide-chunk trick, and a plain
 * 16-bytes-at-a-time loop measured meaningfully slower than it in practice. */
static const char *march_simd_memchr(const char *p, char c, size_t n) {
    const __m128i target = _mm_set1_epi8(c);
    size_t i = 0;
    for (; i + 64 <= n; i += 64) {
        __m128i c0 = _mm_loadu_si128((const __m128i *)(p + i));
        __m128i c1 = _mm_loadu_si128((const __m128i *)(p + i + 16));
        __m128i c2 = _mm_loadu_si128((const __m128i *)(p + i + 32));
        __m128i c3 = _mm_loadu_si128((const __m128i *)(p + i + 48));
        __m128i e0 = _mm_cmpeq_epi8(c0, target);
        __m128i e1 = _mm_cmpeq_epi8(c1, target);
        __m128i e2 = _mm_cmpeq_epi8(c2, target);
        __m128i e3 = _mm_cmpeq_epi8(c3, target);
        __m128i any = _mm_or_si128(_mm_or_si128(e0, e1), _mm_or_si128(e2, e3));
        if (_mm_movemask_epi8(any)) {
            int m0 = _mm_movemask_epi8(e0);
            if (m0) return p + i + __builtin_ctz((unsigned)m0);
            int m1 = _mm_movemask_epi8(e1);
            if (m1) return p + i + 16 + __builtin_ctz((unsigned)m1);
            int m2 = _mm_movemask_epi8(e2);
            if (m2) return p + i + 32 + __builtin_ctz((unsigned)m2);
            int m3 = _mm_movemask_epi8(e3);
            return p + i + 48 + __builtin_ctz((unsigned)m3);
        }
    }
    for (; i + 16 <= n; i += 16) {
        __m128i chunk = _mm_loadu_si128((const __m128i *)(p + i));
        __m128i eq = _mm_cmpeq_epi8(chunk, target);
        int mask = _mm_movemask_epi8(eq);
        if (mask) return p + i + __builtin_ctz((unsigned)mask);
    }
    for (; i < n; i++) if (p[i] == c) return p + i;
    return NULL;
}
#elif defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__)
#include <arm_neon.h>
/* Same 64-byte-chunk shape as the SSE2 path above, using vmaxvq_u8 (a single
 * horizontal-max-across-lanes instruction) as the cheap "any lane matched"
 * test in place of movemask: a plain 16-bytes-at-a-time loop that always
 * paid two vgetq_lane_u64 + ctzll extractions per chunk (even on a miss)
 * measured ~45% SLOWER than libc memchr on Apple Silicon; this reduction
 * shape only pays the precise per-lane extraction once a chunk is known to
 * contain a hit. */
static const char *march_simd_memchr(const char *p, char c, size_t n) {
    const uint8x16_t target = vdupq_n_u8((uint8_t)c);
    size_t i = 0;
    for (; i + 64 <= n; i += 64) {
        uint8x16_t c0 = vld1q_u8((const uint8_t *)(p + i));
        uint8x16_t c1 = vld1q_u8((const uint8_t *)(p + i + 16));
        uint8x16_t c2 = vld1q_u8((const uint8_t *)(p + i + 32));
        uint8x16_t c3 = vld1q_u8((const uint8_t *)(p + i + 48));
        uint8x16_t e0 = vceqq_u8(c0, target);
        uint8x16_t e1 = vceqq_u8(c1, target);
        uint8x16_t e2 = vceqq_u8(c2, target);
        uint8x16_t e3 = vceqq_u8(c3, target);
        uint8x16_t any = vorrq_u8(vorrq_u8(e0, e1), vorrq_u8(e2, e3));
        if (vmaxvq_u8(any)) {
            uint8x16_t hit_eq; size_t base;
            if (vmaxvq_u8(e0))      { hit_eq = e0; base = i; }
            else if (vmaxvq_u8(e1)) { hit_eq = e1; base = i + 16; }
            else if (vmaxvq_u8(e2)) { hit_eq = e2; base = i + 32; }
            else                    { hit_eq = e3; base = i + 48; }
            uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_u8(hit_eq), 0);
            if (lo) return p + base + (__builtin_ctzll(lo) >> 3);
            uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_u8(hit_eq), 1);
            return p + base + 8 + (__builtin_ctzll(hi) >> 3);
        }
    }
    for (; i + 16 <= n; i += 16) {
        uint8x16_t chunk = vld1q_u8((const uint8_t *)(p + i));
        uint8x16_t eq = vceqq_u8(chunk, target);
        uint64_t lo = vgetq_lane_u64(vreinterpretq_u64_u8(eq), 0);
        if (lo) return p + i + (__builtin_ctzll(lo) >> 3);
        uint64_t hi = vgetq_lane_u64(vreinterpretq_u64_u8(eq), 1);
        if (hi) return p + i + 8 + (__builtin_ctzll(hi) >> 3);
    }
    for (; i < n; i++) if (p[i] == c) return p + i;
    return NULL;
}
#else
static const char *march_simd_memchr(const char *p, char c, size_t n) {
    return (const char *)memchr(p, c, n);
}
#endif

/* Substring search shared by every string search site in this file.
 *
 * Two stages: march_simd_memchr finds candidate first bytes with a
 * hand-written SIMD scan (see above), memcmp confirms.  The previous
 * implementation called memcmp at every byte offset, which measured at
 * roughly 0.5 GB/s; delegating the first-byte scan to libc memchr (itself
 * usually SIMD internally, but not something this codebase writes or
 * controls) was the intermediate step before this hand-written kernel.
 *
 * march_string is LENGTH-COUNTED and may contain NUL bytes, so nothing here may
 * use strstr/strchr or treat NUL as a terminator.
 *
 * On a failed candidate the scan resumes at hit + 1, NOT hit + nlen: needles
 * can overlap, and skipping the whole needle would miss the match in
 * ("aaaa", "aa") starting at index 1.  A match that straddles a 16-byte SIMD
 * window boundary is still found correctly: march_simd_memchr only locates
 * the needle's FIRST byte (a single-byte compare, so window boundaries never
 * split what it is looking for), and the subsequent memcmp of the full
 * needle is an ordinary linear scan with no window structure of its own.
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
            march_simd_memchr(p, first, (size_t)(remaining - nlen + 1));
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

/* ASCII-only, first byte, like the siblings above.  The interpreter's
 * versions (eval_builtins.ml) test the same ASCII ranges and use
 * Char.uppercase_ascii / lowercase_ascii, so any other byte (a UTF-8 lead
 * byte included) answers false / is returned unchanged on both backends. */
int64_t march_char_is_alpha(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return 0;
    unsigned char ch = (unsigned char)sc->data[0];
    return ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) ? 1 : 0;
}

int64_t march_char_is_uppercase(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return 0;
    unsigned char ch = (unsigned char)sc->data[0];
    return (ch >= 'A' && ch <= 'Z') ? 1 : 0;
}

int64_t march_char_is_lowercase(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return 0;
    unsigned char ch = (unsigned char)sc->data[0];
    return (ch >= 'a' && ch <= 'z') ? 1 : 0;
}

/* Return a FRESH one-byte string; the argument is only read (borrowed). */
void *march_char_to_uppercase(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return march_string_lit("", 0);
    char ch = sc->data[0];
    if (ch >= 'a' && ch <= 'z') ch = (char)(ch - 'a' + 'A');
    return march_string_lit(&ch, 1);
}

void *march_char_to_lowercase(void *c) {
    march_string *sc = (march_string *)c;
    if (sc->len == 0) return march_string_lit("", 0);
    char ch = sc->data[0];
    if (ch >= 'A' && ch <= 'Z') ch = (char)(ch - 'A' + 'a');
    return march_string_lit(&ch, 1);
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

/* Returns List(Int).  Decodes UTF-8 exactly as the interpreter's
 * `string_to_codepoints` does, INCLUDING its treatment of a truncated
 * sequence: a lead byte whose continuation bytes run past the end of the
 * string yields the lead BYTE itself rather than a replacement character.
 * That is not obviously the right choice, but the two backends have to agree
 * and the interpreter is the older one. */
void *march_string_to_codepoints(void *s) {
    march_string *ss = (march_string *)s;
    const unsigned char *d = (const unsigned char *)ss->data;
    int64_t len = ss->len;
    /* Collect forward into a temporary array, then cons up in reverse — the
     * list has to come out in source order and Cons builds back-to-front. */
    int64_t cap = len > 0 ? len : 1, n = 0;
    int64_t *cps = (int64_t *)malloc(sizeof(int64_t) * (size_t)cap);
    for (int64_t i = 0; i < len; ) {
        unsigned b = d[i];
        if (b < 0x80)                        { cps[n++] = b;                      i += 1; }
        else if (b < 0xE0 && i + 1 < len)    { cps[n++] = ((int64_t)(b - 0xC0) << 6)
                                                        | (d[i+1] - 0x80);        i += 2; }
        else if (b < 0xF0 && i + 2 < len)    { cps[n++] = ((int64_t)(b - 0xE0) << 12)
                                                        | ((int64_t)(d[i+1] - 0x80) << 6)
                                                        | (d[i+2] - 0x80);        i += 3; }
        else if (b >= 0xF0 && i + 3 < len)   { cps[n++] = ((int64_t)(b - 0xF0) << 18)
                                                        | ((int64_t)(d[i+1] - 0x80) << 12)
                                                        | ((int64_t)(d[i+2] - 0x80) << 6)
                                                        | (d[i+3] - 0x80);        i += 4; }
        else                                 { cps[n++] = b;                      i += 1; }
    }
    void *list = make_nil();
    for (int64_t i = n - 1; i >= 0; i--)
        list = make_cons(make_some_i64(cps[i]), list);
    free(cps);
    return list;
}

/* Returns Option(String) in the NICHE encoding (None = 0, Some(p) = p), which
 * is what a heap-pointer payload gets — same as march_process_env.
 * None for an out-of-range codepoint or a UTF-16 surrogate half. */
void *march_string_from_codepoint(int64_t cp) {
    if (cp < 0 || cp > 0x10FFFF) return make_none();
    if (cp >= 0xD800 && cp <= 0xDFFF) return make_none();
    char buf[4];
    int64_t n;
    if (cp <= 0x7F) {
        buf[0] = (char)cp; n = 1;
    } else if (cp <= 0x7FF) {
        buf[0] = (char)(0xC0 | (cp >> 6));
        buf[1] = (char)(0x80 | (cp & 0x3F)); n = 2;
    } else if (cp <= 0xFFFF) {
        buf[0] = (char)(0xE0 | (cp >> 12));
        buf[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        buf[2] = (char)(0x80 | (cp & 0x3F)); n = 3;
    } else {
        buf[0] = (char)(0xF0 | (cp >> 18));
        buf[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        buf[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
        buf[3] = (char)(0x80 | (cp & 0x3F)); n = 4;
    }
    return make_some_ptr(march_string_lit(buf, n));
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
    ((march_hdr *)r)->pad = result_type_id();
    MARCH_FIELD(r, 0) = (int64_t)value;
    return r;
}
static void *mk_ok_unit(void) {
    /* Ok(()) — unit value is null/0 */
    void *r = march_alloc(24);
    ((march_hdr *)r)->pad = result_type_id();
    MARCH_FIELD(r, 0) = 0;
    return r;
}
static void *mk_err(void *msg_str) {
    void *r = march_alloc(24);
    MARCH_SET_TAG(r, 1);
    ((march_hdr *)r)->pad = result_type_id();
    MARCH_FIELD(r, 0) = (int64_t)msg_str;
    return r;
}
static void *mk_err_cstr(const char *msg) {
    return mk_err(march_string_lit(msg, (int64_t)strlen(msg)));
}
static void *mk_err_errno(void) {
    return mk_err_cstr(strerror(errno));
}

/* FileError tags (must match stdlib/file.march ptype declaration order):
   NotFound=0, Permission=1, IsDirectory=2, NotEmpty=3, IoError=4.
   Build a real FileError ctor cell (not a bare string) so compiled code
   matching e.g. Err(NotFound(path)) reads a well-formed tagged cell instead
   of misinterpreting a march_string header as one. */
#define FILEERR_NOT_FOUND    0
#define FILEERR_PERMISSION   1
#define FILEERR_IS_DIRECTORY 2
#define FILEERR_NOT_EMPTY    3
#define FILEERR_IO_ERROR     4

/* File.FileError's header type id (see the march_hdr comment in
 * march_runtime.h).  Cells the C runtime builds carry no type id by default,
 * which is why compiled `to_string` of a file error printed "#<tag:0>" while
 * the interpreter printed NotFound("..."): the value's STATIC type is the
 * bare `FileError` (that is the canonical spelling every builtin signature
 * uses) but the descriptor is keyed on the name the ptype LOWERS to,
 * `File.FileError`, so the static lookup missed and the renderer had only a
 * tag to go on.
 *
 * Stamping the cell answers it from the value instead of from the name.
 * Resolving the bare name to the qualified descriptor at compile time was
 * tried and is NOT sound: `Pid` is a builtin runtime handle and also the
 * short name of stdlib's `GlobalPid.Pid`, so a bare-name alias handed an
 * actor handle a constructor descriptor and the renderer read it as a cell
 * (deterministic SIGSEGV in native_actor_monitor_down_reason, 40/40; see
 * specs/progress/2026-09-12-compiled-to-string-module-declared-type.md).
 * A header id cannot make that mistake: it is written by whoever built the
 * cell. */
static int32_t file_error_type_id(void) {
    static int32_t id = 0;
    if (id == 0) id = march_type_id_of_name("File.FileError");
    return id;
}
static void *mk_file_error(int tag, void *payload_str) {
    void *cell = march_alloc(24); /* header(16) + 1 field(8) */
    MARCH_SET_TAG(cell, tag);
    ((march_hdr *)cell)->pad = file_error_type_id();
    MARCH_FIELD(cell, 0) = (int64_t)payload_str;
    return cell;
}

static void *mk_err_file(int tag, void *payload_str) {
    return mk_err(mk_file_error(tag, payload_str));
}

/* ── errno → FileError mappings ──────────────────────────────────────
   The interpreter does NOT use one mapping for every file_ / dir_
   builtin: each builtin in lib/eval/eval_builtins.ml classifies only the
   errnos its own syscall can actually produce and falls back to IoError.
   The helpers below mirror that split one-for-one.  Routing every site
   through a single mapping would fix the representation bug while still
   reporting the wrong error *kind*, which is harder to spot than the
   original defect.  Reference: lib/eval/eval_net.ml's
   file_error_of_unix / file_error_of_sys, plus the per-builtin `with`
   arms in lib/eval/eval_builtins.ml. */

/* IoError(<msg>) from a C string literal — for failures with no errno. */
static void *mk_err_file_cstr(int tag, const char *msg) {
    return mk_err_file(tag, march_string_lit(msg, (int64_t)strlen(msg)));
}

/* IoError(strerror(errno)) — mirrors `IoError(Unix.error_message err)`. */
static void *mk_err_errno_io(void) {
    return mk_err_file_cstr(FILEERR_IO_ERROR, strerror(errno));
}

/* IoError("<path>: <strerror>") — mirrors the interpreter's Sys_error
   fallback, whose OCaml-formatted message carries the path. */
static void *mk_err_errno_io_path(const char *path) {
    char buf[1024];
    snprintf(buf, sizeof(buf), "%s: %s", path, strerror(errno));
    return mk_err_file_cstr(FILEERR_IO_ERROR, buf);
}

/* Map the current errno to a FileError, mirroring the interpreter's
   unix_error_to_file_error (lib/eval/eval.ml) for file_open: ENOENT ->
   NotFound(path), EACCES -> Permission(path), everything else ->
   IoError(strerror(errno)). */
static void *mk_err_errno_file(const char *path) {
    switch (errno) {
    case ENOENT:
        return mk_err_file(FILEERR_NOT_FOUND, march_string_lit(path, (int64_t)strlen(path)));
    case EACCES:
        return mk_err_file(FILEERR_PERMISSION, march_string_lit(path, (int64_t)strlen(path)));
    default: {
        const char *msg = strerror(errno);
        return mk_err_file(FILEERR_IO_ERROR, march_string_lit(msg, (int64_t)strlen(msg)));
    }
    }
}

/* Full file_error_of_unix / file_error_of_sys mapping, used by the
   read/write/append/delete family: ENOENT -> NotFound, EACCES|EPERM ->
   Permission, EISDIR -> IsDirectory, ENOTEMPTY -> NotEmpty, else
   IoError("<path>: <strerror>"). */
static void *mk_err_errno_file_rw(const char *path) {
    void *p = march_string_lit(path, (int64_t)strlen(path));
    switch (errno) {
    case ENOENT:    return mk_err_file(FILEERR_NOT_FOUND,    p);
    case EACCES:
    case EPERM:     return mk_err_file(FILEERR_PERMISSION,   p);
    case EISDIR:    return mk_err_file(FILEERR_IS_DIRECTORY, p);
    case ENOTEMPTY: return mk_err_file(FILEERR_NOT_EMPTY,    p);
    default:        return mk_err_errno_io_path(path);
    }
}

/* file_stat: ENOENT -> NotFound(path), else IoError(strerror). */
static void *mk_err_errno_stat(const char *path) {
    if (errno == ENOENT)
        return mk_err_file(FILEERR_NOT_FOUND, march_string_lit(path, (int64_t)strlen(path)));
    return mk_err_errno_io();
}

/* dir_list: ENOENT -> NotFound, EACCES -> Permission, ENOTDIR ->
   IsDirectory, else IoError(strerror).  Note ENOTDIR (not EISDIR) maps to
   IsDirectory here, matching the interpreter's dir_list arms. */
static void *mk_err_errno_dir_list(const char *path) {
    void *p = march_string_lit(path, (int64_t)strlen(path));
    switch (errno) {
    case ENOENT:  return mk_err_file(FILEERR_NOT_FOUND,    p);
    case EACCES:  return mk_err_file(FILEERR_PERMISSION,   p);
    case ENOTDIR: return mk_err_file(FILEERR_IS_DIRECTORY, p);
    default:      return mk_err_errno_io();
    }
}

/* dir_rmdir: ENOTEMPTY -> NotEmpty, ENOENT -> NotFound, else IoError. */
static void *mk_err_errno_rmdir(const char *path) {
    void *p = march_string_lit(path, (int64_t)strlen(path));
    switch (errno) {
    case ENOTEMPTY: return mk_err_file(FILEERR_NOT_EMPTY, p);
    case ENOENT:    return mk_err_file(FILEERR_NOT_FOUND, p);
    default:        return mk_err_errno_io();
    }
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
    if (!f) return mk_err_errno_file_rw(ps->data);
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len < 0) { fclose(f); return mk_err_file_cstr(FILEERR_IO_ERROR, "ftell failed"); }
    char *buf = (char *)malloc((size_t)len + 1);
    if (!buf) { fclose(f); return mk_err_file_cstr(FILEERR_IO_ERROR, "out of memory"); }
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
    if (!f) return mk_err_errno_file_rw(ps->data);
    size_t w = fwrite(ds->data, 1, (size_t)ds->len, f);
    fclose(f);
    if ((int64_t)w != ds->len) return mk_err_file_cstr(FILEERR_IO_ERROR, "write failed");
    return mk_ok_unit();
}

void *march_file_append(void *path_ptr, void *data_ptr) {
    march_string *ps = (march_string *)path_ptr;
    march_string *ds = (march_string *)data_ptr;
    FILE *f = fopen(ps->data, "ab");
    if (!f) return mk_err_errno_file_rw(ps->data);
    size_t w = fwrite(ds->data, 1, (size_t)ds->len, f);
    fclose(f);
    if ((int64_t)w != ds->len) return mk_err_file_cstr(FILEERR_IO_ERROR, "write failed");
    return mk_ok_unit();
}

void *march_file_delete(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    if (remove(ps->data) != 0) return mk_err_errno_file_rw(ps->data);
    return mk_ok_unit();
}

void *march_file_copy(void *src_ptr, void *dst_ptr) {
    march_string *src = (march_string *)src_ptr;
    march_string *dst = (march_string *)dst_ptr;
    FILE *in = fopen(src->data, "rb");
    if (!in) return mk_err_errno_io_path(src->data);
    FILE *out = fopen(dst->data, "wb");
    /* fclose() may clobber errno, so classify before closing the source. */
    if (!out) { void *e = mk_err_errno_io_path(dst->data); fclose(in); return e; }
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
    if (rename(src->data, dst->data) != 0) return mk_err_errno_io_path(src->data);
    return mk_ok_unit();
}

/* FileKind tags: RegularFile=0, Directory=1, Symlink=2, OtherKind=3 */
void *march_file_stat(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    struct stat st;
    if (stat(ps->data, &st) != 0) return mk_err_errno_stat(ps->data);
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
    if (!f) return mk_err_errno_file(ps->data);
    void *handle = march_alloc(24);
    MARCH_FIELD(handle, 0) = (int64_t)(uintptr_t)f;
    return mk_ok(handle);
}

/* file_close / csv_close return the `:ok` atom (an i64), matching the
 * typechecker's `Int -> Atom` and the interpreter.  They used to return a
 * heap `Ok(())` Result cell, so a compiled `csv_close(h) == :ok` compared a
 * pointer against an atom (false) and rendered as `:<atom>`.  The "Int"
 * handle is really the heap cell file_open / csv_open built (field 0 is the
 * FILE*); it is an opaque pointer at the March level.  file_close now zeroes
 * field 0 as csv_close always did, so a second close is a no-op, not a
 * double fclose. */
static int64_t march_atom_of_name(const char *name);

int64_t march_file_close(void *handle_ptr) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    if (f) { fclose(f); MARCH_FIELD(handle_ptr, 0) = 0; }
    return march_atom_of_name("ok");
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
    if (!dir) return mk_err_errno_dir_list(ps->data);
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
    if (mkdir(ps->data, 0755) != 0 && errno != EEXIST) return mk_err_errno_io();
    return mk_ok_unit();
}

void *march_dir_mkdir_p(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    if (mkdir_p(ps->data) != 0 && errno != EEXIST) return mk_err_errno_io();
    return mk_ok_unit();
}

void *march_dir_rmdir(void *path_ptr) {
    march_string *ps = (march_string *)path_ptr;
    if (rmdir(ps->data) != 0) return mk_err_errno_rmdir(ps->data);
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
    if (rm_rf(ps->data) != 0) return mk_err_errno_io();
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

int64_t march_csv_close(void *handle_ptr) {
    FILE *f = (FILE *)(uintptr_t)MARCH_FIELD(handle_ptr, 0);
    if (f) { fclose(f); MARCH_FIELD(handle_ptr, 0) = 0; }
    return march_atom_of_name("ok");
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

/* Capabilities are a NULLABLE POINTER: NULL is the plain sentinel (every
   capability that carries no dictionary, which is all of them unless
   `cap_impl` attached one), and otherwise the pointer IS the dictionary
   record.  All three operations below are therefore identity-shaped; the only
   real work is reference counting.
 *
 * OWNERSHIP.  Perceus passes a capability ARGUMENT borrowed and treats a
 * builtin RESULT as owned (it emits a dec for the result and no inc for the
 * argument — visible in `--dump-tir` on any `let d = cap_narrow(c)`).  So a
 * shim that hands its argument straight back must INCREMENT, or the result's
 * dec has no matching inc and the count underflows the moment a capability is
 * a real pointer rather than NULL.  march_incrc is a no-op on non-heap
 * pointers, so this costs nothing for the NULL sentinel — i.e. for every
 * capability in every program that predates dictionaries. */

/* cap_narrow: attenuates a capability to a sub-capability.  Attenuation is a
   compile-time check, so this is the identity — which is also what PROPAGATES
   an attached dictionary across a narrow.
 *
 * NO march_incrc here, deliberately, and the reason is worth keeping: a
 * let-bound cap_narrow result DOES receive a dec_rc (visible in --dump-tir),
 * so if a dictionaried capability ever reached this shim the dec would free a
 * record that the original binding still aliases.  It cannot reach it today:
 * cap_narrow may not produce a proof capability (typecheck_unify.ml's
 * proof-cap forge arm) and an IO capability cannot carry a dictionary
 * (check_cap_impl_sites), so no dictionaried capability is well-typed here.
 * An inc would therefore be an UNTESTABLE guess baked into the runtime.  When
 * IO capabilities gain dictionaries, this ownership question must be
 * re-answered against a program that actually exercises it. */
void *march_cap_narrow(void *cap) {
    return cap;
}

/* mint_cap: a mint produces a NEW capability, not an attenuation of the
   Cap(IO) it was minted from, so it must NOT inherit that capability's
   dictionary — it starts as the plain sentinel.  This used to alias
   march_cap_narrow (identity), which agreed with the interpreter only because
   a Cap(IO) is always NULL today; the moment one could carry a dictionary the
   two backends would silently disagree, compiled inheriting it and
   interpreted not.  Same rule as eval.ml's mint_cap. */
void *march_mint_cap(void *cap) {
    (void)cap;
    return NULL;
}

/* cap_impl: attach a dictionary.  The dictionary becomes the capability's
   runtime value; the capability argument carries nothing else. */
void *march_cap_impl(void *cap, void *dict) {
    (void)cap;
    return dict;
}

/* cap_dict: read the dictionary back as an Option.  Option is NICHE-encoded
   (None = 0, Some(x) = x — see lib/tir/repr.ml), and a capability is already
   NULL-or-pointer, so the Option this returns is bit-identical to its
   argument and no encoding step exists. */
void *march_cap_dict(void *cap) {
    return cap;
}

/* ── Monitor/supervision builtins ────────────────────────────────────── */

/* demonitor: cancel a monitor subscription. Removes the entry from the
   target actor's monitor_head list (best-effort; no-op if ref not found). */
void march_demonitor(int64_t ref) {
    /* Scan all actor meta entries looking for the ref. */
    pthread_mutex_lock(&g_tbl_mu);
    for (int b = 0; b < MARCH_SCHED_BUCKETS; b++) {
        march_actor_meta *m = atomic_load_explicit(&g_actor_tbl[b],
                                                   memory_order_relaxed);
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
            m = atomic_load_explicit(&m->tbl_next, memory_order_relaxed);
        }
    }
    pthread_mutex_unlock(&g_tbl_mu);
}

/* register_supervisor: record supervision metadata for an actor.
   strategy: 0=one_for_one, 1=one_for_all, 2=rest_for_one.
   The actor must already be registered via march_spawn.
   This is a metadata call; actual restart logic is driven by Down events. */
void march_register_supervisor(void *supervisor, int64_t strategy,
                                int64_t max_restarts, int64_t window_secs,
                                int64_t backoff_base_ms,
                                int64_t backoff_cap_ms,
                                int64_t backoff_jitter_pct) {
    if (!IS_HEAP_PTR(supervisor)) return;
    march_reclaim_enter();   /* meta: resolved and used inside */
    march_actor_meta *meta = find_or_create_meta(supervisor);
    if (!meta) { march_reclaim_exit(); return; }
    meta->supervisor_strategy  = (int)strategy;
    meta->supervisor_max_restarts = max_restarts;
    meta->supervisor_window_secs  = window_secs;
    /* The backoff curve. Codegen always emits these three (defaulted by the
     * parser to 25/5000/25, the constants this function's caller used to have
     * hardcoded), but clamp anyway: this is a public C symbol, and a 0 base
     * would make every delay 0 while a negative cap would make the ceiling
     * unreachable. */
    meta->backoff_base_ms = backoff_base_ms > 0 ? backoff_base_ms : 25;
    meta->backoff_cap_ms  = backoff_cap_ms >= meta->backoff_base_ms
                              ? backoff_cap_ms : meta->backoff_base_ms;
    meta->backoff_jitter_pct =
        backoff_jitter_pct < 0 ? 0
      : backoff_jitter_pct > 100 ? 100 : backoff_jitter_pct;
    march_reclaim_exit();
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
                                 void *spawn_clo, int64_t word_idx,
                                 int64_t restart_type, int64_t shutdown_ms) {
    /* One critical section: nothing here switches.  Both actors were just
     * spawned by the calling spawn glue, and the child is not activated yet,
     * so neither meta can normally be missing; if one is (an actor already
     * killed), there is nothing to link. */
    march_reclaim_enter();
    march_actor_meta *sup_meta = find_or_create_meta(supervisor);
    march_actor_meta *child_meta = find_or_create_meta(child);
    if (!sup_meta || !child_meta) { march_reclaim_exit(); return; }
    /* The child was prepared by march_spawn_supervised, so no actor loop can
     * observe this metadata halfway through publication. */
    pthread_mutex_lock(&g_tbl_mu);
    child_meta->sup_pe = sup_meta->pe;
    child_meta->sup_child_index = sup_meta->sup_num_children;
    pthread_mutex_unlock(&g_tbl_mu);
    int idx = sup_meta->sup_num_children;
    sup_meta->sup_children = realloc(sup_meta->sup_children,
                                      (size_t)(idx + 1) * sizeof(march_sup_child));
    sup_meta->sup_children[idx].spawn_clo = spawn_clo;
    sup_meta->sup_children[idx].word_idx = word_idx;
    sup_meta->sup_children[idx].restart_type = (int32_t)restart_type;
    sup_meta->sup_children[idx].shutdown_ms = shutdown_ms;
    sup_meta->sup_children[idx].crash_streak = 0;
    sup_meta->sup_children[idx].last_crash_ms = 0;
    sup_meta->sup_children[idx].pending_names = NULL;
    sup_meta->sup_children[idx].pending_name_count = 0;
    sup_meta->sup_children[idx].pending_spawn_cap = NULL;
    sup_meta->sup_num_children = idx + 1;
    activate_actor_green_thread(child_meta);
    march_reclaim_exit();
}

/* pid_index_of: the Int a compiled supervisor stores in its own state field
 * to represent a just-spawned child's Pid (see march_pid_of_int for the
 * reverse direction). */
int64_t march_pid_index_of(void *actor) {
    /* Live or dead (a dead record the caller still holds resolves through
     * its tombstone); 0 for a record never spawned, as before. */
    march_reclaim_enter();
    march_pid_entry *pe = pid_entry_of_addr(actor);
    int64_t pid_index = pe_pid_or_0(pe);
    march_reclaim_exit();
    return pid_index;
}

/* monitor: establish a monitor link from watcher to target. If death already
 * claimed the target, enqueue the stored terminal reason immediately. */
int64_t march_monitor(void *watcher, void *target) {
    int64_t ref = atomic_fetch_add_explicit(&g_next_monitor_ref, 1,
                                             memory_order_relaxed);
    if (!IS_HEAP_PTR(target)) {
        /* Invalid/never-spawned target: interpreter-compatible Normal fallback. */
        deliver_monitor_down(watcher, ref, target, MARCH_DEATH_NORMAL, NULL, 0);
        return ref;
    }

    march_monitor_node *node = (march_monitor_node *)malloc(sizeof(march_monitor_node));
    if (!node) {
        fputs("march: out of memory registering actor monitor\n", stderr);
        exit(1);
    }
    node->watcher = watcher;
    node->mon_ref = ref;

    /* Link the node onto the target's live meta, or, if the target has
     * already died, deliver its stored terminal reason from its tombstone.
     * Decided under g_tbl_mu, where the death claim unlinks the meta, so a
     * node is never linked onto a meta whose monitor list has already been
     * detached.  find_or_create_meta also covers a target not spawned yet
     * (a C-level stand-in), and returns NULL for a dead one. */
    march_death_reason terminal_reason = MARCH_DEATH_NORMAL;
    const char *terminal_message = NULL;
    size_t terminal_message_len = 0;
    int deliver_now = 0;
    march_reclaim_enter();   /* tm and the tombstone table: used inside */
    march_actor_meta *tm = find_or_create_meta(target);
    pthread_mutex_lock(&g_tbl_mu);
    if (tm && tm->linked && actor_alive_load(target)) {
        node->next = tm->monitor_head;
        tm->monitor_head = node;
    } else {
        /* Dead: its tombstone, found by address because the caller holds
         * the record (so this address is its newest incarnation's). */
        march_pid_entry *pe = (tm && tm->pe) ? tm->pe : tomb_lookup(target);
        if (pe && atomic_load_explicit(&pe->terminal_set, memory_order_acquire)) {
            terminal_reason = pe->terminal_reason;
            terminal_message = pe->terminal_message;
            terminal_message_len = pe->terminal_message_len;
        }
        deliver_now = 1;
    }
    pthread_mutex_unlock(&g_tbl_mu);
    march_reclaim_exit();

    if (deliver_now) {
        free(node);
        deliver_monitor_down(watcher, ref, target, terminal_reason,
                             terminal_message, terminal_message_len);
    }
    return ref;
}

/* mailbox_size: scheduler depth includes both user and reserved control FIFO
 * nodes, so each Down is counted exactly once with no side-band accounting. */
int64_t march_mailbox_size(void *pid) {
    if (!IS_HEAP_PTR(pid)) return 0;
    int64_t depth = 0;
    march_reclaim_enter();   /* meta and gt: resolved and used inside */
    march_actor_meta *meta = find_meta(pid);
    march_proc *gt = meta ? meta_gt(meta) : NULL;
    if (gt) depth = march_sched_mbox_count(gt);
    march_reclaim_exit();
    return depth;
}

/* actor_set_mailbox_limit: bind a mailbox capacity + overflow policy to the
   green thread backing this actor. limit <= 0 means unbounded; policy is a
   march_mbox_policy value (0 unbounded, 1 drop_new, 2 drop_old, 3 block).
   No-op if the actor has no meta entry or no running green thread yet. */
void march_actor_set_mbox_limit(void *actor, int64_t limit, int64_t policy) {
    if (!IS_HEAP_PTR(actor)) return;
    march_reclaim_enter();   /* meta and gt: resolved and used inside */
    march_actor_meta *meta = find_meta(actor);
    march_proc *gt = meta ? meta_gt(meta) : NULL;
    if (gt) march_sched_set_mbox_limit(gt, limit, (march_mbox_policy)policy);
    march_reclaim_exit();
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
 * Callbacks run in reverse acquisition order when kill() is called.
 *
 * The prepend below takes g_tbl_mu, matching march_monitor/march_demonitor's
 * discipline for monitor_head: do_actor_death detaches
 * meta->cleanup_head under the same lock before walking it (see that
 * function's comment), so an unlocked prepend here could race the detach —
 * losing this node entirely, or linking it onto a head do_actor_death is
 * concurrently nulling out from under us. find_meta above is lock-free and
 * march_incrc is a relaxed atomic RMW on the object header with no
 * destructor path, so neither can re-enter and re-acquire g_tbl_mu; only
 * the two-line link itself needs to be inside the critical section. */
void march_register_resource(void *pid, void *name, void *cleanup) {
    (void)name;  /* Name is for documentation only */
    if (!IS_HEAP_PTR(pid)) return;
    march_cleanup_node *node = (march_cleanup_node *)malloc(sizeof(march_cleanup_node));
    if (!node) return;
    node->cleanup_fn = cleanup;
    /* Retain before publishing: take the reference BEFORE the node becomes
     * visible to do_actor_death's detach-and-walk (i.e. before the lock
     * below), not after. Today's caller convention (the compiled call site
     * holds its own live reference across this builtin call, and the
     * cleanup walk never decrc's the closure) means the old publish-then-
     * retain order never actually raced a concurrent drop — but publishing
     * a node whose payload isn't yet retained is fragile against any future
     * caller that doesn't hold its own reference, so retain first. */
    march_incrc(cleanup);  /* Keep closure alive */
    /* Prepend: most recently registered is at head → LIFO on kill.  The meta
     * is resolved under the same lock as the death claim's detach, so a node
     * is linked only onto a live meta's list.  A dead (or never spawned)
     * actor gets no node: nothing would ever run it. */
    march_reclaim_enter();   /* meta: resolved and used inside */
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *meta = find_meta(pid);
    if (meta) {
        node->next = meta->cleanup_head;
        meta->cleanup_head = node;
    }
    pthread_mutex_unlock(&g_tbl_mu);
    march_reclaim_exit();
    if (!meta) {
        march_decrc(cleanup);
        free(node);
    }
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
    if (!actor_alive_load(pid)) return NULL;           /* dead actor -> None */
    march_reclaim_enter();   /* meta: resolved and used inside */
    march_actor_meta *meta = find_meta(pid);
    march_pid_entry *pe = meta ? meta->pe : NULL;
    march_reclaim_exit();
    /* Never spawned, or died since the check above. */
    if (!pe || pe_pid(pe) < 0) return NULL;
    void *cap = march_alloc(40);
    int64_t *w = (int64_t *)cap;
    w[2] = (int64_t)(uintptr_t)pid;
    w[3] = pe_pid(pe);
    w[4] = atomic_load_explicit(&pe->epoch, memory_order_acquire);
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

/* Resolve a cap's (pid_index, epoch) to the meta of the incarnation it names,
 * or NULL if the cap no longer validates: revoked, unknown pid index, that
 * incarnation dead, or an epoch mismatch.
 *
 * NEVER dereferences the actor pointer the cap carries (word[2]), and never
 * reads the actor record's alive word: a cap holds no reference on its actor,
 * so once the actor is dead and the program has dropped its last Pid, the
 * record is freed and its memory reused.  Reading the alive word from that
 * reused memory made a cap on a killed actor validate intermittently (is_cap_valid
 * -> true, send_checked -> :ok, and a send into freed memory).  The pid's
 * tombstone, by contrast, is never freed, and its `live` field is cleared by
 * the death claim under g_tbl_mu before the actor thread drops its own
 * reference on the record.
 *
 * Caller must hold g_tbl_mu: that is what makes "live" imply "the actor
 * thread still holds its reference, so meta->actor is live" for as long as
 * the lock is held. */
static march_actor_meta *cap_live_meta_locked(int64_t pid_index, int64_t epoch) {
    march_pid_entry *pe = pid_entry(pid_index);
    if (!pe) return NULL;
    march_actor_meta *m = atomic_load_explicit(&pe->live, memory_order_relaxed);
    if (!m || !m->actor) return NULL;
    if (atomic_load_explicit(&pe->epoch, memory_order_acquire) != epoch) return NULL;
    return m;
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
    pthread_mutex_lock(&g_tbl_mu);
    int valid = cap_live_meta_locked(pid_index, epoch) != NULL;
    pthread_mutex_unlock(&g_tbl_mu);
    return valid;
}

/* send_checked: send a message to an actor with capability check.
 * Validates revocation, liveness and epoch match, then enqueues.
 *
 * Cap object layout (compiled VCap heap object):
 *   word[0] = rc (int64)
 *   word[1] = tag/pad (int64)
 *   word[2] = actor ptr (NOT a counted reference; not read here, see
 *             cap_live_meta_locked)
 *   word[3] = pid_index (int64)
 *   word[4] = epoch (int64)
 *
 * Returns the :ok atom only when march_send actually accepted the message,
 * :error on any validation failure or when the send itself was refused (the
 * actor died, or started draining, between validation and enqueue).  The
 * validation and the send act on the same record: under g_tbl_mu we take our
 * own reference on the live actor, so it cannot be freed before march_send
 * reads it. */
int64_t march_send_checked(void *cap, void *msg) {
    if (!cap || !IS_HEAP_PTR(cap)) {
        march_decrc(msg);
        return march_atom_of_name("error");
    }
    int64_t *cap_words = (int64_t *)cap;
    int64_t  pidx      = cap_words[3];
    int64_t  epoch     = cap_words[4];
    if (revoc_contains(pidx, epoch)) {
        march_decrc(msg);
        return march_atom_of_name("error");
    }
    pthread_mutex_lock(&g_tbl_mu);
    march_actor_meta *meta = cap_live_meta_locked(pidx, epoch);
    void *actor = meta ? meta->actor : NULL;
    if (actor) march_incrc(actor);
    pthread_mutex_unlock(&g_tbl_mu);
    if (!actor) {
        march_decrc(msg);
        return march_atom_of_name("error");
    }
    /* march_send returns Option(Unit) as a boxed cell: Some(()) carries tag 1
     * at offset 8, None is a bare tag-0 header.  It consumes msg either way. */
    void *result = march_send(actor, msg);
    int delivered = ((int32_t *)((char *)result + 8))[0] == 1;
    march_decrc(result);
    march_decrc(actor);
    return march_atom_of_name(delivered ? "ok" : "error");
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

/* march_actor_pid_indices() -> List(Int): the pid index of every actor alive
 * right now, ascending.
 *
 * The enumeration primitive the overload-shedding guidance needs. Before it,
 * mailbox_size(pid) could only be asked about a Pid you already held, so
 * monitoring code could watch actors it could name in advance and had no way
 * at all to discover an unknown hot one — the documented polling loop could
 * not be closed. March code turns these back into Pids with pid_of_int, the
 * same round trip a supervisor's Int-typed child fields already make.
 *
 * LOCK-FREE on purpose, walking the bucket heads exactly as find_meta does,
 * inside a critical section (see g_actor_tbl for why the walk is safe against
 * a concurrent unlink, and march_actor_meta for why a meta found this way is
 * valid only inside the section).
 * Task 10 deliberately took find_meta off g_tbl_mu to keep sends lock-free; an
 * enumeration that grabbed that mutex on a monitoring timer would re-serialise
 * the very path that work freed.
 *
 * A snapshot is inherently racy — an actor can die between this call and
 * anything done with the result — which is fine and already the norm: every
 * consumer of a Pid handles a dead one.
 *
 * Sorted ascending, and deduplicated, so the result is deterministic (bucket
 * order is an artifact of heap addresses) and identical to the interpreter's. */
static int pid_index_cmp(const void *a, const void *b) {
    int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
    return x < y ? -1 : x > y ? 1 : 0;
}

void *march_actor_pid_indices(void) {
    int64_t cap = 64, n = 0;
    int64_t *idx = (int64_t *)malloc(sizeof(int64_t) * (size_t)cap);
    if (!idx) return make_nil();
    /* Lock-free, inside one critical section (the metas walked are valid only
     * inside it). */
    march_reclaim_enter();
    for (unsigned int b = 0; b < MARCH_SCHED_BUCKETS; b++) {
        for (march_actor_meta *m = atomic_load_explicit(&g_actor_tbl[b],
                                                        memory_order_acquire);
             m; m = atomic_load_explicit(&m->tbl_next, memory_order_acquire)) {
            /* "Has not died", not "is alive right now". The two differ for a
             * just-spawned actor: march_spawn returns before the new actor's
             * green thread has run. The interpreter, whose ai_alive is true
             * from the moment of spawn, lists it; so does this. A meta is
             * linked in g_actor_tbl exactly from its creation to its death
             * claim, so every meta walked here is one that has not died, and
             * the only filter left is "has been spawned" (a tombstone, which
             * carries the index). A snapshot is inherently racy: an actor that
             * dies microseconds after this walk passes it is still listed,
             * which every Pid consumer already handles. The index needs no
             * dedupe any more (one tombstone per spawn, and a meta is linked
             * once), but it is kept below as cheap defence. */
            int64_t pidx = pe_pid(m->pe);
            if (!m->actor || pidx < 0) continue;
            if (n == cap) {
                cap *= 2;
                int64_t *grown = (int64_t *)realloc(idx, sizeof(int64_t) * (size_t)cap);
                if (!grown) break;
                idx = grown;
            }
            idx[n++] = pidx;
        }
    }
    march_reclaim_exit();
    qsort(idx, (size_t)n, sizeof(int64_t), pid_index_cmp);
    void *list = make_nil();
    /* Descending build (Cons is back-to-front), skipping repeats of the index
     * just emitted — sorted, so equal indices are adjacent. */
    for (int64_t i = n - 1; i >= 0; i--) {
        if (i + 1 < n && idx[i] == idx[i + 1]) continue;
        list = make_cons(make_some_i64(idx[i]), list);
    }
    free(idx);
    return list;
}

/* Returns an OWNED reference, like every other value-producing builtin: the
 * Pid it hands back is dropped by whatever holds it (a list cell, a closure
 * parameter), and a borrowed alias dropped that way frees a live actor. */
/*
 * A DEAD pid also gets the sentinel.  It used to get the meta's actor
 * pointer, whose record may already have been freed (a meta found by pid
 * index outlived its record: the live actor's own reference is dropped at
 * green-thread exit), and the incrc here was then a use-after-free.  The
 * record is referenced only while the tombstone's `live` still names a meta,
 * checked under g_tbl_mu, where the death claim clears it before the actor
 * thread drops its reference. */
void *march_pid_of_int(int64_t n) {
    void *actor = NULL;
    pthread_mutex_lock(&g_tbl_mu);
    march_pid_entry *pe = pid_entry(n);
    march_actor_meta *live = pe ? atomic_load_explicit(&pe->live, memory_order_relaxed)
                                : NULL;
    if (live && live->actor) { actor = live->actor; march_incrc(actor); }
    pthread_mutex_unlock(&g_tbl_mu);
    return actor ? actor : (void *)&march_dead_actor_sentinel;
}

/* ── Value pretty-printing ───────────────────────────────────────────── */

/* Render a boxed SIMD vector's Show output for [march_value_to_string]'s
 * type-erased path — "F32x4[1., 2., 3., 4.]" etc, lane-for-lane identical
 * to stdlib/simd.march's `impl Show(<Type>)` (`"F32x4[" ++
 * to_string(extract(v,0)) ++ ", " ++ ... ++ "]"`), so a vector reaching
 * this generic path (e.g. `show`/`to_string` on an erased/polymorphic
 * slot) renders the same as a direct `show(v)` call instead of the
 * previous "#<tag:-4>" placeholder. Reuses [march_float_to_string]'s exact
 * %.12g-plus-trailing-dot algorithm for float lanes (byte-for-byte the
 * interpreter's `string_of_float`) and [march_int_to_string]'s %lld for
 * integer lanes (u8 lanes widen to Int first, matching
 * `simd_u8x16_extract`'s zero-extend contract). Builds via repeated
 * [march_string_concat] rather than one big buffer — Show is not a hot
 * path, and this way every piece (literal, float, int) goes through the
 * SAME formatting helper the rest of the runtime already uses, so a future
 * change to float/int formatting can't silently diverge here. */
static void *march_simd_to_string(void *v) {
    int32_t kind = ((march_hdr *)v)->pad;
    const char *pa = (const char *)v + 16;
    static const char *const names[5] = { "F32x4", "F64x2", "I32x4", "I64x2", "U8x16" };
    static const int lane_counts[5] = { 4, 2, 4, 2, 16 };
    if (kind < 0 || kind > 4) {
        char buf[64];
        int n = snprintf(buf, sizeof(buf), "#<tag:%d>", (int)MARCH_SIMD_TAG);
        return march_string_lit(buf, n);
    }
    void *acc = march_string_lit(names[kind], (int64_t)strlen(names[kind]));
    {
        void *bracket = march_string_lit("[", 1);
        void *next = march_string_concat(acc, bracket);
        march_decrc(acc); march_decrc(bracket);
        acc = next;
    }
    int n = lane_counts[kind];
    for (int i = 0; i < n; i++) {
        void *piece;
        switch (kind) {
            case 0: { float f;    memcpy(&f, pa + (size_t)i * 4, 4); piece = march_float_to_string((double)f); break; }
            case 1: { double d;   memcpy(&d, pa + (size_t)i * 8, 8); piece = march_float_to_string(d); break; }
            case 2: { int32_t x;  memcpy(&x, pa + (size_t)i * 4, 4); piece = march_int_to_string((int64_t)x); break; }
            case 3: { int64_t x;  memcpy(&x, pa + (size_t)i * 8, 8); piece = march_int_to_string(x); break; }
            default: { uint8_t x; memcpy(&x, pa + (size_t)i, 1);      piece = march_int_to_string((int64_t)x); break; }
        }
        void *next = march_string_concat(acc, piece);
        march_decrc(acc); march_decrc(piece);
        acc = next;
        if (i + 1 < n) {
            void *sep = march_string_lit(", ", 2);
            next = march_string_concat(acc, sep);
            march_decrc(acc); march_decrc(sep);
            acc = next;
        }
    }
    {
        void *close = march_string_lit("]", 1);
        void *next = march_string_concat(acc, close);
        march_decrc(acc); march_decrc(close);
        acc = next;
    }
    return acc;
}

/* Format a March value as a human-readable string.
   Handles tagged immediates (low bit == 1), actor Pids, and heap objects. */
void *(*march_render_dyn_hook)(void *v, int repr) = NULL;

void *march_value_to_string(void *v) { return march_value_to_string_mode(v, 0); }
void *march_value_to_string_repr(void *v) { return march_value_to_string_mode(v, 1); }

void *march_value_to_string_mode(void *v, int repr) {
    if (!v) return march_string_lit("nil", 3);
    /* Tagged immediate: low bit == 1 → extract integer value via arithmetic
     * right-shift of the raw pointer bits (sign-preserving). */
    if (((uintptr_t)v & 1u) != 0) {
        int64_t n = (intptr_t)v >> 1;
        return march_int_to_string(n);
    }
    /* Inline (SSO) string: bit63 set, low bit clear.  This is a VALUE, not an
     * address, so it MUST be classified before anything dereferences v — and
     * before IS_HEAP_PTR, which the encoding is deliberately built to fail
     * (march_runtime.h's small-string section).  Inline strings are
     * refcount-free, so returning v unchanged already satisfies the +1
     * contract.  Missing this arm made every erased short string fall through
     * to the h->tag load below and SIGSEGV. */
    if (march_str_is_inline(v)) return v;
    /* Not a heap pointer and not one of the immediate encodings: there is no
     * header to read, so print the bits rather than dereferencing them.  This
     * is the last line of defence for a value that reached an erased slot in a
     * non-uniform representation (raw Float bits were the historical source —
     * see rec_box_erased_float in march_extras.c, which now prevents it). */
    if (!IS_HEAP_PTR(v)) {
        char buf[64];
        int n = snprintf(buf, sizeof(buf), "#<value:0x%llx>",
                         (unsigned long long)(uintptr_t)v);
        return march_string_lit(buf, n);
    }
    march_hdr *h = (march_hdr *)v;
    int32_t tag = h->tag;
    /* String heap cell: every march_string carries MARCH_STRING_TAG at the
     * tag word, so to_string on a value whose static type erased to a TVar but
     * actually holds a string returns the string verbatim (identity), matching
     * the interpreter — instead of misreading the layout (len-as-tag) and
     * printing "#<tag:len>".  Result is +1: alias the borrowed input.
     *
     * Tested BEFORE the actor-Pid lookup below: this is the hot case now that
     * Show$String.show routes through here (lib/tir/lower.ml), and an actor's
     * heap cell always carries an ordinary ctor/record tag (>= 0), never one of
     * the reserved negative sentinels — so the reorder cannot change a verdict. */
    if (tag == MARCH_STRING_TAG) { march_incrc(v); return v; }
    /* Boxed float in an erased slot: render the value, not "#<tag:-3>"
     * (float-boxing design; also closes a cousin of the to_string-on-erased
     * divergence). */
    if (tag == MARCH_FLOAT_TAG) return march_float_to_string(march_unbox_float(v));
    /* Boxed SIMD vector in an erased slot: render lane-for-lane like
       impl Show(<Type>), not "#<tag:-4>" — see march_simd_to_string. */
    if (tag == MARCH_SIMD_TAG) return march_simd_to_string(v);
    /* Check if this pointer is an actor (live, or dead with its record
     * still held) → display as Pid(n).  A live meta not yet spawned prints
     * Pid(0), as it always did. */
    march_reclaim_enter();
    march_actor_meta *meta = find_meta(v);
    int is_actor = meta != NULL;
    march_pid_entry *pe = meta ? meta->pe : tomb_lookup(v);
    int64_t pid_index = pe_pid_or_0(pe);
    march_reclaim_exit();
    if (is_actor || pe) {
        char buf[64];
        int n = snprintf(buf, sizeof(buf), "Pid(%lld)", (long long)pid_index);
        return march_string_lit(buf, n);
    }
    /* A boxed ADT whose header carries a type id (see march_hdr_type_id):
     * the constructor-name table can render it by name even though no static
     * type reached this call.  Only consulted for an ordinary ctor tag, and
     * only once some compilation unit has registered its descriptor. */
    if (tag >= 0 && march_render_dyn_hook) {
        void *r = march_render_dyn_hook(v, repr);
        if (r) return r;
    }
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

/* Milliseconds since the Unix epoch.  Deliberately NOT
 * `(int64_t)(march_unix_time() * 1000.0)`: a double carries 53 bits of
 * mantissa, so once the epoch reaches ~2^53 nanoseconds of precision the
 * seconds-as-double round trip starts dropping sub-millisecond bits and two
 * reads a millisecond apart can come back equal.  Compute in integers instead,
 * which is also what the interpreter's `int_of_float (gettimeofday () *. 1000.)`
 * gets right by accident at today's magnitudes. */
int64_t march_unix_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

/* Peak resident set size of this process, in BYTES on every platform.
 * getrusage reports ru_maxrss in BYTES on macOS and KILOBYTES on Linux;
 * normalising here means no caller can repeat the 1024x error that
 * bench/run_string_bench.sh documents. */
int64_t march_peak_rss_bytes(void) {
    struct rusage ru;
    if (getrusage(RUSAGE_SELF, &ru) != 0) return 0;
#if defined(__APPLE__)
    return (int64_t)ru.ru_maxrss;
#else
    return (int64_t)ru.ru_maxrss * 1024;
#endif
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
 * closure inline on a normal stack (the drain runs from the loop body, never
 * from the signal handler).  The OS handler itself is installed SA_ONSTACK —
 * see march_install_async_signal for why that is not optional.
 *
 * The code of the preemption signal -- Usr1 (3) unless MARCH_PREEMPT_SIGNAL
 * moved it (march_preempt_signal, march_scheduler.c) -- is RESERVED and cannot
 * be watched in compiled programs; march_signal_watch refuses it.  Term/Int (0/1) suppress the
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

/* Install [handler] for [sig] so the kernel builds its signal frame on the
 * per-thread alternate stack (SA_ONSTACK), with signal()'s BSD restart
 * semantics (SA_RESTART).  Used for every runtime handler of a signal that can
 * arrive while a green thread is running (Signal.watch, the HTTP server's
 * Term/Int shutdown handler).
 *
 * SA_ONSTACK is load-bearing, not a nicety.  A signal delivered on a scheduler
 * thread lands on whatever stack is current, and that is usually a green
 * thread's: only MARCH_STACK_INITIAL (4 KiB) of it is committed, the rest is
 * PROT_NONE and grows lazily through the SIGSEGV handler.  The kernel cannot
 * take that fault while building the frame, so a frame that does not fit
 * below SP is fatal: Linux force-sends SIGSEGV with si_code SI_KERNEL (128)
 * and si_addr 0, which the growth handler rightly reports as "fault outside
 * its stack".  On linux/aarch64 the rt_sigframe alone is ~4.6 KiB (its
 * uc_mcontext reserves a full 4096-byte __reserved area), so it can NEVER fit
 * in a fresh green stack and test/native/signal_watch.march died 40/40 there;
 * x86_64 and macOS frames are small enough to fit by luck of headroom.
 * Scheduler threads all have a 64 KiB altstack (setup_alt_stack); a thread
 * without one simply gets the frame on its current (ordinary) stack. */
void march_install_async_signal(int sig, void (*handler)(int)) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_ONSTACK | SA_RESTART;
    sigaction(sig, &sa, NULL);
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

/* Test seam (test/test_signal_watch.c): when non-NULL, called by
 * march_signal_watch immediately after the new watcher is published, i.e. at
 * the point where a concurrent delivery would be deferred to it.  Lets a test
 * land a signal exactly in the registration window.  Never set in programs. */
void (*march_signal_watch_test_hook)(int64_t code) = NULL;

/* Register a watcher.  The closure is passed OWNED (Perceus: the borrow pass
 * marks this call site as consuming), so we keep its reference in the table
 * and release it on replace / unwatch. */
void march_signal_watch(int64_t code, void *clo) {
    if (code < 0 || code > 4) { if (clo) march_decrc(clo); return; }
    /* The code that maps to the preemption signal is reserved: SIGUSR1 (code
     * 3) by default, whichever signal $MARCH_PREEMPT_SIGNAL chose otherwise
     * (none of the five if it chose a real-time signal). */
    if (code == march_signal_code_of_os(march_preempt_signal())) {
        static const char *names[5] = { "Term", "Int", "Hup", "Usr1", "Usr2" };
        fprintf(stderr,
            "march: Signal.watch(%s) is unsupported in compiled programs — "
            "SIG%s is reserved for the scheduler's green-thread preemption "
            "(set MARCH_PREEMPT_SIGNAL to move it); the watcher is ignored.\n",
            names[code], code == 3 ? "USR1" : code == 4 ? "USR2" : names[code]);
        if (clo) march_decrc(clo);
        return;
    }
    /* Reset the per-signal state BEFORE publishing the watcher.  Once the
     * exchange below makes the slot non-NULL, march_signal_dispatch (already
     * the OS handler on a re-watch) defers deliveries to `pending`; a clear
     * AFTER that point would wipe a delivery that landed in between, silently
     * dropping it.  Clearing first means only deliveries that precede this
     * registration are discarded.  Relaxed is enough: the acq_rel exchange
     * orders these stores before the watcher becomes visible, and the handler
     * interrupting this thread observes program order anyway. */
    atomic_store_explicit(&g_signal_seen[code], 0, memory_order_relaxed);
    atomic_store_explicit(&g_signal_pending[code], 0, memory_order_relaxed);
    void *old = atomic_exchange_explicit(&g_signal_handlers[code], clo,
                                         memory_order_acq_rel);
    if (march_signal_watch_test_hook) march_signal_watch_test_hook(code);
    if (old) march_decrc(old);
    /* Overrides any prior Term/Int shutdown handler with the watcher-aware
     * one.  Must be SA_ONSTACK: see march_install_async_signal. */
    march_install_async_signal(march_signal_os_of_code((int)code),
                               march_signal_dispatch);
}

/* Remove a watcher, restoring the signal's default disposition. */
void march_signal_unwatch(int64_t code) {
    if (code < 0 || code > 4
        || code == march_signal_code_of_os(march_preempt_signal())) return;
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
        /* The cons cell owns its head and releases it when the list dies;
         * the array still holds the element, so the cell needs its own +1
         * (same reasoning as march_typed_array_get). */
        march_incrc(elem);
        lst = make_cons(elem, lst);
    }
    return lst;
}

int64_t march_typed_array_length(void *arr) {
    return *(int64_t *)((char *)arr + 16);
}

/* Returns an OWNED reference: the element stays in the array, so the caller
 * gets its own +1.  It used to return the bare slot, which only stayed
 * balanced because every consumer that received it was (wrongly) treated as
 * consuming a reference it never released -- `==`, string_length, to_string.
 * Once those borrow (borrow.ml), a borrowed consumer releases its dead-after
 * argument, and a bare slot would be freed under the array.  A tagged
 * immediate needs no reference (march_incrc ignores it). */
void *march_typed_array_get(void *arr, int64_t i) {
    int64_t len = march_typed_array_length(arr);
    typed_array_check_bounds(i, len);
    void *elem = *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + i * 8);
    march_incrc(elem);
    return elem;
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

/* typed_array_slice(arr, start, len): a fresh array holding a COPY of the
 * clamped range, never an alias of [arr].
 *
 * Bounds CLAMP, matching the interpreter (eval_builtins.ml) exactly, and never
 * fail:  s = max 0 (min start alen);  e = max s (min (s + len) alen).
 * So a negative start reads from 0, a start at/after the end or a
 * non-positive len gives an empty array, and a len running past the end
 * stops at the end. [s + len] is computed without overflow (the interpreter's
 * 63-bit ints wrap there; a huge len here simply means "to the end").
 *
 * RC contract: [arr] is BORROWED (borrow.ml's extern_borrow_table): this
 * function neither stores nor releases it, and the caller drops it after its
 * last use. Each copied element gets its own reference (march_incrc; a no-op
 * on a tagged immediate), since the slice owns its slots independently of
 * [arr], which may be freed first. */
void *march_typed_array_slice(void *arr, int64_t start, int64_t len) {
    int64_t alen = march_typed_array_length(arr);
    int64_t s = start < 0 ? 0 : (start > alen ? alen : start);
    int64_t avail = alen - s;                       /* >= 0 */
    int64_t n = len <= 0 ? 0 : (len > avail ? avail : len);
    void *out = typed_array_alloc(n);
    for (int64_t i = 0; i < n; i++) {
        void *elem = *(void **)((char *)arr + TYPED_ARRAY_HDR_SIZE + (s + i) * 8);
        march_incrc(elem);
        *(void **)((char *)out + TYPED_ARRAY_HDR_SIZE + i * 8) = elem;
    }
    return out;
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
        march_clo_arg_retain(elem);   /* the array keeps its element */
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

/* Release a fold's PREVIOUS accumulator when the closure did not. [prev] is
 * the accumulator just handed to the closure, [result] what it returned, [acc]
 * the fold's INITIAL accumulator.
 *
 * A closure call consumes its heap arguments (march_clo_arg_retain in
 * march_runtime.h), so a non-Float [prev] is the callee's to release or to
 * hand back as [result]; this loop owns nothing more, and may not even look
 * at it again: the callee may already have freed it. That is why the Float
 * test is taken BEFORE the call ([fold_acc_is_float], passed in as
 * [prev_is_float]) — reading [prev]'s tag afterwards is a use-after-free
 * (caught by ASAN on native_arr_fold_acc_leak_probe).
 *
 * A boxed Float is the exception: the apply fn unboxes it in its prologue and
 * never releases the box, and every Float coming out of an apply fn is a FRESH
 * box (re-boxed on return by march_alloc_float), so a Float [prev] that is not
 * [result] is still solely ours.
 *
 * [acc] used to be excluded here too, on the intuition that the fold's INITIAL
 * accumulator belongs to the caller. It does not: every one of these helpers
 * is classified in [extern_owned_builtins], so the caller TRANSFERS its
 * reference, and the call site's boxed-generic-param coercion
 * (Llvm_builtins.builtin_boxed_generic_params_tbl) makes that box FRESH at
 * every call -- `fold_float(a, 0.0, f)` emits a march_alloc_float whose only
 * owner is the call. Excluding it leaked exactly one box per call, independent
 * of length (4/16/64/256 elements all grew by the same amount over 2,000
 * calls), which is what gave the leak away as a boundary cost rather than a
 * per-element one. Dropping the exclusion makes the helper honour the owned
 * convention it is declared under. A zero-length fold never enters the loop,
 * so [acc] is handed straight back as [result] and the caller releases it
 * once; the [prev == result] guard covers a closure that returns its
 * accumulator argument unchanged. See
 * specs/todos/2026-09-16-native-float-arr-fold-leaks-two-boxes-per-call.md.
 *
 * Pinned by test/native/native_arr_fold_acc_leak_probe.march: the Float and
 * String accumulator legs (leak direction) and the identity + element-alias
 * legs (double-free direction). */
static inline int fold_acc_is_float(void *prev) {
    return IS_HEAP_PTR(prev) && ((march_hdr *)prev)->tag == MARCH_FLOAT_TAG;
}

static inline void fold_release_prev_acc(void *prev, int prev_is_float,
                                         void *result) {
    if (!prev_is_float || prev == result) return;
    march_decrc(prev);
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
        void *prev = result;
        int prev_is_float = fold_acc_is_float(prev);
        march_incrc(f);
        /* Unlike every other fold helper here, [elem] is a pointer the ARRAY
         * owns (the int/i32/u8 helpers wire-tag an immediate; the f64/f32
         * helpers box a fresh one and release it themselves), and the call
         * consumes it, so the callee gets its own reference. That also makes
         * a closure that hands the element straight back (`fn (acc, x) -> x`)
         * return a reference this loop owns. */
        march_clo_arg_retain(elem);
        result = call_closure_2(f, prev, elem);
        fold_release_prev_acc(prev, prev_is_float, result);
    }
    march_decrc(f);
    return result;
}

/* ── Native int/float arrays ──────────────────────────────────────────── */
/* NATIVE_ARR_HDR / NATIVE_ELEM_* and the layout they describe are declared
 * once in march_runtime.h so march_extras.c can share them without a second
 * #define. */

static void *native_arr_alloc(int64_t len, int64_t elem_size, uint8_t kind) {
    if (len < 0) { fputs("march: native array: negative length\n", stderr); exit(1); }
    int64_t body;
    if (__builtin_mul_overflow(len, elem_size, &body)) {
        fputs("march: native array: array too large\n", stderr); exit(1);
    }
    void *arr = march_alloc(NATIVE_ARR_HDR + body);
    /* march_alloc returns 16-aligned memory and NATIVE_ARR_HDR is a multiple
     * of 16, so data is unconditionally 16-aligned — assert it so a future
     * allocator change fails loudly instead of faulting a vector load. */
    if ((((uintptr_t)arr + NATIVE_ARR_HDR) & 15) != 0) {
        fputs("march: native array: misaligned allocation\n", stderr); exit(1);
    }
    ((march_hdr *)arr)->tag = MARCH_NATIVE_ARR_TAG;
    *(int64_t *)((char *)arr + 16) = len;
    *(uint8_t *)((char *)arr + 24) = kind;
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
void *native_int_arr_alloc_raw(int64_t len) { return native_arr_alloc(len, 8, NATIVE_ELEM_I64); }
void *native_float_arr_alloc_raw(int64_t len) { return native_arr_alloc(len, 8, NATIVE_ELEM_F64); }

void *native_int_arr_make(int64_t len, int64_t def) {
    void *arr = native_arr_alloc(len, 8, NATIVE_ELEM_I64);
    for (int64_t i = 0; i < len; i++)
        *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8) = def;
    return arr;
}

/* Index bounds check for the NativeArray element accessors.
 *
 * Every native_*_arr_get/_set used to be a raw load/store at
 * `arr + NATIVE_ARR_HDR + i * sizeof(elem)` with no range test, so an
 * out-of-range index from SAFE March code read or wrote arbitrary heap
 * memory — `_set` worst of all, since both its FBIP in-place path and its
 * copy path stored at the unchecked offset. stdlib/native_array.march has
 * always documented "Panics if out of bounds" and the interpreter has always
 * honoured it (lib/eval/eval.ml), so this was an interp/compiled divergence
 * as well as a memory-safety hole — and one the oracle sweep could not see,
 * because it only compares programs that stay in range.
 *
 * `fn` names the accessor so the message pins WHICH one tripped, and the
 * "<fn>: index N out of bounds (len=M)" tail is byte-identical to the
 * interpreter's wording; test/native/native_arr_bounds_panic.march asserts
 * that substring for all ten accessors, so the two backends cannot drift.
 * The "march: runtime error: " prefix matches the other compiled bounds
 * panics (typed_array_check_bounds, march_simd_bounds_panic) rather than the
 * interpreter's bare form — see simd_bounds_panic.march's note that the two
 * backends deliberately differ in prefix only.
 *
 * Length lives at byte offset 16 for every native array width, which is what
 * the per-width native_*_arr_length accessors read.
 *
 * Scope: the USER-FACING accessors only. The inline map/fold fast paths
 * (llvm_emit's $mapfast$ / nmap_body clones, and the *_fold bodies here)
 * generate their own indices from a length they just read, so they are in
 * range by construction; checking them would add a branch per element to
 * exactly the loops NativeArray exists to make fast. */
static void native_arr_check_bounds(const char *fn, int64_t i, int64_t len) {
    if (i < 0 || i >= len) {
        fprintf(stderr,
            "march: runtime error: %s: index %lld out of bounds (len=%lld)\n",
            fn, (long long)i, (long long)len);
        exit(1);
    }
}

int64_t native_int_arr_length(void *arr) {
    return *(int64_t *)((char *)arr + 16);
}

int64_t native_int_arr_get(void *arr, int64_t i) {
    native_arr_check_bounds("native_int_arr_get", i, native_int_arr_length(arr));
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
    native_arr_check_bounds("native_int_arr_set", i, native_int_arr_length(arr));
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8) = val;
        return arr;
    }
    int64_t len = native_int_arr_length(arr);
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_I64);
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

/* ── NativeArray.sort_int: in-place ipnsort-style sort ──────────────────────
 *
 * Design + measurements: specs/progress/2026-09-25-native-array-sort-narrow-widths.md
 * (5-30x libc qsort at n=5M on 7 of 8 input patterns; harness is
 * bench/c/native_sort_bench.c, which verifies every variant against qsort).
 *
 * Unstable, in place, no scratch allocation. Stability is unobservable for
 * bare i64 elements, which is what makes the unstable design free here.
 *
 * Four pieces carry the speed, and each has a regression test that goes red
 * when it is removed (test/native/native_arr_sort.march):
 *   1. a top-level full-run scan      — sorted/reversed input in O(n)
 *   2. equal-partition on a repeated pivot — low-cardinality input in O(n·log k)
 *   3. branchless Lomuto partitioning — clang emits csel, no branch misses
 *   4. an 8-element sorting network   — the small-sort base case
 * Plus a heapsort fallback at depth 2·log2(n) for the O(n log n) bound.
 */

/* The core is written once, as NSORT_DEFINE_CORE(W, T) below, and
 * instantiated for i64 (sort_int, and sort_float on 64-bit totalOrder keys)
 * and i32 (sort_i32, and sort_f32 on 32-bit totalOrder keys). Every helper is
 * suffixed with its width: nsort_heap_i64, nsort_net8_i32, ... The width-free
 * pieces (the xorshift rng and the depth-limit test hook) are shared. u8 does
 * not use the core at all: it is a counting sort (native_u8_arr_sort).
 *
 * Notes on the pieces, since comments inside a multi-line #define are awkward:
 *
 * NSORT_CSWAP_T — branchless compare-exchange. Written as a select on both
 *   slots so clang emits two csel and no branch; an `if (a > b) swap` here
 *   measured slower.
 *
 * nsort_swap_W — parameters are deliberately not named `a`/`b`:
 *   scripts/check-actor-rc-stores.sh is a grep-level guard that treats
 *   `*a = ...` as a refcount store, because an actor alias named `a` is
 *   declared elsewhere in this file.
 *
 * nsort_net8_W — optimal 19-comparator sorting network for 8 elements
 *   (Knuth 5.3.4). Verified by the 0-1 principle (256 cases) in
 *   bench/c/native_sort_bench.c.
 *
 * nsort_small_W — network each aligned block of 8, then one insertion pass.
 *   The insertion pass is near-linear afterwards because every element is
 *   already within its own block, which is the point of doing the network
 *   first.
 *
 * nsort_pivot_W — pseudo-median of 9 at stride n/8 for n >= 64, median of 3
 *   below.
 *
 * nsort_part_lt_W / nsort_part_le_W — branchless Lomuto. Both slots are
 *   written unconditionally and only the output cursor advances
 *   conditionally, so there is no data-dependent branch in the loop.
 *   Elements satisfying the predicate land in v[0..ret). Do not "simplify"
 *   these into `if (pred) swap`: that reintroduces exactly the branch
 *   misprediction this shape exists to avoid, and measured ~3x slower on
 *   random input.
 *
 * nsort_break_patterns_W — pattern-breaking (pdqsort). Fixed-stride pivot
 *   sampling is defeated by periodic input: when the period divides the
 *   stride, all nine samples read the same value, every pivot is the segment
 *   minimum, and the depth limit dumps the whole array into heapsort.
 *   Measured on `i % 1000` at n=5M: 337ms without this, 38-97ms with it.
 *   Only runs on a partition that actually came out lopsided, so balanced
 *   input never pays for it. The seed is derived from the length rather than
 *   from a clock, so a given input always takes the same path; a
 *   non-reproducible sort is miserable to debug.
 *
 * nsort_rec_W — [ancestor], when non-NULL, points at a pivot that every
 *   element of [v] is known to be >= . If the newly chosen pivot is not
 *   greater than it, the two are equal, and so is every element <= the new
 *   pivot: partition those out and drop them from consideration entirely.
 *   This is what turns a low-cardinality array from O(n log n) into roughly
 *   O(n log k). Recurse left, loop right; depth is bounded by [limit], so the
 *   recursion cannot outrun the stack even on an adversarial input.
 *
 * nsort_W — the entry. Top-level full-run scan first: a wholly sorted or
 *   wholly descending array is finished in one pass. Only at the top level,
 *   as ipnsort does; checking every segment costs more than it saves. The
 *   depth limit is 2*floor(log2 n), unless the MARCH_TEST_NSORT_DEPTH_LIMIT
 *   hook (nsort_forced_limit) overrides it, which every width honours. */

static inline uint64_t nsort_rng(uint64_t *s) {
    uint64_t x = *s;
    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
    *s = x;
    return x;
}

/* Test hook: MARCH_TEST_NSORT_DEPTH_LIMIT=<k> replaces the 2·log2(n) depth
 * limit with k, so k = 0 sends every segment above the small-sort cutoff
 * straight to nsort_heap_W. That is the only way to exercise the heapsort
 * fallback directly: the pattern-breaking step makes it practically
 * unreachable from any input. test/dune runs native_arr_sort and
 * native_arr_sort_narrow a second time with this set to 0 and diffs against
 * the same golden. Read once; the benign race on first use stores the same
 * value from every thread. */
static int nsort_forced_limit(void) {
    static int cached = -2;             /* -2 unread, -1 unset, else the limit */
    int c = __atomic_load_n(&cached, __ATOMIC_RELAXED);
    if (c == -2) {
        const char *e = getenv("MARCH_TEST_NSORT_DEPTH_LIMIT");
        c = (e && e[0]) ? atoi(e) : -1;
        if (c < -1) c = -1;
        __atomic_store_n(&cached, c, __ATOMIC_RELAXED);
    }
    return c;
}

#define NSORT_CSWAP_T(T, i, j)                                                 \
    do {                                                                       \
        T _x = v[i], _y = v[j];                                                \
        int _lt = _y < _x;                                                     \
        v[i] = _lt ? _y : _x;                                                  \
        v[j] = _lt ? _x : _y;                                                  \
    } while (0)

#define NSORT_DEFINE_CORE(W, T)                                                \
static inline void nsort_swap_##W(T *lhs, T *rhs) {                            \
    T t = *lhs; *lhs = *rhs; *rhs = t;                                         \
}                                                                              \
                                                                               \
static inline void nsort_net8_##W(T *v) {                                      \
    NSORT_CSWAP_T(T, 0, 2); NSORT_CSWAP_T(T, 1, 3);                            \
    NSORT_CSWAP_T(T, 4, 6); NSORT_CSWAP_T(T, 5, 7);                            \
    NSORT_CSWAP_T(T, 0, 4); NSORT_CSWAP_T(T, 1, 5);                            \
    NSORT_CSWAP_T(T, 2, 6); NSORT_CSWAP_T(T, 3, 7);                            \
    NSORT_CSWAP_T(T, 0, 1); NSORT_CSWAP_T(T, 2, 3);                            \
    NSORT_CSWAP_T(T, 4, 5); NSORT_CSWAP_T(T, 6, 7);                            \
    NSORT_CSWAP_T(T, 2, 4); NSORT_CSWAP_T(T, 3, 5);                            \
    NSORT_CSWAP_T(T, 1, 4); NSORT_CSWAP_T(T, 3, 6);                            \
    NSORT_CSWAP_T(T, 1, 2); NSORT_CSWAP_T(T, 3, 4); NSORT_CSWAP_T(T, 5, 6);    \
}                                                                              \
                                                                               \
static void nsort_insertion_##W(T *v, int64_t n) {                             \
    for (int64_t i = 1; i < n; i++) {                                          \
        T x = v[i]; int64_t j = i;                                             \
        while (j > 0 && v[j - 1] > x) { v[j] = v[j - 1]; j--; }                \
        v[j] = x;                                                              \
    }                                                                          \
}                                                                              \
                                                                               \
static void nsort_small_##W(T *v, int64_t n) {                                 \
    int64_t i = 0;                                                             \
    for (; i + 8 <= n; i += 8) nsort_net8_##W(v + i);                          \
    nsort_insertion_##W(v, n);                                                 \
}                                                                              \
                                                                               \
static void nsort_heap_##W(T *v, int64_t n) {                                  \
    for (int64_t start = n / 2; start-- > 0;) {                                \
        int64_t root = start;                                                  \
        for (;;) {                                                             \
            int64_t child = 2 * root + 1;                                      \
            if (child >= n) break;                                             \
            if (child + 1 < n && v[child] < v[child + 1]) child++;             \
            if (v[root] >= v[child]) break;                                    \
            nsort_swap_##W(&v[root], &v[child]);                               \
            root = child;                                                      \
        }                                                                      \
    }                                                                          \
    for (int64_t end = n; end-- > 1;) {                                        \
        nsort_swap_##W(&v[0], &v[end]);                                        \
        int64_t root = 0;                                                      \
        for (;;) {                                                             \
            int64_t child = 2 * root + 1;                                      \
            if (child >= end) break;                                           \
            if (child + 1 < end && v[child] < v[child + 1]) child++;           \
            if (v[root] >= v[child]) break;                                    \
            nsort_swap_##W(&v[root], &v[child]);                               \
            root = child;                                                      \
        }                                                                      \
    }                                                                          \
}                                                                              \
                                                                               \
static inline int64_t nsort_median3_##W(const T *v, int64_t i0, int64_t i1,    \
                                        int64_t i2) {                          \
    int ab = v[i0] < v[i1], ac = v[i0] < v[i2], bc = v[i1] < v[i2];            \
    if (ab == bc) return i1;                                                   \
    if (ab == ac) return i2;                                                   \
    return i0;                                                                 \
}                                                                              \
                                                                               \
static int64_t nsort_pivot_##W(const T *v, int64_t n) {                        \
    if (n >= 64) {                                                             \
        int64_t s = n / 8;                                                     \
        int64_t p0 = nsort_median3_##W(v, 0, s, 2 * s);                        \
        int64_t p1 = nsort_median3_##W(v, 3 * s, 4 * s, 5 * s);                \
        int64_t p2 = nsort_median3_##W(v, 6 * s, 7 * s, n - 1);                \
        return nsort_median3_##W(v, p0, p1, p2);                               \
    }                                                                          \
    return nsort_median3_##W(v, 0, n / 2, n - 1);                              \
}                                                                              \
                                                                               \
static int64_t nsort_part_lt_##W(T *v, int64_t n, T pivot) {                   \
    int64_t j = 0;                                                             \
    for (int64_t i = 0; i < n; i++) {                                          \
        T x = v[i], y = v[j];                                                  \
        v[i] = y; v[j] = x;                                                    \
        j += (x < pivot);                                                      \
    }                                                                          \
    return j;                                                                  \
}                                                                              \
                                                                               \
static int64_t nsort_part_le_##W(T *v, int64_t n, T pivot) {                   \
    int64_t j = 0;                                                             \
    for (int64_t i = 0; i < n; i++) {                                          \
        T x = v[i], y = v[j];                                                  \
        v[i] = y; v[j] = x;                                                    \
        j += (x <= pivot);                                                     \
    }                                                                          \
    return j;                                                                  \
}                                                                              \
                                                                               \
static void nsort_break_patterns_##W(T *v, int64_t n, uint64_t *seed) {        \
    if (n < 8) return;                                                         \
    int64_t q = n / 4;                                                         \
    nsort_swap_##W(&v[0],     &v[nsort_rng(seed) % (uint64_t)n]);              \
    nsort_swap_##W(&v[q],     &v[nsort_rng(seed) % (uint64_t)n]);              \
    nsort_swap_##W(&v[2 * q], &v[nsort_rng(seed) % (uint64_t)n]);              \
    nsort_swap_##W(&v[n - 1], &v[nsort_rng(seed) % (uint64_t)n]);              \
}                                                                              \
                                                                               \
static void nsort_rec_##W(T *v, int64_t n, const T *ancestor,                  \
                          int limit, uint64_t *seed) {                         \
    for (;;) {                                                                 \
        if (n <= 32) { nsort_small_##W(v, n); return; }                        \
        if (limit == 0) { nsort_heap_##W(v, n); return; }                      \
        limit--;                                                               \
                                                                               \
        int64_t pi = nsort_pivot_##W(v, n);                                    \
        T pivot = v[pi];                                                       \
                                                                               \
        if (ancestor != NULL && !(*ancestor < pivot)) {                        \
            int64_t eq = nsort_part_le_##W(v, n, pivot);                       \
            v += eq; n -= eq; ancestor = NULL;                                 \
            continue;                                                          \
        }                                                                      \
                                                                               \
        nsort_swap_##W(&v[0], &v[pi]);                                         \
        int64_t lt = nsort_part_lt_##W(v + 1, n - 1, pivot);                   \
        nsort_swap_##W(&v[0], &v[lt]);  /* pivot comes to rest at v[lt] */     \
                                                                               \
        int64_t rn = n - 1 - lt;                                               \
        if (lt < n / 8 || rn < n / 8) {                                        \
            nsort_break_patterns_##W(v, lt, seed);                             \
            nsort_break_patterns_##W(v + lt + 1, rn, seed);                    \
        }                                                                      \
                                                                               \
        nsort_rec_##W(v, lt, ancestor, limit, seed);                           \
        ancestor = &v[lt];                                                     \
        v += lt + 1; n -= lt + 1;                                              \
    }                                                                          \
}                                                                              \
                                                                               \
static void nsort_##W(T *v, int64_t n) {                                       \
    if (n < 2) return;                                                         \
    if (n <= 32) { nsort_small_##W(v, n); return; }                            \
                                                                               \
    int64_t i = 1;                                                             \
    if (v[1] < v[0]) {                                                         \
        while (i < n && v[i] < v[i - 1]) i++;                                  \
        if (i == n) {                                                          \
            for (int64_t lo = 0, hi = n - 1; lo < hi; lo++, hi--)              \
                nsort_swap_##W(&v[lo], &v[hi]);                                \
            return;                                                            \
        }                                                                      \
    } else {                                                                   \
        while (i < n && !(v[i] < v[i - 1])) i++;                               \
        if (i == n) return;                                                    \
    }                                                                          \
                                                                               \
    int limit = 0;                                                             \
    for (int64_t m = n; m > 1; m >>= 1) limit += 2;                            \
    int forced = nsort_forced_limit();                                         \
    if (forced >= 0) limit = forced;                                           \
    uint64_t seed = (uint64_t)n * 0x9E3779B97F4A7C15ULL;                       \
    nsort_rec_##W(v, n, NULL, limit, &seed);                                   \
}

NSORT_DEFINE_CORE(i64, int64_t)
NSORT_DEFINE_CORE(i32, int32_t)

/* FBIP/COW contract identical to native_int_arr_set above: [arr] is owned and
 * consumed, so at rc == 1 we sort in place and hand our reference straight
 * back (no allocation, no copy), and at rc > 1 an alias may still observe the
 * original, so we sort a fresh copy and release our own reference. */
void *native_int_arr_sort(void *arr) {
    int64_t len = native_int_arr_length(arr);
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        nsort_i64((int64_t *)((char *)arr + NATIVE_ARR_HDR), len);
        return arr;
    }
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_I64);
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR,
           (size_t)(len * 8));
    nsort_i64((int64_t *)((char *)new_arr + NATIVE_ARR_HDR), len);
    march_decrc(arr);
    return new_arr;
}

/* ── NativeArray.sort_float: the same sort, on IEEE 754 totalOrder keys ────
 *
 * `<` on doubles is not a total order (every comparison with NaN is false),
 * and a quicksort fed an inconsistent comparator can break its own
 * partition invariants. So doubles sort by their totalOrder key:
 *
 *   key(bits) = bits ^ (((int64_t)bits >> 63) & 0x7FFFFFFFFFFFFFFF)
 *
 * compared as a signed i64. Negative doubles get their magnitude bits
 * flipped and keep the sign bit, which yields
 *   -NaN < -Inf < ... < -1 < -0 < +0 < 1 < ... < +Inf < +NaN.
 * Note -0.0 sorts strictly before +0.0, although `compare(-0.0, 0.0)` and
 * `==` treat them as equal.
 *
 * key() leaves the sign bit alone, so it is an involution: applying it twice
 * restores the original bits. That allows "transform in, sort, transform out"
 * with nsort_i64 reused verbatim, which is what this does. The alternative,
 * comparing through key() on every comparison, was measured in
 * bench/c/native_sort_bench.c (`nsb f64`): 10-14% slower on the
 * comparison-bound patterns (random, organ, nearly), 5-14% faster only on
 * the already-O(n) ones (sorted, reversed, equal) where the two extra
 * vectorized passes are the whole cost. Both are bit-identical to qsort
 * with a totalOrder comparator.
 *
 * The interpreter arm (lib/eval/eval_builtins.ml) sorts on the same key; it
 * must not use OCaml's `compare`, which puts every NaN first regardless of
 * sign. */
static inline int64_t nsort_f64_key(int64_t bits) {
    return bits ^ (int64_t)((uint64_t)(bits >> 63) >> 1);
}

static void nsort_f64(double *d, int64_t n) {
    int64_t *v = (int64_t *)d;          /* -fno-strict-aliasing: bit view */
    for (int64_t i = 0; i < n; i++) v[i] = nsort_f64_key(v[i]);
    nsort_i64(v, n);
    for (int64_t i = 0; i < n; i++) v[i] = nsort_f64_key(v[i]);
}
/* native_float_arr_sort itself sits after native_float_arr_set, below, next
 * to the rest of the f64 array entry points. */

/* ── NativeArray.sort_f32: the same decision on 32-bit keys ────────────────
 *
 *   key(bits) = bits ^ (((int32_t)bits >> 31) & 0x7FFFFFFF)
 *
 * compared as a signed i32 is binary32 totalOrder, exactly as the 64-bit key
 * is for binary64, and it is an involution for the same reason. So f32 is
 * transform in / nsort_i32 / transform out. It is deliberately NOT widened to
 * f64: that would double the memory traffic of the sort and need a scratch
 * array, and the i32 core is needed for sort_i32 anyway. (Widening is
 * order-preserving, NaN sign and payload included, so the interpreter arm is
 * free to compute either key; it uses this one.) */
static inline int32_t nsort_f32_key(int32_t bits) {
    return bits ^ (int32_t)((uint32_t)(bits >> 31) >> 1);
}

static void nsort_f32(float *d, int64_t n) {
    int32_t *v = (int32_t *)d;          /* -fno-strict-aliasing: bit view */
    for (int64_t i = 0; i < n; i++) v[i] = nsort_f32_key(v[i]);
    nsort_i32(v, n);
    for (int64_t i = 0; i < n; i++) v[i] = nsort_f32_key(v[i]);
}

/* ── NativeArray.sort_u8: counting sort ─────────────────────────────────────
 *
 * 256 possible values, so a histogram and one fill pass is O(n + 256) with
 * no comparisons, no data-dependent branches and a 2 KiB stack table; no
 * comparison sort can match it at any n that matters. It needs no depth limit
 * and has no heapsort fallback, so MARCH_TEST_NSORT_DEPTH_LIMIT does not
 * apply. [src] and [dst] may be the same buffer (the rc == 1 path): the
 * histogram is complete before the first write. */
static void nsort_u8(const uint8_t *src, uint8_t *dst, int64_t n) {
    int64_t count[256];
    memset(count, 0, sizeof count);
    for (int64_t i = 0; i < n; i++) count[src[i]]++;
    uint8_t *out = dst;
    for (int k = 0; k < 256; k++) {
        if (count[k]) { memset(out, k, (size_t)count[k]); out += count[k]; }
    }
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
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_I64);
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
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_I64);
    for (int64_t i = 0; i < len; i++) {
        int64_t x = *(int64_t *)((char *)arr1 + NATIVE_ARR_HDR + i * 8);
        int64_t y = *(int64_t *)((char *)arr2 + NATIVE_ARR_HDR + i * 8);
        march_incrc(f);
        *(int64_t *)((char *)new_arr + NATIVE_ARR_HDR + i * 8) = clo_call_int_int_int(f, x, y);
    }
    march_decrc(f);
    return new_arr;
}

/* fold: the accumulator is a GENERIC 'a, so it stays in the erased/boxed
 * representation for the whole loop and the caller's codegen owns boxing it
 * in and out.  RC discipline copied verbatim from march_typed_array_fold
 * (above in this file; grep the name rather than trusting a line number)
 * — incrc(f) per element, one decrc(f) after the loop.
 * ARG ORDER IS (acc, arr, f) — matching the March builtin, NOT
 * march_typed_array_fold's (arr, acc, f). */
void *native_int_arr_fold(void *acc, void *arr, void *f) {
    int64_t len = native_int_arr_length(arr);
    void *result = acc;
    for (int64_t i = 0; i < len; i++) {
        int64_t x = *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
        void *elem = (void *)(intptr_t)((x << 1) | 1);   /* wire-tag */
        void *prev = result;
        int prev_is_float = fold_acc_is_float(prev);
        march_incrc(f);
        result = call_closure_2(f, prev, elem);
        fold_release_prev_acc(prev, prev_is_float, result);
    }
    march_decrc(f);
    return result;
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
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_F64);
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
    void *arr = native_arr_alloc(n, 8, NATIVE_ELEM_I64);
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
    void *arr = native_arr_alloc(len, 8, NATIVE_ELEM_F64);
    for (int64_t i = 0; i < len; i++)
        memcpy((char *)arr + NATIVE_ARR_HDR + i * 8, &def, 8);
    return arr;
}

int64_t native_float_arr_length(void *arr) {
    return *(int64_t *)((char *)arr + 16);
}

double native_float_arr_get(void *arr, int64_t i) {
    native_arr_check_bounds("native_float_arr_get", i, native_float_arr_length(arr));
    double v; memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8); return v;
}

/* In-place-at-rc==1 FBIP update — see native_int_arr_set above for the full
 * ownership contract (identical: owned/consumed arg, unique-owner mutates in
 * place, shared array copies-on-write then releases our reference). */
void *native_float_arr_set(void *arr, int64_t i, double val) {
    native_arr_check_bounds("native_float_arr_set", i, native_float_arr_length(arr));
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        memcpy((char *)arr + NATIVE_ARR_HDR + i * 8, &val, 8);
        return arr;
    }
    int64_t len = native_float_arr_length(arr);
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_F64);
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR, (size_t)(len * 8));
    memcpy((char *)new_arr + NATIVE_ARR_HDR + i * 8, &val, 8);
    march_decrc(arr);
    return new_arr;
}

/* NativeArray.sort_float — totalOrder ipnsort; see nsort_f64 above. FBIP/COW
 * contract identical to native_int_arr_sort: [arr] is owned and consumed, in
 * place at rc == 1, a sorted fresh copy (our reference released) at rc > 1. */
void *native_float_arr_sort(void *arr) {
    int64_t len = native_float_arr_length(arr);
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        nsort_f64((double *)((char *)arr + NATIVE_ARR_HDR), len);
        return arr;
    }
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_F64);
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR,
           (size_t)(len * 8));
    nsort_f64((double *)((char *)new_arr + NATIVE_ARR_HDR), len);
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
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_F64);
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
    void *new_arr = native_arr_alloc(len, 8, NATIVE_ELEM_F64);
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

/* fold: element is a raw double, materialised via march_alloc_float (boxed) —
 * unlike native_int_arr_fold's wire-tagged scalar. Same RC discipline and
 * (acc, arr, f) argument order as native_int_arr_fold above.
 *
 * march_decrc(elem) after the call releases the FRESH per-element box we
 * just allocated. Confirmed safe (not a use-after-free) by inspecting
 * -emit-llvm for the compiled closure's apply fn: the erased-ptr calling
 * convention treats a Float argument as borrowed/read-only — the callee
 * only ever calls march_unbox_float(x.arg) to read the double value, never
 * stores x.arg itself. Even a closure that stores the element (e.g. cons it
 * into a List(Float)) allocates a FRESH march_alloc_float box from the
 * unboxed double for storage rather than aliasing our box — so our box has
 * no surviving alias once the call returns and is always safe to drop.
 * Without this decrc, elem leaks: ~32B/element, unbounded in loop length
 * (confirmed via RSS measurement — see task-2-report.md). This decrc is
 * pinned by test/native/native_arr_fold_leak_probe.march; deleting it takes
 * that fixture's peak RSS from 48 MB to 171 MB.
 *
 * The ACCUMULATOR half — each iteration's march_alloc_float result becoming
 * the next accumulator with nobody releasing the previous one — was the
 * second ~32 B/element leak in this loop. Fixed 2026-08-20 by the
 * fold_release_prev_acc call below; see that helper for why the release is
 * MARCH_FLOAT_TAG-guarded rather than unconditional. Pinned by
 * test/native/native_arr_fold_acc_leak_probe.march. */
void *native_float_arr_fold(void *acc, void *arr, void *f) {
    int64_t len = native_float_arr_length(arr);
    void *result = acc;
    for (int64_t i = 0; i < len; i++) {
        double x;
        memcpy(&x, (char *)arr + NATIVE_ARR_HDR + i * 8, 8);
        void *elem = march_alloc_float(x);
        void *prev = result;
        int prev_is_float = fold_acc_is_float(prev);
        march_incrc(f);
        result = call_closure_2(f, prev, elem);
        march_decrc(elem);
        fold_release_prev_acc(prev, prev_is_float, result);
    }
    march_decrc(f);
    return result;
}

void *native_float_arr_from_list(void *lst) {
    int64_t n = 0;
    void *tmp = lst;
    while (*(int32_t *)((char *)tmp + 8) == 1) { n++; tmp = *(void **)((char *)tmp + 24); }
    void *arr = native_arr_alloc(n, 8, NATIVE_ELEM_F64);
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

/* ── Narrow element widths: f32 / i32 / u8 ─────────────────────────────
 * March-side scalars stay int64_t/double; stores narrow by C cast
 * (two's-complement wrap for ints, round-to-nearest-even for f32) and
 * loads widen exactly (uint8_t zero-extends, int32_t sign-extends).
 * Layout/RC/FBIP contracts identical to the i64/f64 families above. */

#define DEF_NARROW_INT_ARR(PREFIX, CTYPE, KIND)                               \
void *PREFIX##_alloc_raw(int64_t len) {                                       \
    return native_arr_alloc(len, (int64_t)sizeof(CTYPE), KIND);               \
}                                                                             \
void *PREFIX##_make(int64_t len, int64_t def) {                               \
    void *arr = native_arr_alloc(len, (int64_t)sizeof(CTYPE), KIND);          \
    CTYPE d = (CTYPE)def;                                                     \
    for (int64_t i = 0; i < len; i++)                                         \
        *(CTYPE *)((char *)arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)) = d;     \
    return arr;                                                               \
}                                                                             \
int64_t PREFIX##_length(void *arr) { return *(int64_t *)((char *)arr + 16); } \
int64_t PREFIX##_get(void *arr, int64_t i) {                                  \
    native_arr_check_bounds(#PREFIX "_get", i, PREFIX##_length(arr));         \
    return (int64_t)*(CTYPE *)((char *)arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)); \
}                                                                             \
void *PREFIX##_set(void *arr, int64_t i, int64_t val) {                       \
    native_arr_check_bounds(#PREFIX "_set", i, PREFIX##_length(arr));         \
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {                    \
        *(CTYPE *)((char *)arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)) = (CTYPE)val; \
        return arr;                                                           \
    }                                                                         \
    int64_t len = PREFIX##_length(arr);                                       \
    void *new_arr = native_arr_alloc(len, (int64_t)sizeof(CTYPE), KIND);      \
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR,    \
           (size_t)(len * (int64_t)sizeof(CTYPE)));                           \
    *(CTYPE *)((char *)new_arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)) = (CTYPE)val; \
    march_decrc(arr);                                                         \
    return new_arr;                                                           \
}                                                                             \
int64_t PREFIX##_sum(void *arr) {                                             \
    int64_t len = PREFIX##_length(arr), s = 0;                                \
    for (int64_t i = 0; i < len; i++)                                         \
        s += (int64_t)*(CTYPE *)((char *)arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)); \
    return s;                                                                 \
}                                                                             \
/* RC contract identical to native_int_arr_map above. */                      \
void *PREFIX##_map(void *arr, void *f) {                                      \
    int64_t len = PREFIX##_length(arr);                                       \
    void *new_arr = native_arr_alloc(len, (int64_t)sizeof(CTYPE), KIND);      \
    for (int64_t i = 0; i < len; i++) {                                       \
        int64_t x = (int64_t)*(CTYPE *)((char *)arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)); \
        march_incrc(f);                                                       \
        *(CTYPE *)((char *)new_arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)) =    \
            (CTYPE)clo_call_int_int(f, x);                                    \
    }                                                                         \
    march_decrc(f);                                                           \
    return new_arr;                                                           \
}                                                                             \
void *PREFIX##_map2(void *arr1, void *arr2, void *f) {                        \
    int64_t len = PREFIX##_length(arr1);                                      \
    if (len != PREFIX##_length(arr2)) {                                       \
        fputs("march: " #PREFIX "_map2: array length mismatch\n", stderr); exit(1); \
    }                                                                         \
    void *new_arr = native_arr_alloc(len, (int64_t)sizeof(CTYPE), KIND);      \
    for (int64_t i = 0; i < len; i++) {                                       \
        int64_t x = (int64_t)*(CTYPE *)((char *)arr1 + NATIVE_ARR_HDR + i * sizeof(CTYPE)); \
        int64_t y = (int64_t)*(CTYPE *)((char *)arr2 + NATIVE_ARR_HDR + i * sizeof(CTYPE)); \
        march_incrc(f);                                                       \
        *(CTYPE *)((char *)new_arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)) =    \
            (CTYPE)clo_call_int_int_int(f, x, y);                             \
    }                                                                         \
    march_decrc(f);                                                           \
    return new_arr;                                                           \
}                                                                             \
/* fold: (int64_t)*(CTYPE *)... already sign-extends int32_t and             \
 * zero-extends uint8_t exactly like PREFIX##_get above, so one shared       \
 * fold body is correct for both instantiations without a per-width         \
 * materialisation branch. Same RC discipline and (acc, arr, f) argument     \
 * order as native_int_arr_fold above. */                                    \
void *PREFIX##_fold(void *acc, void *arr, void *f) {                         \
    int64_t len = PREFIX##_length(arr);                                      \
    void *result = acc;                                                      \
    for (int64_t i = 0; i < len; i++) {                                      \
        int64_t x = (int64_t)*(CTYPE *)((char *)arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)); \
        void *elem = (void *)(intptr_t)((x << 1) | 1);                       \
        void *prev = result;                                                 \
        int prev_is_float = fold_acc_is_float(prev);                         \
        march_incrc(f);                                                      \
        result = call_closure_2(f, prev, elem);                              \
        fold_release_prev_acc(prev, prev_is_float, result);             \
    }                                                                        \
    march_decrc(f);                                                          \
    return result;                                                           \
}                                                                             \
void *PREFIX##_from_list(void *lst) {                                         \
    int64_t n = 0;                                                            \
    void *tmp = lst;                                                          \
    while (*(int32_t *)((char *)tmp + 8) == 1) { n++; tmp = *(void **)((char *)tmp + 24); } \
    void *arr = native_arr_alloc(n, (int64_t)sizeof(CTYPE), KIND);            \
    void *cur = lst;                                                          \
    for (int64_t i = 0; i < n; i++) {                                         \
        int64_t raw = *(int64_t *)((char *)cur + 16);                         \
        int64_t v = (raw & 1) ? (raw >> 1) : raw;                             \
        *(CTYPE *)((char *)arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)) = (CTYPE)v; \
        cur = *(void **)((char *)cur + 24);                                   \
    }                                                                         \
    return arr;                                                               \
}                                                                             \
void *PREFIX##_to_list(void *arr) {                                           \
    int64_t len = PREFIX##_length(arr);                                       \
    void *lst = make_nil();                                                   \
    for (int64_t i = len - 1; i >= 0; i--) {                                  \
        int64_t v = (int64_t)*(CTYPE *)((char *)arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)); \
        void *cons = march_alloc(32);                                         \
        *(int32_t *)((char *)cons + 8) = 1;                                   \
        *(int64_t *)((char *)cons + 16) = (v << 1) | 1;                       \
        *(void **)((char *)cons + 24) = lst;                                  \
        lst = cons;                                                           \
    }                                                                         \
    return lst;                                                               \
}

DEF_NARROW_INT_ARR(native_i32_arr, int32_t, NATIVE_ELEM_I32)
DEF_NARROW_INT_ARR(native_u8_arr,  uint8_t, NATIVE_ELEM_U8)

/* NativeArray.sort_i32 — the ipnsort core instantiated at int32_t
 * (nsort_i32). FBIP/COW contract identical to native_int_arr_sort: [arr] is
 * owned and consumed, sorted in place at rc == 1, a sorted fresh copy (our
 * reference released) at rc > 1. */
void *native_i32_arr_sort(void *arr) {
    int64_t len = native_i32_arr_length(arr);
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        nsort_i32((int32_t *)((char *)arr + NATIVE_ARR_HDR), len);
        return arr;
    }
    void *new_arr = native_arr_alloc(len, 4, NATIVE_ELEM_I32);
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR,
           (size_t)(len * 4));
    nsort_i32((int32_t *)((char *)new_arr + NATIVE_ARR_HDR), len);
    march_decrc(arr);
    return new_arr;
}

/* NativeArray.sort_u8 — counting sort (nsort_u8). Same ownership contract.
 * The rc > 1 path counts straight from the shared original into the fresh
 * array, so it needs no memcpy first. */
void *native_u8_arr_sort(void *arr) {
    int64_t len = native_u8_arr_length(arr);
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        uint8_t *d = (uint8_t *)((char *)arr + NATIVE_ARR_HDR);
        nsort_u8(d, d, len);
        return arr;
    }
    void *new_arr = native_arr_alloc(len, 1, NATIVE_ELEM_U8);
    nsort_u8((const uint8_t *)((char *)arr + NATIVE_ARR_HDR),
             (uint8_t *)((char *)new_arr + NATIVE_ARR_HDR), len);
    march_decrc(arr);
    return new_arr;
}

void *native_f32_arr_alloc_raw(int64_t len) {
    return native_arr_alloc(len, 4, NATIVE_ELEM_F32);
}

void *native_f32_arr_make(int64_t len, double def) {
    void *arr = native_arr_alloc(len, 4, NATIVE_ELEM_F32);
    float d = (float)def;    /* round to nearest-even binary32 */
    for (int64_t i = 0; i < len; i++)
        *(float *)((char *)arr + NATIVE_ARR_HDR + i * 4) = d;
    return arr;
}

int64_t native_f32_arr_length(void *arr) { return *(int64_t *)((char *)arr + 16); }

double native_f32_arr_get(void *arr, int64_t i) {
    native_arr_check_bounds("native_f32_arr_get", i, native_f32_arr_length(arr));
    return (double)*(float *)((char *)arr + NATIVE_ARR_HDR + i * 4);
}

/* FBIP/COW contract identical to native_float_arr_set above. */
void *native_f32_arr_set(void *arr, int64_t i, double val) {
    native_arr_check_bounds("native_f32_arr_set", i, native_f32_arr_length(arr));
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        *(float *)((char *)arr + NATIVE_ARR_HDR + i * 4) = (float)val;
        return arr;
    }
    int64_t len = native_f32_arr_length(arr);
    void *new_arr = native_arr_alloc(len, 4, NATIVE_ELEM_F32);
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR, (size_t)(len * 4));
    *(float *)((char *)new_arr + NATIVE_ARR_HDR + i * 4) = (float)val;
    march_decrc(arr);
    return new_arr;
}

/* NativeArray.sort_f32 — binary32 totalOrder ipnsort; see nsort_f32 above.
 * FBIP/COW contract identical to native_float_arr_sort. */
void *native_f32_arr_sort(void *arr) {
    int64_t len = native_f32_arr_length(arr);
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        nsort_f32((float *)((char *)arr + NATIVE_ARR_HDR), len);
        return arr;
    }
    void *new_arr = native_arr_alloc(len, 4, NATIVE_ELEM_F32);
    memcpy((char *)new_arr + NATIVE_ARR_HDR, (char *)arr + NATIVE_ARR_HDR,
           (size_t)(len * 4));
    nsort_f32((float *)((char *)new_arr + NATIVE_ARR_HDR), len);
    march_decrc(arr);
    return new_arr;
}

double native_f32_arr_sum(void *arr) {
    int64_t len = native_f32_arr_length(arr);
    double s = 0.0;
    /* Same scoped reassociation as native_float_arr_sum — see its comment. */
    {
#pragma clang fp reassociate(on)
        for (int64_t i = 0; i < len; i++)
            s += (double)*(float *)((char *)arr + NATIVE_ARR_HDR + i * 4);
    }
    return s;
}

/* RC contract identical to native_int_arr_map above. */
void *native_f32_arr_map(void *arr, void *f) {
    int64_t len = native_f32_arr_length(arr);
    void *new_arr = native_arr_alloc(len, 4, NATIVE_ELEM_F32);
    for (int64_t i = 0; i < len; i++) {
        double x = (double)*(float *)((char *)arr + NATIVE_ARR_HDR + i * 4);
        march_incrc(f);
        *(float *)((char *)new_arr + NATIVE_ARR_HDR + i * 4) = (float)clo_call_dbl_dbl(f, x);
    }
    march_decrc(f);
    return new_arr;
}

void *native_f32_arr_map2(void *arr1, void *arr2, void *f) {
    int64_t len = native_f32_arr_length(arr1);
    if (len != native_f32_arr_length(arr2)) {
        fputs("march: native_f32_arr_map2: array length mismatch\n", stderr); exit(1);
    }
    void *new_arr = native_arr_alloc(len, 4, NATIVE_ELEM_F32);
    for (int64_t i = 0; i < len; i++) {
        double x = (double)*(float *)((char *)arr1 + NATIVE_ARR_HDR + i * 4);
        double y = (double)*(float *)((char *)arr2 + NATIVE_ARR_HDR + i * 4);
        march_incrc(f);
        *(float *)((char *)new_arr + NATIVE_ARR_HDR + i * 4) = (float)clo_call_dbl_dbl_dbl(f, x, y);
    }
    march_decrc(f);
    return new_arr;
}

/* fold: element is a stored float, widened to double and materialised via
 * march_alloc_float (the wire ABI has no native f32 box — see the ABI
 * comment above clo_apply_ptr). Same RC discipline and (acc, arr, f)
 * argument order as native_int_arr_fold above. march_decrc(elem) after the
 * call releases our per-element box — see native_float_arr_fold's comment
 * above for why this is confirmed safe (borrowed-argument convention, no
 * alias survives the call) rather than a use-after-free. Pinned by
 * test/native/native_arr_fold_leak_probe.march's f32 leg. The accumulator
 * chain is released by fold_release_prev_acc, exactly as in
 * native_float_arr_fold above (fixed 2026-08-20). */
void *native_f32_arr_fold(void *acc, void *arr, void *f) {
    int64_t len = native_f32_arr_length(arr);
    void *result = acc;
    for (int64_t i = 0; i < len; i++) {
        double x = (double)*(float *)((char *)arr + NATIVE_ARR_HDR + i * 4);
        void *elem = march_alloc_float(x);
        void *prev = result;
        int prev_is_float = fold_acc_is_float(prev);
        march_incrc(f);
        result = call_closure_2(f, prev, elem);
        march_decrc(elem);
        fold_release_prev_acc(prev, prev_is_float, result);
    }
    march_decrc(f);
    return result;
}

void *native_f32_arr_from_list(void *lst) {
    int64_t n = 0;
    void *tmp = lst;
    while (*(int32_t *)((char *)tmp + 8) == 1) { n++; tmp = *(void **)((char *)tmp + 24); }
    void *arr = native_arr_alloc(n, 4, NATIVE_ELEM_F32);
    void *cur = lst;
    for (int64_t i = 0; i < n; i++) {
        /* List(Float) elements are BOXED — see native_float_arr_from_list. */
        void *boxed = *(void **)((char *)cur + 16);
        *(float *)((char *)arr + NATIVE_ARR_HDR + i * 4) = (float)march_unbox_float(boxed);
        cur = *(void **)((char *)cur + 24);
    }
    return arr;
}

void *native_f32_arr_to_list(void *arr) {
    int64_t len = native_f32_arr_length(arr);
    void *lst = make_nil();
    for (int64_t i = len - 1; i >= 0; i--) {
        /* Box each element — see native_float_arr_to_list's comment. */
        double v = (double)*(float *)((char *)arr + NATIVE_ARR_HDR + i * 4);
        void *boxed = march_alloc_float(v);
        void *cons = march_alloc(32);
        *(int32_t *)((char *)cons + 8) = 1;
        *(void **)((char *)cons + 16) = boxed;
        *(void **)((char *)cons + 24) = lst;
        lst = cons;
    }
    return lst;
}

/* ── Width conversions ── wrap/round per the narrow-store rule; never trap. */
void *native_float_to_f32_arr(void *arr) {
    int64_t len = native_float_arr_length(arr);
    void *out = native_arr_alloc(len, 4, NATIVE_ELEM_F32);
    for (int64_t i = 0; i < len; i++) {
        double v; memcpy(&v, (char *)arr + NATIVE_ARR_HDR + i * 8, 8);
        *(float *)((char *)out + NATIVE_ARR_HDR + i * 4) = (float)v;
    }
    return out;
}
void *native_f32_to_float_arr(void *arr) {
    int64_t len = native_f32_arr_length(arr);
    void *out = native_arr_alloc(len, 8, NATIVE_ELEM_F64);
    for (int64_t i = 0; i < len; i++) {
        double v = (double)*(float *)((char *)arr + NATIVE_ARR_HDR + i * 4);
        memcpy((char *)out + NATIVE_ARR_HDR + i * 8, &v, 8);
    }
    return out;
}
void *native_int_to_i32_arr(void *arr) {
    int64_t len = native_int_arr_length(arr);
    void *out = native_arr_alloc(len, 4, NATIVE_ELEM_I32);
    for (int64_t i = 0; i < len; i++)
        *(int32_t *)((char *)out + NATIVE_ARR_HDR + i * 4) =
            (int32_t)*(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
    return out;
}
void *native_i32_to_int_arr(void *arr) {
    int64_t len = native_i32_arr_length(arr);
    void *out = native_arr_alloc(len, 8, NATIVE_ELEM_I64);
    for (int64_t i = 0; i < len; i++)
        *(int64_t *)((char *)out + NATIVE_ARR_HDR + i * 8) =
            (int64_t)*(int32_t *)((char *)arr + NATIVE_ARR_HDR + i * 4);
    return out;
}
void *native_int_to_u8_arr(void *arr) {
    int64_t len = native_int_arr_length(arr);
    void *out = native_arr_alloc(len, 1, NATIVE_ELEM_U8);
    for (int64_t i = 0; i < len; i++)
        *(uint8_t *)((char *)out + NATIVE_ARR_HDR + i) =
            (uint8_t)*(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
    return out;
}
void *native_u8_to_int_arr(void *arr) {
    int64_t len = native_u8_arr_length(arr);
    void *out = native_arr_alloc(len, 8, NATIVE_ELEM_I64);
    for (int64_t i = 0; i < len; i++)
        *(int64_t *)((char *)out + NATIVE_ARR_HDR + i * 8) =
            (int64_t)*(uint8_t *)((char *)arr + NATIVE_ARR_HDR + i);
    return out;
}
void *native_i32_to_f32_arr(void *arr) {
    int64_t len = native_i32_arr_length(arr);
    void *out = native_arr_alloc(len, 4, NATIVE_ELEM_F32);
    for (int64_t i = 0; i < len; i++)
        *(float *)((char *)out + NATIVE_ARR_HDR + i * 4) =
            (float)*(int32_t *)((char *)arr + NATIVE_ARR_HDR + i * 4);
    return out;
}
void *native_u8_to_f32_arr(void *arr) {
    int64_t len = native_u8_arr_length(arr);
    void *out = native_arr_alloc(len, 4, NATIVE_ELEM_F32);
    for (int64_t i = 0; i < len; i++)
        *(float *)((char *)out + NATIVE_ARR_HDR + i * 4) =
            (float)*(uint8_t *)((char *)arr + NATIVE_ARR_HDR + i);
    return out;
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
    void *out = native_arr_alloc(count, 8, NATIVE_ELEM_I64);
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
    void *out = native_arr_alloc(count, 8, NATIVE_ELEM_F64);
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
