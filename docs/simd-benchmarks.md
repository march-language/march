---
layout: docs
title: SIMD Benchmarks
nav_order: 11.6
permalink: /docs/simd-benchmarks/
---

# SIMD Benchmarks

Cross-language numbers for the Float-array operations described in
[SIMD & Native Arrays]({{ site.baseurl }}/docs/simd/). March vs. hand-written
OCaml and Rust, idiomatic Elixir, naive interpreted Python, and NumPy (a
hand-tuned, BLAS-backed reference implementation) — three operations, one
that vectorizes cleanly, one that vectorizes with a compiler-side trick, and
one that (honestly) doesn't vectorize at all yet.

---

## Read this before the numbers

**This is a shared development machine, not a dedicated benchmark box.**
The run below shared the machine with several other active sessions — load
average was **8.5** (1-minute) at the time, on a 14-core machine. That mostly
washes out for the SIMD numbers specifically (each program self-times only
its own operation over up to a few milliseconds — see Methodology), but
treat everything here as directional, not authoritative. Run it yourself on
your own hardware if the exact numbers matter to you; the reproduction
command is at the bottom of this page.

**No cherry-picking.** These are the median/min/max of 10 runs, taken
directly from a single invocation of `bench/run_benchmarks.sh`, unedited.
Where March loses or is only mid-pack, that's shown too (`simd-map2` is not
just mid-pack — it's the slowest language here by a wide margin, including
slower than naive interpreted Python; see below for why).

## Machine profile

| | |
|---|---|
| Chip | Apple M3 Max |
| Cores | 14 (10 performance + 4 efficiency) |
| Memory | 36 GB |
| OS | macOS 26.5.2 (Darwin 25.5.0, arm64) |
| Load average at run time | 8.49, 10.05, 8.50 (1m/5m/15m) — **not idle** |
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
only the operation under test** — data generation and (for interpreters)
process startup are excluded from the reported number. This isn't the usual
whole-process wall-clock this project's other benchmarks use (see
[the fib/binary-trees/tree-transform/list-ops results](https://github.com/march-language/march/blob/main/bench/RESULTS.md));
it's necessary here because building the input dominates the operation
itself at this scale. Building a 5M-element `List` of boxed floats in March
(the natural way to construct one, then convert with
`NativeArray.from_list_float`) costs ~200ms on its own — that's ~150x the
~1ms the vectorized `sum` actually takes. Measuring the whole process would
report "how fast March allocates a linked list," not the SIMD claim under
test, and every other language would face the same distortion from its own
input-construction cost, which has nothing to do with vectorization either.

Two per-language notes, both to keep the comparison fair rather than to flatter
March: OCaml's `Array.fold_left`/`Array.map` box every float through a
polymorphic accumulator (confirmed ~5x slower than a manual loop) — not what
a performance-conscious OCaml numeric loop looks like, so the OCaml sources
use manual `for` loops instead. Rust's iterator-based `.sum()`/`.map()`/`.zip()`
were checked against a manual-loop control and found already at parity — Rust's
zero-cost-abstraction claim holds here, so the idiomatic iterator form is used
as-is.

Run 10 times per language per benchmark; median, min, max reported.

## Results

### `sum(arr)` — Float array reduction

| Language | Median | Min | Max |
|----------|-------:|----:|----:|
| **March** | **1.3 ms** | 0.9 ms | 3.2 ms |
| OCaml | 4.8 ms | 4.7 ms | 5.0 ms |
| Rust | 5.4 ms | 5.2 ms | 5.5 ms |
| Elixir | 84.2 ms | 83.1 ms | 97.2 ms |
| Python | 308.8 ms | 288.1 ms | 391.3 ms |
| NumPy | 1.0 ms | 0.9 ms | 1.5 ms |

`native_float_arr_sum` auto-vectorizes under `clang -O2` — see
[SIMD & Native Arrays]({{ site.baseurl }}/docs/simd/#what-vectorizes) for the
`#pragma clang fp reassociate(on)` this needed. March ties NumPy here.

**Source:** [`bench/simd_sum.march`](https://github.com/march-language/march/blob/main/bench/simd_sum.march) ·
[`bench/ocaml/simd_sum.ml`](https://github.com/march-language/march/blob/main/bench/ocaml/simd_sum.ml) ·
[`bench/rust/simd_sum.rs`](https://github.com/march-language/march/blob/main/bench/rust/simd_sum.rs) ·
[`bench/elixir/simd_sum.exs`](https://github.com/march-language/march/blob/main/bench/elixir/simd_sum.exs) ·
[`bench/python/simd_sum.py`](https://github.com/march-language/march/blob/main/bench/python/simd_sum.py) ·
[`bench/python/simd_sum_numpy.py`](https://github.com/march-language/march/blob/main/bench/python/simd_sum_numpy.py)

### `map(x -> x * 2.0 + 1.0)` — elementwise Float map

| Language | Median | Min | Max |
|----------|-------:|----:|----:|
| March | 6.4 ms | 5.3 ms | 7.6 ms |
| OCaml | 5.5 ms | 5.4 ms | 5.6 ms |
| **Rust** | **4.3 ms** | 3.9 ms | 5.1 ms |
| Elixir | 252.8 ms | 242.2 ms | 323.6 ms |
| Python | 193.5 ms | 191.3 ms | 202.2 ms |
| NumPy | 2.4 ms | 2.1 ms | 3.7 ms |

This one needs a compiler-side trick, not just clang: March's closure-call
ABI heap-boxes every `Float` crossing a call boundary, which blocks
vectorization outright. For a concrete-`Float`, single-use callback like this
one, a dedicated pass clones the inlined callback under natural `double`
params with zero boxing (`Float`-boxing Stage 4, Option B) — without it, this
number would look like `map2`'s below, not like this. March is competitive
with hand-written OCaml/Rust and within 3x of NumPy.

**Source:** [`bench/simd_map.march`](https://github.com/march-language/march/blob/main/bench/simd_map.march) ·
[`bench/ocaml/simd_map.ml`](https://github.com/march-language/march/blob/main/bench/ocaml/simd_map.ml) ·
[`bench/rust/simd_map.rs`](https://github.com/march-language/march/blob/main/bench/rust/simd_map.rs) ·
[`bench/elixir/simd_map.exs`](https://github.com/march-language/march/blob/main/bench/elixir/simd_map.exs) ·
[`bench/python/simd_map.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map.py) ·
[`bench/python/simd_map_numpy.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map_numpy.py)

### `map2(a, b, (x, y) -> x + y)` — elementwise two-array zip

| Language | Median | Min | Max |
|----------|-------:|----:|----:|
| March | 299.2 ms | 296.8 ms | 315.6 ms |
| OCaml | 7.0 ms | 7.0 ms | 7.7 ms |
| **Rust** | **6.3 ms** | 5.7 ms | 7.8 ms |
| Elixir | 105.9 ms | 101.7 ms | 140.6 ms |
| Python | 201.8 ms | 196.0 ms | 206.4 ms |
| NumPy | 1.7 ms | 1.6 ms | 1.9 ms |

**The honest gap.** `NativeArray.map2_int`/`map2_float` — added to unblock
`DataFrame.col_add_col` (column-column arithmetic) — has none of the
inlining/boxing-elimination treatment `map` gets: every element dispatches
through the general closure-call path (heap-box, indirect call through the
closure's function pointer, unbox the result). At 299ms it is **~47x slower
than March's own `map`** for essentially the same arithmetic, and **slower
than naive interpreted Python** for the same operation. This isn't a
regression to be fixed reactively — it's a scoping decision (`map2` shipped
correctness-first) now visible as a concrete number instead of a caveat. See
[Known limitations]({{ site.baseurl }}/docs/simd/#known-limitations).

**Source:** [`bench/simd_map2.march`](https://github.com/march-language/march/blob/main/bench/simd_map2.march) ·
[`bench/ocaml/simd_map2.ml`](https://github.com/march-language/march/blob/main/bench/ocaml/simd_map2.ml) ·
[`bench/rust/simd_map2.rs`](https://github.com/march-language/march/blob/main/bench/rust/simd_map2.rs) ·
[`bench/elixir/simd_map2.exs`](https://github.com/march-language/march/blob/main/bench/elixir/simd_map2.exs) ·
[`bench/python/simd_map2.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map2.py) ·
[`bench/python/simd_map2_numpy.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map2_numpy.py)

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

Every other row and benchmark runs without it — the script detects
`bench/.venv` and skips the NumPy row if it's absent.

The runner ([`bench/run_benchmarks.sh`](https://github.com/march-language/march/blob/main/bench/run_benchmarks.sh))
also compares `fib(40)`, `binary-trees(15)`, `tree-transform`, and `list-ops`
against OCaml/Rust/Elixir — allocation, recursion, and HOF-pipeline shaped
workloads unrelated to SIMD. Full results, including those, are in
[`bench/RESULTS.md`](https://github.com/march-language/march/blob/main/bench/RESULTS.md).

## See also

- [SIMD & Native Arrays]({{ site.baseurl }}/docs/simd/) — what vectorizes, how to trigger it, known limitations.
- [Standard Library → NativeArray]({{ site.baseurl }}/docs/stdlib/NativeArray.html) — full API reference.
