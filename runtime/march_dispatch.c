/* march_dispatch.c — Hot Code Reload versioned dispatch table (HCR Phase 2/4).
 * See march_dispatch.h and specs/hot-code-reload.md Part 3. */
#include "march_dispatch.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* dlclose for hot-patch handle GC.  Guard so the file compiles on non-POSIX. */
#if defined(__linux__) || defined(__APPLE__)
#include <dlfcn.h>
#define MARCH_HAS_DLCLOSE 1
#else
#define MARCH_HAS_DLCLOSE 0
#endif

/* Test seam: when set, slot_dlclose calls this INSTEAD of dlclose, so a unit
 * test can observe the exact moment a handle is released (and what a reader
 * can still reach at that moment) without loading real shared objects. */
static void (*g_close_hook)(void *handle) = NULL;

void march_dispatch_set_close_hook(void (*hook)(void *handle)) {
    g_close_hook = hook;
}

static void slot_dlclose(void *handle) {
    if (!handle) return;
    if (g_close_hook) { g_close_hook(handle); return; }
#if MARCH_HAS_DLCLOSE
    dlclose(handle);
#endif
}

typedef struct {
    void              *fn_ptr;          /* native code or trampoline thunk */
    _Atomic(uint64_t)  refs;            /* callers currently pinned to THIS version */
    char               impl_hash[65];   /* 64 hex chars + NUL */
    char               sig_hash[65];    /* 64 hex chars + NUL (Phase 4) */
    uint8_t            kind;            /* MARCH_NATIVE | MARCH_TRAMPOLINE */
    _Atomic(uint8_t)   live;            /* 1 once this ring slot holds a version.
                                           Publication gate: publish release-stores
                                           this LAST (after fn_ptr etc.); enter
                                           acquire-loads it before trusting the slot,
                                           so a concurrent reader never observes a
                                           zeroed/half-written slot. */
    _Atomic(uint32_t)  epoch;           /* Phase 9: deploy epoch; 0 = pre-Phase-9.
                                           Written before the `live` release-store
                                           (relaxed; the release orders it), read
                                           by enter_gen's scan after acquiring
                                           `live`.  Atomic because the scan can
                                           read a slot a reclaim is rewriting. */
    void              *handle;          /* dlopen handle for this .so; NULL for baseline */
    uint8_t            keep_for_older;  /* see march_dispatch_set_keep_for_older */
    uint8_t            staged;          /* 1 between march_dispatch_stage and commit/
                                           unstage: occupied but not yet live.  Read
                                           and written by the publisher only (the
                                           reload thread, or startup). */
} MarchFnVersion;

typedef struct {
    _Atomic(uint32_t) current;                        /* live ring index */
    MarchFnVersion    ring[MARCH_MAX_LIVE_VERSIONS];
    char              baseline_impl_hash[65];          /* Phase 4: set on first publish, never changed */
    long long         activated_at_ms;                 /* Phase 7: Unix ms of last ACTIVATE */
    char              signer_hex[65];                  /* Phase 7: pubkey hex of last ACTIVATE signer */
    char             *callers_str;                     /* Phase 8: comma-separated caller names, or NULL */
    _Atomic(uint32_t) msg_schema_epoch;                /* D30: epoch of the actor's last message-type
                                                          change (0 = never); see march_dispatch.h */
} MarchDispatchSlot;

/* g_slots / g_n_slots are written once by march_dispatch_init (startup, main
 * thread) and read by every boundary call on every worker thread.  They are
 * atomic so the one-time publication is a proper release/acquire handoff:
 * march_dispatch_init release-stores g_slots THEN g_n_slots (the gate); a hot
 * reader acquire-loads g_n_slots first and, on a non-zero result, is guaranteed
 * to see the fully-written g_slots pointer.  Cold accessors (reload-server
 * thread, post-startup) use relaxed loads — correctness there rests on the
 * startup happens-before, and this keeps the change to the hot path minimal. */
static _Atomic(MarchDispatchSlot *) g_slots      = NULL;
static _Atomic(uint32_t)            g_n_slots    = 0;
static const char        **g_id_to_name = NULL;  /* Phase 4: dense id→name array */

/* Relaxed accessors for cold (single-threaded, post-startup) call sites so the
 * bulk of this file reads exactly as before. */
static inline uint32_t n_slots_relaxed(void) {
    return atomic_load_explicit(&g_n_slots, memory_order_relaxed);
}
static inline MarchDispatchSlot *slots_relaxed(void) {
    return atomic_load_explicit(&g_slots, memory_order_relaxed);
}

/* ── Name registry ──────────────────────────────────────────────────────── */

#define MARCH_NAME_BUCKETS 64   /* must be power of two */

typedef struct NameEntry {
    const char       *name;
    uint32_t          id;
    struct NameEntry *next;
} NameEntry;

static NameEntry *g_name_buckets[MARCH_NAME_BUCKETS];

static uint32_t name_hash(const char *s) {
    uint32_t h = 2166136261u;
    while (*s) { h ^= (uint8_t)*s++; h *= 16777619u; }
    return h & (MARCH_NAME_BUCKETS - 1);
}

void march_dispatch_register_name(uint32_t id, const char *name) {
    if (!name) return;
    /* id→name reverse lookup (Phase 4) */
    if (id < g_n_slots && g_id_to_name)
        g_id_to_name[id] = name;
    /* name→id hash table */
    uint32_t b = name_hash(name);
    NameEntry *e = (NameEntry *)malloc(sizeof(NameEntry));
    if (!e) return;
    e->name = name;   /* points into the binary's rodata — stable lifetime */
    e->id   = id;
    e->next = g_name_buckets[b];
    g_name_buckets[b] = e;
}

int march_dispatch_name_to_id(const char *name, uint32_t *out_id) {
    if (!name) return 0;
    uint32_t b = name_hash(name);
    for (NameEntry *e = g_name_buckets[b]; e; e = e->next) {
        if (strcmp(e->name, name) == 0) {
            if (out_id) *out_id = e->id;
            return 1;
        }
    }
    return 0;
}

void march_dispatch_init(uint32_t n_slots) {
    march_dispatch_shutdown();
    MarchDispatchSlot *slots = (MarchDispatchSlot *)calloc(n_slots, sizeof(MarchDispatchSlot));
    const char       **names = (const char **)calloc(n_slots, sizeof(const char *));
    g_id_to_name = names;
    /* Store the slot array (relaxed) BEFORE the gate. */
    atomic_store_explicit(&g_slots, slots, memory_order_relaxed);
    if (!slots || !names) {
        free(slots);
        free(names);
        atomic_store_explicit(&g_slots, NULL, memory_order_relaxed);
        g_id_to_name = NULL;
        atomic_store_explicit(&g_n_slots, 0, memory_order_release);
        return;
    }
    /* Publish the table with a release store on g_n_slots: this is the gate.
     * A worker's first boundary call acquire-loads g_n_slots (in enter/enter_gen)
     * and, seeing a non-zero count, is guaranteed to also see the g_slots pointer
     * and the calloc-zeroed slot contents written above. */
    atomic_store_explicit(&g_n_slots, n_slots, memory_order_release);
}

void march_dispatch_shutdown(void) {
    /* Close the gate first so no reader indexes a slot array we are about to
     * free.  (Shutdown runs at process teardown, single-threaded in practice.) */
    uint32_t n = n_slots_relaxed();
    MarchDispatchSlot *slots = slots_relaxed();
    atomic_store_explicit(&g_n_slots, 0, memory_order_release);
    for (uint32_t i = 0; i < n; i++) {
        free(slots[i].callers_str);
        slots[i].callers_str = NULL;
        /* Release any live .so handles (server shutdown path). */
        for (uint32_t v = 0; v < MARCH_MAX_LIVE_VERSIONS; v++) {
            slot_dlclose(slots[i].ring[v].handle);
            slots[i].ring[v].handle = NULL;
        }
    }
    free(slots);
    atomic_store_explicit(&g_slots, NULL, memory_order_relaxed);
    free(g_id_to_name); g_id_to_name = NULL;
    for (int i = 0; i < MARCH_NAME_BUCKETS; i++) {
        NameEntry *e = g_name_buckets[i];
        while (e) { NameEntry *nx = e->next; free(e); e = nx; }
        g_name_buckets[i] = NULL;
    }
}

/* ── Ring-slot selection (II.4.2) ─────────────────────────────────────── */

/* True if ring version [i] can never be selected by enter_gen because another
 * live version has the same epoch and wins the tie (the current one, else the
 * lowest index -- enter_gen's scan order). */
static int version_shadowed(MarchDispatchSlot *s, uint32_t i, uint32_t cur,
                            uint32_t ep) {
    for (uint32_t j = 0; j < MARCH_MAX_LIVE_VERSIONS; j++) {
        if (j == i) continue;
        if (!atomic_load_explicit(&s->ring[j].live, memory_order_acquire)) continue;
        if (atomic_load_explicit(&s->ring[j].epoch, memory_order_relaxed) != ep) continue;
        if (i == cur) return 0;
        if (j == cur || j < i) return 1;
    }
    return 0;
}

/* The epoch of the next newer live version than [i] in this slot, or
 * UINT32_MAX when [i] is the newest. */
static uint32_t next_newer_epoch(MarchDispatchSlot *s, uint32_t i, uint32_t ep) {
    uint32_t best = UINT32_MAX;
    for (uint32_t j = 0; j < MARCH_MAX_LIVE_VERSIONS; j++) {
        if (j == i) continue;
        if (!atomic_load_explicit(&s->ring[j].live, memory_order_acquire)) continue;
        uint32_t ej = atomic_load_explicit(&s->ring[j].epoch, memory_order_relaxed);
        if (ej > ep && ej < best) best = ej;
    }
    return best;
}

/* Reclaim condition, per slot: refs == 0 and no pinned epoch in
 * [e, e_next).  The current version is never reclaimed: the current epoch
 * always holds its role pin, and current's interval reaches it. */
static int version_reclaimable(MarchDispatchSlot *s, uint32_t i, uint32_t cur) {
    MarchFnVersion *v = &s->ring[i];
    if (i == cur || v->staged) return 0;
    if (!atomic_load_explicit(&v->live, memory_order_acquire)) return 0;
    if (atomic_load_explicit(&v->refs, memory_order_acquire) != 0) return 0;
    uint32_t ep = atomic_load_explicit(&v->epoch, memory_order_relaxed);
    if (v->keep_for_older && ep > 0 && march_epoch_pinned_in(1, ep)) return 0;
    if (version_shadowed(s, i, cur, ep)) return 1;
    return !march_epoch_pinned_in(ep, next_newer_epoch(s, i, ep));
}

/* A ring slot that holds nothing live, nothing staged and no racing reader. */
static int version_free(MarchDispatchSlot *s, uint32_t i) {
    MarchFnVersion *v = &s->ring[i];
    return !v->staged
        && !atomic_load_explicit(&v->live, memory_order_acquire)
        && atomic_load_explicit(&v->refs, memory_order_acquire) == 0;
}

/* Pick the ring slot a stage would use: a free one first, else the
 * reclaimable version with the lowest epoch.  -1: none (the activation
 * waits). *out_reclaim is 1 when the choice holds a live version. */
static int pick_ring_slot(MarchDispatchSlot *s, int *out_reclaim) {
    uint32_t cur = atomic_load_explicit(&s->current, memory_order_acquire);
    *out_reclaim = 0;
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++)
        if (version_free(s, i)) return (int)i;
    int best = -1;
    uint32_t best_ep = 0;
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++) {
        if (!version_reclaimable(s, i, cur)) continue;
        uint32_t ep = atomic_load_explicit(&s->ring[i].epoch, memory_order_relaxed);
        if (best < 0 || ep < best_ep) { best = (int)i; best_ep = ep; }
    }
    if (best >= 0) *out_reclaim = 1;
    return best;
}

int march_dispatch_can_stage(uint32_t name_id) {
    if (name_id >= n_slots_relaxed()) return 0;
    MarchDispatchSlot *s = &slots_relaxed()[name_id];
    int any_live = 0;
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++)
        if (atomic_load_explicit(&s->ring[i].live, memory_order_relaxed)
                || s->ring[i].staged)
            { any_live = 1; break; }
    if (!any_live) return 1;
    int reclaim;
    return pick_ring_slot(s, &reclaim) >= 0;
}

int march_dispatch_live(uint32_t name_id, uint32_t version) {
    if (name_id >= n_slots_relaxed() || version >= MARCH_MAX_LIVE_VERSIONS) return 0;
    return atomic_load_explicit(&slots_relaxed()[name_id].ring[version].live,
                                memory_order_acquire) != 0;
}

int march_dispatch_stage(uint32_t name_id, void *fn_ptr,
                         const char *impl_hash, const char *sig_hash,
                         uint8_t kind, uint32_t epoch) {
    if (name_id >= g_n_slots) return -1;
    MarchDispatchSlot *s = &g_slots[name_id];

    int any_live = 0;
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++)
        if (atomic_load_explicit(&s->ring[i].live, memory_order_relaxed)
                || s->ring[i].staged)
            { any_live = 1; break; }

    int idx;
    if (!any_live) {
        idx = 0;  /* first publish into a fresh slot */
        /* Capture baseline_impl_hash (never overwritten on subsequent publishes) */
        if (impl_hash) {
            strncpy(s->baseline_impl_hash, impl_hash, 64);
            s->baseline_impl_hash[64] = '\0';
        } else {
            s->baseline_impl_hash[0] = '\0';
        }
    } else {
        int reclaim;
        idx = pick_ring_slot(s, &reclaim);
        if (idx < 0) return -1;
        MarchFnVersion *old = &s->ring[idx];
        if (reclaim) {
            /* Retire, THEN re-check refs, THEN dlclose.  The refs==0 test in
             * pick_ring_slot is only a filter: a reader (enter/enter_gen)
             * that passed its live-check just before it can still pin
             * afterwards, and its post-pin re-validation would pass as long
             * as `live` is still 1 -- handing it a fn_ptr into a .so we are
             * about to unload.  So store live=0 first; after that, any reader
             * that pins either shows up in the refs re-check below or sees
             * live==0 on re-validation and backs out without touching fn_ptr.
             *
             * This is a store-buffering (Dekker) pair: we store `live` then
             * load `refs`; the reader RMWs `refs` then loads `live`.
             * Release/acquire does NOT forbid both sides reading the stale
             * value, so all four accesses are seq_cst; the single total order
             * then guarantees at least one side observes the other.
             *
             * If a reader did pin in the window, leave the handle open: the
             * version is retired (no new reader can select it), and a later
             * stage reuses it as a free slot once those pins drain. */
            atomic_store_explicit(&old->live, 0, memory_order_seq_cst);
            if (atomic_load_explicit(&old->refs, memory_order_seq_cst) != 0)
                return -1;
        }
        /* A free slot can still hold the handle of a version retired while a
         * racing reader held it (the -1 above, on an earlier stage). */
        slot_dlclose(old->handle);
        old->handle = NULL;
    }

    MarchFnVersion *v = &s->ring[idx];
    /* Not live while its fields are rewritten (reclaim: retired above; fresh
     * or free: already 0). */
    atomic_store_explicit(&v->live, 0, memory_order_release);
    v->fn_ptr = fn_ptr;
    /* Do NOT reset `refs` here.  It is already 0 on a fresh (calloc'd) slot and
       was verified 0 on reclaim -- but a reader can still be mid-back-out
       (pinned, about to see live==0 and fetch_sub).  A plain store of 0 would
       erase its increment and its decrement would then wrap refs to
       UINT64_MAX, pinning the slot forever. */
    v->kind = kind;
    if (impl_hash) {
        strncpy(v->impl_hash, impl_hash, 64);
        v->impl_hash[64] = '\0';
    } else {
        v->impl_hash[0] = '\0';
    }
    if (sig_hash) {
        strncpy(v->sig_hash, sig_hash, 64);
        v->sig_hash[64] = '\0';
    } else {
        v->sig_hash[0] = '\0';
    }
    /* The epoch is written before the version can become live (commit's
       release store of `live` orders it), so enter_gen never selects this
       slot by its previous occupant's epoch (#551's fix, kept by
       construction). */
    atomic_store_explicit(&v->epoch, epoch, memory_order_relaxed);
    v->keep_for_older = 0;
    v->staged = 1;
    return idx;
}

void march_dispatch_commit(uint32_t name_id, uint32_t version) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return;
    MarchDispatchSlot *s = &g_slots[name_id];
    MarchFnVersion *v = &s->ring[version];
    if (!v->staged) return;
    v->staged = 0;
    /* The slot-level publication point: enter/enter_gen acquire-load `live`
       and only trust the slot once they observe this store. */
    atomic_store_explicit(&v->live, 1, memory_order_release);
    atomic_store_explicit(&s->current, version, memory_order_release);
}

void march_dispatch_set_keep_for_older(uint32_t name_id, uint32_t version) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return;
    g_slots[name_id].ring[version].keep_for_older = 1;
}

void march_dispatch_unstage(uint32_t name_id, uint32_t version) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return;
    MarchFnVersion *v = &g_slots[name_id].ring[version];
    if (!v->staged) return;
    v->staged = 0;
    v->handle = NULL;   /* the caller still owns (and closes) its handle */
}

/* epoch == NULL: a plain (epoch-less) publish, ring epoch 0 -- the baseline's
 * epoch.  Stage and commit in one step. */
static int publish_impl(uint32_t name_id, void *fn_ptr,
                        const char *impl_hash, const char *sig_hash,
                        uint8_t kind, const uint32_t *epoch) {
    int idx = march_dispatch_stage(name_id, fn_ptr, impl_hash, sig_hash, kind,
                                   epoch ? *epoch : 0);
    if (idx < 0) return -1;
    march_dispatch_commit(name_id, (uint32_t)idx);
    return idx;
}

int march_dispatch_publish(uint32_t name_id, void *fn_ptr,
                           const char *impl_hash, const char *sig_hash,
                           uint8_t kind) {
    return publish_impl(name_id, fn_ptr, impl_hash, sig_hash, kind, NULL);
}

void *march_dispatch_enter(uint32_t name_id, uint32_t *out_version) {
    /* Acquire-load the gate: a non-zero count synchronises-with the release
       store in march_dispatch_init, so g_slots below is guaranteed published. */
    if (name_id >= atomic_load_explicit(&g_n_slots, memory_order_acquire)) {
        if (out_version) *out_version = 0;
        return NULL;
    }
    MarchDispatchSlot *slots = atomic_load_explicit(&g_slots, memory_order_acquire);
    MarchDispatchSlot *s = &slots[name_id];
    uint32_t v = atomic_load_explicit(&s->current, memory_order_acquire);
    /* Publication gate.  During the startup warmup window a worker thread can
       reach this slot before its first march_dispatch_publish has run (or before
       that publish is visible to this thread): `current` and ring[0] are still
       calloc-zero, so a naive read returns fn_ptr == NULL and the generated call
       site jumps to address 0.  Acquire-load `live`; if the slot is not yet
       published, report version 0 and return NULL WITHOUT pinning — the caller's
       generated code falls back to a direct static call to the baseline symbol.
       The acquire here pairs with the release store of `live` in publish, so a
       live==1 observation guarantees fn_ptr and all fields are fully visible. */
    if (!atomic_load_explicit(&s->ring[v].live, memory_order_acquire)) {
        if (out_version) *out_version = 0;
        return NULL;
    }
    /* Pin before use, then re-validate: if a concurrent reclaim retired this
       slot between the live check and the pin, back out and fall back.  The
       pin and the re-validation are seq_cst because they form a Dekker pair
       with the reclaimer's retire-store/refs-load (see march_dispatch_publish):
       either the reclaimer sees our pin and keeps the .so open, or we see
       live==0 here and never read fn_ptr. */
    atomic_fetch_add_explicit(&s->ring[v].refs, 1, memory_order_seq_cst);
    if (!atomic_load_explicit(&s->ring[v].live, memory_order_seq_cst)) {
        atomic_fetch_sub_explicit(&s->ring[v].refs, 1, memory_order_acq_rel);
        if (out_version) *out_version = 0;
        return NULL;
    }
    if (out_version) *out_version = v;
    return s->ring[v].fn_ptr;
}

void *march_dispatch_enter_version(uint32_t name_id, uint32_t version,
                                   uint32_t *out_version) {
    if (out_version) *out_version = 0;
    if (name_id >= atomic_load_explicit(&g_n_slots, memory_order_acquire)
            || version >= MARCH_MAX_LIVE_VERSIONS)
        return NULL;
    MarchDispatchSlot *slots = atomic_load_explicit(&g_slots, memory_order_acquire);
    MarchFnVersion *v = &slots[name_id].ring[version];
    if (!atomic_load_explicit(&v->live, memory_order_acquire)) return NULL;
    /* Pin, then re-validate: the same seq_cst Dekker pair with the
       reclaimer's retire-store/refs-load as march_dispatch_enter. */
    atomic_fetch_add_explicit(&v->refs, 1, memory_order_seq_cst);
    if (!atomic_load_explicit(&v->live, memory_order_seq_cst)) {
        atomic_fetch_sub_explicit(&v->refs, 1, memory_order_acq_rel);
        return NULL;
    }
    if (out_version) *out_version = version;
    return v->fn_ptr;
}

void march_dispatch_leave(uint32_t name_id, uint32_t version) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return;
    atomic_fetch_sub_explicit(&g_slots[name_id].ring[version].refs, 1,
                              memory_order_acq_rel);
}

uint32_t march_dispatch_current(uint32_t name_id) {
    if (name_id >= g_n_slots) return 0;
    return atomic_load_explicit(&g_slots[name_id].current, memory_order_acquire);
}

uint64_t march_dispatch_refs(uint32_t name_id, uint32_t version) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return 0;
    return atomic_load_explicit(&g_slots[name_id].ring[version].refs,
                                memory_order_acquire);
}

const char *march_dispatch_impl_hash(uint32_t name_id, uint32_t version) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return NULL;
    return g_slots[name_id].ring[version].impl_hash;
}

const char *march_dispatch_sig_hash(uint32_t name_id, uint32_t version) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return NULL;
    return g_slots[name_id].ring[version].sig_hash;
}

const char *march_dispatch_baseline_hash(uint32_t name_id) {
    if (name_id >= g_n_slots) return NULL;
    return g_slots[name_id].baseline_impl_hash;
}

const char *march_dispatch_id_to_name(uint32_t name_id) {
    if (!g_id_to_name || name_id >= g_n_slots) return NULL;
    return g_id_to_name[name_id];
}

void march_dispatch_set_activation(uint32_t name_id, long long ts_ms,
                                    const char *signer_hex) {
    if (name_id >= g_n_slots) return;
    MarchDispatchSlot *s = &g_slots[name_id];
    s->activated_at_ms = ts_ms;
    if (signer_hex) {
        strncpy(s->signer_hex, signer_hex, 64);
        s->signer_hex[64] = '\0';
    } else {
        s->signer_hex[0] = '\0';
    }
}

long long march_dispatch_activated_at(uint32_t name_id) {
    if (name_id >= g_n_slots) return 0;
    return g_slots[name_id].activated_at_ms;
}

const char *march_dispatch_signer_hex(uint32_t name_id) {
    if (name_id >= g_n_slots) return NULL;
    return g_slots[name_id].signer_hex;
}

/* Phase 8: per-slot caller-set storage for coordinated upgrade gate. */
void march_dispatch_set_callers(uint32_t name_id, const char *callers_str) {
    if (name_id >= g_n_slots) return;
    free(g_slots[name_id].callers_str);
    g_slots[name_id].callers_str = (callers_str && callers_str[0])
        ? strdup(callers_str) : NULL;
}

const char *march_dispatch_callers(uint32_t name_id) {
    if (name_id >= g_n_slots) return NULL;
    return g_slots[name_id].callers_str;
}

/* Store the dlopen handle for a ring slot so it can be dlclosed when the slot
 * is reclaimed.  Called by the ACTIVATE handler after a successful publish.
 * Baseline publishes (from the main binary's startup code) never call this —
 * their slots keep handle = NULL (calloc'd to zero). */
void march_dispatch_set_handle(uint32_t name_id, uint32_t version, void *handle) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return;
    g_slots[name_id].ring[version].handle = handle;
}

/* Phase 9: publish with explicit epoch tag. */
int march_dispatch_publish_epoch(uint32_t name_id, void *fn_ptr,
                                 const char *impl_hash, const char *sig_hash,
                                 uint8_t kind, uint32_t epoch) {
    return publish_impl(name_id, fn_ptr, impl_hash, sig_hash, kind, &epoch);
}

/* Phase 9: read the deploy epoch stored in a ring slot version.
 * Used by VERSIONS_DETAIL to include the epoch in the server response. */
uint32_t march_dispatch_epoch(uint32_t name_id, uint32_t version) {
    if (name_id >= g_n_slots || version >= MARCH_MAX_LIVE_VERSIONS) return 0;
    return atomic_load_explicit(&g_slots[name_id].ring[version].epoch,
                                memory_order_relaxed);
}

/* Phase 9: epoch-aware enter.
 * Find the newest live slot whose epoch <= caller_epoch.
 * If caller_epoch == 0 or no such slot, fall back to march_dispatch_enter. */
void *march_dispatch_enter_gen(uint32_t name_id, uint32_t caller_epoch,
                               uint32_t *out_version) {
    if (caller_epoch == 0)
        return march_dispatch_enter(name_id, out_version);
    /* Acquire the publication gate (see march_dispatch_enter). */
    if (name_id >= atomic_load_explicit(&g_n_slots, memory_order_acquire)) {
        if (out_version) *out_version = 0;
        return NULL;
    }
    MarchDispatchSlot *slots = atomic_load_explicit(&g_slots, memory_order_acquire);
    MarchDispatchSlot *s = &slots[name_id];

    /* Scan the ring for the best match: live, epoch <= caller_epoch,
     * maximum epoch value.  MARCH_MAX_LIVE_VERSIONS iterations, no lock. */
    int    best_idx   = -1;
    uint32_t best_ep = 0;
    uint32_t cur = atomic_load_explicit(&s->current, memory_order_acquire);
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++) {
        /* Acquire-load `live`: same publication gate as march_dispatch_enter, so
           a slot's epoch/fn_ptr are only read once the publishing release-store
           of `live` is visible. */
        if (!atomic_load_explicit(&s->ring[i].live, memory_order_acquire)) continue;
        uint32_t ep = atomic_load_explicit(&s->ring[i].epoch, memory_order_relaxed);
        /* Equal epochs (epoch-less publishes all carry 0): the current
           version wins, so an epoch-less redeploy behaves as it always did. */
        if (ep <= caller_epoch
                && (best_idx < 0 || ep > best_ep || (ep == best_ep && i == cur))) {
            best_idx = (int)i;
            best_ep  = ep;
        }
    }
    if (best_idx < 0)
        return march_dispatch_enter(name_id, out_version);  /* no match: use current */

    uint32_t v = (uint32_t)best_idx;
    /* Pin, then re-validate (mirror of march_dispatch_enter, including the
       seq_cst Dekker pairing with the reclaimer): a concurrent reclaim that
       retired this slot means we must back out and fall back. */
    atomic_fetch_add_explicit(&s->ring[v].refs, 1, memory_order_seq_cst);
    /* ...and the slot must still hold the version it was SELECTED by: a
       reclaim can retire it, restage it with a newer epoch and commit it
       between the scan and the pin, and `live` alone would then accept the
       new occupant -- code from after the caller's epoch (the ABA twin of
       #551).  Epochs only grow, so an unchanged epoch is the same version.
       Unreachable for a caller that pins its epoch (the reclaim condition
       keeps the selected version), which every compiled unit does; this
       keeps enter_gen correct without that argument. */
    if (!atomic_load_explicit(&s->ring[v].live, memory_order_seq_cst)
            || atomic_load_explicit(&s->ring[v].epoch, memory_order_relaxed) != best_ep) {
        atomic_fetch_sub_explicit(&s->ring[v].refs, 1, memory_order_acq_rel);
        if (out_version) *out_version = 0;
        return NULL;
    }
    if (out_version) *out_version = v;
    return s->ring[v].fn_ptr;
}


/* ── The unified epoch model (see march_dispatch.h) ─────────────────────── */

/* Entry word: epoch in the high 32 bits, pinned-unit count in the low 32.
 * One atomic word per entry, so "is this entry still epoch E" and "take a
 * pin" are a single CAS. */
static inline uint32_t pin_epoch(uint64_t w) { return (uint32_t)(w >> 32); }
static inline uint32_t pin_count(uint64_t w) { return (uint32_t)w; }
static inline uint64_t pin_word(uint32_t e, uint32_t c) {
    return ((uint64_t)e << 32) | (uint64_t)c;
}

static _Atomic(uint64_t) g_epoch_pins[MARCH_EPOCH_PIN_SLOTS] = {
    ((uint64_t)MARCH_EPOCH_BASE << 32) | 1u    /* the current role's pin */
};
static _Atomic(uint32_t) g_current_epoch = MARCH_EPOCH_BASE;

uint32_t march_epoch_current(void) {
    return atomic_load_explicit(&g_current_epoch, memory_order_acquire);
}

uint32_t march_epoch_next(uint32_t requested) {
    uint32_t cur = march_epoch_current();
    return requested > cur ? requested : cur + 1;
}

int march_epoch_pin(uint32_t epoch) {
    if (!epoch) return -1;
    for (int i = 0; i < MARCH_EPOCH_PIN_SLOTS; i++) {
        uint64_t w = atomic_load_explicit(&g_epoch_pins[i], memory_order_acquire);
        while (pin_epoch(w) == epoch && pin_count(w) > 0) {
            if (atomic_compare_exchange_weak_explicit(
                    &g_epoch_pins[i], &w, w + 1,
                    memory_order_seq_cst, memory_order_acquire))
                return 0;
        }
    }
    return -1;
}

void march_epoch_unpin(uint32_t epoch) {
    if (!epoch) return;
    for (int i = 0; i < MARCH_EPOCH_PIN_SLOTS; i++) {
        uint64_t w = atomic_load_explicit(&g_epoch_pins[i], memory_order_acquire);
        while (pin_epoch(w) == epoch && pin_count(w) > 0) {
            if (atomic_compare_exchange_weak_explicit(
                    &g_epoch_pins[i], &w, w - 1,
                    memory_order_seq_cst, memory_order_acquire))
                return;
        }
    }
    fprintf(stderr, "march: epoch %u unpinned more times than pinned\n", epoch);
}

int64_t march_epoch_pins(uint32_t epoch) {
    for (int i = 0; i < MARCH_EPOCH_PIN_SLOTS; i++) {
        uint64_t w = atomic_load_explicit(&g_epoch_pins[i], memory_order_acquire);
        if (pin_epoch(w) == epoch && pin_count(w) > 0) return pin_count(w);
    }
    return 0;
}

int march_epoch_reserve(uint32_t epoch) {
    if (!epoch) return -1;
    for (int i = 0; i < MARCH_EPOCH_PIN_SLOTS; i++) {
        uint64_t w = atomic_load_explicit(&g_epoch_pins[i], memory_order_acquire);
        /* count 0: no holder, so no march_epoch_pin can race this CAS into a
           win (it requires count > 0). */
        if (pin_count(w) == 0
                && atomic_compare_exchange_strong_explicit(
                       &g_epoch_pins[i], &w, pin_word(epoch, 1),
                       memory_order_seq_cst, memory_order_acquire))
            return 0;
    }
    return -1;
}

void march_epoch_advance(uint32_t epoch) {
    uint32_t old = atomic_exchange_explicit(&g_current_epoch, epoch,
                                            memory_order_seq_cst);
    if (old != epoch) march_epoch_unpin(old);
}

int march_epoch_pin_table(uint32_t *epochs, int64_t *counts, int max) {
    int n = 0;
    for (int i = 0; i < MARCH_EPOCH_PIN_SLOTS && n < max; i++) {
        uint64_t w = atomic_load_explicit(&g_epoch_pins[i], memory_order_acquire);
        if (pin_count(w) == 0) continue;
        epochs[n] = pin_epoch(w);
        counts[n] = pin_count(w);
        n++;
    }
    return n;
}

int march_epoch_pinned_in(uint32_t lo, uint32_t hi) {
    for (int i = 0; i < MARCH_EPOCH_PIN_SLOTS; i++) {
        uint64_t w = atomic_load_explicit(&g_epoch_pins[i], memory_order_seq_cst);
        if (pin_count(w) == 0) continue;
        uint32_t e = pin_epoch(w);
        if (e >= lo && (hi == UINT32_MAX || e < hi)) return 1;
    }
    return 0;
}

void march_epoch_reset_for_test(void) {
    for (int i = 0; i < MARCH_EPOCH_PIN_SLOTS; i++)
        atomic_store_explicit(&g_epoch_pins[i], 0, memory_order_seq_cst);
    atomic_store_explicit(&g_epoch_pins[0], pin_word(MARCH_EPOCH_BASE, 1),
                          memory_order_seq_cst);
    atomic_store_explicit(&g_current_epoch, MARCH_EPOCH_BASE,
                          memory_order_seq_cst);
}

/* The running proc's code epoch.  The STRONG definition is in
 * march_scheduler.c; this WEAK one (0 = no proc, follow current) lets the
 * dispatch table link on its own (test/test_dispatch.c) -- the same weak
 * discipline as march_signal_drain in march_scheduler.c. */
__attribute__((weak)) uint32_t march_sched_current_epoch(void) { return 0; }

void *march_dispatch_enter_unit(uint32_t name_id, uint32_t *out_version) {
    return march_dispatch_enter_gen(name_id, march_sched_current_epoch(),
                                    out_version);
}

void march_dispatch_set_msg_schema_epoch(uint32_t name_id, uint32_t epoch) {
    if (name_id >= n_slots_relaxed()) return;
    atomic_store_explicit(&slots_relaxed()[name_id].msg_schema_epoch, epoch,
                          memory_order_release);
}

uint32_t march_dispatch_msg_schema_epoch(uint32_t name_id) {
    if (name_id >= atomic_load_explicit(&g_n_slots, memory_order_acquire)) return 0;
    MarchDispatchSlot *slots = atomic_load_explicit(&g_slots, memory_order_acquire);
    return atomic_load_explicit(&slots[name_id].msg_schema_epoch,
                                memory_order_acquire);
}
