# March Benchmarks

All benchmarks live in `bench/`. Run the full suite:

```
bash bench/run_bench.sh
```

Compile and run an individual benchmark:

```
dune exec march -- --compile --opt 2 bench/<name>.march -o /tmp/<name>
/tmp/<name>
```

---

## bench/fib.march — Naive recursive Fibonacci

**Command:** `fib(40)`
**Expected output:** `102334155`

| Feature exercised | Notes |
|-------------------|-------|
| Naive recursion | Exponential call tree — no allocation |
| Integer arithmetic | Pure `+` on unboxed `Int` |
| Function call overhead | ~330 million calls for fib(40) |

**Comparison baseline:** C, OCaml, Rust, Python, Go (all naive recursive).
**What to watch:** March should be within ~10% of C/Rust/OCaml. A regression here
points to function-call or codegen overhead.

---

## bench/binary_trees.march — Binary Trees (Benchmarks Game depth=15)

**Command:** depth 15, min 4
**Expected output:** standard Benchmarks Game output

| Feature exercised | Notes |
|-------------------|-------|
| Heap allocation | Millions of `Node`/`Leaf` allocations |
| Reference counting | Perceus dec_rc on every freed node |
| Pattern matching | `check` walks entire tree via `ECase` |
| Tail recursion | `sum_trees` / `run_depths` are tail calls |

**Comparison baseline:** C (manual malloc/free), OCaml (GC), Rust (Box<T>), Python, Go.
**What to watch:** OCaml's tracing GC batches frees and typically wins here.
March pays per-node dec_rc. A large regression vs the previous run suggests
the Perceus pass is inserting extra dec_rc calls.

---

## bench/tree_transform.march — FBIP tree rewrite (depth=20, ×100)

**Command:** `make(20)` → `repeat(inc_leaves, 100)` → `sum_leaves`
**Expected output:** `104857600`

| Feature exercised | Notes |
|-------------------|-------|
| **FBIP (Functional But In-Place)** | Primary target — uniquely owned nodes rewritten in-place |
| Perceus `EReuse` | `reuse t as Leaf(n+1)` / `reuse t as Node(l', r')` |
| `try_fbip_sink` | Sinks `EDecRC` through intermediate `ELet` bindings |
| Constructor-type tagging | DecRC carries concrete `TCon(ctor, [])` for shape matching |
| Recursive tree traversal | `inc_leaves` is structurally recursive, not tail-recursive |

**Comparison baseline:** C (alloc+free every iteration), OCaml (alloc+GC), Rust (Box<T> drop+alloc).
**What to watch:** March should be ~15–17× faster than C and ~7× faster than OCaml.
If FBIP regresses (TIR shows `alloc` instead of `reuse`), check:
1. `shape_matches` — are constructor types being compared correctly?
2. `try_fbip_sink` — is the DecRC reaching the EAlloc through ELet chains?
3. ECase scrutinee handling — is the DecRC emitted with the concrete ctor tag?

---

## bench/list_ops.march — HOF pipeline (range 1M → map → filter → fold)

**Command:** `irange(1, 1_000_000) |> imap(*2) |> ifilter(%3=0) |> ifold(+, 0)`
**Expected output:** `333333666666`

| Feature exercised | Notes |
|-------------------|-------|
| Higher-order functions | `imap`, `ifilter`, `ifold` take closure arguments |
| Closure call overhead | Each element invokes a captured lambda |
| Tail recursion | All list ops use accumulator+reverse pattern |
| Intermediate allocation | Two full intermediate lists (`ys`, `zs`) |
| `EReuse` on list cons cells | FBIP rewrites `ICons` in-place during `imap`/`ifilter` |

**Comparison baseline:** C (arrays, direct loops — best case), OCaml (`List.map`/`filter`/`fold_left`), Rust (iterators), Python (list comprehensions).
**What to watch:** March uses linked lists with intermediate allocations;
C/Rust use arrays or lazy iterators — the gap is expected. March should be
within ~30% of OCaml (same list-based approach, similar RC overhead to GC here).
A large regression vs OCaml points to closure dispatch or intermediate-list GC overhead.

---

## bench/string_build.march — Join 500K integer strings

**Command:** build List(String) of 1..500000, `string_join(list, "")`
**Expected output:** `2888895` (sum of digit-lengths of integers 1..500000)

| Feature exercised | Notes |
|-------------------|-------|
| `int_to_string` | 500K calls in a tail-recursive loop |
| `string_join` | Single O(n) join via C runtime `march_string_join` |
| Tail recursion | `build` is tail-recursive with List accumulator |
| Reference counting | Cons cells freed after join |

**Comparison baseline:** C (pre-allocated buffer, single sprintf loop), OCaml (Buffer.t), Rust (String::collect), Python (str.join), Go (strings.Builder).
**What to watch:** March pays per-Cons-cell allocation; C/OCaml Buffer avoids it. A regression vs the prior March run points to RC overhead or codegen for `string_join`.

---

## bench/string_pipeline.march — Double and rejoin 100K integer strings

**Command:** build list of 1..100000, `map double_str`, `string_join(list, ",")`
**Expected output:** `644449` (byte length of "200000,199998,...,4,2")

| Feature exercised | Notes |
|-------------------|-------|
| `string_to_int` | 100K calls inside `double_str` |
| `int_to_string` | 100K calls to format doubled values |
| `string_join` | O(n) join at the end |
| Pattern match on `Option` | `Some(n)` / `None` branch in `double_str` |
| Recursive list map | `map_strings` is non-tail-recursive (100K depth) |

**Comparison baseline:** C (sprintf loop), OCaml (Buffer + atoi), Rust (map + join), Python (list comprehension), Go (strconv + strings.Join).
**What to watch:** March uses a linked list; C/Rust use arrays. March should be within ~2× of OCaml. A regression vs OCaml points to Option allocation or string_to_int overhead.

---

## bench/string_scan.march — Substring search over a 1MB buffer

**Command:** 150 absent-needle scans + 150 late-needle scans over 1MB
**Expected output:** `checksum=135000150`

| Feature exercised | Notes |
|-------------------|-------|
| `String.index_of` | Byte-at-a-time loop calling `memcmp` — no `memchr`, no SIMD |
| Absent needle | Full O(n·m) worst case: every byte examined on every call |
| Late needle | Realistic "found at ~90% through" case |

**Comparison baseline:** C (`memmem`), Rust (`str::find`), Go (`strings.Index`), Python (`str.find`).
**What to watch:** Part of the phase 1 string measurement (`specs/2026-07-26-string-performance-design.md`). March is expected to trail C badly here until a `memchr`/SIMD search lands; the point of the benchmark is to size that gap. Once the fast path exists, a regression here points at it.

---

## bench/string_case.march — Case conversion over a 1MB buffer

**Command:** 200 × (`to_uppercase` then `to_lowercase`) over 1MB
**Expected output:** `checksum=200000000`

| Feature exercised | Notes |
|-------------------|-------|
| `String.to_uppercase` / `to_lowercase` | Full-size allocation + byte-loop transform per call |
| Allocation throughput | 400 full-buffer allocations |
| Memory bandwidth | Pure map-and-copy, no search |

**Comparison baseline:** C (in-place `toupper` loop), Rust (`to_uppercase`), Go (`strings.ToUpper`), Python (`str.upper`).
**What to watch:** Paired with `string_scan` — if both are slow the ceiling is memory bandwidth, not the search loop, and no cleverness in `index_of` will help. **Its checksum cannot detect the conversion being optimized away** (it sums `byte_size`, which case conversion leaves unchanged), so judge a suspicious speedup by `copy_bytes` under `MARCH_STRING_STATS=1` — it should stay near 400MB. Under `MARCH_STRING_STATS=1` this should report ~400MB copied; a reading near 1MB means the byte-loop builders lost their copy accounting again (they don't call `memcpy`, so they're counted explicitly).

---

## bench/string_split_large.march — Split an 800KB CSV-shaped buffer

**Command:** 60 × `String.split(buf, ",")` over 800KB (50K rows, 150K fields)
**Expected output:** `checksum=39000000`

| Feature exercised | Notes |
|-------------------|-------|
| `String.split` | One string + one cons cell + one copy per field |
| Cons-cell allocation | ~150K cells per iteration |
| Peak memory | Every field is live simultaneously |

**Comparison baseline:** C (in-place `strtok`, zero copy), Rust (`split` iterator, zero copy), Go (`strings.Split`), Python (`str.split`).
**What to watch:** **Paired with `string_slice_walk`** — same buffer, same field shape, same field count, on purpose. Changing one file's size knob without the other invalidates the comparison. Measured together (60 iterations): `obj_allocs` 9,000,120 vs 0 (the cons cells), `copy_bytes` 39.8MB vs 27.8MB, `peak_live_bytes` **39.8MB vs 800KB**. Note that `allocs` — the *string* counter — is nearly identical for the two (9,000,126 vs 9,000,006), because cons cells go through `march_alloc` rather than `march_string_alloc`; use `obj_allocs` for list overhead.

---

## bench/string_slice_walk.march — Slice 150K fields out of 800KB, no list

**Command:** 60 × 150K `String.slice` calls over 800KB, building no list
**Expected output:** `checksum=27000000`

| Feature exercised | Notes |
|-------------------|-------|
| `String.slice` | Allocates and copies off a large owner — no view representation exists |
| Zero cons cells | The controlled difference vs `string_split_large` |
| Flat peak memory | One field live at a time |

**Comparison baseline:** C (pointer walk, zero copy), Rust (`&str` slices, zero copy), Go (slicing, zero copy), Python (`str` slicing, copies).
**What to watch:** See `string_split_large`. Languages with string views do this with no allocation at all, so the gap is the size of the prize. This benchmark walks by arithmetic rather than by searching: the natural formulation (`index_of` the separator, slice off the tail, recurse) is O(n²) in bytes copied, since `String.index_of` has no start-offset variant and the tail must be re-sliced every step. Search cost is measured separately by `string_scan`.

---

## bench/string_small_churn.march — 2M short-string build/compare cycles

**Command:** 2M × (build two short strings, concat twice, prefix-compare, discard)
**Expected output:** `checksum=17793810`

| Feature exercised | Notes |
|-------------------|-------|
| Small-string allocation | Every string is a `malloc` + refcount, even 4 bytes |
| `++` on short operands | Three concatenations per iteration |
| `String.starts_with` | Short-prefix compare, consumes the concatenation |
| Allocate-and-free churn | Nothing escapes the loop |

**Comparison baseline:** Rust (`String` — no SSO either), C++ (`std::string` — has SSO), Go, Python (interns short strings).
**What to watch:** The size histogram under `MARCH_STRING_STATS=1` is the SSO evidence. Measured: 24,000,004 allocations, of which **91.7% are ≤23 bytes** (13.2M ≤7, 6.9M ≤15, 1.9M ≤23) — 23 being what fits in the footprint the 24-byte header already occupies. Doubling `pairs()` doubles both allocations (24M → 48M) and wall time (0.80s → 1.58s), confirming allocation is the bottleneck rather than incidental. The C++ comparison is the informative one, since it is the baseline that *has* the optimization under consideration.

---

## bench/run_string_xlang.sh — cross-language `string_small_churn`

**Command:** `bash bench/run_string_xlang.sh`
**Expected output:** every implementation prints `checksum=17793810`

Runs `bench/string_small_churn.march` against four baselines, each chosen to
separate an explanation a single number cannot:

| Baseline | Source | Why it is here |
|---|---|---|
| Rust | `bench/rust/string_small_churn.rs` | `String` has **no** small-string optimization — March's exact representation. Isolates allocator + refcount overhead. |
| C++ | `bench/cpp/string_small_churn.cpp` | `std::string` **has** SSO. Bounds the prize from inline storage. The only C++ in the repo, added deliberately as a one-off for this question. |
| C | `bench/c/string_small_churn.c` | Raw `malloc`, no header, no refcount — the floor. |
| Python | `bench/python/string_small_churn.py` | `pymalloc` is itself a size-class freelist, in a much slower language. |

**What to watch:** the run FAILS if any implementation's checksum differs — that
means they are not doing the same work and the timings are meaningless. A
missing toolchain is reported as SKIPPED rather than silently omitted (Go is not
installed on the primary dev machine). Load average is printed and warned on;
compare the *ratios* within one run, never absolute milliseconds across runs.

Measured 2026-07-27: C++ 246ms, C 411ms, Rust 566ms, March 741ms, Python
1305ms. See `specs/2026-07-26-string-performance-profile.md` for what that says
about the freelist-versus-SSO decision.

---

## bench/string_parallel_scan.march — Shared-buffer scan at 1/2/4/8 workers

**Command:** count `"QQ"` occurrences in a 40MB buffer, chunked across 1, 2, 4, 8 workers
**Expected output:** `checksum=16000000`, plus one `workers=N ms=T` line per worker count

| Feature exercised | Notes |
|-------------------|-------|
| `Parallel.pmap` | Vec-based — chunk indices via `RRB.from_list`, results via `RRB.to_list` |
| Shared-owner refcounting | Every worker slices from the same string; atomic RC on one cache line |
| `String.slice` + `replace_all` | Per-chunk copy, then one full O(n) scan |

**Comparison baseline:** Rust (rayon over `&str` chunks, zero copy), Go (goroutines over slices), C (pthreads over pointer ranges).
**What to watch:** The scaling *shape*, not absolute times. Measured on an M3 Max (10 performance + 4 efficiency cores), stable across three runs: **131ms → 66ms (1.97×) → 34ms (3.9×) → 33ms (3.97×)**. Scaling is near-perfect to 4 workers and then flat — 8 workers buy nothing. That ceiling is *not* explained by core count (8 performance cores were available) nor by memory bandwidth (~80MB of traffic in 33ms ≈ 2.4GB/s, far below this machine's capability), which leaves shared-owner refcount traffic and allocator contention as the candidates. Distinguishing those two is phase 3's first job; the gate in `specs/2026-07-26-string-performance-design.md` is triggered.

**Known limitation, deliberate:** a needle straddling a chunk boundary is missed. Every boundary here falls inside the repeated 10-byte unit, so the count stays deterministic and the benchmark remains valid as a timing comparison. Handling boundaries correctly is precisely the problem phase 3 must solve, and it is not solved here.

**Counting method:** hits are counted as the length delta from `replace_all("QQ", "Q")` — one O(n) scan plus one O(n) build. The natural formulation (`index_of`, slice off the tail, repeat) is O(n²) in bytes copied, since `String.index_of` has no start-offset variant; at this size that is ~800GB of copying.

---

## bench/parallel.march — Parallel tree sum (depth=24, threshold=10)

**Status: REAL PARALLELISM (compiled) / SEQUENTIAL (interpreted)** — compiled
mode runs tasks on the M:N pthread work-stealing scheduler
(`runtime/march_scheduler.c`), so subtrees execute concurrently across cores.
The tree-walking interpreter evaluates each `task_spawn` thunk eagerly and
in-order, so interpreted runs are correct but single-threaded.

**Expected output:** `16777216`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn` / `task_await_unwrap` | Task spawning and join |
| **FBIP + parallelism** | Sibling subtrees have independent RC chains → in-place reuse on both sides with no synchronisation |
| Task granularity | Parallel to depth 10 (1024 tasks), then sequential |
| Scheduler scalability | N pthread workers, Chase-Lev work-stealing deques, one green thread per task (not OCaml Domains) |

**Comparison baseline:** Same sequential sum (measure parallel speedup), C with pthreads, Go goroutines.
**What to watch:** In compiled mode, expect near-linear speedup up to
`min(cores, 1024)` tasks. FBIP correctness in the parallel case: each task's sub-tree has RC=1 in its
own context, so `inc_leaves`-style transforms remain safe without locking.

---

## bench/par_fib.march — Parallel Fibonacci (embarrassingly parallel)

**Status: REAL PARALLELISM (compiled) / SEQUENTIAL (interpreted)** — compiled
mode forks the recursive tasks onto the M:N pthread work-stealing scheduler
(`runtime/march_scheduler.c`); the interpreter runs each `task_spawn` thunk
eagerly and in-order (correct but single-threaded).

**Command:** `par_fib(40, 20)`
**Expected output:** `102334155`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn` / `task_await_unwrap` | Fork/join with many small tasks |
| Task creation throughput | Thousands of tasks spawned recursively |
| No inter-task communication | Pure embarrassingly parallel — each subtask independent |
| Threshold tuning | Sequential below depth 20 to avoid micro-task overhead |

**Comparison baseline:** `bench/fib.march` (sequential), C with pthreads, Go goroutines.
**What to watch:** In compiled mode, parallelism is real — expect near-linear
speedup up to core count over the sequential `fib`. Measured scheduler
throughput (4-core M1): ~189K–209K tasks/sec (250K green threads in 1.32s;
see `specs/progress.md`). A regression vs sequential `fib` points to
task_spawn/task_await_unwrap call overhead or per-task scheduling cost.

---

## bench/par_map.march — Parallel Collatz map (embarrassingly parallel)

**Status: REAL PARALLELISM (compiled) / SEQUENTIAL (interpreted)** — compiled
mode runs the per-chunk tasks concurrently on the M:N pthread work-stealing
scheduler (`runtime/march_scheduler.c`); the interpreter runs each `task_spawn`
thunk eagerly and in-order (correct but single-threaded). The same machinery
backs `List.pmap`/`pfilter`/`preduce`, measured at ~281% CPU on a 200k-element
workload (see `specs/progress.md`).

**Command:** `par_map_sum(range(1, 100000), 1000)`
**Expected output:** `2660024`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn` with closure captures | Each task captures a list chunk |
| Independent task execution | No shared state between tasks |
| Variable-cost work items | Collatz step counts vary widely per element |
| Chunked parallelism | 100 tasks of 1000 elements each |

**Comparison baseline:** Sequential `map` + `fold` over same data, C with OpenMP parallel for.
**What to watch:** Measures the "map-reduce without reduce" pattern. Task overhead
should be small relative to the Collatz computation. A regression points to
closure capture overhead or list allocation under task boundaries.

---

## bench/par_worksteal.march — Work-stealing Fibonacci (Tier 2)

**Status: REAL WORK-STEALING (compiled) / SEQUENTIAL (interpreted)** — in
compiled mode `task_spawn_steal` spawns a real green thread onto the Chase-Lev
work-stealing deques (`lib/tir/llvm_emit.ml`, `runtime/march_scheduler.c`,
`runtime/march_deque.h`); idle pthread workers steal from busy ones. The
interpreter runs the thunk eagerly and in-order (correct but single-threaded).

**Command:** `par_fib(pool, 40, 20)` with `Cap(WorkPool)` from `main()`
**Expected output:** `102334155`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn_steal` | Work-stealing tier (Tier 2) task creation |
| `Cap(WorkPool)` capability | Unforgeable capability threaded from `main()` |
| Capability threading | Pool passed explicitly through function signatures |
| Chase-Lev deque operations | Submit to worker deque, steal from others |

**Comparison baseline:** `bench/par_fib.march` (cooperative tier), C with work-stealing.
**What to watch:** Compare Tier 2 (work-stealing) vs Tier 1 (cooperative) overhead.
In compiled mode the work-stealing scheduler delivers better load balancing for
uneven workloads, since idle workers steal queued tasks from busy ones. The `Cap(WorkPool)` threading should have zero runtime cost
(it's a type-level capability, not a runtime check).

---

## bench/deque_ops.march — Functional deque (push_front/push_back/drain, ×100)

**Command:** 100 rounds of `push_phase(empty(), 10000)` → `drain`
**Expected output:** `20001000000`

| Feature exercised | Notes |
|-------------------|-------|
| `Deque.push_front` / `Deque.push_back` | O(1) worst-case Cons prepend |
| `Deque.pop_front` with rebalance | O(n) amortized; triggers `List.reverse` when front exhausted |
| `Deque.empty` | Zero-allocation initial state |
| RC overhead per push | Every `push_front`/`push_back` allocates one Cons cell |
| Persistent value semantics | Each call returns a new `Deque(Int)` — no mutation |

**Comparison baseline:** OCaml (same two-list algorithm, tracing GC — isolates RC vs GC cost),
Rust `std::collections::VecDeque` (mutable ring buffer — no allocation in steady state),
Elixir `:queue` (OTP two-list functional deque).

**What to watch:** March pays ~2× OCaml due to RC vs GC; gap vs Rust is larger because
VecDeque is mutable and allocation-free in steady state. A regression vs the prior March
run points to RC overhead in the Perceus pass or Cons-cell allocation cost.

---

## bench/merkle.march — Merkle tree build+diff (50 rounds, 1024 leaves, 128 changes)

**Command:** 50 rounds of build two 1024-leaf trees + `Merkle.diff`
**Expected output:** `6400` (50 × 128 differing hashes)

| Feature exercised | Notes |
|-------------------|-------|
| `Crypto.sha256` throughput | Hash every leaf string each build |
| `Merkle.build` | Recursive halving, `Some`/`None` tree allocation |
| `Merkle.diff` / `diff_work` | Work-list tail-recursive diff, skips unchanged subtrees via hash compare |
| String equality dispatch | `root_hash(t1) == root_hash(t2)` on polymorphic TVar return — routes through `march_poly_eq` |
| Reference counting on deep trees | 1024-leaf trees freed each round |

**Comparison baseline:** OCaml with `digestif` SHA-256 (requires `ocamlfind`),
Elixir with `:crypto.hash(:sha256, ...)` OTP builtin.
Rust not included (SHA-256 crate requires `Cargo.toml`).

**What to watch:** If output is `51200` instead of `6400`, the `==` comparison in
`diff_work` is using pointer identity instead of string content equality — this was
a real bug (fixed in `lib/tir/llvm_emit.ml`, TVar equality dispatch now routes to
`march_poly_eq`). A regression in SHA-256 throughput points to `Crypto.sha256`
or the C `mbedtls_sha256` binding.

---

## HTTP benchmark: March vs Rust actix-web 4 vs Python FastAPI

### Run 2: 2026-03-25 (batch pipelined writev — evloop handle_read)

**Date:** 2026-03-25 (second run, after Phase 2 batch-writev optimization)
**Machine:** macOS Darwin 24.6.0 (Apple Silicon, 14 logical CPUs)
**Tool:** wrk 4.2.0 — 4 threads, 256 connections, 15s captured run (primer + warmup passes first)
**March:** event-loop server (kqueue + SO_REUSEPORT, 14 threads) + per-thread arena allocator + batch writev in handle_read (N pipelined requests → 1 writev)
**Rust:** actix-web 4.13.0, `--release` (LTO, opt-level 3), 14 workers
**Python:** FastAPI 0.135.2 + uvicorn 0.42.0, uvloop, 14 worker processes

| Test | March | Rust actix-web 4 | Python FastAPI+uvicorn |
|---|---|---|---|
| **JSON** req/s | **52,628** | 46,865 | 46,830 |
| JSON avg latency | 4.84 ms | 5.44 ms | 5.42 ms |
| JSON p99 latency | 5.86 ms | 6.39 ms | 5.97 ms |
| **Plaintext** req/s | **52,812** | 48,384 | 45,963 |
| Plaintext avg latency | 4.84 ms | 5.27 ms | 5.53 ms |
| Plaintext p99 latency | 5.89 ms | 6.37 ms | 7.25 ms |
| **Plaintext pipelined ×16** req/s | 108,572 | **715,186** | 85,409 |
| Pipelined avg latency | 20.40 ms | **3.06 ms** | 24.36 ms |

### vs. Run 1 (pre-Phase-2)

| Metric | Run 1 | Run 2 | Delta |
|---|---|---|---|
| March JSON req/s | 50,270 | 52,628 | **+4.7%** |
| March plaintext req/s | 52,306 | 52,812 | **+1.0%** |
| March pipelined ×16 req/s | 103,611 | 108,572 | **+4.8%** |
| Actix JSON req/s | 46,623 | 46,865 | ±0% |
| Actix plaintext req/s | 47,186 | 48,384 | ±0% |
| Actix pipelined ×16 req/s | 709,265 | 715,186 | ±0% |
| FastAPI JSON req/s | 46,556 | 46,830 | ±0% |
| FastAPI plaintext req/s | 48,068 | 45,963 | ±0% |
| FastAPI pipelined ×16 req/s | 85,866 | 85,409 | ±0% |

### Analysis

**Non-pipelined (JSON/plaintext):** March leads all three frameworks by 8–12%. The event-loop + arena allocator combination eliminates per-request malloc overhead that actix's tokio runtime still pays, and FastAPI's ASGI dispatch adds Python overhead even with uvloop.

**Pipelined ×16 (Phase 2 batch writev):** The handle_read rewrite now batches all N pipelined requests into a single writev() call. This yields +4.8% (103K → 108K req/s), reducing syscall overhead on pipelined connections. The large gap vs actix (715K) persists — actix's tokio `h1` codec is zero-copy through the entire pipeline including the I/O layer, while March still materializes a full `march_response_t` per request. Further gains would require moving to a zero-copy path through the March runtime layer.

**FastAPI multi-worker:** 14 workers with uvloop, on par with March and actix on non-pipelined tests.

### Run 1: 2026-03-25 (initial baseline)

**Date:** 2026-03-25 (first run)

| Test | March | Rust actix-web 4 | Python FastAPI+uvicorn |
|---|---|---|---|
| **JSON** req/s | **50,270** | 46,623 | 46,556 |
| JSON avg latency | 5.08 ms | 5.46 ms | 5.49 ms |
| JSON p99 latency | 5.94 ms | 6.39 ms | 7.38 ms |
| **Plaintext** req/s | **52,306** | 47,186 | 48,068 |
| Plaintext avg latency | 4.87 ms | 5.40 ms | 5.31 ms |
| Plaintext p99 latency | 5.90 ms | 6.34 ms | 5.78 ms |
| **Plaintext pipelined ×16** req/s | 103,611 | **709,265** | 85,866 |
| Pipelined avg latency | 21.31 ms | **3.16 ms** | 24.37 ms |

### How to re-run

```bash
# From repo root
bash bench/tfb/run_comparison.sh
```

Servers: `bench/tfb/tfb_server` (March, compiled), `bench/tfb/rust_actix/target/release/rust_actix` (Rust), `bench/tfb/fastapi_server.py` (Python).
Pipeline script: `bench/tfb/pipeline.lua`.

---

## bench/hash_map_bench.march — HashMap + Enum.uniq/frequencies (O(n) proof)

**Command:** compile with `--opt 2`, run directly (includes internal timing via
`System.monotonic_time()`).

```bash
march --compile --opt 2 bench/hash_map_bench.march -o bench/hash_map_bench
bench/hash_map_bench
```

Three workloads at three scales (10 k / 50 k / 100 k elements):

| Workload | What it exercises | Checksum |
|----------|-------------------|---------|
| HashMap raw put/get | HAMT insert + lookup over unique Int keys | sum of values |
| Enum.uniq | dedup 50%-duplicate list via HashMap membership | unique count |
| Enum.frequencies | count 10-repeat list via HashMap + order list | total count |

**Baseline results (2026-06-24, Apple M-class, --opt 2):**

```
=== HashMap raw put/get ===
  n=10000  27ms  (check=149985000)
  n=50000 161ms  (check=3749925000)
  n=100000 367ms  (check=14999850000)
=== Enum.uniq ===
  n=10000  13ms  (check=5000)
  n=50000  84ms  (check=25000)
  n=100000 193ms  (check=50000)
=== Enum.frequencies ===
  n=10000  23ms  (check=10000)
  n=50000 150ms  (check=50000)
  n=100000 323ms  (check=100000)
```

Times grow ~linearly (10× elements ≈ 14× time), consistent with O(n·log₃₂ n)
HAMT operations (effectively O(n) at these scales).  The previous O(n²)
`Enum.frequencies` at n=100k would do ~2.5 billion list-scan steps; this does
100k HashMap lookups.

**What to watch:** a regression here suggests a change to HashMap's HAMT core,
the `hash` builtin dispatch, or Perceus RC paths for `HEntry` nodes.

---

## bench/rrb_bench.march — RRB.Vec + Parallel bulk operations (n=1M)

**Command:** compile with `--opt 2`, run directly.

```bash
march --compile --opt 2 bench/rrb_bench.march -o bench/rrb_bench
bench/rrb_bench
```

Four workloads over n=1,000,000 integers:

| Workload | What it exercises | Expected result |
|----------|-------------------|-----------------|
| `RRB.fold_left` (sequential) | List-backed Vec traversal | `500000500000` |
| `Parallel.psum` | `task_spawn`/`task_await_unwrap` integer reduce | `500000500000` |
| `Parallel.preduce` (square+sum) | Parallel map-reduce pass | `333333833333500000` |
| `Parallel.pmap` (n=1000) | Vec-building tasks, small n to avoid O(n²) list-push | `333833500` |

**Baseline results (2026-06-24, Apple M-class, no --opt):**

```
seq_sum=500000500000  seq_fold_left: 8ms
par_sum=500000500000  psum: 86ms
par_reduce_sum=333333833333500000  preduce: 87ms
par_map_sum=333833500  pmap+fold (n=1000): 5ms
```

**Note on `pmap` scale:** `RRB.Vec` is list-backed in v1, so `push` is O(n).
Building a Vec of k elements is O(k²); at n=1M per task this would take
minutes. The benchmark uses n=1000 for pmap and verifies correctness of the
task return path only.

**What to watch:** `psum` and `preduce` correctness depend on `task_await_unwrap`
correctly double-untagging i64 task results (`lib/tir/llvm_emit.ml`). If results
are `2×correct+N` the i64 double-untagging is broken. A `psum` that is slower
than `seq_fold_left` by more than 3× (on a multi-core machine) suggests the
parallel scheduler is degraded.

---

## Running benchmarks to validate changes

See also the note in `CLAUDE.md`: run the relevant benchmark after any change
to the features it exercises. Quick reference:

| Changed area | Run this benchmark |
|---|---|
| `lib/tir/perceus.ml` (any) | `tree_transform` + `binary_trees` |
| FBIP / `try_fbip_sink` / `shape_matches` | `tree_transform` |
| ECase / scrutinee dec_rc | `binary_trees` |
| Closure / lambda eval | `list_ops` |
| Tail-call optimisation | `list_ops` + `fib` |
| Codegen / `--opt` levels | all four |
| `string_join` / `string_to_int` / `int_to_string` | `string_build` + `string_pipeline` |
| Task / `task_spawn` / `task_await` | `parallel` + `par_fib` + `par_map` |
| Work-stealing / `task_spawn_steal` / Chase-Lev | `par_worksteal` |
| `Cap(WorkPool)` capability | `par_worksteal` |
| `Deque.*` / Cons allocation / RC amortised | `deque_ops` |
| `Merkle.*` / `Crypto.sha256` / TVar equality | `merkle` |
| `llvm_emit` equality dispatch (TVar / `march_poly_eq`) | `merkle` |
| `HashMap.*` / `Enum.uniq` / `Enum.frequencies` | `hash_map_bench` |
| `RRB.*` / `Parallel.*` / `task_await_unwrap` i64 | `rrb_bench` |
