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
connectives `&& || not`, integer/bool literals, **measures**, and ADT
**constructor tags** (both below). `String` values are supported to the
narrower extent described in [String Refinements](#string-refinements): `len`
and `==`/`!=` against literals. `Bool` values take the boolean operators against
`true`/`false` ([Bool Refinements](#bool-refinements)); `Float` values take
comparisons against float literals, discharged through Z3's bit-precise IEEE-754
theory rather than reals ([Float Refinements](#float-refinements)).

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

**Relational postconditions propagate too, by substitution.** A predicate that
mentions a parameter — `{Int | _ < n}`, `{Int | _ < len(xs)}` — is *relational*.
At a call site the call's arguments are substituted for the callee's parameters,
which restates the contract entirely in the caller's own terms:

```march
fn below(n : Int) : {Int | _ < n} do n - 1 end
fn takepos(k : {Int | _ >= 0}) : Int do k end

takepos(below(0))       -- error: `_ < n` instantiates to `_ < 0`, never >= 0
takepos(below(10))      -- fine: `_ < 10` can still be >= 0
```

Parameters are matched to arguments **positionally**, and substitution is
**simultaneous** — with `fn f(n : Int, m : Int) : {Int | _ < n + m}` called as
`f(m, 1)`, the result is `_ < m + 1` (the caller's `m`), never `_ < 1 + 1`.

Propagation is **skipped** — silently, and with no loss of soundness — whenever
the instantiation cannot be made exactly:

- the predicate mentions a name that is neither the refinement binder nor one of
  the callee's parameters;
- a parameter the predicate mentions has no corresponding argument (an arity
  mismatch, or an omitted defaulted argument);
- the predicate uses syntax the checker does not reflect;
- the callee has a *pattern* parameter, which is rewritten before this pass runs
  and so no longer carries the parameter names the predicate refers to.

A partially substituted predicate is never used: mixing the callee's and the
caller's namespaces is precisely how a false positive would arise here, so the
checker abandons the whole instantiation rather than guess at part of it.

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
    at(xs, i)          -- ok: the guard proves BOTH halves of the precondition
  else
    0
  end
end
```

(`len` is a measure name usable only inside a `{...}` refinement predicate,
not a callable in ordinary code — verified live, 2026-07-22; use
`List.length` in a plain guard expression like the one above.)

### `List.length` is an alias of the `len` measure

The guard above is a genuine proof, not a skip. The checker treats the
**qualified** `List.length` as an alias of the `len` measure, so
`i < List.length(xs)` establishes exactly the fact `i < len(xs)` that `at`'s
precondition asks for. Verified 2026-07-28: `--refine-report` on that program
reports `1 proved, 0 violated, 0 trusted, 0 skipped` for user code.

Until 2026-07-28 the two were unconnected symbols and the guarded call was
silent because it was *skipped*, not because it was verified. That is fixed; the
corpus brackets it from both sides (`accept/t118`, `reject/t117`), because an
accept-only witness exits 0 either way and so cannot tell a working guard from a
contract that checks nothing.

The alias is deliberately narrow, because attaching `len`'s meaning to the wrong
function would manufacture false positives:

- **Only the qualified `List.length`.** A bare `length` is left alone.
- **Only while it is the standard library's own.** The stdlib is identified by
  the source files the compiler actually loaded, so it works the same from a
  repo checkout, an installed `share/march`, or a `MARCH_STDLIB` pointing
  anywhere.
- **Withdrawn for the whole compilation unit** if anything in it could make that
  spelling denote a different function — a program defining its own
  `List.length`, a vendored or forked `List` arriving through `MARCH_LIB_PATH`,
  or rebinding `List` via `alias`/`use`. In those cases the obligation goes back
  to unprovable-and-skipped, which is the pre-alias behaviour.

  **The gate is unit-global, and the unit is bigger than the file you are
  editing.** `bin/main.ml` prepends the entire standard library to every
  compilation, and `MARCH_LIB_PATH` adds every `.march` file in every dependency
  directory. One genuine competitor anywhere in that set disables the alias for
  the whole program, including in files that never mention it. This is a real
  coverage cost, accepted deliberately: deciding whether a competitor could
  actually win at a given call site needs a resolver this pass does not have,
  and the errors are asymmetric — over-withdrawing loses a proof (silence),
  under-withdrawing puts a wrong fact in the assumption set and reports correct
  code, which is the cardinal sin.

- **A glob import RESOLVES its target instead of assuming the worst** (since
  2026-07-29). `import Foo` / `use Foo.*` withdraws the alias only if `Foo`
  actually provides a competing member, decided by walking the compilation
  unit's own module structure (a `use` inside the target is followed
  transitively, under a fuel bound); an unresolvable path, or exhausted fuel,
  still withdraws. Before this, the mere presence of a glob was enough — and
  since `stdlib/system.march` carries a single `import Process` and the stdlib
  is prepended to everything, the alias was withdrawn for **every March program
  ever compiled**. The feature was inert in production and the suite stayed
  green, because a skipped obligation exits 0 exactly as a proved one does; only
  a REJECT witness (`reject/t117`) and the `--refine-report` proof *floor* can
  see the difference.

- **A `use`/`alias` competes only when it is the *program's*** (since
  2026-07-29). The rebinding half now ignores declarations whose span is a
  standard-library source file, exactly as the member-definition half always
  has — an `import` inside `mod System` binds names in System's own body, not
  in the module being checked. This is conjoined with the resolution rule
  above, not substituted for it: a glob withdraws only when it is the
  program's own **and** its target provably provides a competitor. Both are
  over-approximations of "really competes", so their intersection still
  contains every genuine competitor; neither weakens the other's test.

The same treatment applies to strings — see
[String Refinements](#string-refinements).

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

A guard may also read a **record field** (`if c.port >= 1 do serve(c)`) — see
[Refining a record over its fields](#refining-a-record-over-its-fields).

### A qualified spelling in a predicate enforces nothing

The alias above holds in a **guard** — ordinary code the desugarer rewrites.
It does **not** hold inside a **predicate**, the `{T | … }` itself:

```march
fn inner(xs : {List(Int) | List.length(_) > 0}) : Int do …   -- enforces NOTHING
fn inner(xs : {List(Int) | len(_) > 0}) : Int do …           -- enforces the contract
```

Refinement predicates are never run through the expression desugarer —
`Desugar.respan_ty` is the only place that touches `A.TyRefine`, and it only
respans — so inside a predicate `List.length` stays a field-access chain
rather than the dotted variable the alias keys on. The obligation the contract
looks like it generates is simply skipped, and skipping is silent by default.
The contract parses, typechecks, reads as working, and checks nothing.

Since 2026-07-30 this **warns**, naming both the spelling found and the bare
measure that works:

```
`List.length` is a qualified call inside a refinement predicate. Predicates
are not desugared, so this is never reflected and the refinement enforces
nothing. Use the bare spelling `len` instead.
```

It is a warning rather than an error on purpose: this shape compiles today, so
promoting it would break working builds, and the defect being fixed is the
*silence*, not the lack of capability — the bare spelling has always worked.
Desugaring predicates properly, so the qualified spelling means what it reads
as, is a genuine follow-up and a much larger change with its own regression
surface. Witnessed by `accept/t136` (which pins that the program stays exit 0)
and by `test_refinecheck.ml`'s `qualified-predicate` suite, which pins the
warning text together with a false-positive control that the bare spelling
stays quiet.

The same reasoning covers the other qualified measures: write `len(_)`, not
`String.byte_size(_)`, inside a predicate.

---

## A Parameter's Own Contract Is a Fact Inside Its Body

A **guard** and a **declared contract** are two different ways to establish the
same fact, and it matters which one you have. The section above is about the
guard: a runtime test you write (`if List.length(ys) > 0 do …`) becomes an
assumption for the branch it dominates. This section is about the other one: a
parameter whose *declared type* carries a refinement is a promise the caller
already had to keep, and since 2026-07-29 that promise is an assumption inside
the function's own body. So contracts **compose** across a call boundary — a
function that requires a property can pass its own parameter on to another
function requiring the same property, with no guard at either site:

```march
fn inner(xs : {List(Int) | len(_) > 0}) : Int do 0 end
fn outer(ys : {List(Int) | len(_) > 0}) : Int do inner(ys) end
fn main() : Int do outer([1]) end
```

Both call sites are **proved** — `--refine-report` on that program reports
`2 proved, 0 violated, 0 trusted, 0 skipped` for user code (verified 2026-07-29). Before
this, `outer([1])` proved on the literal while `inner(ys)` was silently
*skipped*, so the practical ceiling was that a non-empty contract could not be
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
discharge a callee wanting `is_Some(_)` — that call stays skipped. See
[Limitations](#limitations).

**Only the caller's own promise is loaded, and only what it actually entails.**
A *weaker* declared contract does not launder a stronger requirement: with
`outer(ys : {List(Int) | len(_) >= 0})` — true of every list — the same
`inner(ys)` is **skipped**, not proved and not reported
(`1 proved, 1 skipped`). This is the definite-failure stance holding, and it is
the false positive that matters most in this area, so the corpus brackets the
feature from both sides: `accept/t128` shows the composition, and
`reject/t129` shows the weak contract failing to launder while a genuine
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

**A caller's fact does not travel through a local `let`, for any type.** This
is a separate, pre-existing limitation of the pass and is unchanged: it
propagates no local binding's value into a later goal, so

```march
let u = 5
take_pos(u)      -- skipped, even though `5` satisfies `{Int | _ > 0}`
```

is skipped, and the `List` analogue (`let u = [1, 2]` then `inner(u)`) behaves
identically. Pass the value directly, or restate the fact with `assert`.

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

### Refining a collection over its own length

The measure may also range over the refined value **itself**, which is how a
non-empty-collection precondition is written:

```march
fn head(xs : {List(a) | len(_) > 0}) : a do ... end
```

All three spellings of the refined value mean the same thing here and are
checked identically — the anonymous `_`, a named binder, and the parameter's own
name:

```march
fn head(xs : {List(a)     | len(_)  > 0}) : a do ... end
fn head(xs : {v : List(a) | len(v)  > 0}) : a do ... end
fn head(xs : {List(a)     | len(xs) > 0}) : a do ... end
```

A call with a literal empty list is a definite failure and is reported;
`head([1, 2])` is silent; and a `List` whose contents the checker cannot see
stays **unknown**, so it is skipped rather than guessed:

```march
head([])            -- reported: `len(_) > 0` cannot hold
head([1, 2])        -- silent
fn f(ys : List(Int)) : Int do head(ys) end   -- skipped: length unknown
```

Thirteen stdlib functions that panic on an empty argument carry this contract —
`List.head`/`tail`/`last`/`minimum_int`/`maximum_int`, the `prelude` `head`/`tail`,
`Stats.mean`/`min_val`/`max_val`, `Gen.element`/`one_of`, and `Random.choice`. Each
is derived from that function's own panic message, so the contract is never
stronger than the check the code already performs, and the `panic` remains as the
runtime backstop for the arguments the checker skips.

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
for the exact conditions under which the alias applies — and for when it is
withdrawn, in which case the obligation returns to being skipped.

A runtime **guard** is not the only way to discharge this. If the *enclosing
function* already declares the same contract on the parameter, no guard is
needed at all — the promise composes into the call. That is a different
mechanism from the guard above; see [A Parameter's Own Contract Is a Fact
Inside Its Body](#a-parameters-own-contract-is-a-fact-inside-its-body).

### Refining a record over its fields

A refinement may also range over a **record** type, with the predicate reading
its fields. This works on **both** sides of a signature — as a postcondition on
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
  against them. Fields may be written in any order — they are matched to the
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

  The variable does not need a refinement of its own — a plainly-typed
  `c : Config` works, because an unrefined record variable is modelled as an
  unconstrained value and it is the *guard* that decides it. With no guard
  nothing is known and the call is skipped, exactly as before.

  Field facts obey the same rebinding rule as tag facts and scalar facts: a
  fact is recorded against a *name*, so a `let`, a `let?`, a lambda parameter
  or a `match` binder that rebinds that name retires it.

Everything else about a record is **skipped**:

- an **unrefined record variable with no guard on the field** — nothing is
  known about its fields;
- a record literal with an **unknown field value** (`{ port: p }` for a
  parameter `p`) — nothing is known about that field, so a predicate over it
  is neither proven nor refuted.

An **unreflectable field does not sink its siblings.** A field whose type is
outside the reflected fragment (a `String`, a function, a nested record bound
to anything but a literal), or a **list field holding concrete elements**
(`history: Cons(1, Nil)` — the built-in `List` is generic, so the checker models
its element type as an opaque sort an `Int` cannot be placed in), is replaced by
an unconstrained stand-in of the right shape. The rest of the record is checked
normally:

```march
type Config = { port : Int, name : String }

serve({ port: 0, name: n })    -- error: `port` is still checked
```

Nothing may be concluded *about* the stand-in, in either direction — a predicate
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

Records also compose with measures — `{v : State | len(v.history) == v.count}`
reasons about a `List` field structurally, exactly as `len` does elsewhere.

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

`len` counts **bytes**. For non-ASCII text a character is several bytes:
`len("é")` is 2, not 1. March *does* have a codepoint-length primitive —
`String.codepoint_count`, which returns 1 for `"é"` — and it is deliberately not
what `len` denotes. (An earlier revision of this page claimed no such primitive
existed. It does; reasoning from that claim is how a codepoint count nearly got
equated with a byte count.)

### A byte-length guard discharges a String `len` obligation

Just as `List.length` aliases `len` for lists, the **byte-valued** string-length
spellings alias `len` for strings — `String.byte_size` and the
`string_byte_length` builtin:

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
  codepoints, not bytes, and are left alone.
- `string_length` is **also** a byte length — it lowers to
  `march_string_byte_length`, and `string_length("é")` is 2 — but it is
  deliberately *not* aliased. The abstention is about the NAME, not the current
  semantics: `string_length` reads like a character count, and if it were ever
  corrected to one, an alias written today would silently become unsound. The
  unambiguous `String.byte_size` says what it means and is the spelling to use
  in a guard.

The same withdrawal rules as the list alias apply: a program that defines its own
`String.byte_size` (unless it *is* the standard library's) — in any declaration
form: a `fn`, a module-level `let`, an `extern` block, an interface or impl
method — rebinds `String` via `alias`/`use`, or binds the name
`string_byte_length` itself — as a declaration,
an import, a `let`, a lambda or `fn` parameter, or a match binder — loses the
alias for the whole **compilation unit** (prepended stdlib and every
`MARCH_LIB_PATH` dependency included), and the obligation returns to being
skipped. A glob import withdraws only if its resolved target really provides the
competitor; see
[`List.length` is an alias of the `len` measure](#listlength-is-an-alias-of-the-len-measure).

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

## Bool Refinements

A `Bool` parameter or return can carry a predicate over the ordinary boolean
operators — `==`, `!=`, `&&`, `||`, `not` — against the literals `true` and
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
other postcondition — only if the definition side **proved** it:

```march
fn always_false() : {Bool | _ == false} do false end
fn v() : Int do commit(always_false()) end   -- rejected
```

An unknown `Bool` — a parameter, a value the checker cannot settle — is
**skipped**, and a guard establishes the fact you would expect:
`if k do commit(k) else 0 end` passes.

---

## Float Refinements

A `Float` parameter or return can carry a **comparison** predicate — `>=`, `>`,
`<=`, `<`, `==`, `!=` — against float literals or another float value:

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
false-positive direction* — the one failure this checker must never have.
Consider

```
not (x >= 0.0) && not (x <= 0.0)
```

Over reals, trichotomy makes this **unsatisfiable**. The checker reports a
violation exactly when it proves a predicate can never hold, so a reals encoding
would flag this perfectly ordinary contract on *any* argument. Over floats it is
**satisfiable**, witnessed by `NaN`, which compares false against everything —
so the checker correctly stays silent. Do not "simplify" the encoding to `Real`.

`==` is `fp.eq`, **not** SMT-LIB `=`. `=` on `Float64` is *bitwise* identity,
under which `-0.0` differs from `0.0`; `{Float | _ != 0.0}` would then accept a
negative zero, which is just as bad a divisor as a positive one. Under `fp.eq`,
`-0.0 == 0.0` is true (so a negative-zero argument **is** reported) and `NaN`
equals nothing, including itself.

### What Float refinements do *not* do

- **Arithmetic in a predicate is skipped, not guessed.** `{Float | _ +. 1.0 >
  0.0}` mentions the binder under `+.`, which would need Z3's rounding-mode
  surface to model. The whole predicate becomes unreflectable and the obligation
  is silently skipped — including for an argument that plainly violates it.
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

## Constructor Tags — Refining over ADT Variants

Every constructor of every ADT — your own types, and the built-in `Option`,
`Result` and `List` — implicitly gains an `is_<Ctor>` **tester** the checker
understands inside a predicate. Nothing declares them; `type Shape = Circle(Int)
| Square(Int)` gives you `is_Circle` and `is_Square` for free.

```march
-- a contract that says "this Option is definitely populated"
fn unwrap(o : {Option(Int) | is_Some(_)}) : Int do ... end

unwrap(Some(1))   -- fine
unwrap(None)      -- error: `None` can never satisfy `is_Some(_)`
```

The name is **exact-case**: `is_Some` is the tester for the constructor `Some`;
`is_some` is not a tester at all (it happens to be the lowercase stdlib helper
`Option.is_some`), so a misspelling draws the unrecognized-predicate warning
rather than silently meaning something else.

There are two sources of tag facts.

**A constructor literal at the call site**, as above — the argument's tag is
known exactly, so the tester decides.

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

Narrowing is deliberately conservative, and where it stops is where the checker
goes quiet rather than guessing:

- **The scrutinee must be a bare variable.** `match mk() do …` matches an
  expression with no stable name to attach a fact to, so no narrowing happens
  and calls inside the arms are skipped. Bind it to a `let` first if you want
  the fact.
- **A rebinding pattern binder ends it.** Matching `y` with `Some(x) ->` says
  nothing about `x` — that `x` is a fresh binder for the payload, not the
  scrutinee — so no fact is recorded against the name it shadows.
- **An `as` pattern is not narrowed.** `None as z ->` binds the whole scrutinee
  under a second name, but the arm's head is a `PatAs`, not a bare constructor
  pattern, so no tag fact is recorded — for `z` or for the scrutinee. Write
  `None ->` if you want the narrowing.
- **An ambiguous constructor name is skipped.** If two ADTs in scope both
  declare a constructor `Row`, `is_Row` identifies no particular datatype and is
  not checked.
- **Rebinding the name retires the fact.** A narrowing is recorded against a
  *name*, so any construct that rebinds that name inside the arm — a `let`, a
  `let?`, a lambda parameter, an inner `match` binder — discards it. In

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
`Option` whose tag isn't known is simply not an error.

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

## Counting the obligations — `--refine-report`

Silence is the default outcome for everything that is not a definite failure, so
silence alone cannot tell **proved** from **skipped**. That ambiguity is not
cosmetic: `{List(a) | len(_) > 0}` once shipped enforcing nothing while the test
suite stayed green, because a contract that checks nothing and a contract that
passes look identical from outside.

`--refine-report` makes the checked fraction a number:

```
$ march --check --refine-report stdlib/list.march
refinement obligations (user code): 0 proved, 0 violated, 0 trusted, 5 skipped
  skipped (solver-undecided): 5
  by kind: 5 precondition, 0 postcondition
refinement obligations (user + stdlib): 8 proved, 0 violated, 0 trusted, 28 skipped
  skipped (unreflectable-predicate): 1
  skipped (solver-undecided): 27
  by kind: 36 precondition, 0 postcondition
```

> **Clear `.march/cas/artifacts-v2` first.** A `--check` run whose sources hash to
> an artifact already in the CAS exits immediately, before parsing — so the
> report never runs and the command prints **nothing** while still exiting 0.
> That is indistinguishable from "no obligations found", which is precisely the
> ambiguity this flag exists to remove, so always run it against a cold check
> cache. (`.march/cas/vc` is a *different* cache — solver verdicts, not check
> artifacts. Clearing it forces z3 to re-decide; it does not affect whether the
> report prints.)

Two slices are printed because the compiler prepends the whole standard library
to every compilation: **user code** counts only obligations raised at call sites
in the file you named, **user + stdlib** counts every obligation raised in the
run. Use the first to judge your own module; use the second as a whole-program
coverage number.

**CI ratchets on both, from two different fixtures, and that split is
load-bearing.** The skip **ceiling** reads `stdlib/list.march`'s `user + stdlib`
slice (28 skips, 8 proved as of 2026-07-29). The proof **floor** reads the
`user code` slice of `accept/t118` (1 proved), because a ceiling alone is not a
ratchet — a checker that raises no obligations at all satisfies it perfectly.
The floor cannot live on `stdlib/list.march`: its `user code` slice proves 0, and
its whole-program `8 proved` is dominated by obligations that survive the very
regressions the floor exists to catch. `t118` is a program whose single
obligation is *proved* by a `List.length` guard, so it drops to `0 proved` the
moment the measure alias stops working — which is exactly what the unit-global
glob-import bug did to every March program, invisibly, while `t118` still exited
0 (a skip and a proof are both exit 0; only the count tells them apart).

Each skip is attributed to one of six reasons:

| Reason | What happened |
|---|---|
| `unreflectable-predicate` | the predicate uses vocabulary the checker cannot translate to SMT |
| `unreflectable-subject` | the argument's own value did not translate, so no goal was built |
| `sort-conflict` | reflecting it would declare one symbol at two different sorts |
| `float-sort-gate` | the float wellsortedness gate rejected the formula |
| `alias-withdrawn` | the guard used a measure alias (`List.length`, `String.byte_size`, `string_byte_length`) that this compilation unit had withdrawn, because something in the unit binds that name |
| `solver-undecided` | the solver proved neither the predicate nor its negation |

`alias-withdrawn` is a refinement of `solver-undecided`, not a separate failure:
the VC was built and the solver ran, it just arrived without the fact that would
have discharged it. It is reported separately because the *action* differs — the
call is already guarded, and what has to change is a name binding elsewhere in
the unit. See [the alias-withdrawal note](#a-withdrawn-alias-names-itself) below.

The ledger records both **precondition obligations raised at call sites** and
**postcondition obligations** — a function's own return value checked against
its declared return refinement. Each obligation carries a `kind` (precondition
or postcondition), printed as a `by kind` breakdown line under each slice's
headline; the headline totals themselves do not distinguish kinds; a proved
postcondition is a proved obligation like any other. `cap verified` still
escalates precondition obligations only — see below.

---

## `cap verified` — turning silence into an error

March's default stance is **definite failure only**: a false positive on correct
code is the cardinal sin, so anything the checker cannot decide stays silent. A
module that wants the opposite bargain — "these contracts are a guarantee, not a
best effort" — declares `cap verified`, and every **precondition obligation at a
call site** the checker cannot discharge inside it becomes a compile error:

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
    if List.length(ys) > 0 do head_of(ys) else 0 end   -- proved; no error
  end
end
```

Dropping the guard turns the same call into an error naming the precondition,
the callee, and why it could not be discharged:

```
`cap verified` module: cannot verify precondition `len(_) > 0` on `head_of`
(solver-undecided: the solver proved neither the predicate nor its negation)
note: guard the call or strengthen what is known here, rewrite the predicate
into the fragment the checker supports, or remove `cap verified` from this
module — it asks for every obligation to be discharged
```

Both forms verified 2026-07-28 (guarded: exit 0; unguarded: exit 1 with the
message above).

### A withdrawn alias names itself

The measure aliases (`List.length`, `String.byte_size`, `string_byte_length`)
are withdrawn for the **whole compilation unit** the moment anything in it could
make the spelling denote a different function — see the shadowing rules under
each alias above. The gate is unit-global and syntactic on purpose: it does not
ask whether the competing binding could actually win at this call, because the
precise answer needs a resolver the pass does not have there, and the errors are
asymmetric (over-suppress = a missed proof, silence; under-suppress = a false
positive on correct code).

Under `cap verified` a missed proof is not silence, so a withdrawal is visible —
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
**not** win at runtime — the gate does not care, and that is the point of the
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
   obligation's own argument**;
4. the spelling measures the same kind of thing as that argument — `List.length`
   for a list, `String.byte_size` / `string_byte_length` for a String.

Conditions 3 and 4 are what keep the reason from swallowing unrelated failures.
`if List.length(zs) > 0 do head(ys) else 0 end` is not a guard on `ys` — delete
the competing binding and it is undischarged all the same, so the withdrawal was
never the cause and "guard the call" is the correct advice. A negated guard,
`if List.length(ys) > 0 do 0 else head(ys) end`, does not fail to prove the
predicate — it *disproves* it, and with the binding removed reports a real
refinement violation, so it is never dressed up as a shadowing story. And since
all three spellings route to the single name `len`, condition 4 is what stops a
withdrawn `List.length` being blamed for an undischarged `{String | len(_) > 0}`.

The cost is coverage: a guard laundered through a local (`let n =
List.length(ys)`), applied to a non-variable actual, or established in a caller
falls back to the general message. That is the intended trade — the reason
exists to explain one specific confusion, not to claim every skip.

Verified 2026-07-29 (both triggers report `alias-withdrawn` with the causing
span; an unguarded call, a guard on a different variable, a cross-measure guard,
and a negated guard all still report `solver-undecided`, each matched against a
control with the competing binding deleted).

### `@[trusted]` — a scoped, loud escape hatch

`cap verified` is all-or-nothing at the module level: one obligation the
checker cannot discharge forces the author to either rewrite the predicate,
strengthen what the call site knows, or drop `cap verified` for the *entire*
module — even if every other function in it verifies cleanly. `@[trusted]` is
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
error above. With it, the obligation is still recorded — as its **own**
verdict, `Trusted`, never folded into `proved` — so `--refine-report` shows
exactly how much of a module's "verification" is actually an assertion rather
than a proof:

```
refinement obligations (user code): 0 proved, 0 violated, 1 trusted, 0 skipped
```

**This is a deliberate soundness hole, and it is scoped as narrowly as
possible on purpose:**

- **Only a `Skipped` obligation is eligible.** `@[trusted]` never suppresses a
  `Violated` — a predicate the solver *proved* can never hold is a bug in the
  annotation, not an incompleteness to wave through. `go() do inner(0 - 5) end`
  under `@[trusted]` still reports the refinement violation exactly as it
  would without the attribute.
- **Scoped to the one function that carries the attribute.** A sibling
  function in the same `cap verified` module that is not itself `@[trusted]`
  is unaffected — one annotation does not silently disarm the module.
- **A no-op outside `cap verified` warns.** `@[trusted]` only changes anything
  inside the `strict_verified` escalation path; on a function in a module that
  never declares `cap verified` it warns that the attribute has no effect,
  rather than silently doing nothing — the exact failure mode (an attribute
  that changes no behaviour, mistaken for one that does) this subsystem keeps
  producing.

Verified 2026-07-30. Corpus: `accept/t132` (an otherwise-undischargeable
`cap verified` module rescued by `@[trusted]`), `reject/t133` (a definite
violation inside a `@[trusted]` function is still reported).

**Scope and limits.** State these plainly before relying on it:

- **Strictly opt-in, and scoped to the decl list that declares it.** A
  `cap verified` module calling into an ordinary one does not make the callee's
  module strict — only obligations *raised* at call sites lexically inside the
  strict decl list escalate.
- **Not inherited by nested modules.** Deliberately: the compiler prepends the
  entire standard library as sibling module declarations, so an inherited flag
  would turn every stdlib module strict the moment one user module asked for
  verification.
- **Both preconditions and postconditions escalate (since 2026-07-30).** The
  ledger records both kinds (see `--refine-report` above), and `cap verified`
  now escalates a `Skipped` obligation raised at a call site *or* on a
  function's own return refinement — an undischarged postcondition is a
  compile error under `cap verified`, exactly like an undischarged
  precondition. This is the last place a fact was granted without obliging
  anyone; `cap verified`'s promise — "if it compiles, it is proved" — now
  covers return refinements too. `@[trusted]` reaches this escalation the same
  way it reaches `check_call`'s. Bracketed by
  `reject/t134_refine_postcondition_strict_undischarged` (an undecidable
  return refinement under `cap verified`) and
  `accept/t135_refine_postcondition_strict_trusted` (the same function rescued
  by `@[trusted]`).
- **Every declaration form is walked** (since 2026-07-29). The pass once walked
  only `DFn` and nested `DMod` and ended in a `| _ -> ()` wildcard, so calls
  inside an `impl` method, an `interface` default body, a top-level `let`, an
  actor handler or a `test` raised no obligation and could not escalate. Both
  this walk and `cap no_panic`'s division walk are now exhaustive over `A.decl`
  with no wildcard, so a new declaration form is a compile error rather than a
  silent hole. A `describe` block recurses and inherits the enclosing module's
  capability; a nested `mod` still re-derives its own.

  **What "walked" does and does not buy you.** Walking a body means obligations
  *raised inside it* are reported. Whether a **refinement written on an `impl`
  method's own parameter** is enforced is a separate question, and the answer is
  deliberately conditional:

  - The contract is adopted — registered so every caller must establish it —
    only when the method name unambiguously denotes it: no `fn` in the same
    module owns the name, and only one `impl` defines the method. A call
    resolved by NAME cannot tell two impls' contracts apart, and checking
    correct code against a predicate it never touches is the failure this
    subsystem must never have.
  - When the name is ambiguous the refinement binds **nobody**: the body is
    walked with it stripped, so it cannot discharge anything either. Unenforced
    means unusable in both directions — never "assumed in the body but demanded
    of no caller", which is how `fn run(b, k : {Int | k != 0})` once made
    `m / k` provable under `cap no_panic` while `run(Box(4), 0)` compiled and
    then divided by zero.
  - A refinement written in the **`interface`'s own method signature**
    (`fn run : a -> {Int | _ > 0} -> Int`) is still **not** enforced at call
    sites. Nothing assumes it either, so it is a missing check rather than an
    unsound one, but do not rely on it. Put the refinement on the `impl`
    method's parameter instead.
- **`cap no_panic`'s divisor check tries to DISCHARGE before it rejects**
  (since 2026-07-29). Every outcome short of `Refine.Verified` is an error —
  that is what the capability promises — but "we could not reflect the
  predicate" is not itself an outcome. A divisor refinement outside the linear
  fragment is now handed to z3 anyway: `{v : Int | v * v > 0}` is exactly
  `v != 0` over the integers, and rejecting it was a false positive on a
  *complete* proof. Predicates that reflect but prove nothing (`v * v >= 0`,
  true of every integer) come back `Refuted`, and ones z3 cannot decide come
  back `Unverified`; both are still errors. Path conditions are reflected with
  their negations on both routes, so the `else` side of `if d == 0` discharges
  the obligation exactly as `if d != 0` does on the `then` side. Bracketed by
  `accept/t121` and `reject/t122`.
- **Every fact `cap no_panic`'s divisor check reads is retired when its name is
  REBOUND** (since 2026-07-29). The divisor is identified by bare name, and so
  are all three channels — the path condition, the refined parameter, the `let`
  value — so a `let`, a lambda parameter, a `match` binder, a `let?` pattern or
  a local `fn` that rebinds that name drops everything known about the outer
  variable. Without it, `if d == 0 do 0 else (let d = 0; 10 / d) end` passed
  `--check` and then panicked. Note the direction: unlike the refinement pass,
  where dropping a fact means silence, dropping one here means an ERROR, so the
  retirement is deliberately over-approximate — a guard is re-established by
  re-stating it inside the rebinding scope. `reject/t123`.
- **`@[trusted]` (since 2026-07-30) is a per-function escape hatch.** See
  [above](#trusted--a-scoped-loud-escape-hatch). It accepts a `Skipped`
  obligation as an assertion — recorded as its own `Trusted` verdict, never a
  `Violated` — scoped to the one function that carries the attribute.

### Open holes, stated as of 2026-07-29

Everything above says what these capabilities *do*. This is the complementary
list — what a reader must not assume — kept here rather than only in
`specs/todos/` so that nobody reads a guarantee out of the absence of a
caveat. None of these is known to be *unsound* in the "assumed but unchecked"
sense; each is a check that does not happen.

1. **A refinement in an `interface`'s own method signature is unenforced.**
   Nothing assumes it either. Put it on the `impl` method's parameter.
2. **The measure-alias gates are unit-global.** One genuine competitor anywhere
   in the compilation unit — including in a `MARCH_LIB_PATH` dependency you
   never opened — disables `List.length` / `String.byte_size` /
   `string_byte_length` as measure aliases for the entire program. Under the
   default stance that is silence; under `cap verified` it is a build failure,
   which is why the `alias-withdrawn` reason exists.
3. **Postconditions are in the ledger and escalated (since 2026-07-30).**
   `check_post` records an obligation at every exit (proved, violated, or
   skipped with a reason), so `--refine-report` counts return refinements too,
   and `cap verified` now escalates an undischarged **return** refinement
   exactly as it already escalated an undischarged precondition. The
   2026-07-29 composition work remains confined to `check_call`, though: a
   parameter's promise composes into a *call* in the body, but `check_post`
   still composes no list or ADT measure through a **postcondition** — that is
   a separate, still-open gap from escalation.
4. **`@[trusted]` now reaches postconditions too (since 2026-07-30).** It
   suppresses the escalation both `check_call`'s and `check_post`'s `note`
   perform, scoped to the one function that carries the attribute.
5. **`collect_direct_names` in `lib/desugar/desugar.ml` still ends in a
   wildcard**, covering only `DFn` and `DLet`. It decides which self-qualified
   spellings `strip_entry_self_qual` rewrites, so an entry module that declares
   the name in some other form keeps the qualified spelling — which is what
   makes `accept/t126` / `t127` discriminating, but is a hole of the same
   family as the four that were closed.
6. **Impl-method contract adoption ignores `use`-imported impl methods** when
   judging whether a method name is ambiguous. The judgement is made over the
   compilation unit's own declarations; an impl brought in under a `use` is not
   counted as a competitor for the name.
7. **`alias-withdrawn` attribution does not follow a laundered guard.**
   `let n = List.length(ys)` followed by `if n > 0` falls back to the general
   `solver-undecided` message even when a withdrawal really was the cause.

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
  of an unreflected type is opaque, but only that field — its siblings are
  still checked at a call site. `String` supports only
  `len` and literal equality (see
  [String Refinements](#string-refinements)). Over a **variant**
  (multi-constructor) ADT the checker reasons about the constructor tag only
  (`is_Some(_)`), never the payload: `{Option(Int) | is_Some(_)}` is checkable,
  a predicate about the `Int` inside is not. Refinements over other types
  aren't supported.
- **A tag refinement composes only for the constructor the caller promised.**
  A constructor literal or a `match` narrowing establishes the fact where the
  call is written, and — since 2026-07-29 — so does the caller's own parameter
  contract: forwarding a `{Option(Int) | is_Some(_)}` *parameter* to a function
  expecting the identical contract is proved (`2 proved, 0 skipped`). A
  *different* constructor is deliberately not assumed: with
  `outer(p : {Option(Int) | is_None(_)})`, the call `inner(p)` against
  `is_Some(_)` stays **skipped** rather than reported, even though the two
  testers are exclusive. See [A Parameter's Own Contract Is a Fact Inside Its
  Body](#a-parameters-own-contract-is-a-fact-inside-its-body).
- **A refined `let` annotation is CHECKED against its bound expression**
  (since 2026-07-30). `let ys : {List(Int) | len(_) > 0} = []` is a refinement
  violation reported at the `let`, not a fact the checker adopts. Until that
  date the annotation was believed on sight: it entered the scope channel
  unconditionally, so a later call needing a non-empty list was reported
  **proved** off a premise nobody had established, and `cap verified` — whose
  premise is "if it compiles, it is proved" — accepted the module. That made
  a `let` annotation the one refined position in the language that obliged
  nobody.

  The obligation is the ordinary one, with the ordinary stance: the annotation
  is checked exactly as a call's argument is checked against a parameter's
  precondition, so an expression the checker can neither prove nor refute is
  **skipped**, never reported. An unproven annotation also **grants no fact** —
  it is not merely unverified-but-trusted. In

  ```march
  fn go(zs : List(Int)) : Int do
    let ys : {List(Int) | len(_) > 0} = zs
    inner(ys)
  end
  ```

  the annotation is undecidable (nothing is known about `zs`), so it is skipped
  *and* `inner(ys)` is skipped too, rather than proved off an assumption the
  binding failed to establish. All three spellings of the refined value behave
  alike — `_`, a declared binder (`{v : List(Int) | len(v) > 0}`), and the bound
  name itself (`len(ys) > 0`).
- **A contract that contradicts its own guard makes the guarded branch
  vacuously provable.** In `fn outer(ys : {List(Int) | len(_) > 0}) do if
  List.length(ys) == 0 do inner(ys) else 0 end end` the guarded call *proves*:
  the caller's promise and the guard cannot both hold, so the branch is dead
  code and its obligation is discharged against an unsatisfiable path. This is
  expected and safe-direction — the call can never execute with a violating
  value — not a gap in checking.
- **A local `let` does not carry a fact forward, for any type.** The pass
  propagates no local binding's value into a later goal, so `let u = 5` then
  `take_pos(u)` against `{Int | _ > 0}` is skipped, and the `List` analogue
  behaves identically. Pre-existing and unchanged; pass the value directly or
  restate the fact with `assert`.
- **Incomplete (by the definite-failure stance).** The checker catches values
  that are *definitely* wrong and stays silent otherwise. It will not prove
  every true property; quantified/measure facts in particular sometimes return
  "unknown" and are skipped. This never produces a false positive, but it does
  mean some real guarantees go unchecked.
- **Two higher-order shapes are checked; the rest are not.** A call made
  *through* a refined function-typed parameter is checked —
  `fn ap(f : ({Int | _ >= 0}) -> Int) : Int do f(-3) end` is now rejected,
  exactly like a direct call to a function whose parameter carries that same
  refinement. So is a call through a **local alias** of a named function:
  `let g = takepos  g(-3)` is rejected when `takepos`'s parameter is refined.
  Both are single-argument shapes only (a curried or tupled multi-argument
  callback type is out of scope, and fails typecheck on any call regardless).
  Still **not** checked:
  - a callback parameter whose *declared* type is unrefined, even when the
    concrete function passed as an argument is itself refined — `apply(f :
    Int -> Int, x : Int) : Int do f(x) end` called as `apply(take_n, -3)`
    stays silent, because `apply` never declared a contract on `f` for the
    checker to enforce (see `accept/t77_refine_hof_bypass_limitation.march`).
    The existing workaround still applies: refine the higher-order function's
    *own* parameter type (`f : ({Int | _ >= 0}) -> Int`) to make the caller's
    obligation explicit and checkable;
  - inferring a higher-order function's own requirement from its body — the
    checker never looks inside `f` to derive what `f` needs, it only checks
    what the caller's own declared type or a resolvable alias already states;
  - dispatch through an `interface`/`impl` — which concrete implementation
    runs is not resolved by this pass, so no refinement travels through it.
- **Why general higher-order/polymorphic flow is structurally out of reach —
  the architectural ceiling.** `TRefine` (the internal type-carry for `{T |
  p}`) is deliberately **transparent to unification**: `repr` strips it to the
  base type, which is what keeps refinements invisible to `occurs`,
  generalization, instantiation, and the rest of the ~35 sites that canonicalise
  through `repr` — only 8 sites needed bespoke handling. But the same
  transparency means a refinement survives only where it is *not unified*,
  i.e. on a function's own declared parameters at a direct call. The moment a
  refined function's type is unified against a polymorphic slot (`apply(f, x)`
  with `apply(f, x) = f(x)`), unification strips the predicate before the
  callee's body ever sees it — so `apply(take_n, -3)` typechecks even though
  `take_n : {Int | _ >= 0} -> Int`. This is not a missing case to fill in; it
  is what transparent-`repr` `TRefine` means. The only known route past it is
  making refinements *participate* in unification as a subtyping relation
  (`{T | p} <: {T | q}` discharged as a real SMT obligation instead of
  stripped) — a fundamentally larger change to the bidirectional core, since it
  also requires threading a path/assumption context through `infer_expr`/
  `check_expr` that does not exist today, and it flips the soundness contract
  from "report only definite failure" to "prove or reject," which reopens the
  false-positive risk the current design was built to avoid. That path
  (internally "Path 2: refinement subtyping in unification") was explored and
  explicitly **shelved** as a separate future project rather than pursued now:
  it is a multi-month, quarter-scale core-typechecker effort with real
  abandonment risk, while the shipped direct-call/path-sensitive checker
  already delivers most of the practical value (preconditions, bounds, path
  sensitivity, postconditions) at a fraction of the cost. If it is ever
  revisited, the plan is to validate the subtyping judgment's soundness in
  March's Lean 4 mechanization track first, and to keep it independent of the
  `apply`-style `infer_app` precondition emission that was also considered and
  rejected (it would regress path sensitivity without adding higher-order
  checking).
- **Measures see structure, not elements.** Element values inside a data
  structure are opaque to a measure (`size`/`len`/`depth` never inspect them).
  Measures are single-argument, structurally recursive, and return `Int`/`Bool`.
- **An unproven postcondition does not reach callers.** If the checker can't
  prove a declared return refinement at the definition (an opaque body, a
  predicate it can't reflect, or a body that routes its value through a local
  `let` binding rather than returning it directly), the declaration is still
  accepted but callers learn nothing from it. Only proven postconditions are
  assumed at call sites.
- **Relational postconditions propagate, but only as far as the definition side
  got.** A return refinement mentioning a parameter (`{Int | _ == n + 1}`,
  `{Int | _ < len(xs)}`) *is* instantiated at call sites by substituting the
  call's arguments — but only if the definition **proved** it, so a relational
  contract the solver cannot discharge travels no further than a closed one
  would. Propagation is also skipped when an argument is missing, when the
  predicate mentions anything that is neither the binder nor a parameter, or
  when the callee takes a pattern parameter. See the propagation section above.
- **Structural induction (Tier 2): relating a measure across a recursive
  operation now works, within a narrow shape.** `size(insert(t, x)) == size(t)
  + 1` *is* provable automatically, and therefore propagates to call sites. Z3
  still does no induction; what the checker supplies is the **induction
  hypothesis** — at a self-recursive call whose argument is a *proper component*
  of the matched parameter, the function's own postcondition is assumed about
  that call's result, and each `match` arm is then discharged separately against
  the measure's recursion equations.

  **What is proven:**
  - a single-clause, unguarded function whose whole body is a `match` on one
    parameter, with flat constructor-pattern arms;
  - a return refinement over a **variant ADT** (`{Tree | …}`, `{List(Int) | …}`)
    whose predicate mentions a **`@[measure]`**;
  - self-recursion into any recursive component (left or right, it is the
    pattern that decides, not a position);
  - **relational** (`size(_) == size(t) + 1`) and **closed** (`size(_) >= 1`)
    predicates alike;
  - an accumulator parameter that *grows* — the induction is on the matched
    parameter alone, so the hypothesis is universally quantified over the rest.

  **What is not, and stays silent:**
  - **the built-in `len`.** Only a user `@[measure]` is axiomatised, so only a
    user measure carries recursion equations for the induction to reduce
    through. Declaring `@[measure] fn llen(xs : List(Int)) : Int` over the same
    list is the workaround, and it does prove.
  - **mutual recursion.** The hypothesis is minted only for a call to the
    function's *own* name, so two functions that call each other prove nothing.
  - **a recursive call inside a lambda, or behind a nested `match`.** Only the
    top-level `match`'s pattern equation is asserted, so an arm whose tail sits
    under a second `match` cannot see the inner scrutinee's shape.
  - **non-structural recursion.** A recursive call on the whole parameter, on a
    reconstructed value, or on anything `structural_subvars` does not certify as
    a component gets **no** hypothesis. This is a correctness requirement, not a
    completeness one: a proven postcondition is *added* to the assumption set
    that call-site checks prove `¬goal` against, and adding assumptions makes a
    violation easier to prove — so an unsound hypothesis would manufacture false
    positives on correct code, not merely fail to help.
  - **anything needing a lemma.** A true property the hypothesis alone cannot
    reach returns unknown and is skipped. Use an `assert` lemma there.

  Int-returning postconditions are unaffected: they still go down the Tier 0/1
  path, which this does not touch.

- **The stdlib HAMT (`Map`) is well beyond this.** `stdlib/map.march` stores
  `HEntry(k,v) = HEmpty | HLeaf(Int,k,v) | HBranch(Int, List(HEntry(k,v))) |
  HCollision(Int, List((k,v)))` and inserts via a hash-indexed descent. A local
  reduced model shows **three stacked obstacles**, in the order they bite:
  1. **The built-in `List`'s element sort is opaque.** The checker models
     `List` as `Nil | Cons(Elem, List)` with `Elem` an uninterpreted sort, so a
     count measure that must recurse *into* a list element (`lcount(Cons(h,t)) =
     hcount(h) + lcount(t)`, where `h : Elem` but `hcount : HEntry -> Int`) is
     ill-sorted and is dropped — neither measure gets axiomatised, and nothing
     downstream can run. Substituting a *user-defined* child list for the
     built-in one, changing nothing else, makes the same postcondition prove and
     propagate. This obstacle precedes induction entirely.
  2. **The nested `match`.** With (1) worked around, `node_insert` still reaches
     its child by matching the child list, so the tail lives under a second
     `match` whose pattern equation is not built (see above). Bounded and
     addressable.
  3. **The child is fetched by index, not bound by a pattern.** The real code
     does `let child = list_nth_safe(children, idx)`. `structural_subvars`
     certifies pattern binders only, so `child` is not structurally smaller by
     any test the checker has — and it would need a length/termination lemma
     the checker cannot currently state. On top of that the real `HEntry` is
     generic in `k`/`v`, `Map` wraps it in a `ptype`, and `node_insert` carries
     an `eq` callback and a `level` counter, none of which the measure
     machinery models.

  So: the answer to "does the structural test recognise a child fetched from a
  `List` by index?" is **no** — and obstacle (1) stops the measure from existing
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
  cannot write a predicate that says "not NaN"; see
  [Float Refinements](#float-refinements) for why NaN nevertheless never causes
  a false report.
- **An AXIOMATISED measure applied to the refined value itself is now
  enforced against the actual argument** (fixed 2026-07-29 — this bullet
  previously documented the opposite as a limitation, and that limitation was a
  *bug*). The axiomatised resolver discarded the actual and reasoned about an
  unconstrained placeholder tree instead, so a `{Tree | size(_) > 0}` contract
  checked nothing at all: `inner(Leaf)` was accepted and
  `inner(Node(Leaf, 5, Leaf))` was not proved — both merely skipped, and a skip
  exits 0 exactly as a proof does. Re-verified 2026-07-29 in every direction:
  `inner(Leaf)` against `{Tree(Int) | size(_) > 0}` is **reported** (exit 1),
  `inner(Node(Leaf, 5, Leaf))` is **proved** (exit 0, `1 proved`), `big(Leaf)`
  against `{v : Tree(Int) | size(v) > 2}` is now **reported** rather than
  silent, and `{v : Tree(Int) | size(v) < 0}` is still caught for any argument
  from the non-negativity axiom alone. So a constructor literal in this
  position has its measure computed from the recursion equations, exactly as a
  measure applied to a *different* parameter always did (`get(Node(Leaf, 5,
  Leaf), 3)` above), and exactly as the built-in list `len` does for `head([])`
  against `{List(a) | len(_) > 0}`. The same fix is what lets an ADT measure
  contract compose across a call boundary — see [A Parameter's Own Contract Is
  a Fact Inside Its Body](#a-parameters-own-contract-is-a-fact-inside-its-body).

  What genuinely stays out of reach is the shape with nothing to reflect: where
  the argument is neither a constructor literal nor a variable the pass can
  name, the unconstrained placeholder is still the fallback and the obligation
  is skipped.
- **Performance: measures can be slow on a cold cache.** Quantified + datatype
  reasoning is far more expensive per query than plain arithmetic. Verdicts are
  content-addressed and cached (warm rebuilds are fast), and the cost is
  isolated to call sites that actually mention a measure — but a cold build of
  measure-heavy code pays for it. See the flag below.
- **A predicate can call a name the checker doesn't understand — it now says
  so.** Predicate bodies aren't typechecked, so `{Int | totally_bogus_fn(_) >
  0}` used to compile clean and enforce nothing. The checker now warns when a
  predicate applies a function outside its known vocabulary: the comparison,
  arithmetic, and boolean operators (`==`, `!=`, `<`, `<=`, `>`, `>=`, `+`,
  `-`, `*`, `negate`, `not`, `&&`, `||`), the built-in `len`, every ADT's
  `is_<Ctor>` tester, and any function annotated `@[measure]`. This is a
  Warning, not an Error — the program still
  compiles — but it tells you the refinement it's attached to is not actually
  checked, so you can annotate the function `@[measure]` or switch to a
  supported predicate.

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

Two higher-order call shapes have since been closed (348 refinecheck tests as
of 2026-07-29 — 16 covering Tier 2 structural induction, 9 covering `Bool` and
`Float` refinements, and 8 covering call-boundary contract composition):
a call through a refined function-typed *parameter*, and a call through a
*local alias* of a named refined function — both previously fell through
`resolve_call`'s named-callee-only resolution and were silently skipped.
`accept/t77_refine_hof_bypass_limitation.march` remains a passing, UNCHANGED
fact of the corpus: its `apply`'s callback parameter is declared `Int -> Int`
(unrefined), so it still demonstrates the boundary that *is* still out of
reach — a caller's own contract is only enforced when it is actually
declared refined, never inferred from what the callback happens to point to.

The typing corpus now stands at **229 programs (114 accept, 115 reject)**, with
each refinement feature bracketed from BOTH sides. That pairing is deliberate
and load-bearing: an accept-only witness cannot distinguish a working contract
from one that silently checks nothing, which is exactly how the `_` and
named-binder spellings of a measure over the refined value shipped unenforced
until 2026-07-27 (`accept/t115`–`t117`, `reject/t114`–`t116`; `reject/t116`
additionally pins that a contract declared in a *stdlib* signature reaches a
user call site at all). The `List.length` → `len` alias added 2026-07-28 is
bracketed the same way (`accept/t118`, `reject/t117`): the accept file exits 0
whether the guard is read or the obligation is merely skipped, so only the
reject file shows the alias is load-bearing. Call-boundary **composition**
(2026-07-29) is bracketed the same way and for the same reason
(`accept/t128`, `reject/t129`): the accept file exits 0 whether the inner call
composed or was silently skipped, so only the reject file — where a
deliberately weaker caller contract must NOT launder the stronger callee
requirement, while a real violation on the same shape is still caught — shows
that composition fires exactly where it should and nowhere else. Two witnesses
pin soundness rather than a feature:
`accept/t110` (an unproven postcondition must not propagate) and `accept/t113`
(a NaN-only `Float` predicate must stay satisfiable — it fails the moment
anyone re-encodes floats as reals).

On the operational side, golden `g46_refinement_erasure` is the only refinement
program in the 46-program golden corpus, and it exercises `{Int | _ >= 0}`
only. Erasure was separately re-verified 2026-07-27 for every later form — ADT
tags, `Bool`, `Float`, `String` `len`, non-empty `List`, and the stdlib
`List.head`/`Option.unwrap` contracts — by diffing interpreted against compiled
output on one program using all of them: byte-identical, exit 0 both. The
golden corpus itself remains 46/46 MATCH.

## Next Steps

- [Type System](types.md) — the types refinements attach to
- [Linear Types](linear-types.md) — the other compile-time safety layer
- [Pattern Matching](pattern-matching.md) — `match` guards feed path sensitivity
