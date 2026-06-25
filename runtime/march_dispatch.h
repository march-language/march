/* march_dispatch.h — Hot Code Reload versioned dispatch table (HCR Phase 2/4/7).
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
 *
 * Phase 4 additions:
 *   - sig_hash per version (for ABI compatibility checking)
 *   - baseline_impl_hash per slot (for crash-restart drift detection)
 *   - id→name reverse lookup array (for VERSIONS and ABI_QUERY responses)
 *   - march_dispatch_sig_hash(), march_dispatch_baseline_hash(), march_dispatch_id_to_name()
 *
 * Phase 7 additions:
 *   - activated_at_ms and signer_hex per slot (for VERSIONS_DETAIL and audit log)
 *   - march_dispatch_set_activation(), march_dispatch_activated_at(), march_dispatch_signer_hex()
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
 * [sig_hash] is the ABI signature hash (64 hex chars); stored per-version for
 * the sig_hash compatibility gate in forge deploy hot.
 * Returns the ring index used, or -1 if [name_id] is out of range or no
 * reclaimable ring slot exists (every other version is still pinned — a purge
 * would be required; deferred to a later phase). */
int march_dispatch_publish(uint32_t name_id, void *fn_ptr,
                           const char *impl_hash, const char *sig_hash,
                           uint8_t kind);

/* Pin the current version of [name_id]; return its fn_ptr and write the pinned
 * ring index to *out_version, so a later leave targets the same version even if
 * a concurrent publish advances "current". Returns NULL if out of range. */
void *march_dispatch_enter(uint32_t name_id, uint32_t *out_version);

/* Unpin a version previously returned by enter. */
void march_dispatch_leave(uint32_t name_id, uint32_t version);

/* Introspection (tests / tooling / reload server). */
uint32_t    march_dispatch_current(uint32_t name_id);
uint64_t    march_dispatch_refs(uint32_t name_id, uint32_t version);
const char *march_dispatch_impl_hash(uint32_t name_id, uint32_t version);
const char *march_dispatch_sig_hash(uint32_t name_id, uint32_t version);
const char *march_dispatch_baseline_hash(uint32_t name_id);  /* Phase 4 */
const char *march_dispatch_id_to_name(uint32_t name_id);     /* Phase 4 */

/* Phase 7: per-slot activation metadata for VERSIONS_DETAIL. */
void        march_dispatch_set_activation(uint32_t name_id, long long ts_ms,
                                          const char *signer_hex);
long long   march_dispatch_activated_at(uint32_t name_id);
const char *march_dispatch_signer_hex(uint32_t name_id);

/* Name registry: maps function name strings → dispatch slot IDs.
 * Populated at startup by @main alongside march_dispatch_publish.
 * Thread-safe for concurrent reads after startup; writes are startup-only. */
void march_dispatch_register_name(uint32_t id, const char *name);
int  march_dispatch_name_to_id(const char *name, uint32_t *out_id);

#endif /* MARCH_DISPATCH_H */
