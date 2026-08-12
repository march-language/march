# Simd vector types — compiled path (Tasks 3–5) — DONE

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
  scanner legs; the scanner beat its ≥4x bar (~11.5x, `bench/RESULTS.md`'s
  own pairing: 221.32 / 19.28 ≈ 11.48) but the dot product
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

## Task 5 — done (this file's completion)

JS-target rejection, docs, changelog, and bookkeeping, closing out the plan:

- **JS-target rejection**: `lib/tir/js_emit.ml`'s `unmapped_msgs` mapper
  (~L1371-1393) gained a family case that prefix-matches any unmapped
  builtin named `simd_*` (every `Simd` builtin uses that prefix) and reports
  a dedicated message naming the builtin and the fixed-128-bit-has-no-JS-
  lowering reason, instead of the generic "no JavaScript-target
  implementation" message every other unmapped builtin gets. TDD: the new
  `test/test_codegen.ml` `js_pipeline` case ("simd builtin rejected") was
  written first against `Simd.splat_f32x4`, confirmed red against the
  generic message, then went green after the family-match arm landed.
- **`docs/simd-vectorization.md`**: new "Explicit SIMD — the `Simd` module"
  section — the five types and 127 ops (op-family table), the boundary
  rule, the register-residency contract (straight-line kernels and
  self-tail-recursive accumulator loops are allocation-free), the honest
  benchmark table (scanner ~11.5x, loop-framework-held-constant 4.0x, but
  `Simd` dot product still ~3.9x *slower* than the `NativeArray.map2_f32`+
  `sum_f32` composition — attributed to general March index-loop overhead,
  not a SIMD cost, with a usage recommendation), the fixed-128-bit-width
  rationale (parity, NEON/SSE2/WASM-SIMD baseline, portable-width as a
  future additive layer), and the known-limitations list (TCO-entry
  per-call box leak, unaccelerated mutual-recursion accumulators, true-fma
  ulp difference, i64x2 interpreter-only parity edge above ±2^62,
  polymorphic-context `==`/`show` fallback, JS-target unsupported).
- **`CHANGELOG.md`**: the three fragmentary `Simd` bullets from Tasks 1-4
  (one `Added` entry for the module + two separate `Fixed` entries for the
  Task 4b closure-ABI and TCO-residency fixes) consolidated into one
  coherent `Added` entry under `[Unreleased]`, folding in the performance
  story and the new JS-rejection behavior rather than leaving four
  fragments a reader has to reassemble.
- **`docs/pagefind`** regenerated via `scripts/gen-docs-search-index.sh`;
  `--check` exits 0.
- Other doc pages referencing `Simd` were checked
  (`grep -rl "Simd" specs/lang specs/features docs --include='*.md'`):
  `specs/lang/types/INDEX.md` only references `Simd` in the context of its
  refinement-type reject/accept fixture list (lane-index bounds tests,
  unrelated to this task's scope) and needed no change; the two
  `docs/superpowers/` plan/design files are gitignored planning artifacts,
  not served docs.

All items from `docs/superpowers/plans/2026-08-10-simd-vector-types.md` are
now either shipped or tracked in their own dated `specs/todos/` entries:
`specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md` (general
March index-loop overhead, not SIMD-specific) and
`specs/todos/2026-08-11-simd-tco-entry-box-leak.md` (per-call box leak in
the TCO entry prologue). Nothing else remains open on this plan.

**Op-surface deviation.** The spec's prose carried a rough "~90 operations"
estimate; what shipped is **127**. The estimate was never normative — the
per-type op grid in the plan's Global Constraints is, and 127 is exactly
what that grid enumerates once every family is instantiated across all five
types (float-only `div`/`fma`/`sqrt` and integer-only `shl`/`shr` make the
per-type counts uneven). No op outside the grid was added and none was
dropped; only the informal headline number was off.
