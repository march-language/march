---
layout: docs
title: SIMD & Native Arrays
nav_order: 9.6
permalink: /docs/simd/
---

# SIMD & Native Arrays

`NativeArray` is a flat, contiguous numeric array type — unlike `Array` (a
32-way persistent trie, optimized for structural sharing), `NativeArray` maps
directly onto sequential memory. That makes it cache-friendly for scan
patterns, and lets `march --compile` hand a handful of its operations
straight to LLVM's auto-vectorizer, so they run as real SIMD instructions
(NEON on arm64, SSE4.2+ on x86-64) instead of a scalar loop.

This page covers what actually vectorizes today, how to write code that
triggers it, and the known gaps — this is a fast path you opt into for
numeric hot loops, not the default representation for numeric data.

```march
let arr = NativeArray.make_float(1_000_000, 0.0)
let doubled = NativeArray.map_float(arr, fn x -> x *. 2.0)
let total = NativeArray.sum_float(doubled)
```

---

## What vectorizes

Only **compiled** builds (`march --compile`) vectorize — the interpreter and
REPL never do, since there is no LLVM/clang pass in that path. Everything
below is correct either way; this section is about the compiled fast path.

- **`sum_int` / `sum_float`** — both auto-vectorize under `clang -O2`. `sum_float`
  needed a scoped `#pragma clang fp reassociate(on)` around the runtime C
  loop, since strict IEEE 754 float semantics otherwise forbid the reduction
  from reassociating at all (and thus from vectorizing).
- **`map_int`** — when the callback is a non-capturing lambda, or captures a
  single variable, the compiler inlines the callback directly into the loop
  instead of dispatching through a closure pointer. That lets clang's own
  inliner and vectorizer see straight through it, so arithmetic-heavy bodies
  (`fn x -> x * x + 1`, `fn x -> x + captured`) compile to real SIMD.
- **`map_float`** — gets the same inlining treatment as `map_int`. If the
  callback's signature is concretely all-`Float` (not still generic), the
  compiler goes one step further and clones the inlined callback under
  natural `double` parameters/return with **zero heap boxing**, and the loop
  vectorizes for real (confirmed via `-emit-llvm`: NEON `fadd.2d`/similar
  vector instructions, not just scalar unrolling).

A closure that's **reused elsewhere** (passed to `map` and also called
directly, or stored and called later), or that captures more than one
variable, still runs correctly — it just falls back to the general
closure-dispatch path, which does not vectorize.

## How to trigger it

1. **Use `NativeArray`, not `Array` or `List`, for the hot data.** `Array`'s
   trie layout and `List`'s cons cells are not contiguous in memory, so
   nothing here applies to them.
2. **Compile with `--compile --opt 2`.** `-O2` is what enables clang's
   auto-vectorizer; an interpreted or unoptimized build never vectorizes.
3. **Keep the callback simple and single-use.** A short arithmetic lambda
   passed to `map_int`/`map_float` and used nowhere else gets inlined. If you
   need the same closure for multiple purposes, expect the general
   (non-vectorized, still correct) path.
4. **For `Float`, avoid leaving the callback's type generic** if you want the
   zero-boxing path — a concrete `Float -> Float` signature is what lets the
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
| `sum(arr)`                              | **1.3 ms** | 4.8 ms | 5.4 ms | 1.0 ms |
| `map(x -> x * 2.0 + 1.0)`                | 6.4 ms   | 5.5 ms  | 4.3 ms  | 2.4 ms |
| `map2(a, b, (x, y) -> x + y)`            | 299.2 ms | 7.0 ms  | 6.3 ms  | 1.7 ms |

`sum` and `map` are genuine wins — March ties a hand-tuned, BLAS-backed
reference implementation (NumPy) and is competitive with hand-written
OCaml/Rust, via general-purpose LLVM auto-vectorization rather than a
hand-rolled numeric kernel. `map2` is the honest counterpoint: it has none of
the inlining/vectorization treatment described above yet, and the number
shows it — slower even than naive interpreted Python for the same operation.

Full write-up (machine profile, methodology, per-language source links) at
[SIMD Benchmarks]({{ site.baseurl }}/docs/simd-benchmarks/). Reproduce
locally with `bash bench/run_benchmarks.sh` from a checkout.

## Known limitations

- **`fold_int` / `fold_float` have no compiled implementation yet** — calling
  either from a `--compile` build fails to link. Use `sum`/`map` or a manual
  index loop until this lands.
- **`map2_int` / `map2_float`** (element-wise over two arrays, e.g. for
  column-column arithmetic) are correct in both interpreted and compiled
  builds, but do not yet get the `map_int`/`map_float` inlining/vectorization
  treatment — each element still dispatches through a closure-pointer call.
- **`DataFrame`**: `Sum`/`Mean` aggregation and `col_add_col` (column-column
  arithmetic) use the vectorized `NativeArray` primitives above under the
  hood. `Min`/`Max`/`Std`/`Variance`/`Median` aggregation, `ColExpr`-based
  lazy-frame arithmetic, and `fill_null` do not yet — they're correct, just
  not on the fast path.
- Vectorization is an **LLVM/clang optimizer decision**, not a March
  language guarantee — it can depend on the target architecture and clang
  version. Nothing above changes program *behavior*; a callback that doesn't
  qualify for inlining, or a loop clang declines to vectorize, still produces
  identical results, just via a scalar loop.

## See also

- [Standard Library → NativeArray]({{ site.baseurl }}/docs/stdlib/NativeArray.html) — full API reference.
- [Standard Library → DataFrame]({{ site.baseurl }}/docs/stdlib/DataFrame.html) — columnar data built on `NativeArray`.
- [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/) — parallelizing across cores, a different axis from vectorizing within one core.
- [Memory Model]({{ site.baseurl }}/docs/memory-model/) — how March values are represented, including the float-boxing tradeoff mentioned above.
