# `[P3]` Container subtyping covers `List` and `Option` only

Filed 2026-09-13 when container subtyping landed
(`specs/progress/2026-09-13-container-subtyping.md`).

`Refine_scope.elem_refinement` is the single test of "does the checker
model this container", and it admits exactly `List(…)` and `Option(…)` with
a refinement one layer down. Still unenforced, and reported so by
`--refine-audit` (position `Type_arg`, nesting `Nested`):

- a refinement inside any other container's type argument — `Map(k, {Int |
  p})`, `Set({Int | p})`, `Result({Int | p}, e)`, a user ADT's argument;
- two layers of nesting: `List(List({Int | p}))` (the pinned audit fixture
  in `test/test_refinecheck.ml`'s `audit-flag` group uses this shape for
  exactly that reason);
- elements reached through a stdlib function rather than a `match`:
  `List.head(xs)` on `xs : List({Int | p})` returns an `Option(Int)` as far
  as the checker knows, so the element fact is lost there. Carrying it
  needs the stdlib signature to be polymorphic in the element refinement,
  which is the parametric half of container subtyping.

Each is an extension of the same three sites (`check_elements`'s literal
arms, `contenv`, the `EMatch` element facts); none needs a new mechanism.
