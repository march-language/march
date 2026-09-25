/* march_reclaim.c — epoch-based reclamation.  Contract and design: the header,
 * and specs/progress/2026-09-23-proc-struct-reclamation-metas.md ("Chosen mechanism").
 *
 * Correctness argument, in one place (every ordering below is load-bearing):
 *
 *   g_epoch only increases.  march_reclaim_retire stamps an object with the
 *   value e that its fetch_add REPLACED, so the caller's unlink is sequenced
 *   before the increment e -> e+1 (a seq_cst RMW, hence a release).  A slot
 *   that announces a value a >= e+1 read g_epoch (acquire) at or after that
 *   increment, so it synchronizes with it and can no longer load the unlinked
 *   pointer.  A slot announcing a <= e may have resolved it before the
 *   unlink.  Hence: free an object stamped e once every online slot announces
 *   a > e.  Offline slots (epoch 0) are skipped.
 *
 *   Going ONLINE is the one store->load hazard: the announcement must be
 *   visible to a reclaimer before this thread's next pointer load, and
 *   release/acquire does not order a store before a later load of a
 *   different location.  So an online transition is store + seq_cst fence,
 *   and the reclaimer issues a seq_cst fence before it scans the slots: the
 *   Dekker pair.  Either the reclaimer sees the announcement, or this thread
 *   sees the unlink.
 *
 *   A quiescent state on a thread that is ALREADY online needs no fence:
 *   until the new value is visible the reclaimer sees the older one, which
 *   is only more conservative.  The release store orders every access of
 *   the slice before it ahead of any free that observes the new value.
 *   (The design text allowed a fence per dispatch; it is not needed.)
 */
#include "march_reclaim.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct march_reclaim_slot {
    _Atomic uint64_t                    epoch;  /* 0 = offline, else announced */
    _Atomic int                         owned;  /* claimed by a live thread    */
    struct march_reclaim_slot *_Atomic  next;   /* push-only list, never freed */
} __attribute__((aligned(64))) march_reclaim_slot;

static march_reclaim_slot *_Atomic g_slots = NULL;
static _Atomic uint64_t            g_epoch = 1;   /* never 0: 0 means offline */

/* One TLS block, so each entry point pays one TLS address computation (an
 * indirect call on Darwin/arm64) rather than one per field.  Every function
 * that touches it is noinline: a green thread migrates across a park, and
 * an inlined TLS address cached across the switch would be the OLD thread's
 * (the hazard march_sched_yield's comment describes). */
typedef struct {
    march_reclaim_slot *slot;
    int                 depth;
    int                 qsbr;     /* scheduler thread: quiescent-state based */
} march_reclaim_tls;

static pthread_once_t g_key_once = PTHREAD_ONCE_INIT;
static pthread_key_t  g_key;

static _Thread_local march_reclaim_tls tl_reclaim;

/* The key destructor, run by pthread_exit's TSD cleanup.  It must NOT touch
 * tl_reclaim or any other _Thread_local: on Darwin dyld may already have torn
 * this thread's TLV block down, so a TLS access here instantiates it again,
 * which mallocs, and a preemption tick landing inside that malloc re-entered
 * the allocator from the signal handler and trapped
 * (specs/progress/2026-09-25-preempt-tick-at-thread-exit-sigtrap.md).
 * Everything comes from the argument.  A later key destructor on this thread
 * that enters again cannot reuse the stale tl_reclaim.slot: my_slot checks it
 * against the key's value, which pthreads cleared before calling us. */
static void slot_release(void *v) {
    march_reclaim_slot *s = (march_reclaim_slot *)v;
    atomic_store_explicit(&s->epoch, 0, memory_order_release);
    atomic_store_explicit(&s->owned, 0, memory_order_release);
}

static void key_init(void) {
    if (pthread_key_create(&g_key, slot_release) != 0) {
        fputs("march_reclaim: pthread_key_create failed\n", stderr);
        abort();
    }
}

static march_reclaim_slot *slot_claim(void) {
    pthread_once(&g_key_once, key_init);
    march_reclaim_slot *s;
    for (s = atomic_load_explicit(&g_slots, memory_order_acquire); s;
         s = atomic_load_explicit(&s->next, memory_order_acquire)) {
        int zero = 0;
        if (atomic_compare_exchange_strong_explicit(&s->owned, &zero, 1,
                memory_order_acq_rel, memory_order_relaxed))
            break;
    }
    if (!s) {
        void *mem = NULL;
        if (posix_memalign(&mem, 64, sizeof(march_reclaim_slot)) != 0 || !mem) {
            fputs("march_reclaim: out of memory (slot)\n", stderr);
            abort();
        }
        s = (march_reclaim_slot *)mem;
        memset(s, 0, sizeof *s);
        atomic_store_explicit(&s->owned, 1, memory_order_relaxed);
        march_reclaim_slot *head = atomic_load_explicit(&g_slots, memory_order_relaxed);
        do {
            atomic_store_explicit(&s->next, head, memory_order_relaxed);
        } while (!atomic_compare_exchange_weak_explicit(&g_slots, &head, s,
                     memory_order_release, memory_order_relaxed));
    }
    pthread_setspecific(g_key, s);
    return s;
}

/* t->slot goes stale once slot_release has run for this thread (the slot may
 * belong to another thread by then), so it is ours only while it is still the
 * key's value.  `!t->slot` first: a non-NULL slot means slot_claim ran, so
 * g_key exists. */
static inline march_reclaim_slot *my_slot(march_reclaim_tls *t) {
    if (!t->slot || pthread_getspecific(g_key) != (void *)t->slot)
        t->slot = slot_claim();
    return t->slot;
}

static inline void announce_online(march_reclaim_slot *s) {
    uint64_t e = atomic_load_explicit(&g_epoch, memory_order_acquire);
    atomic_store_explicit(&s->epoch, e, memory_order_relaxed);
    atomic_thread_fence(memory_order_seq_cst);
}

static void die(const char *what, const char *site) {
    fprintf(stderr, "march_reclaim[BUG]: %s%s%s\n", what,
            site ? " at " : "", site ? site : "");
    abort();
}

__attribute__((noinline))
void march_reclaim_enter(void) {
    march_reclaim_tls *t = &tl_reclaim;
    if (t->depth++ == 0 && !t->qsbr) announce_online(my_slot(t));
}

__attribute__((noinline))
void march_reclaim_exit(void) {
    march_reclaim_tls *t = &tl_reclaim;
    if (t->depth <= 0) die("march_reclaim_exit without a matching enter", NULL);
    if (--t->depth == 0 && !t->qsbr)
        atomic_store_explicit(&t->slot->epoch, 0, memory_order_release);
}

__attribute__((noinline))
int march_reclaim_depth(void) {
    return tl_reclaim.depth;
}

__attribute__((noinline))
void march_reclaim_check_switch(const char *site) {
    if (tl_reclaim.depth != 0)
        die("a critical section is held across a context switch "
            "(a resolved pointer must not outlive it)", site);
}

__attribute__((noinline))
int march_reclaim_suspend(void) {
    march_reclaim_tls *t = &tl_reclaim;
    int d = t->depth;
    if (d == 0) return 0;
    t->depth = 0;
    if (!t->qsbr)
        atomic_store_explicit(&t->slot->epoch, 0, memory_order_release);
    return d;
}

__attribute__((noinline))
void march_reclaim_resume(int depth) {
    if (depth <= 0) return;
    march_reclaim_tls *t = &tl_reclaim;
    if (t->depth != 0) die("march_reclaim_resume inside a critical section", NULL);
    if (!t->qsbr) announce_online(my_slot(t));
    t->depth = depth;
}

/* ── scheduler-thread (quiescent-state) hooks ─────────────────────────── */

void march_reclaim_sched_attach(void) {
    march_reclaim_tls *t = &tl_reclaim;
    if (t->depth != 0) die("scheduler attach inside a critical section", NULL);
    t->qsbr = 1;
    announce_online(my_slot(t));
}

void march_reclaim_quiescent(void) {
    march_reclaim_tls *t = &tl_reclaim;
    if (t->depth != 0)
        die("a critical section leaked across a dispatch "
            "(enter without exit on a green thread or in sched_loop)", NULL);
    uint64_t e = atomic_load_explicit(&g_epoch, memory_order_acquire);
    if (atomic_load_explicit(&t->slot->epoch, memory_order_relaxed) != e)
        atomic_store_explicit(&t->slot->epoch, e, memory_order_release);
}

void march_reclaim_offline(void) {
    march_reclaim_tls *t = &tl_reclaim;
    if (t->depth != 0) die("going offline inside a critical section", NULL);
    atomic_store_explicit(&t->slot->epoch, 0, memory_order_release);
}

void march_reclaim_online(void) {
    announce_online(my_slot(&tl_reclaim));
}

void march_reclaim_sched_detach(void) {
    march_reclaim_tls *t = &tl_reclaim;
    if (t->depth != 0) die("scheduler detach inside a critical section", NULL);
    t->qsbr = 0;
    atomic_store_explicit(&t->slot->epoch, 0, memory_order_release);
}

/* ── retire list ──────────────────────────────────────────────────────── */

typedef struct {
    void     *p;
    void    (*free_fn)(void *);
    uint64_t  epoch;
} march_retired;

/* Entries are appended under g_retire_mu in increasing epoch order, so the
 * freeable ones are always a prefix: [g_ret_head, g_ret_len). */
static pthread_mutex_t  g_retire_mu = PTHREAD_MUTEX_INITIALIZER;
static march_retired   *g_ret       = NULL;
static size_t           g_ret_head  = 0, g_ret_len = 0, g_ret_cap = 0;
static unsigned         g_ret_since_poll = 0;

static _Atomic int64_t  g_retired_total = 0;
static _Atomic int64_t  g_freed_total   = 0;

/* Poll the retire path every this many retires; the preempt daemon's tick
 * covers the rest (and drains a quiesced node). */
#define MARCH_RECLAIM_POLL_EVERY 32

static uint64_t min_online_epoch(void) {
    atomic_thread_fence(memory_order_seq_cst);   /* pairs with announce_online */
    uint64_t m = UINT64_MAX;
    for (march_reclaim_slot *s = atomic_load_explicit(&g_slots, memory_order_acquire);
         s; s = atomic_load_explicit(&s->next, memory_order_acquire)) {
        uint64_t e = atomic_load_explicit(&s->epoch, memory_order_acquire);
        if (e != 0 && e < m) m = e;
    }
    return m;
}

void march_reclaim_poll(void) {
    march_retired  local[64];
    for (;;) {
        size_t n = 0;
        pthread_mutex_lock(&g_retire_mu);
        g_ret_since_poll = 0;
        if (g_ret_head < g_ret_len) {
            uint64_t m = min_online_epoch();
            while (n < 64 && g_ret_head < g_ret_len && g_ret[g_ret_head].epoch < m)
                local[n++] = g_ret[g_ret_head++];
            if (g_ret_head == g_ret_len) g_ret_head = g_ret_len = 0;
        }
        pthread_mutex_unlock(&g_retire_mu);
        /* Free outside the lock: a free_fn may take other locks. */
        for (size_t i = 0; i < n; i++) local[i].free_fn(local[i].p);
        if (n) atomic_fetch_add_explicit(&g_freed_total, (int64_t)n, memory_order_relaxed);
        if (n < 64) return;
    }
}

void march_reclaim_retire(void *p, void (*free_fn)(void *)) {
    if (!p) return;
    int poll;
    pthread_mutex_lock(&g_retire_mu);
    if (g_ret_len == g_ret_cap) {
        /* Compact the consumed prefix before growing. */
        if (g_ret_head > 0) {
            memmove(g_ret, g_ret + g_ret_head,
                    (g_ret_len - g_ret_head) * sizeof *g_ret);
            g_ret_len -= g_ret_head;
            g_ret_head = 0;
        }
        if (g_ret_len == g_ret_cap) {
            size_t cap = g_ret_cap ? g_ret_cap * 2 : 256;
            march_retired *g = (march_retired *)realloc(g_ret, cap * sizeof *g);
            if (!g) { fputs("march_reclaim: out of memory (retire)\n", stderr); abort(); }
            g_ret = g;
            g_ret_cap = cap;
        }
    }
    uint64_t e = atomic_fetch_add_explicit(&g_epoch, 1, memory_order_seq_cst);
    g_ret[g_ret_len++] = (march_retired){ p, free_fn, e };
    poll = ++g_ret_since_poll >= MARCH_RECLAIM_POLL_EVERY;
    pthread_mutex_unlock(&g_retire_mu);
    atomic_fetch_add_explicit(&g_retired_total, 1, memory_order_relaxed);
    if (poll) march_reclaim_poll();
}

int64_t march_reclaim_retired_count(void) {
    return atomic_load_explicit(&g_retired_total, memory_order_relaxed);
}

int64_t march_reclaim_freed_count(void) {
    return atomic_load_explicit(&g_freed_total, memory_order_relaxed);
}
