---
layout: home
title: March Programming Language
nav_order: 1
---

# March

**A statically-typed functional language in the ML/Elixir tradition, compiled to native code via LLVM.**

March is designed for building reliable, high-performance systems — from CLI tools to concurrent web servers — with a type system that catches whole categories of bugs at compile time.

---

## Key Features

### Type System
- **Hindley-Milner type inference** — types are inferred everywhere; annotations are optional except where you want them
- **Algebraic data types** — sum types (`type Shape = Circle(Float) | Rect(Float, Float)`) and record types
- **Generics** with type parameters (`List(a)`, `Map(k, v)`, `Result(a, e)`)
- **Linear and affine types** — the compiler tracks ownership; resources cannot be leaked or double-freed
- **Type-level naturals** — `Vector(n, a)` with compile-time dimension checking

### Concurrency
- **Actor model** — share-nothing message passing, isolated by the type system
- **Supervision trees** — fault-tolerant process hierarchies with configurable restart strategies
- **Session types** — typed two-party protocols, verified at compile time (deadlocks caught before you ship)
- **Structured concurrency** via `Task(a)` and `Future(a)`

### Ergonomics
- **Pipe operator** — `list |> map(f) |> filter(g)`
- **Pattern matching** with exhaustiveness checking and guards
- **`with` expressions** for monadic chaining of `Result`/`Option`
- **Multi-head functions** — Elixir-style clause dispatch
- **Default arguments**
- **String interpolation** — `"Hello, ${name}!"`
- **List comprehensions** — `[x * 2 for x in nums, x > 0]`

### Tooling
- **REPL** with two-pane TUI, tab completion, and `:type`/`:doc` queries
- **LSP server** — diagnostics, hover, go-to-definition, completions, performance insights
- **`forge` build tool** — `forge new`, `forge build`, `forge test`, `forge search`
- **Tree-sitter grammar** for Zed editor syntax highlighting
- **Time-travel debugger** — step backward through execution history

### Runtime
- **Perceus reference counting** — deterministic memory management, no stop-the-world GC pauses
- **FBIP optimization** — functional-but-in-place reuse of memory when safe
- **Work-stealing scheduler** — cooperative + preemptive, scales across cores
- **Compiled to LLVM IR** — whole-program monomorphization and defunctionalization

---

## Quick Look

```march
mod Greeter do

type Greeting = Formal | Casual

fn greet(style : Greeting, name : String) : String do
  match style do
    Formal -> "Good day, " ++ name ++ "."
    Casual -> "Hey " ++ name ++ "!"
  end
end

fn main() do
  let names = ["Alice", "Bob", "Carol"]
  names
  |> List.map(fn n -> greet(Casual, n))
  |> List.iter(fn msg -> println(msg))
end

end
```

---

## Documentation

| Guide | What it covers |
|-------|---------------|
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
