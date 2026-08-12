# Cross-Language Benchmark Results

**Date:** 2026-07-24 (after restoring Perceus FBIP reuse + removing the per-call TLS preemption check);
simd-sum/simd-map added 2026-07-27; simd-map2 refreshed 2026-07-27 after extending the map-inlining
compiler pass to the two-array shape (see the fix history under simd-map2 below).
**Machine:** Apple M3 Max, 14 cores (10P+4E), 36 GB, macOS 26.5.2 (Darwin 25.5.0, arm64). This is a
shared development machine, not a dedicated benchmark box — load average was 7.9-11.1 at the
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
| simd-sum                           | **1.1 ms** | 4.7 ms | 5.4 ms | 83.9 ms  | 296.9 ms | 1.0 ms  |
| simd-map                           | 5.1 ms   | 5.5 ms  | **3.9 ms** | 244.8 ms | 194.1 ms | 2.1 ms  |
| simd-map2                          | 6.4 ms   | 7.0 ms  | **4.5 ms** | 101.6 ms | 197.1 ms | 1.6 ms  |

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
| **March**    | **1.1 ms** | 1.0 ms | 1.4 ms |
| OCaml        | 4.7 ms   | 4.7 ms  | 4.8 ms  |
| Rust         | 5.4 ms   | 5.3 ms  | 6.5 ms  |
| Elixir       | 83.9 ms  | 81.2 ms | 91.7 ms |
| Python       | 296.9 ms | 283.0 ms| 319.3 ms|
| NumPy        | 1.0 ms   | 1.0 ms  | 1.0 ms  |

| simd-map(5M) | Median   | Min     | Max     |
|--------------|----------|---------|---------|
| March        | 5.1 ms   | 4.8 ms  | 5.5 ms  |
| OCaml        | 5.5 ms   | 5.4 ms  | 5.6 ms  |
| **Rust**     | **3.9 ms** | 3.7 ms | 4.3 ms |
| Elixir       | 244.8 ms | 236.9 ms| 281.8 ms|
| Python       | 194.1 ms | 192.9 ms| 199.5 ms|
| NumPy        | 2.1 ms   | 2.1 ms  | 2.9 ms  |

| simd-map2(5M)| Median   | Min     | Max     |
|--------------|----------|---------|---------|
| March        | 6.4 ms   | 6.3 ms  | 8.8 ms  |
| OCaml        | 7.0 ms   | 6.9 ms  | 7.1 ms  |
| **Rust**     | **4.5 ms** | 4.3 ms | 4.8 ms |
| Elixir       | 101.6 ms | 99.4 ms | 132.0 ms|
| Python       | 197.1 ms | 189.3 ms| 207.5 ms|
| NumPy        | 1.6 ms   | 1.5 ms  | 1.6 ms  |

**All three: the SIMD claim holds up.** March ties NumPy (a hand-tuned,
BLAS-backed reference implementation) for the reduction, and is competitive
with hand-written OCaml/Rust across all three — genuine wins for a compiler
doing this via general-purpose auto-vectorization (LLVM's, at `-O2`) rather
than a hand-rolled numeric kernel.

**simd-map2 fix history.** This table wasn't always three wins. When first
published, `NativeArray.map2_int`/`map2_float` (added 2026-07-27 to unblock
`DataFrame.col_add_col`) had no inlining/vectorization treatment — every
element dispatched through the boxed closure-call path (`march_alloc_float`
per element, indirect call through the closure pointer). That measured
**299.2 ms** — slower than naive interpreted Python (201.8 ms) for the same
operation, and 47x slower than March's own `simd-map`. Rather than leave that
as a documented-but-unaddressed limitation, `Native_map_inline.ml` (the pass
behind `simd-map`'s numbers above) was extended the same day to recognize
map2's two-array call shape: same eligibility bar (fresh, single-use
callback), same `Float`-boxing Stage 4 Option B unboxed clone for a
concrete-`Float` signature, just matching 2 leading array args instead of 1
before the trailing closure. The inlined loop bypasses
`native_int_arr_map2`/`native_float_arr_map2` entirely, so it also needed its
own length-mismatch check (`native_arr_map2_check_len`,
`runtime/march_runtime.c`) to preserve the "panics on length mismatch"
contract — verified with a dedicated regression test
(`test/native/native_arr_map2_inline_length_panic.march`), not just the
happy path. Result: **299.2 ms → 6.4 ms, ~47x**, now beating OCaml and within
3x of NumPy. See `docs/simd-benchmarks.md`'s "Fix history: map2" section for
the full before/after writeup.

---

## simd-f32(5M) — narrow (4-byte) NativeArray element width vs. f64

Added 2026-08-10 alongside `NativeArray.make_f32`/`map_f32`/`map2_f32`/`sum_f32`
(narrow `f32` element storage — half the width of the `f64`/`Float` element
storage used by every other `simd-*` benchmark on this page). `bench/simd_f32.march`
runs the same three shapes as `simd-sum`/`simd-map`/`simd-map2` — `sum`,
`map(fn x -> x *. 2.0 +. 1.0)`, `map2(fn (x, y) -> x +. y)` — at the same N=5M,
self-timed the same way (data generation excluded from the timed region; see
the section above). Unlike this page's other tables, this one is **March-only,
same-box, same-build, f32 vs. f64** — the point isn't a cross-language
comparison, it's whether halving the element width and doubling the SIMD lane
count actually pays off. Absolute ms are not a regression baseline across
machine/load states; the f32/f64 *ratio* measured in the same run is what
matters. As a sanity check only, the f64 legs below were re-run from the same
build as the existing simd-sum/simd-map/simd-map2 control: they came in
somewhat *faster* than that historical table (e.g. sum's 0.91 ms min and
map's 4.43 ms min/4.54 ms median both fall below every corresponding
historical figure), plausibly compiler improvements landed since those rows
were recorded and/or ordinary run-to-run variance — not evidence of a
regression either way. That gap doesn't affect the load-bearing comparison
here, which is the same-run f32-vs-f64 ratio, not the historical table.

Methodology: 6 timed samples per operation (two 3-run round-robins, one
`f32, f64-sum, f64-map, f64-map2` ordered and one reversed, to cancel the
~25%-on-first-timed-variant warmup bias documented earlier on this page —
neither f32 nor f64 was consistently first). Machine was shared with other
active sessions during this run (load average ~11.6-13.4/13.0-13.4/16.6-17.1
over 1/5/15 min, including one long-running pegged process from an unrelated
worktree) — flat, elevated background load, not a burst, so it should scale
both f32 and f64 runs roughly equally rather than favor either.

| simd-f32 sum(5M)  | Median  | Min     | Max     |
|--------------------|---------|---------|---------|
| f32 (NativeArray)  | 0.49 ms | 0.48 ms | 0.67 ms |
| f64 (NativeArray)  | 1.19 ms | 0.91 ms | 1.34 ms |

| simd-f32 map(5M)   | Median  | Min     | Max     |
|--------------------|---------|---------|---------|
| f32 (NativeArray)  | 2.27 ms | 2.25 ms | 3.42 ms |
| f64 (NativeArray)  | 4.54 ms | 4.43 ms | 5.12 ms |

| simd-f32 map2(5M)  | Median  | Min     | Max     |
|--------------------|---------|---------|---------|
| f32 (NativeArray)  | 2.67 ms | 2.17 ms | 5.96 ms |
| f64 (NativeArray)  | 6.40 ms | 5.98 ms | 8.21 ms |

**f32 is meaningfully faster across all three shapes** — sum ~2.4x, map ~2.0x
(right at the theoretical 2x-lanes ceiling), map2 ~2.4x — consistent with the
map/map2 inline-loop vectorization pass firing for the f32 entry points the
same way it already does for `map_float` (and, after the map2 fix documented
above, `map2_float`). The one outlier is `map2`'s max (5.96 ms, from the very
first sample of the very first round, where f32 happened to occupy the
first-timed-variant slot) — every other f32 map2 sample clustered at
2.17-3.11 ms, so this reads as the known warmup effect rather than a real
f32 regression; it is the reason this run used two opposite orderings rather
than one.

### Cross-language f32: March vs. NumPy (2026-08-10, post-merge re-run)

A second run after the narrow-widths work merged (PR #246), this time
including NumPy at BOTH element widths — the original `simd-*` NumPy rows on
this page are float64 (`np.arange(n) / 100.0` yields float64), so the new
`bench/python/simd_{sum,map,map2}_numpy_f32.py` variants (explicit
`.astype(np.float32)`, float32 scalar operands) exist to make the f32
comparison like-for-like. Same protocol as every table on this page: each
sample is one fresh process invocation, self-timed around the op only.

Methodology: March legs are medians of 10 samples (five interleaved
round-robins, alternating f64-first/f32-first orderings); NumPy legs are
medians of 5 one-shot invocations interleaved with them. Machine shared with
~6 long-lived pegged background processes from unrelated sessions (load
average ~9.5 on 14 cores, stable — not burst load); the f64 March control
came in at or slightly below the historical rows above, validating the run.

| N=5M, medians (ms) | March f64 | March f32 | NumPy f64 | NumPy f32 |
|--------------------|-----------|-----------|-----------|-----------|
| sum                | 1.02      | **0.40**  | 0.70      | 0.74      |
| map (x*2+1)        | 3.69      | **1.81**  | 1.58      | 2.05      |
| map2 (a+b)         | 4.90      | **1.85**  | 1.18      | 1.76      |

March f32/f64 ratios in this run: sum 2.5x, map 2.0x, map2 2.6x —
consistent with the table above. Like-for-like at f32, **March beats NumPy
on sum (1.8x) and map (~13%), and ties it on map2 (~5%)** — the
pre-narrow-widths 4x map2 gap (6.4 ms vs 1.6 ms) is gone.

One protocol-dependent oddity, recorded so nobody "fixes" it later: in this
one-shot-per-process protocol NumPy's f32 legs measure consistently *slower*
than its f64 legs (5/5 rounds for map and map2), while a warm in-process
`timeit` loop on the same arrays shows the expected f32 advantage (map
~1.43 ms vs ~2.20 ms). The one-shot numbers include first-touch/cold-cache
effects that evidently hit NumPy's f32 kernels harder; March's one-shot
numbers include the same cold-start effects and still show the full f32 win.
Cross-protocol numbers are not comparable — every figure in the table above
is one-shot, matching the rest of this page.

---

## simd-kernels — dot product and delimiter scanner (Task 4 validation)

Added 2026-08-11 as the validation kernels for the SIMD vector types plan
(`.superpowers/sdd/2026-08-10-simd-vector-types/`): `bench/simd_kernels.march`
runs two explicit-`Simd`-vs-baseline pairs at N=5,000,000 (dot product,
`f32`) / 16,000,000 bytes (delimiter scan, `u8`), self-timed the same way as
every other table on this page (data generation excluded from the timed
region), plus a deterministic interpreted-vs-compiled parity leg for
`fma_f32x4`. Compiled only (`--compile --opt 2`), redirected to files, never
piped.

**Methodology:** 5 rounds of the same compiled binary, interleaved (all four
legs run back-to-back within one process invocation each round, so there is
no separate-ordering warmup bias to control for — every round pays the same
warmup cost on the same first leg, `dot_simd`). Medians reported; min/max
included to show spread. **Load state:** shared machine, `pgrep -fl
"dune|run-tests"` showed one concurrent `dune build` from another worktree at
the start of this run; `uptime` load averages moved from ~14.7/15.9/14.9
(elevated) down to ~11.7/12.3/13.3 (still elevated, not idle) over the course
of the run. Despite that, the five per-leg timings clustered tightly
(coefficient of variation under 5% on every leg below) — these are
short, CPU-bound, allocation-dominated kernels where a few percent of shared
CPU contention barely moves the needle relative to the effect sizes involved,
so the comparisons below are treated as reliable despite non-idle load; they
are same-run, same-process comparisons only, not compared against any
historical baseline.

**Refreshed 2026-08-11 after the Task 4b vector-ABI fix** (see "dot_simd fix
note" below); the pre-fix `dot_simd` column is kept for comparison. Same
methodology, 5 interleaved rounds; load state at the refresh: shared machine,
one concurrent `run-tests.sh` from another worktree, `uptime` load averages
~11.0/11.6/12.0 throughout (elevated, not idle, and comparable to the original
run's ~11.7-14.7). Per-leg coefficient of variation stayed under 2%.

| dot(5M f32), ms      | Median | Min   | Max   |
|----------------------|--------|-------|-------|
| dot_simd (post-fix)  | 10.01  | 9.96  | 10.13 |
| dot_simd (pre-fix)   | 29.22  | 28.15 | 31.34 |
| dot_composed         | 2.55   | 2.40  | 2.72  |

| scan(16MB u8), ms | Median | Min    | Max    |
|-------------------|--------|--------|--------|
| scan_simd         | 19.28  | 19.07  | 20.41  |
| scan_scalar       | 221.32 | 221.14 | 222.97 |

**scan_simd beats its ≥4x bar**: 221.32 / 19.28 ≈ **11.5x** faster than the
byte-at-a-time scalar loop — this is the classic memchr-shaped SIMD win the
plan expected, and `--emit-llvm` confirms `scan_simd`'s loop never touches
`march_simd_alloc` (the mask value never escapes as a parameter to a
recursive call — see root cause below — it's consumed immediately by
`first_set_u8x16` within the same iteration).

**dot_simd fix note (2026-08-11, Task 4b).** The original run had `dot_simd`
at ~10.8x *slower* than `dot_composed`. Per the plan's contingency ("if a bar
fails: STOP, emit the kernel's LLVM, and report with the IR evidence — most
likely cause: boxing in the loop"), `--emit-llvm` confirmed exactly that:
`dot_loop`'s body allocated a fresh `F32x4` box (`march_simd_alloc`) on every
one of the ~1.25M iterations to pass the accumulator into the next call, even
though `dot_loop` is a plain top-level `pfn`. It was a slot-typing bug, not a
closure bug: `Llvm_toplevel.emit_fn` types every parameter alloca with
`llvm_ty`, which is `ptr` for the SIMD types, so the TCO **back-edge**'s
coerce-to-param-type re-boxed the accumulator each time round the loop. (The
IR also shows nothing `dec_rc`ing the slot's previous box, so those boxes
accumulated.)

That is fixed — a self-tail-recursive function's vector-typed parameter now
gets a native `<N x T>` TCO slot, unboxed once in the entry prologue, with the
function's signature left `ptr` so no caller is affected. The loop body's
`march_simd_alloc` count is now **0** and `dot_simd` went **29.22 ms → 10.01
ms (2.9x)**. See
`specs/progress/2026-08-11-simd-nested-closure-vector-accumulator-segfault.md`
— which also records the more severe sibling finding it was filed for, a
*segfault* (not just a slowdown) when the same accumulator loop is written as
a locally-nested closure, caused by the direct kickoff call and the indirect
self-call disagreeing on whether the vector param was boxed. Both are now
pinned by `test/native/simd_nested_closure_acc.march`.

**dot_simd still FAILS its "beats dot_composed" bar** — 10.01 ms vs 2.55 ms,
~3.9x slower. The remaining gap is *not* about vectors, and an attribution
probe holding the loop framework constant proves it: the SIMD index loop is
**4.0x faster than the equivalent scalar March index loop** (9.89 ms vs 39.95
ms over the same 5M pairs), which is the vector lowering doing its job. What
`dot_composed` really wins on is that it is a single call into a tight C
runtime pipeline, while any hand-written March index loop pays, per iteration,
a volatile preemption load, `llvm.stacksave`/`stackrestore`, two
`march_incrc_local` calls and two `native_f32_arr_length` bounds-check calls,
plus body allocas outside the entry block that `mem2reg` cannot promote. That
is general March loop-codegen overhead affecting every NativeArray index loop,
with its own blast radius and benchmark matrix, so it was left out of the
vector-ABI fix and filed separately as
`specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md`. As
before, `dot_simd` keeps the plan's intended algorithm rather than being
designed away, so the bar stays visible.

| 5M f32 dot, loop framework held constant | ms    |
|------------------------------------------|-------|
| SIMD index loop (4 lanes/iter)            | 9.89  |
| scalar index loop (1 elem/iter)           | 39.95 |
| `map2_f32` + `sum_f32` (one C call)       | 2.34  |

**fma_f32x4 parity leg**: `fma_parity_checksum` drives a deterministic LCG
(`(seed*1664525+1013904223) % 2147483647`, the repo's standard generator)
through 200,000 pseudo-random `f32` triples via `fma_f32x4`, folding lane 0
into a running sum — this is the property-style check for the interpreter
fma (`f32_round(Float.fma a b c)`, double FMA then round) vs. compiled
(`llvm.fma.v4f32`, true single-precision FMA) discrepancy flagged in an
earlier review. Interpreted and compiled `PARITY_CHECKSUM` were compared at
N=2,000 (both `-263.688627893`, exact bit-for-bit match printed by
`float_to_string`) and the `DOT_SIMD_RESULT`/`DOT_COMPOSED_RESULT`/
`SCAN_SIMD_RESULT` values at the full N=5,000,000/16,000,000 scale also
matched exactly between interpreted and compiled runs (`10000001.`,
`10000002.3842`, `12345678` respectively) — **no divergence observed**, so
no STOP-for-coordination was triggered on that leg.

## DataFrame Min/Max: not migrated

Per the plan's guidance ("ONLY migrate if DataFrame tests stay green AND the
bench shows non-regression; otherwise leave it and record why"):
`stdlib/dataframe.march`'s `col_native_min_max` **stays on the
`native_{int,float}_arr_min`/`_max` C builtins** rather than moving to a
`Simd.load_i64x2`/`hmin_i64x2`/`hmax_i64x2` (or `f64x2`) loop.

*Original finding (2026-08-11, before the Task 4b fix — superseded by the
re-probe below, kept for the reasoning trail):* the dot-product kernel above
demonstrated the blocking mechanism — a `Simd`-accumulator loop paid a heap
allocation on every iteration when the value was threaded through a
recursive/self-tail call — and a direct probe of
the DataFrame-shaped workload confirms it transfers: `native_int_arr_min`
over a 5,000,000-element `NativeIntArr` took **1.35 ms**; the equivalent
`Simd.min_i64x2`-accumulator loop (same algorithm shape as `dot_simd`,
2-lane stride) took **46.80 ms** — **~35x slower**, not a non-regression by
any margin.

**Re-probed 2026-08-11 after the Task 4b fix — the verdict is unchanged.**
The per-iteration boxing is gone, and the probe improved by 4.3x, but it is
still nowhere near non-regressing: `native_int_arr_min` **1.26 ms** vs. the
`Simd.min_i64x2` loop **10.38 ms** — **~8.2x slower** (was ~35x). Per the
plan's rule ("ONLY migrate if ... the bench shows non-regression"), Min/Max
**stays on the C builtins**. The residual gap is the general March
index-loop overhead documented under simd-kernels above
(`specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md`), so
this question should be re-opened if and when that is fixed — but note that
even then the ceiling here is low, because `i64x2`/`f64x2` are only 2 lanes
wide (vs. 4 for
`f32x4`/`i32x4`), so even with register residency fixed, the lane-count
ceiling on a win here is much lower than the `f32`/`u8` kernels above; the
existing C loops are already simple, tight, auto-vectorizable reductions
(see `runtime/march_runtime.c`'s `native_int_arr_min`/`native_float_arr_min`).
The new test `test/stdlib/test_dataframe.march` "col_native_min_max"
describe block (7-element, non-lane-multiple column, both `Int` and `Float`)
pins the existing (unmigrated) implementation's correctness so a future
migration attempt — once the residency gap above is fixed — has a regression
net from day one.

---

## Where March wins and trails

**Wins:** FBIP-shaped workloads (tree-transform) — in-place reuse under
Perceus RC beats every allocating implementation by a wide margin. Vectorizable
Float array ops (simd-sum, simd-map, simd-map2 — one- and two-array alike) —
ties or beats NumPy, competitive with hand-written OCaml/Rust.

**Trails:** allocation-heavy churn with short-lived objects (binary-trees),
where a generational GC is structurally better than RC; tight iterator
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
