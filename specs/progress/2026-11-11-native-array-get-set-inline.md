# Inline NativeArray get/set in compiled code — DONE (2026-11-11)

Reported by the Strata project: after its fluid step moved from persistent maps to flat
`NativeIntArr`s, profiling showed every `NativeArray.get_int` / `set_int` as an out-of-line
call into the C runtime (`native_int_arr_get` / `_set`), on every cell access.

## Change

`lib/tir/llvm_emit_narr.ml`, reached from an `emit_expr` arm in `lib/tir/llvm_emit.ml` just
after the SIMD arm, emits the five element widths (int, float, f32, i32, u8) inline:

- **get**: load the length from +16, `icmp ult i, len` (one unsigned compare also rejects a
  negative index), then load at `arr + 32 + i * size`, widened as the C helper does (i32
  sign-extends, u8 zero-extends, f32 `fpext`s to double). The failing branch calls the
  original `native_<w>_arr_get`, which prints the same message and exits, then `unreachable`.
- **set**: the store is inline only when the C helper would itself write in place: index in
  bounds, `IS_HEAP_PTR(arr)`, and an acquire load of the refcount reading 1
  (`march_rc_is_unique`). It returns `arr`. Every other case (out of bounds, or a shared
  array that needs copy-on-write) calls the original `native_<w>_arr_set`, which consumes the
  reference exactly as before. Perceus's view (argument consumed, result owned) is unchanged.

Layout checked against `runtime/march_runtime.c` (`native_arr_alloc`, `NATIVE_ARR_HDR` = 32 in
`march_runtime.h`): rc at +0, length at +16, kind byte at +24, elements from +32. No runtime
change. A user function or local with the same name as a runtime accessor keeps the plain call.

## `&&` / `||`

The same report found `||` evaluating its right operand when the left already decided the
result (an out-of-bounds read in the fluid hash table). That was already fixed on main by
`specs/progress/2026-11-11-and-or-short-circuit.md`; Strata's toolchain predated it. The
regression test below includes Strata's exact `||` guard.

## Tests

`test/test_codegen.ml`, suite "native array inline access": one program covering every width
(narrowing on store, widening on load), copy-on-write of a shared array and Strata's `||`
guard, run interpreted and compiled with identical output; negative-index get and set still
die with the runtime's message; and in the `--emit-llvm` output every runtime get/set call
sits in its slow-path block. With the new arm disabled the IR assertion goes red. The
existing `native_arr_bounds_panic` dune rule still pins the ten out-of-bounds messages.

## Benchmark

Strata `bench/fluid_step.march` (`FLUID_HALF=32`), compiled `--opt 2` by main at 1a4251bc8
with and without this change. Strata needed two local edits to build on current main (the
capability `Result` from `Env.get_int`, and masking `Coord.mix`'s multiplies, which overflow
63 bits); both binaries were built from the same edited copy.

- Static runtime call sites: 98 get / 60 set before, 58 / 57 after (each inline site keeps one
  cold call on its failing branch).
- Instructions retired (`/usr/bin/time -l`, 3 runs each, per fluid step from the
  `FLUID_REPS=1` vs `20` difference): 0.837 G before, 0.805 G after, about 3.8% fewer.
- Wall time under load average 240-450, alternating runs: medians 3.50 vs 3.65 µs/cell-step
  (n=10) and 6.72 vs 6.11 (n=8, `FLUID_REPS=20`), so no change is measurable above the noise.
- `sample` profile: `native_int_arr_get` (76 samples before) is gone; the step is dominated by
  Strata's chunk lookups, drop glue and allocation, so the array calls were a small share.
