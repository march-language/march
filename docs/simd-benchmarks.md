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
hand-tuned, BLAS-backed reference implementation) — three operations, all
three now competitive. `map2` wasn't always one of them; see
[Fix history: map2](#fix-history-map2) below for the before/after.

---

## Read this before the numbers

**This is a shared development machine, not a dedicated benchmark box.**
The run below shared the machine with several other active sessions — load
average was **7.9–11.1** at the time, on a 14-core machine. That mostly
washes out for the SIMD numbers specifically (each program self-times only
its own operation over up to a few milliseconds — see Methodology), but
treat everything here as directional, not authoritative. Run it yourself on
your own hardware if the exact numbers matter to you; the reproduction
command is at the bottom of this page.

**No cherry-picking.** These are the median/min/max of 10 runs, taken
directly from a single invocation of `bench/run_benchmarks.sh`, unedited.
Where March loses or is only mid-pack, that's shown too (`map` loses to Rust
here; `map2` did too, along with everything else, before the fix below).

**Reproducing this.** `bench/run_benchmarks.sh` now prints its own provenance
before it times anything — date, host, CPU, core count, load average, and the
version of every compiler it resolved, including March's taken from the
`dune exec` compiler that actually builds the benchmarks rather than from
whatever `march` sits on `PATH`. If a comparison language is missing it says so
loudly and names the rows that will be absent, because the old failure mode was
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
| Load average at run time | 7.89, 11.10, 10.28 (1m/5m/15m) — **not idle** |
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
| **March** | **1.1 ms** | 1.0 ms | 1.4 ms |
| OCaml | 4.7 ms | 4.7 ms | 4.8 ms |
| Rust | 5.4 ms | 5.3 ms | 6.5 ms |
| Elixir | 83.9 ms | 81.2 ms | 91.7 ms |
| Python | 296.9 ms | 283.0 ms | 319.3 ms |
| NumPy | 1.0 ms | 1.0 ms | 1.0 ms |

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
| March | 5.1 ms | 4.8 ms | 5.5 ms |
| OCaml | 5.5 ms | 5.4 ms | 5.6 ms |
| **Rust** | **3.9 ms** | 3.7 ms | 4.3 ms |
| Elixir | 244.8 ms | 236.9 ms | 281.8 ms |
| Python | 194.1 ms | 192.9 ms | 199.5 ms |
| NumPy | 2.1 ms | 2.1 ms | 2.9 ms |

This one needs a compiler-side trick, not just clang: March's closure-call
ABI heap-boxes every `Float` crossing a call boundary, which blocks
vectorization outright. For a concrete-`Float`, single-use callback like this
one, a dedicated pass clones the inlined callback under natural `double`
params with zero boxing (`Float`-boxing Stage 4, Option B) — without it, this
number would look like `map2`'s pre-fix numbers below, not like this. March
is competitive with hand-written OCaml/Rust and within 3x of NumPy.

**Source:** [`bench/simd_map.march`](https://github.com/march-language/march/blob/main/bench/simd_map.march) ·
[`bench/ocaml/simd_map.ml`](https://github.com/march-language/march/blob/main/bench/ocaml/simd_map.ml) ·
[`bench/rust/simd_map.rs`](https://github.com/march-language/march/blob/main/bench/rust/simd_map.rs) ·
[`bench/elixir/simd_map.exs`](https://github.com/march-language/march/blob/main/bench/elixir/simd_map.exs) ·
[`bench/python/simd_map.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map.py) ·
[`bench/python/simd_map_numpy.py`](https://github.com/march-language/march/blob/main/bench/python/simd_map_numpy.py)

### `map2(a, b, (x, y) -> x + y)` — elementwise two-array zip

| Language | Median | Min | Max |
|----------|-------:|----:|----:|
| March | 6.4 ms | 6.3 ms | 8.8 ms |
| OCaml | 7.0 ms | 6.9 ms | 7.1 ms |
| **Rust** | **4.5 ms** | 4.3 ms | 4.8 ms |
| Elixir | 101.6 ms | 99.4 ms | 132.0 ms |
| Python | 197.1 ms | 189.3 ms | 207.5 ms |
| NumPy | 1.6 ms | 1.5 ms | 1.6 ms |

`NativeArray.map2_int`/`map2_float` — added to unblock
`DataFrame.col_add_col` (column-column arithmetic) — now gets the same
inlining/boxing-elimination treatment `map` does: the same compiler pass
(`Native_map_inline.ml`) that recognizes a single-array `map` call with a
fresh, single-use callback was extended to recognize the two-array `map2`
shape too, cloning a boxing-free variant for a concrete-`Float` callback
exactly as it does for `map`. Beats OCaml, within 3x of NumPy.

### Fix history: map2

This wasn't always true. `map2` originally shipped **correctness-first** —
the primitive itself (runtime, interpreter, typechecker, compiled-path
registration) landed without the inlining pass most other `NativeArray`
operations get, a known, explicitly-documented scoping decision. The numbers
made the cost of that gap concrete rather than a caveat:

| | March (before) | March (after) | Speedup |
|---|---:|---:|---:|
| `map2` | 299.2 ms | 6.4 ms | **~47x** |

Before the fix, every element dispatched through the general closure-call
path (heap-box each argument, indirect call through the closure's function
pointer, unbox the result) — 299ms, **slower than naive interpreted
Python**, and ~47x slower than March's own `map` doing essentially the same
arithmetic. `Native_map_inline.ml` was extended the same day these numbers
were first published: same eligibility bar as `map` (fresh, single-use,
non-capturing-or-single-capture callback), same synthetic-call-name
mechanism, same `Float`-boxing Stage 4 Option B unboxed clone for a
concrete-`Float` signature — just matching a 3-argument call shape (two
arrays + closure) instead of `map`'s 2-argument one. The inlined loop
bypasses `native_int_arr_map2`/`native_float_arr_map2` entirely, so it also
needed its own length-mismatch check (`native_arr_map2_check_len`,
`runtime/march_runtime.c`) to keep panicking on a length mismatch exactly
like the non-inlined path does — verified with a dedicated regression test,
not just the happy path.

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
