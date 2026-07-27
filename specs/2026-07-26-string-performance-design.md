# String Performance — Phase 1: Measurement

**Status:** design approved, not yet implemented
**Date:** 2026-07-26
**Scope:** phase 1 of a three-phase program. Phases 2 and 3 get their own specs,
written after phase 1 reports.

---

## Goal

Make March string operations fast, parallelizable, and memory efficient, for
three workloads:

- **Bulk data processing** — parsing and transforming large inputs (CSV, JSON,
  logs), where a single string can be megabytes.
- **Web serving** — many small strings per request, high allocation churn,
  latency-sensitive.
- **Benchmark positioning** — competitive standing on string-heavy benchmarks.

Phase 1 does not make any of that faster. It produces the measurements that
decide *how*.

## Why measurement comes first

The central question is whether the string representation itself must change.
Today `march_string` (`runtime/march_runtime.h:122`) is:

```c
typedef struct { int64_t rc; int32_t tag; int32_t pad; int64_t len; char data[]; } march_string;
```

A single contiguous, immutable, refcounted, NUL-terminated UTF-8 buffer, one
`malloc` per string. There are no views: `slice`, `trim`, `to_lowercase`, and
`split` all copy. `split` on an n-field input allocates n strings *and* n cons
cells. There is no small-string optimization, so a 3-byte string still costs a
heap allocation plus refcount traffic.

Three candidate answers follow from that, and they imply very different work:

| Answer | Unlocks | Cost |
|---|---|---|
| **Slice/view variant** | zero-copy `slice`/`split`/`trim` | every reader of `->data` goes through an accessor; NUL-termination no longer guaranteed; FFI must materialize views before handing pointers to C |
| **Small-string optimization** | no malloc for short strings | touches RC, codegen, and every runtime string function |
| **Additive only** | SIMD search, n-ary concat | lower ceiling: splitting a 10MB CSV still copies every field |

Choosing between these by reasoning is exactly the mistake that produced the
defects in PR #90: an asymptotic argument (`++` is O(k²), `string_join` is O(n))
that was correct in the limit and wrong at real sizes, because it omitted the
constant cost of materializing a cons list. Measurement showed that constant to
be 59% of the work at five parts. The same failure mode is available here at
much larger scale, so the thresholds are committed in advance (see *Decision
criteria*).

## Phase decomposition

1. **Measurement** (this spec) — benchmark corpus, runtime counters, harness.
   Output: a profile good enough to decide the representation question.
2. **Representation and core ops** — views vs SSO vs additive, chosen from
   phase 1 data. Carries the two wins that are certain regardless: `memchr`/SIMD
   search, and n-ary concat.
3. **Data-parallel string ops** — chunked `split`/`scan`/`count`/`replace`
   across cores, with the chunk-boundary and refcount-contention problems that
   phase 1's scaling curves will have quantified.

## Non-goals for phase 1

- No optimization work. Phase 1 changes no string operation's behavior.
- No new March-level builtin, and no codegen changes.
- No decision about SIMD search or n-ary concat — both are worth doing
  regardless of what the profile says, so they are not gated on it.
- No benchmark for `replace_all`: it is a composite of scan plus build, so it
  would blur attribution, and it follows from `string_scan` plus
  `string_split_large`.

---

## Component 1 — Benchmark corpus

Organizing rule: **each program isolates one cost**, so the profile is
attributable. Inputs are generated in-process (deterministic, no fixtures, no
I/O inside the timed region) and sized by a constant, so the same program runs
small in CI and large for profiling. Each prints a checksum-style number,
matching the existing `bench/` convention.

Six new programs in `bench/`, each documented in `specs/benchmarks.md` with
expected output, features exercised, and cross-language baselines, exactly like
the existing 20:

| Program | Isolates |
|---|---|
| `string_scan.march` | scan throughput — `index_of`/`contains` over a large buffer, needle absent (full scan, the honest worst case) and needle at 90% |
| `string_split_large.march` | the realistic mix — split a CSV-shaped multi-MB buffer on `,` and `\n`: one allocation *and* one cons cell *and* one copy per field |
| `string_slice_walk.march` | copying off a large owner with **no** cons cells — tokenize the same buffer by `index_of` + `slice`, building no list |
| `string_case.march` | transform throughput — `to_lowercase`/`to_uppercase` over a large buffer; a SIMD target with a different shape (no search, pure map+copy) |
| `string_small_churn.march` | per-allocation overhead — many small strings (4–30 bytes, header-name/value sized), concat and compare |
| `string_parallel_scan.march` | parallel scaling and refcount contention — the same scan under `Parallel.pmap`, one chunk per worker, at 1/2/4/8 workers, all sharing one input string |

**The gap between `string_split_large` and `string_slice_walk` is the
load-bearing measurement.** Both copy off a large owner; only the first builds
cons cells. Their difference separates "cons cells are the problem" from
"copying is the problem" — which is precisely the fork between an
array-returning `split` and a view representation.

`bench/string_build.march` and `bench/string_pipeline.march` stay unchanged.
They already cover join and map-then-join; re-doing them would add noise.

`bench/iolist_template.march` and `bench/tfb` already cover end-to-end serving,
so `string_small_churn` deliberately does not duplicate them — it exists to
isolate allocation overhead, not to model a request.

## Component 2 — Runtime counters

`march_string_alloc` (`runtime/march_runtime.c:361`) is the single choke point
for string allocation: it holds the only raw `malloc(sizeof(march_string)…)` in
the runtime, and all 14 other string-creating sites call it. Allocation
instrumentation is therefore one insertion point.

**Known blind spot:** `runtime/march_http.c:350` builds a string with a raw
`malloc` and will not be counted. Documented rather than papered over; if HTTP
paths become interesting, that site gets converted to `march_string_alloc`
first.

Gated on `MARCH_STRING_STATS=1`, following the existing `gc_trace_on()` pattern
(a cached static read once) with relaxed atomics like `march_live_alloc_count`.
Off by default: the cost is one predictable branch inside a function that is
already calling `malloc`.

Tallied:

- **allocation count** and **payload bytes**
- **size histogram**, bucketed ≤7, ≤15, ≤23, ≤31, ≤63, ≤255, >255 bytes. This
  is the load-bearing counter: the SSO question is "what fraction of strings
  would fit inline", and a mean would hide exactly that distribution. 23 bytes
  is the meaningful cutoff — what fits in the footprint the 24-byte header
  already occupies.
- **bytes copied**, via a `march_str_copy()` inline wrapper replacing the bare
  `memcpy` calls in string operations, so copying is attributable per-operation
  rather than as one lump.
- **frees** and **peak live string bytes**

**Reporting:** an `atexit` handler prints a table to stderr when the flag is on.
Deliberately *not* a March builtin — a new builtin would mean touching
typecheck, eval, `defun`'s `builtin_names`, `llvm_builtins`, and the JS runtime
shim, and buys nothing over the env flag. Phase 1 makes zero codegen changes.

## Component 3 — Harness

`bench/run_string_bench.sh`, following `bench/run_bench.sh`'s conventions.

- **Timing** via a python3 wrapper, as `run_bench.sh` already does, rather than
  `/usr/bin/time`, whose output format differs between macOS and Linux.
- **Peak RSS** from `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss` in that same
  wrapper — one mechanism on both platforms. **The unit must be normalized:
  macOS reports bytes, Linux kilobytes.** Getting this backwards silently
  reports a 1024× error.
- Each benchmark runs 5 times; the median wall time is reported, with the
  min/max spread printed alongside so a noisy run is visible rather than
  averaged away.
- Output is a markdown table written to `bench/STRING_RESULTS.md`, alongside the
  existing `RESULTS.md`.
- Everything compiled with `--compile --opt 2`, never interpreted. Per the
  project's benchmark rule, interpreted runs on these shapes take hours and
  would measure the interpreter rather than the strings.

**Placement:** manual/CI-optional, not part of `dune runtest`. Adding minutes to
the default test loop would train everyone to skip it.

---

## Decision criteria

Committed before measuring, so the choice cannot be rationalized after the fact.
These thresholds are judgment calls; what matters is that they are falsifiable
and fixed in advance.

- **SSO is indicated** if ≥40% of allocations land in the ≤23-byte buckets *and*
  `string_small_churn`'s wall time scales at least linearly with its allocation
  count when the string-count knob is doubled (if time is flat while allocations
  double, allocation is not the bottleneck and SSO would buy little).
- **Views are indicated** if `string_split_large` and `string_slice_walk` report
  bytes-copied ≥ 2× the input size *and* ≥25% of their wall time disappears when
  the copy is elided (measured by a throwaway build whose `slice` returns the
  owner unchanged — wrong semantics, but a valid upper bound on the win). If
  split is ≥1.5× slower than slice-walk at comparable copy volume, the indicated
  fix is an array-returning `split`, not views.
- **Additive-only wins** if neither dominates and time concentrates in the scan
  loops, making `memchr`/SIMD the entire answer.
- **Phase 3 contention gate:** if `string_parallel_scan` scales worse than ~4× at
  8 workers on a shared owner, chunked parallel operations need a
  refcount-contention answer (scoped borrow without RC traffic, or per-chunk
  owned copies) *before* the chunking algorithm is worth writing.

These are not mutually exclusive: the profile may indicate both SSO and views,
in which case phase 2 sequences them by measured payoff.

## Keeping the harness honest

A benchmark suite that lies is worse than not having one. Three specific failure
modes, each with a guard:

1. **Doing less work than it claims.** Every benchmark prints a deterministic
   checksum, and the harness *asserts* it against the value documented in
   `specs/benchmarks.md`. A mismatch fails the run rather than reporting a
   suspiciously good number. This is the guard against the compiler eliminating
   a scan whose result nothing consumes.
2. **Counters that miscount.** A unit test runs a program making a known number
   of string allocations at known sizes and asserts the histogram matches
   exactly. A representation decision is about to rest on these numbers; they
   must be validated, not trusted.
3. **Instrumentation contaminating the baseline.** A test asserts that a
   benchmark's median runtime with `MARCH_STRING_STATS` off is within 2% of an
   uninstrumented build, so "zero overhead when off" is a fact rather than an
   assumption.

**Failure handling:** if a benchmark fails to compile or crashes, the harness
reports it and continues, then exits non-zero. It never silently skips — this
codebase has been bitten before by skip-on-failure producing vacuous green runs,
and a perf suite that quietly drops its hardest case is that same failure mode.

## Risks

- **The corpus measures the wrong thing.** Mitigation: once built, profile one
  real workload (`bench/tfb` or a CSV parse) under `perf`/Instruments and
  confirm it points at the same hot spots. If it doesn't, the corpus is wrong
  and gets fixed before phase 2 reads anything into it.
- **Benchmark noise swamps the signal**, particularly for `string_parallel_scan`
  on a loaded machine. Mitigation: median of N runs; scaling curves interpreted
  as shapes rather than absolute numbers.
- **`ru_maxrss` measures the whole process**, including compiler-independent
  startup and the scheduler's arenas. It is a floor-plus-delta, not a pure
  string number; the spec treats RSS *deltas between benchmarks* as the signal,
  not absolute values.

## Deliverables

1. Six `bench/string_*.march` programs with `specs/benchmarks.md` entries.
2. `MARCH_STRING_STATS` counters in `runtime/march_runtime.c` plus the
   `march_str_copy()` wrapper.
3. `bench/run_string_bench.sh` and its `bench/STRING_RESULTS.md` output.
4. Three harness-integrity tests (checksum assertion, counter validation,
   zero-overhead check).
5. A written profile applying the decision criteria, which becomes the opening
   section of the phase 2 spec.
