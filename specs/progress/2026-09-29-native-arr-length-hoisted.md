# `native_*_arr_length` hoisted out of loops (direction 1)

Direction 1 of `specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md`.
(Direction 2, `march_incrc_local` on borrowed params, was already done by #417; directions
3-4 remain open.)

**Change.** The five `native_{int,float,f32,i32,u8}_arr_length` declares in
`lib/tir/llvm_builtins.ml` now carry `nounwind willreturn speculatable memory(none)`.
The C body does read the length word (header offset 16), but that word is written once,
in `native_arr_alloc`, and never again, and the array is live for every use of its pointer,
so the call is a pure function of its argument. `memory(none)` is the right level rather
than `memory(argmem: read)`: with `argmem: read` the loop's `march_incrc_local` call may
write the same object, so LICM still cannot hoist. An inline `load ... !invariant.load`
was tried on paper and rejected: the array params are only `dereferenceable(16)` (the
header), so the offset-16 load is not provably safe to speculate.

**Evidence** (`--emit-llvm` writes `<source>.ll`; the `.ll` is pre-optimisation, so it was
then run through `clang -O2 -S -emit-llvm`). `dot_loop` in `bench/simd_kernels.march`:

- before: `tail call i64 @native_f32_arr_length` for `%a` and `%b` inside `case_default5` /
  `vld_ok8`, i.e. in the loop, every iteration;
- after: both calls sit in `entry`, before `br label %tco_loop1`.

**Measurement** (`bench/simd_kernels.march`, compiled `--opt 2`, arm64 Mac, load average
about 9, 8 alternating runs of baseline-then-new, baseline = a copy of the origin/main
compiler): `DOT_SIMD_TIME_MS` min 10.72 -> 9.44 (median 11.07 -> 9.69). The other three
kernels are within noise (`dot_composed` 2.16/2.29, `scan_simd` 7.60/7.58,
`scan_scalar` 81.4/84.9). The remaining `dot_simd` vs `dot_composed` gap is the other
directions (preempt check, RC calls, in-loop allocas).

**Test.** `test_native_int_arr_ir` (test/test_codegen.ml) pins the declare's attributes.
