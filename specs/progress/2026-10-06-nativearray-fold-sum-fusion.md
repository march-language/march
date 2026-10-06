# DONE NativeArray fold(map) and sum(map) fusion (phase C)

Done 2026-10-06. Phase C of `specs/plans/2026-09-28-nativearray-fusion-plan.md`
(its "Phase 2: fold and sum", second half). The open todo
`specs/todos/2026-09-28-nativearray-fusion.md` stays open for phases D and E.
Builds on the borrow fix in
`specs/progress/2026-10-06-nativearray-builtins-leak-their-argument.md`, found
while doing this.

## The change

- **fold(map) — `lib/tir/fusion.ml`** (`Fusion.run_nativearr`, after Mono,
  before Defun). The wrapper table now also records
  `NativeArray.fold_<w>(arr, acc, f)` whose body is exactly
  `native_<w>_arr_fold(acc, arr, f)`, as kind `NaFold`. A fold whose array
  input is a single-use map of the same width becomes one fold:

      fold(map(a, f), z, g)  →  fold(a, z, fn (s, x) -> let t = f_body[x] in g_body[s, t])

  The same eligibility rules as phase B apply (lambda literals in the chain,
  pure bodies, nothing impure in between, no name capture, u8/i32 wrapped
  between the bodies, f32 never). Only input 0 (the array) is fused, never
  the accumulator; a fold is never a producer; a map2 feeding a fold is not
  fused (it would need a fold2). The fold keeps its strict, in-order callback,
  and `Native_map_inline` turns it into the inline fold loop as before. The
  old `rewrite` was split into the composition step and a shared `splice`.
- **sum(map) — `lib/tir/native_map_inline.ml`**, a peephole after the
  inline-loop rewrite (so after Perceus). A sum whose argument is the result
  of an inline map/map2 loop used only by that sum and its drop,

      let t = (..; __native_<w>_arr_map(2)_inline(args)) in .. let r = native_<w>_arr_sum(t) in dec_rc t; k ..

  becomes one `__native_<w>_arr_summap(2)_inline(args)` loop bound where the
  map was, and `let r = t'`: no intermediate array, no allocation, no drop.
  The map's RHS may end in the call itself or in `let x = call in dec_rc a; x`
  (the array dying at the call); the sum binding is found along lets,
  sequences and case arms, never inside a lambda. Int-family maps (tagged
  ABI) and Float-family maps through the unboxed clone only, like the fold
  loop. `sum(map2(..))` is included because it is a dot product.
- **The loop — `lib/tir/llvm_emit_nmap.ml`** (`emit_native_summap_inline_loop`,
  dispatched from `llvm_emit.ml`). Per element: load, widen, direct call,
  then narrow to the memory type and widen back (the intermediate array's
  store and the sum's load: u8 wraps, f32 rounds to binary32), then add. Int
  widths add in `i64`; Float widths use `fadd reassoc double`, the same
  scoped reassociation `native_float_arr_sum` / `native_f32_arr_sum` grant
  with `#pragma clang fp reassociate(on)`, so a fused Float sum vectorizes
  like the runtime one. map2's length-mismatch panic is kept.
- **Not in Fusion.** The plan proposed rewriting `sum(map)` in `Fusion` into a
  new synthetic builtin. Doing it after `Native_map_inline` instead needs no
  new runtime function, no Defun/Mono/Perceus registration, and no fallback
  when the callback is not inlinable: if there is no inline map loop, there is
  nothing to fuse.
- **Kill switch.** `MARCH_NO_NATIVEARR_FUSION=1` turns off both
  (`Native_map_inline.run ~sum_map:false`); it was already a CAS tag.

## Verification

- `test/native/nativearr_fold_sum_fusion.march` (+ `.expected`, the
  interpreter's output; dyadic Float inputs so a reassociated sum equals the
  in-order one). Positives: fold of a map (Int, Int capturing, Float, Float
  order-sensitive, u8 and i32 wrapping, a map chain, empty); sum of a map for
  all five widths (f32 rounding, u8/i32 wrapping), capturing callbacks, a
  Float dot product, a capturing Int map2, a map chain, empty arrays.
  Negatives that must stay correct: an intermediate used twice, one read
  before the sum, a fold of a map2, an impure fold callback, a map as the
  fold's accumulator, an f32 fold, a callback passed as a parameter. A leak
  loop runs three fused shapes 200 times and must stay flat.
- IR shape rule: 15 sum-map loops, 12 fold loops, 5 map loops, 1 map2 loop
  (the negatives), 2 runtime sums (the two intermediates read twice), with
  reassociating Float sums; with `MARCH_NO_NATIVEARR_FUSION=1`: 0 / 12 / 28 /
  4 and 17 runtime sums.
- Perturbations, each restored afterwards (`cmp`-identical): removing the
  u8/i32 wrap from the fold composition changed the two narrow fold lines;
  removing the store/load round trip from the sum loop changed the f32, u8
  and i32 sum lines; weakening the "exactly two uses" check to `>= 2` made
  the read-before-the-sum case fail to compile (`use of undefined value`).
- `native_arr_map_inline_capture` and `native_arr_narrow_inline` check the
  MAP loop, and each of their maps feeds a sum, so their IR-shape rules now
  run with `MARCH_NO_NATIVEARR_FUSION=1`; every other inline-loop IR check is
  unchanged.
- ASAN (Linux container): 29 programs clean, every NativeArray / DataFrame /
  fold fixture including this one, plus `bench/native_array_chains` and
  `bench/array_numeric`.

## Benchmark

`bench/native_array_chains.march`, `--compile --opt 2`, one compiler with and
without `MARCH_NO_NATIVEARR_FUSION=1` (which also turns off phase B's map
fusion), 4 interleaved runs of each binary, minimum ms, Apple M3 Max, load
~17. Checksums match.

| case | variant | fusion on | fusion off |
|---|---|---:|---:|
| int_map_fold | unfused | 0.477 | 2.919 |
| int_map_fold | hand-fused | 0.453 | 0.442 |
| flt_map_fold | unfused | 3.058 | 3.790 |
| flt_map_fold | hand-fused | 3.063 | 3.032 |
| int_map_sum | unfused | 0.487 | 1.115 |
| int_map_sum | hand-fused as a fold | 0.443 | 0.474 |
| flt_map_sum | unfused | 0.458 | 1.122 |
| flt_map_sum | hand-fused as a fold | 3.015 | 3.080 |

The written-unfused fold and sum chains now run at the hand-fused speed or
better. A fused Float sum (0.46 ms) beats hand-fusing it into a fold
(3.0 ms): the fold is strict, so its scalar `fadd` chain cannot vectorize,
while the sum loop reassociates like the runtime sum. The Float fold stays at
3.06 ms for the same reason; that is the price of an in-order fold. The map
and map2 rows (phase B) are unchanged from its own measurement.
