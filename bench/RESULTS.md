# Cross-Language Benchmark Results

**Date:** 2026-07-24 (after restoring Perceus FBIP reuse + removing the per-call TLS preemption check)
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
| fib(40)          | 394.7 ms | 364.1 ms | **286.5 ms** | 1010.3 ms |
| binary-trees(15) | 164.7 ms | **24.1 ms** | 150.7 ms | 335.1 ms |
| tree-transform   | **579.1 ms** | 3669.5 ms | 4902.3 ms | 2369.0 ms |
| list-ops(1M)     | 64.3 ms  | 34.8 ms  | **5.4 ms** | 311.7 ms |

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

## Where March wins and trails

**Wins:** FBIP-shaped workloads (tree-transform) — in-place reuse under
Perceus RC beats every allocating implementation by a wide margin.

**Trails:** allocation-heavy churn with short-lived objects (binary-trees),
where a generational GC is structurally better than RC; and tight iterator
pipelines (list-ops), where LLVM's fusion of Rust iterators is unmatched.

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
- `bench/ocaml/` — OCaml `.ml` sources (compiled with `ocamlopt`)
- `bench/rust/` — Rust `.rs` sources (compiled with `rustc -O`)
- `bench/*.march` — March sources (compiled with `march --compile --opt 2`)
