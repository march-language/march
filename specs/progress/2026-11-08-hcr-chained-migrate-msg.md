`[P2]` HCR: chain two deploys' `migrate_msg` instead of dropping the message (M7 / H6)

Phase F of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§3.4 "H6. Two
message-type changes compose"; table row M7): "chain two deploys' `migrate_msg`s instead of
dropping (`hcr_route_slow`)". H2 (each `migrate_msg` respects its own build's handler
contract) is what licenses the chain, and it is already checked per link at build time.

## Before

`hcr_route_slow` (`runtime/march_runtime.c`) counted the message-type changes between an
old-format message's epoch and the actor's (`hcr_log_msg_changes`). With exactly one change
and a `migrate_msg`, it converted the message; with two or more it dropped it ("one
conversion cannot bridge"), even when every deploy in between had a `migrate_msg`. A sender
pinned to an epoch two message-type deploys back (a held session party, a slow peer) lost
every message it sent.

## Fix

- `hcr_log_msg_chain` (new, beside `hcr_log_state_migrations`) collects every deploy in
  `(mepoch, cur]` that changed the slot's message type, oldest first, with its `ring_idx`,
  `epoch` and `migrate_msg_fn` (NULL when the deploy has none). It fills a 4-entry stack
  buffer and only mallocs beyond that, so the common case adds no allocation to the path.
- `hcr_msg_link` (new) runs one link: enters that version's frame
  (`march_dispatch_enter_version_frame`), checks `march_dispatch_epoch(slot, ring_idx) ==
  epoch`, calls `msg_fn(msg, g_hcr_none_cell)`, leaves the frame. It answers OK (the
  converted message), NONE (the link returned the none cell and consumed its input), or GONE
  (the version is no longer loaded; input untouched). The one-change path uses it too, so
  that path is the chain with n = 1.
- `hcr_route_slow` now: if any link has no `migrate_msg`, drops without running any link
  (no conversion the message could never finish); otherwise applies each link in order. A
  NONE drops on purpose; a GONE drops what is still owned. Counters: a chained conversion
  counts once in `converted` (no new counter: the counter struct is on the reload server's
  `PINS` wire line and in the observe snapshot, and "messages converted" is still the right
  meaning); every drop counts once in `dropped` / the actor's `hcr_dropped`.
- Drop reasons reported to a remote sender (`hcr_report_drop` → the delivery-failed hook)
  are unchanged for one change (`old message format: migrate_msg returned None`,
  `old message format: no migrate_msg for it`); a chain says which link:
  `... migrate_msg returned None (link 2 of 2)`, `... no migrate_msg for it (message-type
  change 2 of 2 has none)`, `... (link 1 of 2 is no longer loaded)`. All keep the
  `no migrate_msg` / `returned None` substrings existing consumers match.
- `hcr_log_msg_changes` is now count-only (its `last` out-parameter served only the removed
  one-change special case); the D30 early-advance test still uses it.
- Stale comments fixed: the drop comment in `hcr_route_slow`, the activation-log header.

### Ownership

`msg` is always the single message the router owns. A link consumes its input and returns
either a new message (now owned) or the none cell (nothing owned; the none cell is an
immortal static). A link that cannot be entered leaves `msg` owned, and the router disposes
exactly that (the original, or the previous link's output) with `march_actor_msg_dispose`.
No intermediate is retained past the next link's call, and nothing is disposed after a link
consumed it. The compiled wrapper consumes its input: `MARCH_DEBUG_BORROW=1` on a
`--hot-reload` build shows `counter_migrate_msg__hcr(m:own, none:own)` and
`counter_migrate_msg(m:own)`, for a message type with a `String` field and for one with only
scalar fields. Unlike the dispatch fn's `$msg`, though, `borrow.ml` does not pin that
parameter owned; it comes out owned from the fixpoint. That was already true of the one-link
path; see Residuals.

## Tests

`test/test_hcr_migrate_order.c`, `test_migrate_msg_chains` (dune rule
`test_hcr_migrate_order_runner`): two slots, each deployed twice with a message-type change
(`v1 -> v2 -> v3`, a new `v3_dispatch` that reads only the v3 format), an old sender held at
`e0` so the links' versions stay loaded. Messages are heap cells
(`[rc][tag][format][payload]`), so a leak or double release is visible: the test keeps one
extra reference to every message it sends and to every link output, and requires each to be
back to rc 1 at the end (a double release trips the RC-underflow abort).

1. Three v1-format messages two changes old: converted through `migrate_msg_12` then
   `migrate_msg_23`, handled by v3 (sum checked).
2. A v1 message the second link answers None for: dropped, counted, reason
   `(link 2 of 2)`.
3. A v1 message the first link answers None for: dropped, counted, reason `(link 1 of 2)`,
   the second link never called.
4. A v2-format message one change old: the one-link path, converted.
5. A chain whose v3 deploy has no `migrate_msg`: dropped, counted, reason
   `(message-type change 2 of 2 has none)`, and the existing v1->v2 link is not run.

Checks: 4 handled on v3 with no format mismatch, `converted` +4 (a chain counts once),
`dropped` +3, link call counts 5 / 5, the three reasons, no reason for converted messages,
15 tracked cells all at rc 1.

RED evidence. The harness built against the `HEAD` runtime (old "two or more changes: drop"
path, `git show HEAD:runtime/march_runtime.c`) fails 10 of the 15 new checks
(`converted=1 dropped=6 v3 handled=1 link12=0 link23=1`, every reason `no migrate_msg for
it`); `Results: 107 passed, 10 failed`. The ownership check was proved separately by a
perturbation of the new runtime (`march_incrc(*msgp)` before each link call, i.e. a router
that borrows instead of handing over): the check reports the originals and the v2
intermediates at rc 2 and fails. With the fix: `Results: 117 passed, 0 failed`.

ASAN: not run. A local `-fsanitize=address` build of the harness hangs in ASAN's own start-up
on this macOS (`__asan::InitializeShadowMemory` → `MemoryMappingLayout::Next` →
`dyld_shared_cache_iterate_text_swift`, before `main`), and the Docker daemon (the Linux
ASAN route) was not running. CI's sanitizer jobs cover the runtime.

## Residuals

- The GONE path in the middle of a chain (link 1 converted, link 2's version since reclaimed,
  so the router disposes link 1's output) is reasoned about but not exercised: making a
  version vanish while an epoch older than it is still pinned needs the keep-for-older rule
  broken on purpose.
- `borrow.ml` does not pin the `migrate_msg` wrapper's message parameter owned the way it pins
  a dispatch fn's `$msg`. It is owned in every case checked, but a future borrow-inference
  change could make it borrowed and leak each converted message (one-link and chained alike).
  Pinning it (`Tir_names.is_migrate_msg_wrapper_name`, param 0) would close that.
- Tested in the C harness with stand-in links, not end to end through `forge deploy hot` with
  three compiled builds.
