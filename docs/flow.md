---
layout: docs
title: Flow & Backpressure
nav_order: 10.8
permalink: /docs/flow/
scrollmd: true
---

# Flow & Backpressure

A fast producer feeding a slow consumer is one of the classic ways a concurrent program falls over. The producer reads a million-row file or accepts a flood of requests; the consumer does something slow with each item; and the queue between them grows without bound until memory runs out. `Flow` is March's answer: a **backpressure-aware pipeline** where the *consumer* sets the pace and the producer only runs as far ahead as the consumer has asked for.

```march
Flow.from_list([1, 2, 3, 4, 5])
  |> Flow.map(fn x -> x * 2)
  |> Flow.filter(fn x -> x > 4)
  |> Flow.collect
-- [6, 8, 10]
```

---

## What backpressure is, and why you want it

**Backpressure** means demand flows *backward*: consumers pull, producers push only on request. Instead of a producer shoving items into an unbounded buffer and hoping the consumer keeps up, each stage emits only as many items as the next stage has demanded. If the consumer slows down, the demand dries up, and the producer naturally throttles: no buffer blowup, no out-of-memory, no silent backlog.

Use `Flow` when:

- You're processing a stream that doesn't fit in memory: log lines, database rows, an HTTP response body, sensor readings.
- A producer can outrun a consumer and you need the system to self-regulate rather than buffer unboundedly.
- You want a reusable, composable pipeline (`≥ 3` stages) you can plug into different sources and sinks.

Don't use `Flow` for a one-off transformation of a small in-memory list; reach for `List.map` / `Enum.map` there. And for *stateful, bidirectional* workflows, talk to an [actor]({{ site.baseurl }}/docs/actors/) directly.

---

## The producer → transformer → consumer model

Every pipeline has three kinds of stage:

```
producer ──► transformer ──► transformer ──► consumer
                                  ▲
                           demand flows ◄──────────────
```

- **Producers** generate items: `Flow.from_list`, `Flow.from_seq`, `Flow.range`, `Flow.unfold`. They emit lazily; no item is computed until a downstream stage demands it.
- **Transformers** reshape the stream: `Flow.map`, `Flow.filter`, `Flow.flat_map`, `Flow.take`, `Flow.drop`, `Flow.batch`. They're lazy too, and chain with the pipe operator.
- **Consumers** run the pipeline. They are the **only eager** operations; they pull items through and force evaluation: `Flow.collect`, `Flow.reduce`, `Flow.run`, `Flow.each`, `Flow.count`, `Flow.find`.

A `Stage(a)` is the value flowing through the pipe: a lazy sequence of `a`s. Producers create one, transformers return a new one, consumers turn one into a result.

---

## Core API

### Producers

<!-- scroll:skip -->
```march
Flow.from_list([1, 2, 3, 4, 5])     -- from an in-memory list
Flow.from_seq(some_seq)             -- from an existing lazy Seq
Flow.range(0, 1000000)              -- the half-open range [0, 1000000)

-- Unfold a seed: next(seed) -> Option((item, new_seed)); stop on None.
Flow.unfold(0, fn s -> if s >= 5 do None else Some((s * s, s + 1)) end)
-- produces 0, 1, 4, 9, 16
```

`Flow.range` produces a million integers without materialising a million-element list; they're generated on demand as the consumer pulls.

### Transformers

<!-- scroll:skip -->
```march
Flow.from_list(words)
  |> Flow.map(fn w -> String.to_lowercase(w))
  |> Flow.filter(fn w -> String.byte_size(w) > 3)
  |> Flow.flat_map(fn line -> some_flow_of_tokens(line))
  |> Flow.take(100)
```

`flat_map`'s function returns a `Stage`, with items that are flattened into the output stream.

### Consumers

<!-- scroll:skip -->
```march
|> Flow.collect                         -- gather everything into a List
|> Flow.reduce(0, fn (acc, n) -> acc + n)   -- fold to a single value
|> Flow.run                             -- run for side effects, discard items
|> Flow.count                           -- how many items
|> Flow.find(fn x -> x > 100)           -- first match, or None
```

### `with_concurrency`

<!-- scroll:skip -->
```march
Flow.from_list(urls)
  |> Flow.map(fn url -> Http.get(url))
  |> Flow.with_concurrency(8)
  |> Flow.collect
```

`with_concurrency(stage, n)` is a **hint**: in the compiled runtime it asks the scheduler to run this stage across `n` worker actors. In the interpreter it's a no-op (see the next section). It does not change *which* items come out, only how many are computed at once.

---

## Interpreter vs. compiled: two backends, one API

`Flow` has the same shape everywhere, but the engine underneath differs:

- **In the interpreter** (`march run`, the REPL), a `Stage(a)` is a lazy `Seq(a)`, a fold-based, church-encoded sequence. "Demand" is implicit: the consumer's fold simply stops calling the producer's fold once it has enough (via `Seq.take` / a bounded fold). It is single-threaded, so `with_concurrency` is a no-op. The *results* are exactly what the compiled pipeline produces; only the parallelism is absent.
- **In the compiled runtime**, each `Stage` is backed by an **actor**. The consumer sends a `Demand(n)` message upstream; each stage forwards demand to its source, buffers at most `n` items, and pushes them downstream. This is real, message-driven backpressure: the demand protocol is what keeps a fast producer from outrunning a slow stage. `with_concurrency(n)` spawns `n` worker actors for the stage and round-robins demand across them.

So you develop and test against the interpreter (correct results, easy to reason about) and get backpressure and parallelism for free when you compile.

---

## Coming from Elixir: the GenStage comparison

`Flow` is modeled on Elixir's GenStage/Flow. If you know that world:

| Feature | March `Flow` | Elixir GenStage / Flow |
|---------|--------------|------------------------|
| Core model | Stage wraps a lazy `Seq` (interpreter) / actor (compiled) | GenServer stages with an explicit demand protocol |
| Backpressure | implicit (lazy) in the interpreter; actor `Demand(n)` when compiled | explicit `:ask` / `:events` demand messages |
| Parallelism | `with_concurrency(n)` hint | `Flow.partition` / `Flow.from_stages` |
| Stateful stages | stateless transformers; use an `Actor` for state | GenStage `{:noreply, events, state}` |
| Error handling | `Result` values flowing in the pipeline | `:noreply` or supervisor restarts |

`Flow` corresponds to Elixir's high-level **`Flow`** library (composed stages), not the low-level **GenStage** building block (where you hand-write producer/consumer callbacks). Fine-grained `min_demand` / `max_demand` tuning and key-based `partition` are GenStage features March `Flow` doesn't expose yet; for stateful key-routed fan-out, drop down to an [actor]({{ site.baseurl }}/docs/actors/).

---

## Where Flow fits among the concurrency tools

`Flow` is the **bounded streaming** member of March's concurrency toolkit. The decision guide in [Actors → Choosing a concurrency primitive]({{ site.baseurl }}/docs/actors/#choosing-a-concurrency-primitive) places it against actors, `Task.*`, and `List.pmap`. The short version:

> **Use `Flow` when an unbounded `Task.async_stream` would let a fast producer overwhelm a slow stage.** `Task.async_stream` over a giant collection spins up work for *every* item at once; if a downstream stage is the bottleneck, the in-flight work piles up. `Flow` is the bounded alternative: the consumer's demand caps how far ahead the producer runs.

If your data is a fixed list and each item is independent and roughly equal cost, [`List.pmap` / `pmap_n`]({{ site.baseurl }}/docs/parallel-collections/) is simpler. Reach for `Flow` when the work is a *multi-stage stream* and one stage can fall behind.

---

## See also

- [Actors]({{ site.baseurl }}/docs/actors/): the actors and scheduler the compiled `Flow` backend is built on, plus the concurrency decision guide.
- [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/): `pmap` / `pmap_n` for data-parallel collections.
- [Supervision Trees]({{ site.baseurl }}/docs/supervision/): a worked job processor that adds `Flow` backpressure in front of a pool of supervised workers.
