`[P3]` Refinement-indexed type aliases: `type Vec(a, n) = {List(a) | len(_) == n}`. **Done 2026-11-08.**

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

## What landed (2026-11-08)

- **First step's answer:** no alias existed in source at all. `TDAlias` was in the AST and the
  typechecker (transparent aliases), but only `@[endpoints]` generated one; `type Pos = {Int |
  _ > 0}` was a syntax error (`type X = {` reads as a record).
- **Syntax:** a `type`/`ptype` whose right-hand side is a refinement type is an alias, with or
  without a binder (`{v : Int | v > 0}`; told apart from a record on `|`). A parameter `n : Int`
  is a value parameter; on any other type declaration it is a parse error. `TDAlias` now carries
  the value parameters and their sorts; the declaration's parameter list holds every parameter in
  order. Formatter and tree-sitter grammar (value parameters, type-level `+`/`*`) updated.
- **Expansion** (`lib/desugar/desugar.ml`, "Refinement aliases", in `desugar_ty`): each use is
  replaced by its refinement, type arguments into the base type, value arguments (a number, a
  name, `+`/`*` of those) into the predicate (lambda- and quantifier-binder aware); a named binder
  becomes `_`. Aliases nest (`Matrix(r, c)` over `Vec(Int, c)`), a refinement of an alias is the
  conjunction, cycles are `recursive_type_alias`. Actor message parameters, state fields and init
  parameters now go through `desugar_ty` too (they never did, so no refinement there was
  normalised either).
- **Errors name the alias:** every conjunct of an expansion carries the message `expected
  Vec(Int, n)` (the use as written) through `Refine_msg`, on a span of its own per expansion; an
  author's own conjunct message is kept. Kinding: `alias_kind_mismatch` (a value parameter used
  as a type; a type passed for a value; a value passed for a type); arity is `type_arity`,
  reported once.
- **Worked example:** `test/refine/aliases/vec.march`: `replicate` and `push` prove `Vec(Int, n)`
  and `Vec(Int, n + 1)` results, `dot(n, xs : Vec(Int, n), ys : Vec(Int, n))` is proved at its
  call, and `Matrix(2, 3)` checks every row's length; 11 obligations, all proved. A short vector
  or a ragged row is refused, naming the alias and the offending value.
- **Tests:** group `aliases` in `test_refinecheck` (19 cases); `test/errors/alias_kind_mismatch_1`;
  explain page `specs/lang/errors/alias_kind_mismatch.md`; reference section "Refinement aliases"
  in `specs/lang/refinement-types.md`.

The done-when asked for `dot` at a call with two `zip`-built lists. The example builds its
vectors with `replicate` and `push` instead (`dot` uses `List.zip_with` inside): `List.zip` and
`List.map` carry no length contracts, and a recursive length-carrying function cannot prove its
recursive call yet (a list-length fact from a `match` arm does not meet a length hypothesis on the
parameter). Both are filed in `specs/todos/2026-11-08-list-length-recursion-gap.md`.
