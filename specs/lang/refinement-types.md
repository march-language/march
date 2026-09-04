---
layout: docs
title: Refinement Types
nav_order: 5.5
permalink: /docs/refinement-types/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Refinement Types

A **refinement type** attaches a logical predicate to an ordinary type:
`{Int | _ >= 0}` is "an `Int` that is non-negative". March discharges these
predicates with an SMT solver (Z3) at compile time, so a whole class of bugs
(out-of-bounds indices, negative sizes, division by zero, broken invariants)
becomes a **compile error** instead of a runtime panic.

Refinements are March's pragmatic slice of **dependent typing**: types that
depend on *values*. You get the safety where it pays off (preconditions,
bounds, postconditions) without a proof assistant's ceremony; and, crucially,
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
connectives `&& || not`, integer/bool literals, **measures**, and ADT
**constructor tags** (both below). `String` values are supported to the
narrower extent described in [String Refinements](#string-refinements): `len`
and `==`/`!=` against literals. `Bool` values take the boolean operators against
`true`/`false` ([Bool Refinements](#bool-refinements)); `Float` values take
comparisons against float literals, discharged through Z3's bit-precise IEEE-754
theory rather than reals ([Float Refinements](#float-refinements)).

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
checker cannot translate to SMT (nonlinear arithmetic, an opaque call) are
dropped from the query rather than guessed at. That keeps the checker sound
when it *proves* things, but it means a raw "here is a failing input" model
can describe a state your program never reaches:

```march
fn always_one(x : Int) : {Int | _ >= 0} do
  if x * x >= 0 do 1 else x end     -- the else branch is unreachable
end
```

`x * x >= 0` is nonlinear, so the guard is dropped and the solver happily
"refutes" the contract through the `else` branch. Printing that model would
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

### What String refinements do *not* do

The encoding models `String` as an **opaque sort** with `len` as an uninterpreted
function, intentionally outside any SMT string theory, so queries stay decidable
and cheap. Two consequences are worth spelling out clearly:

- **A `== ""` guard does not establish a length.** In

  ```march
  if s == "" do 0 else nonempty(s) end
  ```

  the else-branch knows only that `s` is *distinct from* the empty literal. There
  is no axiom relating a string's identity to its length, so `len(s) > 0` does not
  follow and the call is silently skipped. This is a real gap, not an oversight:
  closing it needs an injectivity axiom with a cost assessed as not worth it.
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
  component of the matched parameter.

A measure that is sound but outside what the encoding can model (see
limitations) isn't an error: it simply falls back to weaker, symbolic
reasoning. "Weaker" can mean *no reasoning at all*: a measure with a value that is a
scalar constructor field discharges neither a predicate nor its negation, and
that case is not always warned about. See [Limitations](#limitations).

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

The name is **exact-case**: `is_Some` is the tester for the constructor `Some`;
`is_some` is not a tester at all (it happens to be the lowercase stdlib helper
`Option.is_some`), so a misspelling draws the unrecognized-predicate warning
rather than silently meaning something else.

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

> **Clear `.march/cas/artifacts-v2` first.** A `--check` run with sources that hash to
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

Each skip is attributed to one of nine reasons:

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
| `solver-undecided` | the solver proved neither the predicate nor its negation |

`unconstrained-subject`, `partial-conjunct`, and `opaque-application` are also
refinements of `solver-undecided`: the VC was built and the solver ran, and each
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
or postcondition), printed as a `by kind` breakdown line under each slice's
headline; the headline totals themselves do not distinguish kinds; a proved
postcondition is a proved obligation like any other. `cap verified` still
escalates precondition obligations only; see below.

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
re-runs the *real* checker over the function, and keeps the candidate only if
the ledger's debt actually shrank and no new violation appeared.

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

See [docs/tooling.md](https://github.com/march-language/march/blob/main/docs/tooling.md)
for the full command surface, including `--apply` and the editor code action.

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

- **Enforced** — the checker's own extractor for this position accepts the
  declared type, so an obligation gets filed against it (at a call site for
  a parameter, or against the function's own body for a postcondition). A
  parameter with no caller yet still counts Enforced: what matters is that
  the position is wired into the checker's scope machinery, not whether a
  call site exists today. See below for why this reading is correct rather
  than a loophole.
- **Inert (warned)** — a `sig` entry, an `extern` signature, or an
  `interface` method whose refinement the compiler already names in its own
  warning. Nothing new here; the audit confirms that warning still fires.
- **Unenforced** — declared, silent, and nothing tells you. No extractor
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
refinement is Unenforced — there is no extractor for a stored field at all,
only for a parameter, a return, or a let-binding. The `user + stdlib` total
(65) is this file's own 2 sites plus the 63 the shipped stdlib always
contributes.

### Why an uncalled parameter still counts as Enforced

This is the design's central subtlety. Enforcement is not a property of
having a caller; it is a property of the checker's scope machinery accepting
the declared type at all. `refined_param_ty` running over
`fn f(n : {Int | n > 0}) : Int do ... end` registers `n > 0` as a fact
inside `f`'s body and would raise an obligation at *any* call site, present
or future — adding one tomorrow gets checked automatically, because the
position is already wired in. This is the same distinction
`--refine-report` already draws between an obligation that is unproven and
one that was never filed; the audit stays consistent with it instead of
inventing an incompatible second notion of "checked."

Contrast a lambda's own parameter (`fn (n : {Int | n > 0}) -> n`): no scope
machinery ever runs over an `ELam`'s parameters, so *no* call through that
lambda, ever, is obliged by it — genuinely Unenforced, not merely uncalled.

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
does nothing — but an audit that silently broke would also report an empty
baseline, which is why a second, deliberately non-empty fixture set exists:
`test/refine_audit/holes/`, one small program per known unenforced position
(a lambda's own parameter, a block-level `fn`'s parameter and return, a
non-adoptable `impl` method's parameter, an actor's state field and handler
parameter, a nested field refinement, and a `{String | ...}` return),
pinned at `test/refine_audit/holes.baseline`. If that baseline ever reports
zero Unenforced sites, the audit itself is broken; the test that diffs it
fails loudly rather than passing.

The positions currently known to be Unenforced, none of which the corpus
above happens to exercise:

- A lambda's own parameter.
- A block-level `fn`'s own parameter and return type: `check_fn_post_verdict`
  and `scope_add_param` are reached only through `A.DFn` / `A.DImpl`, never
  through a local `A.ELetFn`.
- An `impl` method's parameter, when the method's bare name is not
  adoptable (more than one `impl` defines it, or a top-level `fn` shares the
  name): `visit_decl` strips the refinement from the body in that case, and
  no caller is ever obliged. The audit reports every `impl` method
  parameter Unenforced regardless of actual adoptability, since a single
  site cannot make that module-level judgement — when the method *is*
  adoptable the checker does enforce it, so this is a documented
  conservatism in the audit, not a hole in the checker.
- An actor's state field, and a handler's own parameter: no extractor
  exists for either.
- A record field or a variant constructor argument, once a value is
  constructed.
- A refinement nested below the outermost position of a declared type.
- A `{String | ...}` return type: `return_refine_ext` only recognizes Int,
  Bool, Float, and record bases.

See `specs/todos/2026-09-03-lambda-param-refinement-unchecked.md`,
`specs/todos/2026-09-03-block-fn-refinement-unchecked.md`,
`specs/todos/2026-09-03-impl-method-param-refinement-unchecked.md`,
`specs/todos/2026-09-03-actor-state-and-handler-refinement-unchecked.md`,
`specs/todos/2026-09-01-nested-refinement-enforcement.md`, and
`specs/todos/2026-09-03-string-return-refinement-unchecked.md`.

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
promotion still fires but the `help:` is omitted. `Stats.quantile_default`
(`stdlib/stats.march`) is exactly this shape: `quantile` requires both
`len(_) > 0` on its list and `_ >= 0.0 && _ <= 1.0` on its float, and it reports
with no `help:` block.

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
  a predicate about the `Int` inside is not. Refinements over other types
  aren't supported.
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
  violation reported at the `let`, not a fact the checker adopts. Until that
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
  *through* a refined function-typed parameter is checked:
  `fn ap(f : ({Int | _ >= 0}) -> Int) : Int do f(-3) end` is now rejected,
  exactly like a direct call to a function with a parameter that has that same
  refinement. So is a call through a **local alias** of a named function:
  `let g = takepos  g(-3)` is rejected when `takepos`'s parameter is refined.
  Both are single-argument shapes only (a curried or tupled multi-argument
  callback type is out of scope, and fails typecheck on any call regardless).
  Still **not** checked:
  - a callback parameter with a *declared* type that is unrefined, even when the
    concrete function passed as an argument is itself refined: `apply(f :
    Int -> Int, x : Int) : Int do f(x) end` called as `apply(take_n, -3)`
    stays silent, because `apply` never declared a contract on `f` for the
    checker to enforce (see `accept/t77_refine_hof_bypass_limitation.march`).
    The existing workaround still applies: refine the higher-order function's
    *own* parameter type (`f : ({Int | _ >= 0}) -> Int`) to make the caller's
    obligation explicit and checkable;
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
    equation. Unlike the `match` shape, this one also **records its verdict in
    the obligation ledger**, so `--refine-report` distinguishes "attempted and
    proved" from "never looked at"; it still emits no diagnostic either way;
  - a return refinement over a **variant ADT** (`{Tree | …}`, `{List(Int) | …}`)
    with a predicate that mentions a **`@[measure]`**;
  - self-recursion into any recursive component (left or right, it is the
    pattern that determines it, not a position);
  - **relational** (`size(_) == size(t) + 1`) and **closed** (`size(_) >= 1`)
    predicates alike;
  - an accumulator parameter that *grows*: the induction is on the matched
    parameter only, so the hypothesis is universally quantified over the rest.

  **What is not, and stays silent:**
  - **the built-in `len`.** Only a user `@[measure]` is axiomatised, so only a
    user measure includes recursion equations for the induction to reduce
    through. Declaring `@[measure] fn llen(xs : List(Int)) : Int` over the same
    list is the workaround, and it does prove.
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

  Consequence: `Array.get`/`set`/`pop` cannot be given a dischargeable bounds
  contract today and remain on `cap no_panic`'s syntactic ban list. Fixing this
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
  measure-heavy code pays for it. See the flag below.
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
Limitations section states is now a passing corpus fact, not only prose:
`accept/t77_refine_hof_bypass_limitation` proves a refined function called
*through* a higher-order parameter is NOT checked, even when the identical
literal at a direct call site is rejected. `cap no_panic`'s division-safety
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
`accept/t77_refine_hof_bypass_limitation.march` remains a passing, UNCHANGED
fact of the corpus: its `apply`'s callback parameter is declared `Int -> Int`
(unrefined), so it still demonstrates the boundary that *is* still out of
reach: a caller's own contract is only enforced when it is actually
declared refined, never inferred from what the callback happens to point to.

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

## Next Steps

- [Type System](types.md): the types refinements attach to
- [Linear Types](linear-types.md): the other compile-time safety layer
- [Pattern Matching](pattern-matching.md): `match` guards feed path sensitivity
