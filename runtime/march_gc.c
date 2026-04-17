/*
 * march_gc.c — Per-process semi-space copying collector.
 *
 * See march_gc.h for design notes.
 *
 * Algorithm overview:
 *
 *   Pass 1 — Scan from-space:
 *     Walk every arena block in old heap.  For each object:
 *       - If RC == 0: dead — skip.
 *       - If RC > 0: live — copy to to_heap via march_process_alloc.
 *         Record (src_ptr → dst_ptr) in a forwarding table.
 *
 *   Pass 2 — Fix up pointers:
 *     Walk to_heap objects.  For each pointer-sized field:
 *       - If the field value exists in the forwarding table, update it.
 *       - Fields that are unboxed scalars won't be in the table, so they
 *         pass through unchanged (conservative safety: we only update
 *         values we know are pointers because we saw them during Pass 1).
 *
 *   Teardown:
 *     Free all from-space blocks.  Install to_heap as the new heap.
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif

#include "march_gc.h"
#include "march_heap.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ── Internal types ──────────────────────────────────────────────────────── */

typedef struct { int64_t rc; int32_t tag; int32_t pad; } gc_hdr;
#define MARCH_STRING_TAG  (-1)

/* Mirror of IS_HEAP_PTR in march_runtime.h.  Polymorphic containers store
 * tagged immediates in the same fields as heap pointers: tagged integers
 * have the low bit set ((n << 1) | 1), heap pointers (8-byte aligned) have
 * the low bit clear.  Negative values are never valid user-space addresses
 * on any 64-bit ABI. */
#define GC_IS_HEAP_PTR(p) \
    (((uintptr_t)(p) & 1u) == 0 && \
     (uintptr_t)(p) >= 4096u    && \
     (intptr_t)(p)  > 0)

/* ── Forwarding table (open-addressing hash map, power-of-two size) ──────── */

typedef struct {
    void *from;
    void *to;
} gc_fwd_entry;

typedef struct {
    gc_fwd_entry *entries;
    size_t        cap;
    size_t        count;
} gc_fwd_table;

static int fwd_init(gc_fwd_table *t, size_t initial_cap) {
    t->entries = (gc_fwd_entry *)calloc(initial_cap, sizeof(gc_fwd_entry));
    if (!t->entries) return -1;
    t->cap   = initial_cap;
    t->count = 0;
    return 0;
}

static void fwd_free(gc_fwd_table *t) {
    free(t->entries);
    t->entries = NULL;
}

static int fwd_grow(gc_fwd_table *t) {
    size_t new_cap = t->cap * 2;
    gc_fwd_entry *new_entries = (gc_fwd_entry *)calloc(new_cap, sizeof(gc_fwd_entry));
    if (!new_entries) return -1;
    for (size_t i = 0; i < t->cap; i++) {
        if (!t->entries[i].from) continue;
        size_t h = (size_t)((uintptr_t)t->entries[i].from * 2654435761u)
                   & (new_cap - 1);
        for (size_t j = 0; j < new_cap; j++) {
            size_t idx = (h + j) & (new_cap - 1);
            if (!new_entries[idx].from) {
                new_entries[idx] = t->entries[i];
                break;
            }
        }
    }
    free(t->entries);
    t->entries = new_entries;
    t->cap     = new_cap;
    return 0;
}

static int fwd_insert(gc_fwd_table *t, void *from, void *to) {
    if (t->count * 2 >= t->cap) {
        if (fwd_grow(t) != 0) return -1;
    }
    size_t h = (size_t)((uintptr_t)from * 2654435761u) & (t->cap - 1);
    for (size_t i = 0; i < t->cap; i++) {
        size_t idx = (h + i) & (t->cap - 1);
        if (!t->entries[idx].from) {
            t->entries[idx].from = from;
            t->entries[idx].to   = to;
            t->count++;
            return 0;
        }
    }
    return -1;
}

static void *fwd_lookup(const gc_fwd_table *t, void *from) {
    if (!t->count) return NULL;
    size_t h = (size_t)((uintptr_t)from * 2654435761u) & (t->cap - 1);
    for (size_t i = 0; i < t->cap; i++) {
        size_t idx = (h + i) & (t->cap - 1);
        if (!t->entries[idx].from) return NULL;
        if (t->entries[idx].from == from) return t->entries[idx].to;
    }
    return NULL;
}

/* ── Walk helpers ────────────────────────────────────────────────────────── */

/*
 * Iterate over every object in a heap block.
 * The heap layout within data[] is:
 *   [alloc_meta (8 bytes)] [march_hdr + fields (alloc_size - 8 bytes)]
 * Each entry is padded to 8-byte alignment and the total size is stored in
 * alloc_meta.alloc_size.
 */
typedef void (*block_visitor)(void *obj, uint32_t alloc_size, uint32_t n_fields,
                               void *ctx);

static void walk_block(const march_heap_block *blk, block_visitor visit, void *ctx) {
    const char *p   = blk->data;
    const char *end = blk->data + blk->used;
    while (p < end) {
        const march_alloc_meta *meta = (const march_alloc_meta *)p;
        uint32_t total = meta->alloc_size;
        if (total < sizeof(march_alloc_meta) + 16u || total > blk->capacity) break;
        void *obj = (void *)(p + sizeof(march_alloc_meta));
        visit(obj, total, meta->n_fields, ctx);
        p += total;
    }
}

/* ── Pass 1 context ──────────────────────────────────────────────────────── */

typedef struct {
    march_heap_t  *to_heap;
    gc_fwd_table  *fwd;
    march_gc_stats *stats;
} pass1_ctx;

static void pass1_visit(void *obj, uint32_t alloc_size, uint32_t n_fields,
                        void *ctx_) {
    pass1_ctx *ctx = (pass1_ctx *)ctx_;
    ctx->stats->objects_scanned++;

    gc_hdr *h = (gc_hdr *)obj;
    if (h->rc <= 0) return;   /* dead — skip */

    /* Compute user-visible size (without alloc_meta prefix). */
    size_t user_sz = alloc_size - (uint32_t)sizeof(march_alloc_meta);
    if (user_sz < 16u) user_sz = 16u;

    /* Allocate in to-space and copy. */
    void *copy = march_process_alloc(ctx->to_heap, user_sz);
    memcpy(copy, obj, user_sz);
    ((gc_hdr *)copy)->rc = h->rc;   /* preserve RC */

    /* Update n_fields in the to-space meta to match. */
    march_alloc_meta *to_meta = MARCH_ALLOC_META(copy);
    to_meta->n_fields = n_fields;

    fwd_insert(ctx->fwd, obj, copy);
    ctx->stats->objects_copied++;
}

/* ── Pass 2 context ──────────────────────────────────────────────────────── */

typedef struct {
    gc_fwd_table *fwd;
} pass2_ctx;

static void pass2_visit(void *obj, uint32_t alloc_size, uint32_t n_fields,
                        void *ctx_) {
    (void)alloc_size;
    pass2_ctx *ctx = (pass2_ctx *)ctx_;
    gc_hdr *h = (gc_hdr *)obj;
    if (h->rc <= 0) return;

    /* Strings have no pointer fields. */
    if (h->tag == MARCH_STRING_TAG) return;

    int64_t *fields = (int64_t *)((char *)obj + 16);
    for (uint32_t i = 0; i < n_fields; i++) {
        void *fv = (void *)(uintptr_t)(uint64_t)fields[i];
        /* Skip tagged immediates (low bit set), low addresses, and negative
         * values (never valid heap addresses).  Without this guard, a tagged
         * integer such as ((42 << 1) | 1) could match a real from-space
         * address in fwd_lookup and be silently rewritten to a pointer. */
        if (!GC_IS_HEAP_PTR(fv)) continue;
        void *new_fv = fwd_lookup(ctx->fwd, fv);
        if (new_fv) {
            fields[i] = (int64_t)(uintptr_t)new_fv;
        }
    }
}

/* ── march_gc_collect ────────────────────────────────────────────────────── */

int march_gc_collect(march_heap_t *h, march_gc_stats *stats) {
    march_gc_stats local_stats = {0, 0, 0, 0, 0};
    if (!stats) stats = &local_stats;

    /* Zero-initialize caller's stats struct before use. */
    stats->objects_scanned = 0;
    stats->objects_copied  = 0;
    stats->bytes_before    = 0;
    stats->bytes_after     = 0;
    stats->blocks_freed    = 0;

    stats->bytes_before = h->used_bytes;

    /* Estimate number of live objects for initial forwarding table capacity.
     * Assume average object is 64 bytes; round up to next power of two. */
    size_t estimated_live = h->live_bytes / 64 + 16;
    size_t fwd_cap = 16;
    while (fwd_cap < estimated_live) fwd_cap <<= 1;

    gc_fwd_table fwd;
    if (fwd_init(&fwd, fwd_cap) != 0) return -1;

    /* Initialise to-space heap with capacity = current live_bytes (+ 25% slack). */
    size_t to_cap = h->live_bytes + h->live_bytes / 4;
    if (to_cap < MARCH_HEAP_BLOCK_MIN) to_cap = MARCH_HEAP_BLOCK_MIN;

    march_heap_t to_heap;
    march_heap_init(&to_heap);

    /* ── Pass 1: copy live objects from from-space to to-space ──── */
    pass1_ctx p1 = { &to_heap, &fwd, stats };
    for (march_heap_block *blk = h->blocks; blk; blk = blk->next) {
        walk_block(blk, pass1_visit, &p1);
        stats->blocks_freed++;
    }

    /* ── Pass 2: update pointer fields in to-space ──────────────── */
    pass2_ctx p2 = { &fwd };
    for (march_heap_block *blk = to_heap.blocks; blk; blk = blk->next) {
        walk_block(blk, pass2_visit, &p2);
    }

    fwd_free(&fwd);

    /* ── Teardown: free old from-space blocks ───────────────────── */
    {
        march_heap_block *blk = h->blocks;
        while (blk) {
            march_heap_block *nx = blk->next;
            free(blk);
            blk = nx;
        }
    }

    /* Install to-space as the new heap. */
    *h = to_heap;

    /* live_bytes == used_bytes after a perfect compaction
     * (only live objects were copied). */
    h->live_bytes = h->used_bytes;

    stats->bytes_after = h->used_bytes;

    return 0;
}
