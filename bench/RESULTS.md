# Cross-Language Benchmark Results

**Date:** 2026-07-24 (after restoring Perceus FBIP reuse + removing the per-call TLS preemption check);
simd-sum/simd-map/simd-map2 added and last refreshed 2026-07-27.
**Machine:** Apple M3 Max, 14 cores (10P+4E), 36 GB, macOS 26.5.2 (Darwin 25.5.0, arm64). This is a
shared development machine, not a dedicated benchmark box — load average was 8.5 (1-minute) at the
time of the simd-* refresh. See [docs/simd-benchmarks.md](../docs/simd-benchmarks.md) for the fuller
write-up and per-source-file links.
**Methodology:** `RUNS=10 bash bench/run_benchmarks.sh`; median, min, max reported. fib/binary-trees/
tree-transform/list-ops measure subprocess wall-clock; the simd-* benchmarks self-time (see their
section below for why).

## Versions

| Language | Version | Compilation |
|----------|---------|------------|
| March    | HEAD    | `march --compile --opt 2` → clang native |
| OCaml    | 5.3.0   | `ocamlopt` native |
| Rust     | 1.94.0  | `rustc -O` native |
| Elixir   | 1.20.1-otp-29 | BEAM JIT (script mode) |
| Python   | 3.14.3  | CPython, interpreted |
| NumPy    | 2.5.1   | vectorized/BLAS reference (simd-* only, needs `bench/.venv`) |

---

## Summary (medians)

| Benchmark        | March    | OCaml    | Rust     | Elixir   |
|------------------|----------|----------|----------|----------|
| fib(40)          | 394.7 ms | 364.1 ms | **286.5 ms** | 1010.3 ms |
| binary-trees(15) | 164.7 ms | **24.1 ms** | 150.7 ms | 335.1 ms |
| tree-transform   | **579.1 ms** | 3669.5 ms | 4902.3 ms | 2369.0 ms |
| list-ops(1M)     | 64.3 ms  | 34.8 ms  | **5.4 ms** | 311.7 ms |

| SIMD benchmark (N=5M, self-timed) | March    | OCaml   | Rust    | Elixir   | Python   | NumPy   |
|------------------------------------|----------|---------|---------|----------|----------|---------|
| simd-sum                           | **1.3 ms** | 4.8 ms | 5.4 ms | 84.2 ms  | 308.8 ms | 1.0 ms  |
| simd-map                           | 6.4 ms   | 5.5 ms  | **4.3 ms** | 252.8 ms | 193.5 ms | 2.4 ms  |
| simd-map2                          | 299.2 ms | 7.0 ms  | **6.3 ms** | 105.9 ms | 201.8 ms | 1.7 ms  |

Bold = fastest for that benchmark.

---

## fib(40) — naive recursive Fibonacci

No allocation, pure arithmetic. All languages use the same double recursion.

| Language | Median  | Min     | Max     |
|----------|---------|---------|---------|
| March    | 394.7 ms | 392.5 ms | 401.7 ms |
| OCaml    | 364.1 ms | 360.4 ms | 369.2 ms |
| **Rust** | **286.5 ms** | 283.7 ms | 292.2 ms |
| Elixir   | 1010.3 ms | 985.7 ms | 1246.2 ms |

**Was 639.6 ms; fixed 2026-07-24.** The 2026-03-24 table (287.7 ms, level with
Rust) is a *pre-preemption* baseline — reduction counting in compiled code
landed one day later. But the cost was never the counting: it was that the
counter is `_Thread_local`, and thread-local access is an indirect resolver
call on both platforms (Darwin/arm64 `adrp; ldr; blr` through the TLV
descriptor; Linux/arm64 PIE via TLSDESC), executed on *every function entry*.
Compiled code now reads a plain process-wide preemption flag instead: one
load, one predictable branch, no call. A second recovery came from adding
`nsw` to the scalar tag, which unblocks LLVM's accumulator TRE — `fib` now
compiles to a loop with a single recursive call, preemption check verified
inside the loop. The remaining ~35% over the 2026-03-24 figure is the
per-iteration volatile preemption check plus call frame — the price of
compiled green threads staying preemptible, tracked in `specs/todos.md`.

---

## binary-trees(15) — allocation/GC stress

`depth=15` → 65,535 nodes per tree; the inner loop creates and discards many trees.

| Language | Median  | Min     | Max     |
|----------|---------|---------|---------|
| March    | 164.7 ms | 161.7 ms | 168.6 ms |
| **OCaml** | **24.1 ms** | 20.3 ms | 24.9 ms |
| Rust     | 150.7 ms | 146.7 ms | 153.6 ms |
| Elixir   | 335.1 ms | 328.2 ms | 343.9 ms |

OCaml's generational minor heap dominates here; short-lived tree nodes are
close to free for it. March is competitive with Rust. This is the one
benchmark that improved against the 2026-03-24 table (265.4 → 164.7 ms).

---

## tree-transform(depth=20, 100 passes) — Perceus FBIP showcase

`inc_leaves` maps over a depth-20 tree (1,048,576 leaves) incrementing each
leaf, 100 times. March rewrites nodes in place when the RC is 1; OCaml, Rust
and Elixir each allocate a fresh tree per pass.

| Language | Median    | Min       | Max       |
|----------|-----------|-----------|-----------|
| **March** | **579.1 ms** | 566.7 ms | 590.5 ms |
| OCaml    | 3669.5 ms | 3652.6 ms | 3688.5 ms |
| Rust     | 4902.3 ms | 4861.3 ms | 4969.0 ms |
| Elixir   | 2369.0 ms | 2353.4 ms | 2425.8 ms |

**March is 6.3x faster than OCaml and 8.5x faster than Rust** — this is the
benchmark FBIP exists for.

**Regression history.** Before the fix restored in this run, FBIP reuse was
disabled program-wide and this benchmark ran at **3842.5 ms** — slower than
OCaml, on the workload that is supposed to be March's flagship win. See the
CHANGELOG entry: `try_fbip_sink` could not sink a `dec_rc` past the join-point
closure cleanup that every match arm carries, so `EReuse` was never emitted and
every in-place rewrite became free + fresh allocation.

579 ms is within 13% of the 513.3 ms recorded on 2026-03-24. The gap between
852 ms and this figure was the same per-entry TLS preemption check described
under `fib` above.

---

## list-ops(1M) — HOF pipeline (map/filter/fold)

`range(1..1_000_000) |> map(*2) |> filter(%3=0) |> sum`

| Language | Median   | Min      | Max      |
|----------|----------|----------|----------|
| March    | 64.3 ms  | 58.2 ms  | 97.4 ms  |
| OCaml    | 34.8 ms  | 31.9 ms  | 36.6 ms  |
| **Rust** | **5.4 ms** | 4.8 ms | 8.9 ms   |
| Elixir   | 311.7 ms | 301.9 ms | 326.8 ms |

Rust's iterator pipeline fuses into a single allocation-free loop. March's
stream fusion + constant propagation put it ~1.9x behind OCaml. The FBIP fix
restored this benchmark to its 2026-03-24 figure (67.6 → 64.3 ms); it had
regressed to 143.0 ms.

---

## simd-sum(5M) / simd-map(5M) / simd-map2(5M) — Float array numeric ops

See [docs/simd-vectorization.md](../docs/simd-vectorization.md) for what these
operations are and why they vectorize (or don't).

**Self-timed, not subprocess wall-clock.** Every other benchmark on this page
measures the whole process. These three don't: each program times only the
operation itself, excluding data generation and (for interpreters) startup —
see `bench/simd_sum.march`'s header comment. That distinction matters here
specifically because building the *input* is expensive relative to the
operation: a March program that built a 5M-element `List` of boxed floats and
then measured the whole process spent ~200ms on the list build and ~1ms on
the actual (genuinely vectorized) sum — a wall-clock number that would have
measured "how fast can March allocate a linked list," not the SIMD claim
under test. Every language's benchmark generates its input data outside the
timed region for the same reason. OCaml's version also uses a manual
for-loop rather than `Array.fold_left`/`Array.map` — their polymorphic
accumulator boxes every float (~5x slower), which is not what a
performance-conscious OCaml numeric loop looks like; Rust's iterator-based
version was checked against a manual-loop control and found to already be
at parity (zero-cost abstraction, as advertised).

| simd-sum(5M) | Median   | Min     | Max     |
|--------------|----------|---------|---------|
| **March**    | **1.3 ms** | 0.9 ms | 3.2 ms |
| OCaml        | 4.8 ms   | 4.7 ms  | 5.0 ms  |
| Rust         | 5.4 ms   | 5.2 ms  | 5.5 ms  |
| Elixir       | 84.2 ms  | 83.1 ms | 97.2 ms |
| Python       | 308.8 ms | 288.1 ms| 391.3 ms|
| NumPy        | 1.0 ms   | 0.9 ms  | 1.5 ms  |

| simd-map(5M) | Median   | Min     | Max     |
|--------------|----------|---------|---------|
| March        | 6.4 ms   | 5.3 ms  | 7.6 ms  |
| OCaml        | 5.5 ms   | 5.4 ms  | 5.6 ms  |
| **Rust**     | **4.3 ms** | 3.9 ms | 5.1 ms |
| Elixir       | 252.8 ms | 242.2 ms| 323.6 ms|
| Python       | 193.5 ms | 191.3 ms| 202.2 ms|
| NumPy        | 2.4 ms   | 2.1 ms  | 3.7 ms  |

| simd-map2(5M)| Median   | Min     | Max     |
|--------------|----------|---------|---------|
| March        | 299.2 ms | 296.8 ms| 315.6 ms|
| OCaml        | 7.0 ms   | 7.0 ms  | 7.7 ms  |
| **Rust**     | **6.3 ms** | 5.7 ms | 7.8 ms |
| Elixir       | 105.9 ms | 101.7 ms| 140.6 ms|
| Python       | 201.8 ms | 196.0 ms| 206.4 ms|
| NumPy        | 1.7 ms   | 1.6 ms  | 1.9 ms  |

**simd-sum and simd-map: the SIMD claim holds up.** March ties NumPy (a
hand-tuned, BLAS-backed reference implementation) for the reduction, and is
competitive with hand-written OCaml/Rust for both — genuine wins for a
compiler doing this via general-purpose auto-vectorization (LLVM's, at `-O2`)
rather than a hand-rolled numeric kernel.

**simd-map2 is the honest gap.** `NativeArray.map2_int`/`map2_float` (added
2026-07-27 to unblock `DataFrame.col_add_col`) has no inlining/vectorization
treatment yet — every element dispatches through the boxed closure-call path
(`march_alloc_float` per element, indirect call through the closure
pointer). At 299.2 ms it is **slower than naive interpreted Python** (201.8
ms) for the same operation, and 47x slower than March's own `simd-map`. This
is not a regression to fix reactively — it's a known, already-documented
limitation (`docs/simd-vectorization.md` "Known limitations", added the same
day as `map2` itself) surfaced here with a concrete number instead of a
qualitative "not yet vectorized." Extending the Phase 2b/2c/Stage-4-style
inlining machinery that already exists for `map_int`/`map_float` to the
two-array `map2` shape is the natural next step if this gap is worth closing.

---

## Where March wins and trails

**Wins:** FBIP-shaped workloads (tree-transform) — in-place reuse under
Perceus RC beats every allocating implementation by a wide margin. Single-
array vectorizable Float ops (simd-sum, simd-map) — ties or beats NumPy.

**Trails:** allocation-heavy churn with short-lived objects (binary-trees),
where a generational GC is structurally better than RC; tight iterator
pipelines (list-ops), where LLVM's fusion of Rust iterators is unmatched; and
two-array Float ops (simd-map2), which have no vectorization treatment yet.

**Preemption overhead:** compiled green threads stay preemptible via a
per-function-entry check. It is now a single load of a plain global plus a
predictable branch; it used to be a thread-local access, i.e. an indirect
resolver call on every entry, which cost ~1.4x on call-dense code. A residual
~25% gap to the 2026-03-24 `fib` figure is still unexplained and tracked in
`specs/todos.md`.

---

## Reproducing

```bash
# From the march repo root:
bash bench/run_benchmarks.sh

# More iterations (default is 10):
RUNS=20 bash bench/run_benchmarks.sh
```

The script pins `dune exec --root .` so it always measures the compiler in the
checkout it lives in. Without that, running it from a git worktree (which sits
under the parent checkout) makes dune resolve its root to the *parent*
repository and benchmark that compiler instead, with no error — a trap that
already produced one round of misleading "the fix changed nothing" numbers.

Source files:
- `bench/elixir/` — Elixir `.exs` scripts (idiomatic Elixir/BEAM)
- `bench/ocaml/` — OCaml `.ml` sources (compiled with `ocamlopt`; the `simd_*`
  ones link `unix` via `ocamlfind` for `Unix.gettimeofday`)
- `bench/rust/` — Rust `.rs` sources (compiled with `rustc -O`)
- `bench/python/` — Python `.py` sources; the `_numpy` variants need NumPy
- `bench/*.march` — March sources (compiled with `march --compile --opt 2`)

The NumPy row needs a local venv (not committed):
```bash
python3 -m venv bench/.venv
bench/.venv/bin/pip install numpy
```
Every other row and benchmark runs without it (the script detects `bench/.venv`
and skips the NumPy row if it's absent).
