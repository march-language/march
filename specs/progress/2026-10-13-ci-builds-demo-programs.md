# CI builds the demo/ programs

**Landed:** 2026-10-13

## Problem

Nothing in CI built `demo/`. Its eight dune rules (`two_node_rpc`,
`two_node_server`, `two_node_client`, `resource_report`, `hcr_server`,
`hcr_client`, `load_server`, `load_client`) only ever ran under a targetless
`dune build --root .`, which CI never does. During the v0.5.0 cut seven of
them had silently stopped compiling: the cluster transport (NetKernel,
NodeCall, ...) started requiring `IO.Mut` and `IO.Clock` and the demos were
never updated. `scripts/bump-version.sh`'s full build was the first thing to
notice, and it blocked the release until 6114e4aa5 (PR #980) fixed the demos.

A second, quieter gap: each rule listed the handful of stdlib files it
imports as deps. A change to any other stdlib module (where a capability
requirement can come from) did not invalidate the rule, so even a local
build could serve a stale, passing demo from the dune cache.

## Fix

- `demo/dune`: a `demo` alias over all eight `.exe` targets; every rule now
  depends on `(source_tree ../runtime) (source_tree ../stdlib)` instead of a
  hand-picked file list (the same deps the `test/dune` compile rules use).
- `.github/workflows/ci.yml`: a `Build demo/ programs` step at the end of the
  existing `conformance` job (`dune build @demo/demo`). No new runner job;
  that job already has the compiler built and ran 5m20s of its 25 min budget.
- `.github/workflows/README.md`: the conformance row and the local-repro
  section name the new step.

## Verification

- `dune build --root . @demo/demo`: exit 0, all eight demos compiled (~15 s
  on a 14-core Mac).
- RED proof: deleting `needs IO.Mut` from `demo/two_node_server.march` makes
  the same command exit 1 with `[cap_needs]` ("`Cap(IO.Mut)` used in module
  `TwoNodeServer` but `IO.Mut` is not declared in `needs`"); restored after.
