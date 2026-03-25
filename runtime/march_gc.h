#pragma once
/*
 * march_gc.h — Per-process semi-space copying collector.
 *
 * The GC is called when a process's heap fragmentation exceeds the threshold
 * defined in march_heap.h (MARCH_HEAP_GC_THRESHOLD).  It:
 *
 *  1. Allocates a new "to-space" arena of the same total capacity.
 *  2. Walks the "from-space" (all existing blocks).
 *  3. For each object with RC > 0 (live), copies it to to-space.
 *  4. Updates all intra-heap pointer fields using the forwarding map.
 *  5. Frees the from-space blocks (O(number_of_blocks)).
 *  6. Installs the to-space as the process's new heap.
 *
 * Key properties:
 *  - Never pauses other processes (per-process isolation).
 *  - Only runs when the owning process has yielded at a safe point.
 *  - Exact field layout: uses n_fields from march_alloc_meta and scans
 *    fields conservatively (address-range check prevents scalar corruption).
 *  - After collection, all objects are compacted into a fresh contiguous
 *    block with no fragmentation gaps.
 *
 * Limitations (intentional for Phase 5):
 *  - Does not scan the process stack (no pinning roots beyond the heap walk).
 *    The caller must ensure all stack roots have RC > 0 before calling the GC.
 *    In practice, Perceus RC ensures this: the RC reflects all live references.
 *  - String objects (tag = MARCH_STRING_TAG) are copied as opaque blobs;
 *    strings contain no internal pointers.
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif

#include <stddef.h>
#include "march_heap.h"

/* ── GC statistics (returned per collection) ───────────────────────────── */

typedef struct {
    size_t objects_scanned;   /* total objects visited in from-space    */
    size_t objects_copied;    /* live objects copied to to-space         */
    size_t bytes_before;      /* used_bytes before collection            */
    size_t bytes_after;       /* used_bytes after collection             */
    size_t blocks_freed;      /* number of arena blocks freed            */
} march_gc_stats;

/* ── Public API ────────────────────────────────────────────────────────── */

/*
 * Run a full semi-space collection on heap h.
 * Fills *stats (if non-NULL) with collection metrics.
 *
 * Precondition: the owning process must not be running (must be at a
 * scheduler safe point — i.e., yielded or blocked).
 *
 * Returns 0 on success, -1 on allocation failure during to-space setup.
 */
int march_gc_collect(march_heap_t *h, march_gc_stats *stats);
