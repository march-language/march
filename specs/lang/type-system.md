---
layout: docs
title: Type System
nav_order: 5.1
permalink: /docs/types/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).
> This chapter is the **tutorial-register companion** to
> [`core-march-types.md`](https://github.com/march-language/march/blob/main/specs/lang/core-march-types.md), which has the FORMAL typing
> rules (the `Γ ⊢ e : τ` judgment, cited arm-for-arm against
> `lib/typecheck/typecheck.ml`) for the core fragment: literals, `let`,
> lambda/application, `if`, ADT constructors and `match`, tuples/records,
> atoms, guards, and interface-constraint discharge (`Num`/`Eq`/`Ord`/`Show`).
> Where this chapter and `core-march-types.md` cover the same ground, this
> chapter teaches the surface syntax and defers the "why is this well-typed"
> rules to the formal reference rather than restating them.

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
  Circle(Float)
  | Rect(Float, Float)
  | Triangle(Float, Float, Float)
```

Constructors are capitalized. They can carry zero or more fields:

```march
type Expr =
  Num(Int)
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
let p = { x: 1.0, y: 2.0 }
let moved = { p with x: 5.0 }
let dist = p.x +. p.y
```

Records and variants can be combined; a variant constructor can carry a record:

```march
type Config =
  Default
  | Custom({ host : String, port : Int, debug : Bool })
```

---

## Working with Records

Update fields with `{ base with field: value }`: this creates a new record; the original is unchanged:

```march
let p2 = { p with x: 5.0 }  -- new Point, y unchanged
let u2 = { u with age: 31 } -- new User, name/email unchanged
```

**Record patterns are not yet supported by the parser** (`{ x, y } -> ...` in
a `match` is a parse error); use field access in a guard instead. See
[Pattern Matching](pattern-matching.md#record-patterns) for the workaround.

---

## Atoms

An atom is a named constant with a value that is its own name. Atoms are written with a leading colon:

```march
:ok
:error
:pending
:one_for_one
```

Atoms are commonly used as tags in supervision strategies, HTTP methods, and
protocol states: an `Atom`-typed value that stores one of a few expected
names:

```march
fn describe(status : Atom) : String do
  match status do
    :ok      -> "success"
    :error   -> "failure"
    :pending -> "in progress"
    _        -> "unknown"
  end
end
```

All atom literals share the single type `Atom`: `:ok` and `:oke` (a typo)
both typecheck fine as `Atom`, so a misspelled atom is **not** caught at the
type level (unlike a misspelled ADT constructor, which is a compile error).
See `core-march-types.md` §2.2 (P-Atom) for the formal rule: an atom pattern's
type is the bare, tag-erased `Atom` regardless of the atom's name or payload
arity.

The grammar also accepts atoms as variant-constructor names in a `type`
declaration (`type Status = :ok | :error | :pending`, parsed the same as
`:ok(String)`-style payload variants); but, verified live 2026-07-22, this
does not build a nominal sum type the way an `UPPER_IDENT`-constructor
`type` does: a binding annotated `: Status` cannot be constructed or matched
with `:ok`-style syntax (`` expected `Status` but got `Atom` ``), because
`:ok` in expression/pattern position always denotes the one ambient `Atom`
type, and match exhaustiveness against such a `type` declaration is not
enforced: a `match` over an atom value still needs its own `_` catch-all
regardless of what `type` declarations exist. Prefer plain ADTs
(capitalized constructors) when you want an actual closed, exhaustively-
checked sum type; reserve atoms for open-ended tags as shown above.

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
map_option(Some(42), fn x -> x * 2)     -- Option(Int)
map_option(Some("hi"), String.byte_size) -- Option(Int) — there is no `String.length`
```

---

## Type Aliases

Give a type a shorter name:

```march
type Name = String
type Age  = Int
type DB   = Map(String, List(Int))
```

A type alias expands to its definition, so a value declared as the alias can be
used where the underlying type is expected, e.g. a `Name` flows into a function
taking a `String`. The reverse is not always accepted: passing a bare `String`
where the alias `Name` is expected can be rejected, so don't rely on aliases
being freely interchangeable in both directions. Use aliases for readability,
not as a substitute for a distinct wrapper type.

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
Option.flat_map(opt, fn x -> ...)   -- flatMap (not `and_then` — no such function)
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
  Option.to_result(string_to_int(s), "not a valid integer")
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
Result.map_err(Err("x"), String.to_uppercase)
Result.flat_map(res, fn v -> ...)      -- flatMap (not `and_then` — no such function)
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
  let? raw = File.read(path)          -- unwrap or propagate Err
  let? cfg = parse_config(raw)        -- unwrap or propagate Err (your own parser)
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

**There is no postfix `?` unwrap operator on arbitrary expressions** (e.g.
`f()?`); only the `let?` binding form above exists. A bare `?` in expression
position is a distinct, unrelated feature (a typed hole for
incomplete-program tooling), not an unwrap shorthand; see
[`let-propagation.md`](https://github.com/march-language/march/blob/main/specs/lang/let-propagation.md) §12 for the full list of
intentionally out-of-scope `let?`-adjacent forms, including postfix `?`.

`let?` only works with `Result(a, e)`. For `Option(a)`, use `match` or the
`with` construct (or convert first with `Option.to_result`).

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
Http.Request(String)  -- Request is generic over its body type
Http.Method
```

---

## Dependent Types

A **dependent type** is a type that depends on a *value*, not just on other
types. March has two flavours, each with different trade-offs.

### Refinement Types: value predicates

A **refinement type** `{T | predicate}` constrains what values a type can hold.
The predicate is checked by an SMT solver (Z3) at compile time, so a whole
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
when the predicate can *never* hold, never for unknown or possibly-valid
values. This means no false positives, but also no proof obligation: if the
solver can't decide, it stays silent.

```march
fn f(n : Int) : Int do
  chunks(data, n)    -- skipped: n could be positive, compiler doesn't know
end
```

Refinements support **path sensitivity**: a guard you write becomes an
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

For predicates over data structures, define a **`@[measure]`**: a total,
terminating function the solver axiomatises by structure:

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

### Type-Level Naturals: dimension constraints

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

This is resolved entirely during type inference; no Z3 involved. It is
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

Outside `Token`, callers can use `Token` as a type but cannot construct or pattern-match it directly, only through the module's public API.

For completely hidden types, use `ptype`:

```march
ptype Internal = Foo | Bar(Int)
-- Both the type name and constructors are private
```

---

## Operator Reference

| Operator | Types | Description |
|----------|-------|-------------|
| `+` `-` `*` `/` | any `Num` (`Int` or `Float`) | Arithmetic: polymorphic, works on either |
| `%` | `Int` | Integer modulo (monomorphic, `Int` only) |
| `+.` `-.` `*.` `/.` | `Float` | Float arithmetic (monomorphic, `Float` only) |
| `==` `!=` | any `Eq` | Equality / inequality |
| `<` `>` `<=` `>=` | any `Ord` (`Int`, `Float`, `String`) | Ordering |
| `&&` `\|\|` `!` | `Bool` | Boolean and / or / not |
| `++` | `String` | String concatenation |
| `\|>` | any | Pipe: `x \|> f` is `f(x)` |

**`+` `-` `*` `/` are `Num`-polymorphic: they work on both `Int` and `Float`
without a dot suffix.** The dot-suffixed forms (`+.` etc.) are the
*monomorphic* Float-only versions, useful when you want to pin a type down;
they reject an `Int` operand rather than converting it. `%` has no dot form
and is `Int`-only in both directions:

```march
let a = 1.5 +. 2.5   -- Float: correct (monomorphic +.)
let b = 1.5 + 2.5    -- Float: also correct — + is Num-polymorphic, not Int-only
let c = 1 +. 2       -- type error: +. is Float-only, rejects Int operands
let d = 1.5 % 2.0     -- type error: % is Int-only, rejects Float operands
```

The pipe operator chains transformations left-to-right:

```march
[1, 2, 3, 4, 5]
  |> List.filter(fn x -> x % 2 == 0)
  |> List.map(fn x -> x * x)
  |> List.fold_left(0, fn (acc, x) -> acc + x)
-- evaluates to 20
```

---

## Which Safety Tool for Which Job

March gives you many ways to make illegal states unrepresentable. Choose by **the
guarantee you want**, not by the feature name. This table is keyed on the
guarantee:

| Guarantee you want | Reach for | Checked by | Granularity |
|--------------------|-----------|------------|-------------|
| A value stays in a numeric/logical range (`>= 0`, `!= 0`, `< len`) | Refinement `{T \| pred}` | SMT solver (Z3), compile time | Per value |
| A dimension/length matches across values | Type-level natural `Vector(n, a)` | Type inference, compile time | Per value |
| A value can only be built through a vetted constructor | Smart-constructor / opaque `ptype` | Type checker (private constructor) | Per value |
| Validate data with a shape that isn't known until runtime | Runtime validator returning `Result` | Your code, run time | Per value |
| A resource is used the right number of times | `linear` (exactly once) / `affine` (at most once) | Type checker, compile time | Per value |
| A resource is used in the right order (open → read → close) | Typestate (`always_linear type` + `transitions`) | Type checker, compile time | Per value |
| Code may only touch resources it was granted | Capability `needs` / `Cap(X)` | Type checker (transitive), compile time | Per module / call |
| A two-party conversation follows a protocol | Session type `protocol` + `Chan` | Type checker, compile time | Per channel |

### Two confusable pairs

**Refinement vs. smart-constructor.** A refinement `{Int | _ > 0}` checks a
*predicate the solver can read* every time the value flows into a refined
position, great for arithmetic ranges and bounds. A smart-constructor (`ptype`
with a private constructor) enforces an invariant the solver *can't* express
(`Email` is well-formed, `Sanitized` has been escaped): the only way to get the
type is to go through the function that establishes the invariant. Use a
refinement when the property is arithmetic; use a smart-constructor when it's
structural or semantic.

**Refinement vs. runtime validator.** They live at different boundaries:
**refine internals, validate untrusted input at the edge.** A refinement is a
*static* contract between functions you control; it disappears at runtime. A
runtime validator returning `Result` is for data crossing a trust boundary (a
request body, a file, a CLI argument) where you truly don't know the value
until it arrives. Validate once at the edge, then carry the proof inward as a
smart-constructor or a refined type.

See [Safety by Construction](safety-by-construction.md) for one function that
threads capability, typestate, and refinement together.

---

## What's Inferred, What You Must Write

March's rule of thumb: **it infers structure (facts it can read off your code)
and asks you to declare claims (constraints, predicates, and effects it must
verify against your code).**

| | What March does | Examples |
|---|---|---|
| **Inferred** (you write no annotation) | Reconstructed from the code | Types of `let` locals; lambda parameter types; generic instantiation at call sites |
| **Optional** (write for docs/clarity) | Inferred, but you may pin it | Function parameter and return signatures |
| **NOT inferred** (you declare, compiler verifies) | A claim the compiler checks but won't guess | Interface constraints (`when Ord(a)`); refinement predicates (`{Int \| _ >= 0}`); capabilities (`needs IO.FileRead`) |

The imbalance is intentional. A *fact* like "this local is an `Int`" the compiler
can simply read off the expression. A *claim* like "this argument is always
positive" or "this module may read files" is a contract you're asserting: the
compiler can't invent the contract for you, but once you state it, it commits you
(and your callers) to it.

---

## What the Type System Buys at Runtime

The static guarantees aren't just for catching bugs: they let the compiler
*delete* runtime apparatus that dynamic languages pay for on every call:

- **Whole-program monomorphization → no dynamic dispatch.** Generic code is
  specialized to concrete types, so interface calls become direct calls with no
  vtable lookup. (See [memory model](memory-model.md).)
- **Defunctionalization → no heap closures.** Higher-order functions are compiled
  to plain tagged data and a dispatch, so passing a lambda doesn't allocate a
  closure object on the heap. (See [memory model](memory-model.md).)
- **Immutable by default → no write barriers.** Pointer fields are never written
  after construction, so there's no GC write barrier on the common path. (See
  [memory model](memory-model.md).)
- **Linear / affine → static free.** Values with statically known lifetimes get a
  compiler-inserted `free` at last use, no reference-count bookkeeping at all.
  (See [memory model](memory-model.md).)

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

- [Pattern Matching](pattern-matching.md): destructuring all these types
- [Linear Types](linear-types.md): ownership and resource safety
- [Refinement Types](refinement-types.md): types that carry a predicate (`{Int | _ >= 0}`), checked by an SMT solver
- [Interfaces](interfaces.md): ad-hoc polymorphism with `interface`/`impl`
