/* march_trace.c — bounded trace sessions for boundary calls.  See
 * march_trace.h for the contract.
 *
 * Concurrency.  The session table is a fixed array of MARCH_TRACE_MAX_SESSIONS
 * structs; a session's index is its bit in a dispatch slot's `traced` mask.
 *
 *   producers  march_trace_hit, on any scheduler thread, lock-free;
 *   control    start / drain / stop / reap, under g_mu.
 *
 * A producer announces itself (`inflight`), then checks `state`; stop sets
 * `state` then waits for `inflight` to reach zero before freeing the ring
 * (a Dekker pair, all seq_cst), so a ring is never freed under a writer.
 * A producer never waits for a consumer: a full ring drops and counts.
 *
 * Event slots are published with a per-slot sequence word (idx + 1, release),
 * so the consumer never reads a slot a producer has reserved but not yet
 * written. */
#include "march_trace.h"
#include "march_dispatch.h"
#include "march_scheduler.h"

#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* march_dispatch.c's mask accessor (declared there, not in the public
 * header: only this file edits masks). */
int march_dispatch_trace_mask(uint32_t name_id, uint32_t set, uint32_t clear);

int64_t march_pid_index_of(void *actor);

enum { S_FREE = 0, S_ACTIVE = 1, S_DONE = 2, S_STOPPING = 3 };
enum { WHY_NONE = 0, WHY_COUNT, WHY_EXPIRED, WHY_IDLE };

typedef struct {
    _Atomic uint64_t seq;       /* idx + 1 once the fields below are written */
    int64_t          pid;
    uint32_t         name_id;
    uint32_t         epoch;
    uint64_t         at_ns;
} slot_t;

typedef struct {
    _Atomic int      state;
    _Atomic int      inflight;
    _Atomic int      why;
    int64_t          id;
    int              kind;
    int64_t          n;          /* Count: the total; Rate: events per window */
    uint64_t         window_ns;  /* Rate */
    uint32_t         cap;
    slot_t          *ring;
    _Atomic uint64_t head;       /* next index to reserve */
    _Atomic uint64_t tail;       /* next index to drain */
    _Atomic uint64_t dropped;
    _Atomic uint64_t rate_dropped;
    _Atomic uint64_t win_start;
    _Atomic uint64_t win_count;
    _Atomic uint64_t last_touch; /* ns of the last start/drain */
    uint64_t         deadline;   /* ns: lifetime cap */
    uint64_t         start_ns;   /* events report time since this */
    uint32_t         names[MARCH_TRACE_MAX_FNS];
    int              nnames;
} session_t;

static session_t        g_sess[MARCH_TRACE_MAX_SESSIONS];
static pthread_mutex_t  g_mu = PTHREAD_MUTEX_INITIALIZER;
static int64_t          g_next_id = 1;

#define NS_PER_S 1000000000ull

static void clear_masks(session_t *s) {
    uint32_t bit = 1u << (s - g_sess);
    for (int i = 0; i < s->nnames; i++)
        (void)march_dispatch_trace_mask(s->names[i], 0, bit);
}

/* Stop recording: the winner clears the slot masks, so the dispatch path is
 * back to a never-taken branch. */
static void finish(session_t *s, int why) {
    int exp = S_ACTIVE;
    if (atomic_compare_exchange_strong_explicit(&s->state, &exp, S_DONE,
                                                memory_order_seq_cst,
                                                memory_order_seq_cst)) {
        atomic_store_explicit(&s->why, why, memory_order_relaxed);
        clear_masks(s);
    }
}

static int has_name(const session_t *s, uint32_t id) {
    for (int i = 0; i < s->nnames; i++)
        if (s->names[i] == id) return 1;
    return 0;
}

static void record(session_t *s, uint32_t name_id, uint32_t epoch) {
    atomic_fetch_add_explicit(&s->inflight, 1, memory_order_seq_cst);
    if (atomic_load_explicit(&s->state, memory_order_seq_cst) != S_ACTIVE) goto out;
    if (!has_name(s, name_id)) goto out;           /* stale mask after a restart of this index */
    uint64_t now = march_mono_ns();
    if (now >= s->deadline) { finish(s, WHY_EXPIRED); goto out; }
    if (now - atomic_load_explicit(&s->last_touch, memory_order_relaxed)
            > (uint64_t)MARCH_TRACE_IDLE_S * NS_PER_S) {
        finish(s, WHY_IDLE);
        goto out;
    }
    if (s->kind == MARCH_TRACE_RATE) {
        uint64_t ws = atomic_load_explicit(&s->win_start, memory_order_relaxed);
        if (now - ws >= s->window_ns
                && atomic_compare_exchange_strong_explicit(&s->win_start, &ws, now,
                       memory_order_relaxed, memory_order_relaxed))
            atomic_store_explicit(&s->win_count, 0, memory_order_relaxed);
        if (atomic_fetch_add_explicit(&s->win_count, 1, memory_order_relaxed)
                >= (uint64_t)s->n) {
            atomic_fetch_add_explicit(&s->rate_dropped, 1, memory_order_relaxed);
            goto out;
        }
    }
    uint64_t h = atomic_load_explicit(&s->head, memory_order_relaxed);
    for (;;) {
        if (s->kind == MARCH_TRACE_COUNT && h >= (uint64_t)s->n) goto out;
        uint64_t t = atomic_load_explicit(&s->tail, memory_order_acquire);
        if (h - t >= s->cap) {
            atomic_fetch_add_explicit(&s->dropped, 1, memory_order_relaxed);
            goto out;
        }
        if (atomic_compare_exchange_weak_explicit(&s->head, &h, h + 1,
                memory_order_relaxed, memory_order_relaxed))
            break;
    }
    {
        slot_t *sl = &s->ring[h % s->cap];
        march_proc *p = march_sched_current();
        /* The pid index Recon, STATE and pid_to_int speak; -1 off an actor
         * (main, a task). */
        sl->pid     = (p && p->actor) ? march_pid_index_of(p->actor) : -1;
        sl->name_id = name_id;
        sl->epoch   = epoch;
        sl->at_ns   = now;
        atomic_store_explicit(&sl->seq, h + 1, memory_order_release);
        if (s->kind == MARCH_TRACE_COUNT && h + 1 == (uint64_t)s->n)
            finish(s, WHY_COUNT);
    }
out:
    atomic_fetch_sub_explicit(&s->inflight, 1, memory_order_seq_cst);
}

void march_trace_hit(uint32_t name_id, uint32_t mask, uint32_t epoch) {
    for (int i = 0; i < MARCH_TRACE_MAX_SESSIONS; i++)
        if (mask & (1u << i)) record(&g_sess[i], name_id, epoch);
}

/* ── Control plane ────────────────────────────────────────────────────── */

static session_t *find(int64_t id) {
    for (int i = 0; i < MARCH_TRACE_MAX_SESSIONS; i++)
        if (g_sess[i].id == id
                && atomic_load_explicit(&g_sess[i].state, memory_order_relaxed) != S_FREE)
            return &g_sess[i];
    return NULL;
}

/* Quiesce and free (g_mu held). */
static void release(session_t *s) {
    atomic_store_explicit(&s->state, S_STOPPING, memory_order_seq_cst);
    clear_masks(s);
    while (atomic_load_explicit(&s->inflight, memory_order_seq_cst) > 0)
        sched_yield();
    free(s->ring);
    s->ring = NULL;
    s->id = 0;
    s->nnames = 0;
    atomic_store_explicit(&s->state, S_FREE, memory_order_seq_cst);
}

/* Free sessions nobody has touched for the idle period, or past their
 * lifetime (g_mu held). */
static void reap(uint64_t now) {
    for (int i = 0; i < MARCH_TRACE_MAX_SESSIONS; i++) {
        session_t *s = &g_sess[i];
        if (atomic_load_explicit(&s->state, memory_order_relaxed) == S_FREE) continue;
        if (now - atomic_load_explicit(&s->last_touch, memory_order_relaxed)
                    > (uint64_t)MARCH_TRACE_IDLE_S * NS_PER_S
                || now > s->deadline + (uint64_t)MARCH_TRACE_IDLE_S * NS_PER_S)
            release(s);
    }
}

const char *march_trace_start(march_trace_kind kind, int64_t a, int64_t b,
                              int64_t ring, const char *const *names,
                              int nnames, int64_t *id) {
    if (kind == MARCH_TRACE_COUNT) {
        if (a < 1 || a > MARCH_TRACE_COUNT_MAX) return "limit_out_of_range";
    } else if (kind == MARCH_TRACE_RATE) {
        if (a < 1 || a > MARCH_TRACE_RATE_MAX
                || b < 1 || b > MARCH_TRACE_PER_S_MAX) return "limit_out_of_range";
        if (ring > MARCH_TRACE_RING_MAX) return "limit_out_of_range";
    } else {
        return "limit_required";
    }
    if (nnames < 1 || nnames > MARCH_TRACE_MAX_FNS || !names) return "bad_args";

    uint32_t ids[MARCH_TRACE_MAX_FNS];
    int nids = 0;
    for (int i = 0; i < nnames; i++) {
        uint32_t nid;
        if (!names[i] || !march_dispatch_name_to_id(names[i], &nid))
            return "unknown_function";
        int dup = 0;
        for (int j = 0; j < nids; j++) dup |= (ids[j] == nid);
        if (!dup) ids[nids++] = nid;
    }

    pthread_mutex_lock(&g_mu);
    uint64_t now = march_mono_ns();
    reap(now);
    session_t *s = NULL;
    for (int i = 0; i < MARCH_TRACE_MAX_SESSIONS; i++)
        if (atomic_load_explicit(&g_sess[i].state, memory_order_relaxed) == S_FREE) {
            s = &g_sess[i];
            break;
        }
    if (!s) { pthread_mutex_unlock(&g_mu); return "too_many_sessions"; }

    uint32_t cap = kind == MARCH_TRACE_COUNT ? (uint32_t)a
                 : ring > 0 ? (uint32_t)ring : MARCH_TRACE_RING_DEFAULT;
    slot_t *r = (slot_t *)calloc(cap, sizeof(slot_t));
    if (!r) { pthread_mutex_unlock(&g_mu); return "out_of_memory"; }

    s->kind = kind;
    s->n = a;
    s->window_ns = kind == MARCH_TRACE_RATE ? (uint64_t)b * NS_PER_S : 0;
    s->cap = cap;
    s->ring = r;
    atomic_store_explicit(&s->head, 0, memory_order_relaxed);
    atomic_store_explicit(&s->tail, 0, memory_order_relaxed);
    atomic_store_explicit(&s->dropped, 0, memory_order_relaxed);
    atomic_store_explicit(&s->rate_dropped, 0, memory_order_relaxed);
    atomic_store_explicit(&s->win_start, now, memory_order_relaxed);
    atomic_store_explicit(&s->win_count, 0, memory_order_relaxed);
    atomic_store_explicit(&s->last_touch, now, memory_order_relaxed);
    atomic_store_explicit(&s->why, WHY_NONE, memory_order_relaxed);
    s->deadline = now + (uint64_t)MARCH_TRACE_LIFETIME_S * NS_PER_S;
    s->start_ns = now;
    memcpy(s->names, ids, sizeof(uint32_t) * (size_t)nids);
    s->nnames = nids;
    s->id = g_next_id++;
    atomic_store_explicit(&s->state, S_ACTIVE, memory_order_seq_cst);

    uint32_t bit = 1u << (s - g_sess);
    for (int i = 0; i < nids; i++) {
        if (march_dispatch_trace_mask(ids[i], bit, 0) < 0) {
            release(s);
            pthread_mutex_unlock(&g_mu);
            return "unknown_function";
        }
    }
    *id = s->id;
    pthread_mutex_unlock(&g_mu);
    return NULL;
}

static void fill_status(session_t *s, march_trace_status *st, uint64_t now) {
    if (!st) return;
    uint64_t h = atomic_load_explicit(&s->head, memory_order_relaxed);
    uint64_t t = atomic_load_explicit(&s->tail, memory_order_relaxed);
    if (atomic_load_explicit(&s->state, memory_order_relaxed) == S_ACTIVE
            && now >= s->deadline)
        finish(s, WHY_EXPIRED);   /* nothing called the traced fns to notice */
    int state = atomic_load_explicit(&s->state, memory_order_relaxed);
    int why = atomic_load_explicit(&s->why, memory_order_relaxed);
    st->recorded = h;
    st->dropped = atomic_load_explicit(&s->dropped, memory_order_relaxed);
    st->rate_dropped = atomic_load_explicit(&s->rate_dropped, memory_order_relaxed);
    st->pending = h - t;
    st->done = state != S_ACTIVE;
    st->why = !st->done ? NULL
            : why == WHY_COUNT ? "count"
            : why == WHY_EXPIRED ? "expired"
            : why == WHY_IDLE ? "idle" : "stopped";
    st->now_ns = now - s->start_ns;
}

int march_trace_drain(int64_t id, int max, march_trace_event *out,
                      march_trace_status *st) {
    if (max < 0) max = 0;
    if (max > MARCH_TRACE_DRAIN_MAX) max = MARCH_TRACE_DRAIN_MAX;
    pthread_mutex_lock(&g_mu);
    session_t *s = find(id);
    if (!s) { pthread_mutex_unlock(&g_mu); return -1; }
    uint64_t now = march_mono_ns();
    atomic_store_explicit(&s->last_touch, now, memory_order_relaxed);
    uint64_t t = atomic_load_explicit(&s->tail, memory_order_relaxed);
    uint64_t h = atomic_load_explicit(&s->head, memory_order_acquire);
    int k = 0;
    while (t < h && k < max) {
        slot_t *sl = &s->ring[t % s->cap];
        if (atomic_load_explicit(&sl->seq, memory_order_acquire) != t + 1) break;
        out[k].pid = sl->pid;
        out[k].name_id = sl->name_id;
        out[k].epoch = sl->epoch;
        out[k].at_ns = sl->at_ns - s->start_ns;   /* small enough for a JSON double */
        k++; t++;
    }
    atomic_store_explicit(&s->tail, t, memory_order_release);
    fill_status(s, st, now);
    pthread_mutex_unlock(&g_mu);
    return k;
}

int march_trace_stop(int64_t id, march_trace_status *st) {
    pthread_mutex_lock(&g_mu);
    session_t *s = find(id);
    if (!s) { pthread_mutex_unlock(&g_mu); return -1; }
    fill_status(s, st, march_mono_ns());
    release(s);
    pthread_mutex_unlock(&g_mu);
    return 0;
}

int march_trace_sessions(void) {
    int n = 0;
    pthread_mutex_lock(&g_mu);
    for (int i = 0; i < MARCH_TRACE_MAX_SESSIONS; i++)
        n += atomic_load_explicit(&g_sess[i].state, memory_order_relaxed) != S_FREE;
    pthread_mutex_unlock(&g_mu);
    return n;
}
