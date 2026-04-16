---
layout: page
title: REPL
nav_order: 14
---

# REPL

The March REPL is an interactive programming environment with a two-pane TUI, tab completion, syntax highlighting, and access to the full standard library.

---

## Starting the REPL

```sh
forge interactive
# alias:
forge i
```

You'll see:
```
march>
```

The standard library is pre-loaded. Type any March expression and press Enter.

---

## Evaluating Expressions

Any expression can be typed directly:

```
march> 1 + 1
2 : Int

march> "Hello" ++ ", " ++ "World!"
"Hello, World!" : String

march> List.range(1, 6)
[1, 2, 3, 4, 5] : List(Int)

march> List.map([1, 2, 3, 4, 5], fn x -> x * x)
[1, 4, 9, 16, 25] : List(Int)
```

The REPL shows both the value and its type.

---

## `v` — The Last Result

The special variable `v` always holds the most recent result:

```
march> 6 * 7
42 : Int

march> v
42 : Int

march> v * 2
84 : Int

march> v + v
168 : Int
```

This makes it easy to pipe results into the next expression without rebinding.

---

## `tap>` — Tracing

When a `tap>` appears in the output, it's a debug trace from a `|> IO.inspect` or explicit `tap` call. Example:

```
march> [1, 2, 3] |> List.map(fn x -> x * 2) |> List.filter(fn x -> x > 2)
tap> [2, 4, 6]
[4, 6] : List(Int)
```

---

## Let Bindings

`let` bindings persist for the rest of the session:

```
march> let xs = [1, 2, 3, 4, 5]
[1, 2, 3, 4, 5] : List(Int)

march> let evens = List.filter(xs, fn x -> x % 2 == 0)
[2, 4] : List(Int)

march> evens
[2, 4] : List(Int)

march> let doubled = List.map(evens, fn x -> x * 2)
[4, 8] : List(Int)
```

---

## Defining Functions

Define functions and use them in subsequent expressions:

```
march> fn square(n) do n * n end
<function> : Int -> Int

march> square(7)
49 : Int

march> List.map([1, 2, 3, 4, 5], square)
[1, 4, 9, 16, 25] : List(Int)
```

Define types:

```
march> type Color = Red | Green | Blue
type Color

march> Red
Red : Color

march> let c = Green
Green : Color
```

---

## Multi-Line Input

The REPL detects when you're in the middle of a `do...end` block or other multi-line construct and waits for completion:

```
march> fn greet(name) do
  ...>   "Hello, " ++ name ++ "!"
  ...> end
<function> : String -> String

march> greet("Alice")
"Hello, Alice!" : String
```

Similarly for match expressions, if/else, and other block constructs.

---

## REPL Commands

All commands start with `:`:

### `:help` — Show Help

```
march> :help
  :help               — this message
  :quit  :q           — exit
  :type  <expr>       — show inferred type without evaluating
  :inspect  <expr>    — show type and value  (alias: :i)
  :doc   <name>       — show documentation for a name
  :env                — list bindings in scope
  :load  <file>       — load a .march source file
  :reload             — reload the last :load-ed file
  :reset              — reset all bindings to stdlib baseline
```

### `:type` / `:t` — Show Type Without Evaluating

```
march> :type List.map
List(a) -> (a -> b) -> List(b)

march> :type 42
Int

march> :t fn x -> x + 1
Int -> Int
```

### `:inspect` / `:i` — Show Type and Value

```
march> :inspect [1, 2, 3]
value: [1, 2, 3]
type:  List(Int)

march> :i "hello"
value: "hello"
type:  String
```

### `:doc` — Show Documentation

```
march> :doc List.map
List.map : List(a) -> (a -> b) -> List(b)

Applies `f` to each element, returning a new list.

march> :doc unwrap
unwrap : Option(a) -> a

Extracts the value from Some(x), panicking if None.
```

### `:env` — List Bindings in Scope

Shows all user-defined names and their types (stdlib names are filtered out for clarity):

```
march> let x = 42
march> let ys = [1, 2, 3]
march> fn double(n) do n * 2 end

march> :env
x      : Int         = 42
ys     : List(Int)   = [1, 2, 3]
double : Int -> Int  = <function>
```

### `:load` — Load a File

Load a `.march` file into the REPL session. The module's names become available under the module name:

```
march> :load examples/modules.march

march> Example.demo_qualified()
43 : Int
```

### `:reload` — Reload the Last File

After editing a file, reload it without retyping the path:

```
march> :reload
-- reloaded: examples/modules.march
```

### `:reset` — Clear All Bindings

Reset to the stdlib baseline, discarding all user-defined names:

```
march> :reset
-- session reset
```

### `:quit` / `:q` — Exit

```
march> :quit
```

---

## Scope Panel

In a terminal that supports the TUI mode, the REPL shows a right-hand panel with all current bindings and their types. This updates as you type.

If the terminal doesn't support Notty (e.g., piped input, non-TTY), the REPL falls back to plain text mode without the TUI.

---

## Tab Completion

Press `Tab` to complete:
- **Module names** — type `Li` and tab to complete `List`
- **Qualified names** — type `List.` and tab to see all `List.*` functions
- **Keywords** — `fn`, `let`, `match`, `do`, `end`, etc.
- **In-scope names** — any `let`-bound name or function defined in the session

---

## History Navigation

- **↑ / ↓** — navigate through command history
- History is persisted to `~/.march_history` across sessions
- Set `MARCH_HISTORY_FILE` to change the path
- Set `MARCH_HISTORY_SIZE` to change how many entries are saved (default: 1000)

---

## The Debug REPL

When a `dbg()` breakpoint is hit during execution, the REPL enters debug mode. Additional commands are available:

```
dbg> :help
  :continue           — resume execution
  :back  N            — step N steps backward
  :forward  N         — step N steps forward
  :goto  N            — jump to step N
  :where              — show current stack trace
  :diff  N  [names]   — show value changes at step N
  :find               — search for a step by condition
  :trace  N           — show N steps of execution trace
  :actors             — list all actors
  :actor  ID          — show actor state history
  :quit               — exit program
```

The debug REPL lets you inspect and replay program execution. See `examples/debugger.march` for a demonstration.

---

## Workflow Tips

**Explore a stdlib module:**
```
march> :doc List
-- shows module overview

march> :type List.fold_left
b -> List(a) -> (b -> a -> b) -> b
```

**Prototype a function:**
```
march> fn fib(0) do 0 end
march> fn fib(1) do 1 end
march> fn fib(n) do fib(n - 1) + fib(n - 2) end
march> List.map(List.range(0, 10), fib)
[0, 1, 1, 2, 3, 5, 8, 13, 21, 34] : List(Int)
```

**Check a type without running code:**
```
march> :t List.zip
List(a) -> List(b) -> List((a, b))
```

**Load and test a file:**
```
march> :load src/my_module.march
march> MyModule.main()
```

---

## Next Steps

- [Getting Started](getting-started.md) — first programs
- [Standard Library](stdlib.md) — what's available in the REPL
- [Tooling](tooling.md) — LSP for editor integration
