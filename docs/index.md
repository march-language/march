---
layout: home
title: March Lang
nav_order: 1
---

# March

**Elixir's concurrency model. ML's type safety. Native performance.**

March is a statically-typed functional language built for concurrent and distributed systems — the kind you'd normally reach for Elixir or Erlang to build, but with a static type system, algebraic data types, and compilation to native binaries via LLVM.

Write code that reads like Elixir. Get compile-time guarantees that your message protocols are correct, your resources aren't leaked, and your actor supervision trees handle faults the way you expect. Run at native speed with no garbage collector pauses.

---

## What makes March different

### Actors with supervision trees

March's concurrency model is the actor model — share-nothing, message-passing processes, just like Elixir. Actors are first-class: spawn them, link them, monitor them, and organize them into supervision trees that automatically restart failed processes.

```elixir
actor Counter do
  state { count : Int }
  init  { count = 0 }

  on Increment(n : Int) do
    { state with count = state.count + n }
  end

  on Get() -> reply state.count
end

supervisor WorkerSup do
  strategy OneForOne
  children [Counter, Logger]
end
```

The type system enforces actor isolation — you cannot accidentally share mutable state between processes.

### Session types: typed communication protocols

March can verify at compile time that two actors follow a compatible communication protocol — including that neither side will deadlock. If your protocol says the server sends a response after receiving a request, the compiler checks both sides agree.

```elixir
-- Protocol: client sends a query, server replies with a result
session Search do
  client -> server : Query(String)
  server -> client : Results(List(String))
end
```

Mismatched message patterns and deadlocks become compile errors, not runtime surprises.

### Perceus reference counting + FBIP

March uses **Perceus reference counting** — deterministic memory management with no stop-the-world GC pauses. But the real story is **FBIP (Functional But In-Place)**: when a value has exactly one owner, March rewrites it in-place instead of freeing and reallocating. Recursive tree transformations, list maps, and structural recursion patterns run with **zero heap allocations** after the initial build.

```elixir
-- This runs with zero allocations on each recursive call (FBIP fires automatically)
fn inc_leaves(t : Tree) : Tree do
  match t do
    Leaf(n)    -> Leaf(n + 1)
    Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
  end
end
```

On a depth-20 binary tree (1M leaves), 100 passes of a transformation like this:

| | Time |
|---|---|
| C (`malloc`/`free`) | 8.8 s |
| Rust (`Box`) | 9.5 s |
| **March (FBIP)** | **1.3 s** |

March wins not because C is slow, but because FBIP eliminates 200M allocator calls entirely.

### Linear and affine types

March tracks ownership at the type level. Mark a type as `linear` and the compiler guarantees it is used exactly once — no leaks, no double-frees, no "I thought this was already closed" bugs. File handles, socket connections, and database transactions get static guarantees without a runtime cost.

```elixir
linear type FileHandle = FileHandle(Int)

fn write_and_close(f : FileHandle, content : String) : Unit do
  File.write(f, content)  -- consumes f
  -- f cannot be used again; the compiler enforces this
end
```

### A REPL worth using

The March REPL is built with the ambition of Clojure's REPL experience: two-pane TUI, tab completion, syntax highlighting, `:type` and `:doc` queries, and access to the full standard library. Explore types interactively, test functions in isolation, and build intuition without a write-compile-run cycle.

### `forge` — a batteries-included build tool

```sh
forge new my_app       # scaffold a new project
forge build            # compile
forge test             # run the test suite
forge search "List.map"  # Hoogle-style search by name or type signature
forge interactive      # launch the REPL
```

---

## A taste of March

```elixir
mod Chat do

type Message = Join(String) | Leave(String) | Say(String, String)

actor Room do
  state { members : List(String) }
  init  { members = [] }

  on Join(name) do
    { state with members = [name | state.members] }
  end

  on Say(from, text) do
    let line = from ++ ": " ++ text
    state.members |> List.iter(fn m -> println(m ++ " sees: " ++ line))
    state
  end

  on Leave(name) do
    { state with members = List.filter(fn m -> m != name, state.members) }
  end
end

fn main() do
  let room = spawn(Room)
  send(room, Join("alice"))
  send(room, Join("bob"))
  send(room, Say("alice", "hello!"))
  send(room, Leave("bob"))
end

end
```

---

## Feature overview

### Concurrency
- **Actor model** — share-nothing message passing, isolated by the type system
- **Supervision trees** — OneForOne, OneForAll, RestForOne restart strategies
- **Session types** — typed two-party protocols; deadlocks caught at compile time
- **Structured concurrency** via `Task(a)` and `Future(a)`

### Runtime and performance
- **Perceus reference counting** — deterministic, no GC pauses
- **FBIP** — in-place reuse of memory when the compiler can prove unique ownership
- **LLVM backend** — whole-program monomorphization, defunctionalization, native binaries
- **Work-stealing scheduler** — cooperative + preemptive, scales across cores
- **WebAssembly target** — compile to `.wasm` via `--target wasm64-wasi`

### Language
- **Algebraic data types** — `type Shape = Circle(Float) | Rect(Float, Float)`
- **Pattern matching** with exhaustiveness checking and guards
- **Pipe operator** — `list |> map(f) |> filter(g) |> sum`
- **Multi-head functions** — Elixir-style clause dispatch
- **`with` expressions** — monadic chaining for `Result`/`Option`
- **Linear and affine types** — ownership tracking for resource safety
- **String interpolation** — `"Hello, ${name}!"`
- **List comprehensions** — `[x * 2 for x in nums, x > 0]`

### Type system
- **Type inference** — types flow through without annotation boilerplate
- **Generics** — `List(a)`, `Map(k, v)`, `Result(a, e)`
- **Interfaces** — `interface`, `impl`, `derive`
- **Type-level naturals** — `Vector(n, a)` with compile-time dimension checking

### Tooling
- **REPL** — two-pane TUI, tab completion, `:type` / `:doc` queries
- **LSP server** — diagnostics, hover, go-to-definition, completions
- **`forge` build tool** — new, build, test, search, interactive
- **Tree-sitter grammar** for Zed editor syntax highlighting
- **Time-travel debugger** — step backward through execution history

---

## Documentation

| Guide | What it covers |
|-------|---------------|
| [Try It Out](playground.md) | Interactive REPL — run March in your browser |
| [Installation](installation.md) | Build from source, prerequisites |
| [Getting Started](getting-started.md) | Hello world, compiling, running the REPL |
| [Language Tour](tour.md) | Variables, functions, types, pipes — the essentials |
| [Type System](types.md) | ADTs, records, generics, Option, Result |
| [Linear Types](linear-types.md) | Ownership, linear and affine qualifiers |
| [Pattern Matching](pattern-matching.md) | Match, guards, exhaustiveness, nested patterns |
| [Module System](modules.md) | `mod`, `use`, `import`, `alias`, visibility |
| [Actors](actors.md) | Spawn, send, receive, linking, monitoring |
| [Supervision](supervision.md) | Supervision trees, restart strategies |
| [Interfaces](interfaces.md) | `interface`, `impl`, `derive` |
| [Standard Library](stdlib.md) | List, Map, String, Option, Result, and more |
| [REPL](repl.md) | Interactive session guide |
| [Tooling](tooling.md) | LSP, Zed, forge build tool |
