# SIMD closeouts, Task 3: pin mutual-TCO vector correctness

**Filed/closed:** 2026-08-13, third of a 3-task closeout plan for the SIMD
vector-types feature (`.superpowers/sdd/2026-08-12-simd-closeouts/`). Tasks 1
and 2 fixed a real bug each (vector arg-box leak; interpreter fma rounding
parity). Task 3 is a **pin**, not a fix: there is no bug here to close, only a
correctness invariant worth locking down against regression.

## Background

`lib/tir/llvm_tco.ml` combines a MUTUAL-recursion group (functions that
tail-call each other, not just themselves) into one dispatcher function with
a shared parameter-slot layout. A vector-typed parameter threaded through
that group keeps a uniform boxed `ptr` slot — the group boxes/unboxes the
vector on every call — unlike a SELF-tail-recursive function (`emit_fn`'s
path), which promotes a vector parameter to a native `<N x T>` register slot
(see `test/native/simd_leak_probe.march`, Task 1's fixture, and the fix it
pins).

This asymmetry is deliberate: extending native vector-slot residency to
mutual-recursion groups is real but unscoped work, tracked as "no todo" —
wontfix-until-demand — in `docs/simd-vectorization.md`'s "Known limits". It
is NOT something this closeout changes. What Task 3 adds is a fixture proving
the boxed path is still numerically correct, so a future person touching
`llvm_tco.ml`'s parameter-slot logic gets a red test instead of a silent
miscompile if they break it.

## What was added

- `test/native/simd_mutual_tco.march` — `even_step`/`odd_step` mutually
  tail-call each other threading a `Simd.F32x4` accumulator over a 16-lane
  `NativeArray.make_f32` source: `even_step` adds a freshly loaded 4-lane
  chunk, `odd_step` multiplies by `splat_f32x4(1.0)` (identity, to also
  exercise a second op on the boxed accumulator without changing the
  expected value). `main` requires `Cap(IO.Console)` per the current strict
  capability rule. Verified interpreted first (`dune exec march --`) —
  prints `16.` — then `.expected` was produced from that run.
- `test/dune` — a compile-run-diff rule pair for `simd_mutual_tco`, modeled
  on `simd_vector_core`'s (compile once, run once, diff stdout against
  `.expected`; no RSS assertion needed here, this is a correctness pin, not
  a leak guard).
- `lib/tir/llvm_tco.ml` — the mutual-TCO boxed-slot comment now cites this
  fixture and this file by path instead of only gesturing at
  docs/simd-vectorization.md.

## Verification

- `dune exec march -- test/native/simd_mutual_tco.march` → `16.` (interpreted)
- Compiled binary via the new `test/dune` rule reproduces `16.` byte-for-byte
  (asserted every `dune build @test/runtest`).
- Manual trace: `a` is 16 lanes of `2.0`. `even_step(a,0,16,[0,0,0,0])` loads
  `[2,2,2,2]` → `odd_step` multiplies by 1 (no-op) → `even_step` adds the next
  4-lane chunk `[2,2,2,2]` giving `[4,4,4,4]` → `odd_step` multiplies by 1
  again → `i=16 >= n=16`, `sum_f32x4([4,4,4,4]) = 16.0`. Matches.

## Pointers

- `test/native/simd_mutual_tco.march`, `test/native/simd_mutual_tco.expected`
- `test/dune` (search `simd_mutual_tco`)
- `lib/tir/llvm_tco.ml` (the mutual-TCO param-slot alloca comment)
- Sibling closeouts: `specs/progress/2026-08-11-simd-tco-entry-box-leak.md`
  (Task 1), `specs/progress/2026-08-13-simd-fma-rounding-parity.md` (Task 2)
