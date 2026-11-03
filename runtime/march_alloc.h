/* march_alloc.h -- the allocator behind march_alloc().
 *
 * march_obj_malloc does NOT zero.  march_alloc writes the 16-byte header
 * itself and every caller writes every payload word before the object can be
 * read or RC-walked (audited 2026-10-02,
 * specs/progress/2026-10-02-march-alloc-malloc.md: calloc's zeroing was ~11%
 * of binary_trees).  A new caller that wants zeroed payload must store the
 * zeros itself; there is deliberately no zeroing entry point to reach for.
 *
 * Default build (MARCH_USE_MIMALLOC undefined): march_obj_malloc is plain
 * malloc and nothing else changes.  This is what the C unit-test harnesses,
 * the REPL/JIT runtime .so and every `--sanitize` build get.
 *
 * mimalloc build (-DMARCH_USE_MIMALLOC, set by the compile driver): March
 * objects are allocated from a statically linked, vendored mimalloc
 * (runtime/third_party/mimalloc).  libc malloc is NOT globally overridden
 * (a static override is not possible on macOS), so a pointer can come from
 * either allocator.  The driver therefore also passes
 *
 *     -Dfree=march_free_any -Drealloc=march_realloc_any
 *
 * on EVERY runtime and user-FFI translation unit.  Being command-line macros
 * they apply from the first token, so <stdlib.h>'s own `free`/`realloc`
 * declarations become declarations of the two functions defined in
 * march_runtime.c (same signatures), and every free()/realloc() call in C
 * routes by provenance (mi_is_in_heap_region): March objects reach mi_free
 * no matter which file frees them, and memory from strdup/getline/OpenSSL/...
 * still reaches libc free.
 *
 * Why not a force-included header: a header included before the TU's own
 * `#define _XOPEN_SOURCE` (march_scheduler.c needs it before any system
 * header) changes ucontext_t's layout between TUs.  Measured: every actor
 * program crashed.  This header must therefore never be force-included, and
 * must not be included before a TU's feature-test macros.
 *
 * Opt out at compile time with MARCH_MALLOC=libc in the environment.
 */
#ifndef MARCH_ALLOC_H
#define MARCH_ALLOC_H

#include <stddef.h>

#ifdef MARCH_USE_MIMALLOC

#include "third_party/mimalloc/include/mimalloc.h"

static inline void *march_obj_malloc(size_t n) { return mi_malloc(n); }

/* Declared by <stdlib.h> through the -D macros above; defined once, in
 * march_runtime.c (MARCH_ALLOC_DEFINE_SHIMS). */
void  march_free_any(void *p);
void *march_realloc_any(void *p, size_t n);

#ifdef MARCH_ALLOC_DEFINE_SHIMS
#include <stdatomic.h>
#include <stdint.h>
/* The real libc entry points, reached by symbol name because `free` and
 * `realloc` are macros in this TU. */
#define MARCH_ALLOC_STR2(x) #x
#define MARCH_ALLOC_STR(x) MARCH_ALLOC_STR2(x)
extern void  march_libc_free(void *)
    __asm__(MARCH_ALLOC_STR(__USER_LABEL_PREFIX__) "free");
extern void *march_libc_realloc(void *, size_t)
    __asm__(MARCH_ALLOC_STR(__USER_LABEL_PREFIX__) "realloc");

/* Fast path for the provenance test: the bounds of mimalloc's FIRST arena
 * (arena id 1), where every March object lives until the heap outgrows it
 * (mimalloc reserves 1 GiB arenas).  mi_is_in_heap_region is an out-of-line
 * walk of the arena table plus a segment-map lookup; for a pointer inside
 * arena 1 it answers yes by exactly this comparison
 * (_mi_arena_contains: start <= p < start + mi_arena_block_size(count), the
 * same span mi_arena_area reports), so testing it inline first changes no
 * answer, only the cost: ~10% of bench/binary_trees on an M3.
 *
 * The bounds are learnt lazily by whichever free first takes the slow path
 * after the arena exists, and are written with no ordering on purpose: the
 * unset state is the EMPTY range [UINTPTR_MAX, 0), so a reader that sees only
 * one of the two stores sees [lo, 0) or [UINTPTR_MAX, hi), both empty, and
 * falls back to the full test.  Arenas are never unmapped while the process
 * runs (mimalloc's destroy_on_exit is off), so the bounds never go stale. */
static _Atomic uintptr_t march_mi_arena_lo = UINTPTR_MAX;
static _Atomic uintptr_t march_mi_arena_hi = 0;

static inline int march_mi_in_first_arena(const void *p) {
    uintptr_t a = (uintptr_t)p;
    return a >= atomic_load_explicit(&march_mi_arena_lo, memory_order_relaxed)
        && a <  atomic_load_explicit(&march_mi_arena_hi, memory_order_relaxed);
}

__attribute__((noinline))
static int march_mi_owns_slow(const void *p) {
    if (!mi_is_in_heap_region(p)) return 0;
    if (atomic_load_explicit(&march_mi_arena_hi, memory_order_relaxed) == 0) {
        size_t sz = 0;
        void *start = mi_arena_area(1, &sz);
        if (start && sz) {
            atomic_store_explicit(&march_mi_arena_lo, (uintptr_t)start, memory_order_relaxed);
            atomic_store_explicit(&march_mi_arena_hi, (uintptr_t)start + sz, memory_order_relaxed);
        }
    }
    return 1;
}

__attribute__((noinline))
static void march_free_any_slow(void *p) {
    if (p && march_mi_owns_slow(p)) mi_free(p);
    else march_libc_free(p);
}

/* Both arms are tail calls, so an inlined free() needs no stack frame. */
void march_free_any(void *p) {
    if (__builtin_expect(march_mi_in_first_arena(p), 1)) mi_free(p);
    else march_free_any_slow(p);
}

void *march_realloc_any(void *p, size_t n) {
    if (march_mi_in_first_arena(p) || (p && march_mi_owns_slow(p)))
        return mi_realloc(p, n);
    return march_libc_realloc(p, n);
}
#endif /* MARCH_ALLOC_DEFINE_SHIMS */

#else

#include <stdlib.h>
static inline void *march_obj_malloc(size_t n) { return malloc(n); }

#endif /* MARCH_USE_MIMALLOC */

#endif /* MARCH_ALLOC_H */
