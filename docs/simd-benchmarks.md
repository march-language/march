---
layout: docs
title: SIMD Benchmarks
nav_order: 11.6
permalink: /docs/simd-benchmarks/
---

# SIMD Benchmarks

Cross-language numbers for the numeric-array operations described in
[SIMD & Native Arrays]({{ site.baseurl }}/docs/simd/). This page covers three
stories, in order: (1) the original cross-language comparison: March vs.
hand-written OCaml and Rust, idiomatic Elixir, naive interpreted Python, and
NumPy (a hand-tuned, BLAS-backed reference implementation) on three
`Float`(f64)-array operations, all three now competitive (`map2` wasn't
always one of them; see [Fix history: map2](#fix-history-map2) for the
before/after); (2) a March-only, same-box **f32 vs. f64** narrow-width
comparison, plus a like-for-like f32 rematch against NumPy (see [Narrow
element widths: f32 vs. f64](#narrow-element-widths-f32-vs-f64)); and (3) the
explicit `Simd` module's own validation kernels: a byte-scanning win and an
candid dot-product loss against `NativeArray`'s composed fast path (see
[Simd module kernels](#simd-module-kernels)).

---

## Read this before the numbers

**This is a shared development machine, not a dedicated benchmark box.**
The run below shared the machine with several other active sessions; load
average was **7.9–11.1** at the time, on a 14-core machine. That mostly
washes out for the SIMD numbers specifically (each program self-times only
its own operation over up to a few milliseconds; see Methodology), but
treat everything here as directional, not authoritative. Run it yourself on
your own hardware if the exact numbers matter to you; the reproduction
command is at the bottom of this page.

**No cherry-picking.** These are the median/min/max of 10 runs, taken
directly from a single invocation of `bench/run_benchmarks.sh`, unedited.
Where March loses or is only mid-pack, that's shown too (`map` loses to Rust
here; `map2` did too, along with everything else, before the fix below).

**Reproducing this.** `bench/run_benchmarks.sh` now prints its own provenance
before it times anything: date, host, CPU, core count, load average, and the
version of every compiler it resolved, including March's taken from the
`dune exec` compiler that actually builds the benchmarks rather than from
whatever `march` sits on `PATH`. If a comparison language is missing it announces
this visibly and names the rows that will be absent, because the old failure mode was
quiet: a missing tool dropped that language's row and produced a smaller table
with no indication it was smaller. The tables below and the profile beneath them
were transcribed from such a run; the run prints them so you never have to take
this page's word for it.

## Machine profile

| | |
|---|---|
| Chip | Apple M3 Max |
| Cores | 14 (10 performance + 4 efficiency) |
| Memory | 36 GB |
| OS | macOS 26.5.2 (Darwin 25.5.0, arm64) |
| Load average at run time | 7.89, 11.10, 10.28 (1m/5m/15m), **not idle** |
| Date | 2026-07-27 |

## Versions

| Language | Version | Compilation |
|----------|---------|------------|
| March    | HEAD    | `march --compile --opt 2` → clang native |
| OCaml    | 5.3.0   | `ocamlopt` native (`simd-*` link `unix` via `ocamlfind`) |
| Rust     | 1.94.0  | `rustc -O` native |
| Elixir   | 1.20.1-otp-29 | BEAM JIT (script mode) |
| Python   | 3.14.3  | CPython, interpreted |
| NumPy    | 2.5.1   | vectorized/BLAS reference |
| clang    | 17.0.0 (Apple) | backs `march --compile` and `rustc` codegen |

---

## Methodology

Every benchmark operates on 5,000,000 `Float`s. **Each program self-times
only the operation under test**; data generation and (for interpreters)
process startup are excluded from the reported number. This isn't the usual
whole-process wall-clock this project's other benchmarks use (see
[the fib/binary-trees/tree-transform/list-ops results](https://github.com/march-language/march/blob/main/bench/RESULTS.md));
it's necessary here because building the input dominates the operation
itself at this scale. Building a 5M-element `List` of boxed floats in March
(the natural way to construct one, then convert with
`NativeArray.from_list_float`) costs ~200ms on its own; that's ~150x the
~1ms the vectorized `sum` actually takes. Measuring the whole process would
report "how fast March allocates a linked list," not the SIMD claim under
test, and every other language would face the same distortion from its own
input-construction cost, which is likewise unrelated to vectorization.

Two per-language notes, both to keep the comparison fair rather than to flatter
March: OCaml's `Array.fold_left`/`Array.map` box every float through a
polymorphic accumulator (confirmed ~5x slower than a manual loop), not what
a performance-conscious OCaml numeric loop looks like, so the OCaml sources
use manual `for` loops instead. Rust's iterator-based `.sum()`/`.map()`/`.zip()`
were checked against a manual-loop control and found already at parity; Rust's
zero-cost-abstraction claim applies here, so the idiomatic iterator form is used
as-is.

Run 10 times per language per benchmark; median, min, max reported.

## Results

### `sum(arr)`: Float array reduction

| Language | Median | Min | Max |
|----------|-------:|----:|----:|
| **March** | **1.1 ms** | 1.0 ms | 1.4 ms |
| OCaml | 4.7 ms | 4.7 ms | 4.8 ms |
| Rust | 5.4 ms | 5.3 ms | 6.5 ms |
| Elixir | 83.9 ms | 81.2 ms | 91.7 ms |
| Python | 296.9 ms | 283.0 ms | 319.3 ms |
| NumPy | 1.0 ms | 1.0 ms | 1.0 ms |

`native_float_arr_sum` auto-vectorizes under `clang -O2`; see
[SIMD & Native Arrays]({{ site.baseurl }}/docs/simd/#what-vectorizes) for the
`#pragma clang fp reassociate(on)` this needed. March ties NumPy here.

**Source:** [`bench/simd_sum.march`](https://github.com/march-language/march/blob/main/bench/simd_sum.march) ·
[`bench/ocaml/simd_sum.ml`](https://github.com/march-language/march/blob/main/bench/ocaml/simd_sum.ml) ·
[`bench/rust/simd_sum.rs`](https://github.com/march-language/march/blob/main/bench/rust/simd_sum.rs) ·
[`bench/elixir/simd_sum.exs`](https://github.com/march-language/march/blob/main/bench/elixir/simd_sum.exs) ·
[`bench/python/simd_sum.py`](https://github.com/march-language/march/blob/main/bench/python/simd_sum.py) ·
[`bench/python/simd_sum_numpy.py`](https://github.com/march-language/march/blob/main/bench/python/simd_sum_numpy.py)

### `map(x -> x * 2.0 + 1.0)`: elementwise Float map

| Language | Median | Min | Max |
|----------|-------:|----:|----:|
| March | 5.1 ms | 4.8 ms | 5.5 ms |
| OCaml | 5.5 ms | 5.4 ms | 5.6 ms |
| **Rust** | **3.9 ms** | 3.7 ms | 4.3 ms |
| Elixir | 244.8 ms | 236.9 ms | 281.8 ms |
| Python | 194.1 ms | 192.9 ms | 199.5 ms |
| NumPy | 2.1 ms | 2.1 ms | 2.9 ms |

This one needs a compiler-side trick, not just clang: March's closure-call
ABI heap-boxes every `Float` crossing a call boundary, which blocks
vectorization entirely. For a concrete-`Float`, single-use callback like this
one, a dedicated pass inlines the callback and drops the boxing so the loop
vectorizes; without it, this number would look like `map2`'s before-the-fix numbers
below, not like this (the pass details are in
[Compiler internals](#compiler-internals)). March is competitive with
hand-written OCaml/Rust and within 3x of NumPy.

**Source:** [`bench/simd_map.march`](https://github.com/march-language/march/blob/main/bench/simd_map.march) ·
[`bench/ocaml/simd_map.ml`](https://github.com/march-language/march/blob/main/bench/ocaml/simd_map.ml) ·
[`bench/rust/simd_map.rs`](https://github.com/march-language/march/blob/main/bench/rust/simd_map.rs) ·
[`bench/elixir/simd_map.exs`](https://github.com/march-language/march/blob/main/bench/elixir/simd_map.exs) ·
[`bench/python/simd_map.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map.py) ·
[`bench/python/simd_map_numpy.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map_numpy.py)

### `map2(a, b, (x, y) -> x + y)`: elementwise two-array zip

| Language | Median | Min | Max |
|----------|-------:|----:|----:|
| March | 6.4 ms | 6.3 ms | 8.8 ms |
| OCaml | 7.0 ms | 6.9 ms | 7.1 ms |
| **Rust** | **4.5 ms** | 4.3 ms | 4.8 ms |
| Elixir | 101.6 ms | 99.4 ms | 132.0 ms |
| Python | 197.1 ms | 189.3 ms | 207.5 ms |
| NumPy | 1.6 ms | 1.5 ms | 1.6 ms |

`NativeArray.map2_int`/`map2_float` (added to unblock
`DataFrame.col_add_col`, column-column arithmetic) now gets the same
inlining/boxing-elimination treatment `map` does, so a concrete-`Float`
callback vectorizes the same way. Beats OCaml, within 3x of NumPy.
([Compiler internals](#compiler-internals) covers how the pass was extended to
the two-array shape.)

### Fix history: map2

This wasn't always true. `map2` originally shipped **correctness-first**:
the primitive itself (runtime, interpreter, typechecker, compiled-path
registration) landed without the inlining pass most other `NativeArray`
operations get, a known, explicitly-documented scoping decision. The numbers
made the cost of that gap concrete rather than a caveat:

| | March (before) | March (after) | Speedup |
|---|---:|---:|---:|
| `map2` | 299.2 ms | 6.4 ms | **~47x** |

Before the fix, every element dispatched through the general closure-call
path (heap-box each argument, indirect call through the closure's function
pointer, unbox the result): 299ms, **slower than naive interpreted
Python**, and ~47x slower than March's own `map` doing essentially the same
arithmetic. The inlining pass was extended to the two-array `map2` shape the
same day these numbers were first published; [Compiler
internals](#compiler-internals) covers what that took.

**Source:** [`bench/simd_map2.march`](https://github.com/march-language/march/blob/main/bench/simd_map2.march) ·
[`bench/ocaml/simd_map2.ml`](https://github.com/march-language/march/blob/main/bench/ocaml/simd_map2.ml) ·
[`bench/rust/simd_map2.rs`](https://github.com/march-language/march/blob/main/bench/rust/simd_map2.rs) ·
[`bench/elixir/simd_map2.exs`](https://github.com/march-language/march/blob/main/bench/elixir/simd_map2.exs) ·
[`bench/python/simd_map2.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map2.py) ·
[`bench/python/simd_map2_numpy.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map2_numpy.py)

---

## Narrow element widths: f32 vs. f64

Added 2026-08-10 alongside `NativeArray.make_f32`/`map_f32`/`map2_f32`/`sum_f32`
(narrow `f32` element storage, 50% of the width of the `f64`/`Float` element
storage every table above uses). `bench/simd_f32.march` runs the same three
shapes as `simd-sum`/`simd-map`/`simd-map2` above (`sum`,
`map(fn x -> x *. 2.0 +. 1.0)`, `map2(fn (x, y) -> x +. y)`) at the same
N=5M, self-timed the same way (data generation excluded; see Methodology
above). Unlike the tables above, this one is **March-only, same-box,
same-build, f32 vs. f64**: the point isn't a cross-language comparison, it's
whether halving the element width (and doubling the SIMD lane count) actually
pays off. Absolute ms are not a regression baseline across machine/load
states; the f32/f64 *ratio* measured in the same run is what matters.

Methodology: 6 timed samples per operation (two 3-run round-robins, one
`f32, f64-sum, f64-map, f64-map2` ordered and one reversed, to cancel the
first-timed-variant warmup bias this page's other tables also control for;
neither f32 nor f64 was consistently first).

| N=5M | f32 | f64 | Speedup |
|------|----:|----:|--------:|
| `sum(arr)` | 0.49 ms | 1.19 ms | ~2.4x |
| `map(x -> x*2+1)` | 2.27 ms | 4.54 ms | ~2.0x |
| `map2(a, b, +)` | 2.67 ms | 6.40 ms | ~2.4x |

`map`'s ~2.0x sits right at the theoretical upper limit from doubling the lane
count; `sum`/`map2` beat that ratio slightly, within the noise of a shared,
loaded benchmark machine. `map_f32`/`map2_f32`/`sum_f32` get the identical
inline-loop vectorization treatment `map_float`/`map2_float`/`sum_float` get
above, confirmed via `-emit-llvm` to compile to real `<4 x float>` NEON
vector instructions, not just scalar unrolling.

### Cross-language f32 rematch: March vs. NumPy

A second run after the narrow-widths work merged, this time including NumPy
at both element widths; the NumPy rows in the `sum`/`map`/`map2` tables
above are float64 (`np.arange(n) / 100.0` yields float64), so
`bench/python/simd_{sum,map,map2}_numpy_f32.py` (explicit
`.astype(np.float32)`, float32 scalar operands) exist to make the f32
comparison like-for-like. Same self-timed-operation-only protocol as every
table on this page; March legs are medians of 10 samples, NumPy legs medians
of 5, interleaved.

| N=5M, medians (ms) | March f64 | March f32 | NumPy f64 | NumPy f32 |
|---------------------|----------:|----------:|----------:|----------:|
| `sum` | 1.02 | **0.40** | 0.70 | 0.74 |
| `map(x*2+1)` | 3.69 | **1.81** | 1.58 | 2.05 |
| `map2(a+b)` | 4.90 | **1.85** | 1.18 | 1.76 |

March f32/f64 ratios in this run track the table above (sum 2.5x, map 2.0x,
map2 2.6x). Like-for-like at f32, **March beats NumPy on `sum` (1.8x) and
`map` (~13%), and ties it on `map2` (~5%)**; the pre-narrow-widths 4x `map2`
gap (6.4 ms vs 1.6 ms, see [Fix history: map2](#fix-history-map2)) is gone.
Don't overclaim past that: this is one comparison on one shared machine, not
a universal "March beats NumPy" result, and `map` on f64 still trails NumPy
in the main table above.

**Source:** [`bench/simd_f32.march`](https://github.com/march-language/march/blob/main/bench/simd_f32.march) ·
full methodology and load-state notes in
[`bench/RESULTS.md`](https://github.com/march-language/march/blob/main/bench/RESULTS.md)'s
`simd-f32` section.

---

## Simd module kernels

Added 2026-08-11 as the validation kernels for the explicit `Simd` module
(128-bit vector types; see [SIMD & Native Arrays → Explicit SIMD]({{
site.baseurl }}/docs/simd/#explicit-simd--the-simd-module)).
`bench/simd_kernels.march` runs two explicit-`Simd`-vs-baseline pairs,
compiled only (`--compile --opt 2`), self-timed the same way as every other
table on this page: a dot product (5,000,000 `f32` pairs) and a delimiter
scan (16,000,000 `u8` bytes). Medians of 5 interleaved rounds; per-leg
coefficient of variation stayed under 5%.

| `scan(16MB u8)` | Median | Min | Max |
|------------------|-------:|-------:|-------:|
| `scan_simd` (`Simd.eq_u8x16` + `first_set_u8x16`) | 19.28 ms | 19.07 ms | 20.41 ms |
| `scan_scalar` (byte-at-a-time March loop) | 221.32 ms | 221.14 ms | 222.97 ms |

**`scan_simd` is ~11.5x faster** than the scalar byte-at-a-time loop: the
classic memchr-shaped SIMD win: `--emit-llvm` confirms the loop never
allocates (the mask value is consumed immediately by `first_set_u8x16`
within the same iteration, never escaping as a call argument).

| `dot(5M f32)` | Median | Min | Max |
|----------------|-------:|-------:|-------:|
| `dot_simd` (hand-written `Simd` accumulator loop) | 10.01 ms | 9.96 ms | 10.13 ms |
| `dot_composed` (`NativeArray.map2_f32` + `sum_f32`) | 2.55 ms | 2.40 ms | 2.72 ms |

**`dot_simd` is ~3.9x *slower*** than `dot_composed`, and that gap is not a
SIMD cost. Holding the loop framework constant and comparing only the vector
lowering isolates why:

| 5M f32 dot, loop framework held constant | ms |
|--------------------------------------------|-----:|
| SIMD index loop (4 lanes/iter) | 9.89 |
| scalar index loop (1 elem/iter) | 39.95 |
| `map2_f32` + `sum_f32` (one C call) | 2.34 |

The **SIMD index loop is 4.0x faster than the equivalent scalar March index
loop** over the same 5M pairs; the vector lowering is doing its job.
`dot_composed` wins for an unrelated reason: it's a single call into a tight
C runtime pipeline, while any hand-written March index loop, `Simd`-driven
or not, pays per-iteration overhead unrelated to vectors (a
preemption check, a stack save/restore, RC bookkeeping on locals, an
unhoisted length call). That overhead is general to every hand-written
`NativeArray` index loop and is tracked separately at
`specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md`; `dot_simd`
keeps its straightforward accumulator-loop shape rather than being
rewritten around the gap, so the comparison stays fair.

**Recommendation** (same as [SIMD & Native Arrays]({{ site.baseurl
}}/docs/simd/#the-honest-performance-story)): for a simple
elementwise-then-reduce pipeline, reach for `NativeArray.map`/`map2`/`sum`
first. Reach for `Simd` directly for cross-lane structure (masks, `select`,
scans), fused multi-op kernels (`fma`), or byte-level scanning, where, as
the scan numbers above show, it's a clear and large win.

`DataFrame`'s `Min`/`Max` aggregation was evaluated against a `Simd`-based
migration on the same shape and intentionally **not** migrated: a
`Simd.min_i64x2`/`max_i64x2` accumulator loop measured ~8.2x slower than the
existing `native_int_arr_min`/`native_float_arr_min` C reduction, for the
same index-loop-overhead reason above (and with a lower upper limit even once
that's fixed: `i64x2`/`f64x2` are only 2 lanes wide, vs. 4 for the
`f32x4`/`i32x4`/`u8x16` families used above).

**Source:** [`bench/simd_kernels.march`](https://github.com/march-language/march/blob/main/bench/simd_kernels.march) ·
full methodology, load-state notes, and the DataFrame Min/Max probe in
[`bench/RESULTS.md`](https://github.com/march-language/march/blob/main/bench/RESULTS.md)'s
`simd-kernels` section.

---

## Compiler internals

> For compiler hackers: you don't need any of this to *use* `NativeArray`. It records
> the infrastructure behind the boxing-free numeric fast path the benchmarks above exercise.

The inlining and boxing-elimination live in the `Native_map_inline.ml` pass. It
recognizes a `map`/`map2` call with a callback that is fresh, single-use, and either
non-capturing or single-capture (the same eligibility bar for both shapes), inlines that
callback into the loop, and, when the callback's signature is concretely all-`Float`,
clones it under natural `double` parameters and return with zero heap boxing (internally
"`Float`-boxing Stage 4, Option B"). The two-array `map2` support reuses the identical
synthetic-call-name mechanism and unboxed-clone path as single-array `map`; it just
matches a 3-argument call shape (two arrays + closure) instead of `map`'s 2-argument one.

Because the inlined loop bypasses the `native_int_arr_map2` / `native_float_arr_map2`
runtime helpers entirely, it includes its own length-mismatch guard
(`native_arr_map2_check_len` in `runtime/march_runtime.c`) so it still panics on a length
mismatch exactly like the non-inlined path, covered by a dedicated regression test, not
just the happy path.

---

## Reproducing

```bash
# From a march-language/march checkout:
bash bench/run_benchmarks.sh

# More iterations (default is 10):
RUNS=20 bash bench/run_benchmarks.sh
```

The NumPy row needs a local venv (not committed to the repo):

```bash
python3 -m venv bench/.venv
bench/.venv/bin/pip install numpy
```

Every other row and benchmark runs without it; the script detects
`bench/.venv` and skips the NumPy row if it's absent.

The runner ([`bench/run_benchmarks.sh`](https://github.com/march-language/march/blob/main/bench/run_benchmarks.sh))
also compares `fib(40)`, `binary-trees(15)`, `tree-transform`, and `list-ops`
against OCaml/Rust/Elixir: allocation, recursion, and HOF-pipeline shaped
workloads unrelated to SIMD. Full results, including those, are in
[`bench/RESULTS.md`](https://github.com/march-language/march/blob/main/bench/RESULTS.md).

## See also

- [SIMD & Native Arrays]({{ site.baseurl }}/docs/simd/): what vectorizes, how to trigger it, known limitations.
- [Standard Library → NativeArray]({{ site.baseurl }}/docs/stdlib/NativeArray.html): full API reference.
- [Standard Library → Simd]({{ site.baseurl }}/docs/stdlib/Simd.html): full API reference for the explicit 128-bit vector types.
