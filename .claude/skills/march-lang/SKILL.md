---
name: march-lang
description: |
  March programming language reference — syntax, builtins, stdlib API, testing patterns, and common pitfalls. Use this skill whenever working on March source files (.march), writing or fixing March stdlib modules, writing March tests, modifying the March compiler (lexer/parser/AST/desugar/typecheck/eval), or debugging March compilation errors. Also trigger when the user mentions "march", ".march files", "stdlib", "test library", or asks to implement features in the March language. This skill saves significant time by front-loading the language quirks that trip up every agent.
---

# March Language Reference

March is a statically-typed functional language — an ML/Elixir hybrid compiled with OCaml 5.3.0. This document captures the patterns, idioms, and gotchas that matter when writing March code or modifying the compiler. Read the section relevant to your task before writing any code.

## Build & run commands

Run these directly. **Never prefix with `eval $(opam env ...)`** — the opam switch is already configured.

```
dune build                              # compile everything
dune runtest                            # OCaml test suite

# Running March files (use either dune or forge):
dune exec march -- file.march           # run a single .march file
forge run file.march                    # same, via forge CLI

# Running tests (use either dune or forge):
dune exec march -- test path/to/test.march   # run a single test file
forge test path/to/test.march                # same, via forge CLI
forge test test/stdlib/                      # run all tests in a directory
forge test                                   # auto-discover and run all tests
```

## Core syntax

March uses `do...end` blocks, newline-separated expressions (no semicolons), and ML-style type annotations.

### Functions

```march
-- Named function (public by default — no qualifier needed)
fn add(x : Int, y : Int) : Int do
  x + y
end

-- Private (explicit opt-in with `pfn`)
pfn helper(x : Int) : Int do
  x * 2
end

-- Multi-head pattern matching (clauses must be adjacent)
fn factorial(0) : Int do 1 end
fn factorial(n : Int) : Int do n * factorial(n - 1) end
```

**Visibility rules:**
- `fn` = **public** (default — no qualifier needed)
- `pfn` = **private** (explicit opt-in to hide)
- `type` = **public** (default)
- `ptype` = **private** (explicit opt-in to hide)
- `pub` is a **parse error** — do not use it

### Lambdas

```march
-- Single parameter: no parens needed
fn x -> x + 1

-- Multiple parameters: use parens with comma separation
fn (a, b) -> a + b

-- Used in practice (e.g., as callback to fold_left):
List.fold_left(0, xs, fn (acc, x) -> acc + x)
```

**The multi-arg lambda gotcha:** `fn (a, b) -> expr` creates a function taking **two separate arguments**. This is NOT tuple destructuring — it's how March spells multi-param lambdas. To destructure a tuple inside a lambda, use match:

```march
-- This is a 2-arg lambda, NOT tuple destructure:
fn (x, y) -> x + y

-- To destructure a tuple, use match:
fn p -> match p do | (x, y) -> x + y end
```

**JIT caveat:** Standalone multi-arg lambdas (not passed as callbacks) may trigger JIT codegen errors. This is a known issue with the LLVM JIT backend. When writing examples or tests, use lambdas within function calls where they work reliably.

### Let bindings

Block-scoped with no `in` keyword. Subsequent expressions in the same block see the binding:

```march
let x = 42
let y = x + 1
y * 2
```

### Conditionals

```march
if x > 0 then "positive" else "non-positive"
```

Always `if/then/else` — never `if/do/end`.

### Match expressions

```march
match xs do
| Nil        -> 0
| Cons(h, t) -> h + sum(t)
end
```

Arms use `block_body` — multi-statement arms work without wrappers:

```march
match opt do
| Some(x) ->
  let doubled = x * 2
  println(to_string(doubled))
  doubled
| None -> 0
end
```

### Modules

```march
mod MyModule do
  fn greet(name : String) : String do
    "Hello, " ++ name
  end
end
```

Use `mod Name do...end`, not `module`. Call with `MyModule.greet("world")`.

### Types

```march
type Color = Red | Green | Blue
type Shape = Circle(Float) | Rect(Float, Float)
type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))

-- Private type (not exported from module):
ptype InternalState = Active | Inactive
```

No leading `|` on the first variant.

### Lists

Lists use built-in constructors `Cons` and `Nil`:

```march
let xs = Cons(1, Cons(2, Cons(3, Nil)))
-- Equivalent list literal:
let ys = [1, 2, 3]
```

### Records

```march
let point = { x = 1, y = 2 }
let moved = { point with x = point.x + 10 }
point.x    -- field access
```

### Pipe operator

```march
[1, 2, 3] |> List.map(fn x -> x * 2) |> List.filter(fn x -> x > 2)
```

### String interpolation

```march
let name = "world"
let greeting = "Hello, ${name}!"
```

### Atoms

```march
:ok
:error
:ok(42)          -- atom with payload
:error("oops")
```

### Doc comments

```march
doc "Returns the sum of two integers."
fn add(x : Int, y : Int) : Int do
  x + y
end

doc """
Multi-line doc comment.
Supports multiple paragraphs.
"""
fn complex_fn() do ... end
```

## Operators

| Category | Operators |
|----------|-----------|
| Arithmetic (Int) | `+`, `-`, `*`, `/`, `%` |
| Arithmetic (Float) | `+.`, `-.`, `*.`, `/.` |
| Comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` |
| Boolean | `&&`, `\|\|`, `!` (prefix not) |
| String concat | `++` |
| Pipe | `\|>` |

**Int vs Float arithmetic is strict.** Use `+.` for float addition, `-.` for float subtraction, etc. Mixing `+` with floats is a type error.

## Builtins available everywhere

These are in scope without any module prefix:

| Function | Signature | Notes |
|----------|-----------|-------|
| `print(v)` | `a -> Unit` | Print without newline |
| `println(v)` | `a -> Unit` | Print with newline |
| `to_string(v)` | `a -> String` | Polymorphic conversion |
| `int_to_string(n)` | `Int -> String` | |
| `float_to_string(f)` | `Float -> String` | |
| `string_to_int(s)` | `String -> Option(Int)` | Returns `Some`/`None` |
| `string_to_float(s)` | `String -> Option(Float)` | Returns `Some`/`None` |
| `string_length(s)` | `String -> Int` | Byte length |
| `float_abs(f)` | `Float -> Float` | |
| `float_floor(f)` | `Float -> Int` | Returns Int |
| `float_ceil(f)` | `Float -> Int` | Returns Int |
| `float_sqrt(f)` | `Float -> Float` | |
| `float_to_int(f)` | `Float -> Int` | Truncation |
| `int_to_float(n)` | `Int -> Float` | |
| `panic(msg)` | `String -> a` | Abort with error |
| `todo_(msg)` | `String -> a` | Placeholder |

## Stdlib modules

Every module is auto-loaded. Call functions with `Module.function(args)`. Here is the full list of available modules — **always run `forge search Module -p`** before calling functions to verify what actually exists:

`List`, `Map`, `Set`, `Array`, `Queue`, `String`, `Option`, `Result`, `Math`, `Enum`, `BigInt`, `Decimal`, `DateTime`, `Bytes`, `Json`, `Regex`, `Csv`, `File`, `Dir`, `Path`, `Http`, `HttpClient`, `HttpServer`, `HttpTransport`, `WebSocket`, `Process`, `Logger`, `Flow`, `Actor`, `Sort`, `Hamt`, `Seq`, `Iterable`, `IOList`, `Random`, `Stats`, `Plot`, `Prelude`

### Key stdlib patterns

**fold_left takes (acc, list, fn):**
```march
-- fn argument is called with (acc, elem) as a 2-arg call
List.fold_left(0, xs, fn (acc, x) -> acc + x)
```

**sort_by takes a comparator with 2-arg lambda:**
```march
List.sort_by(xs, fn (a, b) -> a < b)
```

**map/filter take (list, fn):**
```march
List.map(xs, fn x -> x + 1)
List.filter(xs, fn x -> x > 0)
```

## Writing tests

March has a native test library. Tests use `test "name" do...end` and `describe "group" do...end` for organization. **Never use the old `fn test_foo() do` pattern.**

### Test file structure

```march
-- test/stdlib/test_list.march
mod TestList do

describe "map" do
  test "maps function over elements" do
    assert (List.map([1, 2, 3], fn x -> x * 2) == [2, 4, 6])
  end

  test "maps over empty list" do
    assert (List.map([], fn x -> x + 1) == [])
  end
end

describe "filter" do
  test "keeps matching elements" do
    assert (List.filter([1, 2, 3, 4], fn x -> x > 2) == [3, 4])
  end
end

end -- mod TestList
```

### Assert syntax

Use `assert expr` where `expr` evaluates to a boolean. For comparisons, the evaluator shows LHS and RHS on failure:

```march
assert (x == 42)             -- comparison: shows both sides on failure
assert (List.length(xs) > 0) -- comparison: shows both sides
assert Result.is_ok(r)       -- plain bool: shows true/false
assert !Result.is_err(r)     -- negation with !
```

**There is no `assert_eq`, `assert_true`, or `assert_false`.** Just `assert (expr)`.

### Float comparison in tests

Floats need epsilon comparison. Define a helper:

```march
fn approx_eq(a : Float, b : Float) : Bool do
  float_abs(a -. b) < 0.000001
end

test "mean is correct" do
  assert approx_eq(Stats.mean(xs), 3.0)
end
```

### Running tests

```
# Via forge (preferred — handles discovery, directories, single files):
forge test                                    # auto-discover all tests
forge test test/stdlib/                       # all tests in directory
forge test test/stdlib/test_list.march        # single file

# Via dune (always works, no forge.toml needed):
dune exec march -- test test/stdlib/test_list.march           # single file
dune exec march -- test test/stdlib/                          # directory
dune exec march -- test --verbose test/stdlib/test_list.march # verbose output
dune exec march -- test --filter="map" test/stdlib/           # filter by name
```

## The newline-as-call gotcha

March's parser is newline-agnostic for function calls. If the last expression in a `let` binding ends with an identifier or literal, and the next line starts with `(`, the parser interprets it as a function call:

```march
-- BROKEN: parser sees `result(next_val, other)` as a call
let result = some_value
(next_val, other)

-- FIX 1: wrap the let RHS in a function call that returns it
let result = identity(some_value)
(next_val, other)

-- FIX 2: bind the tuple to avoid ambiguity
let result = some_value
let pair = (next_val, other)
```

This is especially common with `let x = y` followed by a tuple on the next line.

## Common mistakes and how to avoid them

### 1. Calling functions that don't exist

**Always run `forge search` before writing code that calls stdlib functions.** Agents frequently invent function names like `Logger.level_enabled` or `String.capitalize` that don't exist. Run `forge search Module -p` to see what's actually available. The compiler error will say: `I cannot find a variable named \`Module.function\`.`

### 2. Using `assert_eq` instead of `assert`

```march
-- WRONG
assert_eq(x, 42)

-- RIGHT
assert (x == 42)
```

### 3. Shadowing builtins

If a stdlib module defines a `fn negate(...)`, it shadows the built-in `negate` used for negative literals like `-1`. This breaks integer negation in any file that imports that module. Avoid naming functions `negate`.

### 4. Structural recursion warnings

Functions that recurse without an accumulator get a TCE (Tail-Call Enforcement) warning:

```march
-- WARNING: structurally recursive
fn map(xs, f) do
  match xs do
  | Nil -> Nil
  | Cons(h, t) -> Cons(f(h), map(t, f))
  end
end

-- GOOD: accumulator + reverse pattern
fn map(xs, f) do
  fn go(lst, acc) do
    match lst do
    | Nil -> reverse(acc)
    | Cons(h, t) -> go(t, Cons(f(h), acc))
    end
  end
  go(xs, Nil)
end
```

### 5. Type annotations on lambda parameters in higher-order calls

When passing a lambda to a polymorphic function that the type checker can't infer, you may need annotations:

```march
-- May need annotation if type is ambiguous:
Result.map(Err("e"), fn (x : Int) -> x + 1)
```

### 6. Underscore-prefixed identifiers

`_name` is a valid lowercase identifier (variable), not an ignored pattern. To ignore a value, use bare `_`.

## Compiler architecture

If you're modifying the compiler itself, here's the pipeline and where to make changes:

```
Source → Lexer → Parser → AST → Desugar → Typecheck → Eval
         ↓        ↓       ↓       ↓          ↓         ↓
     lexer.mll parser.mly ast.ml desugar.ml typecheck.ml eval.ml
```

### Adding a new keyword

1. **lexer.mll**: Add to `keyword_table`: `("mykeyword", MYKEYWORD);`
2. **parser.mly**: Add `%token MYKEYWORD` and grammar rules
3. **ast.ml**: Add new AST node type (e.g., `DMyThing` or `EMyExpr`)
4. **desugar.ml**: Handle the new node (often pass-through)
5. **typecheck.ml**: Add type checking logic
6. **eval.ml**: Add evaluation logic

### Adding a new builtin

Add to the `initial_env` list in `eval.ml`:

```ocaml
; ("my_builtin", VBuiltin ("my_builtin", function
      | [VString s] -> VString (String.uppercase_ascii s)
      | _ -> eval_error "my_builtin: expected string"))
```

### Adding a new stdlib module

1. Create `stdlib/mymod.march` with `mod MyMod do ... end`
2. Add to the stdlib loading list in `bin/main.ml`
3. Create `test/stdlib/test_mymod.march` with native test syntax
4. Run `dune build` to verify compilation

## Project conventions

- Update `specs/todos.md` and `specs/progress.md` when completing features
- Stage git files explicitly (`git add file1 file2`) — never `git add -A` or `git add .`
- Comments use `--` (double dash), not `//` or `#`
- Doc comments use `doc "..."` or `doc """..."""` before a function
- Run `dune build` after every change to catch errors early

## Quick reference: finding stdlib functions

Before writing any March code that calls stdlib functions, use `forge search` to find what's available:

```bash
forge search map                          # find functions by name (fuzzy match)
forge search --type "List(a) -> Int"      # find functions by type signature
forge search --doc "sort"                 # search doc strings by keyword
forge search map --type "List(a)" -p      # combined search, pretty table output
forge search reverse --json               # raw JSON output for scripting
```

Use `forge search` instead of grepping source files — it indexes all stdlib modules with signatures, doc strings, and source locations. Add `-p` / `--pretty` for a colored table view.

To see the full public API of a specific module, search by module name:

```bash
forge search List -p                      # all List module functions
forge search Map -p                       # all Map module functions
```

Trust `forge search` results over assumptions about what functions exist.
