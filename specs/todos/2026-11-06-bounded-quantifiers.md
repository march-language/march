`[P2]` Bounded quantifiers in predicates.

Stage B, step 5 of `2026-11-06-verification-ladder-roadmap`.

## Implementation status

Approved design and implementation plan: `specs/plans/2026-11-07-bounded-quantifiers-design.md`
and `specs/plans/2026-11-07-bounded-quantifiers-implementation.md`.
Implementation is in progress; keep this item open until the acceptance gates pass.

The focused suite passes 32 controls, including lexical capture, Boolean map
keys, unsupported Float list domains, checked existential candidates, and
indexing definedness. `test/refine/quantifiers/insertion_sort.march` proves
integer insertion and insertion-sort contracts using lower-bound and pairwise
sortedness invariants. It introduces no trusted sorting axioms. This does not
verify the existing comparator-based `List.sort_by` or `Sort.sort`, nor add a
public `List.sort` API. Use logical `nth(xs, i)` rather than runtime indexing
syntax in predicates.

## Remaining acceptance gates

- Complete parser/formatter, strict-capability, solver-limit and soundness controls;
  review exact sorts and reflected contracts.
- Full suites, fresh review, and CI.
- Byte-identical emitted SMT for the existing quantifier-free corpus.
- Three paired cold and warm solver timings, median within 5% of baseline,
  with no new timeouts.
- Build and validate the updated documentation. Move this item to progress
  only when the implementation and validation are complete.

Bounded forms are `forall` / `exists` over `lo..hi`, `elts(e)`, or `keys(m)`.
Triggers are chosen from suitable binder-dependent applications when available;
quantified solving remains incomplete. Existential goals require checked
candidates satisfying both their domain and body. Unbounded quantification is
tracked separately in `2026-11-06-unbounded-quantified-lemmas`.

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
