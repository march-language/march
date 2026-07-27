# String Performance — Phase 1 Profile and Verdicts

**Date:** 2026-07-27
**Machine:** Apple M3 Max (14 logical cores: 10 performance + 4 efficiency), macOS, arm64
**Spec:** `specs/2026-07-26-string-performance-design.md`
**Plan:** `specs/plans/2026-07-26-string-performance-phase1.md`
**Raw results:** `bench/STRING_RESULTS.md` (regenerate with `bash bench/run_string_bench.sh`)

All benchmarks compiled `--opt 2`, median of 5 runs.

---

## Results

| Benchmark | Median ms | Peak RSS MB | Str allocs | Obj allocs | Copied MB | Peak live MB |
|---|---|---|---|---|---|---|
| string_scan | 578.5 | 6.6 | 162 | 0 | 3.7 | 2.9 |
| string_case | 582.7 | 8.7 | 406 | 0 | 382.4 | 2.9 |
| string_split_large | 561.0 | 557.7 | 9,000,126 | 9,000,120 | 38.0 | 38.0 |
| string_slice_walk | 307.9 | 3.7 | 9,000,006 | 0 | 26.5 | 0.8 |
| string_small_churn | 801.1 | 340.0 | 24,000,004 | 0 | 191.4 | 45.8 |
| string_parallel_scan | 279.9 | 290.3 | 98 | 812 | 343.3 | 110.6 |

Allocation size histogram, `string_small_churn` (24,000,004 allocations):

| ≤7 | ≤15 | ≤23 | ≤31 | ≤63 | ≤255 | >255 |
|---|---|---|---|---|---|---|
| 13,206,191 | 6,893,812 | 1,901,930 | 1,998,071 | 0 | 0 | 0 |

**91.7% of allocations are ≤23 bytes** — the size that would fit inline in the
footprint the 24-byte `march_string` header already occupies.

Parallel scaling, `string_parallel_scan` (40MB shared buffer, stable across
three runs):

| Workers | 1 | 2 | 4 | 8 |
|---|---|---|---|---|
| ms | 131 | 66 | 34 | 33 |
| speedup | 1.00× | 1.97× | 3.85× | 3.97× |

---

## Corpus validity check

The spec's first risk is that the corpus measures the wrong thing. Sampling
`string_split_large` under `sample(1)` puts the hot path at
`march_main → march_string_split → march_string_alloc → malloc` (tiny zone),
which is what the benchmark targets. The corpus is measuring what it claims to.

Worth noting on its own: the profiler shows **allocation, not copying**, at the
top of the split path — consistent with the counter data below.

---

## Verdicts against the pre-committed criteria

The criteria below are quoted verbatim from the spec, which fixed them *before*
any measurement, so these verdicts are checkable rather than rationalized.

### SSO — **INDICATED**

> **SSO is indicated** if ≥40% of allocations land in the ≤23-byte buckets *and*
> `string_small_churn`'s wall time scales at least linearly with its allocation
> count when the string-count knob is doubled.

Both halves met, and not marginally:

- **91.7%** of allocations are ≤23 bytes, against a 40% threshold.
- Doubling the knob doubled allocations (24,000,004 → 48,000,004) and wall time
  (0.80s → 1.58s, 1.98×). Allocation cost is proportional, not incidental.

The corpus supports this beyond the one benchmark: `string_split_large` and
`string_slice_walk` each allocate ~9M strings of 3 bytes, and the profiler puts
`malloc` at the top of the split path.

### Views — **NOT INDICATED** (but see the split verdict)

> **Views are indicated** if `string_split_large` and `string_slice_walk` report
> bytes-copied ≥ 2× the input size *and* ≥25% of their wall time disappears when
> the copy is elided.

Not met. Each processes 48MB of input (800KB × 60 passes) and copies 38.0MB and
26.5MB respectively — **0.79× and 0.55× of input, not ≥2×**. Every field is
copied exactly once. There is no copy amplification for views to remove, so the
second half of the criterion was not measured: the first already fails.

This is the criterion most at risk of being talked into, and the data says no.
Views remain attractive for other reasons (they would make `slice` allocation-free
entirely), but *not* on the evidence this phase was built to gather.

### Array-returning `split` — **INDICATED**

> If split is ≥1.5× slower than slice-walk at comparable copy volume, the
> indicated fix is an array-returning `split`, not views.

Met. `string_split_large` is **1.82×** slower than `string_slice_walk`
(561.0ms vs 307.9ms) while copying only 1.43× as many bytes. The two allocate
essentially the same number of *strings* (9,000,126 vs 9,000,006); the entire
structural difference is **9,000,120 cons cells versus 0**. The excess time
tracks the list, not the copying.

### Additive-only (SIMD search) — **worth doing, but not the main cost**

> **Additive-only wins** if neither dominates and time concentrates in the scan
> loops.

Scanning is genuinely slow in absolute terms: `string_scan` processes roughly
285MB in 578ms, about **0.5 GB/s**, where a `memmem`-class implementation is
several GB/s. So `memchr`/SIMD is real headroom.

But time does *not* concentrate there relative to allocation: the two
allocation-heavy benchmarks (`small_churn`, `split_large`) dominate the corpus,
and the profiler puts `malloc` above the scan loops. SIMD search stays worth
doing — it was never gated on this profile — but it is not the largest win
available.

### Phase 3 contention gate — **TRIGGERED**

> **Phase 3 contention gate:** if `string_parallel_scan` scales worse than ~4× at
> 8 workers on a shared owner, chunked parallel operations need a
> refcount-contention answer *before* the chunking algorithm is worth writing.

Measured **3.97× at 8 workers**, with scaling flat from 4 workers onward. The
ceiling is not explained by core count (8 performance cores were available of
10) nor by memory bandwidth (~80MB of traffic in 33ms ≈ 2.4GB/s, far below this
machine's capability). Shared-owner refcount traffic and allocator contention
are the remaining candidates, and **distinguishing them is phase 3's first
task** — writing a chunking algorithm before then would be building on an
unexplained ceiling.

---

## Blocker: two compiled-only RC leaks

The harness found these on its first real run. Both have minimal repros; both
are absent when interpreted (OCaml GC).

1. **`x ++ "literal"`** allocates a fresh copy of the literal on every
   evaluation and never frees it. The same loop with both operands as variables
   is clean (2,000,004 allocations / 2,000,001 frees, 2.9MB RSS); with a literal
   operand it is 4,000,003 / 2,000,001 and 64.2MB RSS, growing linearly with
   iteration count.
2. **A hand-written recursive walk over `List(String)`** never frees the
   elements. `string_split_large` reports **9,000,126 string allocations and 3
   frees**, RSS growing ~9.3MB per iteration (5 = 52MB, 20 = 190MB, 60 = 558MB).
   Consuming the same list with the builtin `List.length` drops the leak to 1
   per iteration.

**These invalidate the memory columns.** Peak RSS and peak-live measure leaked
memory as much as working set, so they cannot support a representation decision
yet. That matters most for the views criterion, which partly rests on memory —
though as recorded above, views already fail on copy volume, which the leaks do
not affect.

Acting on the memory numbers as they stand would justify a new string
representation to fix what is actually a reference-counting bug. That is the
same failure this phase exists to prevent, reached from the opposite direction.

Timing, allocation counts, and copy volumes are unaffected and were used for
every verdict above.

---

## Recommendation for phase 2

1. **Fix the two RC leaks first.** They are not string work, they block the
   memory evidence, and they are a correctness problem in their own right — any
   March program that builds strings in a loop or walks a split result leaks.
2. **Small-string optimization** is the largest supported win: 91.7% of
   allocations would fit inline, allocation cost is proportional to count, and
   the profiler puts `malloc` at the top of the hottest path.
3. **Array-returning `split`** (or a Vec-returning variant), on the 1.82×-vs-1.43×
   evidence. Cheaper than a representation change and independently useful.
4. **`memchr`/SIMD search**, at ~0.5 GB/s today. Real headroom, unblocked by
   anything here, but not the top of the list.
5. **Do not build views on this evidence.** Revisit only if a workload shows
   genuine copy amplification, which this corpus does not.
6. **Re-run the memory criteria after step 1**, then decide whether anything in
   the views direction is still indicated.

Phase 3 stays gated on explaining the 4-worker ceiling.
