# HCR deploy gate: contracts across versions (2026-11-04)

Phase A0 of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§3.3). Closes
`specs/todos/2026-11-04-hcr-refinement-strengthening-unchecked.md`, filed with that design in
the same day's PR.

## The hole

`.schemas.json` was written from TIR types, where refinements are already erased. A deploy
that only strengthened a state field's refinement (`count : {Int | _ >= 0}` to `_ >= 1`), a
handler parameter's (`n > 0` to `n > 5`), or an `@invariant` was not checked:
- the two sidecars were byte-identical, or differed only in `"invariant"`;
- `--check-migration` verified only actors with a `migrate_state`, and exited 0 with no output.

The new handlers assume the new refinements of incoming state and messages, so their proofs
rested on facts a live actor didn't meet. `per(total, state.count)` with
`b : {Int | _ != 0}` was proved in v2 from `count >= 1`, while a live v1 actor sat at
`count: 0`. This was reproduced statically on `b86c86a63`; no live reload server was run.

## What landed

- **Schema writer (`bin/main.ml`).** Each actor now records:
  - its field refinements, as predicates over the bare field names (`"refine":"(count >= 1)"`,
    the form `@invariant` uses);
  - its handler parameter refinements over positional names (`"refines":[null,"(p1 >= p0)"]`,
    so renaming a parameter is not a change);
  - `"contracts": 1`, which marks a schema from a compiler that records refinements.

  A predicate the writer can't print sets `"refine_unsupported"`, and an unsupported
  `@invariant` sets `"invariant_unsupported"` instead of being dropped.
- **`Schema_diff` (forge)** parses the new keys.
- **`--check-migration` (`bin/schema_migration.ml`)** checks one law per actor state and per
  refined handler, and prints one `migration:` line per law:
  - **`<Actor>.state`:** old invariant ∧ old field refinements ⇒ new ones.
    - With a `migrate_state`, the existing patched-function check runs, now with the field
      refinements added.
    - Without one and with the same fields, the identity migration is checked. It is stated
      over the fields as scalar parameters: a synthesised record literal is ambiguous to the
      checker, because the actor's own state sort has the same field set.
    - A shape change without a migration is left to the compat gate.
  - **`<Actor>.<Handler>`:** each old parameter refinement ⇒ the new one, when the message
    type is unchanged. When it changed and a `migrate_msg` exists, the law is "not checked":
    H2 isn't built yet.
  - **Verdicts:** proved / unchanged / refuted (a counterexample) / not proved / not checked.
    Only proved and unchanged pass. `--accept-unproved Actor.law,...` (or `Actor`) lets the
    last two through. A counterexample never passes.
- **The `migrate_state` check, fixed in passing.** The patched function returned a
  synthesised `State` with the same field set as the actor's own state sort. Its literal was
  ambiguous, so a correct migration was never proved and a wrong one was never refuted (both
  exited 0 on `main`). It now returns the actor's own sort. The documented example
  (`old = { count: 1 }`) now produces its counterexample.
- **`forge deploy hot`:**
  - runs the check whenever either version records any contract;
  - refuses, rather than skipping, when the compiler (`MARCH_BIN`) or the entry file is
    missing;
  - passes `--accept-unproved` through (repeatable or comma-separated) and warns that it did.

## Tests

- `test_refinecheck` group `hcr-variance` (12 cases):
  - refused: strengthened state, strengthened invariant, strengthened handler parameter,
    unrecordable refinement, pre-contracts baseline;
  - passed: weakened or equivalent state or parameter, unchanged state with no solver;
  - the override: accepted for the named law only;
  - `migrate_state`: proved when correct, refuted with a counterexample when wrong.
- RED controls, each run and reverted:
  - `verify` forced to `Proved`: cases 0, 1, 5, 7 and 8 fail;
  - the old `State` return type put back: case 11 fails (the correct migration is "not
    proved").
- `test/native/hcr_schema_contracts` pins what the writer emits, including `Span`'s
  `(p1 >= p0)` and both unsupported flags.
- `test/refine_audit/corpus.baseline` regenerated for the new fixture.

## Not done

- **Reply covariance** for `Actor.call` (design §3.3, item 1) isn't checked yet.
- **H2:** `migrate_msg` results against handler contracts.
- **Nested actors:** the state check names the actor's sort by its schema key. An actor in
  a user's nested module (`mod Main do mod Inner do actor Box`) is keyed `Box` and proves; that
  was checked by hand, not pinned. A key that didn't match its sort would make the law "not
  proved", which is the safe direction (a refusal).
- **The override isn't written to the server's deploy audit log** yet (design §3.3, item 2).
  Today forge prints a warning.
