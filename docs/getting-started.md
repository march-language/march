---
layout: page
title: Getting Started
nav_order: 3
---

# Getting Started

This guide walks you from zero to a working March program. See [Installation](installation.md) first if you haven't built the compiler yet.

---

## Hello, World

Every March file starts with a module declaration. Create `hello.march`:

```elixir
mod Hello do

  fn main() do
    println("Hello, March!")
  end

end
```

Run it:

```sh
dune exec march -- hello.march
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

```elixir
mod Greet do

  fn greet(name : String) : String do
    "Hello, " ++ name ++ "!"
  end

  fn main() do
    let message = greet("World")
    println(message)
    let names = ["Alice", "Bob", "Carol"]
    List.iter(names, fn n -> println(greet(n)))
  end

end
```

Run it:
```sh
dune exec march -- greet.march
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
- `List.iter` takes a list and a function
- Lambdas are written `fn x -> body`

---

## Compiling to a Binary

To produce a standalone native binary, use `--compile`:

```sh
dune exec march -- --compile -o greet greet.march
./greet
```

The compiler runs LLVM, links the C runtime, and produces a native executable.

---

## The REPL

Start an interactive session:

```sh
dune exec march -- --repl
```

Or via forge:
```sh
dune exec forge -- interactive
```

The REPL loads the standard library and drops you into a prompt:

```
march>
```

Try some expressions:

```
march> 1 + 1
2 : Int

march> "Hello" ++ " " ++ "March"
"Hello March" : String

march> let xs = [1, 2, 3, 4, 5]
[1, 2, 3, 4, 5] : List(Int)

march> xs |> List.map(fn x -> x * x)
[1, 4, 9, 16, 25] : List(Int)
```

The last result is always bound to `v`:
```
march> 42 * 2
84 : Int

march> v + 1
85 : Int
```

See the [REPL guide](repl.md) for all commands.

---

## Using forge

`forge` is the recommended project manager for anything beyond a single file.

Create a new project:
```sh
dune exec forge -- new my_app
cd my_app
```

This scaffolds:
```
my_app/
├── forge.toml          # project manifest
├── src/
│   └── my_app.march    # entry point
└── test/
    └── my_app_test.march
```

Build and run:
```sh
dune exec forge -- build
dune exec forge -- run
```

Run tests:
```sh
dune exec forge -- test
```

---

## Program Structure

A typical March program has:

```elixir
mod MyApp do

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

```elixir
fn add(x : Int, y : Int) : Int do
  x + y
end
```

Without annotations, the compiler infers everything:
```elixir
fn add(x, y) do
  x + y
end
```

Both are valid. The compiler will catch type errors either way.

---

## Next Steps

- [Language Tour](tour.md) — a comprehensive walkthrough of all syntax
- [Type System](types.md) — algebraic data types, generics, Option/Result
- [Pattern Matching](pattern-matching.md) — destructuring and exhaustiveness checking
- [Actors](actors.md) — concurrent programming with the actor model
