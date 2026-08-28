---
layout: docs
title: Parallel Collections
nav_order: 9.5
permalink: /docs/parallel-collections/
---

# Parallel Collections

March can run a transformation over a list across multiple CPU cores with a one-character change: `map` → `pmap`. The parallel operations live in the `List` module, produce **exactly** the same results (same values, same order) as their sequential counterparts, and ride the same green-thread scheduler that powers [actors and tasks]({{ site.baseurl }}/docs/actors/).

```march
let squares  = List.map(xs, fn x -> x * x)    -- sequential
let squares2 = List.pmap(xs, fn x -> x * x)   -- parallel, identical result
```

This guide covers the four parallel functions, **how they work under the hood**, the `--pmap-threshold` flag, **when to reach for them explicitly**, and the editor-driven detection that suggests them for you.

---

## The functions

All of these are order-preserving: element *n* of the output corresponds to element *n* of the input, regardless of which core finished first.

### `List.pmap(xs, f)`

Parallel map. Drop-in replacement for `List.map` when `f` is safe to run concurrently.

```march
List.pmap([1, 2, 3], fn x -> x * 2)        -- [2, 4, 6]
List.pmap(rows, fn r -> render_row(r))     -- each row rendered on a worker
```

### `List.pmap_n(xs, f, max_concurrency)`

Like `pmap`, but caps the number of tasks running at once. Use it when each element is **expensive** (a network call, a heavy computation) and you want to bound how many run simultaneously (rate-limiting, connection pools, memory pressure).

```march
-- Fetch up to 8 URLs at a time, no matter how long the list is
List.pmap_n(urls, fn u -> http_get(u), 8)
```

### `List.pfilter(xs, pred)`

Parallel filter. Same semantics as `List.filter`, kept in input order.

```march
List.pfilter(candidates, fn c -> passes_expensive_check(c))
```

### `List.preduce(xs, identity, combine)`

Parallel reduction (a *tree reduce*). Each chunk is reduced independently, then the partial results are combined.

```march
List.preduce([1, 2, 3, 4], 0, fn (a, b) -> a + b)   -- 10
List.preduce(words, "", fn (a, b) -> a ++ b)        -- concatenation
```

> **Contract:** `combine` **must be associative** (`combine(combine(x, y), z)` must equal `combine(x, combine(y, z))`) and `identity` must be its unit. Sum, product, max, min, string/list concatenation, and set union all qualify. Subtraction, division, and average **do not** (you'd get a different answer depending on how the work was split). The compiler cannot verify associativity, so this is your responsibility.

---

## How it works under the hood

### Chunking, not element-per-task

A naïve parallel map would spawn one task per element: a million elements would mean a million tasks, and the scheduling overhead would dwarf the actual work. Instead, `pmap` **splits the list into chunks**, spawns one task per chunk, runs each chunk's elements sequentially inside its task, awaits the tasks in order, and concatenates the results:

```
xs = [................................................]   (say 4000 elements)
       │           │           │           │
     chunk 0     chunk 1     chunk 2     chunk 3          (threshold-sized chunks)
       │           │           │           │
     task        task        task        task            (one green thread each)
       └───────────┴─────┬─────┴───────────┘
                    concat in order
```

Because the number of tasks tracks the chunk count (not the element count), the overhead stays proportional to the number of cores, not the size of the data.

### The scheduler

In **compiled** code, tasks run on March's M:N green-thread scheduler: several OS threads (4 by default), each running many lightweight green threads, with work-stealing to keep cores busy. This is the same runtime described in [Actors]({{ site.baseurl }}/docs/actors/). Reference counting is atomic and each actor/task owns a private arena heap, so there is **no stop-the-world GC pause**; parallel work scales cleanly.

### Why parallel FBIP needs no locks

The reason `preduce` over a tree (or any divide-and-conquer over a uniquely-owned structure) scales without a single mutex comes down to **ownership**. March's [memory model]({{ site.baseurl }}/docs/memory-model/) tracks each value's reference count; a structure with `RC == 1` at the root is *uniquely owned*. When you split a uniquely-owned tree at its root, the left and right subtrees are themselves uniquely owned and **disjoint**: no node is reachable from both parts.

That disjointness is the whole game. Hand each subtree to a different task and the two tasks rewrite their nodes **in place** (functional-but-in-place, FBIP) on separate cores. Because no node is shared, there is no data to race over: no lock, no atomic fence on the data, no cache-line ping-pong. The only synchronization is the join at the end, when the parent task collects two already-finished results and combines them. Reference counting is needed only where sharing is *possible*; unique ownership proves it isn't, so the fast path is lock-free by construction.

This is exactly what the **depth-24 parallel tree-sum benchmark** exercises: a ~16-million-node tree is split top-down, each task sums its disjoint subtree in place, and partial sums combine on the way up. The speedup tracks core count almost linearly exactly because there is zero contention between tasks: the structure's own shape guarantees they never touch the same memory.

### Interpreter vs. compiled

| | Result correctness | Real CPU parallelism |
|---|---|---|
| **Interpreter** (`march run`, REPL) | ✅ identical to sequential | ❌ tasks run eagerly on one thread |
| **Compiled** (`march --compile`, `forge build`) | ✅ identical to sequential | ✅ runs across cores |

The interpreter executes spawned tasks eagerly, so `pmap` there is *correct but sequential*. You get the speedup when you compile. This means you can develop and test against the interpreter and trust that the compiled binary produces the same answers.

---

## The threshold and the `--pmap-threshold` flag

Parallelism isn't free: spawning and joining tasks costs something. For a short list, sequential `map` is the clear winner. So `pmap`, `pfilter`, and `preduce` consult a **cutoff** before deciding what to do.

### What actually happens when you call `pmap`

`pmap` isn't a special compiler intrinsic; it's ordinary March code in the stdlib,
built on the exact same [`task_spawn`/`task_await_unwrap`]({{ site.baseurl }}/docs/actors/)
primitives you could call yourself. Stripped down, `List.pmap(xs, f)` does this:

```march
fn pmap(xs : List(a), f : a -> b) : List(b) do
  let t = pmap_threshold()
  if length(xs) <= t do
    map(xs, f)                                              -- below cutoff: plain sequential map
  else do
    let cs    = chunks(xs, t)                                -- split into t-sized chunks
    let tasks = map(cs, fn c -> task_spawn(fn _ -> map(c, f)))  -- one task per chunk
    concat(map(tasks, fn tk -> task_await_unwrap(tk)))       -- await in order, join results
  end
end
```

(`pfilter` and `preduce` follow the identical shape, swapping `map` for `filter` /
`fold_left`.) Walking through it:

1. **The check is a single length comparison, done fresh on every call.** `length(xs)`
   is a runtime value (the compiler has no way to know it ahead of time), so this
   comparison against the threshold has to happen live, each time `pmap` runs. It's O(1)
   next to the O(n) work being parallelized, so its cost is negligible.
2. **Below the cutoff, it's *literally* `map`.** No task, no scheduler involvement, no
   overhead beyond the one comparison you just paid for.
3. **At or above it, the chunk size *is* the threshold.** `chunks(xs, t)` splits the
   list into pieces of `t` elements each; this is why the earlier diagram shows a
   4000-element list splitting into 4 chunks at the default threshold of 1024
   (`⌈4000 / 1024⌉ = 4`). Each chunk becomes one `task_spawn`, so the number of tasks
   tracks `length(xs) / t`, not `length(xs)`.
4. **The tasks are awaited in order, which is what keeps the result order-preserving.**
   `task_await_unwrap` runs on chunk 0's task, then chunk 1's, and so on. But all the
   tasks were already spawned before any awaiting starts, so this doesn't serialize the
   *work*, only the order results are collected in.
5. **What "spawn" means depends on the backend**, exactly as in [The
   scheduler](#the-scheduler) above. Compiled, `task_spawn` starts a real green thread
   that the M:N scheduler can run on any OS thread. Interpreted, `task_spawn` evaluates
   its function **immediately, synchronously, right there**, so even the "parallel"
   branch above the threshold runs chunk 0 to completion, then chunk 1, then chunk 2, in
   plain left-to-right order, on one thread. That's *why* the interpreter is guaranteed
   to produce the same result as the sequential version: it isn't a special case, just
   the same code evaluated by a backend that has no concurrency to offer. And it's *why*
   the interpreter never gets faster no matter how large the list is.

### The threshold value itself

The cutoff is returned by the builtin `pmap_threshold()` and defaults to **1024
elements**. You can change it:

```bash
march --compile --pmap-threshold=256 -o app app.march
# via forge:
MARCH_PMAP_THRESHOLD=256 forge build
```

For a **compiled** binary, the value is baked in as a compile-time constant when you
build: there's no way to change it later without recompiling, and no per-call runtime
configuration to read. The same `--pmap-threshold` flag also works when running
**interpreted** (`march --pmap-threshold=256 app.march`, no `--compile`); there, it
just sets the value `pmap_threshold()` returns for that one run, which is occasionally
useful for testing how your code behaves at a different cutoff without a full compile,
even though it won't affect wall-clock time either way in the interpreter.

### Why a runtime cutoff instead of the type system?

A natural question: can't the compiler decide statically whether a list is "big enough"? In practice, no, and not because the type system is too weak:

1. **List length is almost always a runtime property.** The lists worth parallelizing come from files, sockets, databases, user input. Their size simply isn't known at compile time.
2. **Profitability is `length × cost-per-element`, not length by itself.** Eight elements that each make a 200&nbsp;ms HTTP call are very worth parallelizing; a million elements that each do `x + 1` are not. The type system can't see how expensive a closure body is.

So March chooses at runtime, on the actual data, with a single cheap length check, the same approach used by Rust's Rayon, Java parallel streams, and .NET PLINQ. The default of 1024 is a safe floor for cheap per-element work; `pmap_n` is the precise override when per-element cost is what matters.

---

## When to use them explicitly

| Situation | Reach for | Why |
|---|---|---|
| Large list, cheap-to-moderate pure work per element | `List.pmap` / `List.pfilter` | The threshold handles the "is it worth it?" decision for you |
| Few elements, **expensive** work each (HTTP, heavy compute) | `List.pmap_n` | Bound concurrency explicitly; the size heuristic doesn't apply |
| Aggregating a large list with an **associative** combiner | `List.preduce` | Tree reduction parallelizes sum/max/concat/union |
| Small list, or trivial per-element work | plain `List.map` / `fold_left` | Spawning overhead would make parallel *slower* |
| The function does I/O ordering, mutation, or must run in sequence | plain `List.map` | Parallel execution would change observable behavior |

Rules of thumb:

- **Prefer the sequential version by default.** Reach for the parallel one when you have evidence (a large dataset, a profiler, a slow loop) that it'll pay off.
- **The function must be safe to run concurrently.** Pure functions (ones that only compute from their arguments) always are. A function that prints, sends actor messages, writes a file, or depends on shared mutable state is *not*, and the runtime won't stop you from misusing it. For those, keep the sequential version (or restructure so the parallel part is pure).
- **Measure in a compiled build.** The interpreter won't show a speedup (see above).

---

## Automatic detection: the "magic," explained

March will tell you when a `map` or `filter` is a parallelization candidate. Open a file in an editor with the [March language server]({{ site.baseurl }}/docs/lsp/) and a pure `List.map` / `List.filter` gets a **Hint**:

> *This `List.map` over a pure function could be `List.pmap` to run in parallel.*

…together with a one-click **"Convert to `List.pmap`"** quick-fix that rewrites just the call.

Here's what is (and isn't) happening, so the behavior never feels mysterious:

- **It's detection, not silent rewriting.** The compiler does **not** secretly turn your `map` into a `pmap` behind your back. Your code runs exactly as written; the suggestion is advisory, and you opt in by accepting the fix. Performance stays predictable and your stack traces stay truthful.
- **It only fires when it's proved safe.** The analysis checks that the mapped function is **pure** (no I/O, no message sends, no mutation), reusing the same purity oracle the optimizer uses internally. If it can't prove purity, it stays quiet. False positives (suggesting an unsafe parallelization) are designed out; the cost is the occasional false negative (staying silent on something that *was* safe).
- **`fold` / `reduce` are never suggested.** Purity is enough to parallelize a `map`, but a parallel *reduce* also needs an **associative** combiner, and associativity isn't something the compiler can check. So the detector never nudges you toward `preduce`; that one is always an intentional, you-vouched-for-the-contract choice.

### Why advisory instead of fully automatic?

Whether to parallelize is a judgment call that depends on data size and per-element cost, exactly the things a static analysis can't know (see the threshold discussion above). Silently rewriting every pure `map` into a `pmap` would make small-list code *slower* and scatter task-scheduling through programs that never wanted it. Surfacing the opportunity and letting you decide keeps the speedups where they matter and the behavior easy to reason about.

> **Roadmap:** a fully-automatic, opt-in rewrite mode (a `--auto-parallel` compiler flag, off by default) has been designed to reuse the same purity analysis and runtime threshold. It is **not yet available**: today, parallelization is always either explicit (you call `pmap`) or accepted from a suggestion (you click the quick-fix).

---

## Correctness guarantees, in one place

- `pmap`, `pmap_n`, and `pfilter` return results **identical** to `map` / `filter` (same elements, same order) for any function safe to run concurrently.
- `preduce` returns a result identical to `fold_left` **iff** `combine` is associative with `identity` as its unit.
- Compiled and interpreted runs produce the **same output**; only wall-clock time differs.
- Below `pmap_threshold()`, every parallel function is exactly its sequential equivalent.

This determinism guarantee is automatically verified for `List.pmap` and the RRB
`Parallel.psum`/`pcount`/`pany`/`pall`/`preduce` family, with identical results interpreted and
compiled. One documented exception: **`psum_float` is not backend-portable**:
IEEE-754 `+.` is not associative, and the two backends pick different worker/chunk
counts, so results can differ in the last bit. Prefer `psum`/integer accumulation, or
pin `psum_float` inputs that are exact in binary, when portability matters.

---

## Bulk parallel work: RRB.Vec and Parallel

For **large datasets where you want full map-reduce control**, use the `RRB` and `Parallel` modules
instead of `List.pmap`.

| Feature | `List.pmap` | `Parallel.pmap` |
|---------|-------------|-----------------|
| Input type | `List` | `RRB.Vec` |
| Custom worker count | `pmap_n(xs, f, n)` | `pmap_n(v, f, n)` |
| Reduce with identity | `preduce` | `Parallel.preduce` |
| Built-in psum / pcount | No | Yes |
| Zero-copy slices | No | Yes (`RRB.slice`) |

### Quick example

```march
let nums  = RRB.range(1, 1000001)
let total = Parallel.psum(nums)                        -- 500_000_500_000
let evens = Parallel.pcount(nums, fn n -> n % 2 == 0) -- 500_000
let sq    = Parallel.pmap(nums, fn n -> n * n)         -- Vec of squares
```

See the [Parallel Data cookbook]({{ site.baseurl }}/docs/cookbook/parallel-data/) for full
examples including word frequency, image processing, and statistics.

---

## See also

- [Actors]({{ site.baseurl }}/docs/actors/): the scheduler, `Task.async` / `Task.await`, and message-passing concurrency these functions build on.
- [Parallel Data cookbook]({{ site.baseurl }}/docs/cookbook/parallel-data/): `RRB.Vec` and `Parallel` with copy-and-run examples.
- [Standard Library → List]({{ site.baseurl }}/docs/stdlib/List.html): the full `List` API reference.
- [LSP & Editors]({{ site.baseurl }}/docs/lsp/): set up the language server to get the parallelization hints and quick-fix.
