---
layout: docs
title: Type System
nav_order: 5
permalink: /docs/types/
---

# Type System

March uses Hindley-Milner type inference with bidirectional checking at function boundaries. You get the convenience of inferred types with the safety of static checking.

---

## Primitive Types

| Type | Description | Literals |
|------|-------------|---------|
| `Int` | 64-bit signed integer | `42`, `-7`, `0` |
| `Float` | 64-bit IEEE 754 | `3.14`, `-0.5`, `1.0e10` |
| `Bool` | Boolean | `true`, `false` |
| `String` | UTF-8 string | `"hello"` |
| `Char` | Unicode scalar value | (accessed via String operations) |
| `()` | Unit (no value) | `()` |

---

## Type Annotations

Annotations are optional everywhere except:
- Recursive functions where inference would loop
- When you want explicit documentation

```march
fn add(x : Int, y : Int) : Int do
  x + y
end

-- Equally valid — fully inferred:
fn add(x, y) do x + y end
```

Parameter and return annotations use `:`:
```march
let count : Int = 0
fn process(data : List(String)) : Option(Int) do ... end
```

---

## Algebraic Data Types (ADTs)

### Sum Types (Variants)

Variants declare a type with multiple possible shapes. No leading `|` on the first case:

```march
type Color = Red | Green | Blue

type Shape =
  | Circle(Float)
  | Rect(Float, Float)
  | Triangle(Float, Float, Float)
```

Constructors are capitalized. They can carry zero or more fields:

```march
type Expr =
  | Num(Int)
  | Add(Expr, Expr)
  | Mul(Expr, Expr)
  | Neg(Expr)
```

Use constructors by applying them like functions:

```march
let c = Circle(3.14)
let r = Rect(4.0, 6.0)
let e = Add(Num(1), Mul(Num(2), Num(3)))
```

### Record Types

Records have named fields:

```march
type Point = { x : Float, y : Float }
type User  = { name : String, age : Int, email : String }
```

Create, access, and update:

```march
let p = { x = 1.0, y = 2.0 }
let moved = { p with x = 5.0 }
let dist = p.x +. p.y
```

Records and variants can be combined — a variant constructor can carry a record:

```march
type Config =
  | Default
  | Custom({ host : String, port : Int, debug : Bool })
```

---

## Records

Record types group named fields into a single value. Define them with curly-brace syntax:

```march
type Point = { x : Float, y : Float }
type User  = { name : String, age : Int, active : Bool }
```

Create a record by supplying all fields:

```march
let p = { x = 1.0, y = 2.0 }
let u = { name = "Alice", age = 30, active = true }
```

Access fields with `.`:

```march
let dist = p.x +. p.y
```

Update fields with `{ base with field = value }` — this creates a new record; the original is unchanged:

```march
let p2 = { p with x = 5.0 }       -- new Point, y unchanged
let u2 = { u with active = false } -- deactivate user
```

Destructure records in patterns:

```march
match p do
  { x, y } -> x +. y
end
```

Records and sum types can be combined — a sum type constructor can carry a record payload:

```march
type Shape =
  | Circle({ radius : Float })
  | Rect({ width : Float, height : Float })
```

---

## Atoms

An atom is a named constant whose value is its own name. Atoms are written with a leading colon:

```march
:ok
:error
:pending
:one_for_one
```

Atoms are commonly used as tags in sum types, supervision strategies, HTTP methods, and protocol states:

```march
type Status = :ok | :error | :pending

match status do
  :ok      -> "success"
  :error   -> "failure"
  :pending -> "in progress"
end
```

Each atom literal has its own distinct type, so the compiler catches typos at the type level.

---

## Type Parameters (Generics)

Type parameters are lowercase:

```march
type Option(a) = None | Some(a)
type Result(a, e) = Ok(a) | Err(e)
type Pair(a, b) = Pair(a, b)
type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))
```

Use the same lowercase letters in function signatures to refer to type parameters:

```march
fn identity(x : a) : a do x end

fn map_option(opt : Option(a), f : a -> b) : Option(b) do
  match opt do
    None    -> None
    Some(x) -> Some(f(x))
  end
end
```

The compiler infers type parameter instantiations at call sites:

```march
map_option(Some(42), fn x -> x * 2)  -- Option(Int)
map_option(Some("hi"), String.length) -- Option(Int)
```

---

## Type Aliases

Give a type a shorter name:

```march
type Name = String
type Age  = Int
type DB   = Map(String, List(Int))
```

Type aliases are structural — `Name` and `String` are interchangeable.

---

## Option(a)

`Option(a)` represents a value that may or may not be present:

```march
type Option(a) = None | Some(a)
```

Standard pattern:

```march
fn safe_head(xs : List(a)) : Option(a) do
  match xs do
    Nil        -> None
    Cons(h, _) -> Some(h)
  end
end
```

Stdlib helpers (from prelude, always in scope):

```march
unwrap(Some(42))           -- 42 (panics if None)
unwrap_or(None, 0)         -- 0
```

From `Option` module:

```march
Option.map(Some(5), fn x -> x + 1)  -- Some(6)
Option.and_then(opt, fn x -> ...)   -- flatMap
Option.unwrap_or_else(opt, fn () -> compute_default())
Option.is_some(opt)
Option.is_none(opt)
```

---

## Result(a, e)

`Result(a, e)` represents either success or failure:

```march
type Result(a, e) = Ok(a) | Err(e)
```

Functions that can fail return `Result`:

```march
fn parse_int(s : String) : Result(Int, String) do
  -- returns Ok(n) or Err("not a valid integer")
  parse_int_builtin(s)
end
```

Chain multiple fallible operations with `let?` (propagates `Err` automatically):

```march
fn run(input : String) : Result(String, String) do
  let? n    = parse_int(input)
  let? user = fetch_user(n)
  Ok(display(user))
end
```

Use `with` when you need custom `else` handling or mixed `Option`/`Result` chains (the `with` construct is covered in the Pattern Matching page; it short-circuits on non-matching patterns):

```march
with Ok(n)    <- parse_int(input),
     Ok(user) <- fetch_user(n) do
  display(user)
else
  Err(e) -> println("Error: " ++ e)
end
```

Stdlib helpers:

```march
Result.map(Ok(5), fn x -> x + 1)     -- Ok(6)
Result.map_err(Err("x"), String.upcase)
Result.and_then(res, fn v -> ...)      -- flatMap
Result.unwrap(Ok(42))                  -- 42
Result.unwrap_or(Err("e"), 0)          -- 0
Result.is_ok(res)
Result.is_err(res)
```

---

## The `let?` Operator

`let?` is syntactic sugar for unwrapping a `Result` and propagating errors automatically. Inside a function that returns `Result`, `let?` saves you from writing nested `match` expressions:

```march
fn load_config(path : String) : Result(Config, String) do
  let? raw  = File.read(path)         -- unwrap or propagate Err
  let? text = Utf8.decode(raw)        -- unwrap or propagate Err
  let? cfg  = Config.parse(text)      -- unwrap or propagate Err
  Ok(cfg)
end
```

Each `let? x = expr` desugars to:

```march
match expr do
  Ok(x)  -> <rest of function>
  Err(e) -> Err(e)    -- early return, propagating the error
end
```

The `?` postfix operator is the expression-level equivalent — use it to unwrap inline:

```march
let cfg = Config.parse(File.read(path)?)?   -- chain unwraps
```

`let?` and `?` only work with `Result(a, e)`. For `Option(a)`, use `match` or the `with` construct.

---

## Tuples

Tuples are anonymous ordered products:

```march
let pair : (Int, String) = (1, "hello")
let triple : (Int, Float, Bool) = (1, 2.0, true)
let unit : () = ()
```

Destructure with `let` or pattern matching:

```march
let (a, b) = pair
match triple do
  (n, f, b) -> ...
end
```

---

## Lists

`List(a)` is a singly-linked cons list:

```march
type List(a) = Nil | Cons(a, List(a))
```

List literals desugar to `Cons` chains:

```march
[1, 2, 3]   -- Cons(1, Cons(2, Cons(3, Nil)))
[]          -- Nil
```

---

## Function Types

Function types are written with `->`, right-associative:

```march
Int -> Bool          -- takes Int, returns Bool
Int -> Int -> Int    -- curried: takes Int, returns (Int -> Int)
(Int, Int) -> Int    -- takes a pair
```

Higher-order functions:

```march
fn apply(f : Int -> Int, x : Int) : Int do f(x) end
fn compose(f : b -> c, g : a -> b) : a -> c do
  fn x -> f(g(x))
end
```

---

## Qualified Types

Types from modules are accessed with `.`:

```march
Http.Request
Map.Entry(String, Int)
```

---

## Dependent Types

A **dependent type** is a type that depends on a *value* — not just on other
types. March has two flavours, each with different trade-offs.

### Refinement Types — value predicates

A **refinement type** `{T | predicate}` constrains what values a type can hold.
The predicate is checked by an SMT solver (Z3) at compile time — so a whole
class of bugs (negative sizes, out-of-bounds indices, division by zero) becomes
a compile error instead of a runtime panic.

```march
-- Precondition: callers must pass a positive chunk size
fn chunks(xs : List(a), size : {Int | _ > 0}) : List(List(a)) do ... end

-- Postcondition: this function promises a non-negative count
fn count(xs : List(a)) : {Int | _ >= 0} do List.length(xs) end

chunks([1,2,3,4,5], 0)   -- compile error: 0 can never be > 0
chunks([1,2,3,4,5], 2)   -- ok
```

Checking follows **definite-failure semantics**: a diagnostic is emitted only
when the predicate can *never* hold — never for unknown or possibly-valid
values. This means no false positives, but also no proof obligation: if the
solver can't decide, it stays silent.

```march
fn f(n : Int) : Int do
  chunks(data, n)    -- skipped: n could be positive, compiler doesn't know
end
```

Refinements support **path sensitivity** — a guard you write becomes an
assumption the solver can use:

```march
fn safe_chunks(xs : List(a), n : Int) : List(List(a)) do
  if n > 0 do
    chunks(xs, n)    -- ok: the guard established n > 0
  else
    [xs]
  end
end
```

For predicates over data structures, define a **`@[measure]`** — a total,
terminating function the solver axiomatises structurally:

```march
@[measure]
fn size(t : Tree(a)) : Int do
  match t do
    Leaf          -> 0
    Node(l, _, r) -> 1 + size(l) + size(r)
  end
end

fn get(t : Tree(a), i : {Int | _ >= 0 && _ < size(t)}) : a do ... end
```

See the [Refinement Types guide](refinement-types.md) for the full syntax,
measure soundness gate, `--no-measure-axioms` flag, and limitations.

### Type-Level Naturals — dimension constraints

`Nat` in a type parameter threads a *compile-time* natural number through the
type, making shape mismatches impossible to express:

```march
type Vector(n, a) = Vector(Array(a))

fn zip_vectors(v1 : Vector(n, a), v2 : Vector(n, b)) : Vector(n, (a, b)) do
  -- the compiler verifies both arguments have the same length n
  ...
end
```

Arithmetic on naturals is supported at the type level:

```march
type Doubled(n, a) = Array(n * 2, a)
```

This is resolved entirely during type inference — no Z3 involved. It is
appropriate for **structural shape constraints** (array lengths, matrix
dimensions) where the relationship is fixed at the call site. Refinements are
appropriate for **value-range constraints** (non-negative, bounded, non-zero)
where the relationship is a predicate you want to check against a concrete
argument.

### Choosing between the two

| | Refinement types | Type-level naturals |
|---|---|---|
| Constraint kind | Value predicates (`>= 0`, `!= 0`, `< len(xs)`) | Shape/dimension equality |
| Base types | `Int`, `Bool` | `Nat` (non-negative integer) |
| Solver | Z3 SMT (optional) | Type inference (always) |
| False positives | None (definite-failure only) | None |
| HOF / dynamic dispatch | Not checked | Checked |
| Incomplete by design? | Yes | No |

---

## Opaque Types

Hide a type's representation while keeping the name usable in signatures:

```march
mod Token do
  opaque type Token = Token(String)

  fn make(s : String) : Token do Token(s) end
  fn value(t : Token) : String do
    match t do Token(s) -> s end
  end
end
```

Outside `Token`, callers can use `Token` as a type but cannot construct or pattern-match it directly — only through the module's public API.

For completely hidden types, use `ptype`:

```march
ptype Internal = Foo | Bar(Int)
-- Both the type name and constructors are private
```

---

## Operator Reference

| Operator | Types | Description |
|----------|-------|-------------|
| `+` `-` `*` `/` `%` | `Int` | Integer arithmetic |
| `+.` `-.` `*.` `/.` | `Float` | Float arithmetic (dot suffix required) |
| `==` `!=` | any `Eq` | Equality / inequality |
| `<` `>` `<=` `>=` | any `Ord` | Ordering |
| `&&` `\|\|` `!` | `Bool` | Boolean and / or / not |
| `++` | `String` | String concatenation |
| `\|>` | any | Pipe: `x \|> f` is `f(x)` |

**Float operators require the dot suffix.** Mixing `Int` operators with `Float` values is a type error:

```march
let a = 1.5 +. 2.5   -- Float: correct
let b = 1.5 + 2.5    -- type error: + is Int-only
```

The pipe operator chains transformations left-to-right:

```march
[1, 2, 3, 4, 5]
  |> List.filter(fn x -> x % 2 == 0)
  |> List.map(fn x -> x * x)
  |> List.fold_left(0, fn acc x -> acc + x)
-- evaluates to 20
```

---

## The Type Hierarchy at a Glance

```
Types
├── Primitives: Int, Float, Bool, String, ()
├── Sum types: type Foo = A | B(T) | ...
├── Record types: type Foo = { field : T, ... }
├── Generic types: type Foo(a) = ...
├── Function types: T -> U
├── Tuple types: (T, U, V)
├── Linear/affine: linear T, affine T
├── Dependent types
│   ├── Refinement types: {Int | _ >= 0}, {Int | _ != 0}
│   └── Type-level naturals: Vector(n, a), Matrix(m, n, a)
└── Stdlib: List(a), Option(a), Result(a,e), Map(k,v), ...
```

---

## Next Steps

- [Pattern Matching](pattern-matching.md) — destructuring all these types
- [Linear Types](linear-types.md) — ownership and resource safety
- [Refinement Types](refinement-types.md) — types that carry a predicate (`{Int | _ >= 0}`), checked by an SMT solver
- [Interfaces](interfaces.md) — ad-hoc polymorphism with `interface`/`impl`
