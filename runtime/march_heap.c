/*
 * march_heap.c — Per-process bump-pointer arena allocator.
 *
 * See march_heap.h for design notes.
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif

#include "march_heap.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ── march_hdr — duplicated from march_runtime.h to avoid a circular dep ── */
/* Object header layout (offsets 0–15):
 *   0: int64_t  rc   (reference count, initialized to 1)
 *   8: int32_t  tag  (constructor tag)
 *  12: int32_t  pad  (alignment padding)
 */
typedef struct { int64_t rc; int32_t tag; int32_t pad; } mh_hdr;

/* ── Internal helpers ──────────────────────────────────────────────────── */

static march_heap_block *block_new(size_t capacity) {
    march_heap_block *b = (march_heap_block *)malloc(
        sizeof(march_heap_block) + capacity);
    if (!b) {
        fputs("march_heap: out of memory allocating arena block\n", stderr);
        exit(1);
    }
    b->next     = NULL;
    b->capacity = capacity;
    b->used     = 0;
    return b;
}

/* ── march_heap_init ───────────────────────────────────────────────────── */

void march_heap_init(march_heap_t *h) {
    march_heap_block *b = block_new(MARCH_HEAP_BLOCK_MIN);
    h->blocks        = b;
    h->current       = b;
    h->total_bytes   = MARCH_HEAP_BLOCK_MIN;
    h->used_bytes    = 0;
    h->live_bytes    = 0;
    h->next_block_sz = MARCH_HEAP_BLOCK_MIN * 2;
    if (h->next_block_sz > MARCH_HEAP_BLOCK_MAX)
        h->next_block_sz = MARCH_HEAP_BLOCK_MAX;
}

/* ── march_process_alloc ───────────────────────────────────────────────── */

void *march_process_alloc(march_heap_t *h, size_t sz) {
    /* sz is the user-visible object size (march_hdr + fields, typically
     * 16 + n_fields*8).  We prepend a hidden march_alloc_meta. */
    size_t total = sizeof(march_alloc_meta) + sz;

    /* Align total to 8 bytes (all march objects are 8-byte aligned). */
    total = (total + 7u) & ~7u;

    march_heap_block *blk = h->current;

    /* Try to fit in the current block. */
    if (blk->used + total > blk->capacity) {
        /* Allocate a new block.  For oversized objects, make the block
         * exactly large enough; otherwise use the doubling policy. */
        size_t new_cap = h->next_block_sz;
        if (total > new_cap) new_cap = total;

        march_heap_block *nb = block_new(new_cap);

        /* Link new block at front of list and make it current. */
        nb->next     = h->blocks;
        h->blocks    = nb;
        h->current   = nb;
        h->total_bytes  += new_cap;

        /* Double next block size (capped). */
        h->next_block_sz *= 2;
        if (h->next_block_sz > MARCH_HEAP_BLOCK_MAX)
            h->next_block_sz = MARCH_HEAP_BLOCK_MAX;

        blk = nb;
    }

    /* Bump the pointer. */
    char *raw = blk->data + blk->used;
    blk->used        += total;
    h->used_bytes    += total;
    h->live_bytes    += total;

    /* Write the hidden metadata. */
    march_alloc_meta *meta = (march_alloc_meta *)raw;
    meta->alloc_size = (uint32_t)total;
    meta->n_fields   = (sz >= 16u) ? (uint32_t)((sz - 16u) / 8u) : 0u;

    /* Zero-initialize and set rc=1. */
    void *p = raw + sizeof(march_alloc_meta);
    memset(p, 0, sz);
    ((mh_hdr *)p)->rc = 1;

    return p;
}

/* ── march_heap_destroy ────────────────────────────────────────────────── */

void march_heap_destroy(march_heap_t *h) {
    /* Walk the block list and free each one.  O(number_of_blocks), not
     * O(number_of_objects) — this is the key win over per-object free. */
    march_heap_block *b = h->blocks;
    while (b) {
        march_heap_block *next = b->next;
        free(b);
        b = next;
    }
    h->blocks      = NULL;
    h->current     = NULL;
    h->total_bytes = 0;
    h->used_bytes  = 0;
    h->live_bytes  = 0;
}

/* ── march_heap_should_gc ──────────────────────────────────────────────── */

int march_heap_should_gc(const march_heap_t *h) {
    if (h->used_bytes == 0) return 0;
    /* dead_bytes = used_bytes - live_bytes (clamped to 0 for safety). */
    size_t dead = (h->used_bytes > h->live_bytes)
                  ? (h->used_bytes - h->live_bytes) : 0u;
    return (float)dead / (float)h->used_bytes >= MARCH_HEAP_GC_THRESHOLD;
}

/* ── march_heap_record_death ───────────────────────────────────────────── */

void march_heap_record_death(march_heap_t *h, size_t sz) {
    /* Called when a process-local object's RC hits 0.  We record that
     * live_bytes decreased so should_gc can detect fragmentation. */
    size_t total = (sizeof(march_alloc_meta) + sz + 7u) & ~7u;
    if (h->live_bytes >= total)
        h->live_bytes -= total;
    else
        h->live_bytes = 0;
}
