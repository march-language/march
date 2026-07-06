> Part of the March Language Reference — see [specs/lang/index.md](index.md)

# Interfaces

Interfaces (typeclasses) provide ad-hoc polymorphism — the ability to write code that works for any type that satisfies a contract, without inheritance.

**The bug they kill:** duplication that drifts out of sync. Without interfaces
you write `show_color`, `show_user`, `show_order` — N near-identical functions
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

> **Historical note (resolved):** an earlier version of this document warned
> that a user-declared `interface Eq(a)` whose default `neq` calls `eq`
> "hangs/stack-overflows at runtime" due to an `impl_tbl` dispatch-key
> collision with the compiler's built-in `Eq` dispatch. That specific bug is
> FIXED — reverified live (interpreted and compiled): the example above
> typechecks and runs to completion on both backends with no hang, no stack
> overflow, and (interpreted) the correct answer. A different, real, still-open
> compiled-only bug was found while reverifying this callout, though: a default
> method's body that calls a *sibling* interface method (`neq` calling `eq`,
> or `Ord`'s `lt`/`gt` calling `cmp`) compiles to a lambda that does not
> re-evaluate correctly per call — it can return the same answer regardless of
> the actual arguments — on the COMPILED backend only (the interpreter is
> correct). This is unrelated to the old `Eq`-name-collision mechanism (it
> reproduces identically for a user interface with no built-in-name collision
> at all, and `Ord`'s `cmp`-calling defaults are affected too, contrary to what
> this callout previously claimed). See `specs/todos.md` ("Compiler:
> interfaces/impls declaration checking, Task 6 closeout") for the live repro
> and citations; see `core-march.md` §4.4.2 for how method dispatch actually
> works operationally.

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
  fn neq : a -> a -> Bool do fn (x, y) -> !eq(x, y) end
end
```

Usage — `eq` is a compiler built-in and works standalone on any `Eq`-comparable
type; `neq` only exists once the `interface Eq` above (or an equivalent) is in
scope, and is subject to the known issue noted above:
```march
eq(42, 42)         -- true
eq("hi", "bye")    -- false
neq(1, 2)          -- true (once the `interface Eq` above is declared)
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

Usage (once the `interface Ord` above, or an equivalent, is declared and
implemented for the type in question — `cmp`/`lt`/`gt`/`le`/`ge` are not
compiler built-ins the way `eq` and `show` are):
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

**The bug `derive` kills:** field drift. A hand-written `eq` or `show` that
enumerates a record's fields silently goes stale the moment you add a field —
the new field just isn't compared or printed, and nothing complains. `derive`
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
- **`Eq`** — structural equality, comparing all fields/constructors
- **`Ord`** — lexicographic ordering by fields, constructor order for variants
- **`Show`** — pretty-printed representation
- **`Hash`** — consistent hash based on structure

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

For the **compiled backend**, the compiler resolves most interface dispatch at compile time (after monomorphization): a call site whose argument type is known statically is compiled to a direct function call to the concrete implementation, with no boxing for primitive types and no per-call overhead.

That compile-time-resolved picture is not the whole story, though — it describes the compiled backend's common case, not a single dispatch mechanism the whole language shares. See `core-march.md` §4.4.2 ("Method dispatch: `impl_tbl` vs. ordinary lexical `env` binding") for the full, precise operational account, which this section summarizes:

- The **built-in type-directed interfaces** (`Show`, `Eq`, `Ord`, `Hash`) dispatch, in the **interpreter**, through a genuine **runtime hashtable** (`impl_tbl`, keyed `(interface, type_name)`) looked up by the argument's dynamic type at the call site — this is real runtime type-directed dispatch, not something resolved ahead of time.
- **User-defined interfaces** get no dispatch table at all, in either backend — a call resolves through ordinary lexical `env`/name binding (whichever `impl`'s method was bound most recently in scope), which is also why overlapping impls of a user interface are "just shadowing," not a coherence policy (see `core-march.md` §4.4.3 for the known interpreter/compiled divergence this causes when more than one impl of the same interface/type pair is in scope).

So "no vtables or runtime type lookups" is accurate for the compiled backend's statically-resolved calls, but not as a claim about the language or the interpreter in general — treat this section's overhead claims as scoped to the compiled backend's common-case dispatch, not a universal guarantee:

- Zero overhead compared to a direct call, for the compiled backend's statically-resolved case
- The compiler can inline implementations across interface boundaries in that case
- No boxing required for primitive types

---

## Next Steps

- [Types](type-system.md) — types you implement interfaces for
- [Standard Library](../../docs/stdlib.md) — stdlib types and their interface implementations
- [Pattern Matching](pattern-matching.md) — using `match` with interface-dispatched values
