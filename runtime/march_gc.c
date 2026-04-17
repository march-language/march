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
/* MARCH_STRING_TAG is reserved by the design notes for opaque-blob strings
 * that should be copied without scanning fields.  At present no allocation
 * path sets the tag to -1: march_string_lit uses plain malloc (so strings
 * never live in a per-process arena), and march_message.c::copy_string
 * overwrites the standard header in-place without re-tagging.  The check
 * below is therefore dead under the current runtime, but is kept so the
 * GC stays correct if a future allocator routes strings through this
 * arena and tags them. */
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

/* Abort with a diagnostic on a corrupt allocation header.  The previous
 * behaviour (silent `break`) silently dropped every object after the
 * corrupted one from pass 1's live set — turning a localised heap-corruption
 * bug into a process-wide use-after-free at teardown.  Aborting surfaces
 * the bug at the point of detection. */
static void gc_corrupt(const march_heap_block *blk, const char *p,
                        const march_alloc_meta *meta, const char *why) {
    fprintf(stderr,
            "march_gc: corrupted allocation meta at %p (block %p, used=%zu, cap=%zu): "
            "alloc_size=%u, n_fields=%u — %s\n",
            (const void *)p, (const void *)blk,
            (size_t)blk->used, (size_t)blk->capacity,
            (unsigned)meta->alloc_size, (unsigned)meta->n_fields, why);
    abort();
}

static void walk_block(const march_heap_block *blk, block_visitor visit, void *ctx) {
    const char *p   = blk->data;
    const char *end = blk->data + blk->used;
    while (p < end) {
        const march_alloc_meta *meta = (const march_alloc_meta *)p;
        uint32_t total = meta->alloc_size;
        /* Lower bound: header + (alloc_meta + march_hdr).  Upper bound: must
         * fit inside the remaining block bytes (not just the block capacity —
         * an oversized object would overshoot the bumped portion). */
        if (total < sizeof(march_alloc_meta) + 16u)
            gc_corrupt(blk, p, meta, "alloc_size below minimum object size");
        if ((size_t)total > (size_t)(end - p))
            gc_corrupt(blk, p, meta, "alloc_size overruns block tail");
        /* Bounds-check n_fields: payload bytes available is
         * total - sizeof(meta) - 16 (header), divided by 8 per field. */
        size_t payload_bytes = (size_t)total - sizeof(march_alloc_meta) - 16u;
        if ((size_t)meta->n_fields * 8u > payload_bytes)
            gc_corrupt(blk, p, meta, "n_fields exceeds payload size");
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

    if (fwd_insert(ctx->fwd, obj, copy) != 0) {
        /* Allocation failure inside the forwarding table.  Without this guard
         * the missing entry would cause pass 2 to leave a dangling pointer in
         * a live object — silent use-after-free at teardown.  Surface it. */
        fputs("march_gc: forwarding table allocation failure during pass 1 — aborting\n",
              stderr);
        abort();
    }
    ctx->stats->objects_copied++;
}

/* ── Pass 2 context ──────────────────────────────────────────────────────── */

/* From-space block address range — used by pass 2 to distinguish dangling
 * intra-arena references (which must abort) from out-of-arena pointers such
 * as malloc'd march_string buffers (which legitimately have no fwd entry). */
typedef struct {
    const char *lo;
    const char *hi;
} gc_block_range;

typedef struct {
    gc_fwd_table   *fwd;
    gc_block_range *from_ranges;
    size_t          from_n;
} pass2_ctx;

static int gc_in_from_space(const pass2_ctx *ctx, const void *p) {
    const char *cp = (const char *)p;
    for (size_t i = 0; i < ctx->from_n; i++) {
        if (cp >= ctx->from_ranges[i].lo && cp < ctx->from_ranges[i].hi)
            return 1;
    }
    return 0;
}

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
        } else if (gc_in_from_space(ctx, fv)) {
            /* The pointer falls inside a from-space arena block but no live
             * object was copied there.  Either the source object had rc <= 0
             * (Perceus invariant violation: a live object holds a reference
             * to one whose RC was supposedly zero) or its meta was corrupt.
             * Either way the from-space buffer is about to be freed, and
             * leaving the pointer in place would create a dangling reference
             * that surfaces as a use-after-free much later.  Abort here so
             * the bug is surfaced at the moment of detection. */
            fprintf(stderr,
                    "march_gc: dangling intra-arena pointer %p in object %p "
                    "(field %u): no forwarding entry — Perceus RC invariant violation\n",
                    fv, (void *)obj, (unsigned)i);
            abort();
        }
        /* Otherwise the pointer is outside the arena (e.g. malloc'd
         * march_string) — leave it untouched. */
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
    /* Snapshot from-space block address ranges first.  Pass 2 needs them to
     * tell intra-arena dangling pointers (which must abort) from out-of-arena
     * pointers such as malloc'd march_strings (which have no fwd entry by
     * design and must be left untouched). */
    size_t n_from = 0;
    for (march_heap_block *blk = h->blocks; blk; blk = blk->next) n_from++;
    gc_block_range *from_ranges = NULL;
    if (n_from) {
        from_ranges = (gc_block_range *)calloc(n_from, sizeof(*from_ranges));
        if (!from_ranges) {
            fwd_free(&fwd);
            march_heap_destroy(&to_heap);
            return -1;
        }
        size_t i = 0;
        for (march_heap_block *blk = h->blocks; blk; blk = blk->next) {
            from_ranges[i].lo = blk->data;
            from_ranges[i].hi = blk->data + blk->used;
            i++;
        }
    }

    pass1_ctx p1 = { &to_heap, &fwd, stats };
    for (march_heap_block *blk = h->blocks; blk; blk = blk->next) {
        walk_block(blk, pass1_visit, &p1);
        stats->blocks_freed++;
    }

    /* ── Pass 2: update pointer fields in to-space ──────────────── */
    pass2_ctx p2 = { &fwd, from_ranges, n_from };
    for (march_heap_block *blk = to_heap.blocks; blk; blk = blk->next) {
        walk_block(blk, pass2_visit, &p2);
    }

    free(from_ranges);
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
