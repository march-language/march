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
  (`$nth(xs, i)` for an index range, `member(x, s)` for a set), with the chosen pattern
  visible in diagnostics. Compiler-selected triggers constrain E-matching; they do not remove
  heuristic search, matching loops, or incompleteness. Do not promise predictable solving merely
  because the quantifier is bounded.
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

## Research-driven implementation gates (2026-11-07)

[Refinement Reflection, POPL 2018](https://nikivazou.github.io/static/popl18/refinement-reflection.pdf)
distinguishes predictable ground unfolding from heuristic quantified axioms. Apply that distinction
here; the following staging is a March design proposal, not a completeness result from the paper.

1. Lower `forall x in S, P` to `forall x. member(x, S) => P`; lower bounded `exists` to
   `exists x. member(x, S) && P`. Empty domains make the former true and the latter false.
   Specify ranges as half-open and oblige every indexing term's definedness, including in triggers.
2. For a universal goal, introduce an arbitrary fresh value and its bound, then prove its body.
   For an existential goal, prefer an explicit witness and check both membership and the body.
   Instantiate universal hypotheses at relevant ground terms before requesting quantified search.
   These are different proof directions; do not handle them all by adding ambient axioms.
3. Retain element/abstract refinements for pointwise collection properties. Add a quantified VC
   only for a property that needs it; do not globally quantify existing library contracts.
4. Validate trigger coverage of all bound variables (including multi-patterns), scope and sorts.
   Reject a predicate with no supported pattern with an actionable diagnostic. Pin resource
   limits and record solver version/options; exhausted search is `not proved`, never `violated`.
5. Treat quantifier statistics as diagnostic evidence: report instantiations when the solver
   supplies them, but call a failure a matching loop only when there is evidence of one.

Additional acceptance corpus: empty/singleton lists, nested binders and shadowing, a two-index
sortedness relation, an existential witness outside its domain, and a self-generating trigger.
Compare explicit instantiation with quantified fallback on sorted insertion and an AVL ordering
lemma. Record proofs, resource use, and diagnostics under unrelated declaration additions and
alpha-renaming; stability is an empirical target, not a guarantee of E-matching.
