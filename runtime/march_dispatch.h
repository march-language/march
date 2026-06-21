/* march_dispatch.h — Hot Code Reload versioned dispatch table (HCR Phase 2).
 *
 * A dense array of dispatch slots, indexed by NAME_ID (see
 * lib/tir/hot_reload.ml Name_table). Each slot holds a small ring of code
 * versions, each tagged by its impl_hash and a refcount of callers currently
 * executing it. A boundary->boundary call emitted by Llvm_emit does:
 *
 *     uint32_t v;
 *     fn  = march_dispatch_enter(NAME_ID, &v);   // pin the active version
 *     r   = fn(args);
 *     march_dispatch_leave(NAME_ID, v);          // unpin THAT version
 *
 * Publishing a new version (initial load or a hot reload) advances the slot's
 * "current" pointer; in-flight callers stay pinned to the version they entered.
 * See specs/hot-code-reload.md Part 3.
 */
#ifndef MARCH_DISPATCH_H
#define MARCH_DISPATCH_H

#include <stdint.h>
#include <stddef.h>

/* Erlang-style old+current cap by default; a reload that would exceed it needs
 * a purge of callers still pinned to the oldest version (deferred phase). */
#ifndef MARCH_MAX_LIVE_VERSIONS
#define MARCH_MAX_LIVE_VERSIONS 2
#endif

/* Version kind: native code vs interpreter trampoline (Model A, later phase). */
enum { MARCH_NATIVE = 0, MARCH_TRAMPOLINE = 1 };

/* Allocate the global table with [n_slots] slots (idempotent: re-init frees
 * any prior table first). */
void march_dispatch_init(uint32_t n_slots);
void march_dispatch_shutdown(void);

/* Publish [fn_ptr] as the new current version of slot [name_id].
 * Returns the ring index used, or -1 if [name_id] is out of range or no
 * reclaimable ring slot exists (every other version is still pinned — a purge
 * would be required; deferred to a later phase). */
int march_dispatch_publish(uint32_t name_id, void *fn_ptr,
                           const char *impl_hash, uint8_t kind);

/* Pin the current version of [name_id]; return its fn_ptr and write the pinned
 * ring index to *out_version, so a later leave targets the same version even if
 * a concurrent publish advances "current". Returns NULL if out of range. */
void *march_dispatch_enter(uint32_t name_id, uint32_t *out_version);

/* Unpin a version previously returned by enter. */
void march_dispatch_leave(uint32_t name_id, uint32_t version);

/* Introspection (tests / tooling). */
uint32_t    march_dispatch_current(uint32_t name_id);
uint64_t    march_dispatch_refs(uint32_t name_id, uint32_t version);
const char *march_dispatch_impl_hash(uint32_t name_id, uint32_t version);

#endif /* MARCH_DISPATCH_H */
