---
layout: docs
title: Refinement Types
nav_order: 5.5
permalink: /docs/refinement-types/
---

# Refinement Types

Normally, a type like `Int` only tells the compiler "this is a whole number": it gives
no hint about *which* whole numbers are actually valid here. A **refinement type** lets
you attach an extra condition to a type, so `{Int | _ >= 0}` means "an `Int`, and
specifically one that's never negative." The condition (`_ >= 0` here) is called a
**predicate**, just a true/false check on the value.

The clever part is that March doesn't just remember the condition as documentation: it
actually *proves* it, at compile time, using an automated reasoning tool called an
**SMT solver** (specifically [Z3](https://github.com/Z3Prover/z3)). An SMT solver is
software that can mechanically work out whether a set of logical/arithmetic statements
is possible or is a contradiction, the same kind of tool used to verify hardware
designs and cryptographic protocols. In March, it's put to work checking your function
contracts, so a whole class of bugs (out-of-bounds indices, negative sizes, division by
zero, broken invariants) becomes a **compile error** instead of a runtime panic.

If you've heard the term **dependent typing** (types that depend on *values*, not just
other types), refinements are March's practical, restricted slice of it. You get the
safety where it pays off (preconditions, bounds, postconditions) without a proof
assistant's ceremony; and, crucially, **without false positives**: if the checker can't
prove a value is definitely wrong, it stays silent rather than guessing.

> **Requires Z3.** Refinement checking runs only when the `z3` solver is on your
> `PATH`. Without it, the predicates type-check as their base type and no
> refinement diagnostics are produced (the build still succeeds).

**New to this?** Read [Syntax](#syntax) through
[Contracts Compose](#contracts-compose-a-parameters-promise-applies-inside-its-body)
and you'll be able to write and read everyday refinements. Everything after
[Postconditions](#postconditions) goes deeper: measures over your own data
structures, `Bool`/`Float`/tag refinements, the strict `cap verified` /
`cap no_panic` modes, and the full [Limitations](#limitations) list. If you
just want to know why a specific contract *isn't* catching something, jump
straight to Limitations or to
[`--refine-report`](#seeing-what-got-checked---refine-report).

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

Refinements appear anywhere a type does, **parameters** (preconditions) and
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
`Bool` and `Float` values are refinable too; see
[Bool and Float Refinements](#bool-and-float-refinements).

---

## How Checking Works: Definite Failure

Think of the checker as a cautious lawyer rather than an eager one: it only objects when
it can prove, beyond doubt, that you're wrong. There are exactly three outcomes for a
predicate at a given point in your code:

- The value **always** satisfies the predicate → **pass**, silently.
- The predicate is **demonstrably violated** → **compile error** with a counterexample.
  The checker has two ways to demonstrate that: the solver proves the predicate can
  never hold, or it finds a concrete input, *runs it*, and watches the contract fail
  (see [Counterexamples](#counterexamples-the-failing-input-in-source-terms)).
- Neither is established (the value is unknown, the solver can't decide, and no failing
  input was found) → **skipped**, silently.

```march
fn take_pos(n : {Int | _ >= 0}) : Int do n end

take_pos(-3)                     -- error: -3 can never be >= 0
take_pos(5)                      -- pass

fn f(k : Int) : Int do
  take_pos(k)                    -- skipped: k is unknown, might be >= 0
end
```

The consequence: **no false positives, by design, but incomplete.** The
checker never flags correct code, and never blocks a build over something it
can't disprove. It also won't *prove* everything you might hope; facts it can't
establish are conservatively let through. This trade is intentional: a
refinement checker that cries wolf is one developers turn off.

---

## Counterexamples: the failing input, in source terms

Being told a contract is broken is only half an answer; the useful half is *which
input breaks it*. When March reports a violation, it names a concrete input — and,
for a function body, the value that input actually produced:

```march
fn bump_progress(pct : {Int | _ >= 0 && _ <= 100}) : {Int | _ <= 100} do
  pct + 1
end
```

```
`bump_progress` does not satisfy its return type constraint on all code paths.

The return type requires:

    _ <= 100

but bump_progress(100) returns 101.

3 |   fn bump_progress(pct : {Int | _ >= 0 && _ <= 100}) : {Int | _ <= 100} do
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

    Every branch must produce a return value satisfying `_ <= 100`.
```

`bump_progress(100)` isn't a guess from the solver, and it isn't a random probe: it
is *the* input that breaks this function, sitting exactly on the boundary — the case
a reviewer skims past and the tests forget. The checker turned the solver's model
into a real March value, **called `bump_progress(100)`**, and watched `101` come back
and fail the predicate. Everything it prints, it ran.

Off-by-one bugs are where this earns its keep, because the counterexample *is* the
edge case:

```march
fn next_slot(i : {Int | _ >= 0 && _ < 16}) : {Int | _ < 16} do
  i + 1
end
```

```
but next_slot(15) returns 16.
```

### Why running it matters

The formula the solver sees is an *approximation* of your program. Anything March
can't translate into logic — nonlinear arithmetic, a call it can't see inside — is
dropped from the question rather than guessed at. That keeps proofs honest, but it
means a raw "here's a failing input" answer can describe a situation your program
never actually reaches:

```march
fn always_one(x : Int) : {Int | _ >= 0} do
  if x * x >= 0 do 1 else x end     -- the else branch can never run
end
```

`x * x >= 0` is nonlinear, so the guard is dropped, and the solver duly "finds" a
failure down the `else` branch. Printing that would be a false alarm on correct
code — the one thing this design refuses to do. Running the candidate returns `1`,
the predicate holds, the answer is thrown away, and **the checker stays quiet**.

So the rule is simple, and worth trusting: **every counterexample you see was
actually executed and observed to fail.** Candidates that can't be run — a function
needing real I/O, one that loops forever, a value the checker can't build — are not
reported at all; the obligation stays skipped, exactly as before.

### Counterexamples respect your other contracts

A counterexample is only fair if your function ever promised to handle that input.
Witnesses must satisfy the parameters' own refinements:

```march
fn scale(x : {Int | _ > 0}, y : {Int | _ > 0}) : {Int | _ > 100} do
  x * y
end
```

```
but scale(1, 1) returns 1.
```

`scale(0, 0)` would be an easier counterexample, but `0` is ruled out by
`{Int | _ > 0}`, so it's never blamed.

Counterexamples are also **shrunk** to the smallest failing input rather than
whatever the solver happened to pick — which is often the most useful number in the
whole message, because it's the *threshold* where things start going wrong:

```march
fn backoff_ms(attempt : {Int | _ >= 0}) : {Int | _ <= 30000} do
  attempt * 1000
end
```

```
but backoff_ms(31) returns 31000.
```

Every attempt from 31 up blows the cap; you're told the first one, so the fix (clamp
at 30) reads straight off the diagnostic. Shrinking is deterministic, so the same
program always reports the same counterexample.

Note that `x * y` never reaches the solver at all. When a contract falls outside what
March can translate, it tries a small batch of likely inputs through the same
run-and-check process. A confirmed failure gets reported; finding nothing leaves the
contract skipped. So a contract that is unprovable *and* true — `{Int | _ > 0}` over
`x * x + 1` — stays silent rather than being guessed at in either direction.

### Records and lists print the way you'd write them

```march
type Config = { port : Int, workers : Int }

fn with_port(cfg : Config, p : Int) : {v : Config | v.port >= 1024} do
  { port: p, workers: cfg.workers }
end
```

```
but with_port({ port: 0, workers: 0 }, 0) returns { port: 0, workers: 0 }.
```

At a **call site**, the example is given in terms of the caller's own variables:

```march
fn median(xs : {List(Int) | len(_) > 0}) : Int do 0 end

fn report(samples : {List(Int) | len(_) == 0}) : Int do
  median(samples)
end
```

```
refinement violation: argument `xs` of `median` does not satisfy precondition
`len(_) > 0` (e.g. samples = [])
```

`samples = []` is the offending value itself. March used to print
`len(samples) = 0` — a true statement *about* the value that you then had to work
backwards from.

### Where they show up

| Site | What the diagnostic adds |
|---|---|
| Return contract | ``but bump_progress(100) returns 101.`` |
| Call-site precondition | ``(e.g. samples = [])`` |
| `cap no_panic` division | ``(e.g. count = 0)`` |

Those are the two places March emits refinement diagnostics: the definition (return
contracts over `Int`, `Bool`, `Float` and records) and the call site (preconditions
of any checkable type, lists and strings included). A return contract over a
collection goes down a different path that stays quiet either way, so a broken
`{List(Int) | len(_) > 0}` return gets caught where the value is *used* rather than
where it's built.

> **One consequence worth knowing.** A function whose return contract is broken for
> *some* input is now a compile error in every module, not just a `cap verified` one,
> whenever a counterexample confirms it: `fn f(n : Int) : {Int | _ >= 0} do n end` no
> longer compiles. The checker hasn't become less cautious — it demonstrated the bug
> by running it. Contracts that stay genuinely undecided are unaffected.

---

## Path Sensitivity: Guards Establish Facts

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
refinement predicate; you can't call it as an ordinary function. In plain code, like
the guard above, use `List.length` instead; the solver knows they mean the same thing.)

> **Length guards count.** A guard you'd write anyway (`if List.length(ys) > 0`,
> or `if String.byte_size(s) > 0`) establishes exactly the fact a `len`-bearing
> contract like `{List(Int) | len(_) > 0}` asks for: the checker treats the qualified
> `List.length`, `String.byte_size`, and the `string_byte_length` builtin as spellings
> of the `len` measure (a bare `length`, `String.codepoint_count`, or `string_length`
> does **not** count). The same applies to a qualified spelling written *inside* the
> braces. The connection is narrow and occasionally withdrawn for a whole compilation
> unit; see [Limitations](#limitations) for the summary and
> [the appendix](#the-solver-really-does-connect-listlength-to-len) for the exact rules.

`match` arm guards (`when`) work the same way. An `assert(p)` acts as an
**assume**: it injects `p` as a fact for the code that follows:

```march
fn g(i : Int) : Int do
  assert(i >= 0)
  take_pos(i)          -- ok: the assert established i >= 0
end
```

Use `assert` as the escape hatch for facts the checker can't derive on its own
(it's the place a hand-proved lemma lives).

---

## Contracts Compose: A Parameter's Promise Applies Inside Its Body

There are two different ways a fact gets established, and it's worth keeping them
apart in your head:

- a **guard**: a runtime test you wrote, like `if List.length(ys) > 0 do …`, which
  is what the section above is about; and
- a **declared contract**: a refinement on a parameter's *type*, which the caller
  already had to satisfy before the function could be entered.

The second one is a promise you were given, so you shouldn't have to check it again.
And you don't: a refined parameter's own predicate is a fact inside the function's
body. Which means contracts **compose**: a function that requires something can pass
its own parameter straight on to another function requiring the same thing, no guard
anywhere:

```march
fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
fn outer(ys : {List(Int) | len(_) > 0}) : Int do inner(ys) end
fn main() : Int do outer([1]) end
```

Both calls are *proved*: `--refine-report` reports `2 proved, 0 violated, 0 trusted, 0 skipped`.
A contract can be threaded through as many hops as you like without re-guarding a list
you'd already promised was non-empty. That's what makes the standard library's contracts
worth having:

```march
mod Y do
  cap verified
  fn head_of(xs : {List(Int) | len(_) > 0}) : Int do
    List.head(xs)          -- proved from head_of's own contract
  end
  fn main() : Int do head_of([1, 2]) end
end
```

`List.head` wants a non-empty list; `head_of` already promised one; done. That
compiles clean even under `cap verified`, which is the strict setting that turns
every undischarged obligation into an error.

This works for every refinement shape: `Int`, `Float`, `Bool`, `String`
lengths, record fields, list `len`, your own `@[measure]` over a tree, and a
**constructor tag** (`{Option(Int) | is_Some(_)}`) all compose. The tag shape
composes only for the constructor you actually promised: promising
`is_None(_)` does not discharge a callee wanting `is_Some(_)`. See
[Limitations](#limitations).

Two things it intentionally won't do for you. First, a **weaker** promise can't
launder a stronger requirement. Declare `outer(ys : {List(Int) | len(_) >= 0})`
(which is true of every list and therefore states no fact) and the inner call goes back
to being *skipped*: not proved, and not reported either, because no value here is
definitely wrong. Second, **rebinding the name drops the fact**, since the promise
belongs to the value, not the spelling:

```march
fn outer(ys : {List(Int) | len(_) > 0}) : Int do
  let ys = List.tail(ys)   -- this call is fine: proved from ys's contract
  inner(ys)                -- skipped: the new ys promises nothing
end
```

A `match` arm that binds the same name (`Cons(_, ys) -> inner(ys)`) behaves the same.
Both leave the call quiet rather than flagged; the checker never guesses.

One related gap, which predates all of this and is easy to trip over: a fact does
**not** travel through a local `let`, for any type at all. `let u = 5` followed by
`take_pos(u)` against `{Int | _ > 0}` is skipped, even though `5` obviously satisfies
it. Pass the value directly, or state the fact with `assert`.

### An annotation on a `let` is checked, not assumed

You *can* write a refinement on a local binding, and it brings a fact forward, but
it has to earn it first:

```march
fn outer() : Int do
  let ys : {List(Int) | len(_) > 0} = [1]
  inner(ys)                                  -- proved: the annotation held
end
```

Two things are checked there, not one: the annotation against `[1]`, and then
`inner`'s precondition against the fact the annotation established. Write something
false and you get told:

```march
let ys : {List(Int) | len(_) > 0} = []
-- refinement violation: bound expression does not satisfy type annotation `len(_) > 0`
```

The annotation is checked, not believed on sight: it earns its fact only when the bound
expression actually satisfies it.

The usual stance still applies at the other end: an annotation the checker can
neither prove nor refute is **skipped**, never reported. But it then grants no fact
either, so it can't invisibly prop up a later call:

```march
fn go(zs : List(Int)) : Int do
  let ys : {List(Int) | len(_) > 0} = zs    -- skipped: nothing known about zs
  inner(ys)                                 -- also skipped, not proved
end
```

All three spellings of the value work the same way: `_`, a declared binder
(`{v : List(Int) | len(v) > 0}`), or the bound name itself (`len(ys) > 0`).

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

A postcondition is checked the same way a precondition is: a **compile
error** when it can never hold, silent **proof** when it always does, and a
silent **skip** when the checker can't decide either way. It also counts
toward [`--refine-report`](#seeing-what-got-checked---refine-report) (tagged
`postcondition` rather than `precondition`, in the report's `by kind` line)
and, inside a `cap verified` module, an undischarged postcondition is a
compile error exactly like an undischarged precondition:

```march
mod Checked do
  cap verified

  fn mk(z : Int) : {Int | _ > 0} do
    z                              -- error under cap verified: unproven
  end
end
```

`@[trusted]` rescues a postcondition the same way it rescues a precondition;
see [`cap verified`](#cap-verified-making-silence-an-error) below.

**What doesn't carry through:** proving a *plain* postcondition (as above) is
different from proving a **relational** one that relates a measure across an
operation (`size(insert(t, x)) == size(t) + 1`), which needs the checker to
supply an induction hypothesis at each structurally-recursive call. That
narrower, more powerful case is covered in [Limitations](#limitations), under
"Relational postconditions work, within structural recursion."

---

## Measures: Refining over Data Structures

Every predicate so far has been about a single plain number, like `i >= 0`. But often
the bound you actually care about depends on the *shape* of a data structure: "the
index must be less than the list's length," say. A **measure** is how you bring that
into a predicate: it's an ordinary-looking function from a value to an `Int` (or
`Bool`), except the compiler is allowed to reason about it symbolically, not just run
it. The built-in `len` measures a list this way:

```march
fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do ... end
```

You can define your own with the `@[measure]` attribute, for example the size
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
rules it's allowed to use, so for a value with a shape it can see (a literal list, an
explicit `Node`/`Leaf` tree), it can effectively "run" the measure symbolically:
from the equations above it works out `size(Node(Leaf, x, Leaf)) = 1`, so an
out-of-bounds index into a literal tree is caught, and `size(t) >= 0` is known for any
`t`. Measures may call **other measures** and be **mutually recursive** (e.g. a
`Tree`/`Forest` pair), and the built-in `List` is modelled too, so a user
`length` measure over `List(a)` reasons the same way as `size`.

### Requiring a non-empty collection

In the examples above the measure describes a *different* parameter: `len(xs)`
bounds the index `i`. A measure can just as well describe the refined value
**itself**, which is how you say "this list must not be empty":

```march
fn head(xs : {List(a) | len(_) > 0}) : a do ... end
```

Inside the predicate you can name the refined value three ways, and they all mean
the same thing and are checked identically: the anonymous `_`, your own binder,
or the parameter's name:

```march
fn head(xs : {List(a)     | len(_)  > 0}) : a do ... end
fn head(xs : {v : List(a) | len(v)  > 0}) : a do ... end
fn head(xs : {List(a)     | len(xs) > 0}) : a do ... end
```

Pass a list the compiler can see is empty and you get an error; pass one it can
see is non-empty and it reports no issue; pass one it can't see into and it stays
quiet rather than guessing:

```march
head([])            -- error: `len(_) > 0` can never hold here
head([1, 2])        -- fine
fn f(ys : List(Int)) : Int do head(ys) end   -- skipped: length unknown
```

Thirteen standard-library functions that panic on an empty argument now carry
this contract (`List.head`, `tail`, `last`, `minimum_int`, `maximum_int`, the
prelude's `head`/`tail`, `Stats.mean`/`min_val`/`max_val`, `Gen.element`/`one_of`,
and `Random.choice`), so `List.head([])` is a compile error rather than a crash.
Each contract is taken from that function's own panic message, so it never
demands more than the code already checked, and every `panic` stays in place to
catch the cases the compiler skips.

`List.nth` is the fourteenth, and the only one with a contract that talks about a
*different* parameter rather than the refined value itself:

```march
fn nth(xs : List(a), n : {Int | _ >= 0 && _ < len(xs)}) : a do ... end
```

So `List.nth([1, 2, 3], 7)` and `List.nth([1, 2, 3], -1)` are compile errors
now. An index the compiler can't pin down (by far the common case) stays
silent, just as `head(ys)` does for a list it can't see into. Before this
shipped the whole standard library and four real projects (`forgepm`,
`bastion`, `conduit`, `depot`) were swept for it: zero calls became errors.
Under `cap verified`, though, that same unbindable index is a hard error
instead of a silent skip: that mode's whole promise is that every obligation
gets discharged, so "can't tell" is no longer good enough.

An ordinary `List.length(xs) > 0` guard **does** satisfy the requirement, so these
contracts bite on a list you checked at runtime and not just on literals; see
[the solver really does connect `List.length` to
`len`](#the-solver-really-does-connect-listlength-to-len) for exactly when that
connection applies, and the (narrow) circumstances in which it's dropped.

And you don't need a guard at all when the *enclosing* function already declares the
same contract: that's a separate mechanism, and it's what
[Contracts Compose](#contracts-compose-a-parameters-promise-applies-inside-its-body)
is about.

Your own measures work in this position too, not just the built-in `len`:

```march
fn inner(t : {Tree(Int) | size(_) > 0}) : Int do 0 end

inner(Leaf)                  -- error: size(Leaf) is 0
inner(Node(Leaf, 5, Leaf))   -- fine: size is 1
```

Both directions are checked: the checker reasons about the actual argument, so
`inner(Leaf)` is rejected and `inner(Node(Leaf, 5, Leaf))` passes.

### Constant functions as bounds

A bound does not have to be a literal. A **zero-argument function whose body is
a compile-time constant** may be called inside a predicate, and it is checked
exactly as if its value had been written in place:

```march
fn size_x() : Int do 128 end
fn size_y() : Int do 2 * size_x() end

fn index(x : {Int | 0 <= _ && _ < size_x()},
         y : {Int | 0 <= _ && _ < size_y()}) : Int do x + size_x() * y end

index(5, 255)     -- proved
index(128, 0)     -- rejected: 128 < size_x() is false
```

This is what lets a program name a dimension once (`World.size()`) and keep
static bounds checking on everything indexed by it, instead of freezing the
literal into every refinement and every guard. A qualified spelling
(`_ < 16 * World.size()`) works the same way.

"Constant" means the body folds without running anything: `Int`/`Bool`
literals, `+ - *` and `negate`, `&& || not`, and calls to other constant
functions. `/` and `%` are deliberately excluded (a fold that disagreed with
the runtime's truncation would assert a false fact). A zero-argument function
whose body does not fold, say one that calls a function with parameters,
draws a warning at the predicate naming the reason, and the refinement is not
checked. No annotation is involved; in particular `@[measure]` is **not** the
remedy: a measure is a function of the value it measures, and annotating a
constant with it is a compile error (see the gate below).

Folding applies wherever the checker reflects an expression, so a call
`takepos(neg_one())` with `fn neg_one() : Int do 0 - 1 end` is a definite
violation rather than an unverified one. If a function binds a local of the
same name (`let size_x = fn -> 7`), folding is suspended inside that function
and the call is treated as opaque.

### The measure soundness gate

The solver trusts a `@[measure]` completely: it treats the function's body as a fact
about the world. That means a badly-behaved measure (one that never finishes, divides
by zero, or skips a case) could let the solver "prove" something false. To prevent that,
the compiler requires every measure to be verifiably well-behaved before it's allowed to
be used at all: a **hard compile error** if it isn't. A `@[measure]` is rejected if it:

- has an **effect** (`spawn`, `send`, `dbg`, `assert`); it must be pure,
- can **diverge or abort** (`panic`, `todo`, `exit`); it must always finish,
- is **non-total** (a non-exhaustive `match` on its parameter, or a `/` / `%`
  that could divide by zero); it must handle every case,
- is **not recursive over the structure** (a recursive call with an argument that isn't a
  component of the matched parameter); each call must work on a strictly smaller piece
  of the input, so it's guaranteed to terminate.
- does **not take exactly one parameter**, the value it measures. A predicate can
  only apply a measure to one argument, so a zero-argument or multi-parameter
  `@[measure]` could never be translated; the annotation would only silence the
  vocabulary warning while every call site went unverified. A zero-argument
  constant needs no annotation at all (see [Constant functions as
  bounds](#constant-functions-as-bounds)).

A measure that is sound but outside what the encoding can model (see
limitations, below) isn't an error: it simply falls back to weaker, symbolic
reasoning. "Weaker" can mean *no reasoning at all*: a measure with a value that is a
scalar constructor field discharges neither a predicate nor its negation. See
[Limitations](#limitations); that case is not always warned about.

---

## Bool and Float Refinements

A `Bool` parameter or return takes a predicate over the ordinary boolean
operators (`==`, `!=`, `&&`, `||`, `not`) against `true` and `false`:

```march
fn commit(confirmed : {Bool | _ == true}) : Int do ... end

commit(false)   -- rejected: `_ == true` can never hold at `false`
commit(true)    -- fine
```

Write the **operator form**: `{Bool | not _}` does not parse, so use
`{Bool | _ == false}`. An unknown `Bool` is skipped, and a guard works as you'd
expect: `if k do commit(k) else 0 end` passes.

A `Float` parameter or return takes a **comparison** (`>=`, `>`, `<=`, `<`,
`==`, `!=`) against float literals or another float value:

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
makes that **impossible**; and since the checker objects exactly when a
predicate can *never* hold, it would flag this contract on every argument. Over
floats it is perfectly possible, witnessed by `NaN`, which compares false
against everything; so the checker correctly stays silent.

Equality is `fp.eq` (IEEE equality), not bitwise identity. Under bitwise
identity `-0.0` would differ from `0.0` and `{Float | _ != 0.0}` would accept a
negative zero, just as bad a divisor as a positive one. Under `fp.eq`,
`-0.0 == 0.0` is true (so a negative zero **is** rejected) and `NaN` equals
no value, not even itself.

Float **arithmetic inside a predicate** (`{Float | _ +. 1.0 > 0.0}`) is out of
scope: modelling it needs rounding-mode reasoning, so the whole predicate is
skipped rather than approximated. Arithmetic over float *literals* is different:
`0.0 -. 1.0` is folded to a constant first and is fully checked, which is how a
negative literal (which March has no direct spelling for) still works.

---

## Constructor Tags: Refining over ADT Variants

Refinements aren't limited to numbers and sizes. You can also require that a
value is a *particular variant* of a union type. Every constructor (in your own
types, and in the built-in `Option`, `Result` and `List`) implicitly comes with
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
`Some`; `is_some` is *not* a tester: it's the lowercase stdlib helper
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

This narrowing is intentionally conservative. Where it stops, the checker goes
quiet rather than guessing, so these are all *silence*, never false alarms:

- **The scrutinee has to be a plain variable.** `match mk() do …` matches an
  expression, and there's no stable name to attach a fact to, so no code inside
  the arms is narrowed. Bind it with a `let` first if you want the fact.
- **A pattern that rebinds the name ends it.** Matching `y` with `Some(x) ->`
  gives you no fact about `x`: that `x` is a fresh name for the payload, not
  for the scrutinee.
- **An `as` pattern isn't narrowed.** `None as z ->` binds the whole scrutinee
  under a second name, but the arm's head is an `as` pattern rather than a bare
  constructor pattern, so no tag fact is recorded: not for `z`, and not for the
  scrutinee. Write `None ->` if you want the narrowing.
- **An ambiguous constructor name is skipped.** If two types in scope both
  declare a constructor `Row`, then `is_Row` doesn't identify a particular type
  and isn't checked.
- **Rebinding the name discards the fact.** A narrowing is recorded against a
  *name*, so anything that rebinds that name inside the arm (a `let`, a `let?`,
  a lambda parameter, an inner `match` binder) drops it:

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

As everywhere else, the definite-failure stance applies: an `Option` with a tag
the checker can't determine is not an error.

Later arms also learn what the earlier ones ruled out. Reaching an arm means
every arm above it failed to match, so for each of those with a failure
decided purely by the tag, the scrutinee is known *not* to carry it:

```march
fn mean_safe(xs : List(Float)) : Result(Float, String) do
  match xs do
  Nil -> Err("empty")
  _   -> Ok(mean(xs))   -- `mean` needs len > 0; the `_` arm has it
  end
end
```

For a **list**, a tag test is a statement about length (`is_Nil(xs)` means
`len(xs) = 0` and `is_Cons(xs)` means `len(xs) > 0`), so the exclusion above
discharges a `len`-bearing precondition directly. This is what makes the
safe-wrapper idiom (match the empty case, return `Err`/`None`, do the real work
in the other arm) check out. The same idea generalizes to a user `@[measure]`:
a base-case arm with a body that is a literal gets an axiom linking its constructor's
tester directly to the measure's value, so the exclusion connects there too.

An earlier arm licenses **no fact** if it includes a guard or a refutable
sub-pattern, because either can fail with the tag still matching:
`Cons(0, _)` does not match `Cons(1, [])`, which is nonetheless a `Cons`, and
`Nil when flag` fails whenever `flag` is false. So

```march
match xs do
Nil -> Err(…)
Cons(_, Nil) -> Err("need at least 2")
_ -> Ok(std_dev(xs))     -- knows only len > 0, NOT len > 1
end
```

still abstains on a `len > 1` requirement, which is the accurate answer.

---

## Seeing What Got Checked: `--refine-report`

Because March stays quiet about anything it can't decide, silence has two very
different meanings: "I proved this" and "I couldn't tell, so I kept quiet." From the
outside they look identical, which is exactly how a `{List(a) | len(_) > 0}` contract
once shipped with zero enforcement while every test stayed green.

`--refine-report` turns the checked fraction into a number you can look at:

```
$ march --check --refine-report stdlib/list.march
refinement obligations (user code): 1 proved, 0 violated, 0 trusted, 5 skipped
  skipped (partial-conjunct): 1
  skipped (unconstrained-subject): 4
  by kind: 6 precondition, 0 postcondition, 0 division
refinement obligations (user + stdlib): 17 proved, 0 violated, 0 trusted, 33 skipped
  skipped (partial-conjunct): 1
  skipped (solver-undecided): 1
  skipped (unconstrained-subject): 31
  by kind: 50 precondition, 0 postcondition, 0 division
```

`--refine-report` records a [promoted call-site failure](#promoting-a-skip-a-demonstrated-precondition-failure)
under `violated`, the same bucket used for a contract the solver proved can
never hold. A nonzero `violated` count on a module with no `cap verified`
annotation is therefore not necessarily a bad annotation; it can be a
demonstrated call-site failure the checker found on its own. The report does
not currently distinguish the two shapes.

One wrinkle to know before you run it: clear `.march/cas/artifacts-v2` first. A
`--check` with sources already in the build cache exits straight away, before
anything is parsed, so the report never runs and you get **no output at all**, while
still exiting 0. That looks exactly like "no obligations to report", which is the very
confusion this flag exists to clear up. (`.march/cas/vc` is a different cache, holding
solver verdicts; clearing that one makes z3 re-decide, but doesn't change whether the
report prints.)

You get two counts because, behind the scenes, the compiler prepends the whole standard library to
every compilation. **User code** counts only the call sites in the file you named;
that's the one to watch while writing a module. **User + stdlib** counts everything
raised in the run, which makes a good whole-program coverage number.

March's own CI ratchets on both directions: an **upper limit** on skips (more skips means
less is being checked) and a **floor** on proofs. The floor matters more than it
sounds: an upper limit on its own is satisfied perfectly by a checker that raises no
obligations at all, and the floor is read from a small fixture with one obligation,
*proved* by a `List.length` guard, so it collapses to zero the instant the measure
alias stops working. This is the failure mode the report exists to expose: a skip and a
proof both exit 0, and only the count can tell them apart.

Every skip states *why*, one of nine reasons: the predicate's own
sub-expression named in the message has no SMT translation
(`unreflectable-predicate`), the argument named in the message could not be
translated (`unreflectable-subject`), a symbol would have needed two
different sorts (`sort-conflict`), the float wellsortedness gate rejected it
(`float-sort-gate`), a measure alias the guard relied on had been withdrawn
(`alias-withdrawn`; see below), no fact the checker derived constrains the
argument the predicate talks about (`unconstrained-subject`), the predicate is
a top-level `&&` and only some of its conjuncts were proved
(`partial-conjunct`; the message names which held and which did not), the goal
names a function the checker has no meaning for (`opaque-application`), or the
solver simply didn't decide either way (`solver-undecided`).

`unconstrained-subject`, `partial-conjunct`, and `opaque-application` are all
more specific answers to the same question `solver-undecided` asks: they fire
only where the VC was built and the solver ran, and each names a narrower
reason the proof didn't go through.

These three diagnosed reasons, plus `unreflectable-predicate` and
`unreflectable-subject`, print at *every* call site that has one, not once
per module: both of those two now name the specific sub-expression or
argument that failed, so repeating the message at every site is a distinct
fact each time. Three of the residual reasons (`solver-undecided`,
`sort-conflict`, and `float-sort-gate`) keep the older behavior: one hint per
module, because their message says the same thing regardless of which call
triggered it. A diagnosed reason does not: "nothing constrains `n`" and
"`_ >= 0` held here, `_ < len(xs)` did not" are different facts about
different calls, so printing only the first one found would hide the rest.

`alias-withdrawn` follows neither rule: outside `cap verified` it prints no
hint at all, not even once per module. It is still counted in
`--refine-report`, and under `cap verified` it becomes its own error; see
[below](#when-the-guard-is-right-and-the-error-still-fires).

**Which one gets blamed.** A call's argument (the "subject") is reflected
first; if that reflection fails, the whole call is filed as
`unreflectable-subject` naming the argument, and the predicate is never even
reached. Only when the subject reflects fine does a further failure get
filed as `unreflectable-predicate`, naming the innermost sub-expression of
the predicate that had no translation. The same rule applies to a
postcondition: the function's own return expression is the subject there,
so a return expression that fails to reflect is `unreflectable-subject`, not
`unreflectable-predicate`, even when the postcondition itself is fine. One
gap: a predicate that never reaches the bare subject at all (only a measure
over it, or an opaque call over it) still blames the predicate when the
predicate is itself unreflectable, even though the subject may also be
opaque. A sibling parameter's actual (an argument the predicate mentions by
name, not the refined parameter's own subject) is not covered by this rule
yet and still blames the predicate.

Two generated examples, one per reason. `unreflectable-subject`, from the
compiler's own test corpus (`test/native/simd_lane_panic.march`, a
`Simd.extract_i32x4` call whose lane index comes from an unrefined helper):

```
$ march --check test/native/simd_lane_panic.march

-- HINT -- test/native/simd_lane_panic.march

precondition `0 <= _ && _ < 4` on `Simd.extract_i32x4` was NOT verified here.
the argument `lane(1)` could not be translated to SMT, so no goal was built

25 |     println(Simd.extract_i32x4(v, lane(1)))
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

`unreflectable-predicate`, for a predicate built on an ordinary function
rather than a measure:

```
mod UpDoc do
  needs IO.Console

  pfn is_prime(n : Int) : Bool do n == 2 || n == 3 || n == 5 || n == 7 end

  fn f(n : {Int | is_prime(_)}) : Int do n end

  fn main(_cap_console : Cap(IO.Console)) : () do
    println(f(7))
  end
end
```

```
$ march --check up_doc.march

-- WARNING -- up_doc.march

`is_prime` is not a measure or known predicate, so this refinement is not checked. Annotate the function `@[measure]`, or use a supported predicate.

6 |   fn f(n : {Int | is_prime(_)}) : Int do n end
                      ^^^^^^^^^^^



-- HINT -- up_doc.march

precondition `is_prime(_)` on `f` was NOT verified here.
the predicate's `is_prime(_)` has no SMT translation

9 |     println(f(7))
                ^^^^
```

The counts include both **preconditions checked at call sites** and
**postconditions**: a function's own return value checked against its declared
return type. Each obligation is tagged with its kind, shown as a `by kind`
breakdown line under each slice; a proved postcondition counts toward the same
"proved" headline as a proved precondition, and [`cap verified`](#cap-verified--making-silence-an-error)
(below) escalates an undischarged one of either kind.

---

## Coverage Audit: Does the Checker Even Look at This Refinement?

`--refine-report` counts obligations, but an obligation only exists once
*something* files it. It says nothing about a declared refinement that never
reaches a goal-building call site at all, because the checker has no code
path that ever looks at that position in the first place. `--refine-audit`
answers that narrower, prior question: for every `{Base | pred}` written
anywhere in the module, does any extractor in the checker ever consult it?

```
$ march --check --refine-audit stdlib/list.march
coverage audit (user code): 7 enforced, 0 inert (warned), 0 unenforced
coverage audit (user + stdlib): 63 enforced, 0 inert (warned), 0 unenforced
```

Every declared refinement is sorted into exactly one of three buckets:

- **Enforced**: the checker's own extractor for this position accepts the
  declared type, so a call site (or the function's own body, for a
  postcondition) gets an obligation filed against it. A parameter that is
  never called from anywhere still counts as Enforced: enforcement is a
  property of the checker's own scope-registration for that parameter's
  position, not of whether a caller exists yet. See below for why this is the
  right reading, not a loophole.
- **Inert (warned)**: a `sig` entry, an `extern` signature, or an
  `interface` method whose refinement the compiler already flags with its
  own warning (`warn_sig_fn_refinement` and friends). The compiler tells you
  about these today; the audit just confirms the warning still fires.
- **Unenforced**: declared, silent, and nothing tells you. No extractor in
  the checker ever looks at this position, so a value that violates the
  written predicate is accepted without complaint.

A line for each `Unenforced` site is printed, one per position, naming the
file, line, column, the enclosing declaration, the predicate, and *why*
nothing checks it. For:

```march
mod PINAUDIT1 do
  type Box = { v : {Int | v > 0} }

  fn f(n : {Int | n > 0}) : {Int | _ > 0} do
    n
  end

  fn main() : Int do
    f(1)
  end
end
```

```
$ march --check --refine-audit t.march
coverage audit: t.march:2:26: field `Box.v`: v > 0: a record (or actor-state) field's declared type is never re-examined once a value is constructed; the checker has no extractor for a stored field, only for a parameter, a return, or a let-binding
coverage audit (user code): 2 enforced, 0 inert (warned), 1 unenforced
coverage audit (user + stdlib): 65 enforced, 0 inert (warned), 1 unenforced
```

`f`'s parameter and return are both Enforced; only `Box.v`'s field refinement
is Unenforced. The `user + stdlib` total (65) is the whole run's site count:
this file's 2 sites plus the 63 the shipped stdlib always contributes.

### Why an uncalled parameter still counts as Enforced

This is the design's central subtlety, and it is easy to get backwards. A
parameter refinement is not enforced by there being callers; it is enforced
by the checker's scope machinery accepting the declared type at all,
`refined_param_ty` running over `fn f(n : {Int | n > 0}) : Int do ... end`
registers `n > 0` as a fact inside `f`'s own body and would raise an
obligation at *any* call site, present or future. Whether such a call site
exists yet is orthogonal: adding one tomorrow gets checked automatically,
because the position itself is wired into the checker. That is exactly the
same reading `--refine-report`'s obligation count already uses (an unproven
obligation and a not-yet-filed obligation are different questions), and the
audit stays consistent with it rather than inventing a second, incompatible
notion of "checked."

Contrast that with a lambda's own parameter (`fn (n : {Int | n > 0}) -> n`):
no scope machinery ever runs over an `ELam`'s parameters at all, so *no*
call through that lambda, ever, is obliged by it. That is genuinely
Unenforced, not just uncalled.

### Where the current baseline stands

A sweep of the corpus the refinement oracle already walks
(`test/native/*.march` and `stdlib/*.march`, ~300 files) finds 63 declared
refinements, every one Enforced: zero Unenforced, zero Inert. That baseline
is committed at `test/refine_audit/corpus.baseline`, ratcheted in CI, and
regenerated the same way the TIR golden snapshots are
(`UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe -e`). It
being empty is a true fact about today's corpus, not evidence the audit does
nothing: `test/refine_audit/holes/` is a second, deliberately non-empty
fixture set built from known holes (a lambda's own parameter, a block-level
`fn`'s parameter and return, a non-adoptable `impl` method's parameter, an
actor's state field and handler parameter, a nested field refinement, and a
`{String | ...}` return), pinned at `test/refine_audit/holes.baseline`. If
that second baseline ever reported zero Unenforced sites, the audit itself
would be broken, not the corpus; the test that diffs it fails loudly with
exactly that message rather than passing vacuously.

The positions currently known to be Unenforced, none of which the corpus
above happens to exercise:

- A lambda's own parameter (`fn (n : {Int | n > 0}) -> ...`).
- A block-level `fn`'s own parameter and return type. `check_fn_post_verdict`
  and `scope_add_param` are only reached through `A.DFn` / `A.DImpl`, never
  through a local `A.ELetFn`.
- An `impl` method's parameter, when the method's bare name is not adoptable
  (more than one `impl` defines it, or a top-level `fn` shares the name):
  `visit_decl` strips the refinement from the body in that case, and no
  caller is ever obliged. The audit reports every `impl` method parameter as
  Unenforced regardless of adoptability, since a single site cannot make that
  module-level judgement; when the method *is* actually adoptable the checker
  does enforce it, and this over-approximation is a documented conservatism,
  not a bug of its own.
- An actor's state field, and a handler's own parameter. No extractor exists
  for either.
- A record field or a variant constructor argument, once a value is
  constructed.
- A refinement nested below the outermost position of a declared type (inside
  a type argument, an arrow side, a tuple element, or a second layer of a
  stacked refinement).
- A `{String | ...}` return type: `return_refine_ext` only recognizes Int,
  Bool, Float, and record bases.
- A parameter refinement that desugar drops or relocates before the audit
  ever sees it: a multi-head function's clause merge, or a default-argument
  function's mangled arity variant. See the next section.

See `specs/todos/2026-09-03-lambda-param-refinement-unchecked.md`,
`specs/todos/2026-09-03-block-fn-refinement-unchecked.md`,
`specs/todos/2026-09-03-impl-method-param-refinement-unchecked.md`,
`specs/todos/2026-09-03-actor-state-and-handler-refinement-unchecked.md`,
`specs/todos/2026-09-01-nested-refinement-enforcement.md`,
`specs/todos/2026-09-03-string-return-refinement-unchecked.md`, and
`specs/todos/2026-09-03-desugar-dropped-refinement-unchecked.md` for
reproducers and root causes.

### Why the audit needs the pre-desugar AST too

A whole-plan review found two shapes where reading only the POST-desugar
declaration list is not enough, and both are corrected as of this section:

- A multi-head function (two or more `fn` clauses for the same name) is
  merged by desugar into a single clause whose parameters are rebuilt with
  no declared type at all. A refined parameter on one of the original
  clauses vanishes before the audit ever runs: not `Unenforced`, simply
  absent, which is worse than a false negative because nothing at all
  reports it.
- A default-argument function survives desugar only under mangled
  arity-variant names (`f$2`, `f$1`, ...); no declaration named `f` remains.
  A refined parameter that lands on the survivor used to report `Enforced`,
  because the checker's own extractor genuinely does accept it there, but
  a plain call written `f(...)` can never resolve to that mangled name, so
  nothing a user writes ever reaches the check.

Both are now caught by comparing the declaration list from BEFORE desugar
ran against the one from after: a declared refinement present before and
absent after (matched by its enclosing declaration's name and its
predicate's exact text) is reported `Unenforced`, regardless of what a
post-desugar site at a similar-looking position might say. A `Return` site
is matched by predicate text alone, not by name: a postcondition is
checked against a function's own body regardless of what the declaration
is named, so `expand_defaults_decl`'s renamed full-arity variant is still
correctly `Enforced` for its return type even though its parameter is not.

```
$ march --check --refine-audit --refine-report t6e.march
coverage audit: t6e.march:3:27: param `f` #1: b > 0: this refinement was declared here, but no occurrence with the same enclosing name and predicate text survives desugaring: either the declared type was discarded entirely (a multi-head function's clause merge drops every parameter type before the checker ever sees it) or it now lives only under a mangled name a plain call cannot resolve to (a default-argument function's arity variant, e.g. `f$2`). See specs/todos/2026-09-03-desugar-dropped-refinement-unchecked.md.
coverage audit (user code): 1 enforced, 0 inert (warned), 1 unenforced
```

(`t6e.march` is `fn f(a : Int, b : {Int | b > 0} \\ 1) : Int do a + b end`,
called as `f(1, 0)`.) `test/refine_audit/holes/default_param.march` and
`multi_head.march` pin both shapes; `test/refine_audit/holes/type_arg.march`,
`arrow_domain.march`, and `linear_wrapper.march` pin the three remaining
nested positions this section's list already named but the holes set had
not yet covered.

This comparison covers only the entry file and its resolved imports, not
the shipped stdlib: a sweep already established the stdlib contains
neither shape today.

---

## Promoting a Skip: a Demonstrated Precondition Failure

Most skips stay silent because the checker genuinely can't decide either way.
A narrow slice is different: the checker can *prove* the skip is a real bug.
When an argument reaches a refined parameter and the obligation is skipped,
the checker runs the *enclosing* function on the solver's own model, watches
for a real `panic`, and then checks whether fixing just that one argument
makes the function return instead of panicking. When both hold, the skip is
promoted from silence to a warning (an error under `cap verified`).

```march
mod Stats do
  fn percentile(xs : {List(Float) | len(_) > 0}, p : {Float | _ >= 0.0 && _ <= 100.0}) : Float do
    match xs do
    Nil -> panic("Stats.percentile: empty list")
    _   -> percentile_sorted(sort_floats(xs), p)
    end
  end

  fn median(xs : List(Float)) : Float do
    percentile(xs, 50.0)
  end
end
```

```
`median` propagates a requirement it doesn't declare.

`percentile` requires  len(_) > 0
but median([]) panics — "Stats.percentile: empty list"

help: declare what `median` actually needs —
        fn median(xs : {List(Float) | len(_) > 0}) : Float
`forge fix` can apply this.
```

**Read the claim precisely.** It says `median` panics on some input (`[]`); it
does not say `percentile` panicked wrongly. `percentile`'s own contract,
`len(_) > 0`, is exactly what rules `[]` out. The bug is that `median` never
forwards that requirement to its own caller.

Outside `cap verified` this is a warning; inside it, the identical message is
a compile error. The `help:` block names the precondition to add and
`forge fix` can rewrite the signature for you, but not every promotion earns
one: when the callee has more than one unforwarded precondition and no single
parameter fix is unambiguously correct, the promotion still fires with no
`help:` block. `Stats.quantile_default` in `stdlib/stats.march` is this
shape (its callee needs both a non-empty list and a `q` in `[0.0, 1.0]`), and
reports with no fix offered.

Promotion is not attempted at spans inside the standard library when the
stdlib is merely imported: those diagnostics never reach the printed stream,
so promoting them would spend real work on a count nobody sees. Compiling a
stdlib file directly as the entry file is different: its own spans are user
spans there, and it reports its own promotions like any other module.

---

## `cap verified`: Making Silence an Error

Everything above is built around never crying wolf: if March can't prove something is
*definitely* wrong, it keeps quiet. That's the right default, but it means a contract
can be technically legal and practically inert.

If you want the opposite deal for a particular module ("I want these contracts to be
a guarantee, and I want to be told when they aren't"), declare `cap verified`. Inside
that module, an obligation the checker can't discharge — a precondition at a call
site, or a return refinement at a definition — becomes a compile error:

```march
mod Checked do
  cap verified

  fn head_of(xs : {List(Int) | len(_) > 0}) : Int do
    match xs do
    Cons(h, _) -> h
    Nil        -> 0
    end
  end

  fn ok(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head_of(ys) else 0 end   -- proved, so no error
  end
end
```

Take the guard away entirely and the same call fails the build, telling you
which precondition, on which function, and why it couldn't be discharged. With
nothing left constraining `ys`, the reason is `unconstrained-subject`:

```
`cap verified` module: cannot verify precondition `len(_) > 0` on `head_of`
(unconstrained-subject: no fact the checker derived constrains `ys`)
note: guard the call or strengthen what is known here, rewrite the predicate
into the fragment the checker supports, or remove `cap verified` from this
module — it asks for every obligation to be discharged
```

Weaken the guard instead of dropping it (`if List.length(ys) >= 0 do
head_of(ys) else 0 end` is always true, so it proves nothing) and a fact stays
in scope, which falls back to the residual `solver-undecided` reason, with the
same note:

```
`cap verified` module: cannot verify precondition `len(_) > 0` on `head_of`
(solver-undecided: the solver proved neither the predicate nor its negation)
note: guard the call or strengthen what is known here, rewrite the predicate
into the fragment the checker supports, or remove `cap verified` from this
module — it asks for every obligation to be discharged
```

If `head_of`'s `Nil` arm panics instead of returning `0`, dropping the guard
produces a different message altogether: the checker can execute `head_of` and
observe the panic, so the skip is *promoted* instead of reported as
`unconstrained-subject`. See
[Promoting a Skip](#promoting-a-skip-a-demonstrated-precondition-failure)
above.

### When the guard is right and the error still fires

The length aliases (`List.length`, `String.byte_size`, `string_byte_length`) are
withdrawn for the **whole compilation unit** as soon as anything in it binds that
name: the check is syntactic and doesn't ask whether the competing binding could
actually win where you called it. Normally the only cost is a proof. Inside
`cap verified` it costs you a build, so the message reports it rather than blaming the
solver:

```
`cap verified` module: cannot verify precondition `len(_) > 0` on `head`
(alias-withdrawn: the guard uses `List.length`, but this compilation unit also
BINDS that name, so the checker withdrew its built-in measure meaning and the
guard proved nothing)
note: at least one binding of `List.length` in this compilation unit
(ver3.march:5) withdrew the alias for the WHOLE unit, including this call — …
```

The culprit can be somewhere you'd never suspect: a nested `mod Internal do mod List
do fn length …` that nothing can even call as `List.length`, an unrelated function's
`let string_byte_length = n + 1`, or a definition inside a `MARCH_LIB_PATH` dependency
you never opened. The span in the note is where to look: it names *at least one* such
binding, and the alias only comes back when every one of them is gone. Rename them, or
state the fact you need as a refinement instead of a runtime guard.

You'll only see this reason when the withdrawal is plausibly what stopped the proof:
the predicate has to use the affected measure, and this call's own argument has to be
guarded by the withdrawn spelling, positively, on the matching kind of value. A guard
on a *different* list, a `List.length` guard in front of a *string* contract, and a
guard on the `else` side (which disproves the predicate rather than failing to prove
it) all keep the plain `solver-undecided` message, because in each of those the
binding you'd be sent to rename is not the reason anything failed. An unguarded call
is not blamed on the withdrawal either, but it does not fall back to
`solver-undecided`: with no guard at all, nothing constrains the argument, and that's
its own reason (`unconstrained-subject`, below).

The price of that caution is coverage: a guard laundered through a local
(`let n = List.length(ys)` and then `if n > 0`), applied to something other than a
plain variable, or established up in a caller falls back to the general message even
when a withdrawal really was the cause. The reason exists to explain one specific
confusion, not to claim every skip.

**Know the edges before you reach for it.** It's strictly opt-in and scoped to the
module that writes it: a `cap verified` module calling an ordinary one doesn't make
the callee strict, and nested modules don't inherit it (they can't: the standard
library arrives as sibling modules, and inheriting would turn all of it strict at
once).

It reaches every declaration form in the module it's written in: a call inside an
`impl` method, an `interface` default body, a top-level `let`, an actor handler or a
`test` all raise obligations that get escalated. Both this walk and `cap no_panic`'s are
exhaustive over the declaration forms, so a future one is a compile error in the compiler
rather than a new silent hole.

It also covers **postconditions**: an undischarged return refinement is a
compile error under `cap verified` too, exactly as a precondition is; see
[Postconditions](#postconditions) above for the example.

One real limitation, and one escape hatch, worth knowing before you rely on it:

- **A refinement in an `interface`'s own method signature isn't enforced,
  and the compiler tells you so.** Write `fn run : a -> {Int | _ > 0} -> Int`
  in the interface and no call site is obliged by it. No body assumes it
  either, so it's a missing check rather than an unsound one. Writing a
  refinement there produces a warning:

  > the interface signature of `run` carries a refinement, which enforces
  > nothing: an interface method signature is never read by the refinement
  > checker, so no call site is obliged by this predicate and no body may
  > assume it. Write the refinement on the corresponding `impl` method's own
  > signature instead — a refinement on its return type is always checked,
  > and one on a parameter is enforced when the method name is unambiguous
  > (exactly one `impl` defines it and no top-level `fn` shares the name).

  **Inside a `cap verified` module this is an error, not a warning.**
  `cap verified`'s escalation otherwise fires only on undischarged obligations
  in the ledger, and an inert interface signature raises none, but the
  capability's whole promise is "if it compiles, it is proved," and this is
  exactly the shape of silent-no-op contract it exists to catch, the same
  reasoning that already made the `sig`/`extern` case below a warning
  everywhere. Outside `cap verified` the message above is unchanged and still
  only a warning.

  The same silent-no-op shape exists for a `sig` ascription and an `extern`
  declaration, and both warn too: `sig Store do fn put :
  Int -> {Int | _ > 0} end` compiles clean while enforcing no contract, because
  a `sig` is an ascription on what a module exports, not a body a call could
  be checked against; write the refinement on the module's own `fn`
  instead. An `extern` refinement is the more fundamental case: the callee
  isn't March code, so there's no body to check a return value against, and
  no amount of rewiring makes it enforceable in principle. The fix there
  is a thin March wrapper around the extern call that checks the foreign
  result itself.

  Enforcement on the `impl` method's parameter, when you use that spelling,
  is conditional. An `impl` method's parameter refinement obliges callers only
  when the method's name unambiguously denotes it: no `fn` in the same module
  owns the name, and only one `impl` defines the method. A call is resolved
  here by *name* while it dispatches by *type*, and checking correct code
  against a predicate it never touches is the one failure this subsystem
  must never have. When the name is ambiguous the refinement binds
  **no one**: it's stripped from the body too, so it can't discharge
  anything either. Unenforced means unusable in both directions, never
  "assumed inside the body but demanded of no caller", which would otherwise let
  `fn run(b, k : {Int | k != 0})` make `m / k` provable under `cap no_panic`
  while `run(Box(4), 0)` compiled and then divided by zero.
- **`@[trusted]` is a per-function escape hatch.** Annotate a
  single function `@[trusted]` and any obligation inside it that the checker
  could not otherwise discharge is accepted as an assertion instead of an
  error, recorded as its own `Trusted` verdict in `--refine-report`, never
  folded into `proved`. It never suppresses a definite violation (a predicate
  the solver proved can never hold is a bug in the annotation, not something to
  wave through), and it is scoped to the one function that has it: a
  sibling function in the same `cap verified` module is unaffected. Putting
  `@[trusted]` on a function outside `cap verified` warns, since it would
  otherwise have no effect and give no sign.

That makes `cap verified` viable for a whole module even when one call site
truly cannot be proved, without switching off verification for everything
else in it.

---

## `cap no_panic`: Divisions That Can't Panic {#cap-no_panic--divisions-that-cant-panic}

`cap verified`'s sibling takes the same "silence is not good enough" stance and points
it at one specific runtime panic: integer division by zero. Declare `cap no_panic` in a
module and **every** `/` and `%` in it must have a divisor the checker can prove
non-zero. Anything short of a proof is a compile error: that's the whole promise, and
it's why this capability fails closed where the default refinement stance fails open.

A divisor is discharged by a literal, by a path condition, or by a refinement on the
parameter it came from. Both sides of a guard count:

```march
mod NonlinearDivisor do
  needs IO.Console
  cap no_panic

  fn scale(d : {v : Int | v * v > 0}) : Int do
    10 / d
  end

  fn guarded(d : {v : Int | v * v > 0}) : Int do
    if d == 0 do 0 else 10 / d end
  end

  fn main() do
    println(int_to_string(scale(2) + guarded(5)))
  end
end
```

Both of those are accepted. `v * v > 0` is exactly `v != 0` over the integers, and the
checker now passes such a predicate to the solver rather than declining to read it:
rejecting a *complete* proof for being written unusually was a false positive on
correct code. The stance itself hasn't moved: a predicate that reflects but proves
no fact (`v * v >= 0`, true of every integer) is still an error, and so is one the
solver can't settle. And on the `else` side of `if d == 0` the fact in scope is
`not (d == 0)`, which discharges the division on its own.

**It covers the whole module.** The division walk descends into every declaration form,
not just `fn` and nested `mod` bodies, so this program is a compile error rather than a
runtime "division by zero":

```march
mod ImplDiv do
  needs IO.Console
  cap no_panic

  type Box = Box(Int)

  interface Runner(a) do
    fn run : a -> Int
  end

  impl Runner(Box) do
    fn run(b) do
      match b do
        Box(n) -> 100 / n
      end
    end
  end

  fn main() do
    println(int_to_string(run(Box(2))))
  end
end
```

It's a compile error. Add the `if n != 0` guard and it's accepted: the walk
reads the body, it doesn't just distrust it. Top-level `let`s, `interface` defaults,
actor handlers, `app` hooks and `test` bodies are covered the same way.

**A rebound name inherits no fact from the old one.** Every fact the divisor check reads
is keyed by a bare variable name (the path condition, the parameter's refinement, a
`let`'s value), so rebinding that name retires all of them. Each of these is caught
rather than silently accepted:

```march
if d == 0 do 0 else (let d = 0; 10 / d) end     -- else side
if d != 0 do (let d = 0; 10 / d) else 0 end     -- then side
if d == 0 do 0 else ap(fn d -> 10 / d) end      -- lambda parameter
if d == 0 do 0 else match o do Some(d) -> 10 / d ... end   -- match binder
```

(Compressed onto one line each for comparison; March has no `;`, so the `let` really
sits on its own line inside the branch.)

A `let`, a local `fn`, a lambda parameter, a `let?` pattern or a `match` binder
drops everything known about the outer variable of that name. Note which way this
errs: in the ordinary refinement checker, losing a fact means silence, but here it
means an *error*, so the retirement is intentionally over-eager. If you need the guard
inside the rebinding scope, re-state it there. Correct code is unaffected:
`let d = 5` followed by `10 / d` still passes, because the new binding replaces the old
fact rather than just erasing it.

**One imbalance to know:** a refinement on an `impl` method's parameter can discharge a
division inside that method's body only when callers are actually obliged to establish
it; the two passes share one adoption rule so they can't drift apart. See
[the `cap verified` edges](#cap-verified-making-silence-an-error) for when that
adoption happens.

---

## Limitations

No refinement system is complete; this one is intentionally a *pragmatic slice* of
dependent typing. Know the edges:

- **`Int`, `Bool`, `Float`, `String` (narrowly), records and ADT tags.**
  Predicates over other types aren't supported. `Float` predicates are
  **comparisons only**; float arithmetic inside one is skipped rather than
  guessed at, and a `Float` sitting inside a record or a constructor is opaque.
  See [Bool and Float Refinements](#bool-and-float-refinements) and
  [Constructor Tags](#constructor-tags-refining-over-adt-variants).
- **Tag narrowing stops at several ordinary shapes.** A `match` on an
  expression rather than a variable, an `as` pattern, a pattern that rebinds the
  name, an ambiguous constructor name, and any rebinding of the name inside the
  arm all leave the call *unchecked* rather than reported. See
  [Facts from a `match`](#facts-from-a-match).
- **A tag refinement composes only for the constructor you promised.** Passing a
  `{Option(Int) | is_Some(_)}` parameter on to a callee wanting the same thing is
  proved. A *different* tag is not assumed: with
  `outer(p : {Option(Int) | is_None(_)})`, a call needing `is_Some(_)` is
  skipped rather than reported, even though the two are exclusive. See [Contracts
  Compose](#contracts-compose-a-parameters-promise-applies-inside-its-body).
- **A fact doesn't survive a local `let`, for any type.** `let u = 5` then
  `take_pos(u)` against `{Int | _ > 0}` is skipped. Pass the value directly, or
  restate it with `assert`. (This is also why rebinding a refined parameter drops
  its promise.)
- **Only preconditions compose automatically.** A parameter's promise reaches
  *calls* in the body; it does not flow into a refined **return** type the same
  way. A postcondition is still checked on every return path, counted by
  `--refine-report`, and escalated by `cap verified` (see
  [Postconditions](#postconditions)), but composing a measure *through* one
  (proving a caller's obligation from a callee's return contract) is the
  narrower, structural-recursion-only case described a few bullets down.
- **Incomplete (by the definite-failure stance).** The checker catches values
  that are *definitely* wrong and stays silent otherwise. It will not prove
  every true property; quantified/measure facts in particular sometimes return
  "unknown" and are skipped. This never produces a false positive, but it does
  mean some real guarantees go unchecked.
- **Higher-order: two shapes are checked, the rest are not.** A call made
  through a parameter with a declared type that includes a refinement
  (`f : ({Int | _ >= 0}) -> Int`) is checked, and so is a call through a local
  alias of a named refined function (`let g = takepos` then `g(-3)`). NOT
  checked: a callback parameter with an unrefined declared type (so
  `apply(take_n, -3)` with `apply(f : Int -> Int, x : Int)` still passes),
  inferring a higher-order function's requirement from its body, dispatch
  through an `interface`/`impl`, and multi-argument callback types. To
  constrain a caller today, refine the higher-order function's *own* parameter.
- **Measures see structure, not elements.** Element values inside a data
  structure are opaque to a measure (`size`/`len`/`depth` never inspect them).
  Measures are single-argument, recursive over structure, and return `Int`/`Bool`.
- **Only *some* length spellings are connected to `len`.** The qualified
  `List.length`, `String.byte_size`, and the `string_byte_length` builtin discharge a
  `len` obligation; a bare `length`, `String.codepoint_count`, and `string_length` do
  not, and a guard written with those leaves the call *skipped* rather than proved.
  The connection is also dropped for the whole **compilation unit** (every prepended
  stdlib module and every `MARCH_LIB_PATH` dependency included) if a single binding
  anywhere in it could make the name denote something other than the standard library's
  own function. See [the solver really does connect
  `List.length` to `len`](#the-solver-really-does-connect-listlength-to-len).
- **Relational postconditions work, within structural recursion.** A predicate
  that relates a measure across an operation (`size(insert(t, x)) == size(t) + 1`)
  is proven by supplying the induction hypothesis at each recursive call with an
  argument that is a proper component of the matched parameter, then discharging each
  `match` arm against the measure's recursion equations. A body that is a bare
  **constructor application** (`fn push(t, x) : {Tree | size(_) == size(t) + 1}
  do Node(t, x, Leaf) end`) is proven too, and needs no induction at all: there
  is no recursive call to hypothesise over, only one unfolding of the measure's
  recursion equation. That shape also records its verdict in the obligation
  ledger, so `--refine-report` shows it as attempted rather than absent. Only a
  postcondition actually *proved* propagates, so an unprovable one stays legal
  but gives callers no fact. Still silent: mutual recursion, a recursive call
  inside a lambda or behind a nested `match`, and any non-structural recursion.
- **A measure with a value that is a *scalar constructor field* never discharges
  anything.** A measure that reads a field out of its constructor
  (`fn length(v) do match v do PVec(n, _, _, _) -> n end end`, the natural way to
  write `length` for a container that stores its own count) is accepted, passes
  the soundness gate, and gets a correct axiom, and yet proves no goal in
  *either* direction. When the checker reflects a constructor at a call site, it
  replaces every field that is not itself a data type with a fresh unconstrained
  constant (`reflect_field`): sound for a measure recursive over structure, with a
  value depending only on tags and sub-measures, and fatal for one with a value that
  *is* the field. So `length(PVec(3, 0, TrieEmpty, Nil))` reaches the solver as
  an unknown `Int`, and an obviously in-range index is neither proved nor
  refuted: it is `solver-undecided` and silently accepted. This is why
  `Array.get`/`set`/`pop` carry no bounds contract today and stay on the
  `cap no_panic` ban list instead.

  The compiler **warns** at the measure's definition when it sees this, but the
  warning fires **only on a bare field read** (`-> n`). A body that only
  *computes* with the erased field (`-> n + 1`, `-> n * 2`) is equally inert
  and draws **no warning at all**: the check is intentionally narrow, because a
  broader one flagged bodies like `-> 0 * n` that mention the field without
  depending on it, and a false positive is the greater harm. **Silence here does not mean
  your measure works.** If a measure's value depends on a scalar constructor
  field in any way, expect it to prove no goal.
- **A measure over a built-in `List` with a non-scalar element does not
  axiomatise.** `List(Int)` is fine; `List(SomeAdt)` collapses the element to an
  opaque sort and the measure is never usable. A user-defined list type with the
  same shape works. This is the first obstacle between this infrastructure and the
  stdlib's HAMT-based `Map`.
- **`Bool` predicates need an operator form.** `{Bool | _ == true}` is checked;
  the bare-binder spelling `{Bool | not _}` is a parse error; write
  `{Bool | _ == false}`.
- **No float special values.** There is no `is_nan` / `is_finite` vocabulary, so
  a predicate cannot mention them (NaN is still modelled correctly *inside* the
  solver, which is what keeps correct code from being flagged).
- **Performance: measures can be slow on a cold cache.** Quantified + datatype
  reasoning is far more expensive per query than plain arithmetic. Verdicts are
  content-addressed and cached (warm rebuilds are fast), and the cost is
  isolated to call sites that actually mention a measure, but a cold build of
  measure-heavy code pays for it. See the flag below.

---

## Practical Rules

1. **Refine the contract, not the convenience.** Add `{Int | _ > 0}` where a
   non-positive value is a real bug (a chunk size, an unguarded divisor), not
   to every `Int`. Many March APIs already clamp defensively and have no real
   precondition.
2. **Guard, then call.** A precondition you can't satisfy with a literal is
   discharged by an `if`/`when` guard right before the call.
3. **Reach for `assert` as your lemma.** When you *know* a fact the checker
   can't derive, `assert(p)` makes it available, and documents the assumption.
4. **Annotate measures you'll reason about.** A `@[measure]` only earns its
   keep if a predicate mentions it; keep them total, exhaustive, and structural
   so they pass the gate.

---

## Appendix: the `List.length`↔`len` alias, in full

*Skip unless a length guard you expected to work isn't discharging. Referenced from
[Path Sensitivity](#path-sensitivity-guards-establish-facts) and
[Limitations](#limitations). This is the exact rule for when a length guard counts as
the `len` measure.*

### The solver really does connect `List.length` to `len`

The checker treats the qualified `List.length` as another name for the `len` measure, so
a guard you'd write anyway (`if List.length(ys) > 0`) establishes exactly the fact the
contract `{List(Int) | len(_) > 0}` is asking for:

```march
fn first_or(ys : List(Int), d : Int) : Int do
  if List.length(ys) > 0 do head(ys) else d end   -- proved
end

fn broken(ys : List(Int)) : Int do
  if List.length(ys) == 0 do head(ys) else 0 end  -- compile error
end
```

The second is a compile error because under `len(ys) == 0` the predicate `len(ys) > 0`
can *never* hold: a definite failure, which is the bar March requires before it reports
anything.

The connection is intentionally narrow, since attaching `len`'s meaning to the wrong
function is how you'd get a false alarm on correct code. Only the **qualified**
`List.length` counts (a bare `length` is left as-is), and only while it still resolves to
the standard library's own. If your program defines its own `List.length` (however it
spells the definition: a `fn`, a module-level `let`, an `extern` block, an interface or
impl method) or ships a forked `List` via `MARCH_LIB_PATH`, the connection is dropped
and you're back to the obligation being skipped, with no message, rather than proved.

**"Dropped" means dropped for the whole compilation unit, not just the file you're
editing.** The check is syntactic and unit-global: it doesn't ask whether the competing
binding could win at your call site at all, because answering that needs a resolver this
pass doesn't have. One real competitor anywhere in the unit (including inside a
`MARCH_LIB_PATH` dependency you never opened, and remembering that the compiler prepends
the entire standard library to every compilation) disables the alias program-wide.
That's a real cost, and it's the direction the checker errs in on purpose:
over-withdrawing loses a proof (silence), while under-withdrawing would put a wrong fact
in the assumption set and flag correct code.

The withdrawal rules for the specific import forms:

- A selector-less `use Foo.List` (importing the module itself, not a member of it)
  resolves its target: `use Analytics.List` where `Analytics.List` only has a `size`
  function leaves `List.length` connected to `len`; a `use` with a target that really does
  define `length` withdraws it.
- `alias Foo.List as List` and a named import (`use Foo.{List}`) withdraw the alias
  unconditionally.
- A glob import (`import Foo`, `use Foo.*`) withdraws the alias only if `Foo`
  **actually provides** a competing `List`, resolved by walking the unit's own module
  structure; if the glob's target can't be resolved, it still withdraws.
- Either side of the guard applies only to the **program's** own bindings, never the
  standard library's own. The two conditions are ANDed, so a glob withdraws only when it
  is your code *and* its target really provides a competitor.

### The same for strings, but only the byte-valued names

`len` measures a `String` too, and the same connection is made for `String.byte_size`
and the `string_byte_length` builtin:

```march
fn slug(s : {String | len(_) > 0}) : String do String.slice(s, 0, 1) end

fn label(t : String) : String do
  if String.byte_size(t) > 0 do slug(t) else "?" end   -- proved
end
```

Swap the guard for `String.byte_size(t) == 0` and that call becomes a compile error, the
same way it does for lists.

The catch is that `len` on a String counts **bytes**, so only byte-valued names get this
treatment. `String.codepoint_count` counts codepoints (it returns 1 for `"é"` where
`String.byte_size` returns 2) and is left as-is. So is `string_length`: it happens to be
a byte length today, but the *name* suggests characters, and a connection made on a name
that might later be corrected is a bug waiting to happen. Reach for `String.byte_size` in
a guard; it states what it means.

### A qualified spelling *inside* the predicate itself

Everything above is about a **guard**: ordinary code, outside the `{...}`. Writing the
qualified name **inside** the braces enforces the same contract as the bare `len`:

```march
fn inner(xs : {List(Int) | List.length(_) > 0}) : Int do 0 end
fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
```

A refinement predicate is not run through the general expression desugarer the way a
function body is (no pipe desugaring, no multi-head-fn desugaring), but the one
transformation that matters here, flattening a module-path call head (`List.length(_)`)
into the dotted form the `len` alias keys on, runs over every `TyRefine` predicate
(parameter, return, `let`-annotation, top-level and block-level alike, and
record/variant field types alike). When the alias is live (no competing `List.length`
in scope), the qualified spelling means exactly what `len` means, so `inner([])` is
rejected as a real precondition violation.

If a unit has withdrawn the alias by defining its own competing `List.length`, the
qualified spelling enforces no contract (correctly: the alias truly doesn't apply there),
and the checker warns, still recommending the bare `len(_)` spelling:

> `List.length` is a qualified call inside a refinement predicate. This spelling is
> never reflected here, so the refinement enforces nothing. Use the bare spelling
> `len` instead.

The same applies to `String.byte_size`. Two shapes remain truly unhandled and still
warn/stay silent: a record **field** call (`{Cfg | c.cb(1) > 0}`, never treated as a
qualified call) and a receiver that is itself a call (`f(x).g(y)`, not rendered as a
path).

## Appendix: Where Refinements Resolve

*This is a plumbing detail about how the checker looks up which function a call refers
to, not something you need to know to start using refinements.*

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

A bare call resolves at the scope that actually owns it: a `use` written
**inside** a nested module is consulted before the checker falls outward to an
enclosing module's own definition of the same name, matching how the call
really dispatches. An enclosing module's `use`, on the other hand, still loses
to a nested module's *own* definition of the name: an import never reaches
in and overrides a local one.

```march
mod Outer do
  fn take_pos(n : {Int | n >= 0}) : Int do n end   -- Outer's own contract

  mod Inner do
    use Lib.{take_pos}                              -- Lib's take_pos, unrefined

    fn go() : Int do
      take_pos(-1)   -- resolves to Lib.take_pos, NOT Outer's — no error
    end
  end
end
```

Checking this call against the *enclosing* `App.take_pos` instead would be a false
positive on correct code, since `Inner.go` never actually calls it, so the checker
resolves it the way the call really dispatches.

---

## Appendix: The `--no-measure-axioms` Flag

*Also a niche knob, only relevant if a measure-heavy build feels slow.*

Pass `--no-measure-axioms` to reflect `@[measure]` functions **symbolically**
instead of axiomatising them. This skips the datatype/quantifier reasoning (and
the soundness gate), trading structural measure reasoning for speed. It changes
only diagnostics, never the compiled artifact. Refinement checking of plain
`Int`/`Bool` predicates is unaffected and always cheap.

```bash
march --check --no-measure-axioms app.march
```

---

## Next Steps

- [Type System](types.md): the types refinements attach to
- [Linear Types](linear-types.md): the other compile-time safety layer
- [Pattern Matching](pattern-matching.md): `match` guards feed path sensitivity
