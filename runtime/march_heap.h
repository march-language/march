#pragma once
/*
 * march_heap.h — Per-process bump-pointer arena allocator.
 *
 * Each March green-thread process owns a private march_heap_t.  All
 * allocation inside a process goes through march_process_alloc, which is a
 * simple pointer-bump with no locks and no synchronization.
 *
 * Memory layout of an arena block:
 *
 *   ┌──────────────────────────────────┐  ← march_heap_block *
 *   │ next ptr (8)                     │
 *   │ capacity (8)                     │
 *   │ used (8)                         │
 *   │ data[0] … data[capacity-1]       │
 *   └──────────────────────────────────┘
 *
 * Within data[], each allocation is preceded by a hidden march_alloc_meta
 * so the arena can be walked for GC:
 *
 *   ┌───────────────────────────────┐  ← returned by march_process_alloc
 *   │ alloc_size (u32)              │  ╮ march_alloc_meta
 *   │ n_fields   (u32)              │  ╯ (8 bytes, before user pointer)
 *   │ march_hdr  rc/tag/pad (16)    │  ╮ visible to caller
 *   │ field[0] … field[n-1] (n*8)  │  ╯
 *   └───────────────────────────────┘
 *
 * The pointer returned to the caller points to the march_hdr, not the
 * alloc_meta.  The GC uses ALLOC_META(p) to recover the meta.
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif

#include <stdint.h>
#include <stddef.h>

/* ── Tuning constants ──────────────────────────────────────────────────── */

/* Default arena block size (64 KiB).  Blocks grow by doubling up to
 * MARCH_HEAP_BLOCK_MAX.  For objects larger than the current block's
 * remaining space, a dedicated oversized block is allocated. */
#define MARCH_HEAP_BLOCK_MIN   (64u  * 1024u)
#define MARCH_HEAP_BLOCK_MAX   (4u   * 1024u * 1024u)

/* Semi-space GC is triggered when the ratio of dead bytes to total
 * allocated bytes exceeds this threshold. */
#define MARCH_HEAP_GC_THRESHOLD  0.50f

/* ── Per-allocation metadata (hidden, before user pointer) ─────────────── */

typedef struct {
    uint32_t alloc_size;   /* total bytes: sizeof(march_alloc_meta) + march_hdr + fields */
    uint32_t n_fields;     /* number of 8-byte fields after the 16-byte march_hdr        */
} march_alloc_meta;

/* Recover the alloc_meta from a user pointer (which points past the meta). */
#define MARCH_ALLOC_META(p)  ((march_alloc_meta *)((char *)(p) - sizeof(march_alloc_meta)))

/* Total allocation size given field count. */
#define MARCH_ALLOC_SIZE(n_fields)  \
    (sizeof(march_alloc_meta) + 16u + (unsigned)(n_fields) * 8u)

/* ── Arena block ───────────────────────────────────────────────────────── */

typedef struct march_heap_block {
    struct march_heap_block *next;
    size_t capacity;   /* usable bytes in data[] */
    size_t used;       /* bytes consumed so far  */
    char   data[];     /* bump-pointer arena      */
} march_heap_block;

/* ── Per-process heap ──────────────────────────────────────────────────── */

typedef struct {
    march_heap_block *current;       /* block being bumped into            */
    march_heap_block *blocks;        /* head of all-blocks list (for GC/destroy) */
    size_t            total_bytes;   /* sum of all block capacities        */
    size_t            used_bytes;    /* bytes allocated across all blocks  */
    size_t            live_bytes;    /* bytes with RC > 0 (updated by local decrc) */
    size_t            next_block_sz; /* size of next block to allocate     */
} march_heap_t;

/* ── Public API ────────────────────────────────────────────────────────── */

/* Initialise a heap struct.  Must be called once before any alloc. */
void   march_heap_init(march_heap_t *h);

/* Bump-allocate sz bytes (must equal 16 + n_fields*8) from the heap.
 * No locks, no synchronization — safe only from the owning process.
 * Returns a pointer to a zeroed march_hdr with rc=1. */
void  *march_process_alloc(march_heap_t *h, size_t sz);

/* Destroy the heap: frees all arena blocks in O(1) (one free per block). */
void   march_heap_destroy(march_heap_t *h);

/* Return 1 if the heap's fragmentation ratio exceeds the GC threshold. */
int    march_heap_should_gc(const march_heap_t *h);

/* Decrement the live_bytes counter by sz bytes (called by march_decrc_local
 * when an RC hits 0 on a process-local object). */
void   march_heap_record_death(march_heap_t *h, size_t sz);
