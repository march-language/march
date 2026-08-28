---
layout: landing
title: March Lang
nav_order: 1
permalink: /
---

<div style="text-align: center; margin: 2rem 0 1.5rem;">
  <img src="{{ site.baseurl }}/assets/logo.webp" alt="March logo" width="120" height="120" style="display: inline-block;">
</div>

# March

**Elixir's concurrency model. ML's type safety. Native performance.**

March is a statically-typed, capability-based functional language built for concurrent and distributed systems: the kind you'd normally reach for Elixir or Erlang to build, but with a static type system, a compile-time effect system, algebraic data types, and compilation to native binaries via LLVM.

Write code that reads like Elixir. Get compile-time guarantees that your message protocols are correct, your resources aren't leaked, and your actor supervision trees handle faults the way you expect. Run at native speed with no garbage collector pauses.

---

## What makes March different

### Actors with supervision trees

March's concurrency model is the actor model: share-nothing, message-passing processes, just like Elixir. Actors are first-class: spawn them, link them, monitor them, and organize them into supervision trees that automatically restart failed processes.

```march
actor Counter do
  state { count : Int }
  init  { count: 0 }

  on Increment(n : Int) do
    { state with count: state.count + n }
  end
end

actor Logger do
  state { entries : Int }
  init  { entries: 0 }

  on Log(msg : String) do
    { state with entries: state.entries + 1 }
  end
end

actor WorkerSup do
  state { counter : Int, logger : Int }
  init  { counter: 0, logger: 0 }

  supervise do
    strategy one_for_one
    max_restarts 5 within 60
    Counter counter
    Logger  logger
  end
end
```

The type system enforces actor isolation: you cannot accidentally share mutable state between processes.

### Session types: typed communication protocols

March can verify at compile time that two actors follow a compatible communication protocol, including that neither side will deadlock. If your protocol states the server sends a response after receiving a request, the compiler checks both sides agree.

```march
-- Protocol: Client sends a query, Server replies with results.
-- Roles are inferred from the steps; the keyword is `protocol`.
protocol Search do
  Client -> Server : String
  Server -> Client : List(String)
end
```

Each side gets its own projected view and the compiler checks they're duals, so
mismatched message patterns and deadlocks become compile errors, not runtime
surprises. See [Session Types]({{ site.baseurl }}/docs/session-types/) for the full walkthrough.

### Perceus reference counting + FBIP

March uses **Perceus reference counting**: deterministic memory management with no stop-the-world GC pauses. But the real story is **FBIP (Functional But In-Place)**: when a value has exactly one owner, March rewrites it in-place instead of freeing and reallocating. Recursive tree transformations, list maps, and structural recursion patterns run with **zero heap allocations** after the initial build.

```march
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

March tracks ownership at the type level. Mark a type as `linear` and the compiler guarantees it is used exactly once: no leaks, no double-frees, no "I thought this was already closed" bugs. File handles, socket connections, and database transactions get static guarantees without a runtime cost.

```march
always_linear type FileHandle = FileHandle(Int)

fn write_and_close(f : FileHandle, content : String) : Unit do
  match f do
    FileHandle(fd) -> write_to_fd(fd, content)  -- consumes f
  end
  -- f cannot be used again; the compiler enforces this
end
```

### A REPL worth using

The March REPL is built with the ambition of Clojure's REPL experience: two-pane TUI, tab completion, syntax highlighting, `:type` and `:doc` queries, and access to the full standard library. Explore types interactively, test functions in isolation, and build intuition without a write-compile-run cycle.

### `forge`, a batteries-included build tool

```sh
forge new my_app       # scaffold a new project
forge build            # compile
forge test             # run the test suite
forge search "List.map"  # Hoogle-style search by name or type signature
forge interactive      # launch the REPL
```

---

## A taste of March

```march
mod Chat do
  needs IO.Console

actor Room do
  state { members : List(String) }
  init  { members: [] }

  on Enter(name) do
    { state with members: Cons(name, state.members) }
  end

  on Say(from, text) do
    let line = from ++ ": " ++ text
    state.members |> List.each(fn m -> println(m ++ " sees: " ++ line))
    state
  end

  on Leave(name) do
    { state with members: List.filter(state.members, fn m -> m != name) }
  end
end

fn main() do
  let room = spawn(Room)
  send(room, Enter("alice"))
  send(room, Enter("bob"))
  send(room, Say("alice", "hello!"))
  send(room, Leave("bob"))
end

end
```

---

## Feature overview

### Concurrency
- **Actor model**: share-nothing message passing, isolated by the type system
- **Supervision trees**: OneForOne, OneForAll, RestForOne restart strategies
- **Session types**: typed two-party protocols; deadlocks caught at compile time
- **Structured concurrency** via `Task(a)` and `Future(a)`

### Runtime and performance
- **Perceus reference counting**: deterministic, no tracing collector; freeing is inline work at a point you choose ([memory model]({{ site.baseurl }}/docs/memory-model/))
- **FBIP**: in-place reuse of memory when the compiler can prove unique ownership
- **LLVM backend**: whole-program monomorphization, defunctionalization, native binaries
- **SIMD & native arrays**: auto-vectorized `NativeArray` numeric loops plus explicit 128-bit `Simd` vector types, competitive with NumPy on the operations that vectorize ([guide]({{ site.baseurl }}/docs/simd/))
- **Work-stealing scheduler**: cooperative + preemptive, scales across cores
- **WebAssembly target**: compile to `.wasm` via `--target wasm64-wasi`
- **Linux cross-compilation**: build `linux/amd64` + `linux/arm64` binaries from any host via `zig cc`, Go's `GOOS=linux` style ([guide](tooling.md#cross-compiling-to-linux))

### Language
- **Algebraic data types**: `type Shape = Circle(Float) | Rect(Float, Float)`
- **Pattern matching** with exhaustiveness checking and guards
- **Pipe operator**: `list |> map(f) |> filter(g) |> sum`
- **Multi-head functions**: Elixir-style clause dispatch
- **`with` expressions**: monadic chaining for `Result`/`Option`
- **`let?` propagation**: `let? x = e` binds `Ok(x)` and returns `Err` immediately
- **Linear and affine types**: ownership tracking for resource safety
- **String interpolation**: `"Hello, ${name}!"`
- **List comprehensions**: `[x * 2 for x in nums, x > 0]`

### Type system
- **Type inference**: types flow through without annotation boilerplate
- **Generics**: `List(a)`, `Map(k, v)`, `Result(a, e)`
- **Interfaces**: `interface`, `impl`, `derive`
- **Type-level naturals**: `Vector(n, a)` with compile-time dimension checking

### Tooling
- **REPL**: two-pane TUI, tab completion, `:type` / `:doc` queries
- **LSP server**: diagnostics, hover, go-to-definition, completions
- **`forge` build tool**: new, build, test, search, interactive
- **Tree-sitter grammar** for Zed editor syntax highlighting
- **Time-travel debugger**: step backward through execution history

---

## Documentation

### Start here

New to March? Read these three in order, then branch out.

| Guide | What it covers |
|-------|---------------|
| [Installation](installation.md) | Prebuilt binaries (recommended); building from source |
| [Getting Started](getting-started.md) | Hello world, compiling, running the REPL |
| [Language Tour](tour.md) | Variables, functions, types, pipes: the essentials |

Prefer to poke at it live? [Try It Out](playground.md) runs March in your browser.

### Guides and reference

| Guide | What it covers |
|-------|---------------|
| [Build a CLI Tool](build-a-cli.md) | Start-to-finish: scaffold, args, files, test, build |
| [Cookbook](cookbook/) | Goal-oriented recipes: CLI, HTTP, JSON, files, config |
| [Type System](types.md) | ADTs, records, generics, Option, Result |
| [Linear Types](linear-types.md) | Ownership, linear and affine qualifiers |
| [Capabilities](capabilities.md) | IO permission caps, proof tokens, `needs` enforcement |
| [Refinement Types](refinement-types.md) | `{T \| pred}` predicates checked by Z3 |
| [Pattern Matching](pattern-matching.md) | Match, guards, exhaustiveness, nested patterns |
| [Safety by Construction](safety-by-construction.md) | Composing linear, capability, refinement, and typestate guarantees |
| [Memory Model](memory-model.md) | Perceus RC, FBIP in-place reuse, allocation-free code |
| [Module System](modules.md) | `mod`, `use`, `import`, `alias`, visibility |
| [Actors](actors.md) | Spawn, send, receive, linking, monitoring |
| [Supervision](supervision.md) | Supervision trees, restart strategies |
| [Parallelism](parallelism.md) | Tasks, `pmap`, the M:N work-stealing scheduler |
| [Session Types](session-types.md) | Typed two-party protocols; deadlocks caught at compile time |
| [Flow](flow.md) | Backpressure pipelines for streaming work |
| [Overload & Resilience](overload-resilience.md) | Bounded mailboxes, load shedding, and backoff, withstanding thundering herds |
| [Clustering](clustering.md) | Distributed actors: SWIM, CRDTs, RPC across nodes |
| [Interfaces](interfaces.md) | `interface`, `impl`, `derive` |
| [FFI](ffi.md) | Bind C/Rust libraries: `extern`, ownership, codecs, the `march` crate |
| [Standard Library](stdlib.md) | List, Map, String, Option, Result, and more |
| [REPL](repl.md) | Interactive session guide |
| [Tooling](tooling.md) | LSP, Zed, forge build tool |
| Coming from [Python](coming-from-python.md) · [TypeScript](coming-from-typescript.md) · [Haskell/Elixir/OCaml](coming-from-fp.md) | Mental-model maps for newcomers |
