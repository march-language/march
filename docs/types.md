---
layout: page
title: Type System
nav_order: 5
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

Chain with `with`:

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

## Type-Level Naturals (Sized Arrays)

March supports `Nat` in type parameters for compile-time dimension checking:

```march
type Vector(n, a) = Vector(Array(a))
type Matrix(m, n, a) = Matrix(Array(Array(a)))
```

Arithmetic on type-level naturals:

```march
type Doubled(n, a) = Array(n * 2, a)
```

This enables functions like `zip` that guarantee equal-length inputs:

```march
fn zip_vectors(v1 : Vector(n, a), v2 : Vector(n, b)) : Vector(n, (a, b)) do
  -- compiler verifies n is the same for both inputs
  ...
end
```

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
└── Stdlib: List(a), Option(a), Result(a,e), Map(k,v), ...
```

---

## Next Steps

- [Pattern Matching](pattern-matching.md) — destructuring all these types
- [Linear Types](linear-types.md) — ownership and resource safety
- [Interfaces](interfaces.md) — ad-hoc polymorphism with `interface`/`impl`
