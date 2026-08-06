# `Stats` — `percentile`/`quantile`/`quantiles`/`five_number_summary`/`variance`/`mode`: empty-list panic refined

Task 6 of the 2026-08-05 no-panic-proof-based-and-group-b plan.

## Verification: each of the six genuinely lacked the contract

Re-grepped every name before touching anything (line numbers drift, names
don't): `percentile` (`stdlib/stats.march:67`), `quantile` (`:251`),
`quantiles` (`:278`), `five_number_summary` (`:313`), `variance` (`:370`),
`mode` (`:415`). All six panic on `Nil` with their own "empty list" message;
none carried `{List(Float) | len(_) > 0}` — confirmed by reading each
signature directly, not assumed from the brief. `Stats.mean`/`min_val`/
`max_val` (lines 27/38/47) already carried the exact contract from an earlier
task and were left untouched (diff-verified at the end, see below).

## The contract

Same shape as `mean`/`min_val`/`max_val`'s existing
`{List(Float) | len(_) > 0}`, applied to all six:

```march
fn percentile(xs : {List(Float) | len(_) > 0}, p : {Float | _ >= 0.0 && _ <= 100.0}) : Float do
fn quantile(xs : {List(Float) | len(_) > 0}, q : {Float | _ >= 0.0 && _ <= 1.0}, method : QuantileMethod) : Float do
fn quantiles(xs : {List(Float) | len(_) > 0}, qs : List(Float), method : QuantileMethod) : List(Float) do
fn five_number_summary(xs : {List(Float) | len(_) > 0}, method : QuantileMethod) : (Float, Float, Float, Float, Float) do
fn variance(xs : {List(Float) | len(_) > 0}) : Float do
fn mode(xs : {List(Float) | len(_) > 0}) : Float do
```

`percentile`/`quantile` already carried a float-range precondition on their
second parameter (`p ∈ [0, 100]` / `q ∈ [0, 1]`) before this task; that
precondition was not touched. `quantiles`'s second parameter, `qs`, is a
plain unrefined `List(Float)` — a batch of quantile levels validated
per-element by a runtime `panic` inside `List.map`, not a type-level
precondition — so `quantiles` carries only the one `xs` precondition added
by this task, not two. `quantiles`/`five_number_summary` also take a
`method : QuantileMethod` parameter, unaffected either way.

## Two preconditions on one callee — confirmed to coexist, not just compile

`percentile`/`quantile` (NOT `quantiles` — see above) now carry two
independent precondition obligations per call site. Confirmed empirically
that BOTH discharge together (`--refine-report`, guarding both `xs` and `p`):

```
refinement obligations (user code): 2 proved, 0 violated, 0 trusted, 0 skipped
  by kind: 2 precondition, 0 postcondition, 0 division
```

and that guarding only ONE still errors, naming specifically the unguarded
one (not a generic message) — guarding `xs` but leaving `p` unconstrained:

```
`f` in `mod SPP` (declared `cap no_panic`) calls `Stats.percentile`, which can panic.
...
precondition `_ >= 0.0 && _ <= 100.0` on `Stats.percentile` was NOT verified here.
```

i.e. the two obligations are tracked and reported independently per refined
parameter, not folded into one "some precondition failed" verdict.

## A measurement trap that nearly produced a false "compiler bug" finding

The first `--refine-report` runs against the FULL, real stdlib (not the
minimal fixture stdlib the OCaml unit tests use) showed `percentile`/`quantile`
discharging cleanly but `quantiles`/`five_number_summary`/`variance`/`mode`
failing to record ANY obligation at their call site — "0 precondition, 0
proved" in user code, identical to a baseline empty module, on properly
guarded calls. This looked like a real, scale-dependent soundness gap (a
false-positive rejection of correct code, the plan's stated cardinal sin) and
was investigated at length: bisecting the stdlib manifest file-by-file, half
by half, checking for name collisions (`Variance` ADT constructor in
`dataframe.march`, `mode_int` in `compress.march`), tracing
`Panic_surface_by_proof`'s span-keyed verdict lookup and `Refine_check`'s
`resolve_call`/`collect_all_defs` machinery.

The actual cause: `dune build --root . bin/main.exe` (a *targeted* build) does
NOT restage `stdlib/*.march` into `_build/default/stdlib/` — a known trap
(`project_build_stdlib_missing_copies.md`). `bin/main.exe`'s stdlib resolution
is exe-relative and reads the STALE staged copy, which still had the
pre-edit, uncontracted signatures for four of the six functions. `diff
stdlib/stats.march _build/default/stdlib/stats.march` confirmed all six
signature lines differed. `percentile`/`quantile` still "worked" against the
stale copy only because their PRE-EXISTING p/q-range obligation (unaffected by
this task) happened to be the only one generated and it was trivially proved,
masking the fact that the (stale, absent) length obligation was never
generated at all. `variance`/`mode`/`quantiles`/`five_number_summary` have no
such second obligation to mask the gap, so the absence was visible.

Fix: `dune build --root . @test/cas-runtime-dir` (a target with a
`(source_tree ../stdlib)` dependency) restages it without doing a full
targetless build. Re-verified `diff` shows the staged copy identical to
source, then reran every fixture: all six now discharge for real. This is
recorded at length because it is exactly the kind of trap
`superpowers:verification-before-completion` and this repo's own memory exist
to catch, and because "no error" or "one clean compile" was not treated as
sufficient evidence anywhere in this investigation — every claim was checked
against a `--refine-report` obligation count, and the anomaly was chased to
its actual root cause rather than written up as a compiler bug on the first
plausible-looking symptom.

## TDD cycle

**RED** (`.march/cas/artifacts-v2`/`.march/cas/vc` cleared once beforehand,
`./_build/default/test/test_refinecheck.exe test no-panic-by-proof`, before any
stdlib/typecheck change): the 6 REJECT-control cases (one unguarded call per
function) all failed with `Expected: true, Received: false` — confirming these
six calls currently compile clean, unguarded, inside `cap no_panic` (the exact
coverage gap the brief describes). The 2 ACCEPT cases (`percentile`,
`variance`) passed trivially at this point — expected, since with no contract
and no covered-set entry there is nothing to check yet; this is why the
REJECT failures, not the ACCEPT passes, are what RED means here.

**Implementation:**
- `stdlib/stats.march` — six signatures updated (lines above).
- `lib/typecheck/typecheck.ml`'s `panic_surface_contracted` — added
  `"Stats.percentile"`, `"Stats.quantile"`, `"Stats.quantiles"`,
  `"Stats.five_number_summary"`, `"Stats.variance"`, `"Stats.mode"` alongside
  the existing `"Stats.mean"`/`"Stats.min_val"`/`"Stats.max_val"` entries. This
  is the ONLY list edited — `Panic_surface_by_proof.covered` is a structural
  alias of `panic_surface_contracted`, so disjointness from the syntactic ban
  lists holds automatically.

**GREEN** (after the stdlib-staging trap above was resolved):
`./_build/default/test/test_refinecheck.exe test no-panic-by-proof`: exit 0,
18 tests run, `Test Successful` (12 pre-existing + 6 REJECT + 2 ACCEPT added
by this task).

## Load-bearing mutation

Reverted only `variance`'s contract (`{List(Float) | len(_) > 0}` back to
plain `List(Float)`) via `Edit` (not `git stash`, per repo convention),
rebuilt with `dune build --root . @test/cas-runtime-dir` (restages stdlib),
and reran the `no-panic-by-proof` group: exactly one case flipped —
`"cap no_panic: a PROVABLY safe Stats.variance (guarded) compiles clean"`
(the ACCEPT case) failed with `Expected: false, Received: true` (an error is
now reported for the guarded call). This is the correct flip shape: `variance`
stayed in `panic_surface_contracted`, so with the contract gone there is no
obligation to record at that call site at all — fail-closed treats "no
obligation recorded" as an error, so the REJECT control (already expecting an
error) did not change, only the ACCEPT control did. Restored the contract,
rebuilt, reconfirmed all 18 cases green again.

## `--refine-report` positive discharge (genuine, not "no error")

Guarded fixture exercising four of the six together
(`percentile`/`variance`/`quantile`/`mode`, `/tmp/t6-nopanic-refine-report.march`):

```
refinement obligations (user code): 6 proved, 0 violated, 0 trusted, 0 skipped
  by kind: 6 precondition, 0 postcondition, 0 division
```

**6 proved, 0 violated** — percentile and quantile each contribute 2 (length +
range), variance and mode each contribute 1. Individually-verified solo
fixtures for all six functions each showed their own `N proved` line (recorded
in the task transcript); `quantiles` and `five_number_summary` each showed `1
proved, 0 violated` guarded by `List.length(xs) > 0` alone.

## Stdlib + ecosystem sweep, with a failure-capable positive control

Per the plan's Global Constraint that a byte-identical diff with no positive
control proves nothing, and that `bin/main.ml` filters diagnostics whose span
points into a stdlib file (so editing a stdlib file for the control produces a
false "no diff" — the trap the Task-1 audit already documented): the control
used a scratch fixture outside `stdlib/`, never a stdlib edit.

Built a "before" binary from the parent commit (`ad1f0517`, via an isolated
`git worktree add --detach`, no `git stash`) and compared it against the
"after" (this branch's) binary on the exact same unguarded fixture:

```
BEFORE (ad1f0517): --check on unguarded `Stats.variance` call -> exit 0, no diagnostics.
AFTER  (this branch): --check on the SAME fixture               -> exit 1, `Stats.variance ... which can panic.`
```

Exit 0 before, exit 1 after, same source, same command, different binary —
this is the failure-capable control demonstrating the check mechanism, not
merely a formatting difference. The temporary worktree was removed
(`git worktree remove --force`) after use.

`diff -rq` of `main.exe --check` output over every file in `stdlib/*.march`,
before vs. after (CAS cleared before each pass): no diff. This is a weak
check (per the known stdlib-diagnostic-filtering trap, most stdlib-internal
diagnostics never print at all), included for completeness alongside the
scratch-fixture control above, which is the one that actually exercises the
behavior change.

**`Stats.mean`/`Stats.min_val`/`Stats.max_val` are unchanged**: `git diff
stdlib/stats.march` shows exactly six changed lines (the six functions listed
above); `mean`/`min_val`/`max_val`'s signatures do not appear in the diff.
Their solo `--refine-report` fixture (`Stats.mean`, guarded) still shows `1
proved, 0 violated` after this task, same as it did independently before this
task touched anything.

## OCaml unit tests (`test/test_refinecheck.ml`)

Added a `stdlib_stats_mod` loader (mirrors `stdlib_random_mod`) and
`no_panic_errors_with_stats`/`has_no_panic_error_stats` (mirrors
`no_panic_errors_with_random`, prepending the REAL `stdlib/stats.march` as a
sibling `DMod` alongside `list.march` and prelude). Eight new cases appended
to the `no-panic-by-proof` group, per the brief's explicit asymmetry (six
REJECT controls — one per function, since each exercises that function's own
panic message and precondition wiring — but only two ACCEPT cases, since the
shared shape is proven once):

- ACCEPT: "a PROVABLY safe Stats.percentile (both preconditions guarded)
  compiles clean" — the two-refined-parameter case, both guards present.
- ACCEPT: "a PROVABLY safe Stats.variance (guarded) compiles clean" —
  single-parameter case; this is the one used for the load-bearing mutation.
- REJECT (6): unguarded `percentile`, `quantile`, `quantiles`,
  `five_number_summary`, `variance`, `mode` — each still errors.

`./_build/default/test/test_refinecheck.exe -e` (full binary, foreground,
CAS cleared once beforehand): exit 0, 513 tests run, `Test Successful`.

## Full suite (foreground, judged by `$?`)

- `run_compiler.exe -e`: exit 0.
- `run_eval.exe -e`: exit 0.
- `run_codegen.exe -e`: exit 0, 546 tests, `Test Successful`.
- `run_stdlib.exe -e`: exit 1, 1 failure of 830 — `adversarial-regressions #40
  MARCH_SANITIZE` (host-wide ASAN hang, independently confirmed by the
  controller as the only stdlib failure on this branch; unrelated files —
  the changed files here are `stdlib/stats.march` and
  `lib/typecheck/typecheck.ml`, neither touched by that regression test).
- `test_stdlib_march.exe -e`: exit 0, 56 tests, `Test Successful`.
- `test_refinecheck.exe -e`: exit 0, 513 tests, `Test Successful`.

`scripts/run-tests.sh` was deliberately NOT run by this task; the controller
runs the full suite independently per this plan's operating notes.

## Files changed

- `stdlib/stats.march` — six signatures (`percentile`, `quantile`,
  `quantiles`, `five_number_summary`, `variance`, `mode`) gain
  `xs : {List(Float) | len(_) > 0}`.
- `lib/typecheck/typecheck.ml` — six names added to
  `panic_surface_contracted`.
- `test/test_refinecheck.ml` — `stdlib_stats_mod`,
  `no_panic_errors_with_stats`, `has_no_panic_error_stats`, 8 cases in
  `no_panic_proof_suite`.
- `docs/capabilities.md`, `specs/lang/capabilities.md` — six names added to
  the contracted-names list; a new paragraph in each on the two-coexisting-
  preconditions behavior for `percentile`/`quantile` (NOT `quantiles`, whose
  `qs` parameter is unrefined — a review correction, see below).
- `CHANGELOG.md` — the six names added to the existing `### Changed` bullet's
  list of newly-proof-checked partials.
- This file.

## Review correction (post-commit)

An earlier version of this note and both doc copies incorrectly grouped
`Stats.quantiles` with `percentile`/`quantile` as a "two independent
preconditions" callee. `stdlib/stats.march:278`'s `quantiles` signature is
`(xs : {List(Float) | len(_) > 0}, qs : List(Float), method :
QuantileMethod)` — `qs` is a **plain, unrefined** `List(Float)` (a batch of
quantile levels validated per-element by a runtime `panic` inside
`List.map`, not a type-level precondition). `quantiles` therefore has exactly
ONE refined parameter, the `xs` length precondition added by this task, same
as `five_number_summary`/`variance`/`mode`. Re-verified in source that
`percentile`'s `p : {Float | _ >= 0.0 && _ <= 100.0}` and `quantile`'s
`q : {Float | _ >= 0.0 && _ <= 1.0}` ARE both still present exactly as
claimed — the drift was isolated to `quantiles` being wrongly lumped in with
those two, not a wider inaccuracy. Both doc copies and this note corrected to
remove `quantiles` from that callout; no code or test changes were needed
(the two-precondition ACCEPT test was already `percentile`-only, consistent
with the corrected claim).

## Carry-forward for later tasks in this plan

The `dune build --root . bin/main.exe` staging trap encountered during this
task's investigation (see above) is a standing hazard for any task in this
plan that measures behavior against a targeted build of `bin/main.exe`: a
*targeted* build does not restage `stdlib/*.march` into
`_build/default/stdlib/`, so `bin/main.exe --check`/`--refine-report` can
silently consult a stale, pre-edit stdlib copy after editing any
`stdlib/*.march` file and rebuilding only `bin/main.exe`. It produced a very
convincing false "compiler bug" signal here (4 of 6 functions appeared not to
discharge against the "full stdlib" when in fact the full stdlib being
consulted was stale). Fix: `dune build --root . @test/cas-runtime-dir` (a
target carrying a `(source_tree ../stdlib)` dependency) restages it cheaply,
without a full targetless build. Verify with
`diff stdlib/stats.march _build/default/stdlib/stats.march` (or the
equivalent file) before trusting any `bin/main.exe`-based measurement. Note
this trap does NOT affect the OCaml unit-test harness in
`test/test_refinecheck.ml` — `load_stdlib_march` there resolves
`stdlib/<name>` against the real repo-root source tree directly, never
through `_build/default/stdlib/`.
