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

## bench/parallel.march — Parallel tree sum (depth=24, threshold=10)

**Status: PHASE 1 (eager)** — task builtins exist but execute eagerly in the
single-threaded interpreter. True parallelism requires OCaml 5 Domains (Phase 2).

**Expected output:** `16777216`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn` / `task_await_unwrap` | Task spawning and join |
| **FBIP + parallelism** | Sibling subtrees have independent RC chains → in-place reuse on both sides with no synchronisation |
| Task granularity | Parallel to depth 10 (1024 tasks), then sequential |
| OCaml 5 Domain scalability | One Domain per task up to GOMAXPROCS equivalent |

**Comparison baseline:** Same sequential sum (measure parallel speedup), C with pthreads, Go goroutines.
**What to watch:** Should show near-linear speedup up to `min(cores, 1024)` tasks.
FBIP correctness in the parallel case: each task's sub-tree has RC=1 in its
own context, so `inc_leaves`-style transforms remain safe without locking.

---

## bench/par_fib.march — Parallel Fibonacci (embarrassingly parallel)

**Status: PHASE 1 (eager)** — task builtins exist but execute eagerly.

**Command:** `par_fib(40, 20)`
**Expected output:** `102334155`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn` / `task_await_unwrap` | Fork/join with many small tasks |
| Task creation throughput | Thousands of tasks spawned recursively |
| No inter-task communication | Pure embarrassingly parallel — each subtask independent |
| Threshold tuning | Sequential below depth 20 to avoid micro-task overhead |

**Comparison baseline:** `bench/fib.march` (sequential), C with pthreads, Go goroutines.
**What to watch:** Phase 1 (eager) overhead should be <5% vs sequential `fib`.
With true parallelism, expect near-linear speedup. A regression vs sequential
`fib` points to task_spawn/task_await_unwrap call overhead.

---

## bench/par_map.march — Parallel Collatz map (embarrassingly parallel)

**Status: PHASE 1 (eager)** — task builtins exist but execute eagerly.

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

**Status: PHASE 1 (eager)** — `task_spawn_steal` exists but delegates to eager
evaluation. True work-stealing requires OCaml 5 Domains (Phase 2).

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
With true parallelism, work-stealing should show better load balancing for
uneven workloads. The `Cap(WorkPool)` threading should have zero runtime cost
(it's a type-level capability, not a runtime check).

---

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
