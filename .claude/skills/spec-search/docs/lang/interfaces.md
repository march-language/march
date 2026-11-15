---
layout: docs
title: Interfaces
nav_order: 5.3
permalink: /docs/interfaces/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md)

# Interfaces

An interface names a contract: a set of function signatures a type can implement. Code
written against the interface works for any type that implements it, and the compiler
picks the implementation from the type at each call. This is ad-hoc polymorphism
without inheritance, what other languages call typeclasses or traits.

The payoff is one name instead of many. Without interfaces you write `show_color`,
`show_user` and `show_order`, and every caller and every refactor has to know all
three. With `interface Show(a)`, callers write `show(x)`, and adding a type means one
`impl`, not a new function name to thread through the program. `derive` goes one step
further and generates the implementation from the type's structure, so adding a field
cannot leave `eq` or `show` silently stale.

This page covers declaring and implementing interfaces, defaults and superinterfaces,
conditional implementations, constraints on functions, the four standard interfaces,
`derive`, and how dispatch works on each backend.

## On this page

**Start here**

- [When to use an interface](#when-to-use-an-interface)
- [How it fits with the rest of March](#how-it-fits-with-the-rest-of-march)
- [Defining an Interface](#defining-an-interface): [default implementations](#default-implementations), [superinterfaces](#superinterfaces)
- [Implementing an Interface](#implementing-an-interface)
- [Conditional Implementations](#conditional-implementations)
- [Using Interfaces in Function Signatures](#using-interfaces-in-function-signatures)
- [Capability bounds on methods](#capability-bounds-on-methods)
- [Laws](#laws)

**The standard interfaces**

- [Standard Interfaces](#standard-interfaces): [`Eq`](#eqa-equality), [`Ord`](#orda-ordering) and [`compare` on `Float`](#built-in-compare-on-float-and-nan), [`Show`](#showa-string-representation), [`Hash`](#hasha-hashing)
- [`derive`: Automatic Implementations](#derive-automatic-implementations)

**Reference**

- [A Complete Example: Implementing a Container](#a-complete-example-implementing-a-container)
- [Interface Dispatch](#interface-dispatch)
- [See also](#see-also)

## When to use an interface

| You want | Write |
|---|---|
| One operation name that works across several of your types | `interface Name(a)` with the signature, and an `impl` per type |
| Equality, ordering, printing or hashing for your own type | `derive Eq, Ord, Show, Hash for T`; hand-write an `impl` only when structure is the wrong answer |
| A function that accepts any type with that operation | A `when Iface(a)` constraint on the function |
| Two constraints on one function | A superinterface that `requires` both, and constrain on that |
| An implementation that depends on the element type | `impl Show(Bag(a)) when Show(a)` |
| A type as a `Map` key or `Set` element | `Hash` and `Eq`, usually derived |
| A type that crosses the network or a hot deploy | `derive Json`; see [Clustering]({{ site.baseurl }}/docs/clustering/) |

Do not reach for an interface to model a type hierarchy: there is no inheritance, and
a variant type with a `match` is usually the simpler tool when the set of cases is
closed.

## How it fits with the rest of March

| Concept | Where interfaces meet it | Chapter |
|---|---|---|
| **Type system** | Interfaces constrain type variables; a `when` clause is part of the function's type. | [Type System]({{ site.baseurl }}/docs/types/) |
| **Pattern matching** | An `impl` body is ordinarily a `match` over the type's constructors; `derive Ord` orders variants by declaration order. | [Pattern Matching]({{ site.baseurl }}/docs/pattern-matching/) |
| **Standard library** | `Map` and `Set` need `Hash` and `Eq`; `Sort` takes comparators built from `Ord`; stdlib types already implement the four standard interfaces. | [Standard Library]({{ site.baseurl }}/docs/stdlib/) |
| **Clustering and hot reload** | `derive Json` is the codec a typed remote message or a protocol payload needs; two types with one short name cannot both derive it. | [Clustering]({{ site.baseurl }}/docs/clustering/), [Choreography]({{ site.baseurl }}/docs/choreography/) |
| **Interpreter vs compiled** | The compiled backend resolves most dispatch statically; the interpreter uses a runtime table and cannot qualify a method name with its module. | [Interface Dispatch](#interface-dispatch) |

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
> that a user-declared `interface Eq(a)` with a default `neq` that calls `eq`
> "hangs/stack-overflows at runtime" due to an `impl_tbl` dispatch-key
> collision with the compiler's built-in `Eq` dispatch. That specific bug is
> FIXED, reverified live (interpreted and compiled): the example above
> typechecks and runs to completion on both backends with no hang, no stack
> overflow, and the correct answer on both backends. A second, unrelated
> compiled-only bug was found while reverifying this callout: a default
> method's body that calls a *sibling* interface method (`neq` calling `eq`,
> or `Ord`'s `lt`/`gt` calling `cmp`) compiled to a lambda that did not
> re-evaluate correctly per call, returning the same answer regardless of the
> actual arguments, on the COMPILED backend only. **That bug is also FIXED**
> (`lib/desugar/desugar.ml`'s `inject_defaults`, 2026-07-18): reverified live
> with the `MyOrd`/`AppColor` repro that motivated the fix: `mylt(Red, Green)`
> / `mylt(Green, Red)` now print `true` / `false` compiled with `--opt 2`,
> matching the interpreter, and the `Eq`-shaped `neq`-calling-`eq` case above
> likewise gives correct, argument-dependent answers compiled. See
> `core-march.md` §4.4.2 for how method dispatch actually works operationally.

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

## Capability bounds on methods

A method signature can carry a `needs` bound after its type. Every impl of the method, in
any module, and the interface's default body are checked against it:

```march
interface Store(a) do
  fn get : (a, String) -> Option(String) needs IO.FileRead
  fn describe : a -> String needs ()
end

impl Store(Disk) do
  fn get(d, key) do read_entry(d, key) end   -- may read files, nothing else
  fn describe(_d) do "disk" end              -- may perform no I/O at all
end
```

An impl that reaches past the bound is rejected at the impl, with the path to the
capability. An impl may declare a narrower bound of its own (`fn describe(_d) needs ()`)
but not a wider one. A method with no bound constrains nothing. The bound is a check on
impls only: it is not part of the method's type, and a function constrained by
`when Store(a)` declares nothing new. See
[Per-function bounds]({{ site.baseurl }}/docs/capabilities/#per-function-bounds) for the
full rules.

## Laws

An interface can state laws: properties every implementation must have. A law is
written as a lemma signature with no body, `@[lemma] fn name(params) : {Unit | P}`,
where `P` may call the interface's methods (see
[Lemmas]({{ site.baseurl }}/docs/refinement-types/#lemmas-proving-what-one-unfolding-cannot)).

```march
interface Monoid(a) do
  fn combine : a -> a -> a
  @[lemma]
  fn combine_assoc(x : a, y : a, z : a)
    : {Unit | combine(combine(x, y), z) == combine(x, combine(y, z))}
end

impl Monoid(Int) do
  fn combine(x, y) do x + y end
end
```

The checker checks each law once per `impl`, with that impl's methods. Here
`combine_assoc` is proved for `Int`. An impl whose methods break a law is an error with
an input that shows it:

```text
the lemma `combine_assoc__Monoid_Box` is false: its theorem
`combine(combine(x, y), z) == combine(x, combine(y, z))` does not hold at
x = Box(-3), y = Box(-2), z = Box(-1)
```

When a law needs a proof (an induction, say), the impl gives one as a lemma with the
law's name. Without it, the checker tries the law with an empty body:

```march
impl Joinable(List(a)) do
  fn join(xs, ys) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, join(t, ys))
    end
  end
  fn none(_xs) do Nil end
  @[lemma]
  fn join_none(xs) do        -- proves the interface's join_none for lists
    match xs do
      Nil -> ()
      Cons(_, t) -> join_none(t)
    end
  end
end
```

A law the checker cannot prove for an impl is `lemma_unproved` (an error in a
`cap verified` module), and `forge test` tests it on generated inputs, like any
lemma. Laws never run: they and the code the checker uses for them are removed
before the program is built.

The checker names each impl's law `<law>__<Interface>_<Type>` in its messages
(`combine_assoc__Monoid_Int`). Every impl is checked: in the interface's file or in
another one, and with the interface's default for any method it does not define. A law
may call a method that takes `Unit` (`combine(empty(()), x) == x`).

`==` in a law is structural equality, so a law about a type with a hand-written `Eq`
does not use that `eq`.

---

## Standard Interfaces

All four standard interfaces are bounded by `needs ()`: an impl of `eq`, `compare`, `show`
or `hash` reaches no `IO` capability, directly or through anything it calls, so showing,
comparing, ordering and hashing a value never do I/O. (The check covers the `IO` lattice;
`Map`, `Sort` and most collection operations take a comparator function instead, which is
charged to whoever passes it, as usual.) `derive` produces pure impls; a hand-written one
that prints, logs or reads the clock is rejected (`cap_bound`) at the impl. Do that work
outside the impl instead.

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

**Tuples.** A tuple is `Eq` when every component is: `(1, ["x"]) == (1,
["x"])` is `true`, with the components compared left to right. No `impl` is
needed, and none could be written for every arity. A tuple with a component
that is not `Eq` (a function, or an ADT without `derive Eq`) is rejected as
before.

Tuples are `Ord` the same way, ordered lexicographically: the first pair of
components that differs decides, each compared by its own `Ord`. So
`(1, 2) < (1, 3)` and `(1, "b") > (1, "ab")` are both `true`, and
`compare((Zed, 1), (Amber, 0))` follows the declaration order of a
`derive Ord` type, not the constructor names. This covers tuples of 2 to 5
components; a longer tuple is not `Ord`.

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

#### Built-in `compare` on `Float`, and NaN

The built-in `compare` (and `compare_float`) on `Float` is a total preorder:
**NaN compares equal to NaN and less than every other value**, including
`-inf`. Otherwise it is the IEEE order, so `-0.0` and `0.0` compare equal. This
is OCaml's `Float.compare`, and both backends agree on it. It means a sort or a
`Map`/`Set` comparator built on `compare` puts every NaN first and keeps them
together.

The comparison *operators* are different: `==`, `!=`, `<`, `<=`, `>`, `>=` on
`Float` stay IEEE 754, so every one of them except `!=` is `false` when either
operand is NaN (`nan == nan` is `false`). Use `compare` when you need an
ordering, and the operators when you want IEEE semantics.

```march
let nan = float_nan()      -- `0.0 / 0.0` is a division-by-zero error in March
compare(nan, 1.0)          -- -1
compare(1.0, nan)          -- 1
compare(nan, nan)          -- 0
compare(-0.0, 0.0)         -- 0
nan == nan                 -- false
nan < 1.0                  -- false
```

Before 2026-09-25 the compiled backend returned `0` from `compare` whenever
either operand was NaN, so NaN compared equal to everything and a sort by
`compare` could put the NaNs anywhere. The interpreter already used the order
described here.

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

**What `derive` prevents:** field drift. A hand-written `eq` or `show` that
enumerates a record's fields silently goes stale the moment you add a field;
the new field just isn't compared or printed, and no diagnostic appears. `derive`
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

Two different types with the same short name (say `A.Note` and `B.Note` in two
modules) cannot both `derive Json`: `from_json` picks its decoder by the result
type's short name, so it cannot tell them apart. The program is rejected at
compile time (`json_derive_name_collision`), naming both types and both `derive`
sites. Rename one, or derive Json for only one of them (that case works).

---

## A Complete Example: Implementing a Container

A file may have only one top-level `mod`, so `main` lives inside `MyStack`
here (a separate entry file could instead `import MyStack` and call the
qualified names from outside).

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
  fn main(_cap_console : Cap(IO.Console)) do
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

For the **compiled backend**, the compiler resolves most interface dispatch at compile time (after monomorphization): a call site with a statically known argument type is compiled to a direct function call to the concrete implementation, with no boxing for primitive types and no per-call overhead.

That compile-time-resolved picture describes the compiled backend's common case, not a single dispatch mechanism the whole language shares. See `core-march.md` §4.4.2 ("Method dispatch: `impl_tbl` vs. ordinary lexical `env` binding") for the full, precise operational account, which this section summarizes:

- The **built-in type-directed interfaces** (`Show`, `Eq`, `Ord`, `Hash`) dispatch, in the **interpreter**, through a real **runtime hashtable** (`impl_tbl`, keyed `(interface, type_name)`) looked up by the argument's dynamic type at the call site. This is real runtime type-directed dispatch, not something resolved ahead of time.
- **User-defined interfaces** used to get no dispatch table at all and overlapping impls were silently "last one wins"; that's no longer the case. **Impl coherence** (checked at declaration) now rejects a second `impl Speak(Dog)` for the same `(interface, type)` pair as an immediate compile error ("Overlapping implementation ... A type may implement an interface at most once"), so it's a diagnostic, not silent shadowing. Separately, **FQN dispatch identity** (commit `44e7a6bb7`, #57; `core-march.md` §4.4.3) lets two truly distinct types that happen to share a short name across different modules (e.g. an unrelated `Thing` declared in two library modules) each `impl` the same general interface and dispatch correctly by the value's runtime type, in *both* backends, when the collision is present: the interpreter qualifies its dispatch table by declaring module and the compiled backend generates a runtime ctor-tag dispatch function for the ambiguous call sites. One narrow, pre-existing gap remains in the **interpreter only**: calling an interface method unqualified from a module other than the one that declared the `impl` can fail to resolve (`unbound variable`) even when the identical call compiles and runs correctly. This shows up again even with no short-name collision at all, so it's a general interpreter scoping limitation, not specific to the collision-dispatch mechanism. See `core-march.md` §4.4.2/§4.4.3 for the full operational account.

A related, separate limitation: **interface method names are not
module-qualifiable in the interpreter**. When `Foo` declares
`interface Speak(a) do fn speak : a -> String end` and dispatches it via
`impl Speak(...)`, `Foo.speak(x)` fails at run time with `unbound variable:
Foo.speak`, for a nested module or the entry module alike, because the
interpreter dispatches through the method's bare name, not module-member
lookup. `--check` accepts the qualified spelling and the compiled backend
runs it correctly, so the failure only surfaces when the program is
interpreted; the spelling that works everywhere is the unqualified
`speak(x)`. Closing the interpreter gap needs interface methods to become
qualifiable in general (a dispatch-side redesign), which was tried and
**measured to regress working code**; see
`specs/progress/2026-08-03-interface-method-names-qualifiability-disposition.md`
for the measurement and why it was closed as won't-fix rather than attempted
again. As a bounded consolation, the **interpreter** now recognizes this
exact failure shape and appends a note to the `unbound variable: Foo.speak`
error naming the interface and suggesting the bare spelling: a diagnostic
improvement only, not a resolution change.

So "no vtables or runtime type lookups" is accurate for the compiled backend's statically-resolved calls, but not as a claim about the language or the interpreter in general; treat this section's overhead claims as scoped to the compiled backend's common-case dispatch, not a universal guarantee:

- Zero overhead compared to a direct call, for the compiled backend's statically-resolved case
- The compiler can inline implementations across interface boundaries in that case
- No boxing required for primitive types

---

## See also

- [Types](type-system.md): types you implement interfaces for
- [Standard Library](../../docs/stdlib.md): stdlib types and their interface implementations
- [Pattern Matching](pattern-matching.md): using `match` with interface-dispatched values
- [Clustering]({{ site.baseurl }}/docs/clustering/#typed-remote-messages-nodesend-and-remote): `derive Json` as the wire codec
