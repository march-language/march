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

Like `pmap`, but caps the number of tasks running at once. Use it when each element is **expensive** — a network call, a heavy computation — and you want to bound how many run simultaneously (rate-limiting, connection pools, memory pressure).

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

> **Contract:** `combine` **must be associative** — `combine(combine(x, y), z)` must equal `combine(x, combine(y, z))` — and `identity` must be its unit. Sum, product, max, min, string/list concatenation, and set union all qualify. Subtraction, division, and average **do not** (you'd get a different answer depending on how the work was split). The compiler cannot verify associativity, so this is your responsibility.

---

## How it works under the hood

### Chunking, not element-per-task

A naïve parallel map would spawn one task per element — a million elements would mean a million tasks, and the scheduling overhead would dwarf the actual work. Instead, `pmap` **splits the list into chunks**, spawns one task per chunk, runs each chunk's elements sequentially inside its task, awaits the tasks in order, and concatenates the results:

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

In **compiled** code, tasks run on March's M:N green-thread scheduler: several OS threads (4 by default), each running many lightweight green threads, with work-stealing to keep cores busy. This is the same runtime described in [Actors]({{ site.baseurl }}/docs/actors/). Reference counting is atomic and each actor/task owns a private arena heap, so there is **no stop-the-world GC pause** — parallel work scales cleanly.

### Interpreter vs. compiled

| | Result correctness | Real CPU parallelism |
|---|---|---|
| **Interpreter** (`march run`, REPL) | ✅ identical to sequential | ❌ tasks run eagerly on one thread |
| **Compiled** (`march --compile`, `forge build`) | ✅ identical to sequential | ✅ runs across cores |

The interpreter executes spawned tasks eagerly, so `pmap` there is *correct but sequential*. You get the speedup when you compile. This means you can develop and test against the interpreter and trust that the compiled binary produces the same answers.

---

## The threshold and the `--pmap-threshold` flag

Parallelism isn't free: spawning and joining tasks costs something. For a short list, sequential `map` wins outright. So `pmap`, `pfilter`, and `preduce` consult a **cutoff** before deciding:

- **Below the cutoff** → they delegate to the plain sequential version. No tasks, no overhead.
- **At or above the cutoff** → they chunk and parallelize as described above.

The cutoff is returned by the builtin `pmap_threshold()` and defaults to **1024 elements**. You can change it at compile time:

```bash
march --compile --pmap-threshold=256 -o app app.march
# via forge:
MARCH_PMAP_THRESHOLD=256 forge build
```

The value is baked into the binary as a compile-time constant — there's no per-call runtime configuration to read.

### Why a runtime cutoff instead of the type system?

A natural question: can't the compiler decide statically whether a list is "big enough"? In practice, no — and not because the type system is too weak:

1. **List length is almost always a runtime property.** The lists worth parallelizing come from files, sockets, databases, user input. Their size simply isn't known at compile time.
2. **Profitability is `length × cost-per-element`, not length alone.** Eight elements that each make a 200&nbsp;ms HTTP call are very worth parallelizing; a million elements that each do `x + 1` are not. The type system can't see how expensive a closure body is.

So March decides at runtime, on the actual data, with a single cheap length check — the same approach used by Rust's Rayon, Java parallel streams, and .NET PLINQ. The default of 1024 is a safe floor for cheap per-element work; `pmap_n` is the precise override when per-element cost is what matters.

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
- **The function must be safe to run concurrently.** Pure functions — ones that only compute from their arguments — always are. A function that prints, sends actor messages, writes a file, or depends on shared mutable state is *not*, and the runtime won't stop you from misusing it. For those, keep the sequential version (or restructure so the parallel part is pure).
- **Measure in a compiled build.** The interpreter won't show a speedup (see above).

---

## Automatic detection — the "magic," explained

March will tell you when a `map` or `filter` is a parallelization candidate. Open a file in an editor with the [March language server]({{ site.baseurl }}/docs/lsp/) and a pure `List.map` / `List.filter` gets a **Hint**:

> *This `List.map` over a pure function could be `List.pmap` to run in parallel.*

…together with a one-click **"Convert to `List.pmap`"** quick-fix that rewrites just the call.

Here's what is — and isn't — happening, so the behavior never feels mysterious:

- **It's detection, not silent rewriting.** The compiler does **not** secretly turn your `map` into a `pmap` behind your back. Your code runs exactly as written; the suggestion is advisory, and you opt in by accepting the fix. Performance stays predictable and your stack traces stay honest.
- **It only fires when it's provably safe.** The analysis checks that the mapped function is **pure** — no I/O, no message sends, no mutation — reusing the same purity oracle the optimizer uses internally. If it can't prove purity, it stays quiet. False positives (suggesting an unsafe parallelization) are designed out; the cost is the occasional false negative (staying silent on something that *was* safe).
- **`fold` / `reduce` are never suggested.** Purity is enough to parallelize a `map`, but a parallel *reduce* also needs an **associative** combiner — and associativity isn't something the compiler can check. So the detector never nudges you toward `preduce`; that one is always a deliberate, you-asserted-the-contract choice.

### Why advisory instead of fully automatic?

Whether to parallelize is a judgment call that depends on data size and per-element cost — exactly the things a static analysis can't know (see the threshold discussion above). Silently rewriting every pure `map` into a `pmap` would make small-list code *slower* and scatter task-scheduling through programs that never wanted it. Surfacing the opportunity and letting you decide keeps the speedups where they matter and the behavior easy to reason about.

> **Roadmap:** a fully-automatic, opt-in rewrite mode (a `--auto-parallel` compiler flag, off by default) has been designed to reuse the same purity analysis and runtime threshold. It is **not yet available** — today, parallelization is always either explicit (you call `pmap`) or accepted from a suggestion (you click the quick-fix).

---

## Correctness guarantees, in one place

- `pmap`, `pmap_n`, and `pfilter` return results **identical** to `map` / `filter` — same elements, same order — for any function safe to run concurrently.
- `preduce` returns a result identical to `fold_left` **iff** `combine` is associative with `identity` as its unit.
- Compiled and interpreted runs produce the **same output**; only wall-clock time differs.
- Below `pmap_threshold()`, every parallel function is exactly its sequential equivalent.

---

## See also

- [Actors]({{ site.baseurl }}/docs/actors/) — the scheduler, `Task.async` / `Task.await`, and message-passing concurrency these functions build on.
- [Standard Library → List]({{ site.baseurl }}/docs/stdlib/List.html) — the full `List` API reference.
- [LSP & Editors]({{ site.baseurl }}/docs/lsp/) — set up the language server to get the parallelization hints and quick-fix.
