---
layout: page
title: Language Tour
nav_order: 4
---

# Language Tour

A fast walkthrough of March syntax and core concepts. Every snippet here runs as-is.

---

## Comments

```elixir
-- this is a line comment

{- this is a block comment
   {- they nest -}
-}
```

---

## Modules

Every March file begins with exactly one module declaration:

```elixir
mod MyApp do
  -- everything goes here
end
```

Modules can be dotted (for multi-file projects):

```elixir
mod MyApp.Router do
  -- ...
end
```

Modules can be nested:

```elixir
mod Outer do
  mod Inner do
    fn greet() do println("from Inner") end
  end
end
```

---

## Variables

`let` binds a name in the current block. No `in` is needed — subsequent expressions in the block see the binding:

```elixir
fn main() do
  let x = 42
  let y = x + 1
  println(int_to_string(y))   -- 43
end
```

Type annotations are optional:

```elixir
let count : Int = 0
let name : String = "March"
```

Module-level `let` defines constants:

```elixir
mod Config do
  let max_retries = 3
  let base_url = "https://example.com"
end
```

---

## Primitive Types

| Type | Examples | Notes |
|------|---------|-------|
| `Int` | `42`, `-7`, `0` | 64-bit signed integer |
| `Float` | `3.14`, `-0.5` | 64-bit floating-point |
| `Bool` | `true`, `false` | |
| `String` | `"hello"` | UTF-8 |
| `Char` | (via String) | Unicode scalar |
| `()` | `()` | Unit (no value) |

Float arithmetic uses dotted operators to make it explicit:

```elixir
let sum = 1.0 +. 2.5    -- Float +
let diff = 3.0 -. 1.5   -- Float -
let prod = 2.0 *. 4.0   -- Float *
let quot = 9.0 /. 3.0   -- Float /
```

Integer arithmetic uses the plain operators: `+`, `-`, `*`, `/`, `%`.

---

## Strings

Concatenate with `++`:

```elixir
let greeting = "Hello, " ++ "World!"
```

String interpolation with `${}`:

```elixir
let name = "Alice"
let msg = "Hello, ${name}!"   -- "Hello, Alice!"
```

Triple-quoted strings preserve newlines:

```elixir
let html = """
  <div>
    <p>Hello</p>
  </div>
"""
```

Useful builtins: `int_to_string`, `float_to_string`, `bool_to_string`, `to_string`.

---

## Functions

Named functions use `fn name(params) do ... end`:

```elixir
fn add(x : Int, y : Int) : Int do
  x + y
end
```

Return type annotation is optional:

```elixir
fn square(n) do
  n * n
end
```

Functions can have multiple expressions in the body; the last one is the return value:

```elixir
fn summarize(xs : List(Int)) : String do
  let n   = List.length(xs)
  let sum = List.fold(xs, 0, fn acc x -> acc + x)
  "count=" ++ int_to_string(n) ++ " sum=" ++ int_to_string(sum)
end
```

### Private Functions

Use `pfn` to make a function private to its module:

```elixir
mod Passwords do
  pfn hash_raw(s : String) : String do
    -- not callable outside this module
    Crypto.sha256(s)
  end

  fn verify(plain, stored) do
    hash_raw(plain) == stored
  end
end
```

### Default Arguments

```elixir
fn greet(name, greeting \\ "Hello") do
  greeting ++ ", " ++ name ++ "!"
end

greet("World")          -- "Hello, World!"
greet("World", "Hi")    -- "Hi, World!"
```

All defaulted parameters must be trailing.

### Multi-Head Functions

Consecutive clauses with the same name are merged into a single function with pattern dispatch (Elixir-style):

```elixir
fn len(Nil) do 0 end
fn len(Cons(_, t)) do 1 + len(t) end
```

```elixir
fn abs(n) when n < 0 do -n end
fn abs(n) do n end
```

---

## Lambdas

Lambdas use arrow syntax: `fn params -> body`.

```elixir
fn x -> x + 1                -- single param
fn (a, b) -> a + b           -- multiple params (parenthesized)
fn () -> 42                  -- ZERO-ARG: must use fn () -> ...
fn _ -> "ignored"            -- wildcard (1-arg, discards the value)
```

Multi-expression lambda bodies use `let` bindings:

```elixir
fn x ->
  let y = x + 1
  let z = y * 2
  z
```

**Common mistake:** `fn -> expr` is a parse error. Zero-arg lambdas require `fn () -> expr`.

---

## If / Else

```elixir
if x > 0 do
  "positive"
else
  "non-positive"
end
```

`else` is optional (returns `()` if omitted):

```elixir
if debug_mode do
  println("debug info")
end
```

Both branches can contain multiple expressions:

```elixir
if List.is_empty(xs) do
  let msg = "list is empty"
  println(msg)
else
  let first = head(xs)
  println("first: " ++ to_string(first))
end
```

There is no `then` keyword in March.

---

## Match

Pattern matching is the primary control flow construct:

```elixir
match xs do
  Nil        -> "empty"
  Cons(h, _) -> "starts with " ++ to_string(h)
end
```

Arms are separated by newlines (or `|`). Multi-expression arms:

```elixir
match result do
  Ok(v) ->
    let s = to_string(v)
    println("success: " ++ s)
  Err(e) ->
    println("error: " ++ e)
end
```

Guards with `when`:

```elixir
match n do
  x when x > 100 -> "big"
  x when x > 0   -> "small"
  _               -> "non-positive"
end
```

Pattern-free multi-way conditional (cond):

```elixir
match do
  score >= 90 -> "A"
  score >= 80 -> "B"
  score >= 70 -> "C"
  _           -> "F"
end
```

---

## With Expressions

`with` chains `Result`/`Option` bindings — short-circuits on failure:

```elixir
with Ok(user) <- fetch_user(id),
     Ok(data) <- fetch_data(user.token) do
  process(user, data)
else
  Err(e) -> handle_error(e)
end
```

Each `pat <- expr`: if `expr` matches `pat`, continue; otherwise fall through to `else` (or propagate the non-matching value).

---

## Pipe Operator

`|>` threads the left value as the first argument of the right expression:

```elixir
[1, 2, 3, 4, 5]
|> List.filter(fn x -> x % 2 == 0)
|> List.map(fn x -> x * x)
|> List.fold(0, fn acc x -> acc + x)
```

Equivalent to:
```elixir
List.fold(
  List.map(
    List.filter([1, 2, 3, 4, 5], fn x -> x % 2 == 0),
    fn x -> x * x),
  0,
  fn acc x -> acc + x)
```

The pipe version reads left-to-right and matches the mental model.

---

## Tuples

```elixir
let pair  = (1, "hello")        -- (Int, String)
let triple = (1, 2.0, true)     -- (Int, Float, Bool)
let unit  = ()                  -- ()
```

Destructure in patterns:

```elixir
let (a, b) = pair
```

---

## Lists

```elixir
let empty = []
let nums  = [1, 2, 3]           -- sugar for Cons(1, Cons(2, Cons(3, Nil)))
let more  = Cons(0, nums)       -- [0, 1, 2, 3]
```

List comprehensions:

```elixir
[x * 2 for x in [1, 2, 3]]               -- [2, 4, 6]
[x for x in nums, x % 2 == 0]            -- even numbers only
[to_string(x) for x in [1, 2, 3]]        -- ["1", "2", "3"]
```

---

## Records

Define a record type:

```elixir
type Point = { x : Float, y : Float }
type User  = { name : String, age : Int, admin : Bool }
```

Create a record:

```elixir
let p = { x = 1.0, y = 2.0 }
let u = { name = "Alice", age = 30, admin = false }
```

Access fields:

```elixir
p.x         -- 1.0
u.name      -- "Alice"
```

Functional update (returns a new record with some fields changed):

```elixir
let p2 = { p with x = 5.0 }
let u2 = { u with age = 31, admin = true }
```

---

## Typed Holes

A `?` anywhere in an expression is a typed hole. The compiler reports what type it expects:

```elixir
fn mystery(xs : List(Int)) : Int do
  List.fold(xs, ?, fn acc x -> acc + x)
  -- error: hole of type Int
end
```

Named holes `?name` for documentation:

```elixir
fn process(x) do
  ?todo_implement_this
end
```

---

## Block Expressions

`do ... end` is an expression that evaluates its body and returns the last value:

```elixir
let result = do
  let a = compute_a()
  let b = compute_b(a)
  a + b
end
```

---

## Docstrings

Attach documentation to any definition:

```elixir
doc "Returns the absolute value of n."
fn abs(n : Int) : Int do
  if n < 0 do -n else n end
end
```

Multi-line docs:

```elixir
doc """
Splits a string by the given delimiter.

Returns a list of substrings. If the delimiter does not
appear, returns a list containing the original string.
"""
fn split(s : String, delim : String) : List(String) do
  -- ...
end
```

---

## Testing

March has built-in test syntax:

```elixir
test "addition is commutative" do
  assert (1 + 2 == 2 + 1)
end

describe "list operations" do
  test "map preserves length" do
    let xs = [1, 2, 3]
    assert (List.length(List.map(xs, fn x -> x * 2)) == 3)
  end

  test "filter reduces length" do
    let xs = [1, 2, 3, 4, 5]
    assert (List.length(List.filter(xs, fn x -> x > 3)) == 2)
  end
end
```

Run with:
```sh
dune exec forge -- test
```

---

## Next Steps

- [Type System](types.md) — algebraic data types and generics in depth
- [Pattern Matching](pattern-matching.md) — exhaustiveness, guards, nested patterns
- [Modules](modules.md) — organizing code across files
- [Actors](actors.md) — concurrent programming
