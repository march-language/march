# NativeArray narrow element widths: f32, i32, u8

Landed 2026-08-09/10 (plan: `.superpowers/sdd/2026-08-09-native-array-narrow-types/`).

`NativeArray` previously supported exactly two element widths — `Int` (i64,
`NativeIntArr`) and `Float` (f64, `NativeFloatArr`). This adds three narrower
widths — **f32**, **i32**, **u8** — with the full interpreter and compiled
API, plus inline-loop vectorization for the compiled path.

## What shipped, by task

- **Task 1 (a0100f48)** — widened the `NativeArray` runtime header from 24B
  to 32B, adding an `elem_kind` tag (`0=i64, 1=f64, 2=f32, 3=i32, 4=u8`) and
  moving the data pointer to a 16-byte-aligned offset (32). These layout
  decisions are **frozen phase-C hooks** — later work (e.g. a phase-C SIMD
  widening pass) can rely on the header shape and alignment without another
  ABI break. The always-on runtime check in `native_arr_alloc` asserts the
  16-byte alignment on every allocation, so any regression here is caught by
  every test that allocates a `NativeArray`, not by a dedicated assertion.
- **Tasks 2-3** — full interpreter and compiled API per width: `make`,
  `length`, `get`, `set`, `sum`, `map`, `map2`, `from_list`, `to_list`, plus
  8 conversions between the five element types (e.g.
  `NativeArray.int_to_u8_arr`, `f32_to_float_arr`). `fold_f32`/`fold_i32`/
  `fold_u8` were **excluded from the compiled path** — deliberately, not an
  oversight — because the existing `fold_int`/`fold_float` compiled linkage
  is itself unimplemented (see `docs/simd-vectorization.md`'s Known
  limitations); the narrow-width folds inherit the identical gap and will
  land together with the fix for the existing two, rather than duplicating
  a linkage strategy that doesn't exist yet.
- **Task 4** — inline-loop vectorization for the new widths, matching the
  existing `map_float`/`map2_float`/`sum_float` treatment: a
  non-capturing/single-capture callback with a concrete signature gets
  cloned under natural (unboxed) parameters and inlined directly into the
  loop, so clang's auto-vectorizer sees through it. Manually confirmed via
  `-emit-llvm` that `map_f32` compiles to real `<4 x float>` NEON vector
  instructions (double the lane count of `map_float`'s `<2 x double>`), not
  just scalar unrolling with a wider element.
- **Task 5** — `bench/simd_f32.march` + `bench/RESULTS.md`'s `simd-f32(5M)`
  section: same-box, same-build f32-vs-f64 comparison (not cross-language;
  see that section for the two-orderings methodology used to cancel
  first-timed-variant warmup bias). Medians: sum 0.49ms vs 1.19ms (~2.4x),
  map 2.27ms vs 4.54ms (~2.0x, at the theoretical 2x-lane-count ceiling),
  map2 2.67ms vs 6.40ms (~2.4x).
- **Task 6 (this entry)** — docs (`docs/simd-vectorization.md`'s new
  "Narrow element widths" section: the three widths, the boundary rule, the
  f32 double-rounding caveat, the benchmark table), the `stdlib/
  native_array.march` header comment ("two opaque element types" → five,
  synced to `share/march/native_array.march`), `specs/lang/actors.md`'s
  non-sendable-types list (was missing the three new backing types even
  though `lib/typecheck/typecheck.ml`'s `non_sendable_types` already
  included them), and this progress entry.

## Boundary semantics (verbatim, load-bearing)

Integer stores truncate mod 2^w two's-complement; float stores round to
nearest-even binary32; loads widen exactly (`u8` zero-extends to 0..255,
`i32` sign-extends). `sum_i32`/`sum_u8` accumulate in i64, `sum_f32` in
double. None of this ever traps.

**f32 double-rounding caveat:** map callbacks compute in double and round to
f32 on store; results can differ in the last ulp from a true single-precision
pipeline.

## Name grid

| Width | Type            | make/length/get/set/sum/map/map2/from_list/to_list |
|-------|-----------------|------------------------------------------------------|
| i64   | `NativeIntArr`   | `*_int` (pre-existing)                                |
| f64   | `NativeFloatArr` | `*_float` (pre-existing)                              |
| f32   | `NativeF32Arr`   | `*_f32`                                               |
| i32   | `NativeI32Arr`   | `*_i32`                                               |
| u8    | `NativeU8Arr`    | `*_u8`                                                |

Plus 8 conversions crossing between the five element types (e.g.
`int_to_u8_arr`, `f32_to_float_arr`, `u8_to_int_arr`).

## Fold exclusion

`fold_i32`/`fold_u8`/`fold_f32` exist only on the interpreter path. Calling
any `fold_*` variant (existing or narrow) from a `--compile` build fails to
link — this predates the narrow-width work and applies uniformly; the narrow
widths were not given a bespoke compiled fold implementation because that
would mean solving the same linkage problem twice. Once `fold_int`/
`fold_float`'s compiled linkage gap closes, the narrow variants should follow
the same fix rather than being revisited independently.

## Verification

- `scripts/run-tests.sh` and `scripts/check-docs.sh` both green (see commit
  for exact run).
- Benchmarks run compiled (`--opt 2`), not interpreted, per
  `bench/tree_transform.march`-style convention — see `bench/simd_f32.march`
  and `bench/RESULTS.md`'s `simd-f32(5M)` section for the full run.
