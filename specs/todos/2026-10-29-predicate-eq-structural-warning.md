`[P2]` No warning when a predicate's structural `==` meets a hand-written `Eq`.

Fact F8 of `specs/2026-10-29-refinement-reflection-design.md` (§0.7 rows g1-g4, and §3.5; pinned by
`test/refine/reflect/g1_handwritten_eq.march`, `g3_handwritten_eq_direct.march`).

- In a refinement, `==` is z3 datatype equality whatever the type's `Eq` (a scalar `Float` `==` is the
  one exception: IEEE `fp.eq`). With `impl Eq(P)` comparing only the first field,
  `need(p : {P | _ == P(1, 2)})` on `P(1, 3)` is `refinement_violated`, while the program's
  `P(1, 3) == P(1, 2)` is true (g4 prints `eq`).
- The checker is consistent with what the predicate means, but nothing tells the user that their
  `Eq` is not what the predicate uses.
- Phase 1 of the reflection design adds the warning `predicate_eq_structural` at a predicate `==` at a
  type with a hand-written `Eq` in its structure ("`==` in a refinement means structural equality;
  `P` has a hand-written `Eq`, which this predicate does not use."), and states the meaning in
  `specs/lang/refinement-types.md`. No verdict changes.
