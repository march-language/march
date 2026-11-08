`[P2]` Prove `Map` and `Set`'s `@[assume]` contracts against their AVL implementation.

Large step 11 of `2026-11-06-verification-ladder-roadmap`. Design:
`specs/2026-11-04-stdlib-lemma-sweep-design.md` §4.

## Why

`Map` and `Set` state their API as trusted (`@[assume]`) contracts over the `keys`/`elts`
measures. Every proof about a map relies on them, so they are the largest single piece of the
trusted base after the solver. Proving them is the clearest demonstration that March can verify
real data-structure code, which is Dafny's home ground.

## Needs

- `2026-11-06-bounded-quantifiers` (the search-tree ordering invariant: every key in the left
  subtree is below the node's key), `2026-11-06-ghost-code` (the abstract set a subtree holds), and
  measures over the tree (`keys(node)`).
- The balance invariant (heights differ by at most one) and lemmas for each rotation.

## Shape

One contract at a time, starting with `member` and `insert` on `Set`, then `delete` (the hard
one: rotations after removal), then `Map`. Each proved contract drops its `@[assume]`; the claim
docs' trusted-base section shrinks accordingly.

## Done when

All of `Set`'s and `Map`'s `@[assume]` contracts are proved (or the ones left are listed in the
trusted-base section with the reason), the stdlib lemma manifest admits them, and
`bench/` shows no runtime change (the proofs are erased).

## Proof decomposition and benchmark (2026-11-07)

[Abstract Refinement Types, ESOP 2013](https://goto.ucsd.edu/~rjhala/papers/abstract_refinement_types.html)
shows how recursive data invariants and higher-order contracts can be factored. Use a small
set of reusable representation predicates rather than exposing the AVL implementation at callers.

- Separate ordering, balance, cached-height correctness and abstract contents. Define an
  abstraction measure; use ghost state only when a measure alone cannot express the proof.
  Quantify over the declared comparator: require the ordering laws actually used, including
  how comparator equality identifies keys. Never assume arbitrary callback comparators are lawful.
- Prove each rotation preserves contents and ordering and restores the required balance/height
  conditions. Then prove `member`, `insert`, and `delete` against those lemmas. Keep extensional
  API contracts independent of tree shape; test duplicate insertion and absent-key deletion.
- Avoid circular justification: implementation proofs must not use the API's own `@[assume]`
  postconditions. Report the transitive trusted dependencies of every newly proved contract.
- Use Set insertion as the first end-to-end gate for quantifiers, reflection, ghosts and lemma
  ergonomics. Record annotation size, manual hints, solver work and the remaining trust set.
  Require negative controls for a wrong rotation and wrong height update; unchanged runtime IR
  checks proof erasure. Do not wait for all Map operations before evaluating the design.
