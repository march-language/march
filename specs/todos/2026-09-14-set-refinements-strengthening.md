`[P2]` **Strengthen set refinements past the landed baseline.** Set
refinements (PR #452) are well defined but only moderately strong: `elts`
does not follow list structure, so no list function body can be proved;
element sorts are guessed and then reconciled per VC, the root of the six
review defects and of opaque payloads; the stdlib `Set`/`Map` contracts are all `@[assume]`d; and
there is no cardinality. Design: `specs/2026-09-14-set-refinements-strengthening-design.md`.
Phase 1 (typed element sorts) landed 2026-09-14; see
`specs/progress/2026-09-14-set-refinements-typed-element-sorts.md`. Remaining: phases 2 to 4.
Four phases, one PR each: (1) derive every element sort from March types, with parametric datatypes and per-instance measures, and enforce the single-element-type rule;
(2) axiomatise `elts` and `len` over `M_List` and extend Tier 2 induction to
set predicates and local functions, proving `List.reverse`/`append`/`filter`/
`dedup` as written; (3) ground-instantiated `card`; (4) prove `SortedSet`'s
tree operations modulo one assumed comparator law. Depends on the six
set-refinement defect fixes (PR #453) reaching `main`.
