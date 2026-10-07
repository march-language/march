# DONE 2026-10-07: B7.3, artifacts write through to the global store

Observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §17, B7.3.

## The problem

`Cas.create` made `~/.march/cas/{objects,artifacts}` and kept it in
`global_root`, but nothing ever wrote a compiled artifact there or looked one
up. Every project, and every fresh clone or worktree of the same project,
rebuilt binaries another build on the same machine had already produced with
the same compiler, runtime, flags and sources.

## The fix (`lib/cas/cas.ml`)

- **Write-through.** Every artifact-entry write is mirrored to
  `~/.march/cas/artifacts-v2/` with the same temp+rename discipline
  (`copy_file_exec`). That covers `store_artifact` (the blob),
  `store_diagnostics` (`.diag`, B7.1) and `store_sidecars` (`.sidecars` plus the
  `.hcr_manifest` / `.schemas.json` outputs). Each write mirrors only its own
  files, so the binary is not copied twice.
- **Fallback on a local miss.** `lookup_artifact` falls back to the global entry
  and warms the local store from it (blob, `.diag`, `.sidecars`, sidecar
  outputs). `lookup_diagnostics` falls back on its own as well, because the hit
  check evaluates it before `lookup_artifact` warms the local copy.
- **Why it is safe.** The key already carries the compiler and runtime
  identities, target, every codegen flag and the source digest, so a global
  entry is valid in any project that computes the same key.
- `runtime_archive.ml`'s stale sentence about `store_artifact` (plan item):
  #782 had already corrected it. It now says the store uses temp+rename through
  `copy_file_exec`, which this change keeps, so there was nothing to delete.

## Consequence for debugging

Clearing only the project's `.march/cas/artifacts-v2` no longer forces a
rebuild. The guidance was updated to clear both trees:
- `CLAUDE.md` (CAS cache paragraph);
- the `march-debug` skill;
- `specs/lang/refinement-types.md` (regenerated into `docs/`).

A private `HOME`, as the oracles, `scripts/triage.sh` and the bisect scripts
use, isolates both stores.

The global store has no garbage collection yet, any more than the local one.

## Test

`test/test_cas_b7.ml`: two fresh project directories share one private HOME.
- Project A's build writes into `~/.march/cas/artifacts-v2`.
- Project B, which has no `.march/cas` of its own, is then a **source-level
  hit**: no `--timings` stamps. It replays A's diagnostics, its binary runs, and
  its local store is warmed.
- Red: with the global fallback disabled, project B rebuilds and the case fails.
