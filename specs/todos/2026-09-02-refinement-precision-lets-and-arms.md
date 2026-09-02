`[P2]` Refinement precision: `let` equalities and nested-pattern facts (filed 2026-09-02)

Two facts the checker never derives, left out of scope by the 2026-09-01
diagnosis split: a `let` with a literal or arithmetic right-hand side records
nothing, and a binder inside a constructor pattern (`t` in `Cons(_, t)`)
receives no fact even when a previous arm excludes the only other shape.
`stdlib/list.march:128` (`last`'s recursive call) is the flagship case.

Design: `specs/2026-09-02-refinement-precision-lets-and-arms-design.md`.
Corpus payoff is small and stated in the design; do not oversell it.
