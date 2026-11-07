`[P2]` Bounded quantifiers in predicates: `forall i in 0..len(xs)`, `forall x in elts(s)`.

Medium step 5 of `2026-11-06-verification-ladder-roadmap`; the biggest single step on it.

## What it unlocks

Properties that need "every pair" or "some element": sortedness
(`forall i in 0..len(xs) - 1, xs[i] <= xs[i + 1]`), membership (`exists x in elts(xs), x == k`),
"all keys below k", "no duplicates". Today element facts come only through measures and
element/abstract refinements, which cannot relate two positions or say "some".

## Design sketch

- Syntax inside predicates: `forall i in lo..hi, P`, `forall x in elts(e), P`,
  `forall k in keys(m), P`, and `exists` likewise. Only bounded forms at first.
- Encoding: SMT quantifiers with a trigger chosen by the compiler from the bound's measure
  (`$nth(xs, i)` for an index range, `member(x, s)` for a set), never left to z3's heuristics.
  This avoids Dafny's main trap (bad triggers: brittle, timing-dependent proofs).
- Needs an indexing measure (`nth(xs, i)` in predicates, reflecting `List.nth_opt` or a
  dedicated measure) and its axioms.
- `exists` in a hypothesis is skolemised; in a goal it needs a witness (the checker tries the
  bound's terms in scope, else reports "give a witness" with an `assert P(k)` fix).

## Done when

- `List.sort`'s result type can say sorted, and `insert` into a sorted list is proved to keep
  it sorted (a lemma by structural induction).
- A predicate using an unbounded quantifier is a clear error pointing at the bounded forms
  (unbounded ones are `2026-11-06-unbounded-quantified-lemmas`).
- Solve-time budget: the refine oracle's corpus time does not regress (quantifier-free VCs are
  unchanged byte for byte: `scripts/ir-oracle.sh`-style hash check over emitted SMT).
