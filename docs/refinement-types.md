---
layout: docs
title: Refinement Types
nav_order: 5.5
permalink: /docs/refinement-types/
---

# Refinement Types

Normally, a type like `Int` only tells the compiler "this is a whole number" — it says
nothing about *which* whole numbers are actually valid here. A **refinement type** lets
you attach an extra condition to a type, so `{Int | _ >= 0}` means "an `Int`, and
specifically one that's never negative." The condition (`_ >= 0` here) is called a
**predicate** — just a true/false check on the value.

The clever part is that March doesn't just remember the condition as documentation — it
actually *proves* it, at compile time, using an automated reasoning tool called an
**SMT solver** (specifically [Z3](https://github.com/Z3Prover/z3)). An SMT solver is
software that can mechanically work out whether a set of logical/arithmetic statements
is possible or is a contradiction — the same kind of tool used to verify hardware
designs and cryptographic protocols. In March, it's put to work checking your function
contracts, so a whole class of bugs — out-of-bounds indices, negative sizes, division by
zero, broken invariants — becomes a **compile error** instead of a runtime panic.

If you've heard the term **dependent typing** — types that depend on *values*, not just
other types — refinements are March's practical, restricted slice of it. You get the
safety where it pays off (preconditions, bounds, postconditions) without a proof
assistant's ceremony — and, crucially, **without false positives**: if the checker can't
prove a value is definitely wrong, it stays silent rather than guessing.

> **Requires Z3.** Refinement checking runs only when the `z3` solver is on your
> `PATH`. Without it, the predicates type-check as their base type and no
> refinement diagnostics are produced (the build still succeeds).

---

## The Problem They Solve

```march
fn at(xs : List(Int), i : Int) : Int do
  -- if i is out of range this panics at runtime
  List.nth(xs, i)
end

at([10, 20, 30], 5)   -- boom, eventually, at runtime
```

A refinement moves the contract into the type, where the compiler checks it:

```march
fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do
  List.nth(xs, i)
end

at([10, 20, 30], 5)   -- compile error: 5 is not < len([10,20,30]) = 3
at([10, 20, 30], 1)   -- ok
```

---

## Syntax

A refinement is written `{ BaseType | predicate }`. The placeholder `_` stands
for the value being refined:

```march
{Int | _ >= 0}              -- a non-negative Int
{Int | _ > 0}              -- a positive Int
{Int | _ != 0}             -- a non-zero Int (safe divisor)
{Int | _ >= 0 && _ < 100}  -- a bounded Int
```

You can name the value instead of using `_`:

```march
{v : Int | v >= 0 && v < 100}
```

Refinements appear anywhere a type does — **parameters** (preconditions) and
**return types** (postconditions):

```march
-- precondition: callers must pass a positive size
fn chunks(xs : List(a), size : {Int | _ > 0}) : List(List(a)) do ... end

-- postcondition: this function promises a non-negative result
fn count(xs : List(a)) : {Int | _ >= 0} do List.length(xs) end
```

The supported predicate fragment is **`Int`/`Bool` linear arithmetic**:
`+ - *` (multiplication by a literal), the comparisons `== != < <= > >=`, the
connectives `&& || not`, integer/bool literals, and **measures** (below).
`Bool` and `Float` values are refinable too — see
[Bool and Float Refinements](#bool-and-float-refinements).

---

## How Checking Works — Definite Failure

Think of the checker as a cautious lawyer rather than an eager one: it only objects when
it can prove, beyond doubt, that you're wrong. There are exactly three outcomes for a
predicate at a given point in your code:

- The argument **always** satisfies the predicate → **pass**, silently.
- The argument **never** satisfies it → **compile error** with a counterexample.
- It **might or might not** satisfy it (the value is unknown, or the solver can't
  decide) → **skipped**, silently.

```march
fn take_pos(n : {Int | _ >= 0}) : Int do n end

take_pos(-3)                     -- error: -3 can never be >= 0
take_pos(5)                      -- pass

fn f(k : Int) : Int do
  take_pos(k)                    -- skipped: k is unknown, might be >= 0
end
```

The consequence: **no false positives, by design — but incomplete.** The
checker never flags correct code, and never blocks a build over something it
can't disprove. It also won't *prove* everything you might hope; facts it can't
establish are conservatively let through. This trade is deliberate — a
refinement checker that cries wolf is one developers turn off.

---

## Path Sensitivity — Guards Establish Facts

A guard you write becomes a fact the solver can use for the rest of that branch. The
then-branch learns the condition is true; the else-branch learns it's false:

```march
fn get(xs : List(Int), i : Int) : Int do
  if i >= 0 && i < List.length(xs) do
    at(xs, i)          -- ok: the guard proves the precondition here
  else
    0
  end
end
```

(`len`, used in earlier examples, is a special name usable only inside a `{...}`
refinement predicate — you can't call it as an ordinary function. In plain code, like
the guard above, use `List.length` instead; the solver knows they mean the same thing.)

### The solver really does connect `List.length` to `len`

That last sentence is worth dwelling on, because it hasn't always been true. The
checker treats the qualified `List.length` as another name for the `len` measure, so a
guard you'd write anyway — `if List.length(ys) > 0` — establishes exactly the fact the
contract `{List(Int) | len(_) > 0}` is asking for:

```march
fn first_or(ys : List(Int), d : Int) : Int do
  if List.length(ys) > 0 do head(ys) else d end   -- proved
end

fn broken(ys : List(Int)) : Int do
  if List.length(ys) == 0 do head(ys) else 0 end  -- compile error
end
```

The second one is a compile error because under `len(ys) == 0` the predicate
`len(ys) > 0` can *never* hold — a definite failure, which is the bar March requires
before it says anything.

The connection is deliberately narrow, since attaching `len`'s meaning to the wrong
function is how you'd get a false alarm on correct code. Only the **qualified**
`List.length` counts (a bare `length` is left alone), and only while it's still the
standard library's own. If your program defines its own `List.length` — however it
spells the definition: a `fn`, a module-level `let`, an `extern` block, an interface
or impl method — ships a forked
`List` via `MARCH_LIB_PATH`, or rebinds `List` with `alias`/`use`/`import`, the connection is
dropped for that whole module and you're back to the older behaviour: the obligation
is skipped, quietly, rather than proved.

### The same for strings — but only the byte-valued names

`len` measures a `String` too, and the same connection is made for
`String.byte_size` and the `string_byte_length` builtin:

```march
fn slug(s : {String | len(_) > 0}) : String do String.slice(s, 0, 1) end

fn label(t : String) : String do
  if String.byte_size(t) > 0 do slug(t) else "?" end   -- proved
end
```

Swap the guard for `String.byte_size(t) == 0` and that call becomes a compile error,
the same way it does for lists.

The catch is that `len` on a String counts **bytes**, so only byte-valued names get
this treatment. `String.codepoint_count` counts codepoints — it returns 1 for `"é"`
where `String.byte_size` returns 2 — and is left alone. So is `string_length`: it
happens to be a byte length today, but the *name* suggests characters, and a
connection made on a name that might later be corrected is a bug waiting to happen.
Reach for `String.byte_size` in a guard; it says what it means.

`match` arm guards (`when`) work the same way. An `assert(p)` acts as an
**assume** — it injects `p` as a fact for the code that follows:

```march
fn g(i : Int) : Int do
  assert(i >= 0)
  take_pos(i)          -- ok: the assert established i >= 0
end
```

Use `assert` as the escape hatch for facts the checker can't derive on its own
(it's the place a hand-proved lemma lives).

---

## Postconditions

A refined return type is checked on **every return path** of the function,
under the path/scope reaching it:

```march
fn clamp_low(n : Int) : {Int | _ >= 0} do
  if n < 0 do 0 else n end        -- both branches satisfy _ >= 0  ✓
end

fn bad(n : Int) : {Int | _ >= 0} do
  if n < 0 do n else 0 end        -- error: the n < 0 branch returns a negative
end
```

---

## Measures — Refining over Data Structures

Every predicate so far has been about a single plain number, like `i >= 0`. But often
the bound you actually care about depends on the *shape* of a data structure — "the
index must be less than the list's length," say. A **measure** is how you bring that
into a predicate: it's an ordinary-looking function from a value to an `Int` (or
`Bool`), except the compiler is allowed to reason about it symbolically, not just run
it. The built-in `len` measures a list this way:

```march
fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do ... end
```

You can define your own with the `@[measure]` attribute — for example the size
of a tree:

```march
type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))

@[measure]
fn size(t : Tree(a)) : Int do
  match t do
    Leaf          -> 0
    Node(l, x, r) -> 1 + size(l) + size(r)
  end
end

fn get(t : Tree(a), i : {Int | _ >= 0 && _ < size(t)}) : a do ... end
```

Once a function is marked `@[measure]`, the solver treats its own definition as a set of
rules it's allowed to use — so for a value whose shape it can see (a literal list, an
explicit `Node`/`Leaf` tree), it can effectively "run" the measure symbolically:
from the equations above it works out `size(Node(Leaf, x, Leaf)) = 1`, so an
out-of-bounds index into a literal tree is caught, and `size(t) >= 0` is known for any
`t`. Measures may call **other measures** and be **mutually recursive** (e.g. a
`Tree`/`Forest` pair), and the built-in `List` is modelled too, so a user
`length` measure over `List(a)` reasons the same way as `size`.

### Requiring a non-empty collection

In the examples above the measure describes a *different* parameter — `len(xs)`
bounds the index `i`. A measure can just as well describe the refined value
**itself**, which is how you say "this list must not be empty":

```march
fn head(xs : {List(a) | len(_) > 0}) : a do ... end
```

Inside the predicate you can name the refined value three ways, and they all mean
the same thing and are checked identically — the anonymous `_`, your own binder,
or the parameter's name:

```march
fn head(xs : {List(a)     | len(_)  > 0}) : a do ... end
fn head(xs : {v : List(a) | len(v)  > 0}) : a do ... end
fn head(xs : {List(a)     | len(xs) > 0}) : a do ... end
```

Pass a list the compiler can see is empty and you get an error; pass one it can
see is non-empty and it says nothing; pass one it can't see into and it stays
quiet rather than guessing:

```march
head([])            -- error: `len(_) > 0` can never hold here
head([1, 2])        -- fine
fn f(ys : List(Int)) : Int do head(ys) end   -- skipped: length unknown
```

Thirteen standard-library functions that panic on an empty argument now carry
this contract — `List.head`, `tail`, `last`, `minimum_int`, `maximum_int`, the
prelude's `head`/`tail`, `Stats.mean`/`min_val`/`max_val`, `Gen.element`/`one_of`,
and `Random.choice` — so `List.head([])` is a compile error rather than a crash.
Each contract is taken from that function's own panic message, so it never
demands more than the code already checked, and every `panic` stays in place to
catch the cases the compiler skips.

An ordinary `List.length(xs) > 0` guard **does** satisfy the requirement, so these
contracts bite on a list you checked at runtime and not just on literals — see
[the solver really does connect `List.length` to
`len`](#the-solver-really-does-connect-listlength-to-len) for exactly when that
connection applies, and the (narrow) circumstances in which it's dropped.

### The measure soundness gate

The solver trusts a `@[measure]` completely — it treats the function's body as a fact
about the world. That means a badly-behaved measure (one that never finishes, divides
by zero, or skips a case) could let the solver "prove" something false. To prevent that,
the compiler requires every measure to be provably well-behaved before it's allowed to
be used at all — a **hard compile error** if it isn't. A `@[measure]` is rejected if it:

- has an **effect** (`spawn`, `send`, `dbg`, `assert`) — it must be pure,
- can **diverge or abort** (`panic`, `todo`, `exit`) — it must always finish,
- is **non-total** — a non-exhaustive `match` on its parameter, or a `/` / `%`
  that could divide by zero — it must handle every case,
- is **not structurally recursive** — a recursive call whose argument isn't a
  component of the matched parameter — each call must work on a strictly smaller piece
  of the input, so it's guaranteed to terminate.

A measure that is sound but outside what the encoding can model (see
limitations, below) isn't an error — it simply falls back to weaker, symbolic
reasoning.

---

## Bool and Float Refinements

A `Bool` parameter or return carries a predicate over the ordinary boolean
operators — `==`, `!=`, `&&`, `||`, `not` — against `true` and `false`:

```march
fn commit(confirmed : {Bool | _ == true}) : Int do ... end

commit(false)   -- rejected: `_ == true` can never hold at `false`
commit(true)    -- fine
```

Write the **operator form**: `{Bool | not _}` does not parse, so use
`{Bool | _ == false}`. An unknown `Bool` is skipped, and a guard works as you'd
expect — `if k do commit(k) else 0 end` passes.

A `Float` parameter or return carries a **comparison** — `>=`, `>`, `<=`, `<`,
`==`, `!=` — against float literals or another float value:

```march
fn sqrtish(x : {Float | _ >= 0.0}) : Float do ... end
fn ratio(n : Float, d : {Float | _ != 0.0}) : Float do n /. d end

sqrtish(0.0 -. 1.0)   -- rejected
sqrtish(4.0)          -- fine
ratio(1.0, 0.0)       -- rejected: a zero divisor
```

### Why floats are not modelled as reals

Float predicates go to Z3's **bit-precise IEEE-754 FloatingPoint** theory:
`Float64`, `fp.geq` / `fp.gt` / `fp.leq` / `fp.lt`, and `fp.eq` for equality.
Modelling floats as mathematical **reals** would break the no-false-positives
promise. Consider `not (x >= 0.0) && not (x <= 0.0)`. Over reals, trichotomy
makes that **impossible** — and since the checker objects exactly when a
predicate can *never* hold, it would flag this contract on every argument. Over
floats it is perfectly possible, witnessed by `NaN`, which compares false
against everything; so the checker correctly stays silent.

Equality is `fp.eq` (IEEE equality), not bitwise identity. Under bitwise
identity `-0.0` would differ from `0.0` and `{Float | _ != 0.0}` would accept a
negative zero — just as bad a divisor as a positive one. Under `fp.eq`,
`-0.0 == 0.0` holds (so a negative zero **is** rejected) and `NaN` equals
nothing, not even itself.

Float **arithmetic inside a predicate** — `{Float | _ +. 1.0 > 0.0}` — is out of
scope: modelling it needs rounding-mode reasoning, so the whole predicate is
skipped rather than approximated. Arithmetic over float *literals* is different:
`0.0 -. 1.0` is folded to a constant first and is fully checked, which is how a
negative literal (which March has no direct spelling for) still works.

---

## Constructor Tags — Refining over ADT Variants

Refinements aren't limited to numbers and sizes. You can also require that a
value is a *particular variant* of a union type. Every constructor — in your own
types, and in the built-in `Option`, `Result` and `List` — implicitly comes with
an `is_<Ctor>` **tester** you can use inside a predicate. You don't declare
these; writing `type Shape = Circle(Int) | Square(Int)` gives you `is_Circle`
and `is_Square` for free.

That lets a function say "I need the populated case" in its own signature:

```march
fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do ... end

unwrap(Some(1))   -- fine
unwrap(None)      -- error: `None` can never satisfy `is_Some(_)`
```

This is what backs the standard library's `Option.unwrap`/`expect` and
`Result.unwrap`/`unwrap_err`/`expect`, so `Option.unwrap(None)` and
`Result.unwrap(Err("boom"))` are now compile errors rather than runtime panics.

The tester name is **exact-case**. `is_Some` is the tester for the constructor
`Some`; `is_some` is *not* a tester — it's the lowercase stdlib helper
`Option.is_some`. Get the case wrong and you don't silently get a different
meaning, you get a warning that the refinement isn't being checked:

> `is_some` is not a measure or known predicate, so this refinement is not
> checked. Annotate the function `@[measure]`, or use a supported predicate.

### Facts from a `match`

A constructor literal at the call site is the easy case. The more useful one is
a `match`: entering an arm tells the checker what the scrutinee's tag is for
everything inside that arm.

```march
fn f(x : Option(Int)) : Int do
  match x do
    None    -> unwrap(x)   -- error: inside this arm, `x` is definitely `None`
    Some(v) -> unwrap(x)   -- fine: inside this arm, `x` is definitely `Some`
  end
end
```

This narrowing is deliberately conservative. Where it stops, the checker goes
quiet rather than guessing — so these are all *silence*, never false alarms:

- **The scrutinee has to be a plain variable.** `match mk() do …` matches an
  expression, and there's no stable name to attach a fact to, so nothing inside
  the arms is narrowed. Bind it with a `let` first if you want the fact.
- **A pattern that rebinds the name ends it.** Matching `y` with `Some(x) ->`
  tells you nothing about `x` — that `x` is a fresh name for the payload, not
  for the scrutinee.
- **An `as` pattern isn't narrowed.** `None as z ->` binds the whole scrutinee
  under a second name, but the arm's head is an `as` pattern rather than a bare
  constructor pattern, so no tag fact is recorded — not for `z`, and not for the
  scrutinee. Write `None ->` if you want the narrowing.
- **An ambiguous constructor name is skipped.** If two types in scope both
  declare a constructor `Row`, then `is_Row` doesn't identify a particular type
  and isn't checked.
- **Rebinding the name discards the fact.** A narrowing is recorded against a
  *name*, so anything that rebinds that name inside the arm — a `let`, a `let?`,
  a lambda parameter, an inner `match` binder — drops it:

  ```march
  match x do
    None ->
      let x = Some(1)
      unwrap(x)     -- fine: this `x` is a different value
    Some(v) -> v
  end
  ```

  This is the same rule that governs facts established by an `if` guard, and
  it's what keeps a fact about an outer value from being wrongly attributed to
  an inner one.

As everywhere else, the definite-failure stance applies: an `Option` whose tag
the checker can't determine is not an error.

---

## Seeing What Got Checked — `--refine-report`

Because March stays quiet about anything it can't decide, silence has two very
different meanings: "I proved this" and "I couldn't tell, so I said nothing." From the
outside they look identical — which is exactly how a `{List(a) | len(_) > 0}` contract
once shipped enforcing nothing while every test stayed green.

`--refine-report` turns the checked fraction into a number you can look at:

```
$ march --check --refine-report stdlib/list.march
refinement obligations (user code): 0 proved, 0 violated, 5 skipped
  skipped (solver-undecided): 5
refinement obligations (user + stdlib): 8 proved, 0 violated, 28 skipped
  skipped (unreflectable-predicate): 1
  skipped (solver-undecided): 27
```

One wrinkle to know before you run it: clear `.march/cas/artifacts-v2` first. A
`--check` whose sources are already in the build cache exits straight away, before
anything is parsed — so the report never runs and you get **no output at all**, while
still exiting 0. That looks exactly like "nothing to report", which is the very
confusion this flag exists to clear up. (`.march/cas/vc` is a different cache, holding
solver verdicts; clearing that one makes z3 re-decide, but doesn't change whether the
report prints.)

You get two counts because the compiler quietly prepends the whole standard library to
every compilation. **User code** counts only the call sites in the file you named —
that's the one to watch while writing a module. **User + stdlib** counts everything
raised in the run, which makes a good whole-program coverage number (March's own CI
fails the build if it climbs, since more skips means less is being checked).

Every skip says *why*: the predicate uses vocabulary the checker can't translate
(`unreflectable-predicate`), the argument's own value didn't translate
(`unreflectable-subject`), a symbol would have needed two different sorts
(`sort-conflict`), the float wellsortedness gate rejected it (`float-sort-gate`), or
the solver simply didn't decide (`solver-undecided`).

One thing the numbers don't include: they count **preconditions checked at call
sites**. Return refinements go through a different path that doesn't file a record, so
a postcondition the checker couldn't discharge won't show up here.

---

## `cap verified` — Making Silence an Error

Everything above is built around never crying wolf: if March can't prove something is
*definitely* wrong, it keeps quiet. That's the right default, but it means a contract
can be technically legal and practically inert.

If you want the opposite deal for a particular module — "I want these contracts to be
a guarantee, and I want to be told when they aren't" — declare `cap verified`. Inside
that module, a precondition at a call site that the checker can't discharge becomes a
compile error:

```march
mod Checked do
  cap verified

  fn head_of(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Cons(h, _) -> h
    Nil        -> panic("empty")
    end
  end

  fn ok(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head_of(ys) else 0 end   -- proved, so no error
  end
end
```

Take the guard away and the same call fails the build, telling you which precondition,
on which function, and why it couldn't be discharged:

```
`cap verified` module: cannot verify precondition `len(_) > 0` on `head_of`
(solver-undecided: the solver proved neither the predicate nor its negation)
note: guard the call or strengthen what is known here, rewrite the predicate
into the fragment the checker supports, or remove `cap verified` from this
module — it asks for every obligation to be discharged
```

**Know the edges before you reach for it.** It's strictly opt-in and scoped to the
module that writes it: a `cap verified` module calling an ordinary one doesn't make
the callee strict, and nested modules don't inherit it (they can't — the standard
library arrives as sibling modules, and inheriting would turn all of it strict at
once). It escalates **preconditions at call sites** only, so an undischarged
postcondition slips through. It doesn't reach into `impl` or `interface` method
bodies. And there's **no `@[trusted]` escape hatch yet** — if one obligation in the
module genuinely can't be discharged, your options are an `assert` or dropping
`cap verified` entirely. That makes it a good fit for a small, deliberately-verified
module today, and not yet something to switch on across a codebase.

---

## Limitations

No refinement system is complete — this one is intentionally a *pragmatic slice* of
dependent typing. Know the edges:

- **`Int`, `Bool`, `Float`, `String` (narrowly), records and ADT tags.**
  Predicates over other types aren't supported. `Float` predicates are
  **comparisons only**; float arithmetic inside one is skipped rather than
  guessed at, and a `Float` sitting inside a record or a constructor is opaque.
  See [Bool and Float Refinements](#bool-and-float-refinements) and
  [Constructor Tags](#constructor-tags--refining-over-adt-variants).
- **Tag narrowing stops at several ordinary shapes.** A `match` on an
  expression rather than a variable, an `as` pattern, a pattern that rebinds the
  name, an ambiguous constructor name, and any rebinding of the name inside the
  arm all leave the call *unchecked* rather than reported. See
  [Facts from a `match`](#facts-from-a-match).
- **Incomplete (by the definite-failure stance).** The checker catches values
  that are *definitely* wrong and stays silent otherwise. It will not prove
  every true property; quantified/measure facts in particular sometimes return
  "unknown" and are skipped. This never produces a false positive, but it does
  mean some real guarantees go unchecked.
- **Higher-order: two shapes are checked, the rest are not.** A call made
  through a parameter whose declared type carries a refinement —
  `f : ({Int | _ >= 0}) -> Int` — is checked, and so is a call through a local
  alias of a named refined function (`let g = takepos` then `g(-3)`). NOT
  checked: a callback parameter whose own type is unrefined (so
  `apply(take_n, -3)` with `apply(f : Int -> Int, x : Int)` still passes),
  inferring a higher-order function's requirement from its body, dispatch
  through an `interface`/`impl`, and multi-argument callback types. To
  constrain a caller today, refine the higher-order function's *own* parameter.
- **Measures see structure, not elements.** Element values inside a data
  structure are opaque to a measure (`size`/`len`/`depth` never inspect them).
  Measures are single-argument, structurally recursive, and return `Int`/`Bool`.
- **Only *some* length spellings are connected to `len`.** The qualified
  `List.length`, `String.byte_size`, and the `string_byte_length` builtin discharge a
  `len` obligation; a bare `length`, `String.codepoint_count`, and `string_length` do
  not, and a guard written with those leaves the call *skipped* rather than proved.
  The connection is also dropped module-wide if the name could denote something other
  than the standard library's own function. See [the solver really does connect
  `List.length` to `len`](#the-solver-really-does-connect-listlength-to-len).
- **Relational postconditions work, within structural recursion.** A predicate
  that relates a measure across an operation — `size(insert(t, x)) == size(t) + 1`
  — is proven by supplying the induction hypothesis at each recursive call whose
  argument is a proper component of the matched parameter, then discharging each
  `match` arm against the measure's recursion equations. Only a postcondition
  actually *proved* propagates, so an unprovable one stays legal but tells
  callers nothing. Still silent: mutual recursion, a recursive call inside a
  lambda or behind a nested `match`, and any non-structural recursion.
- **A measure over a built-in `List` with a non-scalar element does not
  axiomatise.** `List(Int)` is fine; `List(SomeAdt)` collapses the element to an
  opaque sort and the measure is never usable. A user-defined list type with the
  same shape works. This is the first obstacle between this machinery and the
  stdlib's HAMT-based `Map`.
- **`Bool` predicates need an operator form.** `{Bool | _ == true}` is checked;
  the bare-binder spelling `{Bool | not _}` is a parse error — write
  `{Bool | _ == false}`.
- **No float special values.** There is no `is_nan` / `is_finite` vocabulary, so
  a predicate cannot mention them (NaN is still modelled correctly *inside* the
  solver, which is what keeps correct code from being flagged).
- **Performance: measures can be slow on a cold cache.** Quantified + datatype
  reasoning is far more expensive per query than plain arithmetic. Verdicts are
  content-addressed and cached (warm rebuilds are fast), and the cost is
  isolated to call sites that actually mention a measure — but a cold build of
  measure-heavy code pays for it. See the flag below.

---

## Where Refinements Resolve

*This is a plumbing detail about how the checker looks up which function a call refers
to, not something you need to know to start using refinements — feel free to skip to
[Practical Rules](#practical-rules).*

Refinement checking follows the same name resolution as the type checker:
**direct named calls**, across modules, through **`alias`** and **`use`**:

```march
mod App do
  use Lib.{take_pos}          -- imported name resolves to Lib.take_pos
  alias Lib.Inner as I        -- alias resolves to Lib.Inner.*

  fn run() : Int do
    take_pos(-1)              -- error: resolved + checked against Lib's precondition
    I.helper(-1)             -- error: alias-qualified call checked too
  end
end
```

A bare call binds to the nearest enclosing module that defines it (with
shadowing), so a local helper is never confused with a same-named function
elsewhere.

---

## The `--no-measure-axioms` Flag

*Also a niche knob — only relevant if a measure-heavy build feels slow.*

Pass `--no-measure-axioms` to reflect `@[measure]` functions **symbolically**
instead of axiomatising them. This skips the datatype/quantifier reasoning (and
the soundness gate), trading structural measure reasoning for speed. It changes
only diagnostics, never the compiled artifact. Refinement checking of plain
`Int`/`Bool` predicates is unaffected and always cheap.

```bash
march --check --no-measure-axioms app.march
```

---

## Practical Rules

1. **Refine the contract, not the convenience.** Add `{Int | _ > 0}` where a
   non-positive value is a genuine bug (a chunk size, an unguarded divisor), not
   to every `Int`. Many March APIs already clamp defensively and have no real
   precondition.
2. **Guard, then call.** A precondition you can't satisfy with a literal is
   discharged by an `if`/`when` guard right before the call.
3. **Reach for `assert` as your lemma.** When you *know* a fact the checker
   can't derive, `assert(p)` makes it available — and documents the assumption.
4. **Annotate measures you'll reason about.** A `@[measure]` only earns its
   keep if a predicate mentions it; keep them total, exhaustive, and structural
   so they pass the gate.

---

## Next Steps

- [Type System](types.md) — the types refinements attach to
- [Linear Types](linear-types.md) — the other compile-time safety layer
- [Pattern Matching](pattern-matching.md) — `match` guards feed path sensitivity
