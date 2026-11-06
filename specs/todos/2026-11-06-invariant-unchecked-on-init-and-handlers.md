`[P1]` `@invariant` is never checked on `init` or on handler results

Found 2026-11-06 while building the guarantee report (phase B of
`specs/2026-11-04-lemmas-hcr-actors-choreography-design.md`).

```march
@invariant(count <= limit)
actor Counter do
  state { count : Int, limit : Int }
  init { count: 50, limit: 10 }
  on Inc(n : Int) do { state with count: state.count + n } end
end
```

`march --check` accepts this with no diagnostic. The refinement checker only walks the
invariant expression for its own obligations (`Refine_check`, the `DActor` arm); nothing
obliges `init` to establish it or a handler to preserve it. It is used only across a hot
deploy: as the migration's goal (the live-data check, M10, and the deploy gate's old ⇒ new
implication) and, from the deployed baseline, as a hypothesis (`Hcr_baseline`). A user who
writes `@invariant` will read it as "always true of every live actor", which the build does
not establish. That is the design's "never silent" rule (§1.3) broken for the one guarantee
it calls tier 2.

`march --check --guarantees` labels it `not checked`, so it is no longer silent there, but
the check itself is missing.

Fix: treat `@invariant` as an inductive invariant of the actor.

- `init`'s record must satisfy it (an obligation at the record, like a field refinement).
- Each handler assumes it of `state` on entry and must re-establish it of the record it
  returns (every tail position).
- A violation is a `refinement_violated` error with the handler and a counterexample state;
  an undecided one a `refinement_unverified` hint, and an error under `cap verified`.

The vocabulary is the one the deploy gate already reads (`hcr_pred_to_string`): comparisons,
arithmetic, `&&`, `||`, `not`, field access, one-argument measures. Phase F's M2 (an
invariant elaborated to a reflected `<actor>_inv(state)`) widens it later.
