`[P3]` Ghost code: proof-only parameters, lets and functions, erased before codegen.

Medium step 6 of `2026-11-06-verification-ladder-roadmap`. Dafny/Verus `ghost`.

## Why

Some proofs need state the program never computes: the abstract contents of a tree (the set
its nodes hold), a counter's history, the sequence of messages an actor has seen. Today that state
can only be expressed through measures over existing values. Ghost code lets a proof carry it
explicitly and have it erased.

## Wanted

- `ghost` parameters (`fn insert(t : Tree, x : Int, ghost s : Set(Int))`), `ghost let`, and
  `ghost fn` (reflected, never compiled).
- Typing rule: ghost values flow only into ghost positions, refinements and lemma arguments;
  using one in program code is a compile error. Erasure is the same pass that erases lemmas.

## Done when

- The rule is enforced (reject tests), erasure verified by the ir-oracle (a program with ghost
  code emits the same IR as without it).
- One worked proof that needs it, e.g. an insert into a binary search tree proved against a ghost
  set (a stepping stone for `2026-11-06-prove-map-set-contracts`).
