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

/* Live code versions per slot (D13/D32): three, so one drain can overlap the
 * next deploy.  A publish that finds no free or reclaimable ring version does
 * not fail silently: the reload server queues the activation and answers WAIT
 * (see march_dispatch_can_stage and specs/plans/2026-09-21-distributed-
 * authority-and-deploys-plan.md, II.4.2). */
#ifndef MARCH_MAX_LIVE_VERSIONS
#define MARCH_MAX_LIVE_VERSIONS 3
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
 * free or reclaimable ring slot exists (see the reclaim condition under
 * "The unified epoch model" below).  The version gets ring epoch 0, the
 * baseline's; the reload server stages epoch-tagged versions instead. */
int march_dispatch_publish(uint32_t name_id, void *fn_ptr,
                           const char *impl_hash, const char *sig_hash,
                           uint8_t kind);

/* Pin the current version of [name_id]; return its fn_ptr and write the pinned
 * ring index to *out_version, so a later leave targets the same version even if
 * a concurrent publish advances "current". Returns NULL if out of range. */
void *march_dispatch_enter(uint32_t name_id, uint32_t *out_version);

/* Pin one SPECIFIC ring version of [name_id] (not "current"), for a caller
 * that must keep running an older version after a newer one is published:
 * a hot-reload actor stays on the code its state layout belongs to until it
 * reaches its migrate marker (march_actor_publish_migrating).  Returns NULL,
 * pinning nothing, if the version is out of range or not live. */
void *march_dispatch_enter_version(uint32_t name_id, uint32_t version,
                                   uint32_t *out_version);

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

/* Phase 8: per-slot caller-set for coordinated upgrade gate.
 * set_callers stores a comma-separated caller-name string (strdup'd internally).
 * Pass NULL or "" to clear. callers() returns NULL when no callers are stored. */
void        march_dispatch_set_callers(uint32_t name_id, const char *callers_str);
const char *march_dispatch_callers(uint32_t name_id);

/* dlclose GC: store the dlopen handle associated with a ring slot so the
 * dispatch table can release it when the slot is reclaimed.  Call after a
 * successful march_dispatch_publish / march_dispatch_publish_epoch.
 * Baseline slots (main binary) never call this; their handle stays NULL. */
void march_dispatch_set_handle(uint32_t name_id, uint32_t version, void *handle);

/* Test seam: when hook is non-NULL, reclaiming a ring slot calls hook(handle)
 * INSTEAD of dlclose(handle).  Lets a unit test observe the exact moment a
 * handle is released without loading real shared objects.  NULL restores the
 * real dlclose.  Not for production use. */
void march_dispatch_set_close_hook(void (*hook)(void *handle));

/* Phase 9: epoch-tagged dispatch.
 *
 * Each MarchFnVersion now carries a uint32_t epoch (0 = pre-Phase-9 / no epoch).
 * The epoch is assigned by the reload server at ACTIVATE time and stamped into
 * the deployed .so via __march_init(epoch).  Boundary call sites in .so files
 * read the per-.so __march_hcr_epoch cell (set by __march_init) and pass it to
 * march_dispatch_enter_gen so they always call the newest compatible version.
 *
 * march_dispatch_publish_epoch — same as march_dispatch_publish but also sets
 *   ring[idx].epoch = epoch.  Use this when the epoch is known (ACTIVATE with
 *   an "epoch:<N>" field).  The plain march_dispatch_publish leaves epoch = 0.
 *
 * march_dispatch_enter_gen — epoch-aware enter.
 *   Scans both ring slots; returns the fn_ptr from the newest live slot whose
 *   epoch <= caller_epoch.  Falls back to the current slot when caller_epoch == 0
 *   or no slot matches (backward-compat with pre-Phase-9 code).
 *
 * march_dispatch_epoch — read the epoch of a specific ring slot version.
 *   Returns 0 if name_id or version is out of range.
 *   Used by VERSIONS_DETAIL to include the epoch in the server response. */
int      march_dispatch_publish_epoch(uint32_t name_id, void *fn_ptr,
                                      const char *impl_hash, const char *sig_hash,
                                      uint8_t kind, uint32_t epoch);
void    *march_dispatch_enter_gen(uint32_t name_id, uint32_t caller_epoch,
                                  uint32_t *out_version);
uint32_t march_dispatch_epoch(uint32_t name_id, uint32_t version);

/* ── The unified epoch model (D12, D32, D33; plan II.4.1-II.4.2) ─────────
 *
 * Every unit of work (a proc: actor, task, session party) carries a code
 * epoch, march_proc.code_epoch.  A boundary call resolves against it:
 * march_dispatch_enter_unit picks the newest live version whose epoch is at or
 * before the running proc's epoch.  A proc whose epoch is 0 is UNPINNED and
 * follows the slot's current version; the compiled `main` green thread is the
 * one such unit (it runs for the process lifetime and has no marker, so a
 * pinned main would keep its epoch alive for ever and block retirement).
 *
 * Epoch numbering.  g_current_epoch starts at MARCH_EPOCH_BASE (1): every proc
 * spawned before the first deploy is pinned to it, and baseline versions carry
 * ring epoch 0, which is <= 1.  A deploy gets a runtime epoch strictly above
 * the current one (march_epoch_next), so two activations never share an epoch
 * even when a client reuses the server's GET_EPOCH value.
 *
 * Pins (D32).  A small table of MARCH_EPOCH_PIN_SLOTS entries counts the units
 * pinned to each epoch, separately from a version's per-call `refs`.  Every
 * pin has a live holder: a proc (taken at spawn, moved when an actor advances,
 * dropped at the reap), a queued marker (moved to the actor that consumes it),
 * or the "current" role itself (the current epoch always holds one pin, so a
 * spawn that reads g_current_epoch can always pin it).  An entry whose count is
 * 0 has no holder, so nothing but march_epoch_reserve can revive it.
 *
 * Reclaim condition (II.4.2, per slot): ring version V with epoch e is
 * reclaimable iff refs == 0 and no pinned epoch E satisfies e <= E < e_next,
 * where e_next is the epoch of the next newer live version in the same slot
 * (infinity for the newest).  A unit pinned to epoch 5 calling a function last
 * changed at epoch 2 resolves to the epoch-2 version, so that version is in use
 * although epoch 2 itself may have no pins. */

#define MARCH_EPOCH_BASE      1u
#define MARCH_EPOCH_PIN_SLOTS 8

/* Pin the ring version the running proc's epoch selects (see above).  The
 * base binary and every .so call this at a boundary call. */
void    *march_dispatch_enter_unit(uint32_t name_id, uint32_t *out_version);

uint32_t march_epoch_current(void);
/* The runtime epoch for an activation the client tagged [requested]:
 * max(requested, current + 1). */
uint32_t march_epoch_next(uint32_t requested);
/* Take one pin on [epoch] if it has a live entry (count > 0).  0 on success,
 * -1 if the epoch has no holder (the caller picks another epoch). */
int      march_epoch_pin(uint32_t epoch);
void     march_epoch_unpin(uint32_t epoch);
/* Pinned units of [epoch] (0 if it has no entry). */
int64_t  march_epoch_pins(uint32_t epoch);
/* Allocate an entry for a NEW epoch with count 1 (the activation's "current"
 * role pin, taken before any marker is sent).  -1 if all entries are in use:
 * the activation waits. */
int      march_epoch_reserve(uint32_t epoch);
/* Make [epoch] current and drop the previous current's role pin.  [epoch]
 * must already be reserved. */
void     march_epoch_advance(uint32_t epoch);
/* Snapshot of the pin table (entries with count > 0), for PINS.  Returns the
 * number written (<= max). */
int      march_epoch_pin_table(uint32_t *epochs, int64_t *counts, int max);
/* 1 iff some pinned epoch E satisfies lo <= E < hi (hi == UINT32_MAX: no upper
 * bound).  The reclaim condition's pin scan. */
int      march_epoch_pinned_in(uint32_t lo, uint32_t hi);
/* Tests only: reset to a fresh process's state (current = MARCH_EPOCH_BASE,
 * one role pin). */
void     march_epoch_reset_for_test(void);

/* Staged activation (II.4.6 step 1 and 3).  stage writes a version into a free
 * or reclaimable ring slot with live = 0 and returns its index (-1: nothing
 * reclaimable, the activation must wait); readers cannot select it.  commit
 * makes it live and current; unstage discards a staged version. */
int  march_dispatch_stage(uint32_t name_id, void *fn_ptr,
                          const char *impl_hash, const char *sig_hash,
                          uint8_t kind, uint32_t epoch);
void march_dispatch_commit(uint32_t name_id, uint32_t version);
void march_dispatch_unstage(uint32_t name_id, uint32_t version);
/* 1 iff a stage into [name_id] would find a ring slot now (no side effects).
 * The reload server checks every slot of a batch before staging any. */
int  march_dispatch_can_stage(uint32_t name_id);
/* Mark a ring version as carrying a migration (its .so holds a
 * migrate_state or migrate_msg an older actor has yet to run): it is then
 * also kept while ANY epoch older than its own is pinned, on top of the
 * reclaim condition.  Cleared when the version is reused. */
void march_dispatch_set_keep_for_older(uint32_t name_id, uint32_t version);
/* 1 iff ring version [version] of [name_id] is live. */
int  march_dispatch_live(uint32_t name_id, uint32_t version);

/* Per-slot message-schema epoch (D30, II.4.6): the epoch at which the actor
 * whose dispatch function is [name_id] last changed its message type.  Set by
 * an activation whose deploy changed the handler signatures; 0 = never. */
void     march_dispatch_set_msg_schema_epoch(uint32_t name_id, uint32_t epoch);
uint32_t march_dispatch_msg_schema_epoch(uint32_t name_id);

#endif /* MARCH_DISPATCH_H */
