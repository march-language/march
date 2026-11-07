---
layout: docs
title: "predicate_vocabulary_shadowed"
permalink: /docs/errors/predicate_vocabulary_shadowed/
---

# `predicate_vocabulary_shadowed`: a predicate means the built-in, not your function

Inside a refinement predicate, `len`, `elts`, `keys` and the constructor tests
`is_<Ctor>` always have their built-in meaning: the length of a list or string,
the set of a list's elements or of a map's keys, whether a value was built with
a constructor. That holds even where your program declares a function of the
same name, so a predicate that spells the name never calls your function.

This is a warning. No verdict changes; it tells you which meaning the checker
took. A function of the standard library may share one of these names on
purpose (`Map.keys`), so only your own functions are reported.

## A program that triggers it

```march
mod Shadow do
  needs IO
  fn len(_xs : List(Int)) : Int do 7 end

  fn need(_xs : {List(Int) | len(_) == 1}) : Int do 0 end

  fn main(cap : Cap(IO)) : Unit do
    println(int_to_string(len(Cons(1, Nil))))
    let _ = need(Cons(1, Nil))
    ()
  end
end
```

`need(Cons(1, Nil))` is proved, because the list has one element, while the
program's `len(Cons(1, Nil))` is `7`.

## How to fix it

- If the predicate means the built-in, rename your function (`fn count`) so
  the two are not confused.
- If the predicate means your function, rename it (`fn my_len`): a function
  whose name is not predicate vocabulary can be used in a predicate once it is
  reflected (it terminates, has no effects and cannot fail).
