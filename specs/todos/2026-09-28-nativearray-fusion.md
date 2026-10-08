`[P3]` Automatic NativeArray fusion, no annotation

Chains of `NativeArray` map / map2 / fold / sum allocate and walk an intermediate
array per link, and `fold_*` runs an opaque closure call per element. The loops
are memory-bandwidth-bound (specs/optimizations.md P10 measured no gain from
vectorizing a single map), so removing the intermediate traffic is the win.
`lib/tir/fusion.ml` fuses list chains only, and checks only producer/consumer
names, never callback bodies.

Plan: `specs/plans/2026-09-28-nativearray-fusion-plan.md`. Fuse by substituting
lambda-literal callback bodies in TIR (after Mono, before Defun), add a fold
inline loop, keep `sum_*` reassociating as the runtime already does and user
folds strict. `--compile` native/wasm/cross only: JS has no NativeArray codegen
and the REPL JIT runs no optimizer passes. Phase 0 is a benchmark gate that can
cancel the rest. Chosen over an MLIR backend or sidecar; the plan records when
to reopen MLIR.

Phase 0 ran 2026-09-29 (`bench/native_array_chains.march`, results in
`specs/benchmarks.md`): map/map2 chain fusion gives 2.6–6.8×, so GO. `fold_float`
costs ~47 ns/element through the boxed closure ABI, so the fold inline loop now
comes first as a standalone change, and `sum(map)` must never be rewritten into
a `fold_*` call (measured 2.8–65× slower).

Phase A (fold inline loop) landed 2026-09-30
(`specs/progress/2026-09-30-nativearray-fold-inline-loop.md`). Phase B (map / map2
composition, `Fusion.run_nativearr`) landed 2026-10-04
(`specs/progress/2026-10-04-nativearray-map-fusion.md`): written-unfused map3 and
map→map2 chains now run at the hand-fused speed. Phase C (fold(map) into one
fold, sum(map)/sum(map2) into one summing loop) landed 2026-10-06
(`specs/progress/2026-10-06-nativearray-fold-sum-fusion.md`). Still open: phase D
(width conversions, f32 chains, which need a scalar binary32 rounding, dividing
callbacks, which `Purity` rejects today, and `@[vectorize]` messages naming the
link that blocked fusion), and phase E (ASAN sweep, ir-oracle, LSP parity).
