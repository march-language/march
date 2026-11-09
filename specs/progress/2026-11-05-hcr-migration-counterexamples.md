`[P2]` HCR migration counterexamples, and H1/H2 on every build against the deployed baseline

Phase A of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§7): "HCR
counterexamples for H1 and H2 … Then H1 and H2 run on every build of an actor with
`migrate_*` … The baseline is taken from the last deployed build's `.schemas.json`."

## Before

The design probe P3 (`tally_migrate_state(old : { count : Int })` building a state whose
`count : {Int | _ >= 0}`, and `V1.Bump(n) -> Some(Tally.Bump(n))` into
`on Bump(n : {Int | _ > 0})`) gave two `refinement_unverified` hints:

- `the argument old.count could not be translated to SMT` (an unrefined anonymous-record
  field has no sort; G5 lifts only refined fields), and
- `no fact the checker derived constrains n` (a match binder).

Neither was a counterexample. The existing promotion
(`Witness.confirm_precond_reachable`) needs the model to assign the enclosing function's
parameters and an observed panic, and a migration returns its bad value instead of
panicking.

## Fix

- `Witness.confirm_migration` (§11): a skipped `Argument` obligation inside a function named
  `<x>_migrate_state` / `<x>_migrate_msg`, on the actor's own state record or one of its
  message constructors, is decided by execution. The function must have one clause, no
  guard and one annotated parameter. The check enumerates small values of the parameter's
  declared type (`migration_values`: Int battery, records, variants, Option, at most 64,
  smallest first). It keeps those that satisfy every refinement the type states at any depth
  (`satisfies`) and that the deployed handler would have accepted. It runs the migration on
  each and reads the result where the new build consumes it: the field of the returned state,
  or argument `idx` of the returned `Some(<Ctor>(…))`. A value failing the predicate is
  recorded `Violated` and reported as a `refinement_violated` error that names the input and
  the result, with constructors qualified by their datatype's module path. No SMT model is
  used, so an untranslatable subject (`old.count`) is decided too. If no input breaks the
  contract, the original skip is recorded unchanged.
- `Hcr_baseline` (new): the deployed build's contracts. The driver
  (`Schema_migration.load_baseline`, called before both `Refine_check.check_module` sites)
  reads `--hcr-baseline <path>`. Without the flag it reads the one
  `<root>/.march/*_hot.so.schemas.json.prev` under the nearest `forge.toml`, the file
  `forge deploy hot` keeps. `strengthen` (run in `check_module` before `Refine_anon.lift`)
  refines each unrefined field of a `migrate_state`'s anonymous-record parameter. The
  refinement is the deployed field refinement conjoined with every deployed `@invariant`
  conjunct that mentions only that field, so G5 makes it an SMT hypothesis and `satisfies`
  an admissibility check. `handler_refines` filters generated old messages by the deployed
  handler's per-parameter refinements (`p0`, …).

## Result

- P3 (no baseline): both obligations are errors:
  `tally_migrate_state({ count: -1 }) returns { count: -1, hist: [] }` and
  `tally_migrate_msg(V1.Bump(0)) returns Some(Tally.Bump(0))`.
- The corrected P3 (`old : { count : {Int | _ >= 0} }`, `if n > 0 do Some(Tally.Bump(n)) else None end`):
  both migrations prove.
- P3 against a baseline whose `count` was `count >= 0` (or whose `@invariant` was
  `count >= 0 && …`): `migrate_state` proves.
- P3 against a baseline whose `Bump` was `p0 > 0`: no message counterexample. The obligation
  stays an honest hint, because the binder gets no hypothesis.

Tests: `test_refinecheck` suite `hcr-migration` (8 cases). Each one was shown to go red
under a perturbation: the hook disabled turns cases 0, 1 and 7 red, `strengthen` disabled
turns 4 and 5 red, and the deployed-handler filter disabled turns 6 red.

## Residual

- A `migrate_state` parameter of a NAMED record type is not strengthened from the baseline.
- The deployed handler refinements are not SMT hypotheses for `migrate_msg`'s match binders;
  they only filter the inputs tried, so a migration that is correct only because of them
  stays a hint.
- `@invariant` conjuncts over two or more fields are not used.
- The search is bounded (small Ints, depth 3, 64 inputs). A contract broken only by larger
  inputs stays a hint, never a wrong error.
