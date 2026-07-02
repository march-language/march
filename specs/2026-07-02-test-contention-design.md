# Test-run contention: shared dune cache

**Date:** 2026-07-02
**Status:** approved

## Problem

Multiple concurrent Claude agent sessions each work in their own git worktree
under `.claude/worktrees/` (59 exist today). Each worktree builds its own
~1.4 GB `_build` from scratch — the same OCaml compiler and clang-compiled C
runtime, recompiled per session. With 14 cores and several sessions building
simultaneously, the machine saturates: commands that take seconds under no
load were observed stalling for 10+ minutes.

Already solved elsewhere (out of scope here): dune RPC daemon conflicts and
root pinning (`scripts/run-tests.sh`), per-suite timeouts, content-hash-keyed
JIT `.so` cache in `~/.cache/march`.

## Decision

Enable dune's shared build cache **user-globally**, so identical compilation
actions are computed once and reused across all worktrees and sessions.

Chosen over: a committed `dune-workspace` stanza (would apply to CI and other
clones) and a `DUNE_CACHE=enabled` env var in `run-tests.sh` (would miss the
bare `dune build` invocations that CLAUDE.md instructs agents to run).

Explicitly out of scope (user decision): cross-session throttling/semaphores,
reliability/diagnostics hardening. Test *execution* is ~17s; the redundant
*builds* were the pile-up.

## Design

1. **`~/.config/dune/config`** (new file — none existed):

   ```lisp
   (lang dune 3.21)
   (cache enabled)
   (cache-storage-mode hardlink)
   ```

   Hardlink mode is safe here: home directory, the march repo, and
   `/private/tmp` scratchpad worktrees all live on the same APFS volume
   (`/dev/disk3s5`), so cached artifacts add near-zero extra disk.

2. **CLAUDE.md**: one short paragraph in "Build & test" documenting that the
   shared cache is on user-globally, the staleness escape hatch
   (`DUNE_CACHE=disabled dune build …`), and the maintenance command
   (`dune cache trim --size 20GB`). No trim automation — a documented manual
   command until proven insufficient.

## Verification

In a temporary worktree: build the test executables (populates the cache),
delete `_build`, rebuild, and compare wall time — the warm rebuild should be
dramatically faster. Run the quick suite (`scripts/run-tests.sh -q`) from the
warm build to confirm cached artifacts behave identically.

## Risks

- **Cache-induced staleness** during compiler debugging: dune's cache is
  content-addressed on action inputs and mature in 3.21; the escape hatch is
  documented. The known "stale `_build/default/runtime/`" trap is orthogonal —
  it concerns dune's per-worktree copy refresh, not the shared cache.
- **Unbounded growth** of `~/.cache/dune`: bounded operationally via the
  documented trim command.
