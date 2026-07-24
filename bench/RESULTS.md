# Cross-Language Benchmark Results

**Date:** 2026-07-24 (re-run after restoring Perceus FBIP in-place reuse)
**Machine:** Apple M-series (darwin 25.5.0, 14 cores)
**Methodology:** `RUNS=10 bash bench/run_benchmarks.sh`; median, min, max wall-clock reported.

## Versions

| Language | Version | Compilation |
|----------|---------|------------|
| March    | HEAD    | `march --compile --opt 2` → clang native |
| OCaml    | 5.3.0   | `ocamlopt` native |
| Rust     | 1.94.0  | `rustc -O` native |
| Elixir   | 1.20.1-otp-29 | BEAM JIT (script mode) |

---

## Summary (medians)

| Benchmark        | March    | OCaml    | Rust     | Elixir   |
|------------------|----------|----------|----------|----------|
| fib(40)          | 639.6 ms | 362.9 ms | **289.0 ms** | 998.1 ms |
| binary-trees(15) | 176.6 ms | **24.1 ms** | 149.9 ms | 332.4 ms |
| tree-transform   | **852.2 ms** | 3701.4 ms | 4922.5 ms | 2410.3 ms |
| list-ops(1M)     | 67.3 ms  | 34.8 ms  | **5.4 ms** | 311.7 ms |

Bold = fastest for that benchmark.

---

## fib(40) — naive recursive Fibonacci

No allocation, pure arithmetic. All languages use the same double recursion.

| Language | Median  | Min     | Max     |
|----------|---------|---------|---------|
| March    | 639.6 ms | 635.2 ms | 686.7 ms |
| OCaml    | 362.9 ms | 360.8 ms | 370.4 ms |
| **Rust** | **289.0 ms** | 286.3 ms | 291.1 ms |
| Elixir   | 998.1 ms | 983.2 ms | 1075.5 ms |

**Open regression.** The 2026-03-24 run of this same benchmark recorded March
at **287.7 ms** — level with Rust. March is now ~2.2x slower on it. This
benchmark allocates nothing, so it is unaffected by the FBIP fix below and the
cause is unidentified; recursion/call overhead is the obvious place to look.
Tracked in `specs/todos.md`.

---

## binary-trees(15) — allocation/GC stress

`depth=15` → 65,535 nodes per tree; the inner loop creates and discards many trees.

| Language | Median  | Min     | Max     |
|----------|---------|---------|---------|
| March    | 176.6 ms | 175.0 ms | 180.0 ms |
| **OCaml** | **24.1 ms** | 23.3 ms | 25.0 ms |
| Rust     | 149.9 ms | 147.4 ms | 150.8 ms |
| Elixir   | 332.4 ms | 322.8 ms | 350.8 ms |

OCaml's generational minor heap dominates here; short-lived tree nodes are
close to free for it. March is competitive with Rust. This is the one
benchmark that improved against the 2026-03-24 table (265.4 → 176.6 ms).

---

## tree-transform(depth=20, 100 passes) — Perceus FBIP showcase

`inc_leaves` maps over a depth-20 tree (1,048,576 leaves) incrementing each
leaf, 100 times. March rewrites nodes in place when the RC is 1; OCaml, Rust
and Elixir each allocate a fresh tree per pass.

| Language | Median    | Min       | Max       |
|----------|-----------|-----------|-----------|
| **March** | **852.2 ms** | 837.4 ms | 884.1 ms |
| OCaml    | 3701.4 ms | 3660.6 ms | 3814.6 ms |
| Rust     | 4922.5 ms | 4879.4 ms | 4950.7 ms |
| Elixir   | 2410.3 ms | 2368.1 ms | 2637.6 ms |

**March is 4.3x faster than OCaml and 5.8x faster than Rust** — this is the
benchmark FBIP exists for.

**Regression history.** Before the fix restored in this run, FBIP reuse was
disabled program-wide and this benchmark ran at **3842.5 ms** — slower than
OCaml, on the workload that is supposed to be March's flagship win. See the
CHANGELOG entry: `try_fbip_sink` could not sink a `dec_rc` past the join-point
closure cleanup that every match arm carries, so `EReuse` was never emitted and
every in-place rewrite became free + fresh allocation.

852 ms is still ~1.7x the 513.3 ms recorded on 2026-03-24. That residual gap is
not explained by FBIP and may share a cause with the `fib` regression above.

---

## list-ops(1M) — HOF pipeline (map/filter/fold)

`range(1..1_000_000) |> map(*2) |> filter(%3=0) |> sum`

| Language | Median   | Min      | Max      |
|----------|----------|----------|----------|
| March    | 67.3 ms  | 66.6 ms  | 71.2 ms  |
| OCaml    | 34.8 ms  | 31.9 ms  | 36.6 ms  |
| **Rust** | **5.4 ms** | 4.8 ms | 8.9 ms   |
| Elixir   | 311.7 ms | 301.9 ms | 326.8 ms |

Rust's iterator pipeline fuses into a single allocation-free loop. March's
stream fusion + constant propagation put it ~1.9x behind OCaml. The FBIP fix
restored this benchmark exactly to its 2026-03-24 figure (67.6 → 67.3 ms); it
had regressed to 143.0 ms.

---

## Where March wins and trails

**Wins:** FBIP-shaped workloads (tree-transform) — in-place reuse under
Perceus RC beats every allocating implementation by a wide margin.

**Trails:** allocation-heavy churn with short-lived objects (binary-trees),
where a generational GC is structurally better than RC; and tight iterator
pipelines (list-ops), where LLVM's fusion of Rust iterators is unmatched.

**Open:** scalar recursion (fib) used to be level with Rust and no longer is.

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
- `bench/ocaml/` — OCaml `.ml` sources (compiled with `ocamlopt`)
- `bench/rust/` — Rust `.rs` sources (compiled with `rustc -O`)
- `bench/*.march` — March sources (compiled with `march --compile --opt 2`)
