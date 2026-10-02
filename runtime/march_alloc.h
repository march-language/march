/* march_alloc.h -- the allocator behind march_alloc().
 *
 * Default build (MARCH_USE_MIMALLOC undefined): march_obj_calloc is plain
 * calloc and nothing else changes.  This is what the C unit-test harnesses,
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

static inline void *march_obj_calloc(size_t n) { return mi_calloc(1, n); }

/* Declared by <stdlib.h> through the -D macros above; defined once, in
 * march_runtime.c (MARCH_ALLOC_DEFINE_SHIMS). */
void  march_free_any(void *p);
void *march_realloc_any(void *p, size_t n);

#ifdef MARCH_ALLOC_DEFINE_SHIMS
/* The real libc entry points, reached by symbol name because `free` and
 * `realloc` are macros in this TU. */
#define MARCH_ALLOC_STR2(x) #x
#define MARCH_ALLOC_STR(x) MARCH_ALLOC_STR2(x)
extern void  march_libc_free(void *)
    __asm__(MARCH_ALLOC_STR(__USER_LABEL_PREFIX__) "free");
extern void *march_libc_realloc(void *, size_t)
    __asm__(MARCH_ALLOC_STR(__USER_LABEL_PREFIX__) "realloc");

void march_free_any(void *p) {
    if (p && mi_is_in_heap_region(p)) mi_free(p);
    else march_libc_free(p);
}

void *march_realloc_any(void *p, size_t n) {
    if (p && mi_is_in_heap_region(p)) return mi_realloc(p, n);
    return march_libc_realloc(p, n);
}
#endif /* MARCH_ALLOC_DEFINE_SHIMS */

#else

#include <stdlib.h>
static inline void *march_obj_calloc(size_t n) { return calloc(1, n); }

#endif /* MARCH_USE_MIMALLOC */

#endif /* MARCH_ALLOC_H */
