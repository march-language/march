---
layout: docs
title: Lemmas
nav_order: 5.55
permalink: /docs/lemmas/
---

> Part of the March Language Reference; see [specs/lang/index.md](index.md).

# Lemmas

A **lemma** is a function that proves something. You mark it `@[lemma]`, state a theorem in
its result type, `{Unit | P}`, and write the proof as ordinary March code: a `match` or an
`if` to split cases, a recursive call for induction, calls of other lemmas, and `assert` for
an intermediate step. The compiler checks the proof with the z3 solver on every build. Once
a lemma is proved, its theorem is a fact after every call of it, and the
[refinement checker]({{ site.baseurl }}/docs/refinement-types/) can use that fact to prove
your contracts.

A lemma never runs. The compiler removes every lemma, and every call to one, before the
program is built, interpreted or loaded in the REPL. A program behaves exactly as it would
with its lemmas deleted, so a lemma costs nothing at run time.

Lemmas are also useful outside refinements. `forge test` tests the lemmas it can't prove,
and re-runs the proved ones to catch a compiler bug. `forge doc` lists them as laws of the
functions they mention, `forge search --law` finds them, and the editor offers rewrites they
justify. A lemma in a `cap verified` module is a law the build enforces: a change that
breaks it fails the build.

This page shows how to write lemmas, how to use them, and what they don't do yet. The
[Refinement Types]({{ site.baseurl }}/docs/refinement-types/#lemmas-proving-what-one-unfolding-cannot)
chapter has the reference summary.

## On this page

**Start here**

- [Which tool do I need?](#which-tool-do-i-need)
- [How it fits with the rest of March](#how-it-fits-with-the-rest-of-march)
- [Why lemmas: one unfolding is not induction](#why-lemmas-one-unfolding-is-not-induction)
- [Your first lemma](#your-first-lemma)

**Writing lemmas**

- [The five rules](#the-five-rules)
- [Induction: a recursive call](#induction-a-recursive-call)
- [Steps: `assert` inside a lemma](#steps-assert-inside-a-lemma)
- [Decided steps and fuel](#decided-steps-and-fuel)
- [When a lemma does not prove](#when-a-lemma-does-not-prove)
- [When a lemma is false](#when-a-lemma-is-false)

**Using lemmas**

- [A call gives the caller a fact](#a-call-gives-the-caller-a-fact)
- [Hypotheses: refined parameters](#hypotheses-refined-parameters)
- [A fact stays in its branch](#a-fact-stays-in-its-branch)
- [Arguments must be pure](#arguments-must-be-pure)
- [`cap verified`: proofs required](#cap-verified-proofs-required)
- [Lemmas from the standard library](#lemmas-from-the-standard-library)
- [Which lemma to call: `--refine-infer`](#which-lemma-to-call---refine-infer)

**Lemmas beyond refinements**

- [Tested by `forge test`](#tested-by-forge-test)
- [Catching a miscompile](#catching-a-miscompile)
- [Laws in `forge doc`](#laws-in-forge-doc)
- [Finding laws: `forge search --law`](#finding-laws-forge-search---law)
- [Rewrites in the editor](#rewrites-in-the-editor)
- [Interface laws](#interface-laws)
- [Which functions have laws: `--law-coverage`](#which-functions-have-laws---law-coverage)
- [Lemmas as a spec for code someone else writes](#lemmas-as-a-spec-for-code-someone-else-writes)

**Limits**

- [What lemmas don't do (yet)](#what-lemmas-dont-do-yet)
- [See also](#see-also)

## Which tool do I need?

| You want | Write |
|---|---|
| The checker to know a fact it can't work out by itself | A `@[lemma]` that proves it, called before the place that needs it |
| A proof by induction over a list or tree | A lemma that matches on the value and calls itself on the smaller part |
| To spell out one step of a longer proof | `assert step` inside the lemma |
| The checker to follow a function's calls further | `@[reflect(fuel: N)]` on that function (default 2, at most 8) |
| A theorem that only holds for some inputs | Refined parameters on the lemma: `n : {Int \| _ >= 0}` |
| Every lemma in a module to be proved, or the build fails | `cap verified` in that module |
| To know whether a law you can't prove yet is even true | Leave it unproved; `forge test` tests it on generated inputs |
| To find the laws about a function | `forge search --law NAME`, or the "Laws" list on its `forge doc` page |

## How it fits with the rest of March

| Concept | Where lemmas meet it | Chapter |
|---|---|---|
| **Refinement types** | A lemma's theorem is a refinement on `Unit`. A proved lemma gives the checker a fact it can use to prove other contracts. | [Refinement Types]({{ site.baseurl }}/docs/refinement-types/) |
| **Reflection** | A theorem can call your own functions because the checker reflects them: pure, total, terminating functions become definitions the solver can unfold. | [Reflection]({{ site.baseurl }}/docs/refinement-types/#reflection-your-functions-in-predicates) |
| **Termination** | A recursive lemma is an induction only if its recursion terminates. The checker uses the same termination check as `--termination-report`. | [Termination]({{ site.baseurl }}/docs/refinement-types/#termination---termination-report) |
| **Pattern matching** | A `match` in a lemma splits the proof into cases; each arm proves the theorem for its shape. | [Pattern Matching]({{ site.baseurl }}/docs/pattern-matching/) |
| **Capabilities** | `cap verified` turns an unproved lemma, or a lemma call whose hypothesis is not proved, into an error. | [Capabilities]({{ site.baseurl }}/docs/capabilities/) |
| **Testing** | `forge test` runs each lemma's theorem on generated inputs, as a property test or as a check of the compiler. | [Tooling](https://github.com/march-language/march/blob/main/docs/tooling.md) |

---

## Why lemmas: one unfolding is not induction

The refinement checker can use your own functions in a contract. When it meets a call such
as `cat(xs, ys)`, it **unfolds** it: it replaces the call with the function's body, as far
as the facts it has can decide which arm runs. Here is list concatenation, and a function
that demands its second argument equal its first:

```march
mod Main do
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  fn need_eq(a : List(Int), _b : {List(Int) | _ == a}) : Int do 0 end

  fn left(ys : List(Int)) : Int do
    need_eq(ys, cat(Nil, ys))          -- proved: one unfolding of cat
  end

  fn right(xs : List(Int)) : Int do
    need_eq(xs, cat(xs, Nil))          -- not proved
  end

  fn main() : Int do 0 end
end
```

`cat(Nil, ys) == ys` takes one unfolding: the first argument is `Nil`, so the first arm
runs. `cat(xs, Nil) == xs` is just as true, for every list, but the checker can't see it.
With `xs` unknown it doesn't know which arm runs. Even if it took the `Cons` arm, it would
be left with `cat(t, Nil) == t`, the same question one element shorter. No number of
unfoldings settles it. The checker says so in a hint:

```
precondition `_ == a` on `need_eq` was NOT verified here. [refinement_unverified]
the proof may need more unfolding of `cat`; add a lemma call or `assert`, or raise `@[reflect(fuel: N)]`
```

A question that comes back one element smaller is a proof by **induction**. It holds for
`Nil`; and if it holds for `t`, it holds for `Cons(h, t)`. The checker doesn't do induction
by itself. A lemma is how you give it one.

## Your first lemma

```march
mod Main do
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end

  fn need_eq(a : List(Int), _b : {List(Int) | _ == a}) : Int do 0 end

  fn right(xs : List(Int)) : Int do
    cat_nil(xs)
    need_eq(xs, cat(xs, Nil))          -- proved: the lemma's theorem holds here
  end

  fn main() : Int do 0 end
end
```

Read `cat_nil` as a proof:

- **The theorem** is in the result type: `cat(xs, Nil) == xs`, for every `xs`. The value
  is `()`; what matters is the predicate.
- **The `Nil` arm** is the base case. Here `cat(Nil, Nil)` unfolds to `Nil`, so the theorem
  holds and the arm returns `()`.
- **The `Cons` arm** is the step. The call `cat_nil(t)` gives the fact
  `cat(t, Nil) == t`. That is the induction hypothesis. Unfolding `cat(Cons(h, t), Nil)`
  once gives `Cons(h, cat(t, Nil))`, which the hypothesis turns into `Cons(h, t)`.

The checker proves the theorem at every place the body returns. When it does, the lemma is
**admitted**, and every call of `cat_nil` adds `cat(xs, Nil) == xs` for the arguments of
that call. In `right`, that is the fact `need_eq` needed.

---

## The five rules

A lemma never runs, so nothing at run time can catch a false one. The rules below make sure
a body that the checker accepts really is a proof. A lemma that breaks one is the error
[`invalid_lemma`]({{ site.baseurl }}/docs/errors/invalid_lemma/), which names the rule.

- **L1. The result type is `{Unit | P}`.** `P` is the theorem. It talks about the
  parameters, not about the unit value `_`.
- **L2. The body is total and pure.** No effects (`println`, `send`, `spawn`). No way to
  fail: no `panic`, `todo`, typed hole, a division the checker can't prove safe, or a
  `match` that might not match. No lambdas. The body never binds a parameter's name again,
  with a `let` or a pattern, because the theorem is about the parameters as they were
  passed in. `assert` is allowed, as a proof step.
- **L3. It calls only what the logic knows:** reflected functions, other lemmas,
  constructors, and the builtins the solver understands (arithmetic and comparisons on `Int`
  and `Float`, `&&`, `||`, `not`).
- **L4. Recursion must terminate.** A recursive call is an induction hypothesis, and that is
  only sound when the recursion is on something smaller, so the checker must be able to
  prove that the recursion ends.
- **L5. It is only ever called.** A lemma can't be passed as a value, and can't also carry
  `@[opaque]`, `@[measure]`, `@[diverges]`, `@[trusted]` or `@[assume]`.

Each rule closes one way to "prove" something false. A `panic` path proves anything on that
path. An effect would silently vanish when the call is removed. A function the logic can't
see has no definition to reason with. An induction over a recursion that doesn't end is
circular. A lemma used as a value would have to exist at run time.

## Induction: a recursive call

Recursion in a lemma is induction. Match on the value, prove the small cases directly, and
in the others call the lemma on the smaller parts. Each recursive call adds the theorem for
those parts, which is the induction hypothesis.

Associativity of `cat` is induction on the first list. The other two arguments pass through
unchanged:

```march
mod Main do
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  @[lemma]
  fn cat_assoc(xs : List(Int), ys : List(Int), zs : List(Int)) : {Unit | cat(cat(xs, ys), zs) == cat(xs, cat(ys, zs))} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_assoc(t, ys, zs)
    end
  end

  fn main() : Int do 0 end
end
```

The checker accepts the recursive call as a hypothesis only when two things hold:

- the recursion terminates. Here it is structural: `t` is part of the matched `xs`. A lemma
  that recurses on something else needs a termination metric, as any function does
  (see [Termination]({{ site.baseurl }}/docs/refinement-types/#termination---termination-report));
- the call meets the lemma's own hypotheses, if its parameters are refined
  ([below](#hypotheses-refined-parameters)).

A lemma can also call other lemmas. Their theorems become facts for the rest of the arm.
That is how a long proof is split into small ones, as in the next section.

## Steps: `assert` inside a lemma

Outside a lemma, `assert` is checked at run time, and the checker assumes it afterwards.
Inside a lemma nothing runs, so `assert` means something else: it is **a step of the proof**.
The checker proves the asserted fact from what it knows at that point, and then uses it for
the rest of the proof.

An `assert` the checker can't prove is reported, and the proof goes on **without** it. It is
never assumed. So `assert false` proves nothing, and a wrong step can cost you the proof but
can never make a false theorem pass.

Here is `rev(rev(xs)) == xs`. It needs two helper lemmas, and five `assert` steps when the
checker is only allowed one unfolding per call (`@[reflect(fuel: 1)]` on `cat` and `rev`;
fuel is the next section):

```march
mod Main do
  @[reflect(fuel: 1)]
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  @[reflect(fuel: 1)]
  fn rev(xs : List(Int)) : List(Int) do
    match xs do
      Nil -> Nil
      Cons(h, t) -> cat(rev(t), Cons(h, Nil))
    end
  end

  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end

  @[lemma]
  fn cat_assoc(xs : List(Int), ys : List(Int), zs : List(Int)) : {Unit | cat(cat(xs, ys), zs) == cat(xs, cat(ys, zs))} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_assoc(t, ys, zs)
    end
  end

  @[lemma]
  fn rev_cat(xs : List(Int), ys : List(Int)) : {Unit | rev(cat(xs, ys)) == cat(rev(ys), rev(xs))} do
    match xs do
      Nil ->
        cat_nil(rev(ys))
      Cons(h, t) ->
        rev_cat(t, ys)
        cat_assoc(rev(ys), rev(t), Cons(h, Nil))
    end
  end

  @[lemma]
  fn rev_rev(xs : List(Int)) : {Unit | rev(rev(xs)) == xs} do
    match xs do
      Nil -> ()
      Cons(h, t) ->
        rev_rev(t)
        rev_cat(rev(t), Cons(h, Nil))
        assert rev(Nil) == Nil
        assert cat(Nil, Cons(h, Nil)) == Cons(h, Nil)
        assert rev(Cons(h, Nil)) == Cons(h, Nil)
        assert cat(Nil, t) == t
        assert cat(Cons(h, Nil), t) == Cons(h, t)
    end
  end

  fn main() : Int do 0 end
end
```

Each `assert` is one unfolding, and each uses the ones before it. Without them, at fuel 1,
`rev_rev` is `lemma_unproved`. Remove the two `@[reflect(fuel: 1)]` lines and the checker
takes these steps itself, so the asserts become optional: keep them if they make the proof
easier to read.

## Decided steps and fuel

The checker unfolds every call in a query once. When an unfolding produces another call, the
checker unfolds that one too, but only if it can already tell which arm runs, from the facts
it has: a known constructor, an earlier step's value, or plain arithmetic. That is a
**decided step**. A step it can't decide is left alone, so the checker never guesses.

How many rounds of decided steps it takes is the function's **fuel**. The default is 2.
`@[reflect(fuel: N)]` sets it for one function, from 1 to 8:

```march
mod Main do
  @[reflect(fuel: 5)]
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  fn need_eq(a : List(Int), _b : {List(Int) | _ == a}) : Int do 0 end

  fn four() : Int do
    need_eq(Cons(1, Cons(2, Cons(3, Cons(4, Nil)))), cat(Cons(1, Cons(2, Cons(3, Cons(4, Nil)))), Nil))
  end

  fn main() : Int do 0 end
end
```

At the default fuel this check is skipped with the reason `reflect-fuel`: walking a
four-element list takes more steps than that. At fuel 5 it is proved. Fuel never helps with
an unknown list, though: `cat(xs, Nil)` has no decided steps at all, and that is what lemmas
are for.

`@[reflect]` on its own does not switch reflection on (that is automatic). It asserts that
the function **is** reflected, so a later edit that adds a `println` is an error,
[`invalid_reflect`]({{ site.baseurl }}/docs/errors/invalid_reflect/), instead of a quiet loss of
every proof that used the function. Fuel outside 1 to 8 is the same error. Use `@[opaque]`
to keep a function out of the logic.

## When a lemma does not prove

When the checker can't show the theorem at every place the body returns, the lemma is
**unproved**. Here is `cat_nil` with no proof at all, just `()`:

```march
mod Main do
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    ()
  end

  fn main() : Int do 0 end
end
```

```
the lemma `cat_nil` is not proved: its theorem `cat(xs, Nil) == xs` was shown on 0 of the 1 paths through its body, so calls to it give no facts [lemma_unproved]
```

[`lemma_unproved`]({{ site.baseurl }}/docs/errors/lemma_unproved/) is a warning (an error under
`cap verified`). An unproved lemma gives its callers **nothing**: its theorem is never
assumed on its word. The message counts the paths, so "1 of 2 paths" tells you one arm
already works.

To fix it, look at the arm that fails and ask what the checker is missing there:

- **A case split.** If the theorem depends on the shape of a value, `match` on it.
- **The induction hypothesis.** If the arm leaves the same question about a smaller value,
  call the lemma on that value.
- **Another fact.** If the arm needs a law about a helper, prove that law as its own lemma
  and call it.
- **A smaller step.** If a step is true but too big, state it as an `assert` just before it.
  The report (`march --check --refine-report-sites=all`) shows which asserts proved.
- **More fuel.** If the arm only needs more decided steps, raise the fuel of the function
  being unfolded.

## When a lemma is false

When the theorem is false, the checker says so and shows an input where it fails. It runs the
theorem on the solver's candidate and reports it only when the theorem really is false
there:

```march
mod Main do
  fn twice(n : Int) : Int do n + n end

  @[lemma]
  fn twice_grows(n : Int) : {Unit | twice(n) >= n} do
    ()
  end

  fn main() : Int do 0 end
end
```

```
the lemma `twice_grows` is false: its theorem `twice(n) >= n` does not hold at n = -1 [refinement_violated]
```

This is an error, `refinement_violated`, in any module. The fix is usually a hypothesis: the
theorem holds for `n >= 0`, which the next part shows how to say.

---

## A call gives the caller a fact

A lemma call on its own line (or `let _ = cat_nil(xs)`) adds the theorem, with the call's
arguments in place of the parameters, as a fact for the rest of that block. The call
`cat_nil(xs)` adds `cat(xs, Nil) == xs`; `cat_nil(ys)` would add `cat(ys, Nil) == ys`.

Put the call before the place that needs the fact, in the same block. The fact is used by
the calls that follow: their preconditions, and the refined arguments passed to them, as in
[Your first lemma](#your-first-lemma).

## Hypotheses: refined parameters

A lemma's parameters can carry refinements. Those are the theorem's **hypotheses**: the proof
may assume them, and every call has to prove them.

```march
mod Main do
  fn twice(n : Int) : Int do n + n end

  @[lemma]
  fn twice_grows(n : {Int | _ >= 0}) : {Unit | twice(n) >= n} do
    ()
  end

  fn need_at_least(n : Int, m : {Int | _ >= n}) : Int do m end

  fn ok(k : Int) : Int do
    if k >= 0 do
      twice_grows(k)
      need_at_least(k, twice(k))      -- proved
    else
      0
    end
  end

  fn not_ok(k : Int) : Int do
    twice_grows(k)                    -- k may be negative: no fact
    0
  end

  fn main() : Int do ok(3) + not_ok(3) end
end
```

In `ok`, the `if` establishes `k >= 0`, so the call proves its hypothesis and adds
`twice(k) >= k`. In `not_ok` it can't:

```
this call of the lemma `twice_grows` gives no facts: its precondition is not proved here, and a lemma is never run, so there is no check to fall back on [lemma_unproved_call]
```

An ordinary call with an unproved precondition might still be fine at run time. A lemma call
never runs, so the checker's only safe choice is to give nothing.
[`lemma_unproved_call`]({{ site.baseurl }}/docs/errors/lemma_unproved_call/) is a warning, and an
error under `cap verified`.

## A fact stays in its branch

A lemma's fact holds where the call is, and in what comes after it in the same block. It
does not leak into another branch:

```march
mod Main do
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end

  fn need_eq(a : List(Int), _b : {List(Int) | _ == a}) : Int do 0 end

  fn branch(xs : List(Int), flag : Bool) : Int do
    if flag do
      cat_nil(xs)
      need_eq(xs, cat(xs, Nil))       -- proved
    else
      need_eq(xs, cat(xs, Nil))       -- not proved: the fact is in the other branch
    end
  end

  fn main() : Int do 0 end
end
```

If both branches need it, call the lemma before the `if`.

## Arguments must be pure

A lemma call is removed before the program runs, and its arguments are removed with it. So
each argument must be something whose removal changes nothing:

- a variable or a literal;
- a constructor or a tuple of such terms, such as `Cons(x, Nil)`;
- a call of a reflected function (pure, total, terminating), such as `rev(ys)`;
- a builtin the logic knows, such as `n + 1`.

Anything else, such as a call that prints, is the error
[`lemma_argument_impure`]({{ site.baseurl }}/docs/errors/lemma_argument_impure/): erasing it
would erase what it does. Bind the value to a name first, so the effect stays and only the
lemma call goes:

```march
mod Main do
  needs IO.Console

  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end

  fn noisy_list() : List(Int) do
    println("building")
    Cons(1, Nil)
  end

  fn main(_cap : Cap(IO.Console)) : Int do
    let xs = noisy_list()             -- not cat_nil(noisy_list())
    cat_nil(xs)
    0
  end
end
```

## `cap verified`: proofs required

By default an unproved lemma, and a lemma call whose hypothesis isn't proved, are warnings.
In a module that declares `cap verified`, both are errors:

```march
mod Main do
  cap verified

  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end

  fn main() : Int do 0 end
end
```

This module builds. Replace the body of `cat_nil` with `()` and the build fails with
`lemma_unproved`. What `cap verified` promises in full, and what it relies on, is on
[Claim: Refinement Types]({{ site.baseurl }}/docs/claim-refinements/).

## Lemmas from the standard library

The standard library proves lemmas about `List`: `List.append_nil`, `List.append_assoc`,
`List.len_append`, `List.reverse_reverse`, `List.reverse_append`, `List.len_reverse`,
`List.len_take`, `List.len_drop` and `List.take_drop`. You call them like your own lemmas, so
you don't need to re-prove `reverse(reverse(xs)) == xs` in every project. The manifest
`stdlib/lemmas.verified` lists the ones that are proved; a listed lemma is admitted without
re-proving it on every build.

## Which lemma to call: `--refine-infer`

When a call is not verified and the hint says the proof may need more unfolding of a function,
`march --check --refine-infer` (and `forge refine --infer`) looks for a lemma call that closes
it. A candidate is a lemma, yours or the standard library's, whose theorem mentions a call
appearing in the arguments, or in a `let` they read. Each one is checked by putting the call in
your program and checking it again. It is proposed only if the call proves the obligation, its
own preconditions prove, and nothing that was proved before stops proving. At most 8 candidates
are checked for each call.

```march
fn need_same(a : List(Int), b : {List(Int) | b == a}) : Int do 0 end

fn use_it(xs : List(Int)) : Int do
  need_same(xs, List.reverse(List.reverse(xs)))
end
```

```
$ march --check --refine-infer use.march
inferred lemma calls: 1 proposed, 0 not inferred
  use_it (use.march:4)  List.reverse_reverse(xs)  [closes the precondition `b == a` on `need_same`, 1 of 4 candidates checked]
```

`--refine-infer-apply` writes the call on its own line above the statement, then checks the file
again. A call it can't write that way (the statement shares its line with a match arrow, say)
is listed with "apply by hand".

When no lemma closes it, the tool prints the lemma that would. Its theorem is what the call
needs, with every `let` replaced by its right-hand side, over the function's own parameters.
Here `use_it` calls a `rev` of your own, which no lemma is about:

```
  use_it (use.march:4): no lemma call inferred for the precondition `b == a` on `need_same` (0 of 0 candidates checked)
    a lemma stating this would close it (checked; not applied, prove it first), called as `use_it_lemma(xs)` before line 4:
      @[lemma]
      fn use_it_lemma(xs : List(Int)) : {Unit | rev(rev(xs)) == xs} do
        ()
      end
```

"Checked" here means the obligation proves when the theorem is assumed at that point. The
skeleton is never written for you: its body is `()`, which proves nothing. Write the proof
(see [Induction: a recursive call](#induction-a-recursive-call)), then call it.

Two limits: the tool proposes calls only for a call's precondition, not for a function's own
return contract (see the last section), and only one call per obligation.

---

## Tested by `forge test`

A lemma you haven't proved yet may still be false. `forge test` finds out: for every project
source file with a `@[lemma]`, after the tests pass, it evaluates each lemma's theorem on
generated inputs. `march --check --lemma-test FILE` does the same for one file. The inputs
are boundary `Int`s (`0`, `1`, `-1`, the largest and smallest `Int` and their neighbours),
then 100 random draws from a fixed seed, 20261031, so a run is repeatable. An input outside
a refined parameter is skipped.

For this file:

```march
mod Laws do
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  fn len_of(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + len_of(t)
    end
  end

  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end

  @[lemma]
  fn len_cat(xs : List(Int), ys : List(Int)) : {Unit | len_of(cat(xs, ys)) == len_of(xs) + len_of(ys)} do
    ()
  end

  @[lemma]
  fn cat_comm(xs : List(Int), ys : List(Int)) : {Unit | cat(xs, ys) == cat(ys, xs)} do
    ()
  end
end
```

the report is one line per lemma:

```
lemma-test	laws.march	cat_comm	COUNTEREXAMPLE	the theorem is false at xs = Cons(-12, Nil), ys = Cons(-11, Cons(4, Nil))
lemma-test	laws.march	cat_nil	holds	49 inputs, interpreter; 12 compiled
lemma-test	laws.march	len_cat	tested	tested, not proved: 73 inputs
lemma-test: 3 lemmas (seed 20261031, 100 draws + boundary Ints): 1 admitted, 2 unproved
lemma-test: RED (1 lemma false on a concrete input)
```

- An **unproved** lemma is a property test. `len_cat` is true but has no proof yet, so it is
  `tested, not proved`. `cat_comm` is false, and the run fails with the input that shows it.
- An **admitted** lemma (`cat_nil`) is checked too; see the next section.
- An `Int` overflow is reported as `overflow?`, not as a counterexample, because the proofs
  treat `Int` as unbounded ([below](#what-lemmas-dont-do-yet)).
- A lemma whose parameter type has no input generator (a `String`, a `Float`, a record) is
  `not-tested`.

The tests are separate programs. Your build still removes every lemma.

## Catching a miscompile

A proved lemma is true, so if it is false when the program actually runs, the bug is in
March. `forge test` checks for that: it evaluates each admitted lemma's theorem in the
interpreter, and in a small program compiled with the native compiler, on the same inputs.
A false result is `FALSE` (interpreter) or `COMPILED-FALSE` (compiled), and the run fails.
Either one means the compiler or runtime disagrees with the logic, which is a bug to report.
That is the `interpreter; 12 compiled` in `cat_nil`'s line above.

## Laws in `forge doc`

On a `forge doc` page, each function lists the lemmas whose theorem calls it, under the
heading **Laws**, with the theorem as written. `cat`'s entry above would show
`cat(xs, Nil) == xs` and the other two. The list does not yet say which laws are proved and
which are only tested.

## Finding laws: `forge search --law`

`forge search --law TEXT` finds lemmas whose theorem contains `TEXT` (case and spaces
ignored) or calls a function named `TEXT`:

```
forge search --law cat          # every law that mentions cat
forge search --law "== xs"      # laws whose theorem contains this text
```

Each result prints the theorem and the functions it is about
(`law: cat(xs, Nil) == xs  (about: cat)`); `--json` carries it as `law`. A plain
`forge search NAME` also lists the lemmas about `NAME`, after the function itself.

## Rewrites in the editor

When a proved lemma's theorem is an equation, `lhs == rhs`, the editor offers to rewrite an
expression of the shape `lhs` into `rhs`, and names the lemma that justifies it. With
`cat_nil` proved, the cursor on `cat(Cons(1, zs), Nil)` offers
**Rewrite to `Cons(1, zs)`**.

Rewrites are offered only for lemmas the last check proved, and only left to right. They
come from the open file's lemmas; lemmas from other files and dependencies are not used yet.
They need the language server's refinement checking, which is on with `MARCH_LSP_REFINE=1`.

## Interface laws

**Not on `main` yet.** Laws declared on an interface (say, `combine` is associative for every
`Monoid`), which each `impl` must prove, or at least pass as tests, are being built. This
section will describe them when they land.

## Which functions have laws: `--law-coverage`

`march --check --law-coverage FILE` lists the file's **pure** functions (the ones the checker
reflects: they terminate, have no effects and cannot fail) by whether a law covers them. A law
**covers** a function when its theorem calls it; a call inside the proof does not count. Only
a proved lemma covers anything: one that is not proved is listed apart.

```
law coverage: M: 1 of 3 pure functions have a law (1 more only by unproved laws)
  uncovered (public)  zip  m.march:30
  unproved only  rev  m.march:8  (rev_rev)
  covered  cat  m.march:2  (cat_nil, cat_assoc)
  higher-order (no laws possible yet)  map2  m.march:41
```

A function that takes a function (`map2`) is listed apart and left out of the count: a lemma
cannot yet take a function as a parameter. An `impl` method is listed under its impl when its
interface declares laws, with whether they are proved for it
(`impl Monoid for Int: combine  covered  m.march:8  (combine_assoc (via Monoid))`, or
`unproved only`). The report lists the file's own functions; `--law-coverage-all` lists every
user file the check loaded. `--law-coverage-json` prints one JSON object per function instead.

**Covered is not the same as pinned down.** `--law-strength` makes small edits to each covered
function's body, one at a time (return a parameter unchanged, swap two arguments, change a
literal or a comparison, swap two match arms' results, drop the recursive call), and runs its
laws on generated inputs with the edit in place. An edit every law still accepts is
behaviour the laws leave open:

```
  covered  rev  m.march:8  (len_rev)
    strength: 3 of 3 edits survive
    survives: return `xs` unchanged  m.march:8
    survives: drop the recursive call  m.march:11
```

`len_rev` says `rev` keeps the length, which returning `xs` unchanged also does. A law like
`rev(cat(xs, ys)) == cat(rev(ys), rev(xs))` rules that edit out. Edits that do not change
what the function returns (swapping the operands of `+`) are dropped, not reported; when every
edit is, the line says `strength: no edit changed its behaviour`. An edit that makes the function
loop or fail where it returned before does not survive: a law that holds on fewer inputs under
the edit decides nothing. A function
whose parameters have no input generator says `strength: not run (no input generator)`, and
each function gets 5 seconds (`MARCH_LAW_STRENGTH_MS`), after which it says
`strength: partial (budget)`.

`forge audit --laws` prints the same report for every module of a package, checked together, so
a law in `b.march` covers a function in `a.march`; `--strength` adds the edits. It needs no `forge.caps.lock` and exits 0: it is a to-do list, not a gate.

## Lemmas as a spec for code someone else writes

A lemma is a precise statement of what code must do, and the build re-checks it every time.
That makes lemmas a good way to hand work to someone else, a coding agent included: write the
laws first, in a `cap verified` module, and let them change the code.

```march
mod ListLaws do
  cap verified

  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end

  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_nil(t)
    end
  end

  @[lemma]
  fn cat_assoc(xs : List(Int), ys : List(Int), zs : List(Int)) : {Unit | cat(cat(xs, ys), zs) == cat(xs, cat(ys, zs))} do
    match xs do
      Nil -> ()
      Cons(_, t) -> cat_assoc(t, ys, zs)
    end
  end
end
```

A change to `cat` that breaks either law, or breaks its proof, now stops the build, and
`forge test` prints an input that shows a false law. The laws say what must still hold; the
build checks it, so a reviewer doesn't have to.

---

## What lemmas don't do (yet)

- **`Int` overflow is not modelled.** The logic's `Int` is a mathematical integer, with no
  largest value. A lemma such as `{Unit | inc(n) > n}` proves, although at the largest `Int`
  the program's `n + 1` wraps around. `forge test` flags such a lemma `overflow?`. Checking
  overflow in proofs is planned for a later phase.
- **No function values.** A theorem can't take a function as a parameter, so laws about
  higher-order functions (`map` composition, `filter` run twice) can't be stated yet. The
  functions a theorem calls must be reflected, and a reflected function takes no function
  parameter.
- **No quantifiers in a theorem.** A theorem is about the lemma's parameters, for all of
  them at once. It can't say "there exists" or nest a "for all" inside, and a caller gets
  the theorem only for the arguments of a call. To use a law at several values, call the
  lemma once for each.
- **Facts reach later calls, not the function's own return contract.** A lemma call gives a
  fact to the calls after it. A function whose own result type is refined
  (`fn flush(xs : List(Int)) : {List(Int) | _ == xs}`) does not yet use facts from earlier
  lines of its body, from a lemma call or otherwise. State the need at the call that has it,
  as `need_eq` does on this page.
- **`String`, `Bytes` and `Float` theorems are limited.** The logic treats `String` and
  `Bytes` contents as opaque, so a round-trip law such as `decode(encode(s)) == s` can't be
  proved yet. `forge test` can't generate `String` or `Float` inputs for a lemma either.
- **A hand-written `==` is not used.** `==` in a theorem is structural equality. A type
  with its own `Eq` (as `List` has) gets a `predicate_eq_structural` warning; for laws over
  a custom equality, write the equality as a reflected function.

## See also

- [Refinement Types]({{ site.baseurl }}/docs/refinement-types/): the checker lemmas feed, and
  its [reference summary of lemmas]({{ site.baseurl }}/docs/refinement-types/#lemmas-proving-what-one-unfolding-cannot)
- [Claim: Refinement Types]({{ site.baseurl }}/docs/claim-refinements/): what `cap verified`
  promises, and the trusted base it rests on
- [Pattern Matching]({{ site.baseurl }}/docs/pattern-matching/): `match`, which splits a proof
  into cases
- Error pages: [`invalid_lemma`]({{ site.baseurl }}/docs/errors/invalid_lemma/),
  [`lemma_unproved`]({{ site.baseurl }}/docs/errors/lemma_unproved/),
  [`lemma_unproved_call`]({{ site.baseurl }}/docs/errors/lemma_unproved_call/),
  [`lemma_argument_impure`]({{ site.baseurl }}/docs/errors/lemma_argument_impure/),
  [`invalid_reflect`]({{ site.baseurl }}/docs/errors/invalid_reflect/)
