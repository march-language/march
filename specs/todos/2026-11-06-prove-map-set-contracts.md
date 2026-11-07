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
