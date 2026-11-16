# Refinement must-reject corpus (pre-1.0 plan, package G2)

Landed 2026-11-11 on `claude/refine-must-reject-corpus-982ec1`.

## Why

`scripts/refine-oracle.sh` swept `test/native` and `stdlib`, and no fixture there holds a
violated obligation. A change that made the checker prove everything left the oracle, the
obligation ratchet and `refine-agreement` green. The typechecker has had the counterpart
since the conformance corpus: `specs/lang/types/reject/` with `check_types.sh`.

## What

- `specs/lang/refine/reject/`: 20 programs, each with one obligation that must be reported
  violated. Map: `specs/lang/refine/INDEX.md`.
  - `k01`-`k10`, one per obligation kind: precondition, return refinement, division safety,
    Int overflow, element demand, lemma, two-state handler guarantee, actor message
    payload, callable domain at a pass site, actor invariant.
  - `s01`-`s07`, one per fixed false proof whose sound verdict is a violation (element
    demand read in the caller's namespace, an inner binder shadowing a refined parameter,
    two constructor-registry cases, an unchecked `let` annotation, `cap no_panic` skipping
    `impl` bodies, a parameter refinement surviving a rebinding).
  - `a01`-`a03`, wrongly accepted today, listed in `known-accepted.txt`.
- `specs/lang/refine/check_refine.sh`, called by CI's `conformance` job. A fixture names the
  ledger row it expects (`-- EXPECT-VIOLATED: <kind> <callee>`, read from
  `--refine-report-sites=all`) and a piece of the diagnostic. It passes only if `--check`
  exits 1, the row is `violated` and the text is printed; proved, skipped or no obligation
  fails. Each fixture runs from a fresh cwd under a private `HOME`, so no VC cache answers
  for the solver. Missing z3 is a `FATAL`, exit 2.
- `known-accepted.txt` may only shrink. A listed fixture that becomes violated fails the run
  until its line is removed, and the list has a ceiling in the script
  (`KNOWN_ACCEPTED_MAX=3`).
- `scripts/refine-oracle.sh` sweeps the directory too, so the manifest pins the text of a
  violation. A baseline recorded before this change is not comparable (new fixtures).
- `scripts/affected.sh`: `specs/lang/refine/*` selects the runner and the refine oracle;
  `lib/refine/*` and `lib/refinecheck/*` select the runner as well.

## Kinds left out, and why

The runner accepts "violated" only, so a kind whose failing verdict is a skip has no
fixture here:

- **Fold invariant**: a broken base or step is `accumulator-base-unproved` /
  `accumulator-step-unproved`, a skip by design. Pinned under `cap verified` by
  `specs/lang/types/reject/t381`, `t382`.
- **Termination metric**: `not-decreasing` is a skip with a `termination_unproved`
  diagnostic. Pinned by `test/errors/termination_unproved_*`.
- **Session protocol payload refinement**: the checker files no obligation at `Chan.send`
  (and nothing checks at run time). New todo
  `specs/todos/2026-11-11-session-payload-refinement-unchecked.md`; fixture `a03` in the
  known-accepted list. The actor-message form is checked (`k08`).

The same rule kept most fixed false proofs out of the `s` group: their fix made the site a
skip (rows z2-z5 of the relational element review, the fold impostors, `x / -1` at the
smallest Int, the overflowing constant fold, the `let` self-rebinding, the hidden-field and
permuted-field element cases). Six drafted fixtures were measured as skips and dropped.
Those stay pinned by `specs/lang/types/reject/` under `cap verified` and by their
`test_refinecheck` groups. Two constructor-registry probes (`c2`, `c5`) were dropped
because the typechecker now rejects them outright (`type_mismatch`, `reserved_type_name`).

## It goes red

Clean build: `17 violated, 3 known-accepted, 0 failed (20 fixtures)`, exit 0.

**Perturbation 1, the solver proves every goal** (`Refine.discharge` returns `Verified`
before asking z3). Exit 1:

```
  FAIL  [k01_precondition.march] not reported violated: wanted a violated precondition of `need_pos`, got: proved (exit 0)
  FAIL  [k02_return_refinement.march] not reported violated: wanted a violated postcondition of `bad`, got: proved (exit 0)
  PASS  [k03_division_safety.march] violated (division of `n`: "may be by zero")
  FAIL  [k04_int_overflow.march] not reported violated: wanted a violated overflow of `+`, got: proved (exit 0)
  FAIL  [k05_element_demand.march] not reported violated: wanted a violated precondition of `sum_pos`, got: proved (exit 0)
  FAIL  [k06_lemma.march] not reported violated: wanted a violated postcondition of `inc_small`, got: proved (exit 0)
  FAIL  [k07_handler_ensures.march] not reported violated: wanted a violated postcondition of `Account.Steal.ensures`, got: proved (exit 0)
  FAIL  [k08_message_payload.march] not reported violated: wanted a violated precondition of `Add`, got: proved (exit 0)
  FAIL  [k09_callable_domain.march] not reported violated: wanted a violated precondition of `dec`, got: proved (exit 0)
  FAIL  [k10_actor_invariant.march] not reported violated: wanted a violated postcondition of `Account.Take`, got: proved (exit 0)
  FAIL  [s01_element_demand_caller_namespace.march] not reported violated: wanted a violated precondition of `ys`, got: proved (exit 0)
  FAIL  [s02_return_tail_inner_binder.march] not reported violated: wanted a violated postcondition of `g2`, got: proved (exit 0)
  FAIL  [s03_ctor_user_option_beside_builtin.march] not reported violated: wanted a violated precondition of `need1`, got: proved (exit 0)
  FAIL  [s04_ctor_second_declaration_same_module.march] not reported violated: wanted a violated precondition of `need1`, got: proved (exit 0)
  FAIL  [s05_let_annotation_unchecked.march] not reported violated: wanted a violated precondition of `let ys`, got: proved (exit 0)
  PASS  [s06_division_in_impl_method.march] violated (division of `n`: "may be by zero")
  FAIL  [s07_caller_refinement_names_rebound.march] not reported violated: wanted a violated precondition of `at`, got: proved (exit 0)
  KNOWN  [a01_callback_param_element_demand.march] wrongly accepted, as known-accepted.txt records (g: no obligation filed)
  KNOWN  [a02_multi_param_callable_domain.march] wrongly accepted, as known-accepted.txt records (dec2: proved)
  KNOWN  [a03_session_payload.march] wrongly accepted, as known-accepted.txt records (Chan.send: no obligation filed)
=== refine must-reject: 2 violated, 3 known-accepted, 15 failed (20 fixtures) ===
```

The two that still pass are divisions by an unrefined variable, which `Division_safety`
decides without a solver query. Everything that depends on a proof went from `violated` to
`proved`, and `--check` exited 0 on each.

**Perturbation 2, the ledger records every verdict as proved** (`Obligation.record`
overwrites the verdict). Exit 1, 17 of 17 fail:

```
  FAIL  [k01_precondition.march] not reported violated: wanted a violated precondition of `need_pos`, got: proved (exit 1)
  FAIL  [k02_return_refinement.march] not reported violated: wanted a violated postcondition of `bad`, got: proved (exit 1)
  FAIL  [k03_division_safety.march] not reported violated: wanted a violated division of `n`, got: proved (exit 1)
  FAIL  [k04_int_overflow.march] not reported violated: wanted a violated overflow of `+`, got: proved (exit 1)
  FAIL  [k05_element_demand.march] not reported violated: wanted a violated precondition of `sum_pos`, got: proved (exit 1)
  FAIL  [k06_lemma.march] not reported violated: wanted a violated postcondition of `inc_small`, got: proved (exit 0)
  FAIL  [k07_handler_ensures.march] not reported violated: wanted a violated postcondition of `Account.Steal.ensures`, got: proved (exit 1)
  FAIL  [k08_message_payload.march] not reported violated: wanted a violated precondition of `Add`, got: proved (exit 1)
  FAIL  [k09_callable_domain.march] not reported violated: wanted a violated precondition of `dec`, got: proved (exit 1)
  FAIL  [k10_actor_invariant.march] not reported violated: wanted a violated postcondition of `Account.Take`, got: proved (exit 1)
  FAIL  [s01_element_demand_caller_namespace.march] not reported violated: wanted a violated precondition of `ys`, got: proved (exit 1)
  FAIL  [s02_return_tail_inner_binder.march] not reported violated: wanted a violated postcondition of `g2`, got: proved (exit 1)
  FAIL  [s03_ctor_user_option_beside_builtin.march] not reported violated: wanted a violated precondition of `need1`, got: proved (exit 1)
  FAIL  [s04_ctor_second_declaration_same_module.march] not reported violated: wanted a violated precondition of `need1`, got: proved (exit 1)
  FAIL  [s05_let_annotation_unchecked.march] not reported violated: wanted a violated precondition of `let ys`, got: proved (exit 1)
  FAIL  [s06_division_in_impl_method.march] not reported violated: wanted a violated division of `n`, got: proved (exit 1)
  FAIL  [s07_caller_refinement_names_rebound.march] not reported violated: wanted a violated precondition of `at`, got: proved (exit 1)
  KNOWN  [a01_callback_param_element_demand.march] wrongly accepted, as known-accepted.txt records (g: no obligation filed)
  KNOWN  [a02_multi_param_callable_domain.march] wrongly accepted, as known-accepted.txt records (dec2: proved)
  KNOWN  [a03_session_payload.march] wrongly accepted, as known-accepted.txt records (Chan.send: no obligation filed)
=== refine must-reject: 0 violated, 3 known-accepted, 17 failed (20 fixtures) ===
```

Both perturbations were reverted and the corpus re-run green.

Also measured: with `k01` appended to `known-accepted.txt` the run fails twice over ("is
now reported violated: remove it from known-accepted.txt" and the ceiling message); with z3
off `PATH` it stops with the `FATAL` line and exit 2.

## Verification

- `specs/lang/refine/check_refine.sh`: green, as above.
- `scripts/test-affected.sh`: 57 cases pass (4 new).
- `scripts/check-docs.sh`: passes.
- `scripts/oracle-base.sh refine` against the merge-base `cd4b47e96`: 586 fixtures / 9,268
  lines at the base, 606 / 9,762 here. The diff is 494 added lines, every one tagged
  `reject_<fixture>`, and 0 removed: the 20 new fixtures and nothing else. (The oracle
  reports this as CHANGED, which is what a branch that adds fixtures looks like.)
