---
layout: docs
title: Getting Started
nav_order: 3
permalink: /docs/getting-started/
scrollmd: true
---

# Getting Started

This guide walks you from zero to a working March program. See [Installation](installation.md) first if you haven't installed March yet.

> **How to run March.** Use `march file.march` to run a single file, and `forge run` inside a `forge` project. If you built March from source instead of installing a binary, prefix the compiler invocations with `dune exec` (e.g. `dune exec march -- hello.march`, `dune exec forge -- run`) everywhere this guide writes `march …` or `forge …`.

---

## Hello, World

Every March file starts with a module declaration. Create `hello.march`:

```march
mod Hello do
  needs IO.Console

  fn main() do
    println("Hello, March!")
  end

end
```

Run it:

```sh
march hello.march
```

Output:
```
Hello, March!
```

**What's happening:**
- `mod Hello do ... end` declares a module. Every file must have exactly one top-level module.
- `fn main() do ... end` is the program entry point.
- `println` is a builtin that writes a line to stdout.

---

## A More Complete Program

```march
mod Greet do
  needs IO.Console

  fn greet(name : String) : String do
    "Hello, " ++ name ++ "!"
  end

  fn main() do
    let message = greet("World")
    println(message)
    let names = ["Alice", "Bob", "Carol"]
    List.each(names, fn n -> println(greet(n)))
  end

end
```

Run it:
```sh
march greet.march
```

Output:
```
Hello, World!
Hello, Alice!
Hello, Bob!
Hello, Carol!
```

Key things to notice:
- `let x = expr` binds a name (no `in` needed; subsequent lines in the block see it)
- `++` concatenates strings
- `List.each` takes a list and a function, running it for its side effects
- Lambdas are written `fn x -> body`

---

## Compiling to a Binary

To produce a standalone native binary, use `--compile`:

```sh
march --compile -o greet greet.march
./greet
```

The compiler runs LLVM, links the C runtime, and produces a native executable.

---

## The REPL

Start an interactive session:

```sh
march repl
```

(`march` with no arguments also drops you into the REPL.)

Or via forge:
```sh
forge interactive
```

The REPL loads the standard library and drops you into a numbered prompt:

```
march(1)>
```

Try some expressions:

```
march(1)> 1 + 1
= 2

march(2)> "Hello" ++ " " ++ "March"
= "Hello March"

march(3)> let xs = [1, 2, 3, 4, 5]
val xs = [1, 2, 3, 4, 5]

march(4)> xs |> List.map(fn x -> x * x)
= [1, 4, 9, 16, 25]
```

The last result is always bound to `v`:
```
march(5)> 42 * 2
= 84

march(6)> v + 1
= 85
```

Run `:set +t` to also print each result's inferred type (`:set -t` to turn it
back off); see the [REPL guide](repl.md) for the full command list.

---

## Using forge

`forge` is the recommended project manager for anything beyond a single file.

Create a new project:
```sh
forge new my_app
cd my_app
```

This scaffolds:
```
my_app/
├── forge.toml          # project manifest
├── lib/
│   └── my_app.march    # entry point
└── test/
    └── my_app_test.march
```

Build and run:
```sh
forge build
forge run
```

Run tests:
```sh
forge test
```

---

## Program Structure

A typical March program has:

```march
mod MyApp do
  needs IO.Console

  -- Type definitions
  type Color = Red | Green | Blue

  -- Pure helper functions
  fn color_name(c : Color) : String do
    match c do
      Red   -> "red"
      Green -> "green"
      Blue  -> "blue"
    end
  end

  -- Entry point
  fn main() do
    let c = Green
    println("Color: " ++ color_name(c))
  end

end
```

The `main()` function is called automatically when the program starts. Its return type can be `Unit` (implicit) or `Int` for an exit code.

---

## Type Annotations

Type annotations are optional but useful for documentation and catching mistakes early:

```march
fn add(x : Int, y : Int) : Int do
  x + y
end
```

Without annotations, the compiler infers everything:
```march
fn add(x, y) do
  x + y
end
```

Both are valid. The compiler will catch type errors either way.

---

## Next Steps

**Ready to build something?** → [Build a CLI Tool](/docs/build-a-cli/) takes you from `forge new` to a working binary, and the [Cookbook](/docs/cookbook/) has goal-oriented recipes (CLI, HTTP, JSON, files, config).

Learn the language:

- [Language Tour](tour.md): a comprehensive walkthrough of all syntax
- [Type System](types.md): algebraic data types, generics, Option/Result
- [Pattern Matching](pattern-matching.md): destructuring and exhaustiveness checking
- [Actors](actors.md): concurrent programming with the actor model, and the jumping-off point for supervision, clustering, and hot code reload

Curious about March's compile-time safety guarantees? These go beyond a standard ML-family type system:

- [Interfaces](interfaces.md): ad-hoc polymorphism with `interface`/`impl`
- [Linear Types](linear-types.md): resources the compiler proves are used exactly once, at zero runtime cost
- [Refinement Types](refinement-types.md): value predicates (`{Int | _ >= 0}`) checked by an SMT solver
- [Capabilities](capabilities.md): IO permissions tracked in the type system
- [Safety by Construction](safety-by-construction.md): how these layers compose on one function
- [Memory Model](memory-model.md): why March has no garbage collector or pauses

Coming from another language? [Python](coming-from-python.md) · [TypeScript](coming-from-typescript.md) · [Haskell/Elixir/OCaml](coming-from-fp.md).
