---
layout: cookbook
title: "Coming from Haskell / Elixir / OCaml"
permalink: /docs/coming-from-fp/
---

# Coming from Haskell / Elixir / OCaml

March sits in the ML/Elixir family. Most concepts map directly; the main differences are syntax, the actor model, and the absence of laziness and typeclasses.

---

## Syntax cheatsheet

| Concept | Haskell | Elixir | OCaml | March |
|---------|---------|--------|-------|-------|
| Module | `module Foo where` | `defmodule Foo do` | `module Foo = struct` | `mod Foo do` |
| Function | `f x = x + 1` | `def f(x), do: x + 1` | `let f x = x + 1` | `fn f(x) do x + 1 end` |
| Lambda | `\x -> x + 1` | `fn x -> x + 1 end` | `fun x -> x + 1` | `fn x -> x + 1` |
| Pattern match | `case x of` | `case x do` | `match x with` | `match x do` |
| ADT | `data Shape = Circle Float \| Rect Float Float` | `{:circle, r} \| {:rect, w, h}` | `type shape = Circle of float \| Rect of float * float` | `type Shape = Circle(Float) \| Rect(Float, Float)` |
| Type params | `data Maybe a = Nothing \| Just a` | none | `type 'a option = None \| Some of 'a` | `type Option(a) = None \| Some(a)` |
| Result | `Either e a` | `{:ok, v} \| {:error, e}` | `('a, 'e) result` | `Result(a, e)` |
| Let binding | `let x = 42 in ...` | `x = 42` | `let x = 42 in ...` | `let x = 42` (no `in`) |
| Pipe | `f $ g x` | `x \|> g \|> f` | none | `g(x) \|> f   -- or: f(g(x))` |
| Record update | `r { field = v }` | `%{r \| field: v}` | `{ r with field = v }` | `{ r with field: v }` |
| Private fn | module boundary | `defp` | `let` (vs `let ... in sig`) | `pfn` |

---

## Key differences

### No typeclasses / no protocols by name: use `interface`/`impl`

```march
interface Eq(a) do
  fn eq : a -> a -> Bool
end

impl Eq(Int) do
  fn eq(x, y) do x == y end
end
```

The coherence rules are the same as Haskell's: one impl per type per interface per program.

### `let?` instead of `do`-notation / `>>=`

Haskell's `do`-notation for `Maybe`/`Either`:

```haskell
run s = do
  n    <- parseInt s
  user <- fetchUser n
  return (score user)
```

Becomes `let?` in March:

```march
fn run(s : String) : Result(Int, String) do
  let? n    = parse_int(s)
  let? user = fetch_user(n)
  Ok(user.score)
end
```

`let?` is not a monad; it's a first-class desugaring specific to `Result`. `Option` and custom types don't get it (yet).

### Actors instead of OTP GenServers

March actors are similar in structure to Elixir GenServers but without the boilerplate:

```march
actor Counter do
  state { value : Int }
  init { value: 0 }

  on Inc(n : Int) do
    { value: state.value + n }
  end

  on Get() do
    println(int_to_string(state.value))
    state
  end
end
```

`spawn(Counter)` returns a pid. `send(pid, Inc(5))` sends a message. No `handle_cast`/`handle_call` distinction; all messages are async by default.

### No laziness

March is strict. `List` is a linked list, not a lazy sequence. For streaming/lazy evaluation use `Seq` (the lazy sequence module) or `Flow` (concurrent lazy streams).

### Perceus RC instead of GC

No garbage collector: reference counting with in-place reuse (FBIP). Deterministic latency, no stop-the-world pauses. The `linear type` and `always_linear type` features give you Rust-style ownership at compile time when you need it.

---

## Concurrency & shared state

If you're coming from Haskell, mutable references (`IORef`, `MVar`, `TVar`) and
`async`/`Async` map onto March's two concurrency tools. If you're coming from
Elixir, you'll find the model familiar; actors *are* GenServers.

| Haskell / Elixir / OCaml | March |
|---|---|
| `IORef` / `MVar` / `TVar` (mutable cell) | an `actor`'s `state { … }` |
| `Control.Concurrent.Async` / `async` | `Task.async(fn () -> …)` + `Task.await` |
| `mapConcurrently` / `Async.Parallel` | `List.pmap` or `Task.await_many` |
| Elixir `GenServer` (`handle_call`/`cast`) | `actor` with `on Msg do … end` handlers |
| Elixir supervision tree | [Supervision](supervision.md) (`one_for_one`, …) |
| `bracket` / `with` / `withFile` | a `linear` resource; the compiler *checks* it's released, no runtime wrapper |

The last row is the interesting one: where Haskell's `bracket` guarantees cleanup
at runtime via an exception handler, March's [linear types](linear-types.md) make
"this handle must be consumed exactly once" a **compile-time** property; forget to
close it and the program doesn't build. For streaming with backpressure (GenStage
territory), see [Flow](flow.md).

---

## What maps cleanly

| Haskell / OCaml | March |
|-----------------|-------|
| `Data.Map.lookup` | `Map.get` |
| `Data.List.filter` | `List.filter` |
| `foldl` | `List.fold_left` |
| `Maybe.fromMaybe` | `Option.unwrap_or` |
| `Data.Either.fromRight` | `Result.unwrap` |
| `Data.List.sortBy` | `List.sort_by` |
| `concatMap` | `List.flat_map` |
| `Data.Map.insertWith` | `Map.merge_with` |
| `IORef` | `Vault` (shared store) or `actor` state |
| `STM` | `actor` + `Channel` |
