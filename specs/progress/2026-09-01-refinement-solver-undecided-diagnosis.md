`[P2]` Diagnose the `solver-undecided` bucket (filed 2026-09-01, landed 2026-09-01)

32 of 34 skipped refinement obligations over a six-stdlib-module sample land in
one undifferentiated `solver-undecided` bucket whose user-facing text says
nothing about the call in front of the reader.  Split it into four diagnosed
causes (unconstrained subject / partial conjunct / non-linear goal / opaque
application), keeping `Solver_undecided` as the honest residual, and promote the
sub-case that can be *proven* a real failure by executing the enclosing function
from its entry under the existing fuel limit and effect veto.

Design: `specs/2026-09-01-refinement-error-diagnosis-design.md`.

Does **not** close the underlying precision gaps (let-bound constants are still
not propagated into the path context; match-arm exclusions are still not
derived) — those are a separate item, and this one is sized to be independent
of them.

Soundness constraint, do not skip: `Witness.confirm_precond` validates against
the *recorded* path facts, so wiring it into the undecided branch as-is reports
confirmed failures in provably correct code — `stdlib/list.march:128`
(`List.last`'s recursive call) is the worked counterexample.  The negative
fixture asserting silence there is the most important test in the item.

---

**Landed 2026-09-01.**  Plan:
`specs/plans/2026-09-01-refinement-error-diagnosis-plan.md` (9 tasks).
Measurements: `specs/2026-09-01-refinement-error-diagnosis-measurements.md`.

Shipped: `Obligation.reason` gained three diagnosed skip causes —
`Unconstrained_subject`, `Partial_conjunct`, `Opaque_application` — with
`Solver_undecided` kept as the residual.  `Refine_call.check_call`'s
fall-through calls a new `diagnose` that inspects the VC's *user* assumptions
and the goal's conjunct structure; `Refine_check`'s hint renderer prints a
diagnosed cause at EVERY call site that has one and keeps the pre-existing
once-per-module note for the residual.  `bin/main.ml`'s `print_refine_report`
now keys its bucket table on the cause slug rather than on the whole reason
value.  On top of that, `Witness.confirm_precond_reachable` executes the
ENCLOSING function on the solver's model, and a confirmed, repairable panic
promotes the skip to a warning (an error under `cap verified`) carrying a
`Precond_infer`-derived signature and a machine-applicable `forge fix`.

Numbers (Task 8, 298 entry files, clean `user code` slice): `solver-undecided`
fell from 59 of 70 skips (84%, the largest bucket) to 8 of 66 (12%, the third
largest); `unconstrained-subject` 41, `partial-conjunct` 6,
`unreflectable-predicate` 11 unchanged, `proved` unchanged at 95.  Four
promotions corpus-wide, all in `stdlib/stats.march` compiled as an entry file,
all hand-audited genuine — **zero false positives**.

Deviations from the design doc and the plan (each carries a
"Correction"/"Shipped" note in the plan's `### Task N` section):

- **`Nonlinear_goal` was cut**, so three diagnosed causes shipped, not four.
  It is unreachable: `refine_scope.ml`'s `smt_of` returns `None` for a product
  of two non-literals, so `pos(a*b)` dies as `unreflectable-predicate` before
  `check_call`'s fall-through ever runs.  `Smt.Mul` is built only by
  `division_safety` and `return_infer`, neither of which feeds `check_call`'s
  skip ledger.
- **`Opaque_application` was kept deliberately even though it fires zero times**
  on the corpus.  It is reachable in principle (unlike `Nonlinear_goal`) and is
  covered only by a negative control; no positive fixture exists.  Removing it
  would have to be re-argued later, so it stays.
- **Five structural-assumption sites, not one.**  "Nothing constrains the
  subject" cannot be `List.mem subj (consts assumptions)`: the encoder emits
  well-formedness axioms that mention the symbol.  An audit of all 13
  `assume` sites found **5** structural ones, all of which `diagnose` must
  ignore.  Only user facts count as constraining; `discharge` still sees the
  FULL assumption set, so no precision changed.
- **Symbol/name split.**  A measure-typed subject reflects to the SMT symbol
  `len$ys`, so the CHECK must use `len$ys` while the MESSAGE must say `ys`.
  Getting this wrong first made the variant unreachable for exactly the shape
  that motivated it, then leaked `len$ys` into user text; both were caught in
  review (fix rounds 2 and 3 of Task 1).
- **`--refine-report` groups by cause slug.**  The design asserted the report
  needed no change; it did.  Keying the bucket table on the whole reason value
  split `unconstrained-subject` into 9 lines (one per variable name) and would
  have destroyed Task 8's distribution measurement.
- **`Partial_conjunct` renders the CALLEE's vocabulary** (`_ < len(xs)` even
  when the caller's parameter is `idx`).  Defensible — the line above frames
  the whole thing as a precondition *on* the callee and quotes its contract
  verbatim — but noted as a known rough edge.
- **`confirm_precond_reachable` takes five arguments**, not the plan's shape:
  `~fn ~pred ~binder ~arg ~model`.  It gates on three things, all added in
  review: the predicate must be FALSE under the decoded arguments; repairing
  only the subject to a satisfying value must REMOVE the panic (a bare
  "some panic happened" oracle accepts an unrelated branch's panic and would
  make `precond_infer` suggest a fix that does not silence it); and the callee
  must be resolved by IDENTITY via `qualified_fn_name` rather than by bare
  name, since `lookup_fn` prefers an exact bare binding and would attribute a
  top-level `f`'s panic to a nested `Inner.f`.  Ambiguous or unresolved
  declines.
- **`with_harness` classifies panics by prefix.**  It previously mapped every
  `Eval_error` to `Panicked`, but `eval_error` is the evaluator's general
  failure helper (~860 sites).  Only the four user-panic builtin prefixes are
  panics now (marker stripped for the quoted text); everything else declines.
  This is shared with `confirm_post` and `confirm_enumerative`, so the earlier
  return-contract witnesses (#383) are tightened by the same change.
  Coverage gap in the safe direction: `Match_failure`/`Assert_failure`, which
  are genuine March panics, still decline.
- **The fix offer is attached by a caller-side post-pass.**
  `precond_infer.ml` depends on `Refine_check`, so `check_module` cannot call
  `Precond_infer.suggest` from its own epilogue (module cycle).  The drain is
  `Precond_infer.attach_promoted_fixes`, run by the caller immediately after
  `check_module` (both `bin/main.ml` pipelines and the test helper).  This
  satisfies the "never re-enter the checker inside the walk" constraint more
  strictly than the planned epilogue would have; a caller that skips the
  post-pass degrades to "the message without the offer", never to a lost
  finding.
- **The suggestion is selected by EXACT qualified name.**  `Precond_infer`'s
  `matches_target` accepts any dotted suffix (so `forge refine chunks` finds
  `Text.Split.chunks`), and an entry-file top-level function's qualified name
  is unqualified — so taking the head of the match list attached `Inner.go`'s
  `{Int | _ != 0}` to a sibling `go(ys : List(Int))` and `forge fix` rewrote
  `ys : Int`.  Shipped code uses `find_opt (r.rs_fn = qname)` and declines when
  there is no exact match.  Suggestion also probes once per target function
  rather than once per site.
- **Promotion is skipped at stdlib spans** (see the CHANGELOG entry): stdlib
  diagnostics are filtered from the printed stream, so a promotion there was
  invisible cost.  `stdlib/stats.march`'s four sites are visible only because
  the measurement compiles that file as the entry file.
- **`Violated` conflates two verdicts.**  A promotion is recorded as
  `Obligation.Violated`, the same verdict used for a contract that can never
  hold (and already used by `refine_post` for some-input return failures).
  `violated: 4` therefore means "4 obligations for which some input
  demonstrably fails", not "4 that never hold"; the report cannot currently
  distinguish them.

Known gaps, all deferred by review with the finding recorded:

- No positive `Opaque_application` fixture (the variant fires zero times on the
  corpus; only a negative control exercises it).
- `Partial_conjunct`'s message uses callee vocabulary (above).
- `Match_failure`/`Assert_failure` are not recognised as panics (safe
  direction: they decline).  The shrunk-witness re-read is `wall_budget`
  order-dependent, also in the decline direction.  The `fc_guard` decline is
  dead code (desugar folds guards).
- A promoted `cap verified` ERROR carries no argument label, where the
  solver-`Violated` path does.
- `refine_check.mli` exposes writable refs (`promoted_sites`,
  `stdlib_source_files`); a `take_promoted_sites` drain plus the existing
  `is_stdlib_source_file` re-export would be the honest seam.
- `quantile_default` gets a true promotion with no `help:` signature, because
  its callee has two unforwarded preconditions and no single-parameter
  suggestion is unambiguously correct.
- `--refine-report` should distinguish "never holds" from "some input
  demonstrably fails" in the `violated` count.

Follow-up already filed separately: `confirm_post` (#383's return-contract
witness) has the SAME hidden-refinement exposure that Task 5 fixed for the
precondition path — a refinement on a type argument, a named type's field, or
under `TyLinear` is unchecked, so a witness can be built from a value the
checker never validated.  Not a live false positive today (the checker accepts
the violating construction), but it becomes one when nested refinements are
enforced.

Verification: `refine-oracle` proven RED-capable first (a deliberate
"always `Proved`" perturbation at `refine_call.ml`'s discharge produced a
distinct 1080-line diff and a different report-line total), then the real
branch diff of 1710 lines classified exhaustively into expected text change
(439), expected regroup (1211) and intended promotion (60), with **zero**
unclassified lines and zero `opaque-application` slugs.  Full
`scripts/run-tests.sh` green; `test_refinecheck` 588 [OK] (run directly — `scripts/run-tests.sh` does not
include it); `@types-check` 303/0, `@grammar-check` 48/0 and
`scripts/check-docs.sh` all green.

Two further notes from the final-review fix rounds (2026-09-02):

- Alias-withdrawal attribution under a conjunctive predicate now tests the
  guard only against the conjuncts the whole-goal split judged *missing*, and
  requires every measure-mentioning missing conjunct to be discharged by it
  (`guard_discharges`, `refine_call.ml`). A withdrawal is therefore never
  blamed for a conjunct it could not have stopped — verified by a control that
  deletes the competing binding and is still undischarged. Documented trade:
  when a measured missing conjunct IS stopped by the withdrawal but a
  non-measured one also remains undischarged, the message reports the
  withdrawal (true of the measured half) though renaming the binding will not
  fully silence the call.
- `pred_str`'s `<predicate>` fallback can reach user-facing text (e.g.
  `_ != <predicate>` for a string-literal comparison inside a conjunct).
  Pre-existing, not introduced here.
