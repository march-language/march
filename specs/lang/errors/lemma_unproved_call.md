---
layout: docs
title: "lemma_unproved_call"
permalink: /docs/errors/lemma_unproved_call/
---

# `lemma_unproved_call`: a lemma call whose precondition is not proved

A lemma's parameters can carry refinements, such as `n : {Int | _ >= 0}`. Those are the theorem's
hypotheses: the lemma's proof assumes them, so each call has to prove them.

A lemma call is removed before the program runs, so nothing checks a hypothesis at run time. When
the checker cannot prove a hypothesis at a call, that call gives **no facts**: the lemma's theorem
is not assumed after it. This is a warning, and an error inside a `cap verified` module.

## A program that triggers it

```march
mod Main do
  fn dbl(n : Int) : Int do n + n end

  @[lemma]
  fn dbl_nonneg(n : {Int | _ >= 0}) : {Unit | dbl(n) >= 0} do
    ()
  end

  fn use_it(k : Int) : Int do
    dbl_nonneg(k)
    0
  end

  fn main() : Int do
    use_it(3)
  end
end
```

`k` can be negative, so `dbl_nonneg(k)` cannot be called on it.

## The fix

Call the lemma where the hypothesis holds, for example in the branch that tests it:

```march
mod Main do
  fn dbl(n : Int) : Int do n + n end

  @[lemma]
  fn dbl_nonneg(n : {Int | _ >= 0}) : {Unit | dbl(n) >= 0} do
    ()
  end

  fn use_it(k : Int) : Int do
    if k >= 0 do
      dbl_nonneg(k)
      0
    else
      0
    end
  end

  fn main() : Int do
    use_it(3)
  end
end
```

## Why the rule exists

A theorem proved under a hypothesis says nothing where the hypothesis is false. An ordinary call
with an unproved precondition would fail at run time, but a lemma call never runs. So the only
safe choice is to give the caller nothing.

See also: [the language reference](../refinement-types.md), [the lemmas guide](../lemmas.md), `lemma_unproved`, `refinement_violated`.
