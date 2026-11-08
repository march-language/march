`[P2]` Verification ladder: practical steps from Liquid-Haskell-class toward Dafny/Verus, F* and Lean.

From the 2026-11-06 comparison (March vs Liquid Haskell, Dafny/Verus, F*, Lean). March today:
quantifier-free refinements, measures, reflection (terminating, pure, total functions), abstract
refinements, structural-induction `@[lemma]`s, termination metrics, refinement inference,
executed counterexamples, warn-by-default with a strict `cap verified` gate. The aim is Dafny/Verus
parity for functional and actor code, the useful slice of F*, and Lean power through export,
without dependent type checking (full Π-types would break HM inference and March's error
quality; not planned).

One file per step. Grouped by effort, ordered within a group by practical payoff.

## Quick wins (small effort; each makes existing proofs easier to write or debug)

1. ~~`2026-11-06-proof-assert-by`~~ done (`specs/progress/2026-11-06-proof-hints.md`) — `assert P by do … end`: a scoped hint whose helper facts do
   not leak.
2. ~~`2026-11-06-proof-calc-blocks`~~ done (same) — `calc` chains with one obligation per step and per-step
   diagnostics.
3. `2026-11-06-refinement-indexed-type-aliases` — `type Vec(a, n) = {List(a) | len(_) == n}`:
   value-indexed types in refinement form (most of what length-indexed vectors buy).
4. ~~`2026-11-06-proof-reveal-and-local-fuel`~~ done (same) — `reveal f` for `@[opaque]` functions and a
   per-proof fuel override (per-function `@[reflect(fuel: N)]` exists already).

## Medium (a feature each; unlock new classes of property)

5. `2026-11-06-bounded-quantifiers` — `forall i in 0..len(xs)`, `forall x in elts(s)` with
   triggers derived from the measure: sortedness, "contains", "all keys below k". The biggest
   single step.
6. `2026-11-06-ghost-code` — ghost parameters, lets and functions, erased like lemmas: proof-only
   state (the abstraction of a tree, a counter's history).
7. `2026-11-06-two-state-specs` — `old(state)` in actor handler and migration contracts.
8. `2026-11-06-lean-export` — emit reflected definitions and unproved lemmas as Lean 4, prove
   the hard ones there, admit them by digest. Lean's power without becoming Lean.
9. `2026-11-06-checked-solver-proofs` — measure certificate coverage first, then
   independently check exact VCs under an explicit strict opt-in mode.

## Large (projects; each needs earlier steps)

10. `2026-11-06-unbounded-quantified-lemmas` — `forall`/`exists` in lemma conclusions with
    explicit triggers, and a `forall` statement to prove one (needs 5).
11. `2026-11-06-prove-map-set-contracts` — prove `Map`/`Set`'s `@[assume]` contracts against
    the AVL implementation (needs 5, 6; design `2026-11-04-stdlib-lemma-sweep-design` §4).
    Shrinks the trusted base the most.
12. `2026-11-06-capability-effect-specs` — pre/postconditions per capability operation over a
    pure model of the runtime (File, `Actor.send`), F*-style specs for effects; overlaps phase D
    of `2026-11-04-lemmas-hcr-actors-choreography`.
13. `2026-11-06-proof-scripts` — compile-time March functions that produce hint lemma calls: the
    part of tactics that is worth having (P4).

## Suggested order

1-2 and 4 first (cheap, immediately useful); then 5 with 6 (they unlock 11); 8 and 9 in
parallel whenever someone has the appetite (independent of the rest); 3 and 7 when a user needs
them; 10, 12, 13 after 5 has settled.

Move this file to `specs/progress/` when 1-9 have landed; the large items keep their own files.

## Research-informed delivery gates (2026-11-07)

Keep the existing feature scope and HM constraint. Research links and concrete proof obligations
live in each item; these are design refinements, not newly shipped capabilities.

- Use `Set.insert` as the first integration benchmark for 5/6/11. Separate representation
  invariants and comparator laws; track trusted dependencies and reject a broken rotation.
  Ghost state is needed only where an abstraction measure is insufficient.
- Bounded syntax is not a decidable-quantifier guarantee. Prefer proof-direction-specific
  introduction, explicit witnesses and ground instances; measure quantified fallback on actual
  collection proofs before committing to trigger policy.
- Steps 8/9 are independent feasibility workstreams, not assumed turnkey integrations. A digest
  identifies an artifact; a checked Lean theorem or independently checked SMT certificate supplies
  the evidence. Both still depend on the source-to-logic translation and declared assumptions.
- Step 12 starts with an exclusively owned file and explicit error/frame semantics. Actor effect
  models follow the runtime conformance work; capability permission alone is not ownership.
- Keep `2026-11-06-actor-inductive-invariants` and the P1 unchecked-invariant defect ahead of
  optional inference or protocol indexing. Session loop/asynchronous correspondence remains a
  prerequisite for stronger protocol claims.
- Evaluate additional automation in `2026-11-07-local-refinement-inference-experiment` (Fusion;
  separately CHC/ICE invariant synthesis), and resource-aware protocols in
  `2026-11-07-resource-indexed-protocol-experiment` (Rast). Both are P4 experiments with go/no-go
  criteria; neither blocks the ladder.

Across these steps, record proof coverage, manual annotations/hints, solver resource use,
checking cost and transitive trusted assumptions. Include broken implementations and exhausted
budgets alongside successful examples. Preserve the existing quantifier-free path and distinguish
`proved`, `not proved`, `assumed`, and runtime-conformance evidence throughout.
