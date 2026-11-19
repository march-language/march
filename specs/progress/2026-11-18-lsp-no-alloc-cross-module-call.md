`[P1]` - [x] **LSP: false `@[no_alloc]` error on a call into another module of the project.**

## Symptom

In the editor, a `@[no_alloc]` function calling a function from another file of the same
forge project got

> `get` is marked @[no_alloc] but calls through an unknown closure. I can't see what
> `Strata.Coord.index` does. If you know it doesn't allocate, mark `get` @[no_alloc(assume)].

while `forge build` / `march --check` (whole program) accepted it. Seen in Strata,
`lib/strata/chunk.march` (`get` calling `Strata.Coord.index`).

## Cause

`Analysis.run_tir_pass` (lsp/lib/analysis.ml) re-parsed and lowered ONLY the open file.
Every call into another module was then an unknown external, which `Alloc_contract` treats
as an opaque closure. The typecheck path in `analyse` had already resolved the imports
(`Resolver.resolve_imports` with the forge project's lib paths) and kept the whole program
(stdlib @ imports @ this file) in `cap_program`, with `type_map` covering all of it
(`Typecheck_cache` seeds it from the stdlib and deps envs). Only the capability check used it.

## Fix

- `run_tir_pass` lowers `cap_program` (falling back to the open file only when there is
  none) and passes `Lower.get_iface_methods ()` to the pipeline, as the build and
  `Contract_pipeline.check_contracts` do. Diagnostics, lenses and quick-fix candidates were
  already filtered to spans in this file.
- DCE roots, per-function insights and consume modes use only the names THIS file declares.
  `a.def_map` also indexes stdlib and imports (12k names on Strata); rooting all of it kept
  the whole stdlib alive past the early DCE (5 s per pass instead of ~1 s).
- The memo key is now `deps_digest ^ src`: `analyse` computes `Typecheck_cache.deps_key`
  of the resolved imports once (reused for `deps_env ~key`) and stores it in the new
  `deps_digest` field, so editing an imported file re-runs the pass.

Cost on Strata's chunk.march: lower + pipeline ~1.3 s per cache miss, in the background
fiber. The pre-existing `Cap_static.check_program` in the same pass lowers the whole program
again (~3.2 s); sharing one lowering between the two is possible future work.

## Tests

`lsp/test/test_lsp_features.ml`: "cross-module callee: contract holds" (two-file forge
fixture; failed before with the exact message above) and "cross-module callee change
rechecked" (same open-file text, callee edited to allocate: must now be reported, as
`march --check` reports it). Verified against Strata: the L64 error is gone and the pass
produces `✓ no_alloc` lenses for all three contracts in chunk.march.
