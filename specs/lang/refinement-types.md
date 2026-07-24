---
layout: docs
title: Refinement Types
nav_order: 5.5
permalink: /docs/refinement-types/
---

> Part of the March Language Reference — see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Refinement Types

A **refinement type** attaches a logical predicate to an ordinary type:
`{Int | _ >= 0}` is "an `Int` that is non-negative". March discharges these
predicates with an SMT solver (Z3) at compile time, so a whole class of bugs —
out-of-bounds indices, negative sizes, division by zero, broken invariants —
becomes a **compile error** instead of a runtime panic.

Refinements are March's pragmatic slice of **dependent typing**: types that
depend on *values*. You get the safety where it pays off (preconditions,
bounds, postconditions) without a proof assistant's ceremony — and, crucially,
**without false positives**: if the checker can't prove a value is definitely
wrong, it stays silent.

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
`String` values are supported to the narrower extent described in
[String Refinements](#string-refinements): `len` and `==`/`!=` against literals.

---

## How Checking Works — Definite Failure

March reports a refinement violation **only when the predicate can *never*
hold** under everything it knows at that point. This "definite-failure" stance
is the heart of the design:

- The argument **always** satisfies the predicate → **pass**, silently.
- The argument **never** satisfies it → **compile error** with a counterexample.
- It **might** satisfy it (the value is unknown / the solver is unsure) →
  **skipped**, silently.

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

## Postconditions Flow to Call Sites

A function's declared return refinement is a fact its callers can use. Both the
direct and the `let`-bound form are checked:

```march
fn neg() : {Int | _ < 0} do 0 - 1 end
fn takepos(n : {Int | _ >= 0}) : Int do n end

takepos(neg())          -- error: `neg` returns a negative, `takepos` needs >= 0

let c = neg()
takepos(c)              -- error: same, through the binding
```

Resolution follows the same rules as everything else — direct named calls,
across modules, through `alias` and `use`.

**Only *closed* postconditions propagate.** A predicate that mentions a
parameter — `{Int | _ < n}`, `{Int | _ < len(xs)}` — is *relational*, and using
it at a call site requires substituting arguments for parameters. That is not
yet supported, so a relational postcondition is silently skipped at call sites
(it is still checked at the definition).

**Only *proven* postconditions propagate.** A declared return refinement
becomes an assumption at call sites only when the definition side actually
*proved* it — every return path of every clause discharged as verified. A
postcondition the checker can neither prove nor refute stays perfectly legal at
the definition (rejecting it would flag correct-but-unprovable code), it simply
does not travel: callers learn nothing from it.

This is not a stylistic preference, it is what keeps the no-false-positives
promise. A propagated fact is *added* to the assumptions a call-site query
proves against, so a false assumption makes a violation easier to "prove" — a
stale `{Int | _ < 0}` on a function that in fact returns `6` would flag the
perfectly correct call `takepos(score(5))`. Only facts that are true may be
assumed. The cost is incompleteness — a postcondition whose body is opaque to
the solver buys its callers nothing — which is the safe direction and the trade
this checker makes everywhere else.

---

## Path Sensitivity — Guards Establish Facts

A guard you write becomes an assumption the solver can use. The then-branch
learns the condition; the else-branch learns its negation:

```march
fn get(xs : List(Int), i : Int) : Int do
  if i >= 0 && i < List.length(xs) do
    at(xs, i)          -- ok: the guard proves the precondition here
  else
    0
  end
end
```

(`len` is a measure name usable only inside a `{...}` refinement predicate,
not a callable in ordinary code — verified live, 2026-07-22; use
`List.length` in a plain guard expression like the one above.)

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

A **measure** is a function from a value to an `Int` (or `Bool`) that you can
mention in predicates. The built-in `len` measures a list:

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

The solver reasons about measures **structurally**: from the recursion
equations above it computes `size(Node(Leaf, x, Leaf)) = 1`, so an out-of-bounds
index into a literal tree is caught, and `size(t) >= 0` is known for any `t`.
Measures may call **other measures** and be **mutually recursive** (e.g. a
`Tree`/`Forest` pair), and the built-in `List` is modelled too, so a user
`length` measure over `List(a)` reasons structurally just like `size`.

## String Refinements

`len` also measures a **String**, so an emptiness contract is expressible and
checkable:

```march
fn slug(s : {String | len(_) > 0}) : String do ... end
fn code(s : {String | len(_) <= 3}) : String do ... end

fn main() do
  slug("")        -- rejected: len("") is 0, so the predicate can never hold
  slug("hello")   -- fine
  code("abcd")    -- rejected: len("abcd") is 4
end
```

Equality against a **string literal** works too, so the contract can be written
the other way round:

```march
fn slug(s : {String | _ != ""}) : String do ... end
```

`len` is **overloaded** — the same name measures a list and a String. Which one
applies is decided by the *declared* base type of the value being measured, never
guessed from context, so `{Int | _ < len(xs)}` over a `List` and
`{String | len(_) > 0}` over a `String` coexist without ambiguity. If the checker
cannot tell, it skips the obligation rather than assume.

`len` counts **bytes**, matching the `string_length` builtin exactly (March has no
codepoint-length primitive). For non-ASCII text a character is several bytes:
`len("é")` is 2, not 1.

### What String refinements do *not* do

The encoding models `String` as an **opaque sort** with `len` as an uninterpreted
function — deliberately outside any SMT string theory, so queries stay decidable
and cheap. Two consequences are worth stating plainly:

- **A `== ""` guard does not establish a length.** In

  ```march
  if s == "" do 0 else nonempty(s) end
  ```

  the else-branch knows only that `s` is *distinct from* the empty literal. There
  is no axiom relating a string's identity to its length, so `len(s) > 0` does not
  follow and the call is silently skipped. This is a real gap, not an oversight:
  closing it needs an injectivity axiom whose cost was judged not worth it.
- **No prefix, suffix, contains, concatenation, or regex reasoning.** Only `len`
  and `==`/`!=` against literals are understood. Any other string operation in a
  predicate makes the obligation unreflectable, and unreflectable means skipped.

### The measure soundness gate

A `@[measure]` is a *promise* that the function is a **total, terminating, pure**
mathematical function — the solver trusts it, so a broken one would let it
"prove" anything. March enforces the promise as a **hard compile error**. A
`@[measure]` is rejected if it:

- has an **effect** (`spawn`, `send`, `dbg`, `assert`),
- can **diverge or abort** (`panic`, `todo`, `exit`),
- is **non-total** — a non-exhaustive `match` on its parameter, or a `/` / `%`
  that could divide by zero,
- is **not structurally recursive** — a recursive call whose argument isn't a
  component of the matched parameter.

A measure that is sound but outside what the encoding can model (see
limitations) isn't an error — it simply falls back to weaker, symbolic
reasoning.

---

## Where Refinements Resolve

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

## Limitations

Refinements are intentionally a *pragmatic slice* of dependent typing. Know the
edges:

- **`Int`, `Bool`, and `String`.** There are **no `Float` value-refinements** —
  encoding floats as mathematical reals is unsound for IEEE-754 arithmetic, so
  it's deliberately omitted. `String` supports only `len` and literal
  equality (see [String Refinements](#string-refinements)); refinements over
  other types aren't supported.
- **Incomplete (by the definite-failure stance).** The checker catches values
  that are *definitely* wrong and stays silent otherwise. It will not prove
  every true property; quantified/measure facts in particular sometimes return
  "unknown" and are skipped. This never produces a false positive, but it does
  mean some real guarantees go unchecked.
- **Direct calls only — no higher-order or interface dispatch.** A precondition
  on a function passed as a value, called through a variable, or dispatched
  through an `interface`/`impl` is **not** checked. (True higher-order checking
  needs refinement subtyping in unification, which isn't implemented.)
- **Measures see structure, not elements.** Element values inside a data
  structure are opaque to a measure (`size`/`len`/`depth` never inspect them).
  Measures are single-argument, structurally recursive, and return `Int`/`Bool`.
- **An unproven postcondition does not reach callers.** If the checker can't
  prove a declared return refinement at the definition (an opaque body, a
  predicate it can't reflect, or a body that routes its value through a local
  `let` binding rather than returning it directly), the declaration is still
  accepted but callers learn nothing from it. Only proven postconditions are
  assumed at call sites.
- **No relational postconditions yet.** A return refinement that mentions a
  parameter (`{Int | _ == n + 1}`, `{Int | _ < len(xs)}`) is checked at the
  definition but is **not** propagated to call sites — instantiating it there
  requires substituting arguments for parameters. Properties that *relate* a
  measure across an operation — `size(insert(t, x)) == size(t) + 1` — are also
  not provable automatically (they often need induction the solver can't do by
  itself). Use an `assert` lemma where you need them.
- **Performance: measures can be slow on a cold cache.** Quantified + datatype
  reasoning is far more expensive per query than plain arithmetic. Verdicts are
  content-addressed and cached (warm rebuilds are fast), and the cost is
  isolated to call sites that actually mention a measure — but a cold build of
  measure-heavy code pays for it. See the flag below.

---

## The `--no-measure-axioms` Flag

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

## Conformance status

Refinement types are now a conformance-tested part of the language reference
(widening slice 12; `core-march-types.md` §2.14). The central fact §2.14
pins down: `{T | pred}` is completely transparent to `typecheck.ml`'s own
unification (a refined type has the identical typing derivation as its
base type) — checking happens entirely in the separate `lib/refinecheck`
pass this page already describes, at exactly two sites, both mechanically
witnessed: a **precondition** at a direct call (accept/reject pair
`t75`/`t71`) and a **postcondition** on the function's own body
(`t76`/`t72`). The "direct calls only" limitation this page's own
Limitations section states is now a passing corpus fact, not only prose:
`accept/t77_refine_hof_bypass_limitation` proves a refined function called
*through* a higher-order parameter is NOT checked, even when the identical
literal at a direct call site is rejected. `cap no_panic`'s division-safety
check is confirmed as a second, independent `Refine.discharge` consumer
(`t78`/`t73`). Golden `g46_refinement_erasure` witnesses the zero-runtime-
footprint property this transparency implies: a program whose obligations
all provably hold at `--check` time runs byte-identically interpreted and
compiled, since neither backend inserts any runtime predicate check.

## Next Steps

- [Type System](types.md) — the types refinements attach to
- [Linear Types](linear-types.md) — the other compile-time safety layer
- [Pattern Matching](pattern-matching.md) — `match` guards feed path sensitivity
