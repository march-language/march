# Cross-Language Benchmark Results

**Date:** 2026-03-24 (updated after constant propagation pass)
**Machine:** Apple M-series (darwin 24.6.0, 14 cores)
**Methodology:** Each benchmark run 3 times; median, min, max wall-clock time reported.

## Versions

| Language | Version | Compilation |
|----------|---------|------------|
| March    | HEAD    | `march --compile --opt 2` → clang native |
| OCaml    | 5.3.0   | `ocamlopt` native |
| Rust     | 1.94.0  | `rustc -O` native |
| Elixir   | 1.19.5-otp-28 | BEAM JIT (script mode) |

---

## fib(40) — Naive Recursive Fibonacci

Baseline recursion benchmark. No allocation, pure arithmetic.
All languages implement the same double-recursive `fib(n-1) + fib(n-2)`.

| Language | Median  | Min     | Max     |
|----------|---------|---------|---------|
| **March** | **287.7 ms** | 286.5 ms | 289.4 ms |
| OCaml    | 368.6 ms | 366.5 ms | 374.0 ms |
| Rust     | 291.4 ms | 288.4 ms | 293.8 ms |
| Elixir   | 1020.9 ms | 984.2 ms | 1044.6 ms |

**Notes:**
- **TCE structural-recursion fix restored this benchmark.** `fib(n-1)` and `fib(n-2)` are now recognised as arithmetic reductions of parameter `n`, so the non-tail calls are accepted.
- March ≈ Rust; both ≈ 288–291 ms. OCaml is ~27% slower.
- *Previous:* benchmark was rejected by mandatory TCE enforcement (was 257.5 ms before TCE).

---

## binary-trees(15) — Allocation/GC Stress Test

Allocates and walks complete binary trees. Exercises the allocator and garbage collector.
`depth=15` → 65,535 nodes per tree; inner loop creates and immediately discards many trees.

| Language | Median  | Min     | Max     |
|----------|---------|---------|---------|
| March    | 265.4 ms | 265.4 ms | 266.5 ms |
| **OCaml** | **19.8 ms** | 19.3 ms | 22.0 ms |
| Rust     | 257.5 ms | 255.2 ms | 258.1 ms |
| Elixir   | 317.1 ms | 316.8 ms | 325.1 ms |

**Notes:**
- **TCE structural-recursion fix restored this benchmark.** `make(d-1)` is an arithmetic reduction; `check(l) + check(r)` where `l`, `r` are pattern-bound sub-components of the `Node(l, r)` parameter — both now pass structural recursion rules.
- OCaml dominates due to generational GC; minor-heap handles short-lived tree nodes cheaply.
- March is competitive with Rust (RC-based allocation); both ≈ 256–266 ms.
- *Previous:* 275.2 ms — constant propagation improved by ~3.6% (275 → 265 ms).
- *Before TCE:* benchmark was rejected by mandatory TCE enforcement (was 256.7 ms).

---

## tree-transform(depth=20, 100 passes) — Perceus FBIP Showcase

`inc_leaves` maps over a depth-20 tree (1,048,576 leaf nodes) incrementing each leaf, repeated 100 times.
This is the primary showcase for March's **Functional But In-Place (FBIP)** optimisation via Perceus RC.

| Language | Median    | Min       | Max       |
|----------|-----------|-----------|-----------|
| **March** | **513.3 ms** | 513.3 ms | 513.5 ms |
| OCaml    | 3825.0 ms | 3820.5 ms | 3829.0 ms |
| Rust     | 9977.4 ms | 9916.9 ms | 10010.9 ms |
| Elixir   | 2579.4 ms | 2502.8 ms | 2648.1 ms |

**Notes:**
- **TCE structural-recursion fix restored this benchmark.** `inc_leaves(l)` and `inc_leaves(r)` where `l`, `r` are pattern-bound sub-components of `Node(l, r)` — now accepted as structural recursion.
- **March is 7.5× faster than OCaml and 19× faster than Rust** via Perceus FBIP in-place reuse.
- When the RC of the input tree node is 1 (unique ownership), Perceus rewrites every node in-place — zero allocation after the first pass.
- *Previous:* 523.7 ms — constant propagation improved by ~2% (524 → 513 ms).
- *Before TCE:* 480.3 ms before TCE enforcement (7.5–18.9× vs others).

---

## list-ops(1M) — HOF Pipeline (map/filter/fold)

`range(1..1_000_000) |> map(*2) |> filter(%3=0) |> sum`

| Language | Median   | Min      | Max      |
|----------|----------|----------|----------|
| March    | **67.6 ms** *(was 75.8 ms — constant propagation)* | 67.6 ms | 68.1 ms |
| **OCaml** | **31.6 ms** | 31.0 ms | 31.6 ms |
| **Rust** | **5.1 ms** | 4.6 ms   | 5.2 ms   |
| Elixir   | 340.6 ms | 338.3 ms | 352.5 ms |

**Notes:**
- **Constant propagation delivered a further ~11% speedup** (75.8 ms → ~68 ms). CProp enables the Fold pass to evaluate more arithmetic at compile time, reducing runtime loop overhead.
- **Stream fusion previously delivered ~35% speedup** (117.3 ms → ~76 ms). Combined with CProp: 117.3 ms → 68 ms (42% total reduction).
- Rust's iterator pipeline is ~13× faster — LLVM iterator fusion at zero allocation.
- OCaml allocates two intermediate lists but its generational GC handles them cheaply.
- Elixir's `Enum.map` + `Enum.filter` builds intermediate lists on the BEAM heap.

---

## Summary Table (Medians)

| Benchmark        | March    | OCaml    | Rust     | Elixir   |
|------------------|----------|----------|----------|----------|
| fib(40)          | **287.7 ms** ≈ Rust | 368.6 ms | 291.4 ms | 1020.9 ms |
| binary-trees(15) | 265.4 ms ↓3.6% | **19.8 ms** | 257.5 ms | 317.1 ms |
| tree-transform   | **513.3 ms** 7.5–19× ↓2% | 3825.0 ms | 9977.4 ms | 2579.4 ms |
| list-ops(1M)     | 67.6 ms ↓42% total | **31.6 ms**  | **5.1 ms** | 340.6 ms |

Bold = fastest for that benchmark.

---

## Analysis

### TCE Structural-Recursion Refinement Impact (fix/tce)
- **fib, binary-trees, tree-transform: all restored.** The refined TCE pass now accepts structural recursion where arguments are either:
  - Pattern-bound sub-components of a parameter (`l`, `r` from `Node(l, r)`)
  - Arithmetic reductions of a parameter (`n-1`, `n-2`)
- Truly unbounded non-tail recursion (same argument, no reduction) still errors.
- **Result**: March ≈ Rust on fib (288 vs 291 ms); March 7.3–19× faster on tree-transform via FBIP.

### Stream Fusion Impact (feat/fusion)
- **list-ops: 117.3 ms → ~76 ms (~35% speedup)** — the `map+filter+fold` chain is compiled to a single fused loop in the TIR. No intermediate `ICons` chains.
- This validates the fusion design: the ANF-flatten + pattern-match approach in `lib/tir/fusion.ml` works correctly for all three fusion patterns.

### Constant Propagation Impact (feat/opt — 2026-03-24)
- **list-ops: 75.8 ms → 67.6 ms (~11% speedup)** — CProp propagates the loop bounds/step constants through the fused map+filter+fold body, enabling further arithmetic folding.
- **binary-trees: 275.2 ms → 265.4 ms (~3.6% speedup)** — tree-depth constants in `make`/`check` propagate through inlined call chains.
- **tree-transform: 523.7 ms → 513.3 ms (~2% speedup)** — modest gain; FBIP already dominates this benchmark.
- Combined with stream fusion, list-ops has improved 42% total from baseline (117.3 → 67.6 ms).

### Where March wins
- **FBIP / tree-transform**: Perceus RC's in-place reuse — 7.5–19× faster than OCaml/Rust/Elixir.
- **Scalar recursion (fib)**: Competitive with Rust (native code, RC-free path for pure arithmetic).

### Where March trails
- **Allocation-heavy GC workloads** (binary-trees): OCaml's generational minor-heap is ~13× faster.
- **List/iterator pipelines**: Fusion+CProp closed gap to ~2.1× behind OCaml; Rust's LLVM fusion is ~13× faster.

---

## Reproducing

```bash
# From the march repo root:
bash bench/run_benchmarks.sh

# More iterations (default is 10):
RUNS=20 bash bench/run_benchmarks.sh
```

Source files:
- `bench/elixir/` — Elixir `.exs` scripts (idiomatic Elixir/BEAM)
- `bench/ocaml/` — OCaml `.ml` sources (compiled with `ocamlopt`)
- `bench/rust/` — Rust `.rs` sources (compiled with `rustc -O`)
- `bench/*.march` — March sources (compiled with `march --compile --opt 2`)
