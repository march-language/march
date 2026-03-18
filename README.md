# March

March is a statically-typed functional language in the ML/Elixir family. It compiles to native binaries via LLVM.

```
mod Greet do

fn greet(name : String) : String do
  "Hello, " ++ name ++ "!"
end

fn main() : Unit do
  println(greet("world"))
end

end
```

## Features

**Type system**
- Hindley-Milner inference with bidirectional checking at function boundaries — annotations are optional except where inference fails
- Algebraic data types with pattern matching
- Records with functional update syntax (`{ r with field = value }`)
- Polymorphic functions monomorphized at compile time (no boxing overhead)
- Linear and affine types for ownership and safe mutation (in progress)

**Syntax**
- `fn name(x, y) do ... end` — named functions
- `fn x -> x + 1` / `fn (x, y) -> expr` — lambdas
- `let x = expr` — block-scoped bindings, no `in`
- `match expr with | Pat -> body end` — pattern matching
- `if cond then e1 else e2` — conditionals
- `x |> f |> g` — pipe operator
- `mod Name do ... end` — modules
- `--` line comments, `{- -}` nested block comments
- Multi-head functions (Elixir-style): consecutive `fn` clauses grouped automatically
- `when` guards on function heads and match branches

**Backend**
- Compiles to LLVM IR, linked to native binaries via `clang`
- Perceus reference counting — deterministic memory management, no GC pauses
- Escape analysis promotes allocations to the stack where possible
- Defunctionalization: closures compiled to structs + dispatch, no indirect call overhead
- Tree-walking interpreter available for fast iteration

**Concurrency** (interpreter only for now)
- Actor model: share-nothing message passing, `spawn`, `send`, `kill`, `is_alive`
- Actor state updated via record spread: `{ state with count = state.count + 1 }`

## Quick start

```bash
# Interpret a file
march file.march

# Compile to a native binary
march --compile file.march        # produces ./file
march --compile -o hello file.march

# Emit LLVM IR
march --emit-llvm file.march      # produces file.ll

# Interactive REPL
march
```

## Installing from source

**Prerequisites**
- OCaml 5.3.0 (via opam)
- `clang` (for native compilation)

**1. Install opam** (if needed)

```bash
brew install opam          # macOS
# or: https://opam.ocaml.org/doc/Install.html
opam init
```

**2. Create the OCaml switch**

```bash
opam switch create march 5.3.0
eval $(opam env --switch=march)
```

**3. Clone and build**

```bash
git clone https://github.com/march-lang/march.git
cd march
opam install . --deps-only
dune build
```

**4. Run the compiler**

```bash
dune exec march -- examples/list_lib.march
dune exec march -- --compile examples/list_lib.march
./examples/list_lib
```

To install `march` into your PATH:

```bash
dune install
```

## Running the tests

```bash
dune runtest
```

## Language tour

### Values and bindings

```
let x = 42
let greeting = "hello"
let flag = true
```

### Functions

```
fn add(x : Int, y : Int) : Int do
  x + y
end

-- Lambdas
let double = fn x -> x * 2
let add = fn (x, y) -> x + y
```

### Algebraic data types

```
type Shape = Circle(Float) | Rect(Float, Float) | Point

fn area(s : Shape) : Float do
  match s with
  | Circle(r)    -> 3.14159 *. r *. r
  | Rect(w, h)   -> w *. h
  | Point        -> 0.0
  end
end
```

### Records

```
type Point = { x : Int, y : Int }

let p = { x = 3, y = 4 }

-- Field access
let px = p.x

-- Functional update (returns a new record)
let q = { p with x = 10 }
```

### Pattern matching

```
fn describe(n : Int) : String do
  match n with
  | 0 -> "zero"
  | 1 -> "one"
  | _ -> "many"
  end
end
```

### Higher-order functions

```
fn map(f : Int -> Int, lst : List(Int)) : List(Int) do
  match lst with
  | Nil        -> Nil
  | Cons(h, t) -> Cons(f(h), map(f, t))
  end
end

let doubled = map(fn x -> x * 2, my_list)
```

### Option and Result

```
fn safe_div(a : Int, b : Int) : Option(Int) do
  if b == 0 then None else Some(a / b)
end

match safe_div(10, 2) with
| None    -> println("error")
| Some(n) -> println(int_to_string(n))
end
```

### Actors

```
actor Counter do
  state { value : Int }
  init  { value = 0 }

  on Increment(n : Int) do
    { state with value = state.value + n }
  end

  on Get() do
    println(int_to_string(state.value))
    state
  end
end

fn main() : Unit do
  let c = spawn(Counter)
  send(c, Increment(10))
  send(c, Increment(5))
  send(c, Get())
end
```

### Pipe operator

```
let result =
  range(1, 10)
  |> filter(fn x -> x % 2 == 0)
  |> map(fn x -> x * x)
  |> sum
```

## Built-in functions

| Function | Type | Description |
|---|---|---|
| `println(s)` | `String -> Unit` | Print with newline |
| `print(s)` | `String -> Unit` | Print without newline |
| `int_to_string(n)` | `Int -> String` | Format integer |
| `float_to_string(f)` | `Float -> String` | Format float |
| `bool_to_string(b)` | `Bool -> String` | Format boolean |
| `string_length(s)` | `String -> Int` | String length |
| `++` | `String -> String -> String` | String concatenation |

## Project layout

```
bin/main.ml              compiler entry point
lib/
  lexer/lexer.mll        ocamllex lexer
  parser/parser.mly      menhir parser
  desugar/desugar.ml     pipe desugar, multi-head fn grouping
  typecheck/typecheck.ml bidirectional HM type inference
  eval/eval.ml           tree-walking interpreter
  tir/
    lower.ml             AST → ANF typed IR
    mono.ml              monomorphization
    defun.ml             defunctionalization (closure lifting)
    perceus.ml           Perceus reference counting analysis
    escape.ml            escape analysis (stack promotion)
    llvm_emit.ml         TIR → LLVM IR
runtime/
  march_runtime.c        C runtime (alloc, RC, strings, I/O)
examples/
  list_lib.march         map, filter, fold, reverse, find
  actors.march           actor spawning, messaging, kill/restart
specs/                   language and compiler design documents
```

## License

MIT
