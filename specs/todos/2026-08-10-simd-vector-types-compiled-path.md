# Simd vector types — compiled path (Tasks 3–5)

Task 1 (interpreter path) and Task 2 (compiled core — runtime box, `coerce`
vector arms, register-resident inline op lowerings for every op INCLUDING
`load`/`store` — pulled forward from Task 3 after discovering the original
"defer load/store" split broke any whole-stdlib compile, since compiling
`stdlib/simd.march` means compiling its `load_*`/`store_*` wrapper bodies
regardless of whether the calling program invokes them) are done; see
`specs/progress/2026-08-10-simd-vector-types-task1-interpreter.md` and
`specs/progress/2026-08-10-simd-vector-types-task2-compiled-core.md`. The
remaining work from `docs/superpowers/plans/2026-08-10-simd-vector-types.md`
(gitignored; ledger at `.superpowers/sdd/2026-08-10-simd-vector-types/`):

- **Task 3 (reduced scope)** — the load/store lowerings themselves are
  done (Task 2). What remains: the dedicated fixtures from
  `task-3-brief.md` — `test/native/simd_vector_mem.march` (full t9-t11
  interpreter-parity coverage, byte scan/store-round-trip/COW, beyond the
  minimal leg Task 2 already added to `simd_vector_core.march`),
  `test/native/simd_residency.march` + `--emit-llvm` grep rules proving a
  straight-line kernel allocates zero `march_simd_alloc` boxes while an
  escaping vector allocates exactly one, and
  `test/native/simd_bounds_panic.march` + a stderr-diff dune rule (Task 2
  verified this ad hoc, not wired into `test/dune`).
- **Task 4 — done** (`specs/progress/2026-08-11-simd-vector-types-task4-validation-kernels.md`).
  `bench/simd_kernels.march` landed with the dot product and u8 delimiter
  scanner legs; the scanner beat its ≥4x bar (~11.7x) but the dot product
  failed its "beats the composed baseline" bar (~10.8x slower) due to a
  compiled-only gap in how vector values cross call boundaries — which also
  produced an outright segfault for the closure-nested variant of the same
  loop shape.
- **Task 4b — done** (commit `08c02ebb`;
  `specs/progress/2026-08-11-simd-nested-closure-vector-accumulator-segfault.md`).
  Both halves of that gap are **fixed**: the closure kickoff call and the
  indirect self-call now agree on the uniform boxed ptr ABI for vector params
  (segfault gone, interpreter parity), and a self-tail-recursive function's
  vector-typed parameter now gets a **native `<N x T>` TCO slot** so the
  accumulator stays in a register across iterations (`dot_simd` 29.22 ms →
  10.01 ms, 2.9x; loop-body `march_simd_alloc` count 1-per-iteration → 0).
  Pinned by `test/native/simd_nested_closure_acc.march` (+ `.expected` + an
  output-diff rule and a falsifiable IR-residency rule in `test/dune`).

  What that fix did **not** resolve, all separately filed:
  - `dot_simd` still loses to `dot_composed` (10.01 vs 2.55 ms). This is
    **not** a vector problem — an attribution probe holding the loop
    framework constant measures the SIMD loop 4.0x faster than the
    equivalent scalar March loop. The residual is general per-iteration
    March index-loop overhead (volatile preempt load, `stacksave`/
    `stackrestore`, two `march_incrc_local` calls, two loop-invariant
    `native_f32_arr_length` calls, non-entry-block allocas). See
    `specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md`.
  - The TCO entry prologue leaks **one 32-byte box per call** (down from one
    per loop iteration) — unbounded for a long-lived process. See
    `specs/todos/2026-08-11-simd-tco-entry-box-leak.md`.
  - **Mutual**-TCO groups (`Llvm_tco.emit_mutual_tco_group`) still use `ptr`
    slots for vector params — correct, just not accelerated, and untested.
    Only self-TCO was in scope.

  DataFrame Min/Max is still NOT migrated to a `Simd` fast path: re-probed
  after the fix at **~8.2x** slower than the C reduction (down from ~35x),
  which is a real improvement but still not the "non-regression" the plan
  requires. A pinning test guards the unmigrated implementation so a future
  attempt has a regression net — though note that test file currently runs
  only when invoked by hand, not in CI
  (`specs/todos/2026-08-11-test-stdlib-march-files-not-in-ci.md`).
- **Task 5** — JS-target rejection message for `simd_*` builtins, docs
  (`docs/simd-vectorization.md`), changelog entry for compiled support,
  `docs/pagefind` regeneration.

As of Task 2, `--compile` on a program that calls any `Simd.*` function,
including `load_*`/`store_*`, compiles and runs correctly for straight-line
and index-only-recursive shapes. Task 4 found a gap for vector-typed
recursive accumulators specifically; Task 4b **fixed** it (commit `08c02ebb`,
see above), so vector-typed accumulators — both the self-tail-recursive and
the locally-nested-closure shapes — now compile and run correctly too. The
remaining open items are performance and a per-call leak, not correctness:
`specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md` and
`specs/todos/2026-08-11-simd-tco-entry-box-leak.md`.
