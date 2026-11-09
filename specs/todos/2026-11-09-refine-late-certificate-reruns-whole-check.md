# A late metric certificate re-runs the whole refinement check

Logged 2026-11-09 (found when stage B of the Map/Set proofs, #1211, doubled
the CI test jobs' time).

Reflection R2 (`check_module`, `lib/refinecheck/refine_check.ml`): the logic
encoder is built before the walk that certifies `@[decreases]` metrics, so a
function whose only blocker is that certificate is left out of the logic. When
the walk certifies one, `check_module` drops the first pass's diagnostics and
runs `check_module_pass` again, over the whole module, stdlib included, with
the certificate seeded.

The stdlib is checked with every program, so a single non-opaque stdlib
function with a late certificate makes every program's check run twice. Set's
`branch_nodes` did this until it was made `@[opaque]` (and the re-run now skips
opaque functions). The test `reflect-report` "one pass" pins that the stdlib
causes no re-run, using the `MARCH_REFLECT_DEBUG` trace `reflect-recheck:`.

Still open: a user program with one late certificate re-checks everything,
the whole stdlib included, rather than what the certificate can change (the
certified function's own unit and the units that call it, transitively). Either
decide metric certificates before the encoder is built, or re-run only the
affected SCCs and keep the first pass's results for the rest.

Done when: a late certificate in a user file costs a re-check of only the
units that reach it, and a test shows a stdlib obligation is not re-discharged.
