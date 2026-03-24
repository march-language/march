# Flow — Backpressure Pipeline Abstraction

`Flow` provides a composable, demand-driven pipeline abstraction for data
processing.  Pipelines are built from **producers** (sources of data),
**transformers** (map, filter, batch, …), and **consumers** (collect, reduce,
each, …).

---

## 1. What is Flow and when should you use it?

A **backpressure pipeline** is one where consumers control the rate of
production.  Rather than a fast producer flooding a slow consumer with data,
the consumer pulls items as it is ready to handle them.

Use Flow when:

- You are processing a stream of items that don't all fit in memory at once
  (log lines, database rows, HTTP response bodies, sensor readings).
- You want to parallelise independent work across a pipeline (fan-out
  processing with `with_concurrency`).
- You need clean composition: build a reusable pipeline stage and plug it
  into different sources or sinks.
- You are coming from Elixir/GenStage and want the same mental model.

Don't use Flow for:
- One-off in-memory transformations of small lists — use `List.*` or `Enum.*`.
- Stateful, interactive workflows where actors communicate bidirectionally —
  use the `Actor` module directly.

---

## 2. Core concepts

### Stages

A `Stage(a)` represents a lazy sequence of items of type `a`.  In the current
interpreter implementation it wraps a `Seq(a)` (a church-encoded fold
function).  In the compiled runtime each stage will be backed by an actor.

```
producer ──► transformer ──► transformer ──► consumer
                                 ▲
                          demand flows ◄─────────────
```

### Producers

Producers generate items.  They emit only as many items as the downstream
stage has demanded — no items are computed until consumed.

```march
-- From a list (all items pre-computed)
Flow.from_list([1, 2, 3, 4, 5])

-- From an integer range (items generated lazily)
Flow.range(0, 1000000)

-- From a generator (stateful)
Flow.unfold(0, fn i ->
  if i >= 10 then None
  else Some((i * i, i + 1)))
-- produces 0, 1, 4, 9, 16, 25, 36, 49, 64, 81
```

### Transformers

Transformers are lazy: they produce output only when a downstream stage pulls
items.  They can be chained with the pipe operator.

```march
Flow.from_list(words)
  |> Flow.map(fn w -> String.to_lowercase(w))
  |> Flow.filter(fn w -> String.byte_size(w) > 3)
  |> Flow.take(100)
```

### Consumers

Consumers are the **only eager** operations.  They trigger actual evaluation of
the pipeline.

```march
-- Collect all items into a list
|> Flow.collect

-- Run for side effects only
|> Flow.run

-- Fold to a single value
|> Flow.reduce(0, fn(acc, n) -> acc + n)

-- Consume with a custom accumulator (alias for reduce)
|> Flow.into(Map.empty(), fn(m, (k, v)) -> Map.put(m, k, v))
```

### Demand and backpressure

In the interpreter, `Stage(a)` is a lazy `Seq(a)`.  The "demand" is implicit:
the consumer's fold function simply stops calling the producer's fold when it
has enough items (via `Seq.take` / `Seq.fold_while`).

In the compiled runtime, each `Stage` will be an actor.  The consumer sends
`Demand(n)` messages upstream; each stage buffers at most `n` items before
sending them downstream.  This is exactly the GenStage model.

---

## 3. Simple example: transform a list

```march
fn main() do
  let result =
    Flow.from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
      |> Flow.filter(fn x -> x % 2 == 0)    -- keep evens: 2,4,6,8,10
      |> Flow.map(fn x -> x * x)             -- square: 4,16,36,64,100
      |> Flow.collect

  println("${result}")  -- [4, 16, 36, 64, 100]
end
```

---

## 4. File processing example: reading and transforming lines

```march
fn count_words_in_file(path) do
  match File.with_lines(path, fn lines ->
    -- lines is a Seq(String); wrap it as a Flow Stage
    Flow.from_seq(lines)
      |> Flow.flat_map(fn line -> String.split(line, " "))
      |> Flow.filter(fn w -> not String.is_empty(w))
      |> Flow.count
  ) do
  | Ok(n) -> n
  | Err(e) -> panic("read failed: ${e}")
  end
end
```

---

## 5. Parallel example: fan-out with with_concurrency

```march
fn fetch_all(urls) do
  -- In the interpreter, with_concurrency is a no-op.
  -- In the compiled runtime, this spawns 8 worker actors.
  Flow.from_list(urls)
    |> Flow.map(fn url -> Http.get(url))
    |> Flow.with_concurrency(8)
    |> Flow.collect
end
```

`with_concurrency(stage, n)` is a hint to the runtime scheduler.  It does not
change the observable semantics (ordering, correctness) of the pipeline; it
only affects parallelism.  The compiled runtime will:

1. Spawn `n` actor workers for this stage.
2. Round-robin demand across workers.
3. Merge outputs in arrival order (not input order — outputs may be reordered).

If you need ordered output, add `Flow.reduce` with an index rather than
`Flow.collect`.

---

## 6. Error handling in pipelines

Flow stages propagate errors via standard `Result` values.  The pipeline
itself does not short-circuit on errors; you handle them in the consumer.

```march
-- Each item is Ok(value) or Err(msg)
Flow.from_list(filenames)
  |> Flow.map(fn name -> File.read(name))          -- List(Result(String, FileError))
  |> Flow.filter(fn r -> Result.is_ok(r))          -- discard errors
  |> Flow.map(fn r -> Result.unwrap(r))            -- unwrap to String
  |> Flow.flat_map(fn content -> String.split(content, "\n"))
  |> Flow.collect
```

Or collect errors separately:

```march
let (oks, errs) =
  Flow.from_list(filenames)
    |> Flow.map(fn name -> File.read(name))
    |> Flow.reduce((Nil, Nil), fn((oks, errs), r) ->
        match r do
        | Ok(v)  -> (Cons(v, oks), errs)
        | Err(e) -> (oks, Cons(e, errs))
        end)
```

---

## 7. Comparison with Elixir's GenStage / Flow

| Feature | March Flow | Elixir GenStage/Flow |
|---------|------------|----------------------|
| Core model | Stage wraps Seq (lazy fold) | GenServer-based stages with demand protocol |
| Backpressure | Implicit (lazy evaluation) in interpreter; actor-based in compiled | Explicit demand messages (`:ask`, `:events`) |
| Parallelism | `with_concurrency(n)` hint | `Flow.partition` / `Flow.from_stages` |
| State in stages | Stateless transformers; stateful stages need `Actor` | Stateful via GenStage `{:noreply, events, state}` |
| Error handling | `Result` values in the pipeline | `:noreply` or supervisor restarts |
| Ordering | Best-effort ordering; `with_concurrency` may reorder | `Flow.merge` merges in arrival order |
| Supervision | Supervisor tree for compiled runtime | OTP supervisors, `GenStage.stop` |

### Key differences from GenStage

**GenStage** is a low-level building block: you implement producers, consumers,
and producer-consumers explicitly as GenServer callbacks.  March's `Flow` is
the higher-level API (equivalent to Elixir's `Flow` library) that composes
stages automatically.

**Demand granularity**: Elixir's GenStage lets you tune `max_demand` /
`min_demand` per subscription.  In March, demand is implicit at the
`with_concurrency` level; fine-grained tuning is a planned feature.

**Partitioning**: Elixir's Flow has `partition/2` which routes items to
workers by key (useful for stateful aggregations like word counting).  March
`Flow` does not yet have partitioning; use `Actor` directly for stateful
fan-out.

---

## 8. When to use Flow vs Enum vs Seq

| Module | Best for |
|--------|----------|
| `List` / `Enum` | Eager transformations on in-memory lists. Simple, no allocation overhead beyond the list itself. |
| `Seq` | Lazy single-pass sequences (e.g., reading lines from a file, generating infinite sequences). No concurrency, no backpressure. |
| `Flow` | Multi-stage pipelines where you want composability and (in the compiled runtime) automatic parallelism and backpressure. Use when `Seq` would be sufficient but you anticipate adding `with_concurrency` later, or when the pipeline has ≥3 stages and explicit composition clarity matters. |

**Rule of thumb**:
- Transforming a `List` that fits in memory → `List.map` / `Enum.map`
- Streaming a file or large dataset line-by-line → `Seq` or `File.with_lines`
- Multi-stage data pipeline with optional parallelism → `Flow`
