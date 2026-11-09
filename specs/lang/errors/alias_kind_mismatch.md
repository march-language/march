---
layout: docs
title: "alias_kind_mismatch"
permalink: /docs/errors/alias_kind_mismatch/
---

# `alias_kind_mismatch`: a value where a type belongs, or a type where a value belongs

A refinement alias can take type parameters and value parameters:

```
type Vec(a, n : Int) = {List(a) | len(_) == n}
```

`a` is a type and `n` is a value (it has a sort, `Int`). This error reports one used as the
other:
- a value parameter used as a type in the alias itself (`{List(n) | …}`): a value parameter
  appears only in the predicate, or as a value argument of another alias;
- a type passed for a value parameter at a use (`Vec(Int, String)`);
- a value passed for a type parameter at a use (`Vec(3, 3)`).

A value argument is a number, a name in scope, or `+` / `*` of those.

## A program that triggers it

```march
mod Main do
  type Vec(a, n : Int) = {List(a) | len(_) == n}

  fn first(xs : Vec(Int, Int)) : Int do List.length(xs) end
end
```

## The fix

Pass a value for `n`: a number, or a parameter declared before it.

```march
mod Main do
  type Vec(a, n : Int) = {List(a) | len(_) == n}

  fn first(n : Int, xs : Vec(Int, n)) : Int do List.length(xs) end
end
```

## Why the rule exists

An alias is replaced by its refinement at each use, with type arguments put where its type
parameters are and value arguments put into the predicate. A type in a predicate, or a number in
a type, has no meaning, so the mix-up is reported where it is written rather than as a confusing
error in the expansion.

See also: [refinement aliases](../refinement-types.md#refinement-aliases-naming-a-refinement-with-value-parameters), `type_arity`.
