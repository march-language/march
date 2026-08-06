# `--refine-suggest*` corrupted the per-call-site verdict index

Date: 2026-08-05

## The defect

`Obligation.by_span` (see `2026-08-05-per-call-site-verdict-index.md`) is
populated by `Refine_check.check_module` and read by
`Panic_surface_by_proof.check_module`, which enforces `cap no_panic` by asking
whether each covered call's precondition came back `Proved`.

In `bin/main.ml`'s `compile`, the refinement *suggestion* printers ran between
the two:

```
Refine_check.check_module            <- POPULATES Obligation.by_span
print_refine_suggestions             <- Precond_infer probes; each calls Ob.reset ()
print_refine_postconditions          <- Postcond_infer probes; same
Division_safety.check_module
Panic_surface_by_proof.check_module  <- READS Obligation.by_span
```

Each probe (`Precond_infer.walk_debt`, `Postcond_infer.walk_debt`) calls
`Ob.reset ()` and re-walks a **hypothesis** module — the user's program with a
speculative contract spliced into one signature — to see whether the debt
shrank. That refills `by_span` from the hypothesis. `Panic_surface_by_proof`
then read whatever the last probe left behind.

`cap no_panic` therefore flipped in **both** directions on a diagnostic-only
flag, on the branch build with `.march/cas/{artifacts-v2,vc}` cleared:

| fixture | `--check` | `--check --refine-suggest-all` |
|---|---|---|
| `cap no_panic` + unguarded `List.tail(xs)` | rc=1 (error) | **rc=0, clean** |
| `cap no_panic` + `{List(Int) \| len(_) > 0}`-guarded `List.tail` / `Stats.mean` | rc=0 | **rc=1** |

The fail-open row is the guarantee hole: a probe hypothesised
`xs : {List(Int) | len(_) > 0}`, recorded `Proved` at that call's span, and the
pass believed it. The same run still printed
``precondition `len(_) > 0` on `List.tail` was NOT verified here`` — the output
contradicted its own exit code.

The fail-closed row is the mechanism's cardinal sin. Its cause is different:
`Precond_infer.prune` rebuilds a tree holding only the *current* target, so once
the sweep moves past a function, the index holds nothing at all for its call
sites, and "no verdict recorded here" is (correctly, fail-closed) an error.

Reachable from shipped tooling, not just a hand-typed flag: `forge refine`
shells out to `march --check --refine-suggest-json …`
(`forge/lib/cmd_refine.ml:110`, `:239`), and the unsound fixture returned rc=0
through that path too. `march test` was **unaffected** — its copy of the
pipeline has no printers — so the two pipelines disagreed.

## The fix

Two independent parts; both landed, on purpose.

**1. Order.** `Division_safety.check_module` and
`Panic_surface_by_proof.check_module` moved up to sit immediately after
`print_refine_report`, before the two suggestion printers. That makes `compile`
match `run_test_cmd`'s existing order exactly (`bin/main.ml:1387–1397`).

`Panic_surface_by_proof` does not depend on `Division_safety` having run:
`Division_safety` records only `kind = Division` obligations (one `Obligation.record`
call, `lib/refinecheck/division_safety.ml:406`), and
`Panic_surface_by_proof.verdict_for` filters to `kind = Precondition` for the
named callee. Their relative order is preserved anyway. `print_refine_report`
stayed *above* both, so `--refine-report`'s contents are unchanged (moving
`Division_safety` above it would have added `Division` obligations to the
compile pipeline's report).

Diagnostic output ordering is unaffected: diagnostics are printed once, later,
through `March_errors.Errors.sorted` (by position), and the printers write to
stdout before that. Verified by inspection and by the corpora — no existing test
asserts on the relative order of suggestion output and diagnostics.

**2. Non-destructive probes.** New `Obligation.with_scratch : (unit -> 'a) -> 'a`
snapshots the ledger and `by_span`, runs the probe sweep, and restores both
(including on an exception). `Precond_infer.suggest`/`suggest_all` and
`Postcond_infer.suggest`/`suggest_all` are wrapped in it.

Part 1 alone would have left a loaded gun: "consumers of `by_span` must run
before the printers" is an invariant no reader of `by_span` can see. Part 2
enforces it where it is violated.

## Regression test

`test/test_refinecheck.ml`, group `no-panic-by-proof`, two cases:

- `cap no_panic: unguarded List.tail errors with AND without probes`
- `cap no_panic: guarded List.tail is clean with AND without probes`

driven by `no_panic_errors_under_suggestion_probes`, which runs
`Precond_infer.suggest_all` in the **old, hazardous** position — between
`Refine_check` and `Panic_surface_by_proof` — over the real `stdlib/list.march`
and `prelude.march`. Deliberately the hazardous order: the safe order would make
the test pass with the real defect still present.

Two things about the fixture design that were found empirically, and are
recorded because a future edit can silently un-load-bear this test:

- The harness runs `Precond_infer` only. An earlier draft chased it with a
  `Postcond_infer.suggest_all` sweep, and that draft **passed against the
  unfixed compiler**: a postcondition probe's last walk is over a tree whose
  preconditions are unmodified, so it refilled the index with something close
  enough to the truth to mask the corruption.
- The guarded fixture has **two** functions. With one, the last walk is that
  same function's own, the index ends up right by accident, and the fail-closed
  assertion passes against the unfixed compiler.

Verified load-bearing by reverting the `Ob.with_scratch` wrapping (four lines)
and rebuilding: both cases `[FAIL]`, exit 1. Restored: both `[OK]`.

## Also fixed here

`Typecheck.calls_in_expr` (`lib/typecheck/typecheck.ml`) now carries a reciprocal
keep-in-sync note pointing at its structural clone,
`Panic_surface_by_proof.calls_in_expr`. Only the clone pointed at the original.
Because the contract-covered names were *removed* from the typechecker's
syntactic ban rather than double-checked, drift is fail-**open**: a new
`Ast.expr` form added to the typechecker's walk and not to the clone would admit
a covered panicky call. Style follows the existing reciprocal note on
`is_migrate_fn_name`.

## Verification

- CLI, caches cleared once, before and after, for both fixtures, across
  `--refine-suggest-all`, `--refine-suggest-post-all`,
  `--refine-suggest-json --refine-suggest-all` (the `forge refine` command
  line), `--refine-suggest-json --refine-suggest-post-all`, `--refine-report`,
  and no flag: after the fix, the exit code is identical to the no-flag run in
  all twelve combinations.
- `test_refinecheck.exe` 524 tests, `run_compiler.exe` 727, `run_eval.exe` 256,
  `run_stdlib.exe -q` 782, `run_codegen.exe`, `test_refine.exe` 22,
  `test_caps.exe` — all exit 0.

## Deliberately not done

Triaged as separate follow-ups, out of scope here: consolidating the three
near-copies of the check pipeline in `bin/main.ml`; the ten covered names with
no `panic_surface_suggestion` remedy text; the two inert entries (`last`,
`expect`) in `panic_surface_contracted`; the stale test identifier
`test_cap_no_panic_list_tail_guarded_still_error`.
