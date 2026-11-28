#ifndef MARCH_WASM_HEAP_H
#define MARCH_WASM_HEAP_H

#include <stddef.h>
#include <stdint.h>

void *march_alloc(int64_t size);

/* Collect at an embedder safepoint, after March returns and with no compiled
 * frames suspended. Supply every allocation the host retains, including
 * references in JS, static data, or storage owned by another allocator.
 * Roots and traced references must be exact allocation starts; traced
 * references must also be stored at a 4-byte boundary. The collector scans
 * all 32-bit payload words conservatively and never moves an allocation.
 * The roots array can be NULL when count is zero. */
void march_wasm_heap_collect(void *const *roots, size_t count);

/* Aligned payload bytes retained by the most recent collection. */
uint32_t march_wasm_heap_live_bytes(void);

/* Runtime hook for the immortal header of a cached string literal. Call once
 * with a fresh allocation. */
void march_wasm_heap_pin_literal(void *allocation);

#endif
