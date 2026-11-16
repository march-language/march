`[P3]` Collection and quantifier spec features: multisets, explicit extensionality, `assert forall … by`, two-state lemmas.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 14.

## Why

- **Multisets.** A set-valued measure cannot say a sort returns a permutation, because it loses
  multiplicity. Dafny's `multiset(s)` is the standard tool for that.
- **Explicit extensionality.** Verus makes extensional equality an explicit `=~=` operator,
  because its collection axioms are deliberately incomplete and automatic extensionality is a
  common cause of instability.
- **Proving a quantified fact.** Dafny's `forall` statement and Verus's `assert forall … by`
  prove a universally quantified fact by proving it for an arbitrary element. This is the
  introduction rule `2026-11-06-unbounded-quantified-lemmas` needs.
- **Reusable two-state facts.** Dafny's two-state lemmas let a lemma relate two states. They are
  the natural companion to `2026-11-06-two-state-specs`.

## Wanted

A multiset measure vocabulary (`mset`, `count`, union) beside the set vocabulary, `=~=` for sets
and multisets, and `assert forall x in s, P(x) by do … end` with x fresh in the block.

## Done when

An insertion sort is proved to be a permutation (multiset equality) as well as sorted, and
`assert forall … by` proves a fact that bounded quantifiers alone cannot.
