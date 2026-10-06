# DONE NativeArray builtins leaked the array (or list) they read

Found and fixed 2026-10-06, while building phase C of
`specs/plans/2026-09-28-nativearray-fusion-plan.md` (fold/sum fusion).

## The bugs

1. **Owned-but-never-released arguments.** `lib/tir/borrow.ml` listed the
   NativeArray `map`, `map2`, `fold`, `from_list`, `min`, `max`, `sumsq_dev`,
   `to_float_arr`, `filter_mask` and the eight width conversions in
   `extern_owned_builtins`, as "unaudited". Perceus therefore handed each call
   the last reference to its array (or list) argument, and the C function
   never released it. A `map(map(a, f), g)` in a loop leaked the whole
   intermediate array every iteration (1001 objects over 1000 iterations,
   fusion off); every `from_list` leaked its list; an array still used after
   a `map` gained a permanent extra reference, which also defeats any later
   uniqueness-based in-place update. The September 4 commit that made the
   NativeArray readers (`get`, `length`, `sum`, `to_list`) borrow had left
   `map` and `map2` owned "for now".
2. **`filter_mask` was not a builtin to Defun.** `native_int_arr_filter_mask`
   and `native_float_arr_filter_mask` were missing from `Defun`'s builtin
   names, so every call (DataFrame's column filter) was a `call_ptr`, where no
   borrow entry applies, and the filtered column leaked.
3. **The runtime Float map boxes were never released.** `clo_call_dbl_dbl` /
   `clo_call_dbl_dbl_dbl` (`runtime/march_runtime.c`), used by the runtime
   `native_float_arr_map(2)` and `native_f32_arr_map(2)`, boxed each element
   for the closure call and released neither the argument box nor the
   returned one: two leaked boxes per element (three for map2) whenever the
   callback could not be inlined. `native_float_arr_fold` already released
   both.

## The fix

- `borrow.ml`: each listed builtin moved to `extern_borrow_table`, after
  reading its C body (and the `DEF_NARROW_INT_ARR` macro for i32/u8): none
  frees or stores its array/list argument, and each returns a fresh
  allocation. The closure of map/map2/fold stays owned (released once after
  the loop) and so does fold's accumulator (handed to the callback). `set`
  and `sort` really consume their array and stay owned.
- `defun.ml`: the two `filter_mask` builtins added to the builtin names.
- `runtime/march_runtime.c`: the two helpers release the argument box(es)
  after the call and the returned box after reading it, as the fold does. An
  identity callback returns the argument box itself with its own reference,
  so the releases stay balanced (covered by the fixture).
- `native_map_inline.ml`: `strip_alias_chain` became `remove_alias_chain`.
  With the array borrowed, Perceus drops it right after the call, so the call
  and the closure's alias let now sit inside the RHS of a let
  (`let r = (let f = clo in map(a, f)) in dec_rc a; r`), where the old
  head-only peeling no longer found it. Without this the borrow change alone
  cost most inline loops (fold fixture 11 inline loops → 4, map fusion
  fixture 21 → 11, capturing map 9 → 3). The walker removes the alias lets in
  place and leaves every other item where it was; for the old shapes the
  result is the same tree. `vectorize_check.ml` uses it too.

## Verification

- `test/native/nativearray_builtin_borrow_leak_probe.march` (+ `.expected`,
  the interpreter's output): 13 legs, each building a fresh array or list per
  iteration whose last use is the builtin under test, 300 iterations,
  live_allocs must stay flat; the two `_rt` legs pick the callback at run time
  so the map stays on the runtime path, with identity and
  ignore-the-argument callbacks. On main all 13 legs leak; with the fix all
  are flat and the output matches the interpreter.
- Inline-loop IR checks (`native_arr_fold_inline`, `native_arr_map2_inline`,
  `native_arr_map_inline_capture`, `_reuse`, `_unboxed`,
  `native_arr_narrow_inline`, `_float_box_reuse`): the same counts as main.
  `nativearr_map_fusion` gained one inline loop (22 / 8 / 0 instead of
  21 / 8 / 1): its parameter-callback case, which Opt inlines into `main`, is
  now seen through the deeper alias chain. Its rule was updated.
- ASAN (Linux container, `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`): 32
  programs clean, every NativeArray / DataFrame / fold / Float-box fixture
  plus `bench/native_array_chains`, `bench/array_numeric` and the dataframe
  benches. The map2 length-panic fixture exits 1 by design.

## Benchmark

Same box, compilers built from this branch and from main (`--compile
--opt 2`), interleaved runs, minimum shown; every benchmark's results are
identical between the two.

- `bench/native_array_chains.march`: `sum(map(..))` written unfused got
  faster, Int 3.51 → 1.08 ms (3.3×) and Float 3.05 → 1.11 ms (2.7×): the
  intermediate array is freed now, so its 32 MB is reused instead of a fresh
  allocation paying page faults every call. Every other case is within ±6%.
- `bench/simd_sum.march` times ONE 5M-element sum right after `from_list`;
  that list (240 MB of cells and boxes) is now freed just before the timer
  instead of leaking, and the first one or two sums after the free are slower
  (0.6–3.9 ms). Twelve consecutive sums settle at 0.55–0.60 ms, the same as
  main's. `simd_map` is mixed the same way (better minimum, worse mean).
  `array_numeric` and `dataframe_bench` report whole milliseconds and read
  the same.

## Not done

- The TypedArray family has the same unaudited classification:
  `specs/todos/2026-10-06-typed-array-builtins-leak-their-argument.md`.
