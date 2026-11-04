---
layout: docs
title: "lemma_argument_impure"
permalink: /docs/errors/lemma_argument_impure/
---

# `lemma_argument_impure`: a lemma call whose argument does something

Every call of a `@[lemma]` is removed before the program runs, and its arguments are removed with
it. So each argument must be a term whose removal changes nothing:
- a variable or a literal;
- a constructor (`Cons(x, Nil)`) or a tuple of such terms;
- a call of a function the checker reflects (pure, total, terminating);
- a call of a builtin the logic knows, such as `+` or `<`.

Anything else, such as a call that prints, could fail, or isn't reflected, is an error. Erasing
it would silently erase what it does.

## A program that triggers it

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
    cat_nil(noisy_list())
    0
  end
end
```

## The fix

Bind the value to a name first, so the effect stays in the program and only the lemma call goes:

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
    let xs = noisy_list()
    cat_nil(xs)
    0
  end
end
```

## Why the rule exists

Lemmas are proofs, and proofs must not change what a program does. A rule that left lemma calls in
the program would cost time at run time. A rule that removed them along with their arguments'
effects would change behaviour. Requiring pure arguments avoids both.

See also: [the language reference](../refinement-types.md), [the lemmas guide](../lemmas.md), `invalid_lemma`.
