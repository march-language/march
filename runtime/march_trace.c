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
 * written.
 *
 * Actor events.  A session with a kind mask also owns a bit (its index) in
 * g_introspect_armed (the gate the hooks test first) and in the trace_mask of
 * every live proc its pid filter names (the per-actor gate).  A hook ORs the
 * masks of the procs it already holds, ANDs them with the armed word, and
 * does nothing more when the result is 0.  Only then does it derive pids and
 * read a message's tag.  A stale bit (its session ended, or the index was
 * reused for another filter) is harmless: record_ev re-checks the session's
 * state and pid list, and the receiving actor clears bits that no longer
 * apply to it. */
#include "march_trace.h"
#include "march_dispatch.h"
#include "march_scheduler.h"
#include "march_runtime.h"

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
    int64_t          peer;
    int64_t          tag;
    uint64_t         at_ns;
    uint32_t         name_id;
    uint32_t         epoch;
    int32_t          kind;
    int32_t          reason;
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
    uint32_t         ev_kinds;   /* actor-event kinds wanted; 0: boundary calls only */
    int              npids;
    int64_t          pids[MARCH_TRACE_MAX_PIDS];
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
        /* Disarm the hooks for this session; the procs' own bits are cleared
         * when the session is stopped or reaped (and by the receiver). */
        if (s->ev_kinds)
            atomic_fetch_and_explicit(&g_introspect_armed, ~(1u << (s - g_sess)),
                                      memory_order_seq_cst);
    }
}

static int has_name(const session_t *s, uint32_t id) {
    for (int i = 0; i < s->nnames; i++)
        if (s->names[i] == id) return 1;
    return 0;
}

/* The Rate window and the ring reservation, shared by both kinds of event.
 * Returns 1 and sets *hout to the reserved index, or 0 when the event is not
 * taken (over the Rate budget, past Count, ring full: each counted where it
 * has a counter).  [now] is the caller's clock reading. */
static int reserve_slot(session_t *s, uint64_t now, uint64_t *hout) {
    if (s->kind == MARCH_TRACE_RATE) {
        uint64_t ws = atomic_load_explicit(&s->win_start, memory_order_relaxed);
        if (now - ws >= s->window_ns
                && atomic_compare_exchange_strong_explicit(&s->win_start, &ws, now,
                       memory_order_relaxed, memory_order_relaxed))
            atomic_store_explicit(&s->win_count, 0, memory_order_relaxed);
        /* Over budget: a plain load first, so a storm past the budget does
         * not also hammer the window counter with read-modify-writes. */
        if (atomic_load_explicit(&s->win_count, memory_order_relaxed)
                    >= (uint64_t)s->n
                || atomic_fetch_add_explicit(&s->win_count, 1, memory_order_relaxed)
                    >= (uint64_t)s->n) {
            atomic_fetch_add_explicit(&s->rate_dropped, 1, memory_order_relaxed);
            return 0;
        }
    }
    uint64_t h = atomic_load_explicit(&s->head, memory_order_relaxed);
    for (;;) {
        if (s->kind == MARCH_TRACE_COUNT && h >= (uint64_t)s->n) return 0;
        uint64_t t = atomic_load_explicit(&s->tail, memory_order_acquire);
        if (h - t >= s->cap) {
            atomic_fetch_add_explicit(&s->dropped, 1, memory_order_relaxed);
            return 0;
        }
        if (atomic_compare_exchange_weak_explicit(&s->head, &h, h + 1,
                memory_order_relaxed, memory_order_relaxed))
            break;
    }
    *hout = h;
    return 1;
}

/* Publish the slot reserved at [h] and end a Count session at its n-th. */
static void publish_slot(session_t *s, slot_t *sl, uint64_t h) {
    atomic_store_explicit(&sl->seq, h + 1, memory_order_release);
    if (s->kind == MARCH_TRACE_COUNT && h + 1 == (uint64_t)s->n)
        finish(s, WHY_COUNT);
}

/* The pid index Recon, STATE and pid_to_int speak for the current proc; -1
 * off an actor (main, a task). */
static int64_t current_pid(void) {
    march_proc *p = march_sched_current();
    return (p && p->actor) ? march_pid_index_of(p->actor) : -1;
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
    uint64_t h;
    if (!reserve_slot(s, now, &h)) goto out;
    {
        slot_t *sl = &s->ring[h % s->cap];
        sl->kind    = MARCH_TRACE_EV_CALL;
        sl->reason  = -1;
        sl->peer    = MARCH_TRACE_NONE;
        sl->tag     = MARCH_TRACE_NONE;
        sl->pid     = current_pid();
        sl->name_id = name_id;
        sl->epoch   = epoch;
        sl->at_ns   = now;
        publish_slot(s, sl, h);
    }
out:
    atomic_fetch_sub_explicit(&s->inflight, 1, memory_order_seq_cst);
}

void march_trace_hit(uint32_t name_id, uint32_t mask, uint32_t epoch) {
    for (int i = 0; i < MARCH_TRACE_MAX_SESSIONS; i++)
        if (mask & (1u << i)) record(&g_sess[i], name_id, epoch);
}

/* ── Actor events ─────────────────────────────────────────────────────── */

static int pid_listed(const session_t *s, int64_t pid) {
    if (pid < 0) return 0;                      /* main, a task, or "none" */
    for (int i = 0; i < s->npids; i++)
        if (s->pids[i] == pid) return 1;
    return 0;
}

/* One actor event into one session.  Lock-free and bounded: when the session
 * cannot take the event it costs a few loads (and, past a Rate budget or a
 * full ring, one counter increment), never a wait, a lock or an allocation.
 * Order matters for that: the checks that need no clock come first. */
static void record_ev(session_t *s, int ekind, int64_t pid, int64_t peer,
                      int64_t tag, int reason, uint32_t epoch) {
    atomic_fetch_add_explicit(&s->inflight, 1, memory_order_seq_cst);
    if (atomic_load_explicit(&s->state, memory_order_seq_cst) != S_ACTIVE) goto out;
    if (!(s->ev_kinds & MARCH_TRACE_EVB(ekind))) goto out;
    if (!pid_listed(s, pid) && !pid_listed(s, peer)) goto out;   /* stale bit */
    if (s->kind == MARCH_TRACE_COUNT
            && atomic_load_explicit(&s->head, memory_order_relaxed) >= (uint64_t)s->n)
        goto out;
    if (atomic_load_explicit(&s->head, memory_order_relaxed)
            - atomic_load_explicit(&s->tail, memory_order_acquire) >= s->cap) {
        atomic_fetch_add_explicit(&s->dropped, 1, memory_order_relaxed);
        goto out;
    }
    uint64_t now = march_mono_ns();
    if (now >= s->deadline) { finish(s, WHY_EXPIRED); goto out; }
    if (now - atomic_load_explicit(&s->last_touch, memory_order_relaxed)
            > (uint64_t)MARCH_TRACE_IDLE_S * NS_PER_S) {
        finish(s, WHY_IDLE);
        goto out;
    }
    uint64_t h;
    if (!reserve_slot(s, now, &h)) goto out;
    {
        slot_t *sl = &s->ring[h % s->cap];
        sl->kind    = ekind;
        sl->reason  = reason;
        sl->peer    = peer;
        sl->tag     = tag;
        sl->pid     = pid;
        sl->name_id = 0;
        sl->epoch   = epoch;
        sl->at_ns   = now;
        publish_slot(s, sl, h);
    }
out:
    atomic_fetch_sub_explicit(&s->inflight, 1, memory_order_seq_cst);
}

/* Offer an event to every armed session that may want it: those whose bit is
 * in [cand] (a proc's trace_mask said so), and, with [by_list], any session
 * whose pid list names [pid] or [peer] (for events whose proc is gone). */
static void emit(uint32_t cand, int by_list, int ekind, int64_t pid, int64_t peer,
                 int64_t tag, int reason, uint32_t epoch) {
    uint32_t armed = atomic_load_explicit(&g_introspect_armed, memory_order_relaxed);
    for (int i = 0; i < MARCH_TRACE_MAX_SESSIONS; i++) {
        uint32_t bit = 1u << i;
        if (!(armed & bit)) continue;
        if (!(cand & bit) && !by_list) continue;
        record_ev(&g_sess[i], ekind, pid, peer, tag, reason, epoch);
    }
}

/* The message's constructor tag, or MARCH_TRACE_NONE for an immediate.  The
 * header only: nothing of the message's contents is read. */
static int64_t tag_of(void *msg) {
    return (msg && IS_HEAP_PTR(msg)) ? (int64_t)((march_hdr *)msg)->tag
                                     : MARCH_TRACE_NONE;
}

static uint32_t mask_of(march_proc *p) {
    return p ? atomic_load_explicit(&p->trace_mask, memory_order_relaxed) : 0;
}

static uint32_t epoch_of(march_proc *p) {
    return p ? atomic_load_explicit(&p->code_epoch, memory_order_relaxed) : 0;
}

void march_trace_ev_sent(march_proc *sender, march_proc *target, void *msg) {
    uint32_t cand = atomic_load_explicit(&g_introspect_armed, memory_order_relaxed)
                  & (mask_of(sender) | mask_of(target));
    if (!cand) return;                          /* armed, but nobody here is watched */
    emit(cand, 0, MARCH_TRACE_EV_SENT, march_trace_proc_pid(sender),
         target ? march_trace_proc_pid(target) : MARCH_TRACE_NONE,
         tag_of(msg), -1, epoch_of(sender));
}

void march_trace_ev_received(march_proc *self, void *msg) {
    uint32_t armed = atomic_load_explicit(&g_introspect_armed, memory_order_relaxed);
    uint32_t mine = mask_of(self);
    int64_t pid = march_trace_proc_pid(self);
    /* Bits of sessions that ended, or whose filter no longer names this
     * actor: drop them, so this hook is not called again for them. */
    uint32_t stale = mine & ~armed;
    for (int i = 0; i < MARCH_TRACE_MAX_SESSIONS; i++)
        if ((mine & armed & (1u << i)) && !pid_listed(&g_sess[i], pid))
            stale |= 1u << i;
    if (stale) atomic_fetch_and_explicit(&self->trace_mask, ~stale, memory_order_relaxed);
    uint32_t cand = mine & armed & ~stale;
    if (!cand) return;
    emit(cand, 0, MARCH_TRACE_EV_RECEIVED, pid, MARCH_TRACE_NONE, tag_of(msg), -1,
         epoch_of(self));
}

/* pid: the recipient that did not get the message; peer: its sender. */
void march_trace_ev_dropped(march_proc *sender, march_proc *target,
                            int64_t target_pid, void *msg, int reason) {
    uint32_t armed = atomic_load_explicit(&g_introspect_armed, memory_order_relaxed);
    if (!armed) return;
    if (target_pid == -2) target_pid = march_trace_proc_pid(target);
    /* The recipient's proc may be gone: match by pid list as well as by mask. */
    emit(armed & (mask_of(sender) | mask_of(target)), 1, MARCH_TRACE_EV_DROPPED,
         target_pid, sender ? march_trace_proc_pid(sender) : MARCH_TRACE_NONE,
         tag_of(msg), reason, epoch_of(sender));
}

void march_trace_ev_spawned(march_proc *parent, int64_t parent_pid, int64_t child_pid) {
    uint32_t cand = atomic_load_explicit(&g_introspect_armed, memory_order_relaxed)
                  & mask_of(parent);
    if (!cand) return;
    emit(cand, 0, MARCH_TRACE_EV_SPAWNED, parent_pid, child_pid, MARCH_TRACE_NONE, -1,
         epoch_of(parent));
}

void march_trace_ev_exited(march_proc *gt, int64_t pid, int reason) {
    uint32_t armed = atomic_load_explicit(&g_introspect_armed, memory_order_relaxed);
    if (!armed) return;
    emit(armed & mask_of(gt), 1, MARCH_TRACE_EV_EXITED, pid, MARCH_TRACE_NONE,
         MARCH_TRACE_NONE, reason, epoch_of(gt));
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
    if (s->ev_kinds) {
        uint32_t bit = 1u << (s - g_sess);
        atomic_fetch_and_explicit(&g_introspect_armed, ~bit, memory_order_seq_cst);
        for (int i = 0; i < s->npids; i++)
            (void)march_trace_flag_pid(s->pids[i], 0, bit);
    }
    while (atomic_load_explicit(&s->inflight, memory_order_seq_cst) > 0)
        sched_yield();
    free(s->ring);
    s->ring = NULL;
    s->id = 0;
    s->nnames = 0;
    s->ev_kinds = 0;
    s->npids = 0;
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
                              int nnames, const march_trace_actor_opts *ev,
                              int64_t *id) {
    if (kind == MARCH_TRACE_COUNT) {
        if (a < 1 || a > MARCH_TRACE_COUNT_MAX) return "limit_out_of_range";
    } else if (kind == MARCH_TRACE_RATE) {
        if (a < 1 || a > MARCH_TRACE_RATE_MAX
                || b < 1 || b > MARCH_TRACE_PER_S_MAX) return "limit_out_of_range";
        if (ring > MARCH_TRACE_RING_MAX) return "limit_out_of_range";
    } else {
        return "limit_required";
    }
    uint32_t ev_kinds = ev ? ev->kinds : 0;
    int64_t pids[MARCH_TRACE_MAX_PIDS];
    int npids = 0;
    if (ev_kinds & ~MARCH_TRACE_ACTOR_KINDS) return "bad_args";
    if (ev_kinds) {
        /* An actor-event session names the actors it watches: there is no
         * "all actors" form (see march_trace.h). */
        if (ev->npids < 1) return "pids_required";
        if (ev->npids > MARCH_TRACE_MAX_PIDS) return "bad_args";
        for (int i = 0; i < ev->npids; i++) {
            if (ev->pids[i] < 0) return "bad_args";
            int dup = 0;
            for (int j = 0; j < npids; j++) dup |= (pids[j] == ev->pids[i]);
            if (!dup) pids[npids++] = ev->pids[i];
        }
    } else if (ev && ev->npids != 0) {
        return "bad_args";                      /* a pid filter with nothing to filter */
    }
    if (nnames < 0 || nnames > MARCH_TRACE_MAX_FNS || (nnames > 0 && !names))
        return "bad_args";
    if (nnames == 0 && !ev_kinds) return "bad_args";   /* a session watches something */

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
    s->ev_kinds = ev_kinds;      /* before ACTIVE: a stale producer reads these */
    s->npids = npids;
    memcpy(s->pids, pids, sizeof(int64_t) * (size_t)npids);
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
    if (ev_kinds) {
        for (int i = 0; i < npids; i++) {
            if (march_trace_flag_pid(pids[i], bit, 0) < 0) {
                release(s);
                pthread_mutex_unlock(&g_mu);
                return "unknown_pid";           /* no live actor has that pid */
            }
        }
        /* Arm last: the proc bits are in place before a hook can look. */
        atomic_fetch_or_explicit(&g_introspect_armed, bit, memory_order_seq_cst);
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
    st->ev_kinds = s->ev_kinds;
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
        out[k].kind = sl->kind;
        out[k].reason = sl->reason;
        out[k].peer = sl->peer;
        out[k].tag = sl->tag;
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
