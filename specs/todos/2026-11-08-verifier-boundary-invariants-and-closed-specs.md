`[P2]` Boundary type invariants, `closed` spec visibility and opt-in lemma groups.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 8.

## Why

- **Boundary invariants.** SPARK's `Type_Invariant` and Verus's `type_invariant` hold only
  outside the owning module. They are assumed on entry to public functions and checked on
  return and at constructors, and helpers inside the module may break them for a while. March's
  refinement aliases are always-true predicates, so they cannot say "well-formed except inside
  my own helpers". HAMT well-formedness (`2026-11-06-prove-map-set-contracts`, stage C) needs
  exactly that.
- **`closed` visibility.** Every mature tool separates "this spec function exists" from "its
  body is visible": Dafny `provides`/`reveals`, Verus `pub open`/`pub closed`, F* `.fsti`.
  Verus states that opaque is for performance and closed is for modularity. March has only
  opaque.
- **Lemma groups.** Verus's broadcast groups make ambient lemmas opt-in, because every extra
  fact slows the prover. This matters once `2026-11-06-unbounded-quantified-lemmas` lands.

## Wanted

- `@[invariant(p)]` on a `ptype`: p is assumed on parameters and checked on results of the
  module's public functions, and checked at public constructors. It is not assumed inside the
  module's private functions unless they ask for it, and it is never injected at call sites in
  other modules beyond what the public signatures state.
- A `closed` spec function exports its name and contracts, not its body. Clients see a
  function symbol with axioms only.
- Lemma groups declared and enabled by name, with no ambient default.

## Done when

The HAMT well-formedness invariant is stated as a boundary invariant on `Set`, with negative
controls (a public function that breaks it, a client that relies on a closed body).
