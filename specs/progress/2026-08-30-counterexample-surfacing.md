`[P2]` Counterexample surfacing for refinement failures (filed 2026-08-30, landed 2026-08-30)

Z3 models for failed refinement obligations are now turned into concrete,
interpreter-validated failing inputs rendered in source terms — e.g.
`but clamp(0) returns -1.` instead of silence or "solver-undecided".

Design: `specs/2026-08-30-counterexample-surfacing-design.md`.
Plan: `specs/plans/2026-08-30-counterexample-surfacing-plan.md`.

Shipped: `lib/refinecheck/witness.ml` (decode model → execute via
fuel-limited, effect-vetoed `march_eval` → confirm the violation →
deterministic weight-ordered shrink), wired into four sites: return
contracts and the enumerative battery for unreflectable ones
(`refine_post.ml`), call-site precondition examples (`refine_call.ml`),
and `cap no_panic` division errors (`division_safety.ml`).  Two small
evaluator hooks carry it: `Eval_prim.builtin_guard` (checked in
`apply_inner`'s `VBuiltin` arm) and the pre-existing reduction budget
with a writable `remaining` as fuel.  Confirmed witnesses are errors by
default; every unconfirmable candidate leaves the old behavior exactly.

Deviations from the design doc (recorded there too):
- Effect denial is a builtin-NAME guard at the `apply_inner` chokepoint
  (cap-table names + runtime-family prefixes), not per-builtin stubs.
- Division confirmation checks the divisor evaluates to 0 under an
  admissible assignment rather than executing to the panic.
- The predicate evaluator does not apply user measure functions in v1
  (unknown applications are unconfirmable, never guessed).
- Under `cap verified`, a confirmed violation reports the strong
  Violated error INSTEAD of "cannot verify" — the planned appended
  "In fact…" sentence is unreachable and was dropped.
- Shrinking needed a strict structural-weight ordering (the probe pair
  1/-1 otherwise oscillates); negatives weigh one more than their
  magnitude so 1 canonically beats -1.

Behavior change: some-input return-contract violations with a confirmed
witness are errors (CHANGELOG [Unreleased]).  Seven pre-existing
fixtures that used genuinely violable bodies as stand-ins for
"unprovable" were updated (see the Task 3/8 commit messages).

refine-oracle: proven RED-capable on a verdict perturbation first, then
byte-IDENTICAL over all 298 fixtures after the change — the corpus is
correct code, and witness confirmation introduces zero new diagnostics
there (the no-false-positives goal, measured).  Full alcotest suite and
`scripts/run-tests.sh` green; trivial `--check` wall time within noise
of the pre-change compiler (1.17s vs 1.08s).
