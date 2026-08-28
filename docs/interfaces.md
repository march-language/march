---
layout: docs
title: Interfaces
nav_order: 5.3
permalink: /docs/interfaces/
---

# Interfaces

Interfaces (typeclasses) provide ad-hoc polymorphism: the ability to write code that works for any type that satisfies a contract, without inheritance.

**The bug they kill:** duplication that drifts out of sync. Without interfaces
you write `show_color`, `show_user`, `show_order`, N near-identical functions
that every new caller has to know about and every refactor has to update in
lockstep. One `show` constraint collapses them into a single contract: callers
write `show(x)`, and the compiler routes to the right implementation. Add a new
type and you write *one* `impl`, not a new function name to thread everywhere.

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
    fn (x, y) -> !eq(x, y)
  end
end
```

Any type implementing `Eq` automatically gets `neq` for free. It only needs to implement `eq`.

### Superinterfaces

```march
interface Ord(a) requires Eq(a) do
  fn cmp : a -> a -> Int
  fn lt  : a -> a -> Bool do fn (x, y) -> cmp(x, y) < 0 end
  fn gt  : a -> a -> Bool do fn (x, y) -> cmp(x, y) > 0 end
  fn le  : a -> a -> Bool do fn (x, y) -> cmp(x, y) <= 0 end
  fn ge  : a -> a -> Bool do fn (x, y) -> cmp(x, y) >= 0 end
end
```

`Ord(a) requires Eq(a)` means any type implementing `Ord` must also implement `Eq`.

---

## Implementing an Interface

Use `impl Interface(Type) do ... end`:

```march
-- Note: named `AppColor`, not `Color` — `Color` collides with a
-- stdlib module's own type of the same name (March has a single global
-- type namespace), which the compiler flags with a "rename one of them"
-- diagnostic. Pick a name that doesn't collide with stdlib.
type AppColor = Red | Green | Blue

impl Show(AppColor) do
  fn show(c) do
    match c do
      Red   -> "Red"
      Green -> "Green"
      Blue  -> "Blue"
    end
  end
end

impl Eq(AppColor) do
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

Implement an interface for a generic type with constraints. (`List(a)` itself
already has `Show`/`Eq` in the stdlib; writing these exact impls for `List`
now hits impl coherence, "Overlapping implementation", so the example below
wraps a list in a small custom type instead; the mechanics are identical.)

```march
type Bag(a) = Bag(List(a))

-- Show for Bag(a) when a has Show
impl Show(Bag(a)) when Show(a) do
  fn show(Bag(xs)) do
    let items = List.map(xs, fn x -> show(x))
    "Bag[" ++ String.join(items, ", ") ++ "]"
  end
end

-- Eq for Bag(a) when a has Eq
impl Eq(Bag(a)) when Eq(a) do
  fn eq(Bag(xs), Bag(ys)) do eq(xs, ys) end
end
```

The compiler picks the right implementation at call sites based on the concrete type.

---

## Using Interfaces in Function Signatures

Constrain type parameters with `when`:

```march
fn print_all(xs : List(a)) : () when Show(a) do
  List.each(xs, fn x -> println(show(x)))
end

fn sort(xs : List(a)) : List(a) when Ord(a) do
  -- Sort.timsort_by takes an explicit comparator; a real implementation
  -- would build one from this Ord(a) constraint (e.g. `lt` from a
  -- concrete `impl Ord` in scope for `a`).
  Sort.timsort_by(xs, lt)
end

fn unique(xs : List(a)) : List(a) when Eq(a) do
  List.dedup(xs)
end
```

**Multiple constraints on one function are not supported directly.** A
function's `when`-clause parses as a single expression, and the constraint
detector only recognizes one bare `Interface(tyvar)` call; `when Ord(a),
Show(a)` is a parse error (the comma isn't valid outside parens/lists), and
`when Ord(a) && Show(a)` gets type-checked as an ordinary boolean guard
expression and fails with `I don't know a constructor called `Show``.
Verified live: both forms are rejected by the current compiler.

The workaround is to declare a superinterface that `requires` the others
(`requires` itself *does* accept a comma-separated list) and constrain on
that instead. This needs an (even empty) `impl` for the umbrella interface on
each concrete type, but then dispatches correctly, interpreted and compiled:

```march
interface OrdShow(a) requires Ord(a), Show(a) do
end

impl OrdShow(Box) do
end

fn sort_and_show(x : a) : String when OrdShow(a) do
  if lt(x, x) do show(x) ++ " lt self??" else show(x) end
end
```

---

## Standard Interfaces

### `Eq(a)`: Equality

```march
interface Eq(a) do
  fn eq  : a -> a -> Bool
  fn neq : a -> a -> Bool do fn (x, y) -> !eq(x, y) end
end
```

Usage: `eq` is a compiler built-in and works standalone on any `Eq`-comparable
type. `neq` is a *default method*: just declaring `interface Eq` (as above)
does not make `neq` callable; a type needs a concrete `impl Eq(T)` in scope
before `neq` resolves for it. Verified live: with the interface declared but
no `impl Eq(Int)` anywhere, `neq(1, 2)` is `unbound variable: neq` in both
backends; once an `impl Eq(Int)` exists, it works and gives the right answer
in both backends:
```march
eq(42, 42)         -- true
eq("hi", "bye")    -- false

impl Eq(Int) do
  fn eq(a, b) do a == b end
end
neq(1, 2)          -- true (once `impl Eq(Int)` above is in scope)
```

### `Ord(a)`: Ordering

```march
interface Ord(a) requires Eq(a) do
  fn cmp : a -> a -> Int   -- negative = less, 0 = equal, positive = greater
  fn lt  : a -> a -> Bool
  fn gt  : a -> a -> Bool
  fn le  : a -> a -> Bool
  fn ge  : a -> a -> Bool
end
```

Usage (once the `interface Ord` above, or an equivalent, is declared and
implemented for the type in question; `cmp`/`lt`/`gt`/`le`/`ge` are not
compiler built-ins the way `eq` and `show` are):
```march
cmp(1, 2)    -- -1
cmp(2, 2)    -- 0
cmp(3, 2)    -- 1
lt(1, 2)     -- true
```

### `Show(a)`: String Representation

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

### `Hash(a)`: Hashing

```march
interface Hash(a) do
  fn hash : a -> Int
end
```

Required for keys in `Map` and elements in `Set`.

---

## `derive`: Automatic Implementations

**The bug `derive` kills:** field drift. A hand-written `eq` or `show` that
enumerates a record's fields silently goes stale the moment you add a field:
the new field just isn't compared or printed, and no error appears. `derive`
regenerates the implementation from the type definition on every build, so adding
a field automatically extends every derived instance. The structure is the single
source of truth.

For types with straightforward structure, `derive` generates implementations automatically:

```march
type Point = { x : Float, y : Float }
derive Eq, Show for Point

type Status = Active | Inactive | Suspended
derive Eq, Ord, Show, Hash for Status
```

After `derive Eq for Point`, you can use `eq` on `Point` values.

`derive` works for:
- **`Eq`**: structural equality, comparing all fields/constructors
- **`Ord`**: lexicographic ordering by fields, constructor order for variants
- **`Show`**: pretty-printed representation
- **`Hash`**: consistent hash based on structure. The `hash()` VALUE is
  cross-backend equal: the interpreter reimplements the compiled runtime's
  hash primitives bit-for-bit (splitmix64 for ints, FNV-1a for strings,
  masked to 62 bits so the result fits the interpreter's native int), so
  `hash(v)` agrees interpreted-vs-compiled for every value, safe to compare
  across backends. (Hash values are still not a stable serialization format
  across compiler versions, but within one version the two backends agree.)

```march
type User = { name : String, age : Int, role : String }
derive Eq, Ord, Show, Hash for User

let u1 = { name: "Alice", age: 30, role: "admin" }
let u2 = { name: "Bob",   age: 25, role: "user" }

show(u1)          -- "User { name = Alice, age = 30, role = admin }"
eq(u1, u1)        -- true
compare(u1, u2)   -- -1 (lexicographic field order; derived Ord gives `compare`,
                  --     not the `lt`/`gt`/`le`/`ge` names from a hand-written
                  --     `interface Ord` — those require declaring/implementing
                  --     the interface explicitly, as shown above)
```

Multiple types in one `derive`:

```march
derive Json, Eq for MyType
derive Show for AppColor
```

---

## A Complete Example: Implementing a Container

A file may have only one top-level `mod`, so `main` lives inside `MyStack`
here (a separate entry file could instead `import MyStack` and call the
qualified names from outside). The `pop` match arm below binds the returned
pair with a separate `let` rather than destructuring it inline in the
constructor pattern; this sidesteps a compiled-backend bug described in
[Known limitations](#known-limitations) at the end of this page.

```march
mod MyStack do
  needs IO.Console

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

  -- Using the stack:
  fn main() do
    let s0 = MyStack.empty()
    let s1 = MyStack.push(s0, 1)
    let s2 = MyStack.push(s1, 2)
    let s3 = MyStack.push(s2, 3)

    println(show(s3))   -- "Stack[3, 2, 1]"

    match MyStack.pop(s3) do
      Some(pair) ->
        let (top, rest) = pair
        println("popped: " ++ String.from_int(top))
        println("remaining: " ++ show(rest))
      None ->
        println("empty stack")
    end
  end

end
```

---

## Interface Dispatch

On the **compiled backend**, interface dispatch is resolved at compile time.
After whole-program monomorphization, a call site with an argument type known
statically compiles to a direct call to the concrete implementation: no vtable,
no boxing for primitive types, no per-call overhead, and the compiler can inline
across the interface boundary. The **interpreter** instead dispatches through a
true runtime lookup keyed by the argument's dynamic type, so treat the
zero-overhead claims as scoped to the compiled backend's common case, not a
universal guarantee.

**Impl coherence** is checked at declaration: a second `impl Speak(Dog)` for the
same `(interface, type)` pair is a compile error ("Overlapping implementation ...
A type may implement an interface at most once"), so conflicts surface as
diagnostics rather than silent shadowing. Two distinct types that only share a
short name across modules can each `impl` the same interface and dispatch
correctly by runtime type on both backends. One interpreter-only gap remains:
calling an interface method unqualified from a module other than the one that
declared the `impl` can occasionally fail to resolve even when the identical call
compiles and runs correctly.

**Interface method names are not module-qualifiable** in either backend:
`Foo.speak(x)` never resolves (dispatch works through the method's bare name,
not module-member lookup), so the working spelling is always the unqualified
`speak(x)`. This is a known won't-fix (the naive fix was measured to regress
working code; see
`specs/progress/2026-08-03-interface-method-names-qualifiability-disposition.md`).
The interpreter recognizes this failure shape and appends a hint to the
`unbound variable: Foo.speak` error suggesting the bare spelling.

---

## Known limitations

**Tuple destructured inline inside a constructor pattern (compiled backend).**
Destructuring a tuple pattern nested directly inside a constructor pattern,
`Some((top, rest)) -> ...`, silently reads the tuple elements' raw tagged
representation instead of untagging them on the compiled backend only (e.g. an
`Int` `3` comes back as `7`); the interpreter is correct. Bind the whole payload
first and destructure it with a separate `let`, as the stack example above does
(`Some(pair) -> let (top, rest) = pair`), and it works correctly on both
backends.

---

## Next Steps

- [Types](types.md): types you implement interfaces for
- [Standard Library](stdlib.md): stdlib types and their interface implementations
- [Pattern Matching](pattern-matching.md): using `match` with interface-dispatched values
