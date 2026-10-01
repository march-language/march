# DONE NativeArray fold inline loop

Filed and done 2026-09-30. Spec: `specs/plans/2026-09-30-nativearray-fold-inline-loop.md`
(its "As built" section records where the implementation is narrower than the
design). Phase A of `specs/plans/2026-09-28-nativearray-fusion-plan.md`.

## The problem

`NativeArray.fold_*` was the only NativeArray higher-order operation with no
inline loop. It ran a C loop in the runtime calling an opaque closure per
element, and for Float it boxed every element and accumulator: `fold_float` cost
about 47 ns per element against about 0.2 ns for an inline map.

## The change

- `lib/tir/native_map_inline.ml`: fold is a third target family. The builtin's
  `(acc, arr, f)` order puts the closure last, the map2 call shape, so the map2
  substitution functions serve it unchanged. `fold_callback_kind` limits it to
  scalar accumulators: an all-Float callback over float/f32 (through the unboxed
  clone) or an all-Int callback over int/i32/u8. Everything else keeps the
  runtime fold, which sidesteps the runtime's accumulator-release rule.
- `lib/tir/llvm_emit_nmap.ml`: `decode_nfold_inline_call` and
  `emit_native_fold_inline_loop`, a loop carrying the accumulator in a phi. The
  array is left alone, as the runtime leaves it; a capturing closure is
  incremented before each call and released once after the loop, as in the map
  loops.
- `lib/tir/llvm_emit.ml`: two dispatch arms (non-capturing, capturing).

## Verification

- `test/native/native_arr_fold_inline.march`: 16 cases over all five widths,
  capturing and non-capturing, empty arrays, -0.0, large values, plus three folds
  that must stay on the runtime path. Its `.expected` is the interpreter's
  output. A second rule pins the IR shape: 11 inline loops, 3 runtime folds, no
  boxing in the unboxed clones.
- Perturbation: swapping the accumulator and element arguments in the emitter
  turned 5 fixture lines red; restoring it turned them green.
- Refcount balance under `MARCH_TRACE_GC`: a capturing Int and Float fold called
  1,000 and 2,000 times left the same 10 live objects, so no per-call leak.
- `dune build --root . @test/runtest`: the only failure was the refinement
  coverage audit's corpus baseline, which gained exactly the new fixture's two
  lines; regenerated with `UPDATE_SNAPSHOTS=1`.
- Benchmark (`specs/benchmarks.md`, `bench/native_array_chains.march` run 2):
  Float fold 201 ms to 3.0 ms (67×), Int fold 9.0 ms to 0.43 ms (21×). Non-fold
  cases have identical IR after renumbering.
- Optimized assembly: the Int fold loop is vectorized; the Float fold loop is
  scalar with no calls, as the strict Float order requires.
- ASAN (Linux container, `MARCH_SANITIZE=1`): 14 programs clean, covering the new
  fixture, all existing fold and map-inline fixtures, the refcount-balance loops
  and `bench/native_array_chains.march`. Perturbation: removing the per-call
  closure increment produced a heap-use-after-free in `march_decrc`; restoring it
  made the run clean.
- `scripts/ir-oracle.sh` (baseline from the unmodified compiler): 5 of 354
  programs changed, each of which contains folds that now inline; the other 349
  are byte-identical.
- LSP suite (shares the pass pipeline): 378 tests pass.

## Test changes

- `native_arr_fold_boundary_box_probe`: its lambda-literal legs now take the
  inline path, so the runtime fold's boundary boxes lost their guard. Added `_rt`
  twins that pass the callback as a parameter (Float, f32, zero-length), which
  keep the runtime path covered.
- `native_arr_fold_acc_leak_probe`: header notes that its f64/f32 legs now inline
  and where the runtime Float accumulator release is guarded instead.

## Found along the way

- **A pre-existing use-after-free in the runtime Float fold.** A callback that
  ignores its element, reaching `fold_float` through a parameter, double-frees each
  element box; it reproduces on the branch point. Filed as
  `specs/todos/2026-09-30-native-float-arr-fold-unused-elem-double-free.md`. The
  identity `_rt` leg was left out of the boundary-box probe until it is fixed.

- The interpreter's `Int` is 63-bit and compiled `Int` is 64-bit: `2^62 - 1` added
to itself prints `-2` interpreted and `9223372036854775806` compiled, with or
without a fold. Pre-existing and unrelated; the fixture stays inside 62 bits.
