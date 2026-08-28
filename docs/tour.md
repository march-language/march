---
layout: docs
title: Language Tour
nav_order: 4
permalink: /docs/tour/
---

# Language Tour

A fast walkthrough of March syntax and core concepts. Every snippet is valid March.

---

## Comments

```march
-- this is a line comment

{- this is a block comment
   {- they nest -}
-}
```

---

## Modules

Every March file begins with exactly one module declaration:

```march
mod MyApp do
  -- everything goes here
end
```

Modules can be dotted (for multi-file projects):

```march
mod MyApp.Router do
  -- ...
end
```

Modules can be nested:

```march
mod Outer do
  mod Inner do
  needs IO.Console
    fn greet() do println("from Inner") end
  end
end
```

---

## Variables

`let` binds a name in the current block. No `in` is needed; subsequent expressions in the block see the binding:

```march
fn main() do
  let x = 42
  let y = x + 1
  println(String.from_int(y))   -- 43
end
```

Type annotations are optional:

```march
let count : Int = 0
let name : String = "March"
```

Module-level `let` defines constants:

```march
mod Config do
  let max_retries = 3
  let base_url = "https://example.com"
end
```

### Result propagation with `let?`

`let? p = e` binds the `Ok` payload of a `Result` and automatically propagates `Err` upward: the function returns the error immediately without touching the rest of the block:

```march
fn parse_and_add(a : String, b : String) : Result(Int, String) do
  let? x = String.to_int(a)   -- returns Err(msg) if String.to_int fails
  let? y = String.to_int(b)   -- only reached when x succeeded
  Ok(x + y)
end
```

The equivalent without `let?` is:

```march
fn parse_and_add(a : String, b : String) : Result(Int, String) do
  match String.to_int(a) do
    Err(e) -> Err(e)
    Ok(x)  ->
      match String.to_int(b) do
        Err(e) -> Err(e)
        Ok(y)  -> Ok(x + y)
      end
  end
end
```

Rules:
- The right-hand side must be `Result(T, E)`.
- All `let?` bindings in a block must share the same error type `E`.
- `let?` cannot be the last expression in a block; something must follow it.

`let?` works anywhere a `let` binding is valid: function bodies, match arms, and lambda bodies.

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

```march
let sum = 1.0 +. 2.5    -- Float +
let diff = 3.0 -. 1.5   -- Float -
let prod = 2.0 *. 4.0   -- Float *
let quot = 9.0 /. 3.0   -- Float /
```

Integer arithmetic uses the plain operators: `+`, `-`, `*`, `/`, `%`.

---

## Strings

Concatenate with `++`:

```march
let greeting = "Hello, " ++ "World!"
```

String interpolation with `${}`:

```march
let name = "Alice"
let msg = "Hello, ${name}!"   -- "Hello, Alice!"
```

Triple-quoted strings preserve newlines:

```march
let html = """
  <div>
    <p>Hello</p>
  </div>
"""
```

Useful conversions live on the `String` module: `String.from_int`,
`String.from_float`, and `to_string` (the generic `Show` renderer for any type).

> The prelude also exposes bare aliases for the common conversions
> (`int_to_string`, `float_to_string`, `string_to_int`, `string_length`), which are
> the same functions as `String.from_int`, `String.from_float`, `String.to_int`,
> and `String.byte_size`. This guide uses the `String.*` module forms throughout;
> the bare names are interchangeable if you prefer them.

---

## Functions

Named functions use `fn name(params) do ... end`:

```march
fn add(x : Int, y : Int) : Int do
  x + y
end
```

Return type annotation is optional:

```march
fn square(n) do
  n * n
end
```

Functions can have multiple expressions in the body; the last one is the return value:

```march
fn summarize(xs : List(Int)) : String do
  let n   = List.length(xs)
  let sum = List.fold_left(xs, 0, fn (acc, x) -> acc + x)
  "count=" ++ String.from_int(n) ++ " sum=" ++ String.from_int(sum)
end
```

### Private Functions

Use `pfn` to make a function private to its module:

```march
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

```march
fn greet(name, greeting \\ "Hello") do
  greeting ++ ", " ++ name ++ "!"
end

greet("World")          -- "Hello, World!"
greet("World", "Hi")    -- "Hi, World!"
```

All defaulted parameters must be trailing.

### Multi-Head Functions

Consecutive clauses with the same name are merged into a single function with pattern dispatch (Elixir-style):

```march
fn len(Nil) do 0 end
fn len(Cons(_, t)) do 1 + len(t) end
```

```march
fn abs(n) when n < 0 do -n end
fn abs(n) do n end
```

---

## Lambdas

Lambdas use arrow syntax: `fn params -> body`.

```march
fn x -> x + 1                -- single param
fn (a, b) -> a + b           -- multiple params (parenthesized)
fn -> 42                     -- zero-arg (short form)
fn () -> 42                  -- zero-arg (explicit form, identical)
fn _ -> "ignored"            -- wildcard (1-arg, discards the value)
```

Multi-expression lambda bodies use `let` bindings:

```march
fn x ->
  let y = x + 1
  let z = y * 2
  z
```

**Note:** `fn _` is a *one-argument* lambda that discards its argument, not zero-arg. Calling `fn _ -> 42` with no arguments is an arity error.

---

## If / Else

```march
if x > 0 do
  "positive"
else
  "non-positive"
end
```

`else` is mandatory; an `if` without `else` is a parse error ("March `if` expressions always need an `else` branch").

Both branches can contain multiple expressions:

```march
if List.is_empty(xs) do
  let msg = "list is empty"
  println(msg)
else
  let first = head(xs)
  println("first: " ++ to_string(first))
end
```

There is no `then` keyword in March; `if c then e1 else e2` is rejected with "I don't recognize `then` here — March uses do/end blocks instead."

> **Prefer [`match`](#match) for anything beyond a single two-way choice.** `if`/`else` is fine for one boolean condition, but pattern matching is March's primary control-flow construct: it branches on multiple cases and destructures data, checked for exhaustiveness by the compiler.

---

## Match

Pattern matching is the primary control flow construct:

```march
match xs do
  Nil        -> "empty"
  Cons(h, _) -> "starts with " ++ to_string(h)
end
```

Arms are separated by newlines (or `|`). Multi-expression arms:

```march
match result do
  Ok(v) ->
    let s = to_string(v)
    println("success: " ++ s)
  Err(e) ->
    println("error: " ++ e)
end
```

Guards with `when`:

```march
match n do
  x when x > 100 -> "big"
  x when x > 0   -> "small"
  _               -> "non-positive"
end
```

Pattern-free multi-way conditional (cond):

```march
match do
  score >= 90 -> "A"
  score >= 80 -> "B"
  score >= 70 -> "C"
  _           -> "F"
end
```

---

## With Expressions

`with` chains `Result`/`Option` bindings; it short-circuits on failure:

```march
with Ok(user) <- fetch_user(id),
     Ok(data) <- fetch_data(user.token) do
  process(user, data)
else
  Err(e) -> handle_error(e)
end
```

Each `pat <- expr`: if `expr` matches `pat`, continue; otherwise fall through to `else` (or propagate the non-matching value).

`let?` is a lighter-weight alternative when every binding propagates the same `Err` type and you don't need a custom `else` handler:

```march
fn load(id : Int) : Result(String, DbError) do
  let? user = fetch_user(id)
  let? data = fetch_data(user.token)
  Ok(process(user, data))
end
```

Use `with` when you need `else` handlers or mixed `Option`/`Result` patterns. Use `let?` when you only need uniform `Err` propagation.

---

## Pipe Operator

`|>` threads the left value as the first argument of the right expression:

```march
[1, 2, 3, 4, 5]
|> List.filter(fn x -> x % 2 == 0)
|> List.map(fn x -> x * x)
|> List.fold_left(0, fn (acc, x) -> acc + x)
```

Equivalent to:
```march
List.fold_left(
  List.map(
    List.filter([1, 2, 3, 4, 5], fn x -> x % 2 == 0),
    fn x -> x * x),
  0,
  fn (acc, x) -> acc + x)
```

The pipe version reads left-to-right and matches the mental model.

---

## Tuples

```march
let pair  = (1, "hello")        -- (Int, String)
let triple = (1, 2.0, true)     -- (Int, Float, Bool)
let unit  = ()                  -- ()
```

Destructure in patterns:

```march
let (a, b) = pair
```

---

## Lists

```march
let empty = []
let nums  = [1, 2, 3]           -- sugar for Cons(1, Cons(2, Cons(3, Nil)))
let more  = Cons(0, nums)       -- [0, 1, 2, 3]
```

List comprehensions:

```march
[x * 2 for x in [1, 2, 3]]               -- [2, 4, 6]
[x for x in nums, x % 2 == 0]            -- even numbers only
[to_string(x) for x in [1, 2, 3]]        -- ["1", "2", "3"]
```

---

## Records

Define a record type:

```march
type Point = { x : Float, y : Float }
type User  = { name : String, age : Int, admin : Bool }
```

Create a record:

```march
let p = { x: 1.0, y: 2.0 }
let u = { name: "Alice", age: 30, admin: false }
```

Access fields:

```march
p.x         -- 1.0
u.name      -- "Alice"
```

Functional update (returns a new record with some fields changed):

```march
let p2 = { p with x: 5.0 }
let u2 = { u with age: 31, admin: true }
```

---

## Typed Holes

A `?` anywhere in an expression is a typed hole. The compiler reports what type it expects:

```march
fn mystery(xs : List(Int)) : Int do
  List.fold_left(xs, ?, fn (acc, x) -> acc + x)
  -- hint: Typed hole ? has type `u2`
end
```

Named holes `?name` for documentation:

```march
fn process(x) do
  ?todo_implement_this
end
```

---

## Block Expressions

`do ... end` is an expression that evaluates its body and returns the last value:

```march
let result = do
  let a = compute_a()
  let b = compute_b(a)
  a + b
end
```

---

## Docstrings

Attach documentation to any definition:

```march
doc "Returns the absolute value of n."
fn abs(n : Int) : Int do
  if n < 0 do -n else n end
end
```

Multi-line docs:

```march
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

```march
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
forge test
```

---

## Next Steps

**Ready to build something?** → [Build a CLI Tool](/docs/build-a-cli/) goes start-to-finish, and the [Cookbook](/docs/cookbook/) has goal-oriented recipes.

Go deeper:

- [Type System](types.md): algebraic data types and generics in depth
- [Pattern Matching](pattern-matching.md): exhaustiveness, guards, nested patterns
- [Modules](modules.md): organizing code across files
- [Actors](actors.md): concurrent programming, and the jumping-off point for supervision, clustering, and hot code reload

March's compile-time safety goes further than a standard ML-family type system:

- [Interfaces](interfaces.md): ad-hoc polymorphism with `interface`/`impl`
- [Linear Types](linear-types.md): resources the compiler proves are used exactly once, at zero runtime cost
- [Refinement Types](refinement-types.md): value predicates (`{Int | _ >= 0}`) checked by an SMT solver
- [Capabilities](capabilities.md): IO permissions tracked in the type system
- [Safety by Construction](safety-by-construction.md): how these layers compose on one function
- [Memory Model](memory-model.md): why March has no garbage collector or pauses
- [Sigils & Templating](sigils.md): `~H` HTML templates and the general `~Name"..."` mechanism

Coming from another language? [Python](coming-from-python.md) · [TypeScript](coming-from-typescript.md) · [Haskell/Elixir/OCaml](coming-from-fp.md).
