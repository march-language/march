---
layout: docs
title: SIMD & Native Arrays
nav_order: 11.5
permalink: /docs/simd/
---

# SIMD & Native Arrays

`NativeArray` is a flat, contiguous numeric array type. Unlike `Array` (a
32-way persistent trie, optimized for structural sharing), `NativeArray` maps
directly onto sequential memory. That makes it cache-friendly for scan
patterns, and lets `march --compile` hand a handful of its operations
straight to LLVM's auto-vectorizer, so they run as real SIMD instructions
(NEON on arm64, SSE4.2+ on x86-64) instead of a scalar loop.

This page covers what actually vectorizes today, how to write code that
triggers it, and the known gaps; this is a fast path you opt into for
numeric hot loops, not the default representation for numeric data. It also
covers the explicit `Simd` module (five 128-bit vector types you construct
and operate on directly, see [below](#explicit-simd--the-simd-module)):
guaranteed vector codegen rather than a `NativeArray` loop the optimizer may
or may not vectorize.

```march
let arr = NativeArray.make_float(1_000_000, 0.0)
let doubled = NativeArray.map_float(arr, fn x -> x *. 2.0)
let total = NativeArray.sum_float(doubled)
```

---

## What vectorizes

Only **compiled** builds (`march --compile`) vectorize; the interpreter and
REPL never do, since there is no LLVM/clang pass in that path. Everything
below is correct either way; this section is about the compiled fast path.

- **`sum_int` / `sum_float`**: both auto-vectorize under `clang -O2`. `sum_float`
  needed a scoped `#pragma clang fp reassociate(on)` around the runtime C
  loop, since strict IEEE 754 float semantics otherwise forbid the reduction
  from reassociating at all (and thus from vectorizing).
- **`map_int`**: when the callback is a non-capturing lambda, or captures a
  single variable, the compiler inlines the callback directly into the loop
  instead of dispatching through a closure pointer. That lets clang's own
  inliner and vectorizer see straight through it, so arithmetic-heavy bodies
  (`fn x -> x * x + 1`, `fn x -> x + captured`) compile to real SIMD.
- **`map_float`**: gets the same inlining treatment as `map_int`. If the
  callback's signature is concretely all-`Float` (not still generic), the
  compiler goes one step further and clones the inlined callback under
  natural `double` parameters/return with **zero heap boxing**, and the loop
  vectorizes for real (confirmed via `-emit-llvm`: NEON `fadd.2d`/similar
  vector instructions, not just scalar unrolling).
- **`map2_int` / `map2_float`** (element-wise over two arrays, e.g.
  `col_add_col`'s column-column arithmetic) get the identical treatment:
  same eligibility bar, same boxing-free clone for a concrete-`Float`
  callback. Landed after the rest of this page (see the benchmark history
  below); previously these fell straight through to the general
  closure-dispatch path.

A closure that's **reused elsewhere** (passed to `map`/`map2` and also
called directly, or stored and called later), or that captures more than
one variable, still runs correctly; it just falls back to the general
closure-dispatch path, which does not vectorize.

## Narrow element widths

Beyond the `Int`/`Float` (i64/f64) element types shown above, `NativeArray`
also supports three narrower element widths: **f32**, **i32**, and **u8**
(backed by `NativeF32Arr`/`NativeI32Arr`/`NativeU8Arr`), each with the same
`make`/`length`/`get`/`set`/`sum`/`map`/`map2`/`from_list`/`to_list` shape as
`Int`/`Float`, plus 8 conversions to/from the wider types (e.g.
`NativeArray.int_to_u8_arr`). They exist to trade range/precision for memory
bandwidth and SIMD lane count: 50% of the bytes per element of f64/i64 means
twice the lanes per vector instruction.

**Boundary rule:** integer stores truncate mod 2^w two's-complement, float
stores round to nearest-even binary32, and loads widen exactly (`u8`
zero-extends to 0..255, `i32` sign-extends). `sum_i32`/`sum_u8` accumulate in
i64, `sum_f32` in double. None of this traps; an out-of-range store
wraps or rounds rather than erroring.

**f32 double-rounding caveat:** map callbacks compute in double and round to
f32 on store; results can differ in the last ulp from a true single-precision
pipeline.

`map_f32`/`map2_f32`/`sum_f32` get the identical inline-loop vectorization
treatment described above for `map_float`/`map2_float`/`sum_float`,
confirmed via `-emit-llvm` to compile to real `<4 x float>` NEON vector
instructions, not just scalar unrolling. `fold_i32`/`fold_u8`/`fold_f32`
(along with `fold_int`/`fold_float`) all have compiled implementations;
the fold accumulator is a generic `'a` that crosses the closure boundary in
the erased/boxed representation, so fold is a correctness-first scalar loop
rather than a vectorized one; see Known limitations below.

Same-box, same-build f32-vs-f64 comparison at N=5M (median of 6 samples,
two opposite orderings to cancel first-position warmup bias; see
`bench/RESULTS.md`'s `simd-f32` section for full methodology):

| Benchmark (N=5M) | f32      | f64      | Speedup |
|-------------------|----------|----------|---------|
| `sum(arr)`         | 0.49 ms  | 1.19 ms  | ~2.4x   |
| `map(x -> x*2+1)`  | 2.27 ms  | 4.54 ms  | ~2.0x   |
| `map2(a, b, +)`    | 2.67 ms  | 6.40 ms  | ~2.4x   |

`map`'s ~2.0x sits right at the theoretical upper limit from doubling the lane
count; `sum`/`map2` beat that ratio slightly, within the noise of a shared,
loaded benchmark machine (absolute ms are not a regression baseline across
runs; see the "Read this before the numbers" caveats on
[SIMD Benchmarks]({{ site.baseurl }}/docs/simd-benchmarks/)).

## How to trigger it

1. **Use `NativeArray`, not `Array` or `List`, for the hot data.** `Array`'s
   trie layout and `List`'s cons cells are not contiguous in memory, so
   none of this applies to them.
2. **Compile with `--compile --opt 2`.** `-O2` is what enables clang's
   auto-vectorizer; an interpreted or unoptimized build never vectorizes.
3. **Keep the callback simple and single-use.** A short arithmetic lambda
   passed to `map_int`/`map_float`/`map2_int`/`map2_float` and used in no
   other place gets inlined. If you need the same closure for multiple purposes,
   expect the general (non-vectorized, still correct) path.
4. **For `Float`, avoid leaving the callback's type generic** if you want the
   zero-boxing path: a concrete `Float -> Float` signature is what lets the
   compiler drop the boxing entirely.

You can confirm vectorization yourself with `march --compile --opt 2 --emit-llvm
your_file.march` and grepping the output for vector types (`<2 x double>`,
`<4 x float>`) or clang's `%vector.body` loop-vectorizer markers.

## Benchmarks

March vs. hand-written OCaml/Rust, idiomatic Elixir, naive Python, and NumPy
(a hand-tuned, BLAS-backed reference implementation) on three Float-array
operations over 5M elements:

| Benchmark (N=5M)                       | March    | OCaml   | Rust    | NumPy   |
|-----------------------------------------|----------|---------|---------|---------|
| `sum(arr)`                              | **1.1 ms** | 4.7 ms | 5.4 ms | 1.0 ms |
| `map(x -> x * 2.0 + 1.0)`                | 5.1 ms   | 5.5 ms  | 3.9 ms  | 2.1 ms |
| `map2(a, b, (x, y) -> x + y)`            | 6.4 ms   | 7.0 ms  | 4.5 ms  | 1.6 ms |

All three hold up: March ties a hand-tuned, BLAS-backed reference
implementation (NumPy) on `sum`, and is competitive with hand-written
OCaml/Rust on all three, via general-purpose LLVM auto-vectorization rather
than a hand-rolled numeric kernel. `map2` used to be the odd one out here
(**299 ms**, no inlining treatment, slower than naive interpreted Python)
until it got the same closure-inlining/boxing-elimination infrastructure `map`
already had; see the benchmark history in
[SIMD Benchmarks]({{ site.baseurl }}/docs/simd-benchmarks/) for the
before/after.

Full write-up (machine profile, methodology, per-language source links) at
[SIMD Benchmarks]({{ site.baseurl }}/docs/simd-benchmarks/). Reproduce
locally with `bash bench/run_benchmarks.sh` from a checkout.

## Known limitations

- **`fold_int` / `fold_float` / `fold_f32` / `fold_i32` / `fold_u8`** all have
  compiled implementations, but fold is not vectorized: the accumulator is a
  generic `'a` that must stay boxed/erased across the closure boundary for
  the whole loop, so it's a correctness-first scalar loop, not a SIMD one.
  Use `sum`/`map` if you need the auto-vectorized path and your reduction
  fits their shape.
- **`fold_float` / `fold_f32` with a `Float` accumulator used to leak ~32 B
  per element; FIXED 2026-08-20.** Each iteration's accumulator box was never
  released, so folding a 50M-element `NativeFloatArr` into a `Float` cost
  ~1.6 GB of otherwise-unexplained RSS (measured at 5M elements: 193.6 MB with
  a `Float` accumulator vs 40.4 MB for the `fold_int` control). The result was
  always correct; only memory residency was affected. All five fold helpers
  now release the previous accumulator, and the workarounds this entry used to
  recommend are no longer needed. Pinned by
  `test/native/native_arr_fold_acc_leak_probe.march`; see
  `specs/progress/2026-08-20-fold-accumulator-chain-leak-fix.md`.

  A fold with a **heap non-`Float`** accumulator (a `String`, `List`
  or record rebuilt each step) used to leak one object per element on top of
  that, because the runtime could not tell whether the closure it had just
  called consumed the accumulator it was given. Fixed 2026-08-22: the compiler
  now stamps that fact into the closure object and the fold helpers read it
  back; see
  `specs/progress/2026-08-22-fold-heap-accumulator-borrowed-return-leak.md`. It
  is set only when borrow inference can prove the accumulator has no owning
  use, so a callback that passes it to a builtin with undeclared borrow modes
  still leaks; that residual is described in the progress note. `Float` and
  `Int` accumulators, including `fold_int`, `fold_i32` and `fold_u8`, were
  never affected.
- **`DataFrame`**: `Sum`/`Mean` aggregation and `col_add_col` (column-column
  arithmetic, via `map2_int`/`map2_float`) use the vectorized `NativeArray`
  primitives above under the hood. `Min`/`Max`/`Std`/`Variance`/`Median`
  aggregation, `ColExpr`-based lazy-frame arithmetic, and `fill_null` do not
  yet; they're correct, just not on the fast path.
- Vectorization is an **LLVM/clang optimizer decision**, not a March
  language guarantee; it can depend on the target architecture and clang
  version. None of the above changes program *behavior*; a callback that doesn't
  qualify for inlining, or a loop clang declines to vectorize, still produces
  identical results, just via a scalar loop.

## Explicit SIMD: the `Simd` module

Everything above is the compiler deciding whether a `NativeArray` loop
qualifies for auto-vectorization: you write plain scalar code and it may or
may not compile to a vector instruction, depending on the callback shape and
what `clang -O2` chooses to do. `Simd` is the opposite trade: a fixed set of
128-bit vector types you construct and operate on explicitly, so the vector
lowering is **guaranteed**, not opportunistic.

### Types and operations

Five vector types, each holding a fixed number of lanes in a 128-bit value:

| Type     | Lanes | Element      |
|----------|-------|--------------|
| `F32x4`  | 4     | `Float` (binary32, stored widened) |
| `F64x2`  | 2     | `Float` (binary64) |
| `I32x4`  | 4     | `Int` (32-bit, wraps mod 2^32) |
| `I64x2`  | 2     | `Int` (64-bit, wraps mod 2^64) |
| `U8x16`  | 16    | `Int` (0..255, zero-extended) |

Each type gets the same op families, named `Simd.<op>_<type>`, e.g.
`Simd.add_f32x4`, `Simd.load_u8x16`, `Simd.hmax_i32x4`:

- **Construction/access:** `splat`, `make` (one arg per lane), `extract`,
  `replace`, `load` (from a matching `NativeArray`), `store`.
- **Compare/bitwise/select:** `eq`, `lt`, `gt` (mask results: all-ones lane
  where true, zero otherwise), `and`, `or`, `xor`, `not`, `select`
  (mask-driven per-lane choice between two vectors), plus mask-consuming
  scans: `any`, `all`, `first_set`. All four mask consumers read a lane's
  **high bit** (its sign bit): in `select`, a lane with its high bit set
  picks `a`, otherwise `b`. The canonical all-ones/all-zero lanes that
  `eq`/`lt`/`gt` produce read identically under any convention; the high-bit
  rule is what a hand-rolled non-canonical mask (say a lane of `0xFFFFFFFE`)
  follows, and it is the same rule interpreted and compiled.
- **Arithmetic:** `add`, `sub`, `mul`, `min`, `max`, `sum` (horizontal,
  accumulated sequentially: float families in double, int families in
  `i64`), `hmin`, `hmax`; float families additionally get `div`, `fma`
  (true fused multiply-add, one rounding; can differ from a separate
  multiply-then-add in the last ulp) and `sqrt`; integer families
  additionally get `shl`/`shr`.

That is 127 operations total across the five types. Lane get/set indices
(`extract`, `replace`, `load`/`store` offsets) are refinement-typed to the
type's lane count, so an out-of-range literal index is a compile-time
refinement-check failure rather than a runtime panic. An index the
refinement checker cannot decide is *not* rejected (March reports only
definite failures), so every such index is bounds-checked at run time and
panics out of range: `load`/`store` against the array length, `extract`/
`replace` against the lane count. A statically in-range literal lane index
skips the check and compiles to a bare `extractelement`/`insertelement`.
Each type implements `Show`, `Eq`, and `Hash`.

**Boundary rule**, matching `NativeArray`'s narrow-width contract: lane
get/set traffics in widened `Int`/`Float`; integer narrowing on store wraps
mod 2^w two's-complement; `f32` narrowing rounds to nearest-even; `u8` loads
zero-extend, `i32` loads sign-extend. `min`/`max`/`hmin`/`hmax` on floats use
minNum/maxNum semantics (a NaN operand loses to the other; both-NaN is NaN).
None of this traps on out-of-range *values*; only out-of-range
**indices** panic. Lane 0 is the first `make_*` argument / the
lowest-addressed element on `load`.

```march
let a = Simd.load_f32x4(arr, 0)
let b = Simd.splat_f32x4(2.0)
let doubled = Simd.mul_f32x4(a, b)
let total = Simd.sum_f32x4(doubled)
```

### The register-residency contract

`--compile` lowers every `Simd` op, including `load`/`store`, to native
LLVM vector instructions/intrinsics (`<4 x float>`, `llvm.fma.v4f32`, etc.),
not a scalar loop standing in for one. A vector value is **register-resident**
inside a function body and boxed into a 32-byte runtime cell only at the
boundaries where it has to cross one: a call, a return, or a store into an
aggregate field. Two shapes are guaranteed allocation-free (confirmed via
`--emit-llvm`, pinned by fixtures):

1. A **straight-line kernel**: construct, operate, consume, all within one
   function body with no intervening call that takes the vector as an
   argument.
2. A **self-tail-recursive accumulator loop**: the natural shape for a
   dot-product-style horizontal reduction, where the vector is threaded as
   the function's own parameter across each recursive call. The accumulator
   stays in a vector register across iterations; the loop body performs no
   allocation.

`store_*` follows `NativeArray`'s FBIP contract: an in-place update when the
array isn't shared, a copy-on-write when it is.

### The candid performance story

Guaranteed vector codegen is not automatically a performance win over the
implicit path above; it depends on the shape of the computation:

| Kernel (N=5M `f32` / 16MB `u8`)                      | Result |
|-------------------------------------------------------|--------|
| `u8` delimiter scan: `Simd` vs. scalar March loop      | **~11.5x** faster |
| Dot product loop framework, held constant: `Simd` vs. scalar March index loop (same elementwise/reduce shape, no library calls either side) | **4.0x** faster |
| Dot product: hand-written `Simd` accumulator loop vs. `NativeArray.map2_f32` + `sum_f32` composition | `Simd` loop **~3.9x slower** (10.0 ms vs. 2.55 ms) |

The scanner and the loop-framework comparison are `Simd` doing exactly what
it is for: cross-lane, register-resident vector work beating a scalar loop
by close to the lane-count ratio. The third row looks like a regression but
isn't one: it is not a SIMD cost at all. `NativeArray.map2_f32`/`sum_f32`
each compile to a single call into a tight C runtime loop; a hand-written
March index loop, `Simd`-accumulated or not, pays per-iteration overhead
unrelated to vectors (a preemption check, a stack
save/restore, RC bookkeeping on locals, an unhoisted length call). That
overhead is tracked as its own item, general to every hand-written
`NativeArray` index loop:
`specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md`.

**Recommendation:** for a simple elementwise-then-reduce pipeline (map,
then sum; map2, then reduce), reach for `NativeArray.map`/`map2`/`sum`
first; they already compile to the tight C loop and currently beat a
hand-rolled `Simd` loop doing the same computation. Reach for `Simd`
directly when you need something `NativeArray`'s builtin ops don't express:
cross-lane structure (masks, `select`, comparisons feeding a scan),
fused multi-op kernels (e.g. `fma` in one instruction), or byte-level
scanning, where `Simd` is a clear win.

`DataFrame`'s `Min`/`Max` aggregation was evaluated against a `Simd`-based
migration and intentionally **not** migrated: a probe measured a
`Simd.min_i64x2`/`max_i64x2` accumulator loop at ~8.2x slower than the
existing `native_int_arr_min`/`native_float_arr_min` C reduction, for the
same index-loop-overhead reason above. Note the upper limit here is lower even
once that overhead is fixed: `i64x2`/`f64x2` are only 2 lanes wide (vs. 4
for the `f32x4`/`i32x4`/`u8x16` families used in the scanner/dot-product
comparisons), so a Min/Max migration is a re-open condition on the index-
loop-overhead fix, not a closed door. See `bench/RESULTS.md`'s
`simd-kernels` section for full methodology and numbers.

### Fixed 128-bit width

`Simd` is fixed at 128 bits on every target, rather than a portable/
scalable width that adapts to the host's widest vector unit (AVX2/AVX-512
on some x86-64 hosts, SVE on some arm64 hosts). That was an intentional
choice, not an oversight: 128 bits is the width every target this compiles
to actually has (NEON on arm64, SSE2 baseline on x86-64, and it aligns
with WASM-SIMD's 128-bit vectors), so a `Simd` program has **identical
semantics on every target**, interpreted or compiled, with no runtime
feature detection and no "may run at a different width depending on the
machine that built it" caveat. It also keeps interpreter/native parity
testing tractable: one lane count per type, not a matrix over host vector
widths. A portable/scalable width is a plausible future layer on top of
this (e.g. a `Simd.wide_*` variant sized at compile time to the host), but
it is additive; this fixed-128 module is not something a portable-width
feature needs to replace.

### Known limitations

- **TCO-entry box leak; fixed 2026-08-11.** A self-tail-recursive function's
  vector accumulator used to leak one 32-byte box per **call** (not per loop
  iteration; the loop body itself, per the register-residency contract
  above, is allocation-free). The call site now releases the caller-created
  temp box for callees with a native vector TCO slot; measured RSS on a
  2,000,000-call probe went from ~64 MB to ~2.7 MB. The fix is narrow:
  non-TCO vector params still leak per call, and three call paths
  (raises-wrapper, blocking-extern, hot-reload dispatch) are intentionally
  excluded; see `specs/todos/2026-08-12-simd-nontco-vector-param-leak.md` for
  the still-open generalization. Pinned by
  `test/native/simd_leak_probe.march` (leak must happen) and
  `test/native/simd_vector_escape_arg.march` (release must NOT happen for an
  escaping vector). See `specs/progress/2026-08-11-simd-tco-entry-box-leak.md`.
- **Mutual-recursion accumulators stay boxed.** The register-residency
  optimization above covers self-tail-recursion only; a vector threaded
  through a mutual-recursion group is still correct but boxes/unboxes on
  every call, same as before the TCO optimization landed. This is a
  intentional wontfix-until-demand, not a gap-in-waiting. `test/native/
  simd_mutual_tco.march` pins it two ways: an output diff (the boxed path
  still computes the right answer) and an IR-shape rule
  (`simd_mutual_tco_llvm_check` in `test/dune`) asserting a `@__mutco_*`
  dispatcher is emitted at all with both accumulator slots boxed as
  `alloca ptr`. The second rule is not redundant: the two lowerings print
  the same number, and the fixture was briefly an empty check because the TIR
  inliner collapsed the mutual pair into self-recursion. So a change to the
  mutual-TCO slot strategy can neither silently corrupt the result nor
  silently stop being tested. See
  `specs/progress/2026-08-13-simd-closeouts-task3-mutual-tco-pin.md`.
- **`fma` is a true fused multiply-add** (`llvm.fma.v4f32`/`v2f64`, one
  rounding); it can differ from a separate multiply followed by an add in
  the last ulp. Both backends run the same operation on both widths: for
  `f64x2` the interpreter uses OCaml's `Float.fma` (binary64-fused), and for
  `f32x4` it emulates a *single*-rounded binary32 fma (round-to-odd over
  binary64, `eval.ml`'s `fma32_single_round`) rather than double-rounding a
  binary64 `Float.fma`, which is what it did until 2026-08-13 and which
  truly diverged in the last ulp on rounding-boundary triples. Pinned by
  test t15 of the `simd_vector` suite and fuzzed compiled-vs-interpreted over
  400k boundary-heavy lanes by `test/native/simd_fma_fuzz.march`.
- **`i64x2` interpreter parity edge:** lane values beyond ±2^62 lose their
  top bit under the interpreter only, because OCaml's native `int` is
  63-bit. Compiled `i64x2` uses a true 64-bit lane and has no such limit.
  Tests are confined to ±2^62 to avoid asserting on the divergent range.
- **`==`/`show` under a polymorphic context fall back to generic runtime
  helpers**, not the static `Eq`/`Show` impl. At a statically-known vector
  type, `==` dispatches the type's `Eq` impl (lane-wise, NaN lanes unequal)
  and `show` renders per-lane. Under an erased type variable (a generic
  function that never specializes the vector type), both instead go
  through the same pointer-identity/opaque-tag runtime helpers `NativeArray`
  already has this caveat with; not specific to `Simd`.
- **Not supported on the JavaScript target.** Fixed 128-bit SIMD has no JS
  lowering; compiling any `Simd.*` call with `--target js` fails the build
  with a diagnostic naming the builtin, rather than emitting a call that
  throws `ReferenceError` at runtime. Use `NativeArray`'s `map`/`map2`/`sum`
  for numeric hot loops on that target instead.

## See also

- [Standard Library → NativeArray]({{ site.baseurl }}/docs/stdlib/NativeArray.html): full API reference.
- [Standard Library → DataFrame]({{ site.baseurl }}/docs/stdlib/DataFrame.html): columnar data built on `NativeArray`.
- [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/): parallelizing across cores, a different axis from vectorizing within one core.
- [Value Representation]({{ site.baseurl }}/docs/value-representation/): how March values are represented at the bit level, including the float-boxing tradeoff mentioned above.
- [Memory Model]({{ site.baseurl }}/docs/memory-model/): Perceus reference counting and FBIP, the allocation model underneath the register-residency contract above.
