#include "march_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <stdatomic.h>
#include <pthread.h>
#include <sys/stat.h>

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

void march_incrc(void *p) {
    if (!p) return;
    /* Relaxed: caller already holds a reference so the object is alive. */
    atomic_fetch_add_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_relaxed);
}

void march_decrc(void *p) {
    if (!p) return;
    /* acq_rel: release our writes before decrement; acquire before free so
     * we see all other threads' writes to the object. */
    int64_t prev = atomic_fetch_sub_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_acq_rel);
    if (prev <= 1) free(p);
}

int64_t march_decrc_freed(void *p) {
    if (!p) return 1;
    int64_t prev = atomic_fetch_sub_explicit(
        (_Atomic int64_t *)&((march_hdr *)p)->rc, 1, memory_order_acq_rel);
    if (prev <= 1) { free(p); return 1; }
    return 0;
}

void march_free(void *p) {
    free(p);
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

#define MARCH_SCHED_BUCKETS 256   /* Power-of-2 hash table size              */
#define MARCH_BATCH_MAX      64   /* Max messages dispatched per actor/turn  */

/* Single node in an actor's MPSC mailbox (intrusive linked list). */
typedef struct march_msg_node {
    void                  *msg;   /* Payload — one RC reference owned by us  */
    struct march_msg_node *next;
} march_msg_node;

/* Per-actor scheduler metadata.  Stored in a side table keyed by actor
 * pointer so the actor object layout (and codegen) are unaffected. */
typedef struct march_actor_meta {
    void                      *actor;
    _Atomic(march_msg_node *)   mbox_head;  /* MPSC Treiber stack head         */
    _Atomic int                 scheduled;  /* 0 = idle, 1 = queued/running    */
    struct march_actor_meta    *run_next;   /* Run-queue intrusive link        */
    struct march_actor_meta    *tbl_next;   /* Hash-table chain                */
} march_actor_meta;

/* Global side table: actor ptr → march_actor_meta */
static march_actor_meta  *g_actor_tbl[MARCH_SCHED_BUCKETS];
static pthread_mutex_t    g_tbl_mu = PTHREAD_MUTEX_INITIALIZER;

/* Scheduler run queue — FIFO, protected by g_run_mu */
static march_actor_meta  *g_run_head = NULL;
static march_actor_meta  *g_run_tail = NULL;
static pthread_mutex_t    g_run_mu   = PTHREAD_MUTEX_INITIALIZER;

/* Re-entrancy guard: handlers that call march_send must not recurse into
 * the scheduler; the outer loop will pick up newly-queued actors. */
static _Thread_local int g_in_scheduler = 0;

/* ── Side-table helpers ──────────────────────────────────────────── */

static unsigned int actor_bucket(void *actor) {
    return (unsigned int)(((uintptr_t)actor >> 4) % MARCH_SCHED_BUCKETS);
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
    m->tbl_next = g_actor_tbl[b];
    g_actor_tbl[b] = m;
    pthread_mutex_unlock(&g_tbl_mu);
    return m;
}

/* ── Run-queue helpers ───────────────────────────────────────────── */

/* Add actor to run queue tail.  Caller must have won the scheduled CAS. */
static void sched_enqueue(march_actor_meta *meta) {
    meta->run_next = NULL;
    pthread_mutex_lock(&g_run_mu);
    if (g_run_tail) { g_run_tail->run_next = meta; g_run_tail = meta; }
    else            { g_run_head = g_run_tail = meta; }
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

/* ── Public actor API ────────────────────────────────────────────── */

void march_kill(void *actor) {
    int64_t *fields = (int64_t *)actor;
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
    find_or_create_meta(actor);
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
void march_run_scheduler(void) {
    if (g_in_scheduler) return;
    g_in_scheduler = 1;

    march_actor_meta *meta;
    while ((meta = sched_dequeue()) != NULL) {
        void *actor   = meta->actor;
        int64_t *a    = (int64_t *)actor;

        /* Drain mailbox atomically: swap head to NULL, get the Treiber stack,
         * reverse to recover FIFO order. */
        march_msg_node *stack = atomic_exchange_explicit(
            &meta->mbox_head, NULL, memory_order_acquire);

        /* Clear scheduled flag BEFORE re-checking the mailbox.
         * release: our flag clear is visible to producers checking it.
         * We check for new messages below; a producer that pushes after our
         * drain but before our clear will see scheduled=1, skip re-scheduling,
         * and we will re-schedule in the re-check below. */
        atomic_store_explicit(&meta->scheduled, 0, memory_order_release);

        if (stack) {
            march_msg_node *fifo = reverse_msgs(stack);

            /* Dispatch closure is stored as field[2] of the actor struct.
             * Closure layout: header(16) + fn_ptr(8). The wrapper fn takes
             * (closure, actor, msg) and calls ActorName_dispatch(actor, msg). */
            char *closure = (char *)(uintptr_t)a[2];
            typedef void (*closure_fn_t)(void *, void *, void *);
            closure_fn_t fn = *(closure_fn_t *)(closure + 16);

            int count = 0;
            while (fifo && count < MARCH_BATCH_MAX) {
                march_msg_node *node = fifo;
                fifo = node->next;
                void *msg = node->msg;
                free(node);

                if (a[3]) {            /* alive? */
                    fn(closure, actor, msg);   /* dispatch; Perceus handles RC */
                } else {
                    /* Actor died mid-batch: release the reference we own. */
                    march_decrc(msg);
                }
                count++;
            }

            /* Batch was truncated: push leftover messages back to mailbox
             * so other actors get a turn before we continue. */
            if (fifo) {
                march_msg_node *tail = fifo;
                while (tail->next) tail = tail->next;
                /* CAS-push the entire leftover FIFO list onto the stack head. */
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

        /* Re-check mailbox after clearing the scheduled flag.
         * acquire: see any message pushed by a concurrent sender.
         * If the mailbox is non-empty and we win the CAS 0→1 we re-schedule. */
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
     * duplicate entries when concurrent sends race on the same actor. */
    int exp = 0;
    if (atomic_compare_exchange_strong_explicit(
            &meta->scheduled, &exp, 1,
            memory_order_acq_rel, memory_order_relaxed)) {
        sched_enqueue(meta);
        /* Inline scheduling: run the queue now if no scheduler is active.
         * Preserves apparent-synchronous semantics for single-threaded
         * programs without blocking concurrent senders. */
        if (!g_in_scheduler) {
            march_run_scheduler();
        }
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

/* ── Value pretty-printing ───────────────────────────────────────────── */

/* Format a March value as a human-readable string.
   v1: prints scalars inline; heap objects as #<tag:N>.
   Future: can use registered constructor name tables for better output. */
void *march_value_to_string(void *v) {
    if (!v) return march_string_lit("nil", 3);
    march_hdr *h = (march_hdr *)v;
    int32_t tag = h->tag;
    char buf[128];
    int n = snprintf(buf, sizeof(buf), "#<tag:%d>", tag);
    return march_string_lit(buf, n);
}
