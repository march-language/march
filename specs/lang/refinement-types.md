---
layout: docs
title: Refinement Types
nav_order: 5.5
permalink: /docs/refinement-types/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Refinement Types

A **refinement type** attaches a logical predicate to an ordinary type:
`{Int | _ >= 0}` is "an `Int` that is non-negative". Write one on a parameter
and every call must satisfy it; write one on a return type and every return
path must satisfy it. The compiler discharges the predicates with the Z3 SMT
solver at compile time, so out-of-bounds indices, negative sizes, division by
zero and broken invariants become compile errors instead of runtime panics.
Nothing is checked at runtime: a refined type compiles to exactly its base type.

The checker reports a violation **only when it can demonstrate one**, and then
names the concrete input that fails. If it cannot prove a value is wrong, it
stays silent. That is the design's central bargain: no false positives on
correct code, at the price that silence does not mean "proved". The page's
tooling sections show how to tell the two apart, and `cap verified` turns
silence into an error for a module that wants a guarantee.

> **Requires Z3.** Refinement checking runs only when the `z3` solver is on your
> `PATH`. Without it, the predicates type-check as their base type and no
> refinement diagnostics are produced (the build still succeeds).

> **What's new (October 2026).** Refinements now reach further into
> containers, callbacks and folds:
>
> - **2026-10-18. Fold accumulator invariants.** A demand on a fold's result
>   is checked as the invariant its accumulator keeps. You can also state the
>   invariant yourself by annotating the accumulator. See
>   [Folds](#folds-an-accumulator-invariant) and
>   [An annotated accumulator](#an-annotated-accumulator).
> - **2026-10-21. Relational element refinements.** One slot of a type can
>   mention another slot, so you can say "every value is bigger than its key".
>   See [Relational element refinements](#relational-element-refinements).
> - **2026-10-21. Two-argument abstract refinements.** A filter whose callback
>   looks at a key and a value together now carries what the callback decided.
>   `Map.filter` carries this fact. It is assumed, and a runtime property test
>   checks it. See [Two arguments](#two-arguments-a-relation-between-sibling-slots).
> - **2026-10-21. More stdlib functions carry element facts.** `Hamt.fold` and
>   `Enum.scan` carry the fold invariant. `Queue`'s functions pass element
>   refinements through. See [which stdlib folds carry it](#folds-an-accumulator-invariant).
> - **2026-10-21. Module-wide inference.** `march --refine-infer` and
>   `forge refine --infer` propose every kind of refinement the checker can
>   verify. See [Module-wide inference](#module-wide-inference-march---refine-infer-and-forge-refine---infer).
> - **2026-10-22. A name bound twice is a type error.** A lambda, function or
>   pattern that binds the same name twice is rejected as
>   [`duplicate_binder`]({{ site.baseurl }}/docs/errors/duplicate_binder/).
>
> The gaps these features still have are listed under
> [Limitations](#open-gaps-in-element-and-abstract-refinements).

## On this page

**Start here**

- [When to use refinements](#when-to-use-refinements)
- [How it fits with the rest of March](#how-it-fits-with-the-rest-of-march)
- [The Problem They Solve](#the-problem-they-solve)
- [Syntax](#syntax)
- [How Checking Works: Definite Failure](#how-checking-works-definite-failure)
- [Counterexamples: the failing input, in source terms](#counterexamples-the-failing-input-in-source-terms)
- [Path Sensitivity: Guards Establish Facts](#path-sensitivity-guards-establish-facts)
- [A Parameter's Own Contract Is a Fact Inside Its Body](#a-parameters-own-contract-is-a-fact-inside-its-body)
- [Postconditions](#postconditions) and [how they flow to call sites](#postconditions-flow-to-call-sites)
- [Where Refinements Resolve](#where-refinements-resolve)
- [Practical Rules](#practical-rules)

**Refining each kind of value**

- [Measures: Refining over Data Structures](#measures-refining-over-data-structures)
- [String Refinements](#string-refinements)
- [Set Refinements](#set-refinements)
- [Bool Refinements](#bool-refinements)
- [Float Refinements](#float-refinements)
- [Constructor Tags: Refining over ADT Variants](#constructor-tags-refining-over-adt-variants)
- [Element Refinements: Refining What a Container Holds](#element-refinements-refining-what-a-container-holds)
  - [Relational element refinements](#relational-element-refinements): a relation between sibling slots
  - [Abstract refinements](#abstract-refinements-filter-keeps-what-its-predicate-says): `filter` keeps what its predicate says
    - [Two arguments](#two-arguments-a-relation-between-sibling-slots): `k -> v -> Bool[p]`, `Map(k[p], v[p])`
  - [Folds: an accumulator invariant](#folds-an-accumulator-invariant)
    - [An annotated accumulator](#an-annotated-accumulator)

**Finding out what was actually checked**

- [Counting the obligations: `--refine-report`](#counting-the-obligations---refine-report)
- [Getting a contract proposed for you: `forge refine`](#getting-a-contract-proposed-for-you-forge-refine)
  - [Module-wide inference: `march --refine-infer` and `forge refine --infer`](#module-wide-inference-march---refine-infer-and-forge-refine---infer)
- [Coverage audit: does the checker even look at this refinement?](#coverage-audit-does-the-checker-even-look-at-this-refinement)
- [Promoting a skip: a demonstrated precondition failure](#promoting-a-skip-a-demonstrated-precondition-failure)
- [The `--no-measure-axioms` Flag](#the---no-measure-axioms-flag)

**Strict modes**

- [`cap verified`: turning silence into an error](#cap-verified-turning-silence-into-an-error)
- [`cap no_panic`: Divisions That Can't Panic](#cap-no_panic--divisions-that-cant-panic)

**Limits and status**

- [Limitations](#limitations)
  - [Open gaps in element and abstract refinements](#open-gaps-in-element-and-abstract-refinements)
- [Conformance status](#conformance-status)
- [See also](#see-also)

## When to use refinements

Use a refinement where a bad value is a **real bug the caller can avoid**: an
index into a list, a chunk size, an unguarded divisor, a non-empty input a
function cannot do without, a return value a caller will rely on. One contract
at the function boundary replaces a runtime check in the body and a comment in
the docs, and the compiler enforces it at every call.

| You want to | Reach for |
|---|---|
| Reject a bad argument at the call site | A refined parameter: `i : {Int | _ >= 0 && _ < len(xs)}` |
| Promise something about a result | A refined return type: `: {Int | _ >= 0}` |
| Talk about a list's length, a record's fields, or your own data | A [measure](#measures-refining-over-data-structures) |
| Say which elements a collection holds | [Set](#set-refinements) and [element](#element-refinements-refining-what-a-container-holds) refinements |
| Say which constructor an ADT value is | A [constructor tag](#constructor-tags-refining-over-adt-variants) |
| Make unproven contracts an error, not silence | [`cap verified`](#cap-verified-turning-silence-into-an-error) |
| Prove no division in a module can panic | [`cap no_panic`](#cap-no_panic--divisions-that-cant-panic) |
| Find out whether a contract is checked at all | [`--refine-report`](#counting-the-obligations---refine-report) and the [coverage audit](#coverage-audit-does-the-checker-even-look-at-this-refinement) |

Do not refine every `Int`. Many March APIs clamp defensively and have no real
precondition; a contract there adds obligations without preventing a bug. And
do not use a refinement for a fact about *where a value came from* ("this
string was sanitized"): that is an opaque type's job, see
[Capabilities]({{ site.baseurl }}/docs/capabilities/).

## How it fits with the rest of March

| Concept | Where refinements meet it | Chapter |
|---|---|---|
| **Type system** | A refined type is its base type to the type checker; refinement checking is a separate pass after inference, at call sites and return paths. | [Type System](type-system.md) |
| **Pattern matching** | `if` and `match … when` guards become facts the solver can use on the branch they dominate. | [Pattern Matching](pattern-matching.md) |
| **Capabilities** | `cap verified` and `cap no_panic` are behavioral caps that change what the checker does with an unproven obligation. | [Capabilities]({{ site.baseurl }}/docs/capabilities/) |
| **Standard library** | Stdlib functions such as `List.head`, `List.nth` and `Option.unwrap` carry refinement contracts, so a user call site is checked against them. | [Standard Library](standard-library.md) |
| **Linear types** | The other compile-time safety layer: linearity tracks *use*, refinements track *value*. | [Linear Types](linear-types.md) |
| **Safety by construction** | Refinements are one of three orthogonal layers, beside capabilities and typestate. | [Safety by Construction](safety-by-construction.md) |
| **Tooling** | `forge refine` proposes a contract; `--refine-report` and `--refine-audit` say what was proved, skipped, or never looked at. | [Tooling](https://github.com/march-language/march/blob/main/docs/tooling.md) |

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

The supported predicate fragment is **`Int`/`Bool` arithmetic**: `+ - *`, the
connectives `&& || not`, integer/bool literals, **measures**, ADT
**constructor tags** (both below), and the **set vocabulary** over a
collection's elements (`elts`, `keys`, `member`, `union`, `inter`, `diff`,
`subset`, `singleton`, `empty`; see [Set Refinements](#set-refinements)). `String` values are supported to the
narrower extent described in [String Refinements](#string-refinements): `len`
and `==`/`!=` against literals. `Bool` values take the boolean operators against
`true`/`false` ([Bool Refinements](#bool-refinements)); `Float` values take
comparisons against float literals, discharged through Z3's bit-precise IEEE-754
theory rather than reals ([Float Refinements](#float-refinements)).

Multiplication by a literal keeps a query in linear arithmetic, where the
solver is complete and fast. A product of two non-constant terms is accepted
too — `v * v > 0` is exactly `v != 0` over the integers, and refusing it only
turned a decidable predicate into a skip — but the solver is *incomplete*
there, so a non-linear goal it cannot settle is reported as the skip reason
`nonlinear-goal` rather than as a violation. The same holds for a call-site
ARGUMENT: `need_pos(y * y + 1)` against `{Int | _ > 0}` reflects the product
as a subject and proves.

Integer division (`/`, `%`) is in the fragment with March's own semantics:
both **truncate toward zero**, and the remainder takes the dividend's sign
(`-7 / 2` is `-3`, `-7 % 2` is `-1`, `7 / -2` is `-3`). The solver's `div`/`mod`
are Euclidean (`-7 / 2` would be `-4` there), so the checker does not use them
directly: `a / d` is encoded as "`a >= 0` ? `div(a, d)` : `-div(-a, d)`" and
`a % d` likewise, which is exact for either sign of either operand. When the
dividend is known to be non-negative (a non-negative literal, a `len(...)` or
another non-negative measure, a sum or product of such terms, or a variable,
field, or measure that a conjunct of the same `&&` chain bounds below by 0) the
two agree and the plain `div`/`mod` is used, which keeps the query simpler.

```march
fn half(n : {Int | _ >= 0 && _ / 2 < 10}) : Int do n end
fn mid(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs) / 2}) : Int do i end
fn f(n : {Int | _ / 2 == -3}) : Int do n end     -- f(-7) proves; f(-5) is a violation
fn g(d : Int, n : {Int | d != 0 && _ / d > 0}) : Int do n end
```

A literal divisor keeps the query linear. A **variable divisor** (or any other
non-literal one) is non-linear, so an undecided goal is the skip reason
`nonlinear-goal` as for `*`. It also has a side condition: dividing by zero
panics at run time, so a predicate is never *true* at a zero divisor. The
checker conjoins "every divisor it reaches is non-zero" to the predicate,
following `&&`/`||` short-circuiting exactly as March evaluates it:
`d != 0 && _ / d > 0` is defined everywhere, `_ / d > 0 && d != 0` is not (the
division runs first). So `g(0, 5)` above is a violation, and a call that
cannot rule out a zero divisor is not proved. A counterexample whose only
failure is a zero divisor is not confirmed by running the code (the predicate
panics rather than returning `false`), so it is reported as not verified
rather than as a violation.

That side condition needs a Boolean predicate to attach to, so it applies
where the predicate (or path guard) is a comparison or a `&&`/`||`/`not` of
comparisons, which is every ordinary refinement. A division in a bare
`Int`-valued position, such as a call's argument `f(n / d)`, is translated only
when its divisor is a non-zero literal or is syntactically positive
(`len(xs) + 1`).

### Refinements inside containers, callbacks and folds

A refinement may also sit inside a type argument, on a callback, or on a
fold's accumulator. Each form has its own section further down:

| Form | Meaning | Section |
|---|---|---|
| `List({Int \| _ > 0})` | every element is positive | [Element refinements](#element-refinements-refining-what-a-container-holds) |
| `Assoc({x : k \| true}, {y : v \| y > x})` | every value is bigger than its key: one slot mentions the other | [Relational element refinements](#relational-element-refinements) |
| `pred : a -> Bool[p]` returning `List(a[p])` | every element of the result passed `pred` | [Abstract refinements](#abstract-refinements-filter-keeps-what-its-predicate-says) |
| `keep : k -> v -> Bool[p]` returning `Map(k[p], v[p])` | every key and value of the result passed `keep` together | [Two arguments](#two-arguments-a-relation-between-sibling-slots) |
| `fn (acc : {Int \| _ > 0}, x) -> …` passed to a fold | the accumulator stays positive: checked at the start and at every step, then a fact about the result | [An annotated accumulator](#an-annotated-accumulator) |
| `@[assume]` on a function whose return refines its elements | the element fact is assumed, not proved, and counted as `trusted` | [`Map.filter` carries it, assumed](#two-arguments-a-relation-between-sibling-slots) |

```march
type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

fn need_pos(k : {Int | _ > 0}) : Int do k end
fn sum_pos(_xs : List({Int | _ > 0})) : Int do 0 end
fn need_arel(_a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do 0 end
fn need_vals(_m : Map(String, {Int | _ > 0})) : Int do 0 end

fn rel_ok() : Int do need_arel(ACons(1, 2, ANil)) end     -- proved
fn rel_bad() : Int do need_arel(ACons(5, 2, ANil)) end    -- violation: the entry (5, 2)

fn kept(ys : List(Int)) : Int do
  sum_pos(List.filter(ys, fn y -> y > 0))                  -- proved
end

fn vals(m : Map(String, Int)) : Int do
  need_vals(Map.filter(m, fn _k -> fn v -> v > 0, Map.str_cmp))   -- proved (assumed entry fact)
end

fn counted(ys : List(Int)) : Int do
  let s = List.fold_left(ys, 1, fn (acc : {Int | _ > 0}, _x) -> acc + 1)
  need_pos(s)                                              -- proved: the annotation holds
end
```

---

## How Checking Works: Definite Failure

March reports a refinement violation **only when it can demonstrate one**.
This "definite-failure" stance is the heart of the design:

- The value **always** satisfies the predicate → **pass**, silently.
- The predicate is **demonstrably violated** → **compile error** with a
  counterexample. There are two routes to a demonstration: the solver proves
  the predicate can never hold, or the checker finds a concrete input, *runs
  it*, and watches the contract fail (see
  [Counterexamples](#counterexamples-the-failing-input-in-source-terms)).
- Neither is established (the value is unknown, the solver is unsure, and no
  failing input was found) → **skipped**, silently.

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

A refutation is only useful if you can act on it. When March reports a
violation it names a **concrete input**, and — for a function body — the value
that input actually produced:

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

`bump_progress(100)` is not a solver artifact and not a random probe: it is
the *one* input that breaks this function, and it sits exactly on the
boundary — the case a reviewer skims past and a test suite forgets. The
checker decoded the solver's model into a real March value, **called
`bump_progress(100)` through the interpreter**, and observed `101` come back
and fail the predicate. Everything it prints, it ran.

Off-by-one errors are where this pays off most, because the counterexample
*is* the edge case:

```march
fn next_slot(i : {Int | _ >= 0 && _ < 16}) : {Int | _ < 16} do
  i + 1
end
```

```
but next_slot(15) returns 16.
```

### Why execution, and not just the model

A verification condition is an *approximation* of your program: predicates the
checker cannot translate to SMT (a call it cannot see inside, symbolic float
arithmetic) are dropped from the query rather than guessed at. That keeps the
checker sound when it *proves* things, but it means a raw "here is a failing
input" model can describe a state your program never reaches:

```march
fn magnitude(x : Int) : Int do if x < 0 do 0 - x else x end end

fn always_one(x : Int) : {Int | _ >= 0} do
  if magnitude(x) >= 0 do 1 else x end     -- the else branch is unreachable
end
```

`magnitude` carries no contract, so the guard says nothing the solver can use
and it is dropped; the solver then happily "refutes" the contract through the
`else` branch. Printing that model would
be a false positive on correct code — the exact failure mode this design
exists to avoid. Running the candidate returns `1`, the predicate holds, the
model is discarded, and **the checker stays silent.**

The rule is therefore simple, and worth trusting: **every counterexample you
see was executed and observed to fail.** Candidates that cannot be executed —
a function needing real I/O, one that diverges, a value the checker cannot
construct — are not reported at all; the obligation stays skipped, exactly as
before.

### Witnesses respect your other contracts

A counterexample is only fair if the function actually promised to handle it.
Witness inputs must satisfy the parameters' own refinements:

```march
fn scale(x : {Int | _ > 0}, y : {Int | _ > 0}) : {Int | _ > 100} do
  x * y
end
```

```
but scale(1, 1) returns 1.
```

`scale(0, 0)` would be a simpler refutation, but `0` is excluded by
`{Int | _ > 0}`, so it is never blamed.

Witnesses are also **shrunk** to the smallest failing input rather than
whatever the solver happened to pick, and that is often the most informative
number in the diagnostic — it is the *threshold* at which the contract starts
failing:

```march
fn backoff_ms(attempt : {Int | _ >= 0}) : {Int | _ <= 30000} do
  attempt * 1000
end
```

```
but backoff_ms(31) returns 31000.
```

Every attempt count from 31 up violates the cap; the report names the first
one, so the fix (clamp at 30) reads straight off the diagnostic. Shrinking is
deterministic, so the same program reports the same counterexample every time
— which is also what lets tests pin the exact text.

Note that `x * y` never reaches the solver at all. When a contract falls
outside the checkable fragment, March probes a small battery of inputs through
the same execute-and-check pipeline; a confirmed failure is reported, and
finding nothing leaves the obligation skipped. So a contract that is
unprovable *and* true — `{Int | _ > 0}` over `x * x + 1` — stays silent rather
than being guessed at in either direction.

### Structured values print in source syntax

Records, lists and constructors are rendered the way you would write them, so
a counterexample can be pasted straight into a test:

```march
type Config = { port : Int, workers : Int }

fn with_port(cfg : Config, p : Int) : {v : Config | v.port >= 1024} do
  { port: p, workers: cfg.workers }
end
```

```
but with_port({ port: 0, workers: 0 }, 0) returns { port: 0, workers: 0 }.
```

At a **call site**, the example names the caller's own variables:

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

`samples = []` is the value itself; the pre-2026-08-30 rendering was
`len(samples) = 0`, a fact *about* the value that you then had to work
backwards from.

### Where counterexamples appear

| Site | What the diagnostic adds |
|---|---|
| Return contract | ``but bump_progress(100) returns 101.`` |
| Call-site precondition | ``(e.g. samples = [])`` |
| `cap no_panic` division | ``(e.g. count = 0)`` |

Counterexamples come from the two sites that emit diagnostics: the
**definition** (return contracts over `Int`/`Bool`/`Float`/records) and the
**call site** (preconditions of any checkable type, `List` and `String`
included). A return refinement over a collection takes the Tier 2 structural
induction path instead, which emits no diagnostic either way (see
[Limitations](#limitations)), so a broken `{List(Int) | len(_) > 0}` return is
caught where the value is *used*, not where it is produced.

---

## Path Sensitivity: Guards Establish Facts

A guard you write becomes an assumption the solver can use. The then-branch
learns the condition; the else-branch learns its negation:

```march
fn get(xs : List(Int), i : Int) : Int do
  if i >= 0 && i < List.length(xs) do
    at(xs, i)          -- ok: the guard proves BOTH halves of the precondition
  else
    0
  end
end
```

(`len` is a measure name usable only inside a `{...}` refinement predicate,
not a callable in ordinary code (verified live, 2026-07-22); use
`List.length` in a plain guard expression like the one above.)

### `List.length` is an alias of the `len` measure

The guard above is a real proof, not a skip. The checker treats the
**qualified** `List.length` as an alias of the `len` measure, so
`i < List.length(xs)` establishes exactly the fact `i < len(xs)` that `at`'s
precondition asks for. Verified 2026-07-28: `--refine-report` on that program
reports `1 proved, 0 violated, 0 trusted, 0 skipped` for user code.

Until 2026-07-28 the two were unconnected symbols and the guarded call was
silent because it was *skipped*, not because it was verified. That is fixed; the
corpus brackets it from both sides (`accept/t118`, `reject/t117`), because an
accept-only witness exits 0 either way and so cannot tell a working guard from a
contract that checks no property.

The alias is intentionally narrow, because attaching `len`'s meaning to the wrong
function would manufacture false positives:

- **Only the qualified `List.length`.** A bare `length` is left as-is.
- **Only while it is the standard library's own.** The stdlib is identified by
  the source files the compiler actually loaded, so it works the same from a
  repo checkout, an installed `share/march`, or a `MARCH_STDLIB` pointing
  anywhere.
- **Withdrawn for the whole compilation unit** if anything in it could make that
  spelling denote a different function: a program defining its own
  `List.length`, a vendored or forked `List` arriving through `MARCH_LIB_PATH`,
  or rebinding `List` via `alias`/`use`. In those cases the obligation goes back
  to unprovable-and-skipped, which is the pre-alias behaviour.

  **The gate is unit-global, and the unit is bigger than the file you are
  editing.** `bin/main.ml` prepends the entire standard library to every
  compilation, and `MARCH_LIB_PATH` adds every `.march` file in every dependency
  directory. One real competitor anywhere in that set disables the alias for
  the whole program, including in files that never mention it. This is a real
  coverage cost, accepted intentionally: deciding whether a competitor could
  actually win at a given call site needs a resolver this pass does not have,
  and the errors are asymmetric: over-withdrawing loses a proof (silence),
  under-withdrawing puts a wrong fact in the assumption set and reports correct
  code, which is the cardinal sin.

- **A glob import RESOLVES its target instead of assuming the worst** (since
  2026-07-29). `import Foo` / `use Foo.*` withdraws the alias only if `Foo`
  actually provides a competing member, decided by walking the compilation
  unit's own module structure (a `use` inside the target is followed
  transitively, under a fuel bound); an unresolvable path, or exhausted fuel,
  still withdraws. Before this, the mere presence of a glob was enough; and
  since `stdlib/system.march` includes a single `import Process` and the stdlib
  is prepended to everything, the alias was withdrawn for **every March program
  yet compiled**. The feature was inert in production and the suite stayed
  green, because a skipped obligation exits 0 exactly as a proved one does; only
  a REJECT witness (`reject/t117`) and the `--refine-report` proof *floor* can
  see the difference.

- **A selector-less `use X.List` RESOLVES its target too** (since 2026-07-31).
  The `UseSingle` form used to withdraw purely syntactically on its last path
  segment, while the glob forms already looked. Measured cost (obligation
  ledger, `MARCH_LIB_PATH` fixture): one nested `use Extras.Deep.List` in a
  dependency module (with a target that had **no `length` member at all**, so it
  could not make `List.length` denote anything non-stdlib at any call site)
  flipped an entry program's obligation from `1 proved` to `1 skipped
  (alias-withdrawn)`, program-wide. Now the use's target is resolved (from
  every module scope of the unit, **all** matches; which resolution the real
  resolver would pick is exactly the question this pass cannot answer) and the
  alias is withdrawn only if some match provides a member with the aliased
  name, where "provides" is fail-closed: direct members in every form the
  member gate counts, plus the target's own use-forms (`use Y.{length}`
  re-exports count; an unenumerable glob inside the target counts; an
  unresolvable path counts). Soundness does not rest on resolver semantics:
  rebinding `List` to a module that verifiably provides no member named `length`
  cannot make `List.length` resolve to a non-stdlib function anywhere. A
  target that provides it via a direct member decl is a `mod List` containing
  that member, which the member-definition gate withdraws independently, so
  this narrowing by itself stands guard over the re-export and unresolvable
  shapes. `alias … as List` and `import X.{List}` still withdraw
  unconditionally: no measured cost has implicated them, and each narrowing
  in this gate must pay its own way.

- **A `use`/`alias` competes only when it is the *program's*** (since
  2026-07-29). The rebinding side now ignores declarations with a span in a
  standard-library source file, exactly as the member-definition side always
  has: an `import` inside `mod System` binds names in System's own body, not
  in the module being checked. This is conjoined with the resolution rule
  above, not substituted for it: a glob withdraws only when it is the
  program's own **and** its target verifiably provides a competitor. Both are
  over-approximations of "really competes", so their intersection still
  contains every real competitor; neither weakens the other's test.

The same treatment applies to strings; see
[String Refinements](#string-refinements).

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

A guard may also read a **record field** (`if c.port >= 1 do serve(c)`); see
[Refining a record over its fields](#refining-a-record-over-its-fields).

### A qualified spelling in a predicate now works (narrow desugar slice)

The alias above applies in a **guard**: ordinary code the desugarer rewrites.
Until 2026-08-03 it did **not** hold inside a **predicate**, the `{T | … }`
itself:

```march
fn inner(xs : {List(Int) | List.length(_) > 0}) : Int do …   -- used to enforce NOTHING
fn inner(xs : {List(Int) | len(_) > 0}) : Int do …           -- always enforced the contract
```

Refinement predicates were never run through the expression desugarer, so
`List.length` stayed a field-access chain rather than the dotted variable the
alias keys on, and the obligation the contract looked like it generated was
simply skipped, silent by default. From 2026-07-30 this shape **warned**
instead of compiling silently, naming the spelling found and the bare `len`
that works; that warning was intentionally sized to fix the *silence*, not the
capability gap (see `specs/progress/2026-07-30-refine-qualified-spelling-in-predicate-warns.md`).

As of 2026-08-03, `Desugar.desugar_ty` (`lib/desugar/desugar.ml`) closes the
capability gap for the specific case that motivated the warning: a **narrow**
slice that flattens a module-path call head (`List.length(_)`) found inside a
`TyRefine` predicate into the dotted form the alias keys on: the *same*
flattening `Desugar.desugar_expr`'s own `EField` arm already applies to an
ordinary call head, and no more. No pipe desugaring, no multi-head-fn
desugaring, no other expression-desugarer infrastructure runs over the predicate.
It is wired into every site a surface `ty` can carry a `TyRefine`: fn
param/return types, `let`-binding annotations (a top-level `let` and a
block-level `let` alike: the `DLet` decl arm and the `ELet` expr arm both
call it), `EAnnot`, and record/variant field types.

When the alias is live (no competing `List.length` in scope, the ordinary
case), the qualified spelling now means exactly what `len` means: `inner([])`
above is rejected as a real precondition violation, and the warning
correctly stops firing (no shape left to warn about). When a unit has
[withdrawn the alias](#listlength-is-an-alias-of-the-len-measure) by defining
its own competing `List.length`, the qualified spelling still enforces
no contract (correctly, since the alias truly does not apply there), and the
warning still fires, still recommending `len`:

```
`List.length` is a qualified call inside a refinement predicate. This
spelling is never reflected here, so the refinement enforces nothing. Use the
bare spelling `len` instead.
```

(The withdrawn case is reached through a different `warn_predicate_expr` arm
than the live case (the flattened spelling arrives as a plain dotted `EVar`
either way, but only fails `known_predicate_fn` when the alias is down), and
both arms share one `warn_qualified_call` fix-suggestion builder specifically so the
message doesn't degrade to the generic "not a measure" wording in the
withdrawn case.)

The same applies to the other qualified measures: `String.byte_size` inside a
predicate now means `len` under the same conditions.

Two limits remain, both intentional and unaffected by this change: the narrow
slice only touches an `EField` chain that bottoms out at a bare,
zero-arg, uppercase module `ECon`, exactly mirroring what `Desugar.desugar_expr`
itself flattens for an ordinary call head:

- A record **field** call (`{Cfg | c.cb(1) > 0}`) still enforces no contract and
  is still not reported as a qualified call; treating it as one would offer
  the field name as a false "bare spelling."
- A receiver that is itself a call (`f(x).g(y)`) is still not rendered as a
  path and stays silent.

Measurement behind this: a stdlib-wide `--refine-report` sweep (all 112
modules, before-the-fix binary vs. post-fix binary, file-copy revert, no
`git stash`) came back **an exact binary match**, because no stdlib predicate uses a
qualified spelling. The instrument was confirmed non-vacuous on the motivating
repro instead: before the fix, `{List(Int) | List.length(_) > 0}` records
`0 proved, 0 violated, 1 skipped`; post-fix, the same program against an
empty-list call records `0 proved, 1 violated, 0 skipped`: the obligation
went from silently skipped to truly checked. See
`specs/progress/2026-08-03-refine-desugar-predicate-qualified-spelling.md`
for the full writeup, including why the task's originally-scoped anchor site
(`Desugar.respan_ty`'s `TyRefine` arm) turned out to be dead code for this
path: it is reachable only through derive-expansion span uniquification, not
through ordinary function-signature desugaring, which is why the fix lives in
a new `Desugar.desugar_ty` instead.

### A refinement in an interface signature enforces no contract

The predicate above is at least *reached* by the checker. A refinement written
in an **`interface` method signature** is not reached at all:

```march
interface Runner(a) do
  fn run : a -> {Int | _ > 0} -> Int    -- enforces NOTHING
end
```

No code in `lib/refinecheck` reads a method declaration's type: the pass's
`interface` arm descends only into a method's **default body**, and the other
walks that visit an interface read method *names* only. Nor does the front end
carry the predicate anywhere: when the desugarer injects a default method into
an `impl`, it synthesises that function with no return annotation and with
parameters taken from the default lambda, which carry no annotations either. So
the predicate obliges no call site **and** lets no body assume anything: a
*missing* check rather than an unsound one, but a silent one, and the contract
reads exactly like a working one.

Since 2026-07-30 this **warns**, naming the method and the spelling that works:

```
the interface signature of `run` carries a refinement, which enforces nothing:
an interface method signature is never read by the refinement checker, so no
call site is obliged by this predicate and no body may assume it. Write the
refinement on the corresponding `impl` method's own signature instead — …
```

The fix is the `impl` method's own signature, and it is given for **both
positions** because they are enforced under different conditions:

```march
interface Bumper(a) do
  fn bump : a -> Int -> Int              -- leave the signature unrefined
end

impl Bumper(Box) do
  fn bump(_b : Box, n : {Int | _ > 0}) : Int do n end   -- enforced here
end
```

- A refinement on the `impl` method's **return type** is always checked: the
  postcondition check runs on every method body unconditionally.
- A refinement on a **parameter** is enforced only when the method name is
  **unambiguous**: exactly one `impl` defines it and no top-level `fn` shares
  the name. Otherwise a call resolved by name cannot tell which contract
  applies, so the contract is adopted in no place and the body is traversed with the
  parameter refinements stripped. (The full adoption rule is under
  [`@[trusted]`: a scoped, conspicuous escape hatch](#trusted-a-scoped-conspicuous-escape-hatch),
  in the "What 'traversed' does and does not buy you" note.)

The typechecker accepts a refined `impl` parameter against a plain type in the
interface, so following this advice needs no change to the interface; and the
resulting contract really is enforced: `bump(Box(1), 0 - 5)` is a refinement
error.

Outside `cap verified` this is a warning rather than an error on purpose: the
shape compiles today, and the bug being fixed is the *silence*. Making an
interface signature actually enforce (obliging every call dispatched through
the interface and checking it against every `impl`) is a much larger change
and stays open in `specs/todos/`. Witnessed by `accept/t137` (its exit code
is the point: it pins that the program stays exit 0 outside `cap verified`)
and by `test_refinecheck.ml`'s `interface-signature-refinement` suite, which
pins the warning text, the return-position case, and a false-positive control
that a refinement on an `impl` method is *not* reported as inert.

**Under `cap verified` this is an error.** Decided 2026-08-03
(`specs/progress/2026-08-03-cap-verified-interface-signature-decision.md`):
`cap verified`'s escalation infrastructure otherwise fires only on undischarged
*obligations*, and an inert interface signature raises none, so this is new
infrastructure rather than a flipped flag. But the mode's whole promise is "if it
compiles, it is proved," and every other inert-refinement shape this project
has found (the qualified-spelling case above, `sig`/`extern` signatures below)
already warns specifically because silence was assessed as the greater harm. An inert
`interface` signature under `cap verified` is exactly the shape the
capability exists to catch:

```march
mod P do
  cap verified
  interface Runner(a) do
    fn run : a -> {Int | _ > 0} -> Int    -- ERROR under cap verified
  end
  fn main() : Int do 0 end
end
```

exits 1 with the same message, promoted to an error. Outside `cap verified`
the fixture above is unaffected and still exits 0 with a warning, pinned by
the paired tests in `test_refinecheck.ml`'s `interface-signature-refinement`
suite.

### The same applies to a `sig` or an `extern` signature

Two further declaration forms carry a type the checker never reads, and both
were silent until 2026-07-31:

```march
sig Store do
  fn put : Int -> {Int | _ > 0}          -- enforces NOTHING
end

extern "c" : Cap(IO.Foreign) do
  fn take(n : {Int | _ > 0}) : Int = "take"   -- enforces NOTHING
end
```

Both now **warn**, and the two messages say intentionally different things,
because the reasons are not the same and one fix would be wrong advice for
the other position:

- A **`sig`** refinement is only *unread*. A `sig` is an ascription: it
  constrains what a module exports, not what any particular function body does,
  so there is no function definition for the predicate to attach to and no call
  site that consults it. The fix is the module's **own `fn` definition**,
  where a parameter refinement obliges callers and a return refinement is
  checked against the body.
- An **`extern`** refinement cannot be honoured *in principle*. The callee is
  foreign C: there is no March body to discharge a claim about the value it
  returns, and *assuming* such a claim would be **unsound** rather than only
  missing. So the fix is not "move it somewhere it gets checked"; it is a
  March **wrapper** that includes the *parameter* refinement (where call sites
  really are obliged), with the foreign *result* checked at run time rather
  than taken on faith from its type.

Both an extern's parameters and its return type are inspected; they are
separate positions and a check covering only one would stay silent on the
other.

As above, these are warnings and not errors on purpose: the shapes compile
today and the bug is the silence. Making a `sig` ascription or an FFI
boundary actually *enforce* a refinement is a much larger question and stays
open. Witnessed by `accept/t140` (its exit code is the point, pinning that
all three shapes stay exit 0) and by `test_refinecheck.ml`'s
`sig-extern-refinement` suite, which pins both message texts, the
return-position extern case, and unrefined-signature controls for each form.

---

## A Parameter's Own Contract Is a Fact Inside Its Body

A **guard** and a **declared contract** are two different ways to establish the
same fact, and it matters which one you have. The section above is about the
guard: a runtime test you write (`if List.length(ys) > 0 do …`) becomes an
assumption for the branch it dominates. This section is about the other one: a
parameter with a *declared type* that includes a refinement is a promise the caller
already had to keep, and since 2026-07-29 that promise is an assumption inside
the function's own body. So contracts **compose** across a call boundary: a
function that requires a property can pass its own parameter on to another
function requiring the same property, with no guard at either site:

```march
fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
fn outer(ys : {List(Int) | len(_) > 0}) : Int do inner(ys) end
fn main() : Int do outer([1]) end
```

Both call sites are **proved**: `--refine-report` on that program reports
`2 proved, 0 violated, 0 trusted, 0 skipped` for user code (verified 2026-07-29). Before
this, `outer([1])` proved on the literal while `inner(ys)` was silently
*skipped*, so the practical upper limit was that a non-empty contract could not be
threaded any further than one hop. The stdlib's own contracts now compose the
same way, which is what makes them usable rather than decorative:

```march
mod Y do
  cap verified
  fn head_of(xs : {List(Int) | len(_) > 0}) : Int do
    List.head(xs)          -- proved from `head_of`'s own contract; no guard
  end
  fn main() : Int do head_of([1, 2]) end
end
```

That program exits 0 under `cap verified` (`2 proved, 0 violated, 0 trusted, 0 skipped`).

**Every refined form composes.** All verified 2026-07-29 at
`2 proved, 0 violated, 0 trusted, 0 skipped`: `Int` (`{Int | _ > 0}`), `Float`, `Bool`,
`String` (`{String | len(_) > 0}`), a record field
(`{v : Config | v.port >= 1}`), the built-in list `len`, a user `@[measure]`
over an ADT (`{Tree(Int) | size(_) > 0}`), and a **constructor tag**
(`{Option(Int) | is_Some(_)}`). The tag form composes only for the constructor
the caller actually promised: a caller declaring `is_None(_)` does not
discharge a callee wanting `is_Some(_)`; that call stays skipped. See
[Limitations](#limitations).

**Only the caller's own promise is loaded, and only what it actually entails.**
A *weaker* declared contract does not launder a stronger requirement: with
`outer(ys : {List(Int) | len(_) >= 0})` (true of every list), the same
`inner(ys)` is **skipped**, not proved and not reported
(`1 proved, 1 skipped`). This is the definite-failure stance holding, and it is
the false positive that matters most in this area, so the corpus brackets the
feature from both sides: `accept/t128` shows the composition, and
`reject/t129` shows the weak contract failing to launder while a real
violation on the same shape is still caught.

**The fact is retired the moment the name is rebound.** The promise belongs to
the parameter, not to the spelling, so shadowing it drops the assumption rather
than leaking it onto a different value:

```march
fn outer(ys : {List(Int) | len(_) > 0}) : Int do
  let ys = List.tail(ys)   -- this call IS proved from ys's own contract
  inner(ys)                -- skipped: the new `ys` promises nothing
end
```

A `match`-arm binder of the same name (`Cons(_, ys) -> inner(ys)`) retires it
identically. Both leave the call **skipped**, never falsely proved and never
falsely reported.

**A local `let` carries a fact forward only for an `Int` value of a simple
shape.** `let n = e` records `n == e` when `e` is an integer literal, a variable
the typechecker says is `Int`, `+`/`-` over those, `*` with one literal factor,
or an `if` whose arms are all of those (recorded as a case split on the guard).
A call's proved return refinement reaches its `let`-bound result as well. So

```march
let u = 5
let v = u
take_pos(v)      -- proved
```

Any other type carries nothing: `let u = [1, 2]` then `inner(u)` against
`{List(Int) | len(_) > 0}` is skipped, and so is `let b = true` against a
`Bool` refinement. Pass the value directly, or restate the fact with `assert`.

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
error** when it is demonstrably violated (the solver proves it can never hold,
or a [counterexample](#counterexamples-the-failing-input-in-source-terms) is
run and observed to fail), silent **proof** when it always holds, and a silent
**skip** when the checker can't decide either way. It also counts toward
[`--refine-report`](#counting-the-obligations---refine-report) (tagged
`postcondition` rather than `precondition` in the report's `by kind` line)
and, inside a `cap verified` module, an undischarged postcondition is a
compile error exactly like an undischarged precondition:

```march
mod Checked do
  cap verified

  fn cube(z : Int) : Int do z * z * z end

  fn mk(z : Int) : {Int | _ > 0} do
    cube(z) * 0 + 1 + cube(z) - cube(z)   -- error under cap verified: the
  end                                     -- return expression is unreflectable
end
```

Without `cap verified` the same `mk` compiles: its obligation is skipped
(`unreflectable-subject`), not reported.

`@[trusted]` rescues a postcondition the same way it rescues a precondition;
see [`@[trusted]`](#trusted-a-scoped-conspicuous-escape-hatch) below.

**What doesn't carry through:** proving a *plain* postcondition (as above) is
different from proving a **relational** one that relates a measure across an
operation (`size(insert(t, x)) == size(t) + 1`), which needs the checker to
supply an induction hypothesis at each structurally-recursive call. That
narrower, more powerful case is covered in [Limitations](#limitations), under
"Structural induction (Tier 2)".

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

Resolution follows the same rules as everything else: direct named calls,
across modules, through `alias` and `use`.

**Relational postconditions propagate too, by substitution.** A predicate that
mentions a parameter (`{Int | _ < n}`, `{Int | _ < len(xs)}`) is *relational*.
At a call site the call's arguments are substituted for the callee's parameters,
which restates the contract entirely in the caller's own terms:

```march
fn below(n : Int) : {Int | _ < n} do n - 1 end
fn takepos(k : {Int | _ >= 0}) : Int do k end

takepos(below(0))       -- error: `_ < n` instantiates to `_ < 0`, never >= 0
takepos(below(10))      -- fine: `_ < 10` can still be >= 0
```

Parameters are matched to arguments **positionally**, and substitution is
**simultaneous**: with `fn f(n : Int, m : Int) : {Int | _ < n + m}` called as
`f(m, 1)`, the result is `_ < m + 1` (the caller's `m`), never `_ < 1 + 1`.

Propagation is **skipped** (silently, and with no loss of soundness) whenever
the instantiation cannot be made exactly:

- the predicate mentions a name that is neither the refinement binder nor one of
  the callee's parameters;
- a parameter the predicate mentions has no corresponding argument (an arity
  mismatch, or an omitted defaulted argument);
- the predicate uses syntax the checker does not reflect;
- the callee has a *pattern* parameter, which is rewritten before this pass runs
  and so no longer includes the parameter names the predicate refers to.

A partially substituted predicate is never used: mixing the callee's and the
caller's namespaces is exactly how a false positive would arise here, so the
checker abandons the whole instantiation rather than guess at part of it.

**Only *proven* postconditions propagate.** A declared return refinement
becomes an assumption at call sites only when the definition side actually
*proved* it: every return path of every clause discharged as verified. A
postcondition the checker can neither prove nor refute stays perfectly legal at
the definition (rejecting it would flag correct-but-unprovable code), it simply
does not travel: callers learn no fact from it.

This is not a stylistic preference, it is what keeps the no-false-positives
promise. A propagated fact is *added* to the assumptions a call-site query
proves against, so a false assumption makes a violation easier to "prove": a
stale `{Int | _ < 0}` on a function that in fact returns `6` would flag the
perfectly correct call `takepos(score(5))`. Only facts that are true may be
assumed. The cost is incompleteness (a postcondition with a body opaque to
the solver buys its callers no facts), which is the safe direction and the trade
this checker makes everywhere else.

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
elsewhere. Resolution is scope-aware about imports: at each enclosing scope the
checker consults that scope's own definition and then that *same* scope's
`use`-imports before falling outward. So a `use` written **inside** a nested
module beats an enclosing module's own definition of the same name, matching
how the call really dispatches, while an enclosing module's `use` still loses
to a nested module's *own* definition: an import never reaches in and
overrides a local one.

```march
mod Outer do
  fn take_pos(n : {Int | n >= 0}) : Int do n end   -- Outer's own contract

  mod Inner do
    use Lib.{take_pos}                              -- Lib's take_pos, unrefined

    fn go() : Int do
      take_pos(-1)   -- resolves to Lib.take_pos, NOT Outer's: no error
    end
  end
end
```

Checking this call against the enclosing `Outer.take_pos` instead would be a
false positive on correct code, since `Inner.go` never actually calls it. (This
was a live false positive until 2026-07-31; see item 6 in
[Open holes](#open-holes-stated-as-of-2026-07-29).)

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

## Measures: Refining over Data Structures

A **measure** is a function from a value to an `Int` (or `Bool`) that you can
mention in predicates. The built-in `len` measures a list:

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

The solver reasons about measures **by structure**: from the recursion
equations above it computes `size(Node(Leaf, x, Leaf)) = 1`, so an out-of-bounds
index into a literal tree is caught, and `size(t) >= 0` is known for any `t`.
Measures may call **other measures** and be **mutually recursive** (e.g. a
`Tree`/`Forest` pair), and the built-in `List` is modelled too, so a user
`length` measure over `List(a)` reasons by structure just like `size`.

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

### Refining a collection over its own length

The measure may also range over the refined value **itself**, which is how a
non-empty-collection precondition is written:

```march
fn head(xs : {List(a) | len(_) > 0}) : a do ... end
```

All three spellings of the refined value mean the same thing here and are
checked identically: the anonymous `_`, a named binder, and the parameter's own
name:

```march
fn head(xs : {List(a)     | len(_)  > 0}) : a do ... end
fn head(xs : {v : List(a) | len(v)  > 0}) : a do ... end
fn head(xs : {List(a)     | len(xs) > 0}) : a do ... end
```

A call with a literal empty list is a definite failure and is reported;
`head([1, 2])` is silent; and a `List` with contents the checker cannot see
stays **unknown**, so it is skipped rather than guessed:

```march
head([])            -- reported: `len(_) > 0` cannot hold
head([1, 2])        -- silent
fn f(ys : List(Int)) : Int do head(ys) end   -- skipped: length unknown
```

Thirteen stdlib functions that panic on an empty argument carry this contract:
`List.head`/`tail`/`last`/`minimum_int`/`maximum_int`, the `prelude` `head`/`tail`,
`Stats.mean`/`min_val`/`max_val`, `Gen.element`/`one_of`, and `Random.choice`. Each
is derived from that function's own panic message, so the contract is never
stronger than the check the code already performs, and the `panic` remains as the
runtime safety net for the arguments the checker skips.

**The whole `Stats` surface states its non-empty precondition** (2026-09-22).
Beyond `mean`/`min_val`/`max_val`, every `Stats` function that needs a
non-empty list declares `{List(Float) | len(_) > 0}` on it: `percentile`,
`median`, `quantile`, `quantile_default`, `quantiles`, `iqr`, `iqr_default`,
`five_number_summary`, `variance`, `std_dev` and `mode` (`covariance`,
`correlation` and `linear_regression` require `len(_) >= 2`). Before this,
`median`, `quantile_default`, `iqr`, `iqr_default` and `std_dev` forwarded to a
contracted callee without restating the contract, so the checker had nothing to
carry to *their* callers: `Stats.median([])` compiled and panicked at run time.
It is now a compile error, and a caller that cannot establish non-emptiness gets
the propagation warning described under
[Promoting a skip](#promoting-a-skip-a-demonstrated-precondition-failure) below (an error under
`cap verified`). The migration path is `--refine-suggest`:

```
$ march --check --refine-suggest summarize app.march
summarize (app.march:3)
    xs : List(Float)  ->  xs : {List(Float) | len(_) > 0}
  discharges all 1 unproven obligation(s)
```

Either restate the proposed refinement upward (the caller's own callers then
carry it), or guard the call with `match xs do Nil -> … _ -> Stats.median(xs)
end`, which the checker proves. `Stats.sum`, `count`, `variance_pop`,
`std_dev_pop` and the `*_safe` variants still accept any list.

`List.nth` is the fourteenth, and the only one with a contract that is
**cross-parameter** rather than over the refined value itself (2026-08-04):

```march
fn nth(xs : List(a), n : {Int | _ >= 0 && _ < len(xs)}) : a do ... end
```

`List.nth([1, 2, 3], 7)` and `List.nth([1, 2, 3], -1)` are reported; an index the
checker cannot bound (the overwhelmingly common case) stays **skipped and
silent**, exactly as `head(ys)` does for an unknown list. That is not a
concession, it is the point: a blast-radius sweep taken before the contract
shipped (all 112 stdlib modules <!-- doc-lint:ignore-count: historical snapshot at the
time this sweep ran (2026-08-04), not a claim about today's stdlib size -->
plus the `forgepm`, `bastion`, `conduit` and
`depot` projects) produced **zero** new violations and only new skips. Witnesses
`accept/t141`, `reject/t142`. That silence is conditional on being outside
`cap verified`, though: inside a `cap verified` module the same unbindable
index is an undischarged precondition, and therefore a hard error, not a skip
(see [`cap verified`: turning silence into an
error](#cap-verified-turning-silence-into-an-error)).

`Array.get` / `set` / `pop` carry the same cross-parameter treatment
(2026-09-14): `idx : {Int | _ >= 0 && _ < pvec_length(v)}`, and
`pop(v : {PVec(a) | pvec_length(_) > 0})`. `pvec_length` is a private
single-arm `@[measure]` reading `PVec`'s count field (private so it cannot
collide with a user `@[measure] fn length`); `Array.length(v)` in a guard is
aliased to it, gated like `List.length` → `len` on the call really naming the
stdlib member. Because the three moved from `cap no_panic`'s syntactic ban
list to its proof-checked set, a guarded call is now accepted there and an
unguarded one is still an error. Swept first over 1171 files (stdlib,
`test/native`, `test/stdlib`, eighteen ecosystem projects): zero new
violations, zero exit-code changes, only new skips at computed indices.
Progress: `specs/progress/2026-09-13-array-bounds-contracts.md`.

Length postconditions followed (2026-09-15): `empty() : {PVec(a) |
pvec_length(_) == 0}` (proved: a bare constructor application), and under
`@[assume]` `push` (`== pvec_length(v) + 1`), `set` and `map`
(`== pvec_length(v)`) and `from_list` (`== len(xs)`). Neither `set`'s nor
`push`'s body proves (`unreflectable-subject`: the tail/trie `if` and
`push_leaf`'s tuple); `map` and `from_list` recurse through local helpers.
Each assumed one has a runtime witness at the representation's boundary
sizes (0, 1, 31–33, 63–65, 1023–1025, 1057) in `test/stdlib/test_array.march`.
The facts compose one call deep: a relation over a parameter or a guarded
value reaches a `let`-bound result, but `push(push(empty(), 1), 2)` through
two `let`s does not, since the checker does not chain a let-bound call's
postcondition into the next call's. Diagnostics render `pvec_length(x)` as
`Array.length(x)` (`Refine_encode.display_measures`, message text only; the
ledger keeps the raw predicate). Progress:
`specs/progress/2026-09-15-array-contract-followups.md`.

An ordinary `List.length(ys) > 0` guard **does** discharge this obligation, so
the contract bites on a list you validated at runtime and not only on literals:

```march
fn first_or(ys : List(Int), d : Int) : Int do
  if List.length(ys) > 0 do head(ys) else d end   -- proved
end

fn broken(ys : List(Int)) : Int do
  if List.length(ys) == 0 do head(ys) else 0 end  -- reported: len(_) > 0 cannot hold
end
```

Verified 2026-07-28 (`accept/t118`, `reject/t117`). See
[`List.length` is an alias of the `len` measure](#listlength-is-an-alias-of-the-len-measure)
for the exact conditions under which the alias applies, and for when it is
withdrawn, in which case the obligation returns to being skipped.

A runtime **guard** is not the only way to discharge this. If the *enclosing
function* already declares the same contract on the parameter, no guard is
needed at all: the promise composes into the call. That is a different
mechanism from the guard above; see [A Parameter's Own Contract Is a Fact
Inside Its Body](#a-parameters-own-contract-is-a-fact-inside-its-body).

### Refining a record over its fields

A refinement may also range over a **record** type, with the predicate reading
its fields. This works on **both** sides of a signature, as a postcondition on
the return type, and as a precondition on a parameter:

```march
type Config = { port : Int, retries : Int }

-- precondition: callers must pass a config with a usable port
fn serve(c : {v : Config | v.port >= 1 && v.retries >= 0}) : Int do c.port end

-- postcondition: this function promises a valid config
fn defaults() : {v : Config | v.port >= 1} do { port: 8080, retries: 3 } end
```

At a call site the argument is checked against the field predicate:

```march
serve({ port: 8080, retries: 3 })   -- fine
serve({ port: 0, retries: 3 })      -- error: `v.port >= 1` can never hold
serve({ retries: 0, port: 0 })      -- same error; field order doesn't matter
```

What counts as a **fact** about a record argument:

- **A record literal.** Its field values are known, so the predicate is decided
  against them. Fields may be written in any order; they are matched to the
  declaration by name, not position.
- **A variable holding a record-refined parameter or local.** Its own
  refinement travels with it, so a call forwards:

  ```march
  fn fwd(c : {v : Config | v.port >= 1}) : Int do serve(c) end   -- fine
  ```

  Forwarding obeys the same definite-failure rule as everything else: a
  *weaker* incoming refinement (`v.port >= 0`) neither proves nor contradicts
  the callee's, so it is **skipped**, not reported. Only a *contradictory* one
  (`v.port <= 0`) is an error.

- **A guard on a field.** A field comparison in an enclosing `if`, `when` or
  `assert` is a path condition like any other, so it reaches the call:

  ```march
  fn f(c : Config) : Int do
    if c.port >= 1 do serve(c)          -- fine: the guard discharges it
    else 0 end
  end

  fn g(c : Config) : Int do
    if c.port <= 0 do serve(c)          -- error: the guard makes it definite
    else 0 end
  end
  ```

  The variable does not need a refinement of its own: a plainly-typed
  `c : Config` works, because an unrefined record variable is modelled as an
  unconstrained value and it is the *guard* that determines it. With no guard
  no fact is known and the call is skipped, exactly as before.

  Field facts obey the same rebinding rule as tag facts and scalar facts: a
  fact is recorded against a *name*, so a `let`, a `let?`, a lambda parameter
  or a `match` binder that rebinds that name retires it.

Everything else about a record is **skipped**:

- an **unrefined record variable with no guard on the field**: no fact is
  known about its fields;
- a record literal with an **unknown field value** (`{ port: p }` for a
  parameter `p`): no fact is known about that field, so a predicate over it
  is neither proven nor refuted.

An **unreflectable field does not sink its siblings.** A field with a type
outside the reflected fragment (a `String`, a function, a nested record bound
to anything but a literal), or a **list field holding concrete elements**
(`history: Cons(1, Nil)`; the built-in `List` is generic, so the checker models
its element type as an opaque sort an `Int` cannot be placed in), is replaced by
an unconstrained stand-in of the right shape. The rest of the record is checked
normally:

```march
type Config = { port : Int, name : String }

serve({ port: 0, name: n })    -- error: `port` is still checked
```

No conclusion may be made *about* the stand-in, in either direction: a predicate
over that field is skipped, whether it happens to hold or not:

```march
type State = { count : Int, history : List(Int) }
fn take(s : {v : State | len(v.history) == v.count}) : Int do s.count end

take({ count: 5, history: Cons(1, Nil) })   -- silent, though `len` is really 1
```

An **empty** list (`history: Nil`) has no elements and reflects exactly, which is
what the `len(v.history) == v.count` examples above rely on.

The stand-in applies to a **call site** only. On the return side an
unreflectable field still skips the whole record: postcondition checking treats a
counterexample over a concrete record as definite, and a counterexample free to
pick the stand-in's value would not be one.

Records also compose with measures: `{v : State | len(v.history) == v.count}`
reasons about a `List` field by structure, exactly as `len` does elsewhere.

---

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

`len` is **overloaded**: the same name measures a list and a String. Which one
applies is decided by the *declared* base type of the value being measured, never
guessed from context, so `{Int | _ < len(xs)}` over a `List` and
`{String | len(_) > 0}` over a `String` coexist without ambiguity. If the checker
cannot tell, it skips the obligation rather than assume.

`len` counts **bytes**. For non-ASCII text a character is several bytes:
`len("é")` is 2, not 1. March *does* have a codepoint-length primitive
(`String.codepoint_count`, which returns 1 for `"é"`), and it is intentionally not
what `len` denotes. (An earlier revision of this page claimed no such primitive
existed. It does; reasoning from that claim is how a codepoint count nearly got
equated with a byte count.)

### A byte-length guard discharges a String `len` obligation

Just as `List.length` aliases `len` for lists, the **byte-valued** string-length
spellings alias `len` for strings (`String.byte_size` and the
`string_byte_length` builtin):

```march
fn label(t : String) : String do
  if String.byte_size(t) > 0 do slug(t) else "?" end   -- proved
end
```

Verified 2026-07-28: `--refine-report` on that program reports `1 proved,
0 violated, 0 trusted, 0 skipped` for user code. The contradictory `String.byte_size(t) == 0`
form is reported as a violation.

Only byte-valued spellings are aliased, because `len` is a byte count:

- `String.codepoint_count` and its legacy alias `grapheme_count` count
  codepoints, not bytes, and are left as-is.
- `string_length` is **also** a byte length (it lowers to
  `march_string_byte_length`, and `string_length("é")` is 2) but it is
  intentionally *not* aliased. The abstention is about the NAME, not the current
  semantics: `string_length` reads like a character count, and if it were later
  corrected to one, an alias written today would silently become unsound. The
  unambiguous `String.byte_size` states what it means and is the spelling to use
  in a guard.

The same withdrawal rules as the list alias apply: a program that defines its own
`String.byte_size` (unless it *is* the standard library's) (in any declaration
form: a `fn`, a module-level `let`, an `extern` block, an interface or impl
method) rebinds `String` via `alias`/`use`, or binds the name
`string_byte_length` itself (as a declaration,
an import, a `let`, a lambda or `fn` parameter, or a match binder) loses the
alias for the whole **compilation unit** (prepended stdlib and every
`MARCH_LIB_PATH` dependency included), and the obligation returns to being
skipped. A glob import (and, since 2026-07-31, a selector-less `use X.String`)
withdraws only if its resolved target really provides the
competitor; see
[`List.length` is an alias of the `len` measure](#listlength-is-an-alias-of-the-len-measure).

### A `== ""` guard establishes a length

```march
if s == "" do 0 else nonempty(s) end
```

The else-branch discharges `nonempty`'s `{String | len(_) > 0}`. `Str` is an
opaque sort and `$strlen` is otherwise constrained only by non-negativity, so
this does not come for free: each declared string constant carries the ground
implication `s != "" -> len(s) > 0`, which is true of byte length (the empty
string is the only string of length 0) and needs no string theory. It is a
ground implication per constant rather than a quantified axiom on purpose —
quantified axioms are what once turned every stdlib `Array` bounds check into
a 1.5 s `unknown`.

The then-branch proves nothing: the fact is conditional on `s != ""`, so a
call guarded the wrong way round stays skipped, as it should.

### What String refinements do *not* do

The encoding models `String` as an **opaque sort** with `len` as an uninterpreted
function, intentionally outside any SMT string theory, so queries stay decidable
and cheap. The consequence worth spelling out clearly:

- **No prefix, suffix, contains, concatenation, or regex reasoning.** Only `len`
  and `==`/`!=` against literals are understood. Any other string operation in a
  predicate makes the obligation unreflectable, and unreflectable means skipped.

### The measure soundness gate

A `@[measure]` is a *promise* that the function is a **total, terminating, pure**
mathematical function: the solver trusts it, so a broken one would let it
"prove" anything. March enforces the promise as a **hard compile error**. A
`@[measure]` is rejected if it:

- has an **effect** (`spawn`, `send`, `dbg`, `assert`),
- can **diverge or abort** (`panic`, `todo`, `exit`),
- is **non-total**: a non-exhaustive `match` on its parameter, or a `/` / `%`
  that could divide by zero,
- is **not recursive over the structure**: a recursive call with an argument that isn't a
  component of the matched parameter,
- does **not take exactly one parameter**, the value it measures: a predicate can
  only apply a measure to one argument, so a zero-argument or multi-parameter
  `@[measure]` could never be translated and the annotation would only silence
  the vocabulary warning while every call site went unverified. A zero-argument
  constant needs no annotation (see [Constant functions as
  bounds](#constant-functions-as-bounds)).

A measure that is sound but outside what the encoding can model (see
limitations) isn't an error: it simply falls back to weaker, symbolic
reasoning. "Weaker" can mean *no reasoning at all*: a measure with a value that is a
scalar constructor field discharges neither a predicate nor its negation, and
that case is not always warned about. See [Limitations](#limitations).

---

## Set Refinements

A predicate can talk about **which elements** a collection holds, not only how
many. The vocabulary is Liquid Haskell's, in March spelling
(`specs/2026-09-13-set-refinements-design.md`):

| Predicate | Meaning |
| --- | --- |
| `elts(xs)` | the set of elements of a `List` |
| `keys(m)` | the set of keys of a `Map` |
| `member(x, s)` | `x` is in `s` |
| `union(a, b)`, `inter(a, b)`, `diff(a, b)` | the usual set operations |
| `subset(a, b)` | every element of `a` is in `b` |
| `singleton(x)`, `empty` | the one-element set, the empty set |
| `a == b`, `a != b` | extensional set equality |
| `card(s)` | the number of elements of `s` |

Like `len`, these names mean something **only inside a `{...}` predicate**; a
function or variable of the same name in ordinary code is unaffected. `empty`
is the empty set only in a **set position**: an operand of `union`, `inter`,
`diff` or `subset`, the second argument of `member`, or a side of `==`/`!=`
whose other side is a set (`elts(_) == empty`). Anywhere else it is an ordinary
name, so a parameter or local called `empty` keeps its meaning. Sets are encoded as
Z3 arrays from the element sort to `Bool`, so every set query is
quantifier-free and decidable: `Int` and `String` elements are concrete (a
string literal compares by literal distinctness, as elsewhere), any other
element type is opaque.

```march
fn need2(xs : {List(Int) | member(2, elts(_))}) : Int do 0 end
fn ok() : Int do need2([1, 2, 3]) end      -- proved
fn bad() : Int do need2([1, 3]) end        -- refinement violation

-- relational: a contract may relate a return to a parameter
fn keep(xs : List(Int)) : {List(Int) | elts(_) == elts(xs)} do xs end

-- and compose through a call, a `let`, or a parameter's own promise
fn mk() : {List(Int) | member(2, elts(_))} do [2, 5] end
fn use_it() : Int do
  let ys = mk()
  need2(ys)                                -- proved from `mk`'s contract
end
```

The definite-failure stance is unchanged: `fn lose(xs : List(Int)) :
{List(Int) | elts(_) == elts(xs)} do [7] end` is **skipped**, not reported,
because `xs` may well be `[7]`.

A set holds **one element type**. A set predicate whose operands have known,
different element types is an error at the predicate:

```march
fn f(xs : {List(Int) | member("a", elts(_))}) : Int do 0 end
-- error: this set predicate mixes element types: the element type of
-- `elts(_)` is `Int` but the type of `"a"` is `String`.
```

Element types are read from declared types, so an unannotated value or a type
variable is never reported.

### The stdlib `Set` and `Map` carry assumed contracts

`Set(a)` and `Map(k, v)` are hash tries no measure can see into, so their
element sets are stated rather than proved: every public `Set` operation
(`empty`, `singleton`, `insert`, `remove`, `union`, `intersection`,
`difference`, `contains`, `is_subset`, `is_empty`, `eq`, `to_list`,
`from_list`) and the key-affecting `Map` operations (`empty`, `singleton`,
`insert`, `remove`, `get`, `contains_key`, `is_empty`, `keys`, `map_values`,
`filter`, `merge`) declare their effect on `elts`/`keys` under `@[assume]`.
`Map.filter` also assumes an entry fact, `Map(k[p], v[p])`: every entry of its
result satisfies `pred` (see [two-argument abstract
refinements](#abstract-refinements-filter-keeps-what-its-predicate-says)).

```march
@[assume]
fn insert(s, elem, cmp) : {Set(a) | elts(_) == union(elts(s), singleton(elem))} do … end
@[assume]
fn get(m, key, cmp) : {Option(v) | is_Some(_) == member(key, keys(m))} do … end
```

`@[assume]` is the counterpart of Liquid Haskell's `assume`: the return
refinement propagates to every call site **without a proof** and the body is
not checked against it. It differs from `@[trusted]`, which only accepts a
*skip* inside `cap verified` and never propagates. Each assumed contract is
counted in `--refine-report` under `trusted`, and each one in the stdlib has a
runtime property witness in `test/stdlib/test_set.march` /
`test/stdlib/test_map.march`, because the contracts hold only when the
comparator `cmp` is a strict total order consistent with `==` on the element
type. That trust boundary is the price of an opaque implementation.

With those contracts, membership flows through the API and through guards:

```march
fn need_x(s : Set(Int), x : {Int | member(_, elts(s))}) : Int do 0 end

fn ok(x : Int) : Int do
  let s = Set.insert(Set.empty(), x, int_cmp)
  need_x(s, x)                                       -- proved
end
fn guarded(s : Set(Int), x : Int) : Int do
  if Set.contains(s, x, int_cmp) do need_x(s, x) else 0 end   -- proved
end
fn wrong_branch(s : Set(Int), x : Int) : Int do
  if Set.contains(s, x, int_cmp) do 0 else need_x(s, x) end   -- violation
end
fn need_some(o : {Option(String) | is_Some(_)}) : Int do 0 end
fn lookup(m : Map(Int, String)) : Int do
  need_some(Map.get(Map.insert(m, 7, "x", int_cmp), 7, int_cmp))   -- proved
end
```

A guard that *is* a call with a Bool contract, or a Bool local bound to one
(`let present = Set.contains(…)` then `if present`), establishes the contract
on its branch and its negation on the other.

### Proved list contracts

A function that recurses over a list parameter can have its `elts` and `len`
contract **proved** rather than assumed: the checker unfolds `len` and `elts`
over the matched list's `Cons` cells and assumes the contract for the
recursive call on its tail. A proved contract reaches call sites like any
other. The stdlib's `List.reverse`, `List.append`, `List.filter` and
`List.dedup` carry such contracts, proved from their bodies as written:

```march
fn reverse(xs : List(a)) : {List(a) | elts(_) == elts(xs)} do
  fn go(lst : List(a), acc : List(a)) : {List(a) | elts(_) == union(elts(lst), elts(acc))} do
    match lst do
    Nil        -> acc
    Cons(h, t) -> go(t, Cons(h, acc))
    end
  end
  go(xs, Nil)
end

fn no_two(zs : {List(Int) | !member(2, elts(_))}) : Int do 0 end
fn bad(ys : {List(Int) | member(2, elts(_))}) : Int do no_two(List.reverse(ys)) end
-- refinement violation
```

The pieces that make this work: a local `fn` like `go` is proved first and
its contract used by the body around it; a call to another function uses that
function's proved contract; and a parameter refinement is an invariant the
body may assume (`dedup`'s helper takes `acc : {List(a) | member(prev,
elts(_))}`). A contract is used only once it is proved, whatever the
declaration order, so two functions cannot prove each other's claims. A
contract that is not proved is still not reported unless it can never hold,
and it does not reach call sites. `List.map` has no such contract: the
elements of an arbitrary callback's image have no set expression.

### `SortedSet` is proved, not assumed

`SortedSet` is an AVL tree the checker can see into, so its tree operations
carry contracts **proved** from their bodies against a set-valued measure over
the tree, `sorted_set_elts`: building a node, both rotations, rebalancing, insertion
(`sorted_set_elts(_) == union(sorted_set_elts(t), singleton(x))`), deleting the minimum,
and flattening to a list. One fact is assumed, the comparator law, stated once
as `compare_by(cmp, x, k) : {Int | (_ == 0) == (x == k)}`; every comparison in
the tree goes through it. What needs the search-tree ordering invariant
(exact membership, exact deletion) is a quantified property and stays
unclaimed. A differential property test checks `SortedSet` against the hash-trie
`Set` on random operation sequences.

### Cardinality

`card(s)` is the number of elements of a set, predicate-only like the rest of
the vocabulary. It has no quantified axiom. Instead, a query that mentions
`card` gets facts about every set term it contains, each a theorem of finite
sets: a count is non-negative, `empty` has 0 elements and `singleton(x)` has
1, adding or removing one element changes the count by at most one depending
on membership, a union is no smaller than either side and no larger than
both together, a subset is no larger than its superset, a set with a member
is non-empty, and a list's element set is no larger than the list. Equal sets
have equal counts automatically.

`Set.size` and `Map.size` carry assumed contracts, `{Int | _ == card(elts(s))}`
and `{Int | _ == card(keys(m))}`, with runtime witnesses in the stdlib tests:

```march
fn need1(n : {Int | _ == 1}) : Int do 0 end
fn need2(n : {Int | _ == 2}) : Int do 0 end
fn one(x : Int) : Int do need1(Set.size(Set.insert(Set.empty(), x, lt))) end      -- proved
fn two(x : Int) : Int do need2(Set.size(Set.insert(Set.empty(), x, lt))) end      -- violation

fn need_same(a : Int, b : {Int | _ == a}) : Int do 0 end
fn present(s : Set(Int), x : Int) : Int do
  if Set.contains(s, x, lt) do need_same(Set.size(s), Set.size(Set.insert(s, x, lt))) else 0 end
end                                                                               -- proved
```

### Set-valued measures

A user `@[measure]` may return a set, under the same structural gate as an
`Int` measure. Its body uses the set vocabulary, which is bound for that body
only; such a measure is logic, and calling it in expression position is an
error:

```march
type Expr = Var(Int) | Lam(Int, Expr) | App(Expr, Expr)

@[measure]
fn free_vars(e : Expr) : Set(Int) do
  match e do
    Var(x)    -> singleton(x)
    Lam(x, b) -> diff(free_vars(b), singleton(x))
    App(f, a) -> union(free_vars(f), free_vars(a))
  end
end

fn closed(e : {Expr | free_vars(_) == empty}) : Int do 0 end
fn ok() : Int do closed(Lam(1, Var(1))) end          -- proved
fn bad() : Int do closed(Lam(1, Var(2))) end         -- violation
fn need_sub(f : Expr, a : Expr,
            e : {Expr | subset(free_vars(_), union(free_vars(f), free_vars(a)))}) : Int do 0 end
fn sym(f : Expr, a : Expr) : Int do need_sub(f, a, App(f, a)) end   -- proved by the axioms alone
```

`Int` and `Bool` payloads are concrete, including the payload of a parametric
type at a concrete instance: a measure declared over `Tree(Int)` or
`Expr(Int)` reads its `Int` payloads, and a measure declared over `Tree(a)`
applies at `Tree(Int)` too.

```march
type Tree(a) = Leaf | Node(Tree(a), a, Tree(a))

@[measure]
fn sum(t : Tree(Int)) : Int do
  match t do
    Leaf -> 0
    Node(l, x, r) -> sum(l) + x + sum(r)
  end
end

fn need_pos(t : {Tree(Int) | sum(_) > 0}) : Int do 0 end
fn ok() : Int do need_pos(Node(Leaf, 5, Leaf)) end    -- proved
fn bad() : Int do need_pos(Node(Leaf, 0, Leaf)) end   -- violation
```

A `String` or type-variable payload is opaque, so a set measure over strings
reasons symbolically but not about particular literals. A refuted set contract
renders its model as a set literal: `Set.insert() can return {4}`,
`elts(s) = {1}`.

### What sets do not do

- **Cardinality knows only what the query's own set terms imply.** `card` has
  no general axiom; each query gets the finite-set facts about the set terms
  it contains (see "Cardinality" above). A property that needs a quantifier,
  such as "this list has no duplicates" (`card(elts(xs)) == len(xs)` after
  `List.dedup`), is not provable, and a permutation contract still writes
  both halves: `{List(Int) | elts(_) == elts(xs) && len(_) == len(xs)}`.
- **List structure is followed only inside a proof by recursion.** A
  contract on a function that recurses over a list (see "Proved list
  contracts" above) is proved through its `Cons` cells. Everywhere else `elts`
  folds a list built from constructors whose tail is a literal or a name
  (`Cons(h, acc)`) and otherwise stands for one opaque set per variable.
- **Mixed element types are an error only when both are declared.**
  `member(3, elts(_))` against a `List(String)` is reported at the predicate
  (see above). A clash the declared types cannot show, such as an unannotated
  operand or a type variable instantiated differently at a call, is a sort
  conflict and is skipped, never reported. A clash that only a *fact* brings in
  (a guard, a parameter's promise) drops that fact instead, so the call is
  still checked without it.
- **The vocabulary names are reserved in predicates, and only there.** Inside
  `{...}`, `elts`, `keys`, `member`, `union`, `inter`, `diff`, `subset`,
  `singleton` and `empty` always mean the set operations; a `@[measure]` may
  not take one of those names, and a predicate that applies one in a non-set
  shape (`member(xs, 3)`) draws the unrecognised-predicate warning. In
  ordinary code, including an `if` guard, they are just names: a module's own
  `fn keys(r)` or `fn member(xs, x)` is treated like any other function.
- **A rebound name loses its set promise**, exactly as it loses a `len` one.

---

## Bool Refinements

A `Bool` parameter or return can carry a predicate over the ordinary boolean
operators (`==`, `!=`, `&&`, `||`, `not`) against the literals `true` and
`false`:

```march
fn commit(confirmed : {Bool | _ == true}) : Int do ... end

fn main() do
  commit(false)   -- rejected: `_ == true` can never hold at `false`
  commit(true)    -- fine
end
```

The predicate must use an **operator form**. The bare-binder spelling
`{Bool | not _}` does not parse; write `{Bool | _ == false}`.

A `Bool` postcondition propagates to call sites under the same rule as every
other postcondition, only if the definition side **proved** it:

```march
fn always_false() : {Bool | _ == false} do false end
fn v() : Int do commit(always_false()) end   -- rejected
```

An unknown `Bool` (a parameter, a value the checker cannot settle) is
**skipped**, and a guard establishes the fact you would expect:
`if k do commit(k) else 0 end` passes.

---

## Float Refinements

A `Float` parameter or return can carry a **comparison** predicate (`>=`, `>`,
`<=`, `<`, `==`, `!=`) against float literals or another float value:

```march
fn sqrtish(x : {Float | _ >= 0.0}) : Float do ... end
fn ratio(n : Float, d : {Float | _ != 0.0}) : Float do n /. d end

fn main() do
  sqrtish(0.0 -. 1.0)   -- rejected: -1.0 is not >= 0.0
  sqrtish(4.0)          -- fine
  ratio(1.0, 0.0)       -- rejected: the divisor contract can never hold at 0.0
end
```

March spells float comparison with the *ordinary* operators, the same ones
integers use; which meaning applies is decided by the **declared** base type of
the refinement, never guessed. `0.0 -. 1.0` and friends are constant-folded, so
the negative literal March has no direct spelling for is still recognised.

### Why the FloatingPoint theory, and not reals

The predicates are discharged through Z3's **bit-precise IEEE-754
FloatingPoint** theory: the sort is `Float64`, comparisons are `fp.geq` /
`fp.gt` / `fp.leq` / `fp.lt`, equality is `fp.eq`, and a literal is
`((_ to_fp 11 53) RNE 1.0)`.

Modelling floats as mathematical **reals** would be unsound *in the
false-positive direction*: the one failure this checker must never have.
Consider

```
not (x >= 0.0) && not (x <= 0.0)
```

Over reals, trichotomy makes this **unsatisfiable**. The checker reports a
violation exactly when it proves a predicate can never hold, so a reals encoding
would flag this perfectly ordinary contract on *any* argument. Over floats it is
**satisfiable**, witnessed by `NaN`, which compares false against everything;
so the checker correctly stays silent. Do not "simplify" the encoding to `Real`.

`==` is `fp.eq`, **not** SMT-LIB `=`. `=` on `Float64` is *bitwise* identity,
under which `-0.0` differs from `0.0`; `{Float | _ != 0.0}` would then accept a
negative zero, which is just as bad a divisor as a positive one. Under `fp.eq`,
`-0.0 == 0.0` is true (so a negative-zero argument **is** reported) and `NaN`
equals no value, itself included.

### What Float refinements do *not* do

- **Arithmetic in a predicate is skipped, not guessed.** `{Float | _ +. 1.0 >
  0.0}` mentions the binder under `+.`, which would need Z3's rounding-mode
  surface to model. The whole predicate becomes unreflectable and the obligation
  is silently skipped, including for an argument that clearly violates it.
  Arithmetic over float **literals only** (`0.0 -. 1.0`) is different: it is
  folded to a constant before reflection and is fully checked.
- **Float record fields and ADT payloads are opaque.** A `Float` *parameter* or
  *return* is modelled; a `Float` inside a record or constructor is not.
- **No special values.** There is no `is_nan` or `is_finite` vocabulary, so a
  predicate cannot mention them. NaN is nevertheless modelled correctly inside
  the solver, which is what keeps the encoding from reporting correct code.
- **A literal with no exact plain-decimal form is skipped.** SMT-LIB decimals
  admit neither exponent notation nor infinities, so a magnitude that cannot be
  written out exactly is not reflected at all.

---

## Constructor Tags: Refining over ADT Variants

Every constructor of every ADT (your own types, and the built-in `Option`,
`Result` and `List`) implicitly gains an `is_<Ctor>` **tester** the checker
understands inside a predicate. No declaration is needed; `type Shape = Circle(Int)
| Square(Int)` gives you `is_Circle` and `is_Square` for free.

```march
-- a contract that says "this Option is definitely populated"
fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do ... end

unwrap(Some(1))   -- fine
unwrap(None)      -- error: `None` can never satisfy `is_Some(_)`
```

This is what backs the standard library's `Option.unwrap`/`expect` and
`Result.unwrap`/`unwrap_err`/`expect` (`stdlib/option.march`,
`stdlib/result.march`), so `Option.unwrap(None)` and
`Result.unwrap(Err("boom"))` are compile errors rather than runtime panics.

The name is **exact-case**: `is_Some` is the tester for the constructor `Some`;
`is_some` is not a tester at all (it happens to be the lowercase stdlib helper
`Option.is_some`), so a misspelling draws the unrecognized-predicate warning
rather than silently meaning something else:

```
`is_some` is not a measure or known predicate, so this refinement is not
checked. Annotate the function `@[measure]`, or use a supported predicate.
```

There are two sources of tag facts.

**A constructor literal at the call site**, as above: the argument's tag is
known exactly, so the tester determines the answer.

**A `match` arm**, which is where the realistic bug lives. Entering an arm
narrows the scrutinee's tag for everything inside it:

```march
fn f(x : Option(Int)) : Int do
  match x do
    None    -> unwrap(x)   -- error: inside this arm, `x` is definitely `None`
    Some(v) -> unwrap(x)   -- fine: inside this arm, `x` is definitely `Some`
  end
end
```

Later arms also learn what the earlier ones ruled out. Reaching an arm means
every arm above it failed to match, so for each of those with a failure decided
purely by the tag, the scrutinee is known *not* to carry it:

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
safe-wrapper idiom check out; before 2026-08-03 it could not, and every such
function was left with permanently unprovable debt.

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

The same idea generalizes to a user `@[measure]`, not just the built-in `len`.
An excluded constructor's tester over the scrutinee (a free variable) does not
by itself reach a quantified recursion-equation axiom: those trigger only on
a *constructed* term (`size(Cons(h, t))`), never on `((_ is Nil) xs)`. So
`build_measure_preamble` also emits a base-case linking axiom for every
constructor with an arm body that is a literal, tying the tester directly to the
measure's value: `(_ is Nil) x => size(x) = 0`. A nullary base case needs no
axiom of its own (it is already a ground fact); this covers a base case where the
constructor takes fields but the body is still a plain literal, e.g.
`Cons(_, _) -> 0`.

Narrowing is intentionally conservative, and where it stops is where the checker
goes quiet rather than guessing:

- **The scrutinee must be a bare variable.** `match mk() do …` matches an
  expression with no stable name to attach a fact to, so no narrowing happens
  and calls inside the arms are skipped. Bind it to a `let` first if you want
  the fact.
- **A rebinding pattern binder ends it.** Matching `y` with `Some(x) ->` states
  no fact about `x` (that `x` is a fresh binder for the payload, not the
  scrutinee), so no fact is recorded against the name it shadows.
- **An `as` pattern is not narrowed.** `None as z ->` binds the whole scrutinee
  under a second name, but the arm's head is a `PatAs`, not a bare constructor
  pattern, so no tag fact is recorded, for `z` or for the scrutinee. Write
  `None ->` if you want the narrowing.
- **An ambiguous constructor name is skipped.** If two ADTs in scope both
  declare a constructor `Row`, `is_Row` identifies no particular datatype and is
  not checked.
- **Rebinding the name retires the fact.** A narrowing is recorded against a
  *name*, so any construct that rebinds that name inside the arm (a `let`, a
  `let?`, a lambda parameter, an inner `match` binder) discards it. In

  ```march
  match x do
    None ->
      let x = Some(1)
      unwrap(x)     -- fine: this `x` is a different value
    Some(v) -> v
  end
  ```

  the fact `is_None(x)` does not survive the `let`. The same rule applies to
  scalar facts from an `if` guard.

As everywhere else, these are checked under the definite-failure stance: an
`Option` with a tag that isn't known is simply not an error.

---

## Element Refinements: Refining What a Container Holds

A refinement may sit inside a type argument, where it constrains every element
the container holds:

```march
fn sum_pos(xs : List({Int | _ > 0})) : Int do
  match xs do
    Nil -> 0
    Cons(h, t) -> need_pos(h) + sum_pos(t)   -- h is known > 0; t is still List({Int | _ > 0})
  end
end

sum_pos([1, 2, 3])     -- proved
sum_pos([1, -2, 3])    -- refinement violation, pointing at -2
```

This works for `List`, `Option`, `Result`, and every user variant type
(`Tree({Int | _ > 0})`), and nests one level deeper (`List(List({Int | p}))`).

**Where a container value owes the element obligation:** at a call argument, a
function's return (every tail, with the facts of the block's `let`s in scope),
an annotated `let`, and a record field. A literal is checked element by
element. A value whose element refinement is known must *imply* the expected one
(`List({Int | _ > 1})` passes where `List({Int | _ > 0})` is expected; the
reverse is reported with a witness element). A value's element refinement is
known when it is:

- a parameter, or a proved annotated `let`;
- a call to a function whose declared container return
  (`: List({Int | _ > 0})`) was **proved** at its definition (every tail);
- a call through a callback parameter typed `… -> List({Int | p})`, which every
  caller was obliged to meet;
- a call to a polymorphic function, as described next.

Anything else is a recorded skip. Every element a `match` takes out of such a
value carries the fact, whether the scrutinee is a variable or a call
(`match List.head_opt(xs) do Some(h) -> …`).

**An element refinement that names a parameter** means that parameter, at the
call. `fn need_lt(xs : List({Int | _ < n}), n : Int)` called as
`need_lt(ys, 10)` demands `_ < 10` of every element of `ys`, whatever the
caller happens to call `n`; a demand naming a parameter the call does not
supply is a recorded skip. Inside a function, such a fact is about the
binding it names: after `let n = 0`, `xs`'s elements are no longer known to be
`< n`, and a return tail under a binding that rebinds `n` is a recorded skip
rather than checked against the local. A lambda whose parameter is spelled like
a name the demand mentions is not read as that name. On a record field
(`xs : List({Int | _ < n})` naming the sibling field `n`) or on an expected
function codomain, such a refinement is a recorded skip, never checked.

The same holds for a **return**. A call to a function whose container return
names a parameter and was proved at its definition carries that return at the
call's own arguments:

```march
fn below(n : Int) : List({Int | _ < n}) do [n - 1, n - 2] end

fn t(k : {Int | _ <= 10}) : Int do
  sum_small(below(10)) + sum_small(below(k))   -- both proved (_ < 10)
end
sum_lt5(below(10))                              -- violated: _ < 10 does not imply _ < 5
```

Only an argument that is a variable, a literal, or `+`/`-`/literal-`*`
arithmetic over them is substituted. `below(f(x))` carries nothing. A
`let`-bound result (`let ys = below(k)`) keeps the fact until a name it
mentions is rebound. A recursive call to the function being checked carries the
return at its own arguments, so `clamp(t, n)` inside
`fn clamp(xs, n) : List({Int | _ <= n})` is `_ <= n`. A tuple component works
the same way, and so does a block-level `fn` whose return names only its own
parameters. A function passed as a value carries nothing, because there are no
arguments to substitute.

When such a return fails to imply what a call demands, the result is a
violation only if every caller variable it or the demand mentions is
constrained by a refinement or a guard (`k` above), and the checker can read
every condition on the way to the call. Under a guard it cannot translate
(`if small(k)`), a pattern it does not record (`Some(3) ->`), a `match` arm
after one whose failure it does not record, or a later arm of a `match do`
cond, the call is a recorded skip instead. An `Int` literal arm (`3 ->`) is
recorded: inside it the scrutinee is `3`, and after an unguarded one it is
not. A `Bool` local bound to a comparison or connective (`let ok = k < 5`) is
read as that comparison in a guard, until `ok` or a name it mentions is
rebound. Any other local the guard or the demand mentions (`let ok =
small(k)`, a value destructured from a computed local, a lambda's parameter)
makes the call a skip rather than a violation. If no fact constrains the
variable (`sum_small(below(n))` with `n : Int`), the call is a recorded skip,
unless no value of it could work (`need_ge(below(n), n)` against
`List({Int | _ >= n})` is violated for every `n`). A pattern binder spelled
like a name the slot mentions (`Cons(n, _)` over `List({Int | _ < n})`) gets no
fact from it.

### Relational element refinements

An element refinement says something about each element on its own:

```march
List({Int | _ > 0})   -- every element is positive
```

Some facts are about two values at once. Take a list of key/value pairs where
every value must be bigger than its key. No refinement on the keys alone, or
on the values alone, can say that. It is a fact about the key and the value of
the same pair.

The running example in this section is an association list:

```march
type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))
```

To state the fact, give each slot a name and let one slot's predicate mention
the other's name:

```march
Assoc({x : Int | true}, {y : Int | y > x})   -- every value is bigger than its key
```

Here `x` names the key and `y` names the value. `true` means the key on its own
is unconstrained. `y > x` is the relation.

**An entry** is the values one constructor holds for the related slots: the
`k` and `v` fields of one `ACons`. The relation must hold of every entry.

```
ACons(1, 5, ACons(2, 9, ANil))
      ^  ^        ^  ^
      entry (1, 5)   entry (2, 9)
```

Both entries have a value bigger than its key, so this value satisfies the
relation. `ANil` holds no key and no value. It is no entry, so it owes nothing.

The checker uses a relation in three ways.

**Building a value owes the relation, once per entry.** Each `ACons` you write
is checked over its own two fields:

```march
mod Build do
  type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

  fn need_up(_a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do 0 end

  fn ok() : Int do need_up(ACons(1, 5, ACons(2, 9, ANil))) end    -- proved
  fn bad() : Int do need_up(ACons(1, 5, ACons(7, 3, ANil))) end   -- violation
end
```

The violation names the entry that breaks it:

```
refinement violation: the entry (7, 3) passed to `need_up` does not satisfy precondition `y > x`
```

**Matching an entry gives you the relation.** If you bind the key and the value
from the same constructor pattern, the checker knows they are related:

```march
mod Match do
  type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

  fn need_gt(k : Int, v : {Int | _ > k}) : Int do v - k end

  fn first_gap(a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do
    match a do
      ANil -> 0
      ACons(k, v, _) -> need_gt(k, v)                 -- proved
    end
  end

  fn mixed(a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do
    match a do
      ACons(k, _, ACons(_, v, _)) -> need_gt(k, v)    -- skip: no fact the checker derived constrains `v`
      _ -> 0
    end
  end
end
```

In `mixed`, `k` is the first entry's key and `v` is the second entry's value.
They are not one entry, so nothing relates them. Both names must be pattern
variables of the same constructor.

**Passing to a weaker demand works when the relation implies it.** A function
may ask for less than a value promises. Then the checker asks whether every
entry that keeps the promise also meets the demand. This is called projection.

```march
mod Project do
  type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

  fn need_pos_vals(_a : Assoc(Int, {Int | _ > 0})) : Int do 0 end

  fn pos_up(a : Assoc({x : Int | x > 0}, {y : Int | y > x})) : Int do
    need_pos_vals(a)   -- proved
  end

  fn up(a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do
    need_pos_vals(a)   -- violation (e.g. x = -1, y = 0)
  end
end
```

`need_pos_vals` asks only that every value be positive. In `pos_up`, every key
is positive and every value is bigger than its key. So every value is
positive, and the call is proved. In `up`, keys may be negative. The entry
`(-1, 0)` has a value bigger than its key, but the value is not positive. The
checker reports that entry:

```
refinement violation: an element of the container passed as `a` does not satisfy the expected element refinement `_ > 0` (e.g. x = -1, y = 0)
```

**The names are local to each type.** A demand may spell the same relation with
other names. Only the meaning is compared:

```march
mod Rename do
  type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

  fn need_up(_a : Assoc({a : Int | true}, {b : Int | b > a})) : Int do 0 end

  fn renamed(a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do
    need_up(a)   -- proved: `b > a` is `y > x`
  end
end
```

A relation also travels the way any element refinement does. A proved
annotated `let` carries it. So do a proved declared return and the recursive
call of the function being checked:

```march
mod Bump do
  type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

  fn need_up(_a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do 0 end

  fn bump(a : Assoc({x : Int | true}, {y : Int | y > x})) : Assoc({x : Int | true}, {y : Int | y > x}) do
    match a do
      ANil -> ANil
      ACons(k, v, t) -> ACons(k, v + 1, bump(t))   -- proved: the recursive call keeps it
    end
  end

  fn use_bump(a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do
    need_up(bump(a))                               -- proved
  end
end
```

**Details.**

- A slot can mention the names of all its siblings, in any order.
- If a parameter has the same name as a slot's name, the slot's name wins
  inside the type:

  ```march
  fn f(x : Int, a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do … end
  -- inside the type, `x` in `y > x` is the key, not the parameter `x`
  ```

- A slot predicate is split at its top-level `&&`. A part that mentions no
  sibling stays an ordinary fact about that slot. So a predicate over one slot
  is always an ordinary element refinement:

  ```march
  {y : Int | y > 0 && y > x}   -- `y > 0` is a fact about each value; `y > x` is the relation
  ```

- Two slots may mention each other. Each slot's predicate is then one
  relation:

  ```march
  Assoc({x : Int | x < y}, {y : Int | y > x})
  ```

- A constructor whose only field is another container passes the relation on
  to that container, when the inner container holds all the related slots:

  ```march
  type Outer(k, v) = O(Assoc(k, v))   -- a relation on Outer is checked on the inner Assoc's entries
  ```

- You cannot write a relation over type-variable slots.
- You cannot write a relation between two different entries, such as "the keys
  are sorted".

**What is not checked.**

- **A relation is lost when the value goes through a generic function.**
  Calling `need_up` on the result of `shift(a)` is a skip, even when `a`
  carries the relation. A function generic in `k` and `v` keeps each slot's
  own facts. But it may pair the key of one entry with the value of another.
  This `shift` does exactly that:

  ```march
  mod Shift do
    type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

    fn need_up(_a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do 0 end

    fn shift(a : Assoc(k, v)) : Assoc(k, v) do
      match a do
        ACons(k1, _, ACons(_, v2, rest)) -> ACons(k1, v2, rest)
        _ -> a
      end
    end

    fn t() : Int do need_up(shift(ACons(5, 6, ACons(0, 1, ANil)))) end   -- skip
  end
  ```

  The input's entries `(5, 6)` and `(0, 1)` both have a value bigger than its
  key. The result has the single entry `(5, 1)`, which does not. So the call
  is a `parametric-source-unproved` skip, with this message:

  ```
  a relation between `k` and `v` is not preserved through `shift`: a function parametric in them may pair the components of different entries
  ```

  A generic reverse is treated the same way. To carry a relation through a
  combinator, give the combinator a
  [two-argument abstract refinement](#two-arguments-a-relation-between-sibling-slots).

- **A relation on a type that is not entry-shaped is ignored, with a
  warning.** Every constructor must hold one value for each related slot, or
  none of them. This type breaks that rule:

  ```march
  mod Shape do
    type Two(k, v) = K(k) | V(v)

    fn need_two(_t : Two({x : Int | true}, {y : Int | y > x})) : Int do 0 end   -- warning: refinement_unchecked

    fn go() : Int do need_two(V(0 - 5)) end   -- no obligation
  end
  ```

  `V(-5)` holds a value and no key. It sits in no entry, so the value has no
  key to be compared with. The relation is therefore treated as not written.
  It is never assumed and never owed. The checker warns:

  ```
  This relation is not checked: `Two`'s constructor `K` carries a value for `x` without one for `y`, so a relation between them has no entries to hold of
  ```

  The same warning covers these shapes:

  - a slot whose type is itself a container;
  - a slot inside a nested container that mentions an outer slot's name;
  - a constructor that holds some related values directly and others inside a
    nested container;
  - a constructor that holds them inside another type, where they are not one
    entry.

  ```march
  {xs : List(Int) | true}                            -- a slot whose type is a container
  Assoc({x : Int | true}, List({y : Int | y > x}))   -- a nested slot names the outer `x`
  type Mix(k, v) = MX(k, List(v))                    -- `k` direct, `v` inside a List
  type Pairs(k, v) = Pairs((List(k), List(v)))       -- inside a tuple of lists: no entry
  ```

  One type application of both slots does count as entry-shaped. `Map` is
  fine, because it holds its keys and values in one `HEntry(k, v)`.

### Through a polymorphic call

A function that is generic in its element type cannot invent an element, so its
result keeps its argument's element refinement:

```march
fn t(xs : List({Int | _ > 0})) : Int do
  sum_pos(List.drop(List.take(xs, 2), 1))   -- proved, by parametricity
end
```

The checker reads where a value of the element type can **enter** the callee
(its *sources*): an element of a container argument, the argument itself, or the
result of a function argument. Here every source is an element of `xs`. When
sources disagree, the result carries nothing:
`List.append(pos, neg)` holds elements from both lists. A type variable that only
appears in a function argument's *parameters* (`sort_by`'s `cmp : a -> a -> Bool`)
is handed out, not received, so it is not a source.

The rule reads the callee's declared signature, so the checker first confirms
that the signature tells the truth about the callee:

- **The type variable must really be generic.** A type variable in a March
  signature is not rigid: `fn bad(xs : List(a)) : List(a) do [0 - 5] end`
  typechecks, with `a` fixed to `Int` by the body. The checker reads the
  *inferred* parameter types. A variable the body fixed, merged with
  another, or let in through an unannotated parameter carries nothing.
- **The body must not be able to create one.** A function that reaches a builtin
  returning a type variable it was not given (a decoder such as `from_json`, a
  typed global lookup, an actor call), an FFI extern, or an interface method
  whose result mentions a type variable, directly or through another function,
  carries nothing. The builtin classification is computed from the
  typechecker's own builtin table. An interface method counts even when its
  result is one of its arguments' types (`fn norm : t -> t`) and even when the
  module has a single `impl` of it: that `impl` is written at one type and may
  return any value of it.
- **A callee with a bound on the variable carries nothing.**

When any of these fails, the call's element obligation is a recorded skip:
silent by default, an error under `cap verified`.

### `map`, `flat_map` and friends: meeting a demand

A call whose result carries no element refinement of its own can still meet the
one its position *demands*. The checker matches the callee's return type
against the demand, then requires every source of the demanded type variable to
meet it:

```march
fn a(ys : List(Int)) : Int do
  sum_pos(List.map(ys, fn y -> if y > 0 do y else 1 end))   -- proved: every tail of the lambda is > 0
end

fn b(pos : List({Int | _ > 0})) : Int do
  sum_pos(List.map(pos, fn y -> y + 1))   -- proved: y comes from pos, so y > 0
end

fn c(ys : List(Int)) : Int do
  sum_pos(List.flat_map(ys, fn y -> [1, 2]))   -- proved
end
```

As `b` shows, a one-parameter lambda passed where the callee's function
argument takes the element type receives its source's element refinement as a
fact, both for this check and for every obligation inside the lambda body.

A *named* function passed there contributes its declared return refinement,
but only when each of its own refined parameters is met by what the callee
hands it at that position: the element refinement of the source there, or (for
a fold's accumulator) the demand itself, see
[Folds](#folds-an-accumulator-invariant). With
`fn dbl(x : {Int | _ > 0}) : {Int | _ > 0}`, `sum_pos(List.map(pos, dbl))`
proves and `sum_pos(List.map(ys, dbl))` over an unrefined `ys` is a skip naming
`dbl`'s unmet precondition.

A lambda with several parameters gets the same fact position by position: each
parameter assumes the element refinement of the type variable at its place in
the callee's function type, when every source of that variable is an element.

```march
fn need_pos(k : {Int | _ > 0}) : Int do k end

fn d(xs : List({Int | _ > 0}), ys : List({Int | _ > 0})) : Int do
  sum_pos(List.zip_with(xs, ys, fn (x, y) -> x + y))       -- proved: x from xs, y from ys
end

fn e(xs : List({Int | _ > 0})) : Int do
  List.fold_left(xs, 0, fn (acc, x) -> acc + need_pos(x))  -- proved: x comes from xs
end

fn s(xs : List({Int | _ > 0})) : List({Int | _ > 0}) do
  List.sort_by(xs, fn (a, b) -> need_pos(a) < need_pos(b)) -- proved: a -> a -> Bool, both from xs
end
```

`fold_left`'s accumulator gets no *domain* fact: its type variable also enters
through the bare initial value and the callback's own result, so
`fn (acc, x) -> need_pos(acc) + x` is a skip. (A demand on the fold's *result*
is different: the accumulator may then assume it, see
[Folds](#folds-an-accumulator-invariant).) A lambda in which any parameter
carries a refinement annotation of its own receives no fact at all (an
[annotated accumulator](#an-annotated-accumulator) whose annotation was proved
aside: its siblings keep theirs), a fact
that names one of the lambda's own parameters is not given to any of them,
and a lambda with fewer parameters than the function type takes arguments (other
than a one-parameter lambda) gets nothing.

A source that does not meet the demand gives a **skip**, never a violation, with
the reason `parametric-source-unproved`. `sum_pos(List.map(ys, fn y -> 0))` is
fine when `ys` is empty, and whether it is empty is the caller's data. Under
`cap verified` the skip is an error, as always.

The same rule applies when the callee returns a single value of the type
variable rather than a container of them, and the demand is a scalar
refinement: a precondition, an annotated `let`, an element of a literal, or a
function's declared return.

```march
fn f(o : Option({Int | _ > 0}), xs : {List({Int | _ > 0}) | len(_) > 0}) : Int do
  need_pos(Option.unwrap_or(o, 1))                         -- proved: an element of o, or 1
  need_pos(Option.unwrap_or_else(o, fn () -> 1))           -- proved
  need_pos(List.fold_left(xs, 1, fn (acc, x) -> x))        -- proved: x comes from xs
  need_pos(List.head(xs) + 1)                              -- proved: List.head(xs) > 0
  need_pos(Option.unwrap_or(o, 0))                         -- skip: the default can fail it
end

fn g(o : Option({Int | _ > 0})) : {Int | _ > 0} do
  Option.unwrap_or(o, 1)                                   -- proved
end
```

An element demand on such a call works the same way: when the value the call
returns is itself a container (`b` instantiated to `List(Int)` at the call),
the whole demand is `b`'s, and each source must meet it as a container. With
`fn pick(c : Bool, x : b, y : b) : b`, `sum_pos(pick(c, pos, [3]))` is proved
and `sum_pos(pick(c, pos, zs))` with `zs : List(Int)` is a skip. A fold's
list-building accumulator is the case that matters; see
[Folds](#folds-an-accumulator-invariant).

### Callbacks and user-written combinators

A callback's refined codomain is a fact wherever its result lands, including in
an element position, and a structurally recursive self-call carries the
function's own element return (the same induction rule as
[Tier 2](#limitations)). Together these prove a hand-written refined `map`:

```march
fn map_pos(xs : List(Int), g : (Int) -> {Int | _ > 0}) : List({Int | _ > 0}) do
  match xs do
    Nil -> Nil
    Cons(h, t) -> Cons(g(h), map_pos(t, g))   -- proved
  end
end
```

The contract is enforced where the callback is passed. A lambda whose return
can break a declared codomain refinement is reported with a witness input,
exactly like a named function:

```march
map_pos(ys, fn y -> y - 1)    -- error: the lambda returns 0 for y = 1
```

A lambda that names a local variable of its enclosing function cannot be run on
its own, so for it the check stays a skip.

A callback type's codomain may name the domain's argument:
`keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}`. Inside the higher-order
function, a guard `if keep(h)` then establishes `h > 0` (and its `else` branch
`h <= 0`), and `let b = keep(h)` binds `b == (h > 0)`. Where a callable is
passed, it is checked under its own parameter name: `fn y -> y > 0` and a
named `is_pos(n : Int) : {Bool | _ == (n > 0)}` both satisfy that codomain,
and `fn y -> y >= 0` or `is_nonneg(n) : {Bool | _ == (n >= 0)}` do not.

A codomain that applies one of the function's *abstract refinements*
(`keep : ({x : a | true}) -> {Bool | _ == p(x)}`, with `p` also in the
signature) does not constrain what may be passed for it: `p` stands for
whatever that callable returns, so any callable satisfies it and the pass site
records no obligation.

### Abstract refinements: `filter` keeps what its predicate says

`List.filter` returns the elements its predicate accepted, and its signature
says so:

```march
fn filter(xs : List(a), pred : a -> Bool[p]) : {List(a[p]) | subset(elts(_), elts(xs))}
```

`p` is an *abstract refinement*. The signature uses it twice:

```march
pred : a -> Bool[p]   -- defines p: whatever pred returns for an element
List(a[p])            -- every element of the result satisfies p
```

At each call, `p` stands for whatever the passed predicate computes. The
shorthand means exactly this spelled-out form, which is also accepted:

```march
fn filter(xs : List(a), pred : ({x : a | true}) -> {Bool | _ == p(x)})
    : {List({a | p(_)}) | subset(elts(_), elts(xs))}
```

The shorthand has three forms:

```march
T[p]                -- means {T | p(_)}, e.g. List(a[p]), Option(a[p]), List(Bool[p])
D -> Bool[p]        -- the definer: means ({x : D | true}) -> {Bool | _ == p(x)}
k -> v -> Bool[p]   -- a definer of a two-argument p
```

A few rules about the definer:

- If the callback's domain already names its argument, the definer keeps that
  name.
- If the domain is refined over `_`, it must name its argument instead.
- Breaking either rule is a parse error that says so.
- A curried callback of two arguments defines a `p` of two arguments. It
  relates two sibling slots; see [Two arguments](#two-arguments-a-relation-between-sibling-slots).
- A tuple domain is one argument, a tuple. So it defines nothing over the
  tuple's parts. Writing one is a parse error, and the message writes the
  curried chain for you.

```march
({v : Int | v > 0}) -> Bool[p]   -- keeps the name `v`
(a, a) -> Bool[p]                -- parse error: one tuple argument
```

Here is `List.filter` at work, with this demand:

```march
fn sum_pos(xs : List({Int | _ > 0})) : Int do … end

sum_pos(List.filter(ys, fn y -> y > 0))     -- proved
let zs = List.filter(ys, fn y -> y > 0)
sum_pos(zs)                                 -- proved
sum_pos(List.filter(pos, fn y -> y < 100))  -- proved when pos : List({Int | _ > 0}):
                                            --   the input's own fact carries over
sum_pos(List.filter(ys, fn y -> y >= 0))    -- skip: abstract-refinement-too-weak
```

At the call, the checker puts the lambda's body in place of `p`. Then it
decides one question for an arbitrary element: does the body imply the
demand?

A predicate too weak for the demand is a skip, never a violation. Filtering an
empty list is fine whatever the predicate. So a too-weak predicate is an error
only under `cap verified`. The reason is `abstract-refinement-too-weak`, and
the message names the lambda and the demand.

Inside `filter` itself, `p` is an uninterpreted function. The body proves its
own return from its guard on `pred(h)` and from the callback's contract. So the
fact is proved, not assumed.

**Your own functions can declare one.** Give a callback parameter a type
ending in `Bool[p]`, and put `a[p]` in an element slot of the return:

```march
fn keep_if(xs : List(a), pred : a -> Bool[p]) : List(a[p]) do … end
```

The body must prove that return like any other element contract. A body that
does not prove it lends nothing at its calls. One that returns its input
unfiltered is an example.

Passing any callable for the defining parameter is always allowed. `p` is, by
definition, what that callable returns. So the pass site owes no codomain
obligation.

**`p` can also sit on a parameter.** Then it is an obligation on the caller,
checked as if the parameter's elements carried the passed predicate:

```march
fn need(xs : List(a[p]), keep : a -> Bool[p]) : Int do … end

need(pos, fn y -> y > 0)      -- proved, when pos : List({Int | _ > 0})
need([1, 2], fn y -> y > 0)   -- proved
need([0, 1], fn y -> y > 0)   -- violation
need(ys, fn y -> y > 0)       -- skip, when ys : List(Int)
```

Inside `need`, the elements of `xs` carry `p`.

**Negation and combined slots.** An element slot may combine `p(_)` with `&&`,
`||` and `!` or `not`. It may also use the ordinary vocabulary over the
element. Spell the negation with `!`, or with `not` and parentheses. `not` is a
function, so it needs the parentheses:

```march
{a | !p(_)}       -- ok
{a | not(p(_))}   -- ok
{a | not p(_)}    -- syntax error
```

At a call, the checker reads the slot with `p` replaced by the passed
predicate:

```march
fn rej(xs : List(a), pred : a -> Bool[p]) : List({a | !p(_)}) do
  match xs do
  Nil -> Nil
  Cons(h, t) -> if pred(h) do rej(t, pred) else Cons(h, rej(t, pred)) end
  end
end

fn sum_nonpos(xs : List({Int | _ <= 0})) : Int do … end
sum_nonpos(rej(ys, fn y -> y > 0))     -- proved: `!(y > 0)`
sum_nonpos(rej(ys, fn y -> y > 5))     -- skip: `!(y > 5)` is too weak
```

A slot may also sit at a concrete base type, as in `Range`'s helper:

```march
pfn filter_list(xs : List(Int), f : Int -> Bool[p]) : List(Int[p]) do … end
```

**Helpers inside a definition.** An accumulator helper may take a parameter
whose elements carry `p`. It is checked like any other parameter:

- If you push an element on the branch where `pred` rejected it, that is a
  violation.
- If you push it without testing `pred`, that is a skip.

```march
acc : List(a[p])   -- the helper's accumulator parameter
Cons(h, acc)       -- pushed where pred(h) was false: violation
```

A recursive helper's element return is proved by induction only when every
element precondition of its recursive call is proved. A skip or a violation
there leaves the return unproved. Then the helper lends nothing to its
callers. This holds for a concrete slot too, such as an accumulator of
positive `Int`s.

The recursive call must also pass the function's own callback, unchanged, for
each abstract refinement:

```march
filt(t, pred)           -- covered
filt(t, fn y -> true)   -- not covered
let q = pred            -- an alias: not covered
```

Two callbacks passed in swapped order, or a rebound `pred`, are not covered
either. A definition may pass its own callback on to another combinator, for
example to `List.filter` inside a `myfilter` with the same signature.

**Shapes that are not read.** If `p` is applied under anything but `&&`, `||`
and `!`, the slot is not read at a call. Two abstract refinements in one slot
are not read either. Both are `abstract-refinement-uninstantiated`. Applying
`p` to another function's result is an error:

```march
{a | p(_) == false}   -- not read at a call
{a | p(q(_))}         -- an error
```

**What can instantiate `p`.** Besides an inline lambda:

```march
fn is_pos(n : Int) : {Bool | _ == (n > 0)} do n > 0 end

sum_pos(List.filter(ys, is_pos))              -- a named predicate: proved
sum_pos(List.filter(ys, fn y -> is_pos(y)))   -- the same (`fn y -> g(y)` is `g`)
let keep = fn y -> y > 0
sum_pos(List.filter(ys, keep))                -- a let-bound lambda: proved
fn keep_pos(ys : List(Int), k : ({x : Int | true}) -> {Bool | _ == (x > 0)}) : Int do
  sum_pos(List.filter(ys, k))                 -- a callback parameter: proved
end
```

A named function or a callback contributes its proved Bool contract over its
one parameter, the shape `is_pos` has above. The `==` may be written either
way round. A contract the definition does not prove never reaches a caller.
So it never instantiates `p` either. A predicate whose return type is a plain
`Bool` instantiates nothing.

A `let`-bound lambda is read as the lambda itself. It shadows a top-level
function of the same name. It stops counting once its name is rebound.

**Lambda bodies.** A lambda's body is read as an exact predicate over its
parameter, never a weaker one. The reader understands:

- `&&`, `||`, `!` and `not`;
- `if`;
- a `match` on a Bool, with `true` and `false` arms, or one of them and `_`,
  and no guards;
- a call to a `let`-bound lambda, read as its body with the arguments put in;
- a call to a function or callback with a proved Bool contract over any number
  of parameters, read as that contract with the arguments put in order.

```march
fn gt(n : Int, m : Int) : {Bool | _ == (n > m)} do n > m end

sum_pos(List.filter(ys, fn y -> is_pos(y) && y < 100))             -- proved
sum_pos(List.filter(ys, fn y -> if y > 0 do y < 100 else false end)) -- proved
sum_pos(List.filter(ys, fn y -> gt(y, 0)))                         -- proved: `y > 0`
sum_pos(List.filter(ys, fn y -> gt(0, y)))                         -- skip: too weak
sum_pos(List.filter(ys, fn y -> is_pos(y) || y < 100))             -- skip: too weak
```

A too-weak skip prints the lambda and what it was read as:

```
`fn y -> is_pos(y) || y < 100` (read as `y > 0 || y < 100`) does not imply `_ > 0`
```

The body may mention nothing but the lambda's parameter. A lambda that uses
one of the caller's variables is declined. So is a `let`-bound lambda that
captures one:

```march
fn y -> gt(y, k)   -- declined: `k` is the caller's variable
```

Calls to `let`-bound lambdas are inlined at most four deep. `f4` calling `f3`
calling `f2` calling `f1` is read. One level more is declined, and the message
names the bound.

A helper's Bool contract holds only for arguments that meet its refined
parameters. So the reader inlines a helper only where each of those is proved
at the call. The facts come from two places:

- what the combinator's callback domain promises, which for a plain
  `a -> Bool[p]` is nothing;
- what the lambda has already decided on the way to the call, such as the left
  side of `&&` or `||`, or an `if` condition.

```march
fn weird(a : {Int | _ > 0}) : {Bool | _ == (a > 0)} do a > 0 end

sum_pos(List.filter(ys, fn y -> weird(y)))            -- declined: weird's precondition is not proved
sum_pos(List.filter(ys, fn y -> y > 0 && weird(y)))   -- proved: read as `y > 0 && y > 0`
```

**The standard library.** These combinators carry `p`:

- `List.filter`, `List.take_while` and `List.partition`;
- `List.find`, with an `Option` result;
- `Option.filter`;
- the bare `filter` (`Prelude.filter`), `Enum.filter`, `Enum.take_while` and
  `Iterable.filter`, each returning a `List`;
- `Enum.find` and `Iterable.find`, each returning an `Option`;
- `Range.filter`, whose predicate is over `Int`;
- `Deque.filter`, returning a `Deque`.

The last bullet of
[What element refinements do not do](#what-element-refinements-do-not-do)
explains how a type whose elements sit in `List` fields is checked.

```march
fn one_pos(o : Option({Int | _ > 0})) : Int do … end
one_pos(List.find(ys, fn y -> y > 0))         -- proved
one_pos(Option.filter(o, is_pos))             -- proved
sum_pos(List.take_while(ys, is_pos))          -- proved
sum_pos(filter(ys, fn y -> y > 0))            -- proved: Prelude.filter
one_pos(Enum.find(ys, fn y -> y > 0))         -- proved
sum_pos(Range.filter(Range.new(0, n), fn y -> y > 0))  -- proved
sum_pos(Deque.to_list(Deque.filter(d, fn y -> y > 0))) -- proved
```

Each proves its own contract on the definition side. None is assumed.

**Tuples: `List.partition`.** A return that is a tuple of containers carries
one element slot per component:

```march
fn partition(xs : List(a), pred : a -> Bool[p]) : (List(a[p]), List({a | !p(_)}))

let (pos, neg) = List.partition(ys, fn y -> y > 0)
sum_pos(pos)                                  -- proved: `y > 0`
sum_nonpos(neg)                               -- proved: `!(y > 0)`
sum_pos(neg)                                  -- skip: too weak (`!(y > 0)`)
match List.partition(ys, fn y -> y > 0) do
(pos, _) -> sum_pos(pos)                      -- proved
end
```

A component reaches a demand only when you destructure the call directly.
There are two ways:

- a `let` with a tuple pattern;
- a `match` with exactly one arm, no guard, whose pattern is a tuple of names
  and `_`.

Each name then stands for its component of that call. An alias of the name
keeps it. The fact ends when the name, or a name the call mentions, is
rebound.

```march
let (a, b) = g(…)                  -- a let with a tuple pattern
match g(…) do (a, _) -> … end      -- one arm, a tuple of names and `_`
let p2 = pos                       -- an alias keeps the fact
```

Your own function may declare such a return, abstract or not:

```march
fn split_pos(xs : List(Int)) : (List({Int | _ > 0}), List(Int)) do … end
```

Every tail is checked component by component. A tail may be a tuple literal,
a recursive call through the structural induction hypothesis, or a call to
another proved tuple return. A recursive result destructured in the body
carries the hypothesis as well:

```march
let (yes, no) = part(t, pred)
```

`List.partition` uses a tail-recursive accumulator, a top-level helper named
`partition_go`. Its `yes` and `no` parameters carry the two element slots, and
they are checked at every push. So both halves are proved on the definition
side.

#### Two arguments: a relation between sibling slots

Some filters decide on a key and a value together. Their callback takes two
arguments, so it defines a `p` of two arguments.

In March a two-argument callback is a curried chain, whichever way the
combinator calls it. A tuple domain is one argument:

```march
D1 -> D2 -> Bool   -- two arguments
(D1, D2) -> Bool   -- ONE argument, a tuple
```

The definer applies `p` to both of its argument names, in order. Each use of
`p` then relates two sibling slots of one type, as a
[relational element refinement](#relational-element-refinements) does. The
shorthand marks every slot that `p` relates, in slot order:

```march
type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

fn filt(a : Assoc(k, v), keep : k -> v -> Bool[p]) : Assoc(k[p], v[p]) do
  match a do
    ANil -> ANil
    ACons(k, v, t) -> if keep(k, v) do ACons(k, v, filt(t, keep)) else filt(t, keep) end
  end
end
```

It means exactly the spelled-out form, which is also accepted:

```march
fn filt(a : Assoc(k, v), keep : ({x : k | true}) -> ({y : v | true}) -> {Bool | _ == p(x, y)})
    : Assoc({x : k | true}, {y : v | p(x, y)}) do
  …
end
```

The slot markings mean one relation only because `p` takes two arguments. The
checker reads that from the definer in the same signature. With a
one-argument `p`, the same markings are two separate facts, one per slot:

```march
keep : k -> v -> Bool[p]   -- with Assoc(k[p], v[p]): one relation over each entry
keep : k -> Bool[p]        -- with Assoc(k[p], k[p]): two facts, one per slot
```

A domain may name its argument in the chain, as for one argument. Two domains
may not share one name:

```march
({x : Int | x > 0}) -> v -> Bool[p]
```

**What the return means.** The return says that every entry of the result
satisfies `p`. Inside `filt`, `p` is an uninterpreted function of two
arguments. Calling `keep` on a key and a value is `p` of that key and value.
So the guard in the body is exactly what it needs to prove its return.

**At a call, `p` is what the passed callable computes.** The checker compares
the relation it produces with the demand. A demand about one slot is met by
[projection](#relational-element-refinements), as for a written relation:

```march
mod Filt do
  type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))

  fn filt(a : Assoc(k, v), keep : k -> v -> Bool[p]) : Assoc(k[p], v[p]) do
    match a do
      ANil -> ANil
      ACons(k, v, t) -> if keep(k, v) do ACons(k, v, filt(t, keep)) else filt(t, keep) end
    end
  end

  fn need_pos(_a : Assoc(Int, {Int | _ > 0})) : Int do 0 end
  fn need_up(_a : Assoc({x : Int | true}, {y : Int | y > x})) : Int do 0 end

  fn t1(a : Assoc(Int, Int)) : Int do need_pos(filt(a, fn (_k, v) -> v > 0)) end          -- proved
  fn t2(a : Assoc(Int, Int)) : Int do need_up(filt(a, fn (k, v) -> v > k)) end            -- proved: the relation itself
  fn t3(a : Assoc(Int, Int)) : Int do need_pos(filt(a, fn (k, v) -> k > 0 && v > k)) end  -- proved: projected onto the values
  fn t4(a : Assoc(Int, Int)) : Int do need_pos(filt(a, fn (k, v) -> v > k)) end           -- skip: too weak (a negative key)
  fn t5(a : Assoc(Int, Int)) : Int do need_pos(filt(a, fn (_k, v) -> v >= 0)) end         -- skip: too weak
end
```

The two skips are `abstract-refinement-too-weak`. The message for `t4` is:

```
`fn (k, v) -> v > k` does not imply `_ > 0`
```

In `t4`, an entry such as `(-1, 0)` passes the filter, and its value is not
positive.

**What you can pass for a two-argument `p`:**

- an uncurried lambda, for a combinator that calls its callback with both
  arguments at once;
- a curried lambda, for a combinator that calls it in two steps (today that
  counts only for a parameter's `p` and for `Map.filter`'s assumed return,
  below; see "Not yet");
- either of those bound by `let`;
- a function with a proved Bool contract over two parameters;
- a callback parameter that itself defines a two-argument abstract refinement
  of the enclosing function, passing its own `p` on.

```march
fn (k, v) -> v > k                                       -- uncurried lambda
fn k -> fn v -> v > k                                    -- curried lambda
fn above(k : Int, v : Int) : {Bool | _ == (v > k)} do … end   -- a named function
keep : k -> v -> Bool[q]                                 -- a callback parameter, passing its q on
```

Anything else is `abstract-refinement-uninstantiated`, and the message says
why. Two cases are worth knowing.

**A name bound twice.** A lambda that binds one name twice in one parameter
list is not a program at all. Since 2026-10-22 the typechecker rejects it as
[`duplicate_binder`]({{ site.baseurl }}/docs/errors/duplicate_binder/). It
rejects a function's parameter list and a pattern the same way. Before that,
the interpreter and compiled code disagreed about which argument the name
meant. A curried chain that reuses a name is ordinary shadowing, and it still
typechecks. It instantiates nothing. The call is an
`abstract-refinement-uninstantiated` skip.

```march
fn (x, x) -> x > 0                  -- duplicate_binder
fn two(a : Int, a : Int) : Int      -- duplicate_binder
(a, a)                              -- duplicate_binder, in a pattern
fn k -> fn k -> k > 0               -- typechecks; skip: "the lambda passed for `p` binds `k` twice"
```

**A chain ending in a concrete contract.** Nothing checks the callable passed
for such a parameter against its contract. So inside the function, calling it
gives no fact. Passing it on to `filt` instantiates nothing. A one-argument
codomain contract, by contrast, is checked at each call, as above.

```march
kk : ({x : Int | true}) -> ({y : Int | true}) -> {Bool | _ == (y > x)}   -- carries no fact yet
```

**`p` can also sit on a parameter.** Then the argument's entries must meet the
relation that the passed callable computes. A callable that makes the
relation constant still binds it. Passing one that always returns `false` is a
violation for any non-empty argument:

```march
fn need(a : Assoc({x : k | true}, {y : v | p(x, y)}), keep : k -> v -> Bool[p]) : Int do … end

need(ACons(1, 2, ANil), fn (k, v) -> v > k)       -- proved
need(ACons(1, 2, ANil), fn (_k, _v) -> false)     -- violation: the entry (1, 2)
```

**A slot may also mention another parameter of the callee.** That name is read
at the call's argument for it. This holds on a return and on a parameter
alike:

```march
{y : Int | p(x, y) && y > n}   -- `n` is the call's argument for the parameter `n`
```

**The input's slot facts carry over. Its relations do not.** A fact about each
value of the input still holds of each value of the result, as for one
argument. A relation on the input is not carried. The result's entries are not
the input's, and a function generic in `k` and `v` may pair the key of one
entry with the value of another (see `shift` under
[relational element refinements](#relational-element-refinements)).

```march
-- a : Assoc(Int, {Int | _ > 0})
filt(a, fn (_k, v) -> v < 100)   -- meets Assoc(Int, {Int | _ > 0 && _ < 100})
```

**The signature is checked.** Each of these mistakes is an
`abstract_refinement_misuse` error, and the message gives the fix:

- the definer does not apply `p` to every argument of its chain, once each, in
  order;
- a use of `p` does not name distinct binders of sibling slots, for example it
  marks a single slot or a number of slots other than two;
- an argument has different types in the definer and in a use;
- the container is not entry-shaped (every constructor must hold one `k` and
  one `v`, or neither; see
  [relational element refinements](#relational-element-refinements));
- one `p` is used with two arities.

```march
p(y)                                   -- under a two-argument callback: error
p(y, x)                                -- arguments out of order: error
Assoc(k, v[p])                         -- one slot: error, the fix is Assoc(k[p], v[p])
Assoc(k, {v | p(_)})                   -- the same
HamtMap(HEntry(k, v))                  -- inside another type, one type application of both: fine
```

**Not yet.** Inside a body, a callback called in two steps gives the second
step no fact. So a combinator written that way does not prove its relational
return, and its calls instantiate nothing. (March has no syntax for calling
the result directly, as in `keep(k)(v)`.)

```march
let g = keep(k)
if g(v) do … else … end   -- no fact about k and v
```

**`Map.filter` carries it, assumed.** Its callback is curried, and it decides
on a key and a value together:

```march
@[assume]
fn filter(m : Map(k, v), pred : k -> v -> Bool[p], cmp : k -> k -> Bool)
    : {Map(k[p], v[p]) | subset(keys(_), keys(m))} do … end
```

```march
mod MapFilter do
  fn need_vals(_m : Map(String, {Int | _ > 0})) : Int do 0 end
  fn need_rel(_m : Map({x : Int | true}, {y : Int | y > x})) : Int do 0 end

  fn t1(m : Map(String, Int)) : Int do
    need_vals(Map.filter(m, fn _k -> fn v -> v > 0, Map.str_cmp))    -- proved
  end
  fn t2(n : Map(Int, Int)) : Int do
    need_rel(Map.filter(n, fn k -> fn v -> v > k, Map.int_cmp))      -- proved
  end
  fn t3(m : Map(String, Int)) : Int do
    need_vals(Map.filter(m, fn _k -> fn v -> v >= 0, Map.str_cmp))   -- skip: too weak
  end
end
```

`Map`'s body goes through a list of tuples, and it calls `pred` in two steps.
So the checker cannot prove the entry fact. It is `@[assume]`d, like every
other `Map` contract.

`@[assume]` on a function whose return has an element entry assumes that
entry. The entry may be slots, relations or abstract applications. The body is
not checked against it. The definition counts one `trusted` postcondition per
entry in `--refine-report`, and it is accepted under `cap verified`.

At a call, an assumed entry is instantiated like a proved one, with two
differences:

- An assumed callee is asked only that its type variables are generic in its
  inferred type. Its parameters must be annotated.
- The input's own element facts are not added. A map of positive values,
  filtered to values below 100, does not meet a demand for values that are
  both. The too-weak message says so.

```march
-- m : Map(String, {Int | _ > 0})
Map.filter(m, fn _k -> fn v -> v < 100, Map.str_cmp)   -- does not meet `_ > 0 && _ < 100`
```

The property test in `test/stdlib/test_map.march` checks the fact at run time.
`HashMap.filter`, `OrderedMap.filter` and a list of pairs do not carry it yet;
see [Limitations](#open-gaps-in-element-and-abstract-refinements).

#### What abstract refinements do not do

These apply to one argument and two alike. Where a demand meets one of them,
the reason is `abstract-refinement-uninstantiated`. The two-argument gaps are
also collected under
[Limitations](#open-gaps-in-element-and-abstract-refinements).

- **A predicate with no proved Bool contract instantiates nothing.** This is
  true by name and when called inside a lambda. No contract is inferred from a
  body. Passed by name, a predicate must also take one parameter. A bare
  two-parameter `gt` has no one-argument meaning. Calling it inside a lambda
  is read:

  ```march
  sum_pos(List.filter(ys, fn y -> gt(y, 0)))   -- read as `y > 0`
  ```

- **Some lambda bodies are not translated.** The checker declines them, and
  the message names the construct. These are:
  - a body that mentions a name besides its parameter;
  - a block with `let`;
  - a `match` on anything but a Bool, or one with guards;
  - an `if` or Bool `match` used as a non-Bool value;
  - a call to a function with no proved contract, or to the lambda's own
    parameter;
  - a call whose head is computed;
  - a `let`-bound lambda that names itself;
  - inlining deeper than four `let`-bound lambdas.

  Int-valued helpers are not inlined. Neither is a helper whose refined
  parameters are not proved at the call inside the lambda.

  ```march
  fn y -> y > m       -- mentions `m`: declined
  fn y -> score(y) > 3   -- with score : {Int | _ == …}: not inlined
  ```

- **A callback parameter's contract is taken on trust from its callers.**
  Inside `keep_pos` above, the contract on `k` instantiates `p`. But it is only
  as good as the obligation at each place `keep_pos` is called. Today, passing
  a callable whose return is not known to meet it is a skip there, not a
  violation.

- **`Map`'s other functions carry no element fact.** `Map.insert`,
  `Map.remove`, `Map.get`, `Map.merge` and `Map.map_values` keep nothing of a
  refined input. Inserting into a map of positive values, for a demand on
  positive values, is a skip. A fold's accumulator invariant needs no abstract
  refinement at all; see [Folds](#folds-an-accumulator-invariant).

  ```march
  need_vals(Map.insert(pos_map, "b", 5, cmp))   -- skip
  ```

- **Not every combinator carries `p`.**
  - `drop_while` (`List`, `Enum`) keeps no element fact. Its result starts at
    the first element that FAILS `pred`, so nothing holds of all of it.
  - `List.filter_map`'s callback returns an `Option`, not a `Bool`, so nothing
    defines `p`.
  - `List.find_index` returns an index, not an element.

- **A tuple component counts only through direct destructuring.** These carry
  no component fact:
  - taking a component with a function such as `Tuple.first`;
  - binding the tuple whole and taking it apart later;
  - a `match` with more than one arm, or with a refutable component;
  - a tuple `let` whose call mentions one of its own names;
  - a nested tuple, or a tuple inside a container;
  - a tuple passed on to another function.

  ```march
  Tuple.first(g(…))                  -- no fact
  let r = g(…)                       -- then `match r do …`: no fact
  (Cons(_, pos), _) -> …             -- a refutable component: no fact
  let (xs, b) = g(xs)                -- the call mentions `xs`: no fact
  ```

- **A String callback on the definition side is not read yet.** Inside a
  combinator over a list of strings, calling the callback does not yet reflect
  as `p`. So a body written by hand over strings does not prove its return.
  Delegating to `List.filter` does.

  ```march
  f : String -> Bool[p]   -- `f(h)` inside the body is not read as `p(h)`
  ```

- **`p` only works in an element slot.** It does not work on a bare scalar
  return, and not through `interface`/`impl` dispatch.

  ```march
  (a) -> {a | p(_)}   -- not supported
  ```

### Folds: an accumulator invariant

A demand on the result of a fold is read as the invariant its accumulator
keeps. Look at `List.fold_left`'s signature:

```march
fn fold_left(xs : List(a), acc : b, f : b -> a -> b) : b
```

It is generic in `b`. So every `b` it returns is either the initial value or
a result of `f`. Every `b` it hands to `f` is one of those again. The demand
therefore holds when two things do:

- **the base**: the initial value meets it;
- **the step**: `f` returns a value that meets it, assuming the demand of each
  of its parameters whose type is exactly `b`.

```march
fn need_nn(k : {Int | _ >= 0}) : Int do k end
fn need_pos(k : {Int | _ > 0}) : Int do k end

fn count(ys : List(Int)) : Int do
  need_nn(List.fold_left(ys, 0, fn (acc, _x) -> acc + 1))      -- proved
end

fn drained(pos : List({Int | _ > 0})) : Int do
  need_nn(List.fold_left(pos, 0, fn (acc, x) -> acc - x))      -- skip: the step can break it
end

fn summed(pos : List({Int | _ > 0})) : Int do
  need_pos(List.fold_left(pos, 0, fn (acc, x) -> acc + x))     -- skip: the base 0 fails it
end

fn running_max(ys : List(Int)) : {Int | _ >= 0} do
  List.fold_left(ys, 0, fn (a, x) -> if x > a do x else a end) -- proved, at a return
end
```

The step may also use what its other parameters know. In `drained`, `x` has
`pos`'s element refinement. The step may use anything it captures too. Adding
a captured positive `m` proves, and adding a captured unrefined `m` does not.

Nothing about how often, or in what order, the step runs is assumed. Running
it zero times is the base. So these all work the same way:

- `fold_right`, whose accumulator is the second parameter;
- the curried `Enum.fold`, whose step is read as one two-parameter lambda;
- `Enum.reduce`, which has no initial value: the list's elements are the base,
  and both parameters assume the demand;
- a fold you write yourself.

Nothing here is specific to the stdlib's folds. The rule applies to any
function generic in its return variable, with a callback that consumes it.

**The accumulator can be a container.** Then an element demand on the fold's
result sets `b` to that refined list. The initial list must meet it. The step,
assuming the list it is handed meets it, must build one that does.

```march
fn sum_pos(xs : List({Int | _ > 0})) : Int do 0 end

fn reversed(pos : List({Int | _ > 0})) : Int do
  sum_pos(List.fold_left(pos, [], fn (acc, x) -> Cons(x, acc)))       -- proved
end

fn kept(ys : List(Int)) : List({Int | _ > 0}) do
  List.fold_left(ys, [1], fn (acc, x) -> if x > 0 do Cons(x, acc) else acc end) -- proved
end

fn copied(ys : List(Int)) : Int do
  sum_pos(List.fold_left(ys, [], fn (acc, x) -> Cons(x, acc)))        -- skip: x is not known positive
end

fn seeded(pos : List({Int | _ > 0})) : Int do
  sum_pos(List.fold_left(pos, [0], fn (acc, x) -> Cons(x, acc)))      -- skip: the base [0] fails it
end
```

`List.fold_right`, the curried `Enum.fold` and a nested fold prove the same
way. In a nested fold, the inner fold's initial value is the outer
accumulator, which meets the demand by the outer assumption. A curried step's
inner parameter also gets its element refinement here:

```march
need_pos(Enum.fold(pos, 1, fn a -> fn x -> a + x))   -- proved: `x` comes from pos
```

**Which stdlib folds carry it.**

- `List.fold_left`, `List.fold_right` and the prelude's `fold_left`;
- `Enum.fold`, `Iterable.fold`, `Enum.reduce` and `Range.reduce`;
- `Map.fold`, `Set.fold` and `HashMap.fold`;
- `Array.fold_left`, `RRB.fold`, `RRB.fold_left`, `Deque.fold_left` and
  `Deque.fold_right`;
- `Hamt.fold`, whose callback is curried.

Each declares its accumulator `b` and its callback's arrow. The parametricity
checks read those:

```march
f : b -> k -> v -> b   -- the map folds
f : b -> a -> b        -- the rest declare one of these two
f : a -> b -> b
```

`List.scan_left` and the curried `Enum.scan` return every accumulator value as
a list. So an element demand on their result is the same invariant:

```march
sum_nn(Enum.scan(ys, 0, fn a -> fn _x -> a + 1))   -- proved
```

```march
fn entries(m : Map(String, Int)) : Int do
  need_nn(Map.fold(m, 0, fn (acc, _k, _v) -> acc + 1))         -- proved
end

fn shrink(d : Deque.Deque(Int)) : Int do
  need_nn(Deque.fold_left(d, 0, fn (acc, _x) -> acc - 1))      -- skip: the step can break it
end
```

These folds do **not** carry it, and a demand through them stays a skip:

- the `NativeArray` folds, such as `fold_int`: the body is one builtin, which
  the checks cannot see through;
- `Seq.fold`, `Seq.fold_while` and the folds built on them, `JsonStream.fold`
  and `Flow.reduce`: the accumulator travels through a closure stored in data;
- for now, `SortedSet.fold` and `OrderedMap.fold`: they are annotated, but
  their collection parameter is a record type, which the parametricity check
  does not yet walk.

None of these is `@[assume]`d. Parametricity is checked, never taken on trust.

A refuted base or step is a **skip, never a violation**. Each has its own
reason, `accumulator-base-unproved` or `accumulator-step-unproved`, so the
report says which half failed. A failing base can be harmless on a non-empty
list. A failing step can be harmless on an empty one. And a true property
need not be an invariant of the step. A fold that adds 1 from 0 never returns
-1, but "not -1" before a step does not imply "not -1" after it. Under
`cap verified` the skip is an error, as always.

The argument rests on the callee being unable to make a `b` of its own. So it
applies only where the [parametricity checks](#through-a-polymorphic-call)
pass. A "fold" gets no assumption, and keeps the plain
`parametric-source-unproved` skip, when it does any of these:

- its body fixes `b`;
- it feeds the step a value it built;
- it takes an unannotated callback;
- it calls a decoder or an interface method returning a type variable;
- it is marked `@[trusted]` or `@[assume]`, or dispatched through an `impl`.

The rule also declines a step that uses `let?` or `let*`, and a step whose
parameter is spelled like a name the demand mentions. An accumulator
parameter with its own refinement annotation is the next subsection's case.

Only a demand the checker already traces reaches a fold:

- a closed scalar demand: a precondition, an annotated `let`, or a closed
  return;
- an element demand on the call, or a declared element return.

```march
one_pos(Enum.reduce(pos, …))           -- an element demand on the call
sum_pos(List.fold_left(pos, [], …))    -- the same
: {Int | _ >= lo}                      -- a relational scalar return: not traced yet
```

A `let`-bound fold result used later carries nothing, unless the accumulator
is annotated (below). The step's tails are checked where the lambda is
written. So a tail that names something bound inside the step is not checked,
and the call is a skip:

```march
match acc do Cons(h, _) -> Cons(h, acc) … end   -- `h` is bound inside the step: skip
```

#### An annotated accumulator

You can state the invariant yourself by annotating the accumulator:

```march
fn (acc : {Int | _ > 0}, x) -> …
```

The annotation is checked as exactly the judgment above, with the annotation
in place of a demand. The initial value must meet it. The step, assuming it of
every parameter typed `b`, must return a value that meets it.

When it holds, `acc` may assume it inside the step's body. The call's result
carries it too. So a `let`-bound fold result has the fact with no demand on
the call:

```march
fn count(ys : List(Int)) : Int do
  let s = List.fold_left(ys, 1, fn (acc : {Int | _ > 0}, _x) ->
    let _u = need_pos(acc)                                 -- proved: acc assumes it
    acc + 1)
  need_pos(s) + need_nn(s)                                 -- both proved
end

fn above(ys : List(Int), lo : Int) : Int do
  let s = List.fold_left(ys, lo, fn (acc : {Int | _ >= lo}, _x) -> acc + 1)
  need_ge(s, lo)                                           -- proved
end

fn zeroed(ys : List(Int)) : Int do
  let s = List.fold_left(ys, 0, fn (acc : {Int | _ > 0}, _x) -> acc + 1)
  need_pos(s)                         -- skip: the base 0 fails the annotation
end

fn shrinking(ys : List(Int)) : Int do
  List.fold_left(ys, 1, fn (acc : {Int | _ > 0}, _x) -> acc - 1) -- skip: the step breaks it
end
```

The annotation is an obligation of its own, on the parameter. It is reported
against the callee, `List.fold_left`, with the same two reasons. A refuted
base or step is a skip, never a violation, for the reasons above. Under
`cap verified` it is an error.

An annotation that does not hold is not assumed, in the body or of the
result. The fact belongs to its call's result. It is retired like any other
fact when the result is rebound, or when a name the annotation mentions is
rebound, such as `lo` above.

If the call also has a demand on it, the annotation is checked and must imply
the demand. A return tail counts as a demand. If the annotation does not hold,
or does not imply the demand, the demand is tried as the invariant on its own,
as if the parameter were unannotated. The annotation is never assumed for it.

```march
need_nn(List.fold_left(ys, 1, fn (acc : {Int | _ > 0}, _x) -> acc + 1))   -- annotation and demand
```

The same gates apply. The callee must be generic in its return variable `b`
by the parametricity checks. It must not be `@[trusted]`, `@[assume]` or an
`impl` method. The shape is narrow:

- The callee's declared return is a bare type variable `b`, and the annotated
  parameter's type is exactly `b`. The lambda must be written inline. A
  `let`-bound lambda passed by name is not read.
- The annotation refines the value itself, not a container's elements. An
  annotation on a list accumulator's elements stays as it was: not checked,
  not assumed.
- Exactly one parameter typed `b` is annotated. The others typed `b` assume it
  too. Two annotated ones are left as they were.
- A one-parameter lambda is checked at the pass site instead, as any refined
  callable is. That includes the outer lambda of a curried step. Annotating an
  inner curried parameter is read as above.

```march
acc : List({Int | _ > 0})                              -- a container's elements: not read
fn (a : {Int | _ > 0}, c) -> a + c                     -- passed as f : b -> b -> b: `c` assumes it too
fn (k : {Int | _ > 0}) -> k + 1                        -- passed as f : b -> b: violation at the pass site
Enum.fold(ys, 1, fn (a : {Int | _ > 0}) -> fn x -> …)  -- the outer lambda of a curried step: pass site
```

The one-parameter case is a violation because `b` does not imply `_ > 0`.

An annotation on the *element* parameter is not an invariant of anything. It
is a claim about the list's elements that nobody checks. So it is neither
checked nor assumed. Give the list the refinement instead, and the element
parameter gets it:

```march
fn (acc, x : {Int | _ > 0}) -> …   -- not checked, not assumed
xs : List({Int | _ > 0})           -- do this instead: then `x` gets it
```

### What element refinements do not do

- **Only these combinators carry an abstract refinement:** `List.filter`,
  `List.find`, `List.take_while`, `Option.filter`, `List.partition` (per
  component), `Prelude.filter` (the bare `filter`), `Enum.filter`,
  `Enum.find`, `Enum.take_while`, `Iterable.filter`, `Iterable.find`,
  `Range.filter`, `Deque.filter` and, over a key and a value together and
  assumed rather than proved, `Map.filter`. Each is instantiated from a lambda
  (whose body may combine `&&`/`||`/`not`/`if` and calls to proved helpers),
  a named predicate with a proved contract, a callback parameter or a
  `let`-bound lambda; see [Abstract refinements](#abstract-refinements-filter-keeps-what-its-predicate-says).
- **A scalar demand is traced only when it is closed.** `need_pos(Option.unwrap_or(o, 1))`
  is checked through `unwrap_or`'s sources (the elements of `o` and the
  default), but a demand that names another parameter of its function
  (`List.nth(xs, Option.unwrap_or(o, 0))` against `_ < len(xs)`) is not, and
  neither is a relational return (`: {Int | _ >= lo}`, so a fold's running
  maximum `>= lo` is not checked either). A block-level `fn`'s
  return tail is traced over that `fn`'s own parameters only: a captured
  variable carries no fact there. A source that fails the demand makes the call
  a skip, never a violation.
- **A fold's accumulator assumes only a demand on the fold's result.** In
  `fold_left(xs, 1, fn (acc, x) -> …)`, `x` assumes `xs`'s element refinement,
  but `acc` assumes something only while the step's result is being checked
  against a demand on the call ([Folds](#folds-an-accumulator-invariant)).
  With no such demand (`need_pos(acc)` inside the step, a `let`-bound result
  used later) it assumes nothing unless it is annotated
  ([An annotated accumulator](#an-annotated-accumulator)), and an invariant is
  never inferred. An annotation on the element parameter
  (`fn (acc, x : {Int | _ > 0}) -> …`) is neither checked nor assumed. Indexed
  invariants (`_ == len(xs)`), tuple or record accumulators, a
  callback parameter of type `List(b)` and a hand-written accumulator
  recursion (`fn sum(xs, acc : {Int | _ >= 0}) : {Int | _ >= 0}`) are not
  covered. A curried lambda (`fn a -> fn x -> …`) gives an element fact to its
  inner parameters only while its result is checked against a demand on the
  call; inside its body otherwise, only the outer parameter gets one.
- **A local `fn` with a container return lends it only when the entry names
  nothing but the `fn`'s own parameters, and the `fn` does not recurse into it.**
  Its tails are checked like a top-level function's, and a proved one is a fact
  at its later calls in the block (read at each call's arguments), but a return
  naming a captured variable (`List({Int | _ < k})` with `k` from outside)
  lends nothing, and a recursive call inside the local carries nothing (no
  structural self-call hypothesis), so `fn go(xs) : List({Int | _ > 0})` whose
  tail is `go(t)` is a skip. A local returning a tuple of element-refined
  containers has every component of every tail checked, but lends nothing at
  its calls.
- **A predicate relating different elements to each other** (sortedness,
  distinctness) cannot be written. A relation between the components of ONE
  entry can ([Relational element refinements](#relational-element-refinements));
  see [Set Refinements](#set-refinements) for what a predicate can say about a
  collection's elements as a set.
- **A parameter inside another container is followed one level, and only
  as a bare argument.** A constructor field `C(…)` of another registered
  container (`List`, `Option`, `Result`, or a variant type of the program)
  whose every argument is a bare type parameter or mentions none is checked
  as that container: in `type Dq(a) = Dq(Int, List(a), List(a))`,
  `Dq(1, [0 - 1], [])` against `Dq({Int | _ > 0})` is a violation, and
  `match d do Dq(_, f, b) -> …` gives `f` and `b` the element refinement. That
  is what lets `Deque.filter` declare `Deque(a[p])`. Any other field that
  holds a parameter (`type Box(b) = Box(Int -> b)`,
  `type Wrap(k, v) = Wrap(List((k, v)))`, a `List(List(a))` field, a field of
  a container that itself hides the parameter, a self-reference with the
  parameters permuted) has its element refinement checked at no construction:
  `Wrap([(1, 0 - 5)])` against `Wrap(Int, {Int | _ > 0})` is a recorded
  `unreflectable-subject` skip naming the constructor and the hiding type (an
  error under `cap verified`), a function returning such a construction lends
  no element fact at its call sites, and a `match` binder at that field gets
  none. Element refinements say nothing about order or size: a `Dq(a[p])`
  with its two lists swapped is still one.
- **A parameter typed with a module-qualified container is not yet a
  source.** `q : Queue.Queue({Int | _ > 0})` (or `Deque.Deque(...)`) gives
  `sum_pos(Queue.to_list(q))` no element fact (a `parametric-source-unproved`
  skip), although the same shape over a type declared in the module under
  check (`q : Lk({Int | _ > 0})`) proves. A queue built in the same function
  does carry it: `sum_pos(Queue.to_list(Queue.push_back(Queue.from_list(pos), 3)))`
  and `one_pos(Queue.peek_front(Queue.from_list(pos)))` are proved.

---

## Counting the obligations: `--refine-report`

Silence is the default outcome for everything that is not a definite failure, so
silence by itself cannot tell **proved** from **skipped**. That ambiguity is not
cosmetic: `{List(a) | len(_) > 0}` once shipped with zero enforcement while the test
suite stayed green, because a contract that checks no case and a contract that
passes look identical from outside.

`--refine-report` makes the checked fraction a number:

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

> **Clear `.march/cas/artifacts-v2` and `~/.march/cas/artifacts-v2` first** (builds
> write through to the global store, so a project-only clear can still hit). A `--check` run with sources that hash to
> an artifact already in the CAS exits immediately, before parsing, so the
> report never runs and the command prints **no output** while still exiting 0.
> That looks identical to "no obligations found", which is exactly the
> ambiguity this flag exists to remove, so always run it against a cold check
> cache. (`.march/cas/vc` is a *different* cache: solver verdicts, not check
> artifacts. Clearing it forces z3 to re-decide; it does not affect whether the
> report prints.)

Two slices are printed because the compiler prepends the whole standard library
to every compilation: **user code** counts only obligations raised at call sites
in the file you named, **user + stdlib** counts every obligation raised in the
run. Use the first to judge your own module; use the second as a whole-program
coverage number.

**CI ratchets on both, from two different fixtures, and that split is
essential.** The skip **upper limit** reads `stdlib/list.march`'s `user + stdlib`
slice (28 skips, 8 proved as of 2026-07-29). The proof **floor** reads the
`user code` slice of `accept/t118` (1 proved), because an upper limit by itself is not a
ratchet: a checker that raises no obligations at all satisfies it perfectly.
The floor cannot live on `stdlib/list.march`: its `user code` slice proves 0, and
its whole-program `8 proved` is dominated by obligations that survive the very
regressions the floor exists to catch. `t118` is a program with a single
obligation, *proved* by a `List.length` guard, so it drops to `0 proved` the
moment the measure alias stops working, which is exactly what the unit-global
glob-import bug did to every March program, invisibly, while `t118` still exited
0 (a skip and a proof are both exit 0; only the count tells them apart).

Each skip is attributed to one of sixteen reasons:

| Reason | What happened |
|---|---|
| `unreflectable-predicate` | the predicate's own sub-expression named in the message has no SMT translation |
| `unreflectable-subject` | the argument named in the message could not be translated to SMT, so no goal was built |
| `sort-conflict` | reflecting it would declare one symbol at two different sorts |
| `float-sort-gate` | the float wellsortedness gate rejected the formula |
| `alias-withdrawn` | the guard used a measure alias (`List.length`, `String.byte_size`, `string_byte_length`), directly or through one `let` (`let n = List.length(ys)` then `if n > 0`), that this compilation unit had withdrawn, because something in the unit binds that name |
| `unconstrained-subject` | no fact the checker derived constrains the argument the predicate talks about |
| `partial-conjunct` | the predicate is a top-level `&&`, and the checker proved some conjuncts but not others; the message names which held and which did not |
| `opaque-application` | the goal names a function the checker has no meaning for, so it cannot reason through it |
| `nonlinear-goal` | the goal multiplies two non-constant terms (`y * y + 1`, `x * k`), and the solver, which is incomplete on non-linear integer arithmetic, settled it neither way |
| `parametric-source-unproved` | a polymorphic call's result meets an element demand only if every source of the demanded type variable does, and the source the message names did not |
| `accumulator-base-unproved` | a fold's initial value (or, for a `reduce`, the list's elements) was not proved to meet the demand or the annotated accumulator; see [Folds](#folds-an-accumulator-invariant) |
| `accumulator-step-unproved` | a fold's step, assuming the invariant of its accumulator parameters, was not proved to keep it (or the rule declined that step; the message says why) |
| `abstract-refinement-too-weak` | the predicate instantiated from the passed callable does not imply the demand; see [Abstract refinements](#abstract-refinements-filter-keeps-what-its-predicate-says) |
| `abstract-refinement-uninstantiated` | the abstract refinement could not be instantiated from what was passed (a callable with no proved contract, a lambda body the reader does not translate, a name bound twice, …); the message names why |
| `refuted-unconfirmed` | the solver refuted the goal on some path, but no concrete input was found on which the function returns a violating value (Tier 2 induction), so nothing is reported |
| `solver-undecided` | the solver proved neither the predicate nor its negation |

`unconstrained-subject`, `partial-conjunct`, `opaque-application`, and
`nonlinear-goal` are also refinements of `solver-undecided`: the VC was built and the solver ran, and each
names a more specific reason the solver could not decide it.

`alias-withdrawn` is a further refinement of `solver-undecided`, not a separate
failure: the VC was built and the solver ran, it just arrived without the fact
that would have discharged it. It is reported separately because the *action*
differs: the call is already guarded, and what has to change is a name binding
elsewhere in the unit. See [the alias-withdrawal note](#a-withdrawn-alias-names-itself)
below.

**Where a skip is reported differs by reason.** `unconstrained-subject`,
`partial-conjunct`, `opaque-application`, `unreflectable-predicate`, and
`unreflectable-subject` print at every call site that has one, because each
of their messages now names the specific sub-expression or argument that
failed, so repeating it is a distinct fact each time, not the same line
twice. Three residual reasons (`solver-undecided`, `sort-conflict`,
`float-sort-gate`) keep the older, once-per-module throttle: one hint per
module, because their message says the same thing regardless of which call
raised it, so repeating it at every site would be noise, not information. A
diagnosed reason's message does not repeat: "no fact ... constrains `n`" and
"`_ >= 0` established here; `_ < len(xs)` not" describe different calls, so
suppressing the second because the first already printed would hide a real
finding.

**Which one gets blamed.** A call's argument (the "subject") is reflected
first; if that reflection fails, the whole call is filed as
`unreflectable-subject` naming the argument, and the predicate is never even
reached. Only when the subject itself reflects fine does a further failure
get filed as `unreflectable-predicate`, naming the innermost sub-expression
of the predicate that had no translation. The same rule applies to a
postcondition: the function's own return expression is the subject there, so
a return expression that fails to reflect is `unreflectable-subject`, not
`unreflectable-predicate`, even if the postcondition itself is unrelated. One
gap: a predicate that never reaches the bare subject at all (it only applies
a measure to it, or passes it to an opaque call) still blames the predicate
when it is itself unreflectable, even though the subject may also be opaque;
distinguishing that case would need reflecting the subject speculatively,
which risks forcing work that would not otherwise happen (see the induction
hazard note in `specs/progress/2026-09-02-unreflectable-predicate-attribution.md`).
A sibling parameter's actual (not the refined parameter's own subject, but
another argument the predicate mentions by name) is not covered by this rule
yet and still blames the predicate; see the same progress note.

Two generated examples, one per reason:

```
$ march --check test/native/simd_lane_panic.march

-- HINT -- test/native/simd_lane_panic.march

precondition `0 <= _ && _ < 4` on `Simd.extract_i32x4` was NOT verified here.
the argument `lane(1)` could not be translated to SMT, so no goal was built

25 |     println(Simd.extract_i32x4(v, lane(1)))
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

`lane(1)` is a call to an unrefined function, so its own value could not be
reflected; the predicate `0 <= _ && _ < 4` is never reached.

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

Here the subject (`7`) reflects fine; `is_prime` is an ordinary function, not
a measure or a supported predicate operator, so the predicate itself has no
SMT translation, and the message names it.

`alias-withdrawn` follows neither rule: outside `cap verified` it prints no
hint at all, not even once per module. It still counts toward
`--refine-report`'s skip totals, and under `cap verified` it becomes its own
error; see [the alias-withdrawal note](#a-withdrawn-alias-names-itself) below.

```
$ march --check <file>

-- HINT -- <file>

precondition `len(_) > 0` on `head` was NOT verified here.
no fact the checker derived constrains `ys`

10 |     head(ys)
         ^^^^^^^^
```

The residual reasons still print the longer canned paragraph, unchanged:

```
-- HINT -- <file>

precondition `len(_) > 0` on `head_of` was NOT verified here.
reason: solver-undecided — the solver proved neither the predicate nor its negation
note: March reports only definite failures, so a contract it cannot decide
is accepted in silence. Add `cap verified` to this module to make every
unverifiable obligation an error instead; `--refine-report` lists them all.
```

Under `cap verified` the same split holds, just escalated to an error instead
of a hint; see [`cap verified`](#cap-verified-turning-silence-into-an-error)
below for the exact rendering.

The ledger records both **precondition obligations raised at call sites** and
**postcondition obligations**: a function's own return value checked against
its declared return refinement. Each obligation includes a `kind` (precondition
or postcondition; the line's third column, `division`, is the kind
`Obligation.Division` reserves for a `cap no_panic` divisor), printed as a `by kind`
breakdown line under each slice's headline; the headline totals themselves do
not distinguish kinds; a proved postcondition is a proved obligation like any
other. `cap verified` escalates an undischarged precondition *and* an
undischarged postcondition; see below.

---

## Getting a contract proposed for you: `forge refine`

`--refine-report` tells you an obligation went unproven; it does not tell you
what contract would have proved it. `forge refine <fn>` (equivalently
`march --refine-suggest <fn>`) answers that question:

```
$ forge refine split
lib/text.march:10  split
    n : Int  ->  n : {Int | _ > 0}
  discharges all 1 unproven obligation(s)
```

The mechanism matters more than the output. The obligation ledger records a
span, a callee and a verdict; it does **not** record which parameter is to
blame, and there is no truthful way to recover that after the fact, since an
argument is an arbitrary expression over several parameters. So the tool does
not attribute anything. It hypothesises a refinement onto the signature,
re-runs the *real* checker over the function **and every caller of it in the
unit**, and keeps the candidate only if, site by site, it proves at least one
obligation, breaks none, and creates no violation. A candidate that would turn a
caller's call into a violation is reported as `refused (caller-violation)` with
that call, not proposed.

Two consequences follow, both intentional:

- **A suggestion cannot over-claim.** It exists because `Refine_check` proved
  something under it, so `march check` after applying it reports what the tool
  predicted. There is no parallel VC generator to drift.
- **A suggestion cannot exceed the checker.** Where the checker is incomplete
  (a `len(xs)` fact that does not propagate from a caller to a callee, say), the
  tool reports `no candidate refinement discharges any of them` rather than
  proposing a contract that would not, in fact, help.

Where several candidates verify, the **weakest** is proposed: `_ != 0` before
`_ > 0`, `_ >= 0` before `_ > 0`, `_ < len(xs)` before
`_ >= 0 && _ < len(xs)`. A contract narrows the set of callers a function
accepts, so proposing a stronger one than the body needs is a real cost, not a
harmless conservatism.

The grammar is finite by design (sign and non-zero contracts on `Int`/`Float`,
`len(_) > 0` on `List`/`String`, index contracts against each list or string
parameter in the same signature). It will miss contracts it cannot spell; it
will not invent one it did not prove.

See [`forge refine` in the Tooling guide](../../docs/tooling.md#forge-refine-suggest-a-refinement-type)
for the per-function command surface, including `--apply`, `--all`, `--budget`
and the editor code action.

The per-function tool proposes a parameter contract for one function, from a
fixed grammar. With `--postconditions` it proposes a return contract instead.

To propose **every** kind of refinement the checker can verify, use
module-wide inference. It works over a whole module or project at once, and it
covers returns, element and abstract refinements, and fold accumulators.
Preview the edits with `--diff`, and write them with `--apply`. See the next
subsection.

```
march --check --refine-infer FILE   # one module
forge refine --infer                # the whole project
```

### Module-wide inference: `march --refine-infer` and `forge refine --infer`

`--refine-infer` runs the same assume-and-re-check loop over every function in
user code. It covers every kind of refinement the checker can verify:

| Kind | Example proposal |
|---|---|
| scalar parameter / return | `b : {Int \| _ != 0}`, `: {Int \| _ > 0}` |
| relational | `i : {Int \| _ < n}` (a demand a callee makes, re-spelled in the caller) |
| element parameter / return | `xs : List({Int \| _ > 0})`, `: (List({Int \| _ > 0}), Int)` |
| abstract | `pred : a -> Bool[p]` with `: List(a[p])`, `Option(a[p])`, or `partition`'s `(List(a[p]), List({a \| !p(_)}))` |
| fold accumulator | `fn (acc : {Int \| _ > 0}, x) -> …` |

**Where candidates come from.** The program is mined first:

- the predicate a skipped obligation asks for;
- refinements already written in signatures the function can see;
- comparisons in its body.

Only then are candidates taken from the fixed grammar. Each slot gets at most
12, weakest first by implication.

**The search order.** The search is a fixpoint over the call graph, callees
first. Returns and abstract refinements are tried before preconditions,
because they cost no caller anything. A precondition moves the obligation to
the callers. A return that holds only through its tail call tries the
callee's return too. A return is proposed only when the checker proves it,
**and** some caller gets something from it.

**A precondition must prove a site, not delete it.** Take this function:

```march
pfn set_n(j : Int, n : Int, v) do
  if j >= n do v else set_n(j + 37, n, Array.set(v, j, 0 - j)) end
end
```

`n : {Int | _ <= j}` closes the `Array.set` index obligation only because the
`else` can no longer run. So for each site a precondition closes, the checker
also asks whether any execution still reaches it. A site that is reachable
without the precondition and dead with it does not count for the proposal. If
no other site is left, or too few to pay for the obligations the precondition
adds at its callers, the candidate is rejected as `vacuous-branch`:

```
  set_n: rejected (vacuous-branch) param n : _ <= j
    closes `Array.set` at array_trie_drop_leak_probe.march:46:26 only by making its branch unreachable
```

A precondition that proves a real site, and as a result also makes a branch
dead, is still proposed. The dead branch's site still counts in its total.

```
$ march --check --refine-infer app.march
inferred refinements: 2 proposed, 1 refused; user skips 3 -> 1 (58 probes, 2 rounds)
  pos_only (app.march:4)  return/elem : List({Int | _ > 0})  [element-return, closes 1]
  total (app.march:6)  param xs/elem : List({Int | _ > 0})  [element-param, closes 1]
  go: refused (caller-violation) param n : _ > 0
    would break the call at app.march:9:21
```

**Previewing and applying.**

- `--refine-infer-diff` prints the edits as a diff.
- `--refine-infer-apply` writes them, through the same splicer the editor's
  code action uses. Then it re-checks the program. If the result is not
  exactly the predicted one, it reverts every edit and exits 3. A mismatch is
  a bug in the tool, never something to fix by hand.
- A second run after applying proposes nothing.

**For a whole project, use `forge refine --infer`.** It runs inference over
the project as one checked unit, so a caller in another file counts. A project
that does not check as a unit is tried one file at a time. `--apply-public`
and `--allow-caller-violations` pass through. `--fixpoint` is now the same
thing as `--infer`. The
[Tooling guide](../../docs/tooling.md#infer-every-contract-forge-refine---infer)
covers the command in full.

```
forge refine --infer            # print the proposals
forge refine --infer --diff     # print them as a diff
forge refine --infer --apply    # write them, then re-check
```

**Other outputs and switches.**

- `--refine-infer-json` emits the same results as JSON (version 1).
- With `--refine-report`, the report also prints the ledger as it will be once
  the proposals are applied. For a `cap verified` module, it also says how
  many of the module's errors they close.
- `--refine-infer-kinds` restricts the kinds, as in `--refine-infer-kinds k1,k4`.
- `--refine-infer-budget N` caps the probes. The default is 3000.
- `--allow-caller-violations` accepts a refused precondition.

```
refinement obligations (user code, if applied): …
```

**In the editor**, the code actions "Infer refinements for `f`" and "Infer
refinements in this file" run the same inference and apply the same bytes. A
precondition that adds unproven obligations at its callers is marked as
needing confirmation.

A proposal on a public function with no caller in the unit is marked, because
its real callers are elsewhere. Nothing is proposed for a program that does
not check.

**It cannot exceed the checker.** Like the per-function tool, it never
proposes a contract the checker does not prove, however natural. Three
examples it misses today:

- a relational element return built by `List.filter` with a captured bound;
- an `Option` return through a local `fn`;
- a return that holds only through a callee's return.

The v1 limits are:

- a one-argument container's element slots only;
- an `Int` literal as a fold accumulator's initial value;
- no mutually recursive functions, which are reported `scc-unsupported`.

---

## Coverage audit: does the checker even look at this refinement?

`--refine-report` counts obligations that were actually filed. It has
nothing to say about a declared refinement that never reaches a
goal-building call site at all, because no code path in the checker ever
looks at that position. `--refine-audit` (`lib/refinecheck/refine_audit.ml`)
answers that prior question directly: for every `{Base | pred}` written
anywhere in the module, does any extractor in the checker ever consult it?

```
$ march --check --refine-audit stdlib/list.march
coverage audit (user code): 7 enforced, 0 inert (warned), 0 unenforced
coverage audit (user + stdlib): 63 enforced, 0 inert (warned), 0 unenforced
```

Every declared refinement lands in exactly one of three buckets:

- **Enforced**: the checker's own extractor for this position accepts the
  declared type, so an obligation gets filed against it (at a call site for
  a parameter, or against the function's own body for a postcondition). A
  parameter with no caller yet still counts Enforced: what matters is that
  the position is wired into the checker's scope machinery, not whether a
  call site exists today. See below for why this reading is correct rather
  than a loophole.
- **Inert (warned)**: a `sig` entry, an `extern` signature, or an
  `interface` method whose refinement the compiler already names in its own
  warning. Nothing new here; the audit confirms that warning still fires.
- **Unenforced**: declared, silent, and nothing tells you. No extractor
  ever reads this position, so a value violating the written predicate is
  accepted without complaint.

Every `Unenforced` site prints one line, naming the file position, the
enclosing declaration, the predicate, and the specific reason no extractor
reaches it. For:

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

`f`'s parameter and return are both Enforced. Only `Box.v`'s field
refinement is Unenforced. There is no extractor for a stored field at all,
only for a parameter, a return, or a let-binding. The `user + stdlib` total
(65) is this file's own 2 sites plus the 63 the shipped stdlib always
contributes.

### Why an uncalled parameter still counts as Enforced

This is the design's central subtlety. Enforcement is not a property of
having a caller; it is a property of the checker's scope machinery accepting
the declared type at all. `refined_param_ty` running over
`fn f(n : {Int | n > 0}) : Int do ... end` registers `n > 0` as a fact
inside `f`'s body and would raise an obligation at *any* call site, present
or future. Adding one tomorrow gets checked automatically, because the
position is already wired in. This is the same distinction
`--refine-report` already draws between an obligation that is unproven and
one that was never filed; the audit stays consistent with it instead of
inventing an incompatible second notion of "checked."

A lambda's own parameter (`fn (n : {Int | n > 0}) -> n`) was the textbook
case of "genuinely Unenforced rather than merely uncalled" until 2026-09-13:
no scope machinery ran over an `ELam`'s parameters, so *no* call through it
was ever obliged. A `let`-bound lambda is now a local function for the
checker (direct calls obliged through the callee environment) and passing
any refined callable is obliged at the pass site, so the position reports
Enforced; see the Limitations section's higher-order entry.

### Where the current baseline stands

A sweep of the corpus `scripts/refine-oracle.sh` already walks
(`test/native/*.march` and `stdlib/*.march`, ~300 files) finds 63 declared
refinements, every one Enforced: zero Unenforced, zero Inert. That result is
committed at `test/refine_audit/corpus.baseline` and ratcheted in CI
(`.github/workflows/ci.yml`'s "Refinement coverage audit ratchet" step,
beside the existing obligation ratchet). It is regenerated the same way the
TIR golden snapshots are:
`UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe -e`.

An empty baseline over real code is a true finding, not evidence the audit
does nothing, but an audit that silently broke would also report an empty
baseline, which is why a second, deliberately non-empty fixture set exists:
`test/refine_audit/holes/`, one small program per known unenforced position
(a refinement on a tuple element; a fixture leaves the set when its
position becomes enforced, as twelve of them did on 2026-09-13, the two-layer
container one last),
pinned at `test/refine_audit/holes.baseline`. If that baseline ever reports
zero Unenforced sites, the audit itself is broken; the test that diffs it
fails loudly rather than passing.

The positions currently known to be Unenforced, none of which the corpus
above happens to exercise. Unenforced cuts both ways: since 2026-09-13 the
checker also walks an escaping lambda's or block-level `fn`'s body (and a
handler's, when its message name clashes) with those parameter refinements
*stripped* from scope, exactly as it already did for a non-adoptable `impl`
method. Before that, the body assumed
`n > 0` from a `fn (n : {Int | n > 0}) -> need(n)` while `g(0)` obliged
nobody, and `cap verified` accepted the program. The plan that turns each
position into a real contract, obligation and assumption together, is
`specs/plans/2026-09-13-refinement-enforcement-holes-plan.md`.

- (Closed 2026-09-13.) A lambda's own parameter: a `let`-bound lambda obliges
  its direct callers like a block-level `fn`, and passing any refined
  callable is obliged at the pass site (see the higher-order limitation
  entry). A lambda that is returned or stored, and called later through a
  field, is the same gap a top-level function has.
- (Closed 2026-09-13.) A block-level `fn`'s own parameter and return type are
  now enforced: every direct `inner(...)` after the definition, and every
  recursive call inside it, is obliged through the callee environment, and
  the return refinement is verified against the body. The body assumes its
  parameter refinements only while `inner` never escapes callee position
  (returned, aliased, or passed where the pass-site check cannot oblige it);
  an escaping local is walked with them stripped. See
  `specs/progress/2026-09-13-block-fn-refinement-enforced.md`.
- (Closed 2026-09-13.) An `impl` method's parameter when the method's bare
  name is not adoptable (more than one `impl` defines it, or a top-level
  `fn` shares the name): the call is now resolved by the *first argument's
  type*, the rule compilation dispatches by, and checked against that
  impl's own contract. A call whose receiver type the typechecker cannot
  name (a type variable, no or several matching impls) is a recorded skip,
  counted by `--refine-report` and an error under `cap verified`. The
  method body still assumes its parameter refinements only when the name is
  adoptable; obliging callers without letting the body assume is sound.
- (Closed 2026-09-13.) An actor's state field: an inductive invariant. The
  state's refined fields are obliged at `init` and at every handler's result
  (an update `{ state with ... }`, or a fresh literal at a tail), and assumed
  of the incoming `state` in every handler body.
- (Closed 2026-09-13.) A handler's own parameter: `on Inc(n : {Int | n >
  0})` obliges every construction of `Inc(...)` in the program (`send`,
  `Actor.call`, a message bound to a `let` first), and the handler body
  assumes `n > 0` exactly then. Fail closed: a message name defined by two
  handlers, or shared with a variant constructor, is neither obliged nor
  assumed. **Trust boundary:** a message arriving from a remote node was
  built by code this compiler did not check; the handler's assumption is
  stated here as that boundary, not enforced across it.
- (Closed 2026-09-13.) A record field or a variant constructor argument:
  every construction is obliged — a record literal (typed by its field set;
  two types of one shape make it ambiguous and it is not obliged, fail
  closed), an update `{ r with f: e }` for the updated fields, a constructor
  application `W(e)` — and every reader of the field through a
  record-typed variable assumes it. A `linear` wrapper is transparent.
  Program-wide, two constructors (or a constructor and an actor message)
  sharing a name withdraw the contract, neither obliged nor assumed.
- (Closed 2026-09-13.) A refinement inside a registered container's type
  argument — `List`, `Option`, `Result`, a user variant such as `Tree({Int |
  _ > 0})`, any stdlib type defined as one, and nested containers
  (`List(List({Int | _ > 0}))`) — is a contract on
  every value flowing into the position — a literal element-wise, a
  container-typed variable by element implication (its own element
  refinement must imply the expected one, refuted with a witness element
  otherwise), anything else a recorded skip — at a parameter, a return, an
  annotated `let`, or a field; and a fact about every element a `match`
  takes out (`Cons(h, t)`, `Some(x)`, `Node(_, x, right)`); a polymorphic
  call carries it through its declared signature (`let h = first(xs)` with
  `first : List(a) -> Option(a)`; `let x = List.head(xs)` gives `x` the
  refinement itself), refusing any callee that could manufacture an element
  (`put(xs : List(a), v : a)`). Still unenforced: a tuple element, an arrow
  side, a second layer of a stacked refinement, and a type with no registered
  constructor model.
- (Closed 2026-09-13.) A `{String | ...}` return type is verified against
  the body: a literal tail and the predicate's literal meet on one `Str`
  constant, `len(_)` is the returned string's byte length, and a String
  built by a call is a recorded skip. Its postcondition does not yet
  propagate to callers.
- (Closed 2026-09-13, with one shape left open on purpose.) A refined
  default parameter obliges a full-arity call: `f(1, 0)` resolves to the
  `f$2` arity variant the runtime dispatches to. A multi-head function
  keeps its first head's declared types through the clause merge when that
  head dominates (no guard, every parameter a plain variable), so its
  refinement is the function's contract; a refinement on a non-dominating
  head is still dropped, since another head may legitimately handle the
  value, and the audit keeps reporting it. See below.

See `specs/todos/2026-09-03-lambda-param-refinement-unchecked.md`,
`specs/todos/2026-09-03-impl-method-param-refinement-unchecked.md`,
`specs/todos/2026-09-03-actor-state-and-handler-refinement-unchecked.md`,
`specs/todos/2026-09-01-nested-refinement-enforcement.md`,
`specs/todos/2026-09-03-string-return-refinement-unchecked.md`, and
`specs/todos/2026-09-03-desugar-dropped-refinement-unchecked.md`.

### Why the audit needs the pre-desugar AST too

A whole-plan review of this design found two shapes where the POST-desugar
declaration list alone is not enough:

- A multi-head function's clause merge rebuilds every parameter with no
  declared type at all, so a refined parameter on one of the original
  clauses is not `Unenforced`; it is simply absent, with no site and no
  disposition, which is worse than a false negative.
- A default-argument function survives desugar only under mangled
  arity-variant names (`f$2`, `f$1`, ...). A refined parameter on the
  survivor used to report `Enforced`, correctly describing what the
  checker's extractor accepts at that decl, but incorrectly implying a
  plain call `f(...)` is covered by it: no decl named `f` remains, so no
  such call resolves to anything refined.

Both are fixed by diffing the pre-desugar site list against the
post-desugar one: a pre-desugar site with no matching post-desugar
occurrence (same enclosing declaration name and predicate text) is reported
`Unenforced`, overriding whatever a post-desugar site at a similar position
would otherwise say. `Return` is the one exception: it matches by predicate
text alone, not by name, because a postcondition is checked against a
function's own body with no notion of a caller, so a default-argument
function's renamed full-arity variant is still correctly `Enforced` for its
return type even while its parameter is not. Confirmed directly: `fn f(a :
Int, b : Int \\ 1) : {Int | _ > 0} do a - b end` called as `f(0, 5)` still
errors under `cap verified` (`f$2` does not satisfy its return type
constraint), unaffected by this fix.

```
$ march --check --refine-audit --refine-report t6e.march
coverage audit: t6e.march:3:27: param `f` #1: b > 0: this refinement was declared here, but no occurrence with the same enclosing name and predicate text survives desugaring: either the declared type was discarded entirely (a multi-head function's clause merge drops every parameter type before the checker ever sees it) or it now lives only under a mangled name a plain call cannot resolve to (a default-argument function's arity variant, e.g. `f$2`). See specs/todos/2026-09-03-desugar-dropped-refinement-unchecked.md.
coverage audit (user code): 1 enforced, 0 inert (warned), 1 unenforced
```

(`t6e.march` is `fn f(a : Int, b : {Int | b > 0} \\ 1) : Int do a + b end`,
called as `f(1, 0)`.) Pinned at `test/refine_audit/holes/default_param.march`
and `multi_head.march`; `type_arg.march`, `arrow_domain.march`, and
`linear_wrapper.march` add fixtures for the three nested positions this
list already named but the holes set had not yet covered (a whole-plan
review finding). This comparison covers only the entry file and its
resolved imports, not the shipped stdlib, which a sweep already established
contains neither shape today.

`Refine_check.check_module` takes this pre-desugar list as an optional
`?pre_desugar_decls` argument alongside `?audit`; omitting it (every caller
before this fix) keeps behavior identical to before.

---

## Promoting a skip: a demonstrated precondition failure

Most skips stay silent because the checker cannot *prove* anything either way.
A narrow slice is different: the checker can show the skip is a real bug. When
an argument reaches a refined parameter and the obligation is skipped, the
checker executes the *enclosing* function on the solver's model, watches for a
genuine `panic`, and then checks whether repairing just that one argument makes
the function return instead. If both hold, the skip is promoted to a warning
(an error under `cap verified`) instead of staying silent.

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

**What the warning claims, precisely.** It says `median` panics on some input
(`[]`), a fact about the caller. It does not say `percentile` raised that
panic incorrectly; `percentile`'s own contract, `len(_) > 0`, is exactly what
rules `[]` out, and `percentile` is not at fault for panicking on an input it
declared it does not accept. The bug is that `median` does not forward the
requirement it relies on.

**Status and offer.** Outside `cap verified` the promotion is a warning; inside
it, the same message is a compile error, worded identically apart from the
`WARNING`/`ERROR` banner. The `help:` block shows the precondition to declare
on the caller, and `forge fix` can rewrite the signature for you. Not every
promotion gets a `help:` block: when the callee has more than one unforwarded
precondition and no single-parameter fix is unambiguously correct, the
promotion still fires but the `help:` is omitted. A wrapper forwarding both
arguments of `Stats.quantile`, which requires `len(_) > 0` on its list and
`_ >= 0.0 && _ <= 1.0` on its float, is exactly this shape and reports with no
`help:` block. (`Stats.quantile_default` itself used to be that wrapper; since
2026-09-22 it declares both preconditions.)

### Promotion and the standard library

Promotion is not attempted at spans inside the standard library when the
stdlib is merely imported: those diagnostics are filtered from the printed
stream before promotion ever runs, so paying the execution cost there would
produce a count nobody could see. Compiling a stdlib file directly as the
entry file is different: its own spans are then user spans, not filtered
stdlib spans, and it reports its own promotions the same as any other module.

### The `violated` count

`--refine-report` records a promotion under `violated`, the same bucket used
for a contract the solver proved can never hold. A nonzero `violated` count on
a module without `cap verified` is therefore not necessarily a bad annotation;
it can be a demonstrated call-site failure the checker found on its own. The
report does not currently distinguish the two shapes.

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

## `cap verified`: turning silence into an error

March's default stance is **definite failure only**: a false positive on correct
code is the cardinal sin, so anything the checker cannot decide stays silent. A
module that wants the opposite bargain ("these contracts are a guarantee, not a
best effort") declares `cap verified`, and every obligation the checker cannot
discharge inside it — a **precondition at a call site**, or a **return
refinement** at a definition — becomes a compile error:

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
    if List.length(ys) > 0 do head_of(ys) else 0 end   -- proved; no error
  end
end
```

Dropping the guard entirely turns the same call into an error naming the
precondition, the callee, and why it could not be discharged. With nothing at
all constraining `ys`, the reason is `unconstrained-subject`:

```
`cap verified` module: cannot verify precondition `len(_) > 0` on `head_of`
(unconstrained-subject: no fact the checker derived constrains `ys`)
note: guard the call or strengthen what is known here, rewrite the predicate
into the fragment the checker supports, or remove `cap verified` from this
module — it asks for every obligation to be discharged
```

Weakening the guard instead of dropping it (`if List.length(ys) >= 0 do
head_of(ys) else 0 end`, which is always true and proves nothing) leaves a fact
in scope, so the reason falls back to the residual `solver-undecided`:

```
`cap verified` module: cannot verify precondition `len(_) > 0` on `head_of`
(solver-undecided: the solver proved neither the predicate nor its negation)
note: guard the call or strengthen what is known here, rewrite the predicate
into the fragment the checker supports, or remove `cap verified` from this
module — it asks for every obligation to be discharged
```

Note that if `head_of`'s `Nil` arm panics instead of returning a value, dropping
the guard produces a different error altogether: the checker can demonstrate
the panic, and the skip is *promoted* rather than reported as
`unconstrained-subject`. See
[Promoting a skip](#promoting-a-skip-a-demonstrated-precondition-failure) above.

### A withdrawn alias names itself

The measure aliases (`List.length`, `String.byte_size`, `string_byte_length`)
are withdrawn for the **whole compilation unit** the moment anything in it could
make the spelling denote a different function; see the shadowing rules under
each alias above. The gate is unit-global and syntactic on purpose: it does not
ask whether the competing binding could actually win at this call, because the
precise answer needs a resolver the pass does not have there, and the errors are
asymmetric (over-suppress = a missed proof, silence; under-suppress = a false
positive on correct code).

Under `cap verified` a missed proof is not silence, so a withdrawal is visible;
and it must not be mistaken for a solver failure. This program is guarded by the
exact idiom the alias exists for, and is still an error:

```march
mod Ver3 do
  cap verified
  mod Internal do
    mod List do
      fn length(xs : List(Int)) : Int do 99 end
    end
  end
  fn head(xs : {List(Int) | len(_) > 0}) : Int do 0 end
  fn go(ys : List(Int)) : Int do
    if List.length(ys) > 0 do head(ys) else 0 end
  end
end
```

```
`cap verified` module: cannot verify precondition `len(_) > 0` on `head`
(alias-withdrawn: the guard uses `List.length`, but this compilation unit also
BINDS that name, so the checker withdrew its built-in measure meaning and the
guard proved nothing)
note: at least one binding of `List.length` in this compilation unit
(ver3.march:5) withdrew the alias for the WHOLE unit, including this call — the
gate is unit-global and syntactic, so it does not matter whether that binding
could ever win here.  There may be others: renaming or moving every one of them
out of this unit restores the alias, and restating the fact as a refinement
avoids the guard entirely
```

The nested `length` is reachable only as `Ver3.Internal.List.length` and does
**not** win at runtime; the gate does not care, and that is the point of the
message. The same applies to a bare-name binding anywhere in the unit, including
one in an unrelated function (`let string_byte_length = n + 1`) or in a
`MARCH_LIB_PATH` dependency you never opened; the reported span is where to
look.

The note names *at least one* binding; a unit may hold several, and the alias
comes back only when every one of them is gone.

**Attribution is conservative, and the bar is causal relevance rather than mere
presence.** All four of these must hold, or the general `solver-undecided`
message stands:

1. the skip is a solver-undecided one (a withdrawal removes an assumption; it
   cannot cause an earlier reflection or sort failure);
2. the predicate applies the measure the alias routes to;
3. a **positive** path condition applies the withdrawn spelling **to this
   obligation's own argument**, either directly, or laundered through exactly
   **one** `let`: `let n = List.length(ys)` followed by `if n > 0` is the same
   author intent stopped by the same withdrawal. The laundered walk re-checks
   the *recorded application* against the obligation's own argument (so
   `let n = List.length(zs)` is not a guard on `ys`), and the recorded fact is
   shadow-disciplined: rebinding either the laundering name (`let n = 5` in
   between) or the collection itself (`let ys = zs` in between) retires it,
   and a two-`let` chain (`let a = List.length(ys)` then `let n = a`) stays
   general;
4. the spelling measures the same kind of thing as that argument: `List.length`
   for a list, `String.byte_size` / `string_byte_length` for a String.

Conditions 3 and 4 are what keep the reason from swallowing unrelated failures.
`if List.length(zs) > 0 do head(ys) else 0 end` is not a guard on `ys`: delete
the competing binding and it is undischarged all the same, so the withdrawal was
never the cause and "guard the call" is the correct advice. A negated guard,
`if List.length(ys) > 0 do 0 else head(ys) end`, does not fail to prove the
predicate: it *disproves* it, and with the binding removed reports a real
refinement violation, so it is never dressed up as a shadowing story. And since
all three spellings route to the single name `len`, condition 4 is what stops a
withdrawn `List.length` being blamed for an undischarged `{String | len(_) > 0}`.

The cost is coverage: a guard laundered through a **chain** of locals
(`let a = List.length(ys)` then `let n = a`), applied to a non-variable actual,
or established in a caller falls back to the general message. That is the
intended trade: the reason exists to explain one specific confusion, not to
claim every skip.

Verified 2026-07-29 (both triggers report `alias-withdrawn` with the causing
span; a guard on a different variable, a cross-measure guard, and a negated
guard all still report `solver-undecided`, each matched against a control with
the competing binding deleted). An unguarded call was `solver-undecided` too at
the time; since the diagnosed causes shipped it reports `unconstrained-subject`
instead, and `unconstrained-subject` is excluded from alias-withdrawal
attribution by condition 1 above the same way `solver-undecided` is. The
one-`let` laundered walk was
added and verified 2026-07-31: the laundered witness reports `alias-withdrawn`,
and its four wrong-attribution controls (a laundered guard on a *different*
collection, a rebound laundering name, a rebound collection, and a two-level
chain) all keep `solver-undecided`, with the negated laundered guard never
blamed.

### `@[trusted]`: a scoped, conspicuous escape hatch

`cap verified` is all-or-nothing at the module level: one obligation the
checker cannot discharge forces the author to either rewrite the predicate,
strengthen what the call site knows, or drop `cap verified` for the *entire*
module, even if every other function in it verifies cleanly. `@[trusted]` is
a per-**function** escape hatch: it accepts, as an assertion, whatever the
checker could not discharge inside that one function, without disarming the
capability for its siblings.

```march
mod Trusted1 do
  cap verified

  fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end

  @[trusted]
  fn go(zs : List(Int)) : Int do
    inner(zs)   -- SKIPPED (nothing here proves len(zs) > 0) --
                -- accepted as an assertion, not an error, because `go` is trusted
  end

  fn main() : Int do go([1]) end
end
```

Without `@[trusted]` the call inside `go` would be the exact `head_of`-style
error above. With it, the obligation is still recorded (as its **own**
verdict, `Trusted`, never folded into `proved`), so `--refine-report` shows
exactly how much of a module's "verification" is actually an assertion rather
than a proof:

```
refinement obligations (user code): 0 proved, 0 violated, 1 trusted, 0 skipped
```

**This is an intentional soundness hole, and it is scoped as narrowly as
possible on purpose:**

- **Only a `Skipped` obligation is eligible.** `@[trusted]` never suppresses a
  `Violated`: a predicate demonstrably violated — proved impossible by the
  solver, or refuted by a [counterexample that was actually
  run](#counterexamples-the-failing-input-in-source-terms) — is a bug in the
  annotation, not an incompleteness to wave through. `go() do inner(0 - 5) end`
  under `@[trusted]` still reports the refinement violation exactly as it
  would without the attribute; so does a `@[trusted]` function whose body a
  witness proves violates its own return contract.
- **Scoped to the one function that has the attribute.** A sibling
  function in the same `cap verified` module that is not itself `@[trusted]`
  is unaffected: one annotation does not silently disarm the module.
- **A no-op outside `cap verified` warns.** `@[trusted]` only changes anything
  inside the `strict_verified` escalation path; on a function in a module that
  never declares `cap verified` it warns that the attribute has no effect,
  rather than silently having no effect: the exact failure mode (an attribute
  that changes no behaviour, mistaken for one that does) this subsystem keeps
  producing.

Verified 2026-07-30. Corpus: `accept/t132` (an otherwise-undischargeable
`cap verified` module rescued by `@[trusted]`), `reject/t133` (a definite
violation inside a `@[trusted]` function is still reported).

**Scope and limits.** State these clearly before relying on it:

- **Strictly opt-in, and scoped to the decl list that declares it.** A
  `cap verified` module calling into an ordinary one does not make the callee's
  module strict: only obligations *raised* at call sites lexically inside the
  strict decl list escalate.
- **Not inherited by nested modules.** Intentionally: the compiler prepends the
  entire standard library as sibling module declarations, so an inherited flag
  would turn every stdlib module strict the moment one user module asked for
  verification.
- **Both preconditions and postconditions escalate (since 2026-07-30).** The
  ledger records both kinds (see `--refine-report` above), and `cap verified`
  now escalates a `Skipped` obligation raised at a call site *or* on a
  function's own return refinement: an undischarged postcondition is a
  compile error under `cap verified`, exactly like an undischarged
  precondition. This is the last place a fact was granted without obliging
  anyone; `cap verified`'s promise ("if it compiles, it is proved") now
  covers return refinements too. `@[trusted]` reaches this escalation the same
  way it reaches `check_call`'s. Bracketed by
  `reject/t134_refine_postcondition_strict_undischarged` (an undecidable
  return refinement under `cap verified`) and
  `accept/t135_refine_postcondition_strict_trusted` (the same function rescued
  by `@[trusted]`).
- **Every declaration form is traversed** (since 2026-07-29). The pass once visited
  only `DFn` and nested `DMod` and ended in a `| _ -> ()` wildcard, so calls
  inside an `impl` method, an `interface` default body, a top-level `let`, an
  actor handler or a `test` raised no obligation and could not escalate. Both
  this walk and `cap no_panic`'s division walk are now exhaustive over `A.decl`
  with no wildcard, so a new declaration form is a compile error rather than a
  silent hole. A `describe` block recurses and inherits the enclosing module's
  capability; a nested `mod` still re-derives its own.

  **What "traversed" does and does not buy you.** Traversing a body means obligations
  *raised inside it* are reported. Whether a **refinement written on an `impl`
  method's own parameter** is enforced is a separate question, and the answer is
  intentionally conditional:

  - The contract is adopted (registered so every caller must establish it)
    only when the method name unambiguously denotes it: no `fn` in the same
    module owns the name, only one `impl` defines the method, and (since
    2026-07-30) no `use` in the same declaration list imports the name. A call
    resolved by NAME cannot tell two impls' contracts apart, and checking
    correct code against a predicate it never touches is the failure this
    subsystem must never have.
  - The `use` side of that test **fails closed on a glob**. `use Other.{run}`
    is an enumerated import, so only `run` is withdrawn. `use Other.*`,
    `import Other` (a bare `import` parses to the *same* `UseAll`) and
    `import Other, except: [f]` name a module this pass cannot see, so whether
    they bind the method name is undecidable here and **every** `impl` method
    in that declaration list is withdrawn. `use Other` with no selector binds
    the module, not any bare name, and withdraws no name. Failing closed costs
    silence; failing open would cost a false positive.
  - The competition is assessed over **one declaration list**, and the review of
    this change examined both cross-list nestings end-to-end (2026-07-31). An
    enclosing `use` over a nested `impl` turned out NOT to be a hole: the call
    inside the nested module really dispatches to the impl, so adoption matches
    dispatch. The **mirror** shape (a `use` in a *nested* module shadowing an
    *enclosing* contract, reaching plain `fn` contracts as well as `impl`
    methods) was a live false positive at the time this was written and is
    now CLOSED; see item 6 in [Open holes](#open-holes-stated-as-of-2026-07-29).
  - When the name is ambiguous the refinement binds **no one**: the body is
    traversed with it stripped, so it cannot discharge anything either. Unenforced
    means unusable in both directions: never "assumed in the body but demanded
    of no caller", which is how `fn run(b, k : {Int | k != 0})` once made
    `m / k` provable under `cap no_panic` while `run(Box(4), 0)` compiled and
    then divided by zero.
  - A refinement written in the **`interface`'s own method signature**
    (`fn run : a -> {Int | _ > 0} -> Int`) is still **not** enforced at call
    sites. No body assumes it either, so it is a missing check rather than an
    unsound one, but do not rely on it. Put the refinement on the `impl`
    method's own signature instead. Since 2026-07-30 the pass warns about it
    outside `cap verified`; since 2026-08-03, inside a `cap verified` module
    this is promoted to an **error**, the same asymmetric-silence reasoning
    as the `check_call`/`check_post` escalation elsewhere in this section; see
    [A refinement in an interface signature enforces no contract](#a-refinement-in-an-interface-signature-enforces-no-contract).
  - The same is true of a refinement in a **`sig`** signature or an **`extern`**
    signature, and since 2026-07-31 both **warn** as well. A `sig` refinement is
    simply never read (the fix is the module's own `fn` definition); an
    `extern` one cannot be honoured at all, since the callee is not March code
    (the fix is a March wrapper, with the foreign result checked at run
    time). See
    [The same applies to a `sig` or an `extern` signature](#the-same-applies-to-a-sig-or-an-extern-signature).
- **`cap no_panic`'s divisor check tries to DISCHARGE before it rejects**
  (since 2026-07-29). Every outcome short of `Refine.Verified` is an error
  (that is what the capability promises), but "we could not reflect the
  predicate" is not itself an outcome. A divisor refinement outside the linear
  fragment is now passed to z3 anyway: `{v : Int | v * v > 0}` is exactly
  `v != 0` over the integers, and rejecting it was a false positive on a
  *complete* proof. Predicates that reflect but prove no fact (`v * v >= 0`,
  true of every integer) come back `Refuted`, and ones z3 cannot decide come
  back `Unverified`; both are still errors. Path conditions are reflected with
  their negations on both routes, so the `else` side of `if d == 0` discharges
  the obligation exactly as `if d != 0` does on the `then` side. Bracketed by
  `accept/t121` and `reject/t122`.
- **Every fact `cap no_panic`'s divisor check reads is retired when its name is
  REBOUND** (since 2026-07-29). The divisor is identified by bare name, and so
  are all three channels (the path condition, the refined parameter, the `let`
  value), so a `let`, a lambda parameter, a `match` binder, a `let?` pattern or
  a local `fn` that rebinds that name drops everything known about the outer
  variable. Without it, `if d == 0 do 0 else (let d = 0; 10 / d) end` passed
  `--check` and then panicked. Note the direction: unlike the refinement pass,
  where dropping a fact means silence, dropping one here means an ERROR, so the
  retirement is intentionally over-approximate: a guard is re-established by
  re-stating it inside the rebinding scope. `reject/t123`.
- **`@[trusted]` (since 2026-07-30) is a per-function escape hatch.** See
  [above](#trusted-a-scoped-conspicuous-escape-hatch). It accepts a `Skipped`
  obligation as an assertion (recorded as its own `Trusted` verdict, never a
  `Violated`), scoped to the one function that has the attribute.

### Open holes, stated as of 2026-07-29

Everything above states what these capabilities *do*. This is the complementary
list (what a reader must not assume), kept here rather than only in
`specs/todos/` so that no one reads a guarantee out of the absence of a
caveat. None of these is known to be *unsound* in the "assumed but unchecked"
sense; each is a check that does not happen.

1. **A refinement in an `interface`'s own method signature is unenforced.**
   No body assumes it either. Put it on the `impl` method's parameter.
2. **The measure-alias gates are unit-global.** One real competitor anywhere
   in the compilation unit (including in a `MARCH_LIB_PATH` dependency you
   never opened) disables `List.length` / `String.byte_size` /
   `string_byte_length` as measure aliases for the entire program. Under the
   default stance that is silence; under `cap verified` it is a build failure,
   which is why the `alias-withdrawn` reason exists.
3. **Postconditions are in the ledger and escalated (since 2026-07-30).**
   `check_post` records an obligation at every exit (proved, violated, or
   skipped with a reason), so `--refine-report` counts return refinements too,
   and `cap verified` now escalates an undischarged **return** refinement
   exactly as it already escalated an undischarged precondition.

   Since 2026-08-30 a return refinement that is violated for *some* input is
   an error in **every** module, not only a `cap verified` one, whenever a
   [counterexample](#counterexamples-the-failing-input-in-source-terms)
   confirms it by execution — `fn f(n : Int) : {Int | _ >= 0} do n end` no
   longer compiles anywhere. That is not a widening of the definite-failure
   stance but a stronger refutation search under it: the failing input was
   run and observed to fail, so it is a demonstrated bug rather than an
   undecided obligation. Contracts that remain genuinely undecided are
   untouched, and stay silent outside `cap verified` as before. The
   2026-07-29 composition work remains confined to `check_call`, though: a
   parameter's promise composes into a *call* in the body, but `check_post`
   still composes no list or ADT measure through a **postcondition**; that is
   a separate, still-open gap from escalation.
4. **`@[trusted]` now reaches postconditions too (since 2026-07-30).** It
   suppresses the escalation both `check_call`'s and `check_post`'s `note`
   perform, scoped to the one function that has the attribute.
5. **`collect_direct_names` in `lib/desugar/desugar.ml` is exhaustive over
   `A.decl` (since 2026-07-30) but still does not cover `interface`/`impl`
   METHOD names.** It determines which self-qualified spellings
   `strip_entry_self_qual` rewrites, so an entry module that declares the name
   only as a method keeps the qualified spelling, which is what makes
   `accept/t126` / `t127` discriminating. Anyone closing that residual must
   re-verify those two by mutation: folding method names in makes the entry
   module's `List.length(ys)` rewrite to a bare `length(ys)`, and both
   witnesses would then pass regardless of the behaviour they pin.
6. **CLOSED (2026-07-31).** A `use` in a NESTED module no longer loses to an
   ENCLOSING contract of the same name. `resolve_call`'s lexical walk over
   `modpath_prefixes` is now scope-aware: `ctx.uses` includes a third
   component, the modpath of the module that recorded it, and at each prefix
   the walk consults that prefix's own definition, then that SAME prefix's
   own `use`-imports, before falling outward to the next prefix. That makes a
   nested `use` beat an enclosing definition (matching runtime dispatch)
   while an outer module's `use` still loses to an inner module's own
   definition: the imbalance a naive "move the `use` step first" fix would
   have gotten backwards, since `ctx.uses` inherits into nested modules while
   declaration-list competition does not. Pinned by the `resolve-precedence`
   suite in `test/test_refinecheck.ml` (obligation-count assertions, since a
   correctly-resolved call and a silently-skipped one are both quiet) and
   verified against real dispatch with a two-file `MARCH_LIB_PATH` fixture.
   (The opposite nesting, enclosing `use` over a nested `impl`, was examined
   in the original review and was never a hole: adoption already matched
   dispatch there. Since 2026-07-30 a `use` in the *same* declaration list
   competes for adoption, glob imports failing closed.)
7. **`alias-withdrawn` attribution follows a laundered guard one `let` deep,
   and no deeper.** `let n = List.length(ys)` followed by `if n > 0` is
   attributed to the withdrawal (closed 2026-07-31); a chain
   (`let a = List.length(ys)` then `let n = a`) still falls back to the
   general `solver-undecided` message even when the withdrawal really was the
   cause. A related pre-existing approximation is unchanged: condition 3
   checks that the guard *applies the spelling to the argument*, not that the
   guard would have *discharged* the obligation, so `if List.length(ys) >= 0`
   is attributed to the withdrawal although `len >= 0` proves no fact about
   `len > 0`, identically in the direct and laundered spellings. On the
   laundered path, a mention of the laundering name is counted only when it is
   FREE: a lambda parameter in the guard that only collides with the name
   is not evidence (fixed 2026-07-31 after review; `expr_mentions_free`). The
   DIRECT path retains the mirror-image pre-existing hole: an application
   under a binder that shadows the subject (`fn ys -> List.length(ys) > 0`
   passed to a combinator) still counts. Logged in `specs/todos/`; fixing it
   changes direct-path behavior that predates the laundering work.

---

## `cap no_panic`: Divisions That Can't Panic
{: #cap-no_panic--divisions-that-cant-panic}

`cap verified`'s sibling takes the same "silence is not good enough" stance and points
it at one specific runtime panic: integer division by zero. Declare `cap no_panic` in a
module and **every** `/` and `%` in it must have a divisor the checker can prove
non-zero. Anything short of a proof is a compile error: that's the whole promise, and
it's why this capability fails closed where the default refinement stance fails open.
(The implementation history of each rule below is in the `cap no_panic` bullets under
[`@[trusted]`](#trusted-a-scoped-conspicuous-escape-hatch)'s "Scope and limits".)

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

  fn main(_cap : Cap(IO.Console)) do
    println(int_to_string(scale(2) + guarded(5)))
  end
end
```

Both of those are accepted. `v * v > 0` is exactly `v != 0` over the integers, and the
checker passes such a predicate to the solver rather than declining to read it:
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

  fn main(_cap : Cap(IO.Console)) do
    println(int_to_string(run(Box(2))))
  end
end
```

Add an `if n != 0` guard and it's accepted: the walk reads the body, it doesn't just
distrust it. Top-level `let`s, `interface` defaults, actor handlers, `app` hooks and
`test` bodies are covered the same way.

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
it; the two passes share one adoption rule (`Refine_check.adoptable_impl_methods`) so
they can't drift apart. See the "What 'traversed' does and does not buy you" note under
[`@[trusted]`](#trusted-a-scoped-conspicuous-escape-hatch) for when that adoption
happens.

---

## Limitations

Refinements are intentionally a *pragmatic slice* of dependent typing. Know the
edges:

- **`Int`/`Bool`/`Float` values, record fields, `String` (narrowly), plus ADT
  constructor *tags*.** `Float` refinements are **comparisons only** (`>= > <=
  < == !=` against float literals or another float value); float **arithmetic**
  inside a predicate (`_ +. 1.0 > 0.0`) is out of scope and makes the whole
  predicate skipped rather than guessed at (see
  [Float Refinements](#float-refinements)). A predicate may range over the
  `Int`/`Bool` **fields of a record** (see
  [above](#refining-a-record-over-its-fields)); a record field
  of an unreflected type is opaque, but only that field; its siblings are
  still checked at a call site. `String` supports only
  `len` and literal equality (see
  [String Refinements](#string-refinements)). Over a **variant**
  (multi-constructor) ADT the checker reasons about the constructor tag only
  (`is_Some(_)`), never the payload: `{Option(Int) | is_Some(_)}` is checkable,
  a predicate about the `Int` inside is not. (A refinement on the payload's
  *type*, `Option({Int | _ > 0})`, is an
  [element refinement](#element-refinements-refining-what-a-container-holds)
  and is checked.) **Sets of elements** are
  supported through the set vocabulary (`elts`, `keys`, `member`, `subset`,
  …; see [Set Refinements](#set-refinements)), with cardinality through
  ground facts only and list structure only inside a proof by recursion.
  Refinements over
  other types aren't supported.
- **A tag refinement composes only for the constructor the caller promised.**
  A constructor literal or a `match` narrowing establishes the fact where the
  call is written, and, since 2026-07-29, so does the caller's own parameter
  contract: forwarding a `{Option(Int) | is_Some(_)}` *parameter* to a function
  expecting the identical contract is proved (`2 proved, 0 skipped`). A
  *different* constructor is intentionally not assumed: with
  `outer(p : {Option(Int) | is_None(_)})`, the call `inner(p)` against
  `is_Some(_)` stays **skipped** rather than reported, even though the two
  testers are exclusive. See [A Parameter's Own Contract Is a Fact Inside Its
  Body](#a-parameters-own-contract-is-a-fact-inside-its-body).
- **A refined `let` annotation is CHECKED against its bound expression**
  (since 2026-07-30). `let ys : {List(Int) | len(_) > 0} = []` is a refinement
  violation reported at the `let` ("bound expression does not satisfy type
  annotation `len(_) > 0`"), not a fact the checker adopts. Conversely, a
  `let` annotation that *is* proved does grant its fact: `let ys : {List(Int) |
  len(_) > 0} = [1]` followed by `inner(ys)` proves both obligations. Until that
  date the annotation was believed on sight: it entered the scope channel
  unconditionally, so a later call needing a non-empty list was reported
  **proved** off an assumption no one had established, and `cap verified` (its
  promise being "if it compiles, it is proved") accepted the module. That made
  a `let` annotation the one refined position in the language that obliged
  no one.

  The obligation is the ordinary one, with the ordinary stance: the annotation
  is checked exactly as a call's argument is checked against a parameter's
  precondition, so an expression the checker can neither prove nor refute is
  **skipped**, never reported. An unproven annotation also **grants no fact**:
  it is not simply unverified-but-trusted. In

  ```march
  fn go(zs : List(Int)) : Int do
    let ys : {List(Int) | len(_) > 0} = zs
    inner(ys)
  end
  ```

  the annotation is undecidable (no fact is known about `zs`), so it is skipped
  *and* `inner(ys)` is skipped too, rather than proved off an assumption the
  binding failed to establish. All three spellings of the refined value behave
  alike: `_`, a declared binder (`{v : List(Int) | len(v) > 0}`), and the bound
  name itself (`len(ys) > 0`).
- **A contract that contradicts its own guard makes the guarded branch
  provable as dead code.** In `fn outer(ys : {List(Int) | len(_) > 0}) do if
  List.length(ys) == 0 do inner(ys) else 0 end end` the guarded call *proves*:
  the caller's promise and the guard cannot both hold, so the branch is dead
  code and its obligation is discharged against an unsatisfiable path. This is
  expected and safe-direction (the call can never execute with a violating
  value), not a gap in checking.
- **A caller's own contract forwards through a call, including when it mentions
  another parameter.** `fn pick(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)})`
  calling `at(xs, i)` (where `at` declares the same contract) *proves*. Until
  2026-08-03 it did not: the assumption side mapped every name that was not the
  refinement's own subject to no value, and a single such name discarded the whole
  predicate, so the call was silently unchecked. A promise is retired when any
  name it mentions is rebound between the parameter and the call, so a shadowed
  name never lends its fact to a new binding.
- **A local `let` carries a fact forward only for a simple `Int` value.**
  An integer literal, an `Int` variable, `+`/`-`/literal-`*` over those, or an
  `if` of them (see "A local `let`" above). `let u = [1, 2]` then `inner(u)`
  against a non-empty contract is skipped, as is any other non-`Int` binding;
  pass the value directly or restate the fact with `assert`.
- **Incomplete (by the definite-failure stance).** The checker catches values
  that are *definitely* wrong and stays silent otherwise. It will not prove
  every true property; quantified/measure facts in particular sometimes return
  "unknown" and are skipped. This never produces a false positive, but it does
  mean some real guarantees go unchecked.
- **Two higher-order shapes are checked; the rest are not.** A call made
  *through* a refined function-typed parameter is checked:
  `fn ap(f : ({Int | _ >= 0}) -> Int) : Int do f(-3) end` is now rejected,
  exactly like a direct call to a function with a parameter that has that same
  refinement. So is a call through a **local alias** of a named function:
  `let g = takepos  g(-3)` is rejected when `takepos`'s parameter is refined.
  Both are single-argument shapes only (a curried or tupled multi-argument
  callback type is out of scope, and fails typecheck on any call regardless).
  Checked since 2026-09-13, at the **pass site** (contravariant subtyping):
  passing a refined callable — a named function, a `let`-bound lambda, a
  block-level `fn`, or an inline lambda — where a function type is expected
  is allowed only if that type's *domain* implies the callable's own
  parameter refinement for every value. `apply(f : Int -> Int, x : Int)`
  called as `apply(take_n, -3)` is therefore rejected at the pass of
  `take_n`, with a witness (`-1`), because `Int` promises nothing and
  `true ⇒ _ >= 0` is refuted; it was the accept witness `t77` until then and
  is `reject/t77_refine_hof_pass_site_rejected.march` now. The remedy is
  unchanged: refine the higher-order function's *own* parameter type
  (`f : ({Int | _ >= 0}) -> Int`), which both discharges the pass and obliges
  the call inside. A domain spelled as a type variable (`List.map`'s) promises
  nothing either, so passing a refined function to a generic combinator is
  rejected the same way. Scope: the passed callable must have exactly one
  parameter; a multi-parameter callable is neither obliged nor assumed.
  Still **not** checked:
  - inferring a higher-order function's own requirement from its body: the
    checker never looks inside `f` to derive what `f` needs, it only checks
    what the caller's own declared type or a resolvable alias already states;
  - dispatch through an `interface`/`impl`: which concrete implementation
    runs is not resolved by this pass, so no refinement travels through it.
- **Why general higher-order/polymorphic flow is out of reach by construction,
  the architectural limit.** `TRefine` (the internal type-carry for `{T |
  p}`) is intentionally **transparent to unification**: `repr` strips it to the
  base type, which is what keeps refinements invisible to `occurs`,
  generalization, instantiation, and the rest of the ~35 sites that canonicalise
  through `repr`; only 8 sites needed bespoke handling. But the same
  transparency means a refinement persists only where it is *not unified*,
  i.e. on a function's own declared parameters at a direct call. The moment a
  refined function's type is unified against a polymorphic slot (`apply(f, x)`
  with `apply(f, x) = f(x)`), unification strips the predicate before the
  callee's body sees it at all, so `apply(take_n, -3)` typechecks even though
  `take_n : {Int | _ >= 0} -> Int`. This is not a missing case to fill in; it
  is what transparent-`repr` `TRefine` means. The only known route past it is
  making refinements *participate* in unification as a subtyping relation
  (`{T | p} <: {T | q}` discharged as a real SMT obligation instead of
  stripped), a fundamentally larger change to the bidirectional core, since it
  also requires threading a path/assumption context through `infer_expr`/
  `check_expr` that does not exist today, and it flips the soundness contract
  from "report only definite failure" to "prove or reject," which reopens the
  false-positive risk the current design was built to avoid. That path
  (internally "Path 2: refinement subtyping in unification") was explored and
  explicitly **shelved** as a separate future project rather than pursued now:
  it is a multi-month, quarter-scale core-typechecker effort with real
  abandonment risk, while the shipped direct-call/path-sensitive checker
  already delivers most of the practical value (preconditions, bounds, path
  sensitivity, postconditions) at a fraction of the cost. If it is later
  revisited, the plan is to validate the subtyping judgment's soundness in
  March's Lean 4 mechanization track first, and to keep it independent of the
  `apply`-style `infer_app` precondition emission that was also considered and
  rejected (it would regress path sensitivity without adding higher-order
  checking).
- **Measures see structure, not elements.** Element values inside a data
  structure are opaque to a measure (`size`/`len`/`depth` never inspect them).
  Measures are single-argument, recursive over structure, and return `Int`/`Bool`.
- **An unproven postcondition does not reach callers.** If the checker can't
  prove a declared return refinement at the definition (an opaque body, a
  predicate it can't reflect, or a body that routes its value through a local
  `let` binding rather than returning it directly), the declaration is still
  accepted but callers learn no fact from it. Only proven postconditions are
  assumed at call sites.
- **Relational postconditions propagate, but only as far as the definition side
  got.** A return refinement mentioning a parameter (`{Int | _ == n + 1}`,
  `{Int | _ < len(xs)}`) *is* instantiated at call sites by substituting the
  call's arguments, but only if the definition **proved** it, so a relational
  contract the solver cannot discharge travels no further than a closed one
  would. Propagation is also skipped when an argument is missing, when the
  predicate mentions anything that is neither the binder nor a parameter, or
  when the callee takes a pattern parameter. See the propagation section above.
- **Structural induction (Tier 2): relating a measure across a recursive
  operation now works, within a narrow shape.** `size(insert(t, x)) == size(t)
  + 1` *is* provable automatically, and therefore propagates to call sites. Z3
  still does no induction; what the checker supplies is the **induction
  hypothesis**: at a self-recursive call with an argument that is a *proper component*
  of the matched parameter, the function's own postcondition is assumed about
  that call's result, and each `match` arm is then discharged separately against
  the measure's recursion equations.

  **What is proven:**
  - a single-clause, unguarded function with a body that is entirely a `match` on one
    parameter, with flat constructor-pattern arms;
  - a single-clause, unguarded function with a body that is entirely a **constructor
    application**: `fn push(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1}
    do Node(t, x, Leaf) end`. No induction is needed here (there is no recursive
    call to hypothesise over), just one unfolding of the measure's recursion
    equation. Both shapes **record their verdict in the obligation ledger**, so
    `--refine-report` distinguishes "attempted and proved" from "never looked
    at"; neither emits a diagnostic;
  - a return refinement over a **variant ADT** (`{Tree | …}`, `{List(Int) | …}`)
    with a predicate that mentions a **`@[measure]`**, or, over a `List`, the
    built-in **`len`** and **`elts`**, which follow the list's `Cons` cells
    inside the induction;
  - a body whose leading statements are **local `fn` definitions** followed by
    one of the shapes above;
  - a tail that **calls another function** whose return refinement is proved,
    including a local `fn` defined in the same body (`reverse`'s `go`): the
    call stands for a value satisfying that contract. A contract is only ever
    used once proved, so two functions cannot prove each other;
  - the function's own **parameter refinements** as hypotheses: every call is
    obliged to establish them, so `acc : {List(a) | member(prev, elts(_))}` is
    an invariant the body may use;
  - self-recursion into any recursive component (left or right, it is the
    pattern that determines it, not a position);
  - **relational** (`size(_) == size(t) + 1`) and **closed** (`size(_) >= 1`)
    predicates alike;
  - an accumulator parameter that *grows*: the induction is on the matched
    parameter only, so the hypothesis is universally quantified over the rest.

  **What is not, and stays silent:**
  - **mutual recursion.** The hypothesis is created only for a call to the
    function's *own* name, so two functions that call each other prove no property.
  - **a recursive call inside a lambda, or behind a nested `match`.** Only the
    top-level `match`'s pattern equation is supplied, so an arm with a tail that sits
    under a second `match` cannot see the inner scrutinee's shape.
  - **non-structural recursion.** A recursive call on the whole parameter, on a
    reconstructed value, or on anything `structural_subvars` does not certify as
    a component gets **no** hypothesis. This is a correctness requirement, not a
    completeness one: a proven postcondition is *added* to the assumption set
    that call-site checks prove `¬goal` against, and adding assumptions makes a
    violation easier to prove, so an unsound hypothesis would manufacture false
    positives on correct code, not just fail to help.
  - **anything needing a lemma.** A true property the hypothesis by itself cannot
    reach returns unknown and is skipped. Use an `assert` lemma there.

  Int-returning postconditions are unaffected: they still go down the Tier 0/1
  path, which this does not touch.

- **A measure with a value that is a *scalar constructor field* is INERT: it
  discharges no obligation in either direction.** Established by a feasibility gate on
  2026-08-05 while attempting a bounds contract for `Array.get`/`set`/`pop`.
  `Array` stores its own count, so `Array.length` is a single-arm field read:

  ```march
  @[measure]
  fn length(v : PVec(a)) : Int do
    match v do
    PVec(n, _, _, _) -> n
    end
  end
  ```

  This is accepted with no error and no warning from the soundness gate, is
  shape-OK for `build_measure_preamble`, and produces a **correct** axiom
  (`forall ((n Int) …) (= (length (PVec n …)) n)`). It still proves no goal. The
  cause is upstream of the axioms, in call-site reflection: `reflect_field`
  recurses into a constructor field only when its sort is a data type other
  than the opaque `Elem`, and mints a **fresh unconstrained constant** for
  everything else, on the (until now universally true) assumption that a scalar
  field is "irrelevant to a structural measure". So
  `length(PVec(3, 0, TrieEmpty, Cons(x, Nil)))` reaches z3 as
  `(length (PVec _e3 _e2 TrieEmpty (Cons _e1 Nil)))` (the literal `3` erased),
  and `1 < _e3` is neither valid nor unsatisfiable. Both directions are
  `solver-undecided`.

  Note what is **not** the cause, each disproved by a dedicated probe: a
  single-arm measure is fine (`Box(_, _) -> 3` proves), non-recursion is fine,
  a constructor with a scalar field the measure does *not* read is fine
  (`N3(k, rest) -> 1 + size3(rest)` proves), and the syntactic non-negativity
  classification is irrelevant. The sole discriminator is whether the measure's
  **value depends on an erased field**.

  A **warning** is emitted at the measure's definition, but only for a **bare
  field read** (`-> n`). A body that computes with the erased field (`-> n + 0`,
  `-> n * 2`) is equally inert and warns **not at all**. The predicate is
  intentionally narrow because the broader "mentions an erased field" version
  false-positived on `Zleaf(n) -> 0 * n`, with a value that does not actually depend
  on `n`; under-warning is the safe direction, but it means **silence is not
  evidence that a measure works**.

  Consequence (historical, resolved 2026-09-13/14): `Array.get`/`set`/`pop`
  could not be given a dischargeable bounds contract and stayed on
  `cap no_panic`'s syntactic ban list; they are contracted now (see the
  `List.nth` paragraph). Fixing this
  means reflecting a scalar field concretely when the actual argument is a
  literal (`term_fits_sort` already accepts a scalar term at an `SInt`/`SBool`
  field, so the ill-sorted-VC hazard that motivated the erasure does not apply
  to that case), keeping the fresh constant only for a non-literal scalar.
  Because that widens what **every** existing contract can prove, it needs a
  full stdlib + ecosystem sweep for new false positives, not a "still compiles"
  check. Tracked in `specs/todos/2026-08-05-measure-over-scalar-ctor-field.md`.

- **The stdlib HAMT (`Map`) is well beyond this.** `stdlib/map.march` stores
  `HEntry(k,v) = HEmpty | HLeaf(Int,k,v) | HBranch(Int, List(HEntry(k,v))) |
  HCollision(Int, List((k,v)))` and inserts via a hash-indexed descent. A local
  reduced model shows **three stacked obstacles**, in the order they bite:
  1. **The built-in `List`'s element sort is opaque.** The checker models
     `List` as `Nil | Cons(Elem, List)` with `Elem` an uninterpreted sort, so a
     count measure that must recurse *into* a list element (`lcount(Cons(h,t)) =
     hcount(h) + lcount(t)`, where `h : Elem` but `hcount : HEntry -> Int`) is
     ill-sorted and is dropped: neither measure gets axiomatised, and no step
     downstream can run. Substituting a *user-defined* child list for the
     built-in one, changing no other detail, makes the same postcondition prove and
     propagate. This obstacle precedes induction entirely.
  2. **The nested `match`.** With (1) worked around, `node_insert` still reaches
     its child by matching the child list, so the tail lives under a second
     `match` with a pattern equation that is not built (see above). Bounded and
     addressable.
  3. **The child is fetched by index, not bound by a pattern.** The real code
     does `let child = list_nth_safe(children, idx)`. `structural_subvars`
     certifies pattern binders only, so `child` is not smaller in structure by
     any test the checker has; and it would need a length/termination lemma
     the checker cannot currently state. On top of that the real `HEntry` is
     generic in `k`/`v`, `Map` wraps it in a `ptype`, and `node_insert` includes
     an `eq` callback and a `level` counter, none of which the measure
     infrastructure models.

  So: the answer to "does the structural test recognise a child fetched from a
  `List` by index?" is **no**; and obstacle (1) stops the measure from existing
  before that question is even reached.
- **`Bool` predicates use the operator forms, not a bare binder.**
  `{Bool | _ == true}`, `{Bool | _ != false}` and the connectives `&& || not`
  are checked; the bare-binder spelling `{Bool | not _}` is a **parse error**,
  so write `{Bool | _ == false}` instead.
- **`Float` record fields and ADT payloads are opaque.** A `Float` *parameter*
  or *return* is checked; a `Float` sitting inside a record or a constructor is
  not reflected, and a record with such a field is skipped at the call site
  rather than half-modelled.
- **There is no special-value vocabulary.** No `is_nan`, no `is_finite`. You
  cannot write a predicate expressing "not NaN"; see
  [Float Refinements](#float-refinements) for why NaN nevertheless never causes
  a false report.
- **An AXIOMATISED measure applied to the refined value itself is now
  enforced against the actual argument** (fixed 2026-07-29; this bullet
  previously documented the opposite as a limitation, and that limitation was a
  *bug*). The axiomatised resolver discarded the actual and reasoned about an
  unconstrained placeholder tree instead, so a `{Tree | size(_) > 0}` contract
  checked no case at all: `inner(Leaf)` was accepted and
  `inner(Node(Leaf, 5, Leaf))` was not proved: both simply skipped, and a skip
  exits 0 exactly as a proof does. Confirmed again 2026-07-29 in every direction:
  `inner(Leaf)` against `{Tree(Int) | size(_) > 0}` is **reported** (exit 1),
  `inner(Node(Leaf, 5, Leaf))` is **proved** (exit 0, `1 proved`), `big(Leaf)`
  against `{v : Tree(Int) | size(v) > 2}` is now **reported** rather than
  silent, and `{v : Tree(Int) | size(v) < 0}` is still caught for any argument
  from the non-negativity axiom by itself. So a constructor literal in this
  position has its measure computed from the recursion equations, exactly as a
  measure applied to a *different* parameter always did (`get(Node(Leaf, 5,
  Leaf), 3)` above), and exactly as the built-in list `len` does for `head([])`
  against `{List(a) | len(_) > 0}`. The same fix is what lets an ADT measure
  contract compose across a call boundary; see [A Parameter's Own Contract Is
  a Fact Inside Its Body](#a-parameters-own-contract-is-a-fact-inside-its-body).

  What truly stays out of reach is the shape with no value to reflect: where
  the argument is neither a constructor literal nor a variable the pass can
  name, the unconstrained placeholder is still the fallback and the obligation
  is skipped.
- **Performance: measures can be slow on a cold cache.** Quantified + datatype
  reasoning is far more expensive per query than plain arithmetic. Verdicts are
  content-addressed and cached (warm rebuilds are fast), and the cost is
  isolated to call sites that actually mention a measure, but a cold build of
  measure-heavy code pays for it. See the flag below. A *non-recursive*,
  Int-valued measure (every arm translates with no measure call) is emitted as
  a quantifier-free `define-fun` (an `ite` over constructor testers with
  `let`-bound selectors) instead of `declare-fun` + forall axioms
  (`measure_definition`, 2026-09-14). Under the quantified encoding z3 answered
  every *satisfiable* query over such a measure `unknown (incomplete
  quantifiers)` only at the 3 s per-query timeout, so a single contracted
  `Array.get` in the stdlib cost ~1 min of cold checking per program; the
  definition decides the same query in ~30 ms in both directions. Recursive
  and set-valued measures keep the axioms.
- **A predicate can call a name the checker doesn't understand; it now tells
  you.** Predicate bodies aren't typechecked, so `{Int | totally_bogus_fn(_) >
  0}` used to compile clean and enforce no contract. The checker now warns when a
  predicate applies a function outside its known vocabulary: the comparison,
  arithmetic, and boolean operators (`==`, `!=`, `<`, `<=`, `>`, `>=`, `+`,
  `-`, `*`, `negate`, `not`, `&&`, `||`), the built-in `len`, every ADT's
  `is_<Ctor>` tester, and any function annotated `@[measure]`. This is a
  Warning, not an Error (the program still
  compiles), but it tells you the refinement it's attached to is not actually
  checked, so you can annotate the function `@[measure]` or switch to a
  supported predicate.

### Open gaps in element and abstract refinements

The October 2026 features stop at these edges. Each one is a recorded skip:
never a violation, and an error under `cap verified`. Each has an open item in
`specs/todos/`, except the generic-function one, which is a design ruling.

- **`Map`'s other functions carry no element fact.** Inserting into, removing
  from, looking up in, merging or mapping over a refined `Map` keeps nothing.
  Only `Map.filter` carries an entry fact. (Todo: Map element flow through
  combinators.)
- **`HashMap.filter` and `OrderedMap.filter` carry no entry fact yet**, unlike
  `Map.filter`. (Todos: HashMap filter two-argument abstract, and OrderedMap
  filter two-argument abstract.)
- **A list of pairs is not modelled.** A tuple element is not a container
  type, so a list of pairs has no element slots, and no relation over its
  parts. This is also why `Map.filter`'s entry fact is assumed rather than
  proved. (Todo: tuple elements, list of pairs, abstract.)
- **A curried callback with a concrete contract carries no fact.** Inside the
  function, calling it gives no fact. Nothing checks the callable passed for
  it. Only a chain whose result applies an abstract `p` is read; see
  [Two arguments](#two-arguments-a-relation-between-sibling-slots). (Todo:
  chain predicate contract pass site.)
- **A callback called in two steps gives no fact.** If a body takes the
  partial call into a `let` and then tests the result, it establishes nothing.
  So a combinator written that way does not prove its relational return.
  (Todo: abstract curried two-step call, no fact.)
- **A relation is lost through a generic function.** A function generic in `k`
  and `v` keeps each slot's fact. But it may pair one entry's key with another
  entry's value, as `shift` does, so its result is a recorded skip. To carry a
  relation through a combinator, give it a two-argument abstract refinement.
  (No todo: a ruling, recorded in the progress note for phase 1b of the
  multi-argument abstract refinements.)
- **A container parameter spelled with its module name gives no element
  fact.** This covers `Queue.Queue` and `Deque.Deque`, for example. It is a
  `parametric-source-unproved` skip. The same shape over a type declared in
  the module under check proves. (Todo: refine qualified container
  param entry.)

```march
Map.insert(pos_map, "b", 5, cmp)        -- into a positive-value demand: skip
List((k, v))                            -- a list of pairs: no slots
kk : ({x : Int | true}) -> ({y : Int | true}) -> {Bool | _ == (y > x)}   -- no fact
let g = keep(k)                         -- then `if g(v)`: no fact
need_up(shift(a))                       -- the relation is lost: skip
q : Queue.Queue({Int | _ > 0})          -- `sum_pos(Queue.to_list(q))`: skip
```

---

## Conformance status

Refinement types are now a conformance-tested part of the language reference
(widening slice 12; `core-march-types.md` §2.14). The central fact §2.14
pins down: `{T | pred}` is completely transparent to `typecheck.ml`'s own
unification (a refined type has the identical typing derivation as its
base type); checking happens entirely in the separate `lib/refinecheck`
pass this page already describes, at exactly two sites, both mechanically
witnessed: a **precondition** at a direct call (accept/reject pair
`t75`/`t71`) and a **postcondition** on the function's own body
(`t76`/`t72`). The "direct calls only" limitation this page's own
Limitations section stated was, at the time, a passing corpus fact:
`accept/t77_refine_hof_bypass_limitation` proved a refined function called
*through* a higher-order parameter was NOT checked (since closed; see the
end of this section). `cap no_panic`'s division-safety
check is confirmed as a second, independent `Refine.discharge` consumer
(`t78`/`t73`). Golden `g46_refinement_erasure` witnesses the zero-runtime-
footprint property this transparency implies: a program with obligations that
are all proved at `--check` time runs byte-identically interpreted and
compiled, since neither backend inserts any runtime predicate check.

Two higher-order call shapes have since been closed (348 refinecheck tests as
of 2026-07-29: 16 covering Tier 2 structural induction, 9 covering `Bool` and
`Float` refinements, and 8 covering call-boundary contract composition):
a call through a refined function-typed *parameter*, and a call through a
*local alias* of a named refined function; both previously fell through
`resolve_call`'s named-callee-only resolution and were silently skipped.
The remaining boundary, `apply(take_n, -3)` through an unrefined
`f : Int -> Int`, held as `accept/t77_refine_hof_bypass_limitation.march`
until 2026-09-13, when contravariant subtyping at the pass site closed it
(`specs/progress/2026-09-13-hof-pass-site-contravariance-closes-t77.md`);
the same program is now `reject/t77_refine_hof_pass_site_rejected.march`,
rejected at the pass of `take_n` rather than at the indirect call.

The typing corpus now stands at **229 programs (114 accept, 115 reject)**, with
each refinement feature bracketed from BOTH sides. That pairing is intentional
and essential: an accept-only witness cannot distinguish a working contract
from one that silently checks no case, which is exactly how the `_` and
named-binder spellings of a measure over the refined value shipped unenforced
until 2026-07-27 (`accept/t115`–`t117`, `reject/t114`–`t116`; `reject/t116`
additionally pins that a contract declared in a *stdlib* signature reaches a
user call site at all). The `List.length` → `len` alias added 2026-07-28 is
bracketed the same way (`accept/t118`, `reject/t117`): the accept file exits 0
whether the guard is read or the obligation is simply skipped, so only the
reject file shows the alias is doing the real work. Call-boundary **composition**
(2026-07-29) is bracketed the same way and for the same reason
(`accept/t128`, `reject/t129`): the accept file exits 0 whether the inner call
composed or was silently skipped, so only the reject file (where a
intentionally weaker caller contract must NOT launder the stronger callee
requirement, while a real violation on the same shape is still caught) shows
that composition fires exactly where it should and in no other place. Two witnesses
pin soundness rather than a feature:
`accept/t110` (an unproven postcondition must not propagate) and `accept/t113`
(a NaN-only `Float` predicate must stay satisfiable; it fails the moment
anyone re-encodes floats as reals).

On the operational side, golden `g46_refinement_erasure` is the only refinement
program in the 46-program golden corpus, and it exercises `{Int | _ >= 0}`
only. Erasure was separately confirmed again 2026-07-27 for every later form (ADT
tags, `Bool`, `Float`, `String` `len`, non-empty `List`, and the stdlib
`List.head`/`Option.unwrap` contracts) by diffing interpreted against compiled
output on one program using all of them: an exact byte match, exit 0 both. The
golden corpus itself remains 46/46 MATCH.

---

## See also

- [Type System](type-system.md): the types refinements attach to
- [Linear Types](linear-types.md): the other compile-time safety layer
- [Pattern Matching](pattern-matching.md): `match` guards feed path sensitivity
- [Capabilities]({{ site.baseurl }}/docs/capabilities/): `cap no_panic` and `cap verified` beside the other behavioral caps
- [Safety by Construction](safety-by-construction.md): refinements as one of three layers
