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
