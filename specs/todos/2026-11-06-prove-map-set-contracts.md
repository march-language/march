`[P2]` Prove `Map` and `Set`'s `@[assume]` contracts against their HAMT implementation.

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

## What the code actually is, and what blocks it (2026-11-08)

`Map` and `Set` are NOT AVL trees: both are hash array mapped tries (`stdlib/map.march`
`HEntry`, `stdlib/set.march` `SEntry`: `Leaf(hash, x)`, `Branch(bitmap, List(children))`,
`Collision(hash, List(x))`), routed by `int_and`/`int_shr` hash slots and `int_popcount`
ranks. The AVL tree is `SortedSet`, whose tree operations are already proved against a set
measure (`sorted_set_elts`) with one trusted comparator law (`compare_by`). Set has 14
`@[assume]` contracts, Map 12.

**The contracts split in two.**

- *No invariant needed.* `insert`'s `elts(_) == union(elts(s), singleton(x))` holds for any
  trie: the bits only pick the route, `list_nth_safe` panics (a vacuous path) when an index is
  out of range, and `list_insert_at`/`list_replace_at` keep every other child. The same goes for
  `empty`, `singleton`, `to_list`, `fold`-built `from_list` and `union`.
- *Needs the hash-path invariant.* `contains` (the "found when present" half), `remove`, `size`
  (`card`, so no duplicates), `is_empty`, `intersection`, `difference`, `is_subset`, `eq`. The
  invariant `WF(node, level)`: a leaf's hash is its key's hash; a collision's keys share its
  hash and are distinct; a branch has `popcount(bitmap)` children and the child at
  `rank(bitmap, s)` holds exactly the keys whose slot at this level is `s`, recursively. It
  needs bit-level facts about `bitmap_set`/`bitmap_has`/`bitmap_rank`/`popcount` (rank shifts
  by one past an inserted slot, and so on), either as trusted primitive laws (small, and
  checkable by an exhaustive property test over 32-bit slots) or through a bit-vector encoding.

**Compiler blockers found by a probe (a user-space copy of `SEntry`).**

1. **A measure cannot recurse through a second type.** The contents of a trie need `ne` over
   `SEntry(a)` and `ces` over its `List(SEntry(a))` children, each calling the other; both are
   rejected `invalid_measure` ("not structurally recursive"). This is the cross-type mutual
   recursion item of `2026-10-27-termination-structural-certificate-gaps`, applied to measures.
   The alternative, an inline children datatype in the runtime representation, still crosses
   two types and changes a hot data structure.
2. **`elts` over a `List` is not callable inside a measure body** (`unbound_variable`), so a
   collision bucket's contents need a hand-written list measure or that builtin opened to
   measure bodies.
3. `eq` is a closure parameter (`cmp_eq(cmp, a, b)`). The `SortedSet` precedent is one
   `@[assume]` law on the comparator wrapper; `cmp_eq` would get `{Bool | _ == (a == b)}`.

**Stages.** (A) mutual measures across a datatype and its `List`; (B) prove the
invariant-free contracts (`insert` first, the end-to-end gate); (C) bit laws and `WF`, then
`contains`, `remove`, `size`; (D) Map, which is the same trie with values.
