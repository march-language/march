# DONE 2026-09-21: `--emit-core-ast`'s `"verdict"` now matches `--check` on every corpus program

## The bug

`march --emit-core-ast` reported `"verdict":"accept"` (exit 0) on three
`specs/lang/types/reject/` programs that `march --check` rejects (exit 1):

- `t43_cap_no_alloc_tuple.march`
- `t180_ceiling_stdlib_mediated_under_check.march`
- `t182_ceiling_module_let_stdlib_mediated.march`

march-lean's conformance harness classifies that as `MARCH_SELF_INCONSISTENT`
(a hard failure), so these blocked bumping its pinned march SHA; and
`scripts/types-oracle.sh`'s Tier 1 (which hashes the emitted JSON) was blind to
both rejection classes below.

## Two causes, not one

The verdict was computed from the front-end error set only, and the hoist
comment in `bin/main.ml` claimed it was "the same accept/reject condition
--check uses". It was not, in two separate ways:

1. **Contract stage (t43).** `--check` then runs
   `March_tir.Contract_pipeline.check_contracts` (allocation contracts,
   `cap no_alloc` / `@[no_alloc]`, judged on lowered TIR) and exits 1 on an
   Error. Those diagnostics did not exist yet when the emit call ran.
2. **Typecheck-side capability ceiling (t180, t182).** These are *not*
   contract-stage rejections, contrary to the initial report. The
   typechecker's stdlib-mediated ceiling (`Typecheck.cap_strict_ceiling`) was
   switched on only for `--check`/`--check-json`, so under `--emit-core-ast`
   the typechecker never produced the diagnostic at all. Fixing (1) alone
   leaves both still reporting accept. Confirmed by running the fix for (1)
   first.

## The fix (`bin/main.ml`)

- `cap_strict_ceiling` is now also on under `--emit-core-ast` (still off on
  `--compile`, where the TIR-side `Cap_ceiling` is authoritative).
- The contract check is one `lazy` value shared by `--check` and
  `--emit-core-ast`. The emit path forces it only on a front-end-clean
  program (the same condition under which `--check` reaches it), appends its
  user diagnostics to the emitted `"diagnostics"`, and folds any Error into
  the verdict. `frontend_rejected` names the front-end condition once and
  replaces its three copies. The hoist comment is rewritten to say it is
  only the front-end half.

Cost on ordinary programs: `check_contracts` returns `[]` after a
`List.exists is_obligation` scan unless the program carries an obligation.
Timed 8x `--emit-core-ast` base vs fixed, warm cache: `t01_literals` 3.29 s
vs 3.19 s, `stdlib/json.march` 22.8 s vs 21.8 s, i.e. noise.

## Evidence

- A sweep of `--check` exit code against the emitted verdict over all 770
  types-oracle fixtures (`specs/lang/types/{accept,reject}`, `test/native`,
  `stdlib`): 0 disagreements after the fix (484 accept / 286 reject).
- `scripts/types-oracle.sh` A/B (baseline = unfixed `main.ml`): Tier 2
  (`--check`'s diagnostic text) byte-identical over 11840 lines; Tier 1 moved
  on 19 fixtures, every one by the emitted JSON gaining exactly the
  diagnostic `--check` already prints: t43, t180, t182 (accept to reject),
  t39 (already reject, gains its ceiling line), and 15 stdlib modules used as
  entry files (ceiling lines; `stdlib/cluster.march` flips accept to reject,
  as `--check` already did).
- `test/test_emit_core_ast.ml`: new table-driven "verdict matches --check"
  group (the three files, plus a typecheck-only reject, a plain accept, and
  `t55_cap_no_alloc_arithmetic`, an accept that does run the contract stage).
  Against the unfixed binary exactly the three target cases fail.

## Not changed

`--check-json` has no verdict field and still does not run the contract stage,
so it omits a `cap no_alloc` violation's diagnostic. Separate item if it
matters to a consumer.
