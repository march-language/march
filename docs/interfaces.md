---
layout: page
title: Interfaces
nav_order: 11
---

# Interfaces

Interfaces (typeclasses) provide ad-hoc polymorphism — the ability to write code that works for any type that satisfies a contract, without inheritance.

---

## Defining an Interface

```march
interface Show(a) do
  fn show : a -> String
end
```

An interface declares one or more function signatures that implementing types must provide.

### Default Implementations

Interfaces can provide default implementations that types inherit unless overridden:

```march
interface Eq(a) do
  fn eq  : a -> a -> Bool
  fn neq : a -> a -> Bool do
    fn x y -> !eq(x, y)
  end
end
```

Any type implementing `Eq` automatically gets `neq` for free. It only needs to implement `eq`.

### Superinterfaces

```march
interface Ord(a) requires Eq(a) do
  fn cmp : a -> a -> Int
  fn lt  : a -> a -> Bool do fn x y -> cmp(x, y) < 0 end
  fn gt  : a -> a -> Bool do fn x y -> cmp(x, y) > 0 end
  fn le  : a -> a -> Bool do fn x y -> cmp(x, y) <= 0 end
  fn ge  : a -> a -> Bool do fn x y -> cmp(x, y) >= 0 end
end
```

`Ord(a) requires Eq(a)` means any type implementing `Ord` must also implement `Eq`.

---

## Implementing an Interface

Use `impl Interface(Type) do ... end`:

```march
type Color = Red | Green | Blue

impl Show(Color) do
  fn show(c) do
    match c do
      Red   -> "Red"
      Green -> "Green"
      Blue  -> "Blue"
    end
  end
end

impl Eq(Color) do
  fn eq(a, b) do
    match (a, b) do
      (Red,   Red)   -> true
      (Green, Green) -> true
      (Blue,  Blue)  -> true
      _              -> false
    end
  end
end
```

Now you can call `show(Red)` or `eq(Red, Blue)` and the dispatch is resolved by the type.

---

## Conditional Implementations

Implement an interface for a generic type with constraints:

```march
-- Show for List(a) when a has Show
impl Show(List(a)) when Show(a) do
  fn show(xs) do
    let items = List.map(xs, fn x -> show(x))
    "[" ++ String.join(items, ", ") ++ "]"
  end
end

-- Eq for List(a) when a has Eq
impl Eq(List(a)) when Eq(a) do
  fn eq(xs, ys) do
    match (xs, ys) do
      (Nil, Nil)             -> true
      (Cons(x, xt), Cons(y, yt)) -> eq(x, y) && eq(xt, yt)
      _                      -> false
    end
  end
end
```

The compiler picks the right implementation at call sites based on the concrete type.

---

## Using Interfaces in Function Signatures

Constrain type parameters with `when`:

```march
fn print_all(xs : List(a)) : () when Show(a) do
  List.iter(xs, fn x -> println(show(x)))
end

fn sort(xs : List(a)) : List(a) when Ord(a) do
  -- implementation uses lt/gt from Ord
  Sort.timsort(xs)
end

fn unique(xs : List(a)) : List(a) when Eq(a) do
  List.dedup(xs)
end
```

Multiple constraints:

```march
fn sort_and_show(xs : List(a)) : String when Ord(a), Show(a) do
  let sorted = sort(xs)
  show(sorted)
end
```

---

## Standard Interfaces

### `Eq(a)` — Equality

```march
interface Eq(a) do
  fn eq  : a -> a -> Bool
  fn neq : a -> a -> Bool do fn x y -> !eq(x, y) end
end
```

Usage:
```march
eq(42, 42)         -- true
eq("hi", "bye")    -- false
neq(1, 2)          -- true
```

### `Ord(a)` — Ordering

```march
interface Ord(a) requires Eq(a) do
  fn cmp : a -> a -> Int   -- negative = less, 0 = equal, positive = greater
  fn lt  : a -> a -> Bool
  fn gt  : a -> a -> Bool
  fn le  : a -> a -> Bool
  fn ge  : a -> a -> Bool
end
```

Usage:
```march
cmp(1, 2)    -- -1
cmp(2, 2)    -- 0
cmp(3, 2)    -- 1
lt(1, 2)     -- true
```

### `Show(a)` — String Representation

```march
interface Show(a) do
  fn show : a -> String
end
```

Usage:
```march
show(42)      -- "42"
show(true)    -- "true"
show([1,2,3]) -- "[1, 2, 3]"  (if List has Show)
```

### `Hash(a)` — Hashing

```march
interface Hash(a) do
  fn hash : a -> Int
end
```

Required for keys in `Map` and elements in `Set`.

---

## `derive` — Automatic Implementations

For types with straightforward structure, `derive` generates implementations automatically:

```march
type Point = { x : Float, y : Float }
derive Eq, Show for Point

type Status = Active | Inactive | Suspended
derive Eq, Ord, Show, Hash for Status
```

After `derive Eq for Point`, you can use `eq` on `Point` values.

`derive` works for:
- **`Eq`** — structural equality, comparing all fields/constructors
- **`Ord`** — lexicographic ordering by fields, constructor order for variants
- **`Show`** — pretty-printed representation
- **`Hash`** — consistent hash based on structure

```march
type User = { name : String, age : Int, role : String }
derive Eq, Ord, Show, Hash for User

let u1 = { name = "Alice", age = 30, role = "admin" }
let u2 = { name = "Bob",   age = 25, role = "user" }

show(u1)       -- "{ name = \"Alice\", age = 30, role = \"admin\" }"
eq(u1, u1)     -- true
lt(u1, u2)     -- depends on lexicographic field order
```

Multiple types in one `derive`:

```march
derive Json, Eq for MyType
derive Show for Color
```

---

## A Complete Example: Implementing a Container

```march
mod MyStack do

  type Stack(a) = Stack(List(a))

  fn empty() : Stack(a) do Stack(Nil) end

  fn push(Stack(xs), x) do Stack(Cons(x, xs)) end

  fn pop(Stack(xs)) : Option((a, Stack(a))) do
    match xs do
      Nil        -> None
      Cons(h, t) -> Some((h, Stack(t)))
    end
  end

  fn size(Stack(xs)) : Int do List.length(xs) end

  impl Show(Stack(a)) when Show(a) do
    fn show(Stack(xs)) do
      let items = List.map(xs, fn x -> show(x))
      "Stack[" ++ String.join(items, ", ") ++ "]"
    end
  end

  impl Eq(Stack(a)) when Eq(a) do
    fn eq(Stack(xs), Stack(ys)) do eq(xs, ys) end
  end

end

-- Using the stack:
fn main() do
  let s0 = MyStack.empty()
  let s1 = MyStack.push(s0, 1)
  let s2 = MyStack.push(s1, 2)
  let s3 = MyStack.push(s2, 3)

  println(show(s3))   -- "Stack[3, 2, 1]"

  match MyStack.pop(s3) do
    Some((top, rest)) ->
      println("popped: " ++ int_to_string(top))
      println("remaining: " ++ show(rest))
    None ->
      println("empty stack")
  end
end
```

---

## Interface Dispatch

The compiler resolves interface dispatch at compile time (after monomorphization). There are no vtables or runtime type lookups — interface calls are direct function calls to the concrete implementation.

This means:
- Zero overhead compared to a direct call
- The compiler can inline implementations across interface boundaries
- No boxing required for primitive types

---

## Next Steps

- [Types](types.md) — types you implement interfaces for
- [Standard Library](stdlib.md) — stdlib types and their interface implementations
- [Pattern Matching](pattern-matching.md) — using `match` with interface-dispatched values
