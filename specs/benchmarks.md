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

## bench/parallel.march — Parallel tree sum (depth=24, threshold=10)

**Status: NOT YET RUNNABLE** — requires `spawn_task` / `await_all` / `Task(a)`,
which are designed but not implemented.

**Expected output:** `16777216`

| Feature exercised | Notes |
|-------------------|-------|
| `spawn_task` / `await_all` | Task spawning and join |
| **FBIP + parallelism** | Sibling subtrees have independent RC chains → in-place reuse on both sides with no synchronisation |
| Task granularity | Parallel to depth 10 (1024 tasks), then sequential |
| OCaml 5 Domain scalability | One Domain per task up to GOMAXPROCS equivalent |

**Comparison baseline:** Same sequential sum (measure parallel speedup), C with pthreads, Go goroutines.
**What to watch:** Should show near-linear speedup up to `min(cores, 1024)` tasks.
FBIP correctness in the parallel case: each task's sub-tree has RC=1 in its
own context, so `inc_leaves`-style transforms remain safe without locking.

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
| Task / spawn_task | `parallel` (once implemented) |
