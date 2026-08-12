# SIMD vector types — Task 4: validation kernels + DataFrame Min/Max decision

Task 4 of `docs/superpowers/plans/2026-08-10-simd-vector-types.md`
(gitignored; ledger at `.superpowers/sdd/2026-08-10-simd-vector-types/`,
`task-4-brief.md`/`task-4-report.md`). Follows Task 1 (interpreter path,
`2026-08-10-simd-vector-types-task1-interpreter.md`), Task 2 (compiled core,
`2026-08-10-simd-vector-types-task2-compiled-core.md`), and the reduced-scope
Task 3 fixtures.

## What landed

- **`bench/simd_kernels.march`** — dot product (`f32`, `Simd.fma_f32x4`
  accumulator loop vs. `NativeArray.map2_f32` + `sum_f32`, N=5,000,000) and a
  delimiter scanner (`u8`, `Simd.load_u8x16`/`eq_u8x16`/`first_set_u8x16`
  16-byte stride vs. a byte-at-a-time scalar loop, 16MB haystack), plus a
  deterministic `fma_f32x4` interpreted-vs-compiled parity leg (LCG-driven,
  200,000 triples, checksum comparison).
- **`bench/RESULTS.md`** new `## simd-kernels` section: methodology, load
  state, per-leg medians/min/max over 5 rounds, and the DataFrame Min/Max
  non-migration decision with its supporting probe numbers.
- **`test/stdlib/test_dataframe.march`** new `describe "col_native_min_max"`
  block: 7-element (non-lane-multiple) `Int` and `Float` columns, pinning
  `(-7, 9)`. Runs via `march test test/stdlib/test_dataframe.march` (220
  tests total in that file, all passing).
- **`specs/todos/2026-08-11-simd-nested-closure-vector-accumulator-segfault.md`**
  — new open item, filed per the plan's "if a bar fails, STOP and report
  with IR evidence" protocol, documenting a compiled-only codegen gap
  discovered while writing the dot-product kernel (see below).

## What did NOT land

- **`stdlib/dataframe.march`'s `col_native_min_max` was NOT migrated** to a
  `Simd`-based fast path. The plan's own condition for migrating
  ("ONLY if... the bench shows non-regression") was not met — see below.

## Results

- **`scan_simd` beats its ≥4x bar**: ~11.5x faster than `scan_scalar`
  (19.28ms vs 221.32ms median, 5 rounds, N=16,000,000 bytes). This kernel's
  loop never threads a vector value across a recursive call (only the plain
  `Int` index), so it hits the register-resident path Task 2/3 built and
  wins decisively, matching the plan's expectation for a memchr-shaped
  workload.
- **`dot_simd` FAILS its "beats `dot_composed`" bar**: ~10.8x *slower*
  (29.22ms vs 2.71ms median). `--emit-llvm` evidence: `dot_loop` (a
  top-level `pfn`, not a closure) allocates a fresh `F32x4` box
  (`march_simd_alloc`) on every one of its ~1.25M loop iterations to pass
  the running accumulator into its own recursive call — the classic
  "boxing in the loop" the plan's contingency anticipated.
- A separate, more severe variant of the same gap: the algorithm's *natural*
  March idiom — a locally-nested `fn` inside `dot_simd`, capturing `a`/`b`/`n`
  instead of threading them as explicit parameters — **segfaults when
  compiled** (correct interpreted). Root cause (from IR): the closure's
  direct "kick off the loop" call site and its own indirect self-recursive
  call disagree on whether the vector-typed accumulator parameter is boxed
  or register-resident. `bench/simd_kernels.march` works around this by
  hoisting the loop to a top-level `pfn` (which avoids the crash but still
  pays the per-iteration boxing cost above). Full repro + IR:
  `specs/todos/2026-08-11-simd-nested-closure-vector-accumulator-segfault.md`.
- **DataFrame Min/Max probe**: `native_int_arr_min` (existing C loop) vs. an
  equivalent `Simd.min_i64x2`-accumulator loop over the same shape, both
  over a 5,000,000-element `NativeIntArr`: 1.35ms vs. 46.80ms — ~35x
  slower. Given `i64x2`/`f64x2` are also only 2 lanes wide (half the
  `f32x4`/`i32x4` lane count), migrating Min/Max was declined; the new
  7-element pinning test guards the existing (unmigrated) implementation and
  is ready to catch a regression once the residency gap is fixed and
  migration becomes worth revisiting.

## Gates run

- `march test test/stdlib/test_dataframe.march` — 220/220 tests pass
  (includes the 2 new Min/Max pins).
- `dune build --root . bin/main.exe` clean.
- Full `scripts/run-tests.sh` / `dune build --root . @test/runtest` — see
  the accompanying commit for the actual gate run (this file predates that
  step in the task sequence; update if a failure surfaces there).

## Next step (not part of this task)

Whoever next touches compiled `Simd` closures/residency should read
`specs/todos/2026-08-11-simd-nested-closure-vector-accumulator-segfault.md`
first — it has a minimal repro, the full `--emit-llvm` IR for both the
segfault and the boxing-cost variant, and a concrete suggested fix
direction. Once that's closed, DataFrame Min/Max migration is worth
re-measuring (the pinning test added here is the regression net for it).
