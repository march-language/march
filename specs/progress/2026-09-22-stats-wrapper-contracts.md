# `Stats`: every non-empty requirement is declared in the signature

**Landed 2026-09-22.** Closes the `Stats` row of
`specs/todos/2026-09-16-refine-stdlib-wrapper-contracts.md` (the todo stays open
for the `seq`/`flow`/`gen` rows; `aho_corasick` is decided "no", recorded
there). Sized by `specs/progress/2026-09-16-refine-skip-census.md`.

## Decision

Repo owner, 2026-09-22: yes, for the whole `Stats` surface at once, shipped with
`--refine-suggest` as the migration path. It is a breaking change to public
signatures on purpose: an undeclared precondition is how
`DataFrame.col_describe`'s zero-row panic
(`2026-09-16-dataframe-col-describe-zero-rows.md`) got past the compiler.

## What changed

`stdlib/stats.march`, the five wrappers that forwarded to a contracted callee
without restating the contract (each was a census skip and a "propagates a
requirement it doesn't declare" warning when `stats.march` is checked directly):

| Function | Forwards to | Now declares |
|---|---|---|
| `median(xs)` | `percentile` | `xs : {List(Float) \| len(_) > 0}` |
| `quantile_default(xs, q)` | `quantile` | `xs` non-empty, `q : {Float \| _ >= 0.0 && _ <= 1.0}` |
| `iqr(xs, method)` | `quantiles` | `xs` non-empty |
| `iqr_default(xs)` | `iqr` (now contracted) | `xs` non-empty |
| `std_dev(xs)` | `variance` | `xs` non-empty |

`five_number_summary` already declared the contract but passed `sort_floats(xs)`
to `quantiles`; `sort_floats` has no length-preserving postcondition, so that
call could not be proved. It now queries the sorted list directly through the
private `quantile_sorted` (the same helper `quantiles` uses), which also drops a
redundant second sort. The rest of the surface (`mean`, `min_val`, `max_val`,
`percentile`, `quantile`, `quantiles`, `variance`, `mode`, and the `len(_) >= 2`
bivariate functions) was already declared. `sum`, `count`, `variance_pop`,
`std_dev_pop` and the `*_safe` wrappers accept any list and are unchanged; the
safe wrappers' `match xs do Nil -> Err(…) _ -> Ok(std_dev(xs)) end` shape proves.
Doc strings on each changed function state the precondition; the module header
names `--refine-suggest` as the migration path.

## Callers

Swept `stdlib/`, `test/`, `bench/`, `forge/`, `examples/`, `docs/` for the five
functions. One caller could not prove:

- **`DataFrame.eval_agg`'s `Median` arm** (`stdlib/dataframe.march`) passed
  `float_list(sub_df, col)` straight to `Stats.median`. Groups built by
  `apply_group_by` are non-empty, so no reachable panic is known, but nothing
  stated it. It now matches `Ok(Nil) -> NullVal` first, like `First`/`Last`
  already do for an empty frame; proved. New test: "group_by Median aggregates
  correctly" in `test/stdlib/test_dataframe.march`.
- `col_describe_column`, `col_z_score`, `col_normalize` (new `std_dev`/`median`
  obligations) are already guarded by `if List.length(xs) == 0` since the
  zero-row fix and **prove** under a normal entry (see the census caveat below).
- `examples/stats_basic.march`, `test/stdlib/test_stats.march`, `docs/examples.md`
  pass let-bound list literals: skipped in silence, the same as their existing
  `Stats.mean` calls; no error, no warning.

`share/march/` is a tracked, already-stale stdlib copy (its `stats.march` differed
from `stdlib/` before this change) and was not touched.

## Red, then green

Same compiler, old stdlib (`MARCH_STDLIB` = `git archive` of the pre-change tree)
vs new:

```
mod AppEmpty do
  fn empty_median() : Float do Stats.median([]) end
end
```
old: `--check` rc=0. new: rc=1,
`refinement violation: argument `xs` of `Stats.median` does not satisfy precondition `len(_) > 0``.

```
mod App do
  cap verified
  fn summarize(xs : List(Float)) : Float do Stats.median(xs) end
end
```
old: rc=0. new: ERROR "`summarize` propagates a requirement it doesn't declare",
with `help: fn summarize(xs : {List(Float) | len(_) > 0}) : Float`.
`--refine-suggest summarize` prints the same refinement ("discharges all 1
unproven obligation(s)"); with it applied, plus a `match`-guarded caller and a
literal caller, `--refine-report` says 3 proved, 0 skipped, rc=0. Without
`cap verified` the propagation is a WARNING.

## Census, before / after

`--check --refine-report-sites --refine-report`, `rm -rf .march/cas/vc
.march/cas/artifacts-v2` before each run.

**Neutral entry** (a one-function user module; this is how any real program
sees the stdlib): 52 → **46** skips, `unconstrained-subject` 33 → **27**,
proved 61 → **75**. `stats.march` wrapper skips 6 → **0**; no new non-`List.nth`
skip appears in `stats.march` or `dataframe.march`.

**`stdlib/list.march` as entry** (the original census's entry): 40 → **40**.
`stats.march` 6 → 0, but `dataframe.march` 16 → 22. That is an artifact of the
entry, not of the change: with `list.march` compiled as the *user* file, the
unit contains a user-defined `List.length`, and the `List.length` → `len` alias
is withdrawn for the whole compilation unit (the documented gate in
`specs/lang/refinement-types.md`, "Only while it is the standard library's
own"), so every `if List.length(xs) == 0` guard in `dataframe.march` looks
unconstrained (7 new `std_dev`/`median` obligations at already-guarded sites,
minus the fixed `Median` agg, which uses a `match` and proves either way). The
same 22 sites prove with `dataframe.march` or a neutral file as the entry.
**Future censuses should use a neutral entry**, not `stdlib/list.march`; the
2026-09-16 census's 16 `dataframe.march` rows were inflated the same way once
the zero-row guards landed.
