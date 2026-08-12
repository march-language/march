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
  scanner legs; the scanner beat its ≥4x bar (~11.5x) but the dot product
  failed its "beats the composed baseline" bar (~10.8x slower) due to a
  compiled-only residency gap — see
  `specs/todos/2026-08-11-simd-nested-closure-vector-accumulator-segfault.md`
  (also documents a related segfault for the closure-nested variant of the
  same loop shape). DataFrame Min/Max was NOT migrated to a `Simd` fast path
  as a result (measured ~35x slower on the equivalent probe); a pinning test
  was added instead so a future migration attempt has a regression net.
- **Task 5** — JS-target rejection message for `simd_*` builtins, docs
  (`docs/simd-vectorization.md`), changelog entry for compiled support,
  `docs/pagefind` regeneration.

As of Task 2, `--compile` on a program that calls any `Simd.*` function,
including `load_*`/`store_*`, compiles and runs correctly for straight-line
and index-only-recursive shapes. Task 4 found a gap for vector-typed
recursive accumulators specifically — see
`specs/todos/2026-08-11-simd-nested-closure-vector-accumulator-segfault.md`.
