# Hot-deploy correctness

Status: design for the five road-to-1.0 deploy items requested 2026-10-31.

## Intent

A first hot deploy must migrate from the state actually running on the server.
A deploy must not send new ABI calls from an old running frame. Queued work must
observe the existing epoch drain semantics, sandbox grants must cover reload
writes, and reverting a bad release must be demonstrated against running nodes.

## Schema baseline (existing owner decision)

Follow decision 12 in `2026-09-28-road-to-1.0.md` and
`../todos/2026-10-18-hcr-first-deploy-no-schema-baseline.md`:

- Embed deterministic schemas and manifest in every hot-reload base and patch.
  Use the same serialization as the sidecars and include it in the artifact key.
- Add owner-only, peer-uid-checked, unsigned `SCHEMAS` queries. Report the latest
  activated schema for each actor and the release that supplied it. This reports
  the activation baseline, not the possibly older state of draining actors.
- Derive patch metadata from the verified artifact. Staging, rejected activation,
  and disconnected batches must not advance the schema baseline. Persist metadata
  with activated patch records and prune it with the stack. Replay restores the
  baseline from the same verified artifacts; partial function updates must not
  overwrite unrelated actors' schemas.
- Forge queries each target's baseline; server data takes precedence over `.prev`
  and a mismatch produces a warning. Only an explicitly unsupported query allows
  legacy fallback. Malformed responses and transport failures are errors.
- Legacy servers use an explicit `--old-schemas` or the saved `.prev`; without
  either, refuse with restart / `--old-schemas` guidance. An empty actor set is a
  valid known baseline, distinct from an unavailable baseline.
- Cover first migration without a separately compiled base `.so`, stale operator
  checkout, successive deployments, failed batches, restart/replay, and old servers.

## Running old caller frames

**Owner decided in this chat: implement per-frame version pinning.** Preserve
coordinated signature-changing upgrades; do not replace them with blanket refusal.

Existing dispatch refs keep the directly called function version alive, but nested
calls select using `march_proc.code_epoch`. In particular, `main` has epoch zero
and follows current code. Keeping an image mapped does not fix a nested call that
selects a new, incompatible callee.

- Give running hot-reload frames a stable routing epoch. Nested boundary calls
  inherit their caller's epoch, so an old frame calls a compatible old callee even
  after a coordinated upgrade. Retain versions needed by that epoch, in addition
  to the existing direct-call refs.
- Pin entry frames too, including compiled `main`; pinning only at a nested call
  after a deploy is too late. Direct calls, self tail loops, mutual tail calls,
  closure invocation and runtime callbacks must preserve the same invariant.
  An unchanged function reached at a newer epoch inherits the caller's routing
  context, not simply the epoch when that function's body was last published.
- Keep frame context with the green thread, not an OS-thread-local variable:
  yielding and scheduler migration must not transfer it to another actor.
- Pop context and release pins on normal return and nonlocal exits: caught panic,
  actor termination, cancellation and task unwinding. Restore the enclosing frame
  rather than clearing its epoch. Test exceptional exits for leaked pins/refs.
- Actor handlers enter under the actor's selected epoch. Marker processing moves
  to a newer epoch only after the handler frame has unwound; nested calls cannot
  silently cross that boundary. Sends and child work must not mislabel old-frame
  work as new-epoch work.
- A truly nonreturning old frame may retain an old epoch indefinitely. Preserve
  existing bounded-version admission and report the blocker rather than reclaiming
  live versions or silently routing to a newer ABI. This intentionally revises the
  old rationale for leaving `main` unpinned. Do not invent a forced unsafe advance.
- Maintain existing borrow-mode refusal until tests demonstrate that frame pinning
  also makes those ownership transitions safe; lifting it is not required here.
- Cover a retyped callee under a long-running old caller, coordinated callers,
  nested returns, scheduler migration, tail loops, cancellation/panic cleanup,
  code reclamation pressure, actor migration, and unchanged-signature patches.
  Prove both that old work keeps old behavior and fresh eligible work sees new code.

## Drain-first reload

The todo predates the unified epoch implementation. Existing
`test/test_hcr_migrate_order.c` already asserts that in-flight and pre-marker work
runs on old code, migration occurs once, and post-marker work runs on new code.
Retain this mechanism rather than adding a second pause state. Sends continue
under the existing mailbox policy. Retain documented soft/hard deadline and
message-conversion semantics; do not claim unconditional losslessness when a
configured deadline deliberately drops incompatible messages or kills an actor.

Verify the existing tests, add compiled coverage where necessary, and fix the
remaining `on_stop` interaction: after state migration, never invoke a callback
that expects the old layout. Prefer routing a replacement callback through the
actor's active version. For an actor with a registered callback, refuse a
state-changing activation if it cannot supply a compatible current-version
callback. Do not silently skip the callback or run the old one. This fail-closed
fallback is an implementation choice, not an additional owner decision. Reconcile
the stale todo only after its acceptance and callback behavior are proven.

## Sandboxed reload writes (owner decided this chat)

Require an explicit `IO.FileWrite` grant; do not add filesystem exceptions.
Diagnose `--hot-reload --cap-sandbox` when that grant is absent, explaining that
CAS upload, activation state, and audit writes require it. Keep the OS filter
unchanged. Prefer a compiler warning, matching the existing todo's option 2,
so read-only reload/observe queries remain usable. Runtime write failure must
leave activation state unchanged. Test actual `CAS_PUT` rejection without the
grant and success with it, not merely generated filter strings.

## Tested rollback

Rollback is a new signed release of prior code, not `ROLLBACK_BATCH` and not
rewinding epochs. Exercise v1 -> faulty-but-ABI-compatible v2 -> v1-as-v3 against
live nodes, using the normal deployment path. Assert behavior, continued service,
monotone release/epoch metadata, and the schema baseline after recovery. Include
a failed deployment that preserves the previous baseline. For state changes,
require an explicit reverse migration; never infer an inverse or restore stale
state over newer writes. Add an explicit refusal test if the reverse migration
is missing. This work does not promise reversal of external side effects.

## Delivery and validation

Use the current clean worktree. Keep changes in independently reviewable chunks:
schema baseline; per-frame routing and lifetime; drain/callback behavior; sandbox diagnostics;
rollback scenarios. Each chunk includes regression evidence, progress/todo updates,
and the user-facing changelog when behavior changes. Run focused C, compiler,
Forge and scenario tests, then affected checks. Determinism testing covers embedded
schema/manifest data. Linux sandbox validation must run on Linux; a macOS-only
result is not proof of seccomp behavior.

## Baseline evidence

2026-10-31: built `test/test_hcr_migrate_order_runner` with `dune build --root .`
and ran it directly: **94 passed, 0 failed**. This proves existing marker-order,
in-flight handler, mailbox, migration, and deadline cases; it does not establish
the shutdown-callback or end-to-end rollback requirements above.

A fresh builder review found only the unresolved callback fallback; the
fail-closed rule above resolves that concern. The owner subsequently chose
per-frame version pinning; that section now replaces the refusal proposal and
requires a fresh implementation review. No product code has been changed yet.
