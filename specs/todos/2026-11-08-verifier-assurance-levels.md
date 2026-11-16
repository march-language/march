`[P3]` Report a per-module assurance level (SPARK-style), alongside the strict `cap verified` gate.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 10.

## Why

SPARK's stone/bronze/silver/gold/platinum levels let a team adopt verification one module and
one guarantee at a time. That is the longest-lived industrial adoption model surveyed. Bronze
(initialisation and data flow) is meant for nearly everything, and silver (no run-time errors)
is the usual target. March has one bar, `cap verified`, which is all or nothing.

## Wanted

- `march --guarantees` (`bin/guarantees.ml`) reports a level per module, for example:
  typechecked → no panics/division/index faults proved → contracts proved → full (no
  `@[assume]`, no unproved obligations). Each level comes with its remaining obligations and
  trusted assumptions.
- An optional `cap verified(level)` that gates on a level below full.

## Done when

The levels are documented, the stdlib's modules are reported, and a project can gate CI on a
level.
