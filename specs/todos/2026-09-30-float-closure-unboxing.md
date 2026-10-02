`[P2]` Unboxed Float calls through closures

Floats cross the erased closure ABI heap-boxed. `List.fold_left` over Floats through
a lambda measured 194 ms vs 16 ms for Ints and 11 ms hand-written (2M elements,
`bench/float_closure_calls.march`, 2026-09-30): ~90 ns/element of boxing.

Spec: `specs/plans/2026-09-30-float-closure-unboxing.md`. Part 1 routes known calls
to unboxed clones of the apply fn; part 2 is a new `hof_spec` pass specializing
static-argument higher-order functions on a known lambda so the call becomes
known. Depends on the fold inline loop spec's generalized unboxed-clone helper.
