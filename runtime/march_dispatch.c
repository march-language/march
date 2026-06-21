/* march_dispatch.c — Hot Code Reload versioned dispatch table (HCR Phase 2).
 * See march_dispatch.h and specs/hot-code-reload.md Part 3. */
#include "march_dispatch.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    void              *fn_ptr;          /* native code or trampoline thunk */
    _Atomic(uint64_t)  refs;            /* callers currently pinned to THIS version */
    char               impl_hash[65];   /* 64 hex chars + NUL */
    uint8_t            kind;            /* MARCH_NATIVE | MARCH_TRAMPOLINE */
    uint8_t            live;           /* 1 once this ring slot holds a version */
} MarchFnVersion;

typedef struct {
    _Atomic(uint32_t) current;                        /* live ring index */
    MarchFnVersion    ring[MARCH_MAX_LIVE_VERSIONS];
} MarchDispatchSlot;

static MarchDispatchSlot *g_slots = NULL;
static uint32_t           g_n_slots = 0;

void march_dispatch_init(uint32_t n_slots) {
    march_dispatch_shutdown();
    g_slots = (MarchDispatchSlot *)calloc(n_slots, sizeof(MarchDispatchSlot));
    g_n_slots = g_slots ? n_slots : 0;
}

void march_dispatch_shutdown(void) {
    free(g_slots);
    g_slots = NULL;
    g_n_slots = 0;
}

int march_dispatch_publish(uint32_t name_id, void *fn_ptr,
                           const char *impl_hash, uint8_t kind) {
    if (name_id >= g_n_slots) return -1;
    MarchDispatchSlot *s = &g_slots[name_id];
    uint32_t cur = atomic_load_explicit(&s->current, memory_order_acquire);

    int any_live = 0;
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++)
        if (s->ring[i].live) { any_live = 1; break; }

    int idx;
    if (!any_live) {
        idx = 0;  /* first publish into a fresh slot */
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
    }

    MarchFnVersion *v = &s->ring[idx];
    v->fn_ptr = fn_ptr;
    atomic_store_explicit(&v->refs, 0, memory_order_relaxed);
    v->kind = kind;
    v->live = 1;
    if (impl_hash) {
        strncpy(v->impl_hash, impl_hash, 64);
        v->impl_hash[64] = '\0';
    } else {
        v->impl_hash[0] = '\0';
    }
    /* Publish with release so a reader that acquires `current` sees the fully
       initialised version. */
    atomic_store_explicit(&s->current, (uint32_t)idx, memory_order_release);
    return idx;
}

void *march_dispatch_enter(uint32_t name_id, uint32_t *out_version) {
    if (name_id >= g_n_slots) {
        if (out_version) *out_version = 0;
        return NULL;
    }
    MarchDispatchSlot *s = &g_slots[name_id];
    uint32_t v = atomic_load_explicit(&s->current, memory_order_acquire);
    /* Pin before use. The publish path only reclaims a slot with refs == 0, so
       a fully-safe reclaim against this read needs epoch/grace reclamation
       (a later phase); single-version steady state and the test path are
       correct as-is. */
    atomic_fetch_add_explicit(&s->ring[v].refs, 1, memory_order_acq_rel);
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
