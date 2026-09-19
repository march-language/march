# Plan: element refinements through expressions, callbacks, and polymorphic combinators

**Date:** 2026-09-18
**Design:** `specs/2026-09-18-parametric-element-flow-design.md` (section numbers below refer to it).
**Todos:** `specs/todos/2026-09-18-refine-parametric-rule-trusts-flexible-tyvars.md` (Phase 0),
`-refine-element-facts-through-expressions.md` (Phase 1),
`-refine-callback-element-sources.md` (Phase 2),
`-refine-demand-driven-element-instantiation.md` (Phase 3).

Conventions, same as the set-refinements and precision plans:

- One PR per phase. Phase 0 lands first and alone; it is a soundness fix.
- Every step keeps `test_refinecheck.exe` green and is proven by a test that
  **fails on the code before it**. Record which case goes RED without the step
  in the progress note.
- Every new assumption gets a control that must *skip*; every new obligation
  gets a REJECT fixture. Assert on ledger counts (`proved, violated, skipped`),
  not just exit codes: a skip and a proof both exit 0.
- Unit fixtures that exercise P1 must use the typed harness
  (`has_refine_error_typed` / `typed_ledger`). Without a type table P1 answers
  "no", so an untyped fixture silently tests the fallback.
- Run from the worktree with `--root .`. z3 must be on `PATH`, or
  `test_refinecheck` reports 550+ `[SKIP]`s and exits 0.

## Baseline (before Phase 0)

1. Record, under a private `HOME` with `.march/cas/vc` and `.march/cas/artifacts-v2` cleared once:
   - `--refine-report` and `--refine-report-sites` for `stdlib/list.march`;
   - `--refine-audit` counts;
   - cold `--check` wall time for `stdlib/list.march` (three runs, take the median).
2. `scripts/refine-oracle.sh baseline /tmp/<slug>-refine-oracle` and
   `scripts/types-oracle.sh baseline /tmp/<slug>-types-oracle`. Perturb one
   fixture on purpose and confirm `check` goes RED before trusting a GREEN.
3. Save the probe programs from design §0 as fixtures under
   `test/refine_probes/element_flow/` (rows a–n, z) with a small driver that
   prints each row's ledger triple. That's the before/after table for every
   phase's progress note.

## Phase 0: parametric soundness (design §1)

| Step | Change | Proof |
|---|---|---|
| 0.1 | **Investigate before coding.** Confirm that `type_map` holds each parameter binder's post-generalization type, that it's present on the cached driver path (`bin/main.ml`, the `cached_tm` merge), and what an unbound, generalized variable looks like after `repr`. If binder types are missing or specialized for generic functions, add a `fn_generic_vars` export from `lib/typecheck` keyed by declaration span and pass it through `check_module` beside `~type_map`. Write the finding into the progress note. | a scratch probe printing the recorded type for `bad`'s `xs` (expect `List(Int)`) and `List.reverse`'s `xs` (expect `List('a)`) |
| 0.2 | `Refine_encode` (or a new `refine_param.ml` if it passes ~200 lines): `generic_in_inferred sg fd v`, implementing P1 with its distinctness check. | unit: `bad` fails, `reverse` passes, `f(xs : List(a), ys : List(b)) : List(b) do xs end` fails |
| 0.3 | `manufacturing_builtins` and `diverging_builtins` lists, plus a **drift-guard test** in `test/test_refinecheck.ml` that enumerates `Typecheck_builtins` schemes and asserts every result-only-type-variable builtin is on one of the two lists. | the guard goes RED when one name is removed from the list |
| 0.4 | `parametric_safe` fixpoint over the call graph (reuse `gate_unverified_posts`' `calls_of`; lift it to a shared helper rather than copying it). Externs, bounded variables and non-safe polymorphic-return callees taint. | unit: a function calling a listed creating builtin is unsafe; one calling `int_to_string` is safe; one calling an unsafe polymorphic helper is unsafe |
| 0.5 | Gate `parametric_return` on P1 ∧ P2 for each type variable it uses. | row z: `1 proved` becomes `1 skipped`. The whole `container-subtyping-2` group stays green |
| 0.6 | Re-measure the baseline. **Expected: no change** to stdlib counts or the skip ceiling. If a stdlib site moves from proved to skipped, find which of P1 (a binder type not recorded) or P2 (an over-broad taint) caused it before relaxing anything. | numbers in the progress note |
| 0.7 | Docs: state P1/P2 wherever `specs/lang/refinement-types.md` describes element refinements flowing through a polymorphic call (and in its drifted copy under `docs/`; edit both). CHANGELOG `### Fixed`: "a polymorphic function whose type variable was silently fixed by its body no longer lends element refinements to its result." File `specs/todos/2026-09-18-typecheck-annotated-tyvars-flexible.md` (already drafted). `git mv` the Phase 0 todo to `specs/progress/`. | `scripts/check-docs.sh` |

**Exit:** row z skips, stdlib counts are unchanged, the refine oracle is GREEN
except the row-z fixture, and `cap verified` rejects a module containing row z
(pinned with a test).

## Phase 1: facts through expressions (design §2)

| Step | Change | Proof |
|---|---|---|
| 1.1 | `container_entry_of_expr` with the `EVar` / `EAnnot` / parametric arms only (no declared-return arm yet). Route `check_elements`' variable arm, `parametric_return`'s actual lookup, and the `let` §2c arm through it. Pure refactor on the variable case. | the whole existing suite green; the oracle shows no diff |
| 1.2 | Nested actuals: `parametric_return` resolves actuals recursively. | row d proves; `reverse(reverse(xs))` proves; unrefined-source control skips |
| 1.3 | `EMatch` element facts on a non-variable scrutinee. | row e proves; control skips |
| 1.4 | `elem_ret_proved` table plus fixpoint rounds (`check_elements ~emit:false`). The declared-return arm of `container_entry_of_expr`. | row g proves; a function with a skipped tail is **not** in the table (control skips at its caller); a two-function chain in reverse declaration order proves (fixpoint) |
| 1.5 | Move container-return tail checks into `visit` (`rctx.ret_elem`); delete the pre-walk block in `visit_fn`; set/reset in `visit_lambda`, `visit_local_fn`, handlers. | row f proves; a literal bad tail under a `let` is reported **once** (ledger count pins single-checking); a local `fn` with a refined container return is now checked (REJECT fixture) |
| 1.6 | Re-measure. **Expected:** stdlib proved count up or equal, skips down or equal. Lower the CI skip ceiling if it drops. Coverage audit: no site becomes Unenforced. | numbers in the progress note |
| 1.7 | Docs + CHANGELOG `### Added` + `git mv` Phase 1 todo. | `check-docs.sh` |

## Phase 2: callback and self-call sources (design §3)

| Step | Change | Proof |
|---|---|---|
| 2.1 | Thread `cb` into `check_elements`, `check_arg_elements`, `check_field_elements`; `postcond_of ~cb`. | row i's element `f(h)` proves; with `~cb` removed again the case goes RED |
| 2.2 | Self-call hypothesis inside `elem_ret_proved`'s check (structural only, scoped like `enclosing_fn`). | row j proves `map_pos`; the non-structural control (`map_pos(xs, f)`) skips; a mutual-recursion pair skips |
| 2.3 | Container codomain at the pass site: obligation (lambda tails via `check_elements`; named via `elem_ret_proved` + `Element_domain` implication), then `callback_sig_of_ty` records `ret_ty` and the declared-return arm accepts `cbenv` callees. **Obligation first, assumption second, same PR.** | lambda returning `[0]` reported; named proved callable passes; named unproved callable is a recorded skip; assumption proves `sum_pos(g(x))` inside the HOF |
| 2.4 | `Witness.confirm_lambda_post`: closed-lambda evaluation in `module_env ()`, same fuel/wall/effect harness, shrink. Wire it into `check_pass_sites`' inline-lambda codomain branch. | row k reported with witness; capturing-lambda control stays a skip; an effectful lambda body (`println`) is declined by the veto, not run |
| 2.5 | Re-measure + ASAN is **not** needed (no runtime change). Refine oracle: the only diffs are the new fixtures. | numbers in the progress note |
| 2.6 | Docs (the "Two higher-order shapes are checked" bullet in Limitations needs rewriting), CHANGELOG, `git mv` Phase 2 todo. | `check-docs.sh` |

## Phase 3: demand-driven instantiation (design §4)

| Step | Change | Proof |
|---|---|---|
| 3.1 | `sources_of g v`: the polarity walk, returning `Bare`/`Elem`/`Codomain` sources or `None`. Pure function, unit-tested on the real stdlib signatures of `map`, `flat_map`, `filter_map`, `filter`, `sort_by`, `fold_left`, `Option.map`, `Result.map`, and on `Task(v)` / tuple / higher-rank negatives. | unit table |
| 3.2 | Replace §2c's `safe` with the source analysis for the **assumption** direction (every source is an `Elem` with an agreed slot). | `container-subtyping-2` unchanged; `sort_by(pos, cmp)` now proves (it was a skip); the interface-bound control skips |
| 3.3 | Demand matching: the declared return against the demanded entry, giving `D(b)`. Obligation discharge per source kind, with the verdict combination in §4.3, and the new skip reason `parametric-source-unproved` added to `Obligation`, `--refine-report`, and the `cap verified` message. | row l proves; `flat_map`/`filter_map`/`Option.map`/`Result.map` fixtures prove; each has a control that skips |
| 3.4 | Refuted source: skip plus witness hint, **not** a violation. | the `put(xs, 0 - 1)` shape and `List.map(ys, fn y -> y - 1)` into `sum_pos` both skip with the hint text asserted; under `cap verified` both are errors |
| 3.5 | Domain facts for inline lambdas (§4.4). | row m proves; with disagreeing sources (a two-list callee) nothing is assumed (control skips) |
| 3.6 | Re-measure, including cold time against the 10% budget (design §6). Run the stdlib skip census (`--refine-report-sites`) and record which stdlib skips moved. | numbers in the progress note |
| 3.7 | Docs: a new "Element refinements through polymorphic functions" subsection in `specs/lang/refinement-types.md` (+ `docs/` copy), naming the §4.5 exclusions. CHANGELOG `### Added`. `git mv` Phase 3 todo. File follow-ups: curried callbacks / `fold` invariant; scalar demand on a bare return; abstract refinements (`filter`). | `check-docs.sh` |

## Verification before each merge

- `scripts/run-tests.sh` (full), plus `scripts/run-tests.sh refinecheck` with z3 on `PATH`.
- `scripts/refine-oracle.sh check` and `scripts/types-oracle.sh check` against the
  baseline: the only allowed diffs are the fixtures this phase added. The types
  oracle must be fully GREEN, since no phase touches the typechecker. The
  exception is Phase 0 if step 0.1 needed the `fn_generic_vars` export, and
  even then it adds data without changing any inference result.
- `scripts/check-docs.sh`.
- The probe table from the baseline, re-run and pasted into the progress note.

## Effort (rough)

| Phase | Estimate | Risk |
|---|---|---|
| 0 | 1–2 days | 0.1 may force the typechecker export |
| 1 | 2–3 days | 1.5 (moving tail checks) touches every function's walk; watch ledger double counts |
| 2 | 2–3 days | 2.4 depends on evaluating a bare `ELam` in the interpreter env; decline paths must stay total |
| 3 | 4–6 days | the polarity walk's edge cases; keep `None` generous |

## Decisions taken in this plan (revisit only with a reason)

1. Phase 0 fixes the checker, not the language. Rigid type variables are a separate todo.
2. The self-call hypothesis stays structural, matching Tier 2.
3. A refuted parametric source is a skip with a hint, never a violation (§4.3).
4. Phase 3 is single-parameter callbacks with container demands only. `fold`, scalar demands and `filter` are named follow-ups.
