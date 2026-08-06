# `Stats.covariance` / `correlation` / `linear_regression` — the relational equal-length precondition

Task 7 of the 2026-08-05 no-panic-proof-based-and-group-b plan. This is the
first contract in this plan whose predicate relates TWO parameters.

## Sub-task (b) was already resolved by Task 6 — recorded, not redone

The plan bundled a second sub-task: re-verify that `percentile`/`quantile`/
`quantiles` already carry a float-range precondition on their second parameter.
Task 6 (`e4b92051`, corrected by `1ddfa1a2`) verified this against source twice.
The established findings, restated here so this file is self-contained:

- `Stats.percentile` — `p : {Float | _ >= 0.0 && _ <= 100.0}` **present**.
- `Stats.quantile` — `q : {Float | _ >= 0.0 && _ <= 1.0}` **present**.
- `Stats.quantiles` — `qs : List(Float)`, **no refinement**. The plan's claim
  that all three carry a range precondition is wrong for this one. `qs` is a
  *batch* of quantile levels validated per-element by a runtime `panic` inside
  `List.map`; "every element of this list is in [0, 1]" is a per-element
  property over a list, not a scalar range precondition, and is a different
  shape from the other two. Deliberately left unrefined and out of scope.

Task 6 also added the `xs` length precondition to all six of its functions
(including these three) and corrected the documentation that had wrongly grouped
`quantiles` with the other two. No code was written for (b) in this task.

## The contracts (sub-task (a))

`stdlib/stats.march`, three signatures:

```march
fn covariance(xs : {List(Float) | len(_) >= 2},
              ys : {List(Float) | len(_) == len(xs)}) : Float

fn correlation(xs : {List(Float) | len(_) >= 2},
               ys : {List(Float) | len(_) == len(xs)}) : Float

fn linear_regression(xs : {List(Float) | len(_) >= 2},
                     ys : {List(Float) | len(_) == len(xs)}) : (Float, Float)
```

Each function opened with `if nx != ny do panic(...) else if nx < 2 do
panic(...)`; both of those panics are *structural* — properties of the lists'
lengths — so both are expressible and both are now declared.

### This reuses `List.nth`'s already-shipped mechanism

`ys`'s predicate refines one parameter by referencing a **sibling** parameter's
measure. That is not new engineering: `List.nth`'s own shipped contract,
`n : {Int | _ >= 0 && _ < len(xs)}` (`stdlib/list.march:141`), has referenced
sibling parameter `xs` from `n`'s refinement since it landed. The only novelty
here is `==` in place of `<`, and that the refined value is itself a `List`
(so `len(_)` and `len(xs)` appear in the same predicate) rather than an `Int`.
Feasibility was therefore not re-derived from scratch — but per the brief it
was still *measured*, because a prior task in this plan (Task 4, `4c827019`)
showed a contract can compile clean and discharge nothing in either direction.

## The relational predicate genuinely discharges — measured, not assumed

Caches cleared once beforehand (`rm -rf .march/cas/artifacts-v2 .march/cas/vc`).
Scratch fixtures live outside `stdlib/` because `bin/main.ml` filters
stdlib-span diagnostics, which would make an in-stdlib control silently vacuous.

Fully guarded (`/tmp/t7-nopanic/f_guarded.march`):

```march
mod FixG do
  cap no_panic
  fn f(xs : List(Float), ys : List(Float)) : Float do
    if List.length(xs) >= 2 && List.length(ys) == List.length(xs) do
      Stats.covariance(xs, ys)
    else 0.0 end
  end
end
```

```
refinement obligations (user code): 2 proved, 0 violated, 0 trusted, 0 skipped
  by kind: 2 precondition, 0 postcondition, 0 division
```
exit 0.

Two obligations proved is consistent with either precondition doing the work, so
the two were then **separated**, which is the decisive measurement:

- guard only `List.length(xs) >= 2` → `1 proved, 0 violated, 1 skipped`, and the
  hint names the survivor: ``precondition `len(_) == len(xs)` on
  `Stats.covariance` was NOT verified here.``
- guard only `List.length(ys) == List.length(xs)` → `1 proved, 0 violated,
  1 skipped`, hint: ``precondition `len(_) >= 2` on `Stats.covariance` was NOT
  verified here.``

`correlation` and `linear_regression` were confirmed the same way in one
fixture: `4 proved, 0 violated, 0 skipped`, exit 0.

### Why the relational predicate is attributably proved — the sound argument

The hint texts above are *suggestive* but they are **not** decisive on their
own, and an earlier draft of this note leaned on them as if they were.
`refine_check.ml:3483-3486` fires the unverified-precondition hint **at most
once per declaration list** (`unverified_hinted`). So in a run where BOTH
obligations were `Skipped`, only the first by parameter order would be hinted
anyway — "guard only the equality, observe `len(_) >= 2` named as the survivor"
is consistent with the relational obligation being silently skipped too. The
hint tells you which precondition was *named*, not that the other one was
proved.

The sound chain is the OCaml test pair, and it needs both halves:

- **`SCV2`** (guard `len >= 2` only) shows the relational obligation is
  *recorded* and comes back `Skipped` — the call errors, so a `Skipped`
  precondition obligation exists at that site. This rules out the Task 4 failure
  mode, where a contract is accepted by the machinery and produces no obligation
  at all in either direction.
- **`SCV1`** (guard both) passes, i.e. the call is accepted. Acceptance requires
  the weakest-wins fold over **all** recorded precondition obligations at that
  site to come back `Proved`. Since `SCV2` established that the relational
  obligation is one of the recorded ones, `SCV1`'s acceptance forces
  `len(_) == len(xs)` itself to be `Proved` — it cannot be carried by its
  sibling.

Together those two force the conclusion: `len(ys) == len(xs)` is genuinely
recorded, genuinely discharged when provable, and genuinely fails closed when
not. The `--refine-report` counts (`2 proved` fully guarded, `1 proved /
1 skipped` half-guarded) are consistent with this and are useful corroboration,
but the test pair is the argument.

## TDD cycle

**RED** (pre-change binary, caches cleared): the unguarded fixture

```march
mod FixU do
  cap no_panic
  fn f(xs : List(Float), ys : List(Float)) : Float do Stats.covariance(xs, ys) end
end
```

compiled clean — `--check` exit **0**, `0 proved, 0 violated, 0 skipped` in user
code, no diagnostic. Neither function was on any ban list nor carried any
contract, so `cap no_panic` said nothing about a call that panics on two
distinct conditions. That is the "a call that can genuinely panic compiles
clean" direction the plan's Global Constraints call as serious as a false
positive.

**GREEN** (same fixture, after the contracts + covered-set wiring): exit **1**,
`` `f` in `mod FixU` (declared `cap no_panic`) calls `Stats.covariance`, which
can panic. `` plus the unverified-precondition hint. Guarded fixture: exit 0.

Note on staging: `dune build --root .` was followed by
`dune build --root . @test/cas-runtime-dir` and a `diff -q stdlib/stats.march
_build/default/stdlib/stats.march` before trusting any `bin/main.exe` result —
a targeted `dune build bin/main.exe` does NOT restage `stdlib/*.march`, and
Task 6 lost significant time to the resulting false "compiler bug" signal. The
OCaml harness (`test/test_refinecheck.ml`'s `load_stdlib_march`) reads repo-root
source directly and is unaffected.

## Covered-set wiring — ONE edit

`lib/typecheck/typecheck.ml`'s `panic_surface_contracted` gained
`"Stats.covariance"; "Stats.correlation"; "Stats.linear_regression"`. That is
the only list touched: `Panic_surface_by_proof.covered` is a structural alias of
this binding rather than a second hand-maintained list, so disjointness from the
syntactic ban lists (`panic_surface_all_direct`, `panic_surface_stdlib`) holds
automatically. Verified none of the three names appears in either ban list
before or after.

## OCaml tests (`test/test_refinecheck.ml`) and the load-bearing mutation

Two preconditions on one call site is a trap for test design: the shared
`cap no_panic` **error** message is identical whichever of the two goes
undischarged, so a test that only asserts "this errors" would pass on either
and could not tell the relational contract from a no-op. The suite therefore
asserts on the unverified-precondition **hint** instead:

- `stats_diagnostics` was factored out of the existing
  `no_panic_errors_with_stats` (which now filters that same diagnostic list —
  no behavior change to Task 6's cases).
- `unverified_preconditions_stats` returns the hint texts, filtered to the
  FIXTURE's span exactly as the error path is. This filter is load-bearing: the
  harness prepends the real `list.march`/`stats.march`, whose own bodies raise
  their own hints (``precondition `_ >= 0 && _ < len(xs)` on `List.nth```,
  ``precondition `len(_) > 0` on `last```). Without the filter every assertion
  passed or failed for the wrong reason — observed directly during development.
- `only_unverified_is pred src` asserts the fixture left exactly `pred`
  undischarged.

Nine new cases in the `no-panic-by-proof` group:

- 2 ACCEPT — `covariance` fully guarded; `correlation` + `linear_regression`
  fully guarded (one fixture, two functions).
- 3 REJECT, **equal-length violation** — one per function: guarded on
  `len >= 2` only, asserting the surviving unverified precondition is
  `len(_) == len(xs)`.
- 3 REJECT, **short-list violation** — one per function: guarded on the equality
  only, asserting the survivor is `len(_) >= 2`.
- 1 REJECT — `covariance` fully unguarded still errors.

**Load-bearing mutation, on the relational check specifically.** Per the brief,
only the equal-length comparison was mutated: `covariance`'s
`ys : {List(Float) | len(_) == len(xs)}` → `len(_) >= 0` (trivially true), via a
file-copy swap (never `git stash` — shared stash stack). Result:

| case | before | after mutation |
|---|---|---|
| #20 `covariance` … RELATIONAL precondition | OK | **FAIL** |
| #23 `covariance` … SHORT-LIST precondition | OK | OK |
| #18 `covariance` fully guarded (ACCEPT) | OK | OK |
| #26 `covariance` unguarded (REJECT) | OK | OK |

Exactly one, distinct test caught it: **#20, the RELATIONAL case** — the
SHORT-LIST case (#23), the ACCEPT (#18) and the unguarded control (#26) were all
blind to it, which is precisely the confusion this mutation exists to rule out.
(An earlier draft of this paragraph named #23 as the catcher, contradicting the
table directly above it. The table is the measurement; #20 is the test that
flipped.) Contract restored and re-verified byte-identical.

**The short-list REJECT trio is coverage, not relational evidence.** `SCV3` /
`SCR3` / `SLR3` guard the equality and assert the survivor is `len(_) >= 2`.
They would pass **unchanged if the relational contract were deleted outright**:
with `ys` unrefined there is still exactly one recorded obligation,
`len(_) >= 2`, still `Skipped`, still hinted. So they say nothing about whether
`len(_) == len(xs)` exists or works — the whole relational load is carried by
the `SCV1` + `SCV2` pair described in the section above. Keep them (they are
real coverage of the short-list precondition), but do not cite them as
relational evidence.

## Deliberately unrefined: zero-variance and zero-standard-deviation

`Stats.linear_regression` also panics when `xs` has zero variance
(`stdlib/stats.march`, `panic("Stats.linear_regression: xs have zero
variance")`), and `Stats.correlation` when either list has zero standard
deviation (`panic("Stats.correlation: zero standard deviation")`). Both stay
unrefined, permanently, and this is the reasoning so a future reader does not
reopen it:

Both conditions are **data-dependent**. Zero variance means `n * Σx² - (Σx)² ==
0` — an arithmetic fact about the `Float` *values* in the list, which can hold
for a list of any length ≥ 2 (`[1.0, 1.0]` and `[1.0, 1.0, 1.0]` both trip it)
and fail for another list of the identical length (`[1.0, 2.0]`). No structural
property of the list — its length, its shape, anything a measure ranges over —
determines it. This plan's refinement machinery is Tier-1/Tier-2 induction over
`len` and user `@[measure]`s driven by ADT *structure*; it has no vocabulary for
"the sum of squares of the elements exceeds the square of their sum". There is
no contract to write, not merely a hard one.

This is the same carve-out already recorded for `Random.choice_weighted`'s
"weights sum to zero" and "negative weight" panics
(`specs/progress/2026-08-05-random-choice-weighted-empty-list-contract.md`,
Task 5), and it is called out by name in the plan's Global Constraints.

**Consequence, stated in both doc copies:** a `cap no_panic` module that calls
`Stats.correlation` with two lists proven equal-length and proven ≥ 2 elements
compiles clean and can still panic at runtime on zero standard deviation.

**This is not a regression, and the question was checked rather than assumed.**
The obvious worry is that moving a *partially* contracted name into the
proof-based covered set takes it from "always rejected" to "accepted while still
able to panic". Reviewed at the branch base (`38434ee1`): `panic_surface_stdlib`
and `panic_surface_prelude` contained **no** `Stats.*`, `Random.*` or
`DateTime.*` names at all, so a `cap no_panic` module could already call
`Stats.correlation` freely with zero checking of either structural condition.
This branch therefore moves these names from *no coverage* to *structural
coverage* — strictly more checking, not less. The thirteen names that WERE
previously banned were enumerated and each confirmed *fully* covered (its
contract matches that function's sole panic condition), so no previously
guaranteed name was weakened either. The
capability's guarantee covers the two structural conditions only. This is
partial coverage of a covered name, the same shape `Random.choice_weighted`
already documents.

## Stdlib + ecosystem sweep, with a failure-capable positive control

`grep -rn` for `covariance` / `correlation(` / `linear_regression` across
`stdlib/`, `test/`, `bench/`, and the `conduit` / `test_conduit_app` ecosystem
checkouts.

**Correction to an earlier draft of this note**, which claimed "no production
call site anywhere". That was wrong, and the misreading was mine: the sweep's
own output contained real March call sites and the summary line dropped them.
The actual results are:

- **`test/stdlib/test_stats.march:194, 200, 208, 214, 222, 229, 237` — seven
  real March call sites** (two `Stats.covariance`, two `Stats.correlation`,
  three `Stats.linear_regression`), the shipped behavioral tests for these
  functions. Every one passes list literals of 3–5 elements with `xs` and `ys`
  the same length, so all seven satisfy both new preconditions by construction.
  The file declares no `cap no_panic` (`grep`: no match), so none of them is
  even subject to the proof-based check. This file is exactly what `test_stdlib_march.exe` runs, and it passed
  (56 tests, exit 0) — so this is a *measured* result for these call sites, not
  an inspection.
- `stdlib/stats.march` itself (the definitions).
- This task's own new cases in `test/test_refinecheck.ml`.
- `test/whole_program/zoo.mjs`, a generated JS artifact (not a source call site).
- **No call site in `stdlib/` outside `stats.march`, in `bench/`, or in the
  `conduit` / `test_conduit_app` ecosystem checkouts.** `stdlib/dataframe.march`
  calls other `Stats` functions (`mean`, `median`, `percentile`, `min_val`,
  `max_val`, `std_dev`) but none of the three bivariate ones.

So there IS a production-shaped consumer, it is covered by a suite that ran
green, and nothing regressed.

The plan requires a positive control, because a byte-identical sweep result
proves nothing on its own — and it specifically rules out the prescribed
in-stdlib control, since `bin/main.ml` filters stdlib-span diagnostics and would
report a false "no diff". The control used is the RED/GREEN pair above: the same
scratch fixture text, outside `stdlib/`, exits **0** on the pre-change binary and
**1** after, on the same build process. The sweep is a measurement, not a no-op.

Suite results below are the other half of the control: `run_stdlib`,
`test_stdlib_march` and `run_eval` all exercise `stats.march` and stayed green.

## Nothing widened

- **`List.nth` is unchanged.** `stdlib/list.march` is not in the diff at all.
  Behaviorally re-confirmed on a scratch fixture: a guarded `List.nth` proves
  (`1 proved`) and an unguarded one still errors — the same shape it had before,
  despite this task reusing exactly its sibling-measure machinery.
- **Task 5's and Task 6's contracts are unchanged.** `stdlib/random.march` is
  not in the diff; `git diff stdlib/` touches only the three `covariance` /
  `correlation` / `linear_regression` signatures and their docstrings — no other
  signature in `stats.march` was edited, so `percentile`/`quantile`/`quantiles`/
  `five_number_summary`/`variance`/`mode`'s `len(_) > 0` and the two float-range
  preconditions are byte-identical.
- `panic_surface_contracted` was only APPENDED to; no existing entry's spelling
  or position changed.

## Test results

Foreground, redirected, judged by `$?`:

- `./_build/default/test/test_refinecheck.exe -e` — exit **0**, **522 tests**,
  `Test Successful` (513 before this task's 9 additions).
- `./_build/default/test/run_compiler.exe -e` — exit **0**, 727 tests.
- `./_build/default/test/run_stdlib.exe -e` — exit 1, 830 tests, **1 failure**:
  `adversarial-regressions #40 MARCH_SANITIZE`, the known host-wide ASAN-hang
  flake this plan's operating notes name as the only stdlib failure on this
  branch. Mechanism check: the files changed here are `stdlib/stats.march` and
  `lib/typecheck/typecheck.ml`; that regression exercises an unrelated sanitized
  binary and reaches neither.
- `./_build/default/test/test_stdlib_march.exe -e` — exit **0**, 56 tests.
  (Required separately: `stdlib/*.march` edits are covered by two different
  binaries.)
- `./_build/default/test/run_eval.exe -e` — exit **0**, 256 tests.
- `scripts/check-docs.sh` — exit **0**, doc-lint passed.

## Published stdlib HTML regenerated (branch-close task)

`docs/docs/stdlib/*.html` is pre-generated, committed, and served directly by
GitHub Pages; nothing in CI regenerates it and `scripts/check-docs.sh` does not
lint it, so it had gone stale for this whole branch — `Stats.html` still
rendered `covariance(xs : List(Float), ys : List(Float))`, and Task 5's
`Random.choice_weighted` and Task 6's `percentile` `xs` were equally stale.
Regenerated with `scripts/gen-stdlib-docs.sh` (dune + the `march_doc` generator;
no Ruby/Jekyll needed for this step), exit 0, 112 module pages. The diff is
exactly the three tasks' contracts and nothing else: `Random.html` (Task 5),
`Stats.html` (Tasks 6 and 7), `search-index.json`. No hand-editing.

## Files changed

- `stdlib/stats.march` — the two preconditions on all three bivariate
  functions; each docstring extended to state the declared preconditions and,
  for `correlation`/`linear_regression`, to name the data-dependent panic that
  stays a runtime check.
- `lib/typecheck/typecheck.ml` — three names appended to
  `panic_surface_contracted`.
- `test/test_refinecheck.ml` — `stats_diagnostics` factored out;
  `unverified_preconditions_stats`, `only_unverified_is`; nine cases.
- `docs/capabilities.md`, `specs/lang/capabilities.md` — three names added to
  the contracted-names list; the existing "not every panic on a covered name is
  covered" paragraph rewritten in each (it previously said these two functions
  were "not on the covered list at all", which this task makes false) to
  describe the structural/data-dependent split within one signature and to name
  the `List.nth` precedent for the relational shape.
- `CHANGELOG.md` — three names added to the existing `### Changed` bullet's
  list; a new bullet for the relational precondition and its carve-out.
- `docs/docs/stdlib/Stats.html`, `docs/docs/stdlib/Random.html`,
  `docs/docs/stdlib/search-index.json` — regenerated published API reference,
  catching up Tasks 5, 6 and 7 (see above).
- This file.

## Known gap, deliberately deferred

`panic_surface_suggestion` has no case for the three new names, so the
"use X instead" hint is generic for them. Cosmetic, and consistent with Task 6,
which left the same gap for its six. Not fixed here.
