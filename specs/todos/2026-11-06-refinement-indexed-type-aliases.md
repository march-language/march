`[P3]` Refinement-indexed type aliases: `type Vec(a, n) = {List(a) | len(_) == n}`.

Quick win 3 of `2026-11-06-verification-ladder-roadmap`. The Liquid Haskell way to get most of
what length-indexed (dependent) types give, without dependent type checking.

## Wanted

```march
type Vec(a, n : Int) = {List(a) | len(_) == n}
type Matrix(r : Int, c : Int) = {List(Vec(Int, c)) | len(_) == r}

fn dot(n : Int, xs : Vec(Int, n), ys : Vec(Int, n)) : Int do …
```

A type alias may take value parameters (Int, or any predicate sort) and its body is a refinement
over them; at a use it expands, with the arguments substituted into the predicate. Nothing new in
the solver: it is the refinement the user would have written.

## First step

Check what exists: whether a plain refined alias (`type Pos = {Int | _ > 0}`) is accepted and
expanded everywhere a refinement is (signatures, element types, actor messages) today. If not,
that is part of this item.

## Done when

- Value parameters in alias declarations (syntax, kinding: a value parameter is not a type), and
  substitution at expansion; errors name the alias (`expected Vec(Int, 3)`), not the expansion.
- `dot` above proves its precondition at a call with two `zip`-built lists of equal length, and
  rejects mismatched lengths with a counterexample.
- Docs; tree-sitter grammar.
