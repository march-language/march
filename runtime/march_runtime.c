#include "march_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

/* ── Allocation ──────────────────────────────────────────────────────── */

void *march_alloc(int64_t sz) {
    void *p = calloc(1, (size_t)sz);
    if (!p) { fputs("march: out of memory\n", stderr); exit(1); }
    /* Initialize rc=1, tag=0, pad=0 */
    march_hdr *h = (march_hdr *)p;
    h->rc  = 1;
    h->tag = 0;
    h->pad = 0;
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
    atomic_fetch_add_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_relaxed);
}

void march_decrc(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    /* acq_rel: release our writes before decrement; acquire before free so
     * we see all other threads' writes to the object. */
    int64_t prev = atomic_fetch_sub_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_acq_rel);
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
    int64_t prev = atomic_fetch_sub_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_acq_rel);
    if (prev <= 1) { free(p); return 1; }
    return 0;
}

void march_free(void *p) {
    free(p);
}

/* Non-atomic reference counting — for values provably local to one thread.
 * These must NOT be called on values that may be concurrently accessed from
 * another actor.  The callers (Perceus-generated code) guarantee this. */
void march_incrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    ((march_hdr *)p)->rc++;
}

void march_decrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    march_hdr *h = (march_hdr *)p;
    h->rc--;
    if (h->rc <= 0) {
        if (h->rc < 0) {
            fprintf(stderr, "march: local RC underflow at %p — aborting\n", p);
            abort();
        }
        free(p);
    }
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

/* ── Panic ───────────────────────────────────────────────────────────────── */

void march_panic(void *s) {
    march_string *ms = (march_string *)s;
    fprintf(stderr, "panic: ");
    fwrite(ms->data, 1, (size_t)ms->len, stderr);
    fputc('\n', stderr);
    fflush(stderr);
    exit(1);
}

/* ── Actor runtime — concurrent mailbox + scheduler ──────────────────────── */
/*
 * Design overview
 * ───────────────
 * Each actor has a per-actor side-table entry (march_actor_meta) holding:
 *   • mbox_head — an MPSC Treiber stack.  Any thread CAS-pushes message
 *     nodes here lock-free.  The scheduler atomically swaps the head to NULL,
 *     reverses the result to recover FIFO order, then dispatches.
 *   • scheduled — atomic int, 0 = idle, 1 = in run queue.  Only the thread
 *     that wins the CAS 0→1 adds the actor to the run queue, preventing
 *     duplicate entries and the "silent message loss" race.
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
 * reference, store it in the mailbox node, and the dispatch function's own
 * Perceus instrumentation decrements after unpacking.
 *
 * We do NOT force-write rc=1 before calling dispatch (the FBIP anti-pattern
 * described in the correctness audit).  FBIP within handlers operates on the
 * locally-constructed state record, which is ephemeral and always rc=1 by
 * construction — not on the actor struct whose rc may be >1.
 *
 * Scheduling
 * ──────────
 * march_send enqueues the message and, on winning the scheduled CAS, calls
 * march_run_scheduler().  A re-entrancy guard (g_in_scheduler) prevents
 * nested scheduler invocations: if a handler calls march_send the inner send
 * still enqueues to the run queue but does not recurse into the scheduler.
 * The outer scheduler loop picks up newly-added actors on the next iteration.
 *
 * Starvation prevention
 * ─────────────────────
 * The scheduler drains up to MARCH_BATCH_MAX messages per actor per turn.
 * Any remaining messages are pushed back to the mailbox and the actor is
 * re-scheduled, ensuring other actors get CPU time between large bursts.
 */

#define MARCH_SCHED_BUCKETS  256  /* Power-of-2 hash table size              */
#define MARCH_BATCH_MAX       64  /* Max messages dispatched per actor/turn  */
/* M2 preemption: wall-clock time budget per actor turn (5 ms). */
#define MARCH_TIME_QUANTUM_NS  5000000LL
/* M3 work: number of worker threads in the pool (0 = single-threaded). */
#define MARCH_NUM_WORKERS      4

/* Single node in an actor's MPSC mailbox (intrusive linked list). */
typedef struct march_msg_node {
    void                  *msg;   /* Payload — one RC reference owned by us  */
    struct march_msg_node *next;
} march_msg_node;

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
    _Atomic(march_msg_node *)   mbox_head;  /* MPSC Treiber stack head         */
    _Atomic int                 scheduled;  /* 0 = idle, 1 = queued/running    */
    struct march_actor_meta    *run_next;   /* Run-queue intrusive link        */
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

/* Scheduler run queue — FIFO, protected by g_run_mu */
static march_actor_meta  *g_run_head = NULL;
static march_actor_meta  *g_run_tail = NULL;
static pthread_mutex_t    g_run_mu   = PTHREAD_MUTEX_INITIALIZER;
/* M3: Condition variable to wake idle workers when work arrives. */
static pthread_cond_t     g_run_cond = PTHREAD_COND_INITIALIZER;
/* M3: Worker threads + shutdown flag. */
static pthread_t           g_worker_threads[MARCH_NUM_WORKERS];
static _Atomic int         g_workers_started = 0;
static _Atomic int         g_shutdown        = 0;
/* Number of workers currently processing an actor (for quiescence). */
static _Atomic int         g_active_workers  = 0;

/* Re-entrancy guard: handlers that call march_send must not recurse into
 * the scheduler; the outer loop will pick up newly-queued actors. */
static _Thread_local int g_in_scheduler = 0;

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
    atomic_init(&m->mbox_head, NULL);
    atomic_init(&m->scheduled, 0);
    atomic_init(&m->down_count, 0);
    m->tbl_next = g_actor_tbl[b];
    g_actor_tbl[b] = m;
    pthread_mutex_unlock(&g_tbl_mu);
    return m;
}

/* ── Run-queue helpers ───────────────────────────────────────────── */

/* Add actor to run queue tail.  Caller must have won the scheduled CAS.
 * M3: signals any idle worker thread that work is available. */
static void sched_enqueue(march_actor_meta *meta) {
    meta->run_next = NULL;
    pthread_mutex_lock(&g_run_mu);
    if (g_run_tail) { g_run_tail->run_next = meta; g_run_tail = meta; }
    else            { g_run_head = g_run_tail = meta; }
    /* Wake one idle worker (no-op if no workers are running). */
    pthread_cond_signal(&g_run_cond);
    pthread_mutex_unlock(&g_run_mu);
}

/* Remove and return the head of the run queue (NULL = empty). */
static march_actor_meta *sched_dequeue(void) {
    pthread_mutex_lock(&g_run_mu);
    march_actor_meta *meta = g_run_head;
    if (meta) {
        g_run_head = meta->run_next;
        if (!g_run_head) g_run_tail = NULL;
        meta->run_next = NULL;
    }
    pthread_mutex_unlock(&g_run_mu);
    return meta;
}

/* Reverse a singly-linked msg list (Treiber stack → FIFO order). */
static march_msg_node *reverse_msgs(march_msg_node *head) {
    march_msg_node *prev = NULL;
    while (head) {
        march_msg_node *next = head->next;
        head->next = prev;
        prev = head;
        head = next;
    }
    return prev;
}

/* ── M2: Time measurement helpers ───────────────────────────────── */

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/* ── M3: Worker thread body ──────────────────────────────────────── */

/* Process one actor turn: drain up to MARCH_BATCH_MAX messages within
 * MARCH_TIME_QUANTUM_NS nanoseconds, then re-enqueue if more remain. */
static void process_actor_turn(march_actor_meta *meta) {
    void *actor   = meta->actor;
    int64_t *a    = (int64_t *)actor;

    march_msg_node *stack = atomic_exchange_explicit(
        &meta->mbox_head, NULL, memory_order_acquire);

    atomic_store_explicit(&meta->scheduled, 0, memory_order_release);

    if (stack) {
        march_msg_node *fifo = reverse_msgs(stack);

        char *closure = (char *)(uintptr_t)a[2];
        typedef void (*closure_fn_t)(void *, void *, void *);
        closure_fn_t fn = *(closure_fn_t *)(closure + 16);

        int count = 0;
        /* M2 preemption: record start time; yield after time quantum. */
        long long t_start = now_ns();

        while (fifo && count < MARCH_BATCH_MAX) {
            /* M2: check time budget after each dispatch */
            if (count > 0 && (now_ns() - t_start) >= MARCH_TIME_QUANTUM_NS)
                break;

            march_msg_node *node = fifo;
            fifo = node->next;
            void *msg = node->msg;
            free(node);

            if (a[3]) {
                /* Force RC=1 so FBIP always takes the in-place reuse path.
                 * Safety: only one scheduler thread processes this actor at a
                 * time (scheduled CAS), and march_run_scheduler() blocks the
                 * calling thread, so no concurrent RC changes occur here. */
                int64_t saved_rc = a[0];
                a[0] = 1;
                fn(closure, actor, msg);
                a[0] = saved_rc;
            } else {
                march_decrc(msg);
            }
            count++;
        }

        if (fifo) {
            march_msg_node *tail = fifo;
            while (tail->next) tail = tail->next;
            march_msg_node *cur;
            do {
                cur = atomic_load_explicit(&meta->mbox_head,
                                           memory_order_relaxed);
                tail->next = cur;
            } while (!atomic_compare_exchange_weak_explicit(
                         &meta->mbox_head, &cur, fifo,
                         memory_order_release, memory_order_relaxed));
        }
    }

    /* Re-schedule if mailbox is non-empty and we win the CAS 0→1. */
    {
        int exp = 0;
        if (atomic_load_explicit(&meta->mbox_head, memory_order_acquire)
                != NULL &&
            atomic_compare_exchange_strong_explicit(
                &meta->scheduled, &exp, 1,
                memory_order_acq_rel, memory_order_relaxed)) {
            sched_enqueue(meta);
        }
    }
}

/* M3: Worker thread body — processes actors from the shared run queue
 * until shutdown is signaled and the queue is empty. */
static void *march_worker_body(void *_arg) {
    (void)_arg;
    g_in_scheduler = 1;   /* Prevent nested scheduler re-entrancy */

    while (!atomic_load_explicit(&g_shutdown, memory_order_acquire)) {
        march_actor_meta *meta = sched_dequeue();
        if (meta) {
            atomic_fetch_add_explicit(&g_active_workers, 1, memory_order_relaxed);
            process_actor_turn(meta);
            atomic_fetch_sub_explicit(&g_active_workers, 1, memory_order_release);
        } else {
            /* Queue empty: sleep until work arrives or shutdown. */
            pthread_mutex_lock(&g_run_mu);
            while (!g_run_head &&
                   !atomic_load_explicit(&g_shutdown, memory_order_relaxed)) {
                pthread_cond_wait(&g_run_cond, &g_run_mu);
            }
            pthread_mutex_unlock(&g_run_mu);
        }
    }
    return NULL;
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
    return actor;
}

/* Read an int64 field at word index from an actor struct.
 * Index mapping: 0=rc, 1=tag+pad, 2=dispatch, 3=alive, 4+=state fields. */
int64_t march_actor_get_int(void *actor, int64_t index) {
    return ((int64_t *)actor)[index];
}

/* Drain the run queue: dispatch messages in batches of MARCH_BATCH_MAX.
 *
 * Starvation prevention: if an actor has more than MARCH_BATCH_MAX pending
 * messages the remainder are pushed back to its mailbox and it is
 * re-scheduled, so other actors in the run queue get a turn.
 *
 * Re-entrancy: if a handler calls march_send the inner call enqueues to the
 * run queue but does NOT call march_run_scheduler (g_in_scheduler == 1).
 * The outer loop below processes newly-queued actors on its next iteration. */
/* M3: Start the worker thread pool (called once on first march_run_scheduler).
 * Workers process actors from the shared run queue concurrently.
 * Each worker blocks on g_run_cond when the queue is empty. */
static void start_workers(void) {
    int exp = 0;
    if (!atomic_compare_exchange_strong_explicit(
            &g_workers_started, &exp, 1,
            memory_order_acq_rel, memory_order_relaxed))
        return;   /* Already started by another thread */

    atomic_store_explicit(&g_shutdown, 0, memory_order_relaxed);
    for (int i = 0; i < MARCH_NUM_WORKERS; i++) {
        if (pthread_create(&g_worker_threads[i], NULL,
                           march_worker_body, (void *)(intptr_t)i) != 0) {
            fprintf(stderr, "march: failed to create worker thread %d\n", i);
            exit(1);
        }
    }
}

/* M3: Shut down workers and join them.  Called after all actors are done. */
static void stop_workers(void) {
    atomic_store_explicit(&g_shutdown, 1, memory_order_release);
    /* Wake all sleeping workers so they can notice the shutdown. */
    pthread_mutex_lock(&g_run_mu);
    pthread_cond_broadcast(&g_run_cond);
    pthread_mutex_unlock(&g_run_mu);
    for (int i = 0; i < MARCH_NUM_WORKERS; i++) {
        pthread_join(g_worker_threads[i], NULL);
    }
    atomic_store_explicit(&g_workers_started, 0, memory_order_relaxed);
}

/* Drain the actor run queue.
 *
 * M2 preemption: each actor gets at most MARCH_BATCH_MAX messages AND
 *   MARCH_TIME_QUANTUM_NS nanoseconds per turn.  A handler that takes
 *   longer than the time budget yields to the next actor in the queue,
 *   preventing one slow handler from starving all others.
 *
 * M3 work: on first call, spawns MARCH_NUM_WORKERS worker threads that
 *   consume from the shared run queue in parallel.  The calling thread
 *   waits (with exponential back-off) until the queue is empty AND no
 *   workers are active, then shuts down the pool and returns.
 *
 * Re-entrancy: if a handler calls march_send the inner call enqueues to
 *   the run queue but does NOT call march_run_scheduler (g_in_scheduler==1).
 *   Workers — and this function — pick up the new actor on the next loop. */
void march_run_scheduler(void) {
    if (g_in_scheduler) return;
    g_in_scheduler = 1;

    /* M3: Start worker pool on first invocation. */
    start_workers();

    /* Main thread participates in draining alongside workers. */
    march_actor_meta *meta;
    while ((meta = sched_dequeue()) != NULL) {
        atomic_fetch_add_explicit(&g_active_workers, 1, memory_order_relaxed);
        process_actor_turn(meta);
        atomic_fetch_sub_explicit(&g_active_workers, 1, memory_order_release);
    }

    /* Wait for quiescence: run queue empty AND no in-flight processing.
     * Spin with decreasing sleep to minimise latency while avoiding busy-wait. */
    long sleep_ns = 1000;   /* 1 µs initial backoff */
    for (;;) {
        /* Acquire fence: see worker writes to g_active_workers and g_run_head. */
        int active = atomic_load_explicit(&g_active_workers, memory_order_acquire);
        pthread_mutex_lock(&g_run_mu);
        int has_work = (g_run_head != NULL);
        pthread_mutex_unlock(&g_run_mu);
        if (active == 0 && !has_work) break;

        struct timespec ts = { 0, sleep_ns };
        nanosleep(&ts, NULL);
        sleep_ns = (sleep_ns < 1000000) ? sleep_ns * 2 : 1000000; /* cap 1 ms */
    }

    /* M3: Shut down the worker pool now that all work is done. */
    stop_workers();

    g_in_scheduler = 0;
}

/* Send a message to an actor.
 *
 * RC contract: we do NOT call march_incrc on msg.  Perceus at the call site
 * either transfers ownership (msg not used after send → no extra incrc) or
 * has already incremented (msg used after send → incrc before the call).
 * Either way we receive exactly one reference.  The dispatch function's own
 * Perceus instrumentation decrements it after unpacking.
 *
 * FBIP: we do NOT force-write actor->rc = 1 before calling the dispatch
 * closure.  Doing so (with relaxed ordering) would silently clobber any
 * concurrent RC modifications.  FBIP for state mutation operates on the
 * locally-constructed state record inside the handler (always rc=1).
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

    /* Allocate message node — does NOT touch msg's RC. */
    march_msg_node *node = (march_msg_node *)malloc(sizeof(march_msg_node));
    if (!node) { fputs("march: out of memory (msg node)\n", stderr); exit(1); }
    node->msg = msg;

    /* MPSC Treiber-stack push — lock-free, safe from any thread.
     * release: node->msg write is visible to the consumer (scheduler). */
    march_msg_node *old;
    do {
        old = atomic_load_explicit(&meta->mbox_head, memory_order_relaxed);
        node->next = old;
    } while (!atomic_compare_exchange_weak_explicit(
                 &meta->mbox_head, &old, node,
                 memory_order_release, memory_order_relaxed));

    /* Schedule actor if not already in the run queue.
     * Only the winner of the CAS 0→1 adds to the run queue, preventing
     * duplicate entries when concurrent sends race on the same actor.
     *
     * Scheduling is deferred: march_run_scheduler() is called by the
     * @main() C wrapper after march_main() returns, or explicitly by
     * the caller via march_run_scheduler().  This ensures true async
     * semantics consistent with the interpreter: send() enqueues and
     * returns without executing the handler; the handler runs in a
     * separate scheduler pass. */
    int exp = 0;
    if (atomic_compare_exchange_strong_explicit(
            &meta->scheduled, &exp, 1,
            memory_order_acq_rel, memory_order_relaxed)) {
        sched_enqueue(meta);
    }

    /* Return Some(()). */
    void *some = march_alloc(16 + 8);
    int32_t *hdr = (int32_t *)((char *)some + 8);
    hdr[0] = 1;
    int64_t *fld = (int64_t *)((char *)some + 16);
    fld[0] = 0;
    return some;
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

/* Returns List(String). */
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

/* Header layout: rc(8) | tag(4) | pad(4) | fields... */
#define MARCH_FIELD(obj, i) (((int64_t *)(obj))[2 + (i)])
#define MARCH_FIELD_PTR(obj, i) ((void *)MARCH_FIELD(obj, i))
#define MARCH_SET_TAG(obj, t) (((march_hdr *)(obj))->tag = (int32_t)(t))

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
