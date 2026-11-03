`[P2]` A user function named like predicate vocabulary is silently ignored by predicates.

Fact F21 of `specs/2026-10-29-refinement-reflection-design.md` (§0.12 row r3; pinned by
`test/refine/reflect/r3_shadow.march`).

- With `fn len(xs : List(Int)) : Int do 7 end`, the predicate `len(_) == 1` still means the builtin
  `$len`: `need(Cons(1, Nil))` is proved, while the program's `len(Cons(1, Nil))` is `7`.
- The same holds for every vocabulary name (`len`, `elts`, `keys`, the set operators, `is_<Ctor>`;
  `predicate_operators` / `set_vocabulary` / `known_predicate_fn` in
  `lib/refinecheck/refine_encode.ml`). No diagnostic says the user's function is not the one meant.
- `--reflect-report` (phase 0) already reports such a function `no R11:its name `len` is predicate
  vocabulary`, and a caller of it `no R6`.
- Phase 1 of the reflection design should add a warning at the declaration (or at a predicate that
  spells the name while a user function of that name is in scope).
