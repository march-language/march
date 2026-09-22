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
} MarchFnVersion;

typedef struct {
    _Atomic(uint32_t) current;                        /* live ring index */
    MarchFnVersion    ring[MARCH_MAX_LIVE_VERSIONS];
    char              baseline_impl_hash[65];          /* Phase 4: set on first publish, never changed */
    long long         activated_at_ms;                 /* Phase 7: Unix ms of last ACTIVATE */
    char              signer_hex[65];                  /* Phase 7: pubkey hex of last ACTIVATE signer */
    char             *callers_str;                     /* Phase 8: comma-separated caller names, or NULL */
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

/* epoch == NULL: leave the ring slot's epoch as it is (plain publish). */
static int publish_impl(uint32_t name_id, void *fn_ptr,
                        const char *impl_hash, const char *sig_hash,
                        uint8_t kind, const uint32_t *epoch) {
    if (name_id >= g_n_slots) return -1;
    MarchDispatchSlot *s = &g_slots[name_id];
    uint32_t cur = atomic_load_explicit(&s->current, memory_order_acquire);

    int any_live = 0;
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++)
        if (atomic_load_explicit(&s->ring[i].live, memory_order_relaxed))
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
        /* Reclaim a ring slot that is neither current nor pinned. With a cap of
           2 this is "the other slot, iff its refs have drained". No free slot
           means every live version is still in use -> caller must purge. */
        idx = -1;
        for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++) {
            if (i == cur) continue;
            if (atomic_load_explicit(&s->ring[i].refs, memory_order_acquire) == 0) {
                idx = (int)i;
                break;
            }
        }
        if (idx < 0) return -1;
        MarchFnVersion *old = &s->ring[idx];
        /* Retire, THEN re-check refs, THEN dlclose.  The refs==0 test above is
         * only a filter: a reader (enter/enter_gen) that passed its live-check
         * just before it can still pin afterwards, and its post-pin re-validation
         * would pass as long as `live` is still 1 — handing it a fn_ptr into a
         * .so we are about to unload.  So store live=0 first; after that, any
         * reader that pins either shows up in the refs re-check below or sees
         * live==0 on re-validation and backs out without touching fn_ptr.
         *
         * This is a store-buffering (Dekker) pair: we store `live` then load
         * `refs`; the reader RMWs `refs` then loads `live`.  Release/acquire does
         * NOT forbid both sides reading the stale value (each load may be
         * satisfied before the other thread's store is visible), so all four
         * accesses are seq_cst; the single total order then guarantees at least
         * one side observes the other.  The reader-side seq_cst costs nothing
         * extra on x86 (lock xadd / plain mov) or AArch64 (ldaddal / ldar).
         *
         * If a reader did pin in the window, leave the handle open: the version
         * is retired (no new reader can select it), and the next publish reclaims
         * it once those pins drain.  This keeps one .so mapped a little longer in
         * the racing case, which beats unmapping code under a caller.  The full
         * fix — epoch/grace reclamation, so the reclaimer never needs a racing
         * reader to back out — is not built yet. */
        atomic_store_explicit(&old->live, 0, memory_order_seq_cst);
        if (atomic_load_explicit(&old->refs, memory_order_seq_cst) != 0)
            return -1;
        slot_dlclose(old->handle);
        old->handle = NULL;
    }

    MarchFnVersion *v = &s->ring[idx];
    /* Reclaim case: already retired above.  Fresh slot: already 0.  The store is
       kept so the slot is provably not live while its fields are rewritten. */
    atomic_store_explicit(&v->live, 0, memory_order_release);
    v->fn_ptr = fn_ptr;
    /* Do NOT reset `refs` here.  It is already 0 on a fresh (calloc'd) slot and
       was verified 0 on reclaim — but a reader can still be mid-back-out (pinned,
       about to see live==0 and fetch_sub).  A plain store of 0 would erase its
       increment and its decrement would then wrap refs to UINT64_MAX, pinning
       the slot forever. */
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
    /* Stamp the epoch BEFORE the publication store, so enter_gen never selects
       this slot by its previous occupant's epoch. */
    if (epoch)
        atomic_store_explicit(&v->epoch, *epoch, memory_order_relaxed);
    /* Mark the slot live with a release store AFTER every field (fn_ptr, kind,
       hashes) is written.  This is the slot-level publication point: enter/
       enter_gen acquire-load `live` and only trust the slot once they observe
       this store, so they can never read a zeroed or half-initialised slot. */
    atomic_store_explicit(&v->live, 1, memory_order_release);
    /* Publish with release so a reader that acquires `current` sees the fully
       initialised version. */
    atomic_store_explicit(&s->current, (uint32_t)idx, memory_order_release);
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

    /* Scan the 2-slot ring for the best match: live, epoch <= caller_epoch,
     * maximum epoch value.  This is 2 iterations, no lock needed. */
    int    best_idx   = -1;
    uint32_t best_ep = 0;
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++) {
        /* Acquire-load `live`: same publication gate as march_dispatch_enter, so
           a slot's epoch/fn_ptr are only read once the publishing release-store
           of `live` is visible. */
        if (!atomic_load_explicit(&s->ring[i].live, memory_order_acquire)) continue;
        uint32_t ep = atomic_load_explicit(&s->ring[i].epoch, memory_order_relaxed);
        if (ep <= caller_epoch && (best_idx < 0 || ep > best_ep)) {
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
    if (!atomic_load_explicit(&s->ring[v].live, memory_order_seq_cst)) {
        atomic_fetch_sub_explicit(&s->ring[v].refs, 1, memory_order_acq_rel);
        if (out_version) *out_version = 0;
        return NULL;
    }
    if (out_version) *out_version = v;
    return s->ring[v].fn_ptr;
}
