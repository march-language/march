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

## Addendum, 2026-07-27: `index_of_from` measured, and what it does to the split decision

`String.index_of_from` (phase 2 Task 1) landed. Same-session A/B, counting every
field in an 800KB CSV-shaped buffer over 60 passes, both halves in one process:

| Method | Time (3 runs) | Allocations |
|---|---|---|
| `String.split` + `List.length` | 975 / 988 / 987ms | ~9M strings + ~9M cons cells, 39.8MB copied |
| `index_of_from` walk | **267 / 269 / 268ms** | ~0 (7 strings for a single pass, no copying) |

Identical field counts (9,000,060) both ways, so the work is equivalent.
**3.7× faster with effectively no allocation.**

The six harness benchmarks are unchanged by this, correctly: `index_of_from` is
a new entry point, not an optimization of an existing path. Nothing in the
corpus calls it.

**This strengthens option C in phase 2 Task 5's decision** (the container-returning
`split`). A large share of what a zero-cons `split` would buy is available today
without any new container type, provided the caller wants to *scan* rather than
to *materialize* the fields. The remaining case for a new container is narrower
than phase 1 implied: it is specifically for callers that genuinely need every
field as a retained `String`, which the scan pattern does not serve.

Before building a `StringArray`, measure how much of the real workload is
scan-shaped versus materialize-shaped. If it is mostly the former, Task 5 should
close as "not needed" rather than ship a container type nobody's hot path uses.

## Addendum, 2026-07-27: Task 4's gate, settled by cross-language measurement

`bench/run_string_xlang.sh` runs `string_small_churn` (2M short-string
build/concat/compare cycles) against four baselines chosen to separate two
explanations a single number cannot distinguish. All five print the same
checksum, so the work is equivalent; all five ran back-to-back in one session,
so the ratios are sound even though the machine was loaded and the absolute
milliseconds are not comparable across runs.

| | ms | vs March |
|---|---|---|
| C++ (`std::string`, **has SSO**) | 246 | **3.0× faster** |
| C (raw `malloc`, no header, no RC) | 411 | 1.8× faster |
| Rust (`String`, **no SSO** — same representation as March) | 566 | 1.3× faster |
| **March** | **741** | — |
| Python (`pymalloc` size classes) | 1305 | 1.8× slower |

**Verdict: the phase 1 recommendation was wrong, and so was its phase 2
refinement.** Phase 1 said "SSO indicated"; the phase 2 plan then argued for a
size-class freelist instead, on the grounds that true SSO is far more invasive.
The data does not support that ordering:

- **Rust has March's exact representation** — heap allocation per string, no
  inline storage — and is only ~1.3× faster. That gap is allocator and refcount
  overhead, and it bounds what a freelist can win. It is the smallest gap in the
  table and therefore the least precise; treat it as "roughly a third", not 31%.
- **C++ with SSO is 3× faster, and faster than C with raw `malloc`** (246 vs
  411ms). A hand-rolled allocator cannot beat not allocating at all. This is the
  decisive comparison, and it is why C++ was worth adding as a one-off despite
  not being in the project's usual baseline set.

So the ordering is inverted: **a freelist buys roughly a third; the 3× needs
inline storage.** A freelist is still the cheaper change and still a real win,
but it should be chosen knowing it forecloses most of the available gain, not
in the belief that it captures it.

Nothing here says to build SSO now — it is a String ABI change touching
`IS_HEAP_PTR`, the erased-i64 tagging convention, codegen, and the C FFI. It
says the decision is between "a third, cheaply" and "3×, expensively", which is
a different question from the one the phase 2 plan posed.

## Addendum, 2026-07-27: what SSO would actually take in March

### The encouraging part: the RC hot path needs no changes

March already tags immediates, and `IS_HEAP_PTR` already rejects them:

    immediate integer n  -> ptr = (n << 1) | 1   (low bit set)
    heap pointer p       -> ptr = p              (low bit clear)

    #define IS_HEAP_PTR(p) \
        (((uintptr_t)(p) & 1u) == 0 && (uintptr_t)(p) >= 4096u && (intptr_t)(p) > 0)

`march_incrc` and `march_decrc` both begin with `if (!IS_HEAP_PTR(p)) return;`.
So **an inline string carrying the tag bit is refcount-free with no change to the
RC path** — normally the most invasive part of retrofitting SSO, and here it is
already done.

### The constraining part: capacity

A tagged immediate has 64 bits total. One bit distinguishes immediate from
pointer; a second is needed to distinguish an inline string from an immediate
*integer*, which already claims the low-bit-set encoding. Three more bits hold
the length (0-7). That leaves **7 bytes of payload**.

Against the measured distribution on `bench/string_small_churn` (10,000,009
allocations on current main):

| inline capacity | allocations eliminated | what it costs |
|---|---|---|
| **7 bytes** (fits the existing tag scheme) | **42%** | runtime + codegen only; no ABI change, no RC change |
| 15 bytes | 61% | String becomes a 2-word value — ABI change across every signature, closure, and FFI boundary |
| 23 bytes | 80% | 3 words, or reusing the 24-byte header; same ABI change, larger |

C++ gets its 3× with 15 bytes (libstdc++) or 22 (libc++), which is why it
captures so much more than 7 bytes would.

### What 7-byte inline strings would break

Bounded, and all in one layer: roughly 30 runtime functions dereference
`((march_string *)p)->len` or `->data` and would each need a tag check first,
plus the codegen sites that construct and consume strings. The FFI boundary
needs materialization before handing a pointer to C. The JS backend is
unaffected (strings are JS strings there).

Notably it is **not** a type-system change: `String` stays one type, and nothing
in typecheck, mono, or defun needs to know.

### Measured: real workloads are MORE <=7-skewed than the synthetic benchmark

The analysis above worried that 7 bytes is too small, since HTTP header names
(`content-type` at 12, `user-agent` at 10) exceed it. Measured against real
workloads, that worry was wrong in the opposite direction:

| workload | allocations | <=7 bytes | <=15 |
|---|---|---|---|
| `bench/iolist_template` (web templating) | 100,007 | **53%** | 100% |
| JSON parse + re-serialize | 9,720,054 | 90% | 96% |
| `bench/string_split_large` (CSV-shaped) | 9,000,126 | 99.99% | ~100% |
| `bench/string_small_churn` (synthetic) | 10,000,009 | 42% | 61% |

**Trust the templating number (53%), not the other two.** The CSV split is my
own synthetic with 3-byte fields. And the JSON figure is an ARTIFACT: that
parser allocates 2.03 strings per input BYTE for a 239-byte document containing
about 20 distinct strings — 486 allocations per parse. Those are one-character
strings from per-character token building, not real content. Tracked separately;
it is a parser bug worth more than the SSO it would flatter.

That artifact is itself the sharpest argument for care here: **an SSO would make
an allocation-heavy implementation look fast without fixing it.** The JSON
parser would go from 486 tiny allocations per parse to 486 free inline strings,
and nobody would notice it is allocating 24x more strings than the document
contains.

Revised estimate: 7-byte inline storage eliminates roughly **half** of
allocations in real templating work — better than the 42% the synthetic
benchmark suggested, and it needs no ABI change and no RC-path change.

### Honest assessment

7-byte inline strings are the only variant that fits March's existing
representation, and they address 42% of allocations. That is real, and it is
strictly better than the freelist option, which the cross-language data bounds at
roughly a third and which does not compose with anything.

But 7 bytes is genuinely small for the workload that motivated this. HTTP header
names — `content-type` at 12 bytes, `user-agent` at 10 — mostly miss it. The
42% figure comes from one synthetic benchmark whose string sizes were chosen to
straddle the 23-byte boundary, not from a real corpus.

That measurement has now been done (see above) and it came back favourable:
real templating work is 53% <=7 bytes, better than the synthetic 42%. The
remaining question is not whether the sizes fit but whether ~half of allocations
going free is worth a runtime-and-codegen change across ~30 functions — and
whether some of the workloads that would benefit should instead stop allocating
so much, as the JSON parser should.

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
