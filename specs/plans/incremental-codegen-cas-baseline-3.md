# Compile-time baseline 3 (B0 re-run), 2026-11-24

The third dated snapshot for `specs/plans/incremental-codegen-cas-plan.md` §13 (B0), taken
during the plan's 2026-11-24 status review to check whether criterion 1 still holds seven
weeks after `incremental-codegen-cas-baseline-2.md`. Scope is narrower than baseline 2: the
topology corpus at `--opt 2` only, which is the cell criterion 1 reads. Don't edit these numbers
in place; re-run `scripts/compile-time-bench.sh` and write a new dated file.

## Verdict on criterion 1: **still passes**, essentially unchanged

| topology, `--opt 2`, median of 3 | 2026-10-07 (baseline 2) | 2026-11-24 (this) |
|---|---|---|
| leaf edit, wall | 14.5 s | 15.7 s |
| leaf edit, back end (`llvm-emit` + `clang`) | 11.1 s | 11.2 s |
| leaf edit, back end share of wall | 76% | 71% |
| leaf edit, whole-program TIR bucket | — | 3.2 s |
| leaf edit, front end | — | 1.1 s |
| comment edit (post-TIR hit) | — | 5.9 s |
| warm, no change (source-level hit) | — | 0.15 s |
| cold (fresh `HOME` and project) | — | 37.1 s |

The back end hasn't moved. The ~1.2 s of extra wall time is in the front end and whole-program
TIR buckets. That's consistent with the ocap work since October, for example
`specs/todos/2026-11-19-ocap-authority-mono-compile-cost.md` (every compile monomorphizes ~100
`Authority` functions and then drops them), but this run doesn't attribute it. Both thresholds
are still cleared: over ~10 s, and back end over 60%.

`sig` and `field` are `n/a` for topology, as in baseline 2: the harness has no safe edit recipe
for that program.

## Conditions

- **Date:** 2026-11-24, ~11:15–11:45 EST.
- **Machine:** the same as baselines 1 and 2 (Apple M3 Max, 14 cores, macOS 26 / Darwin 25.6.0),
  Apple clang 17.0.0 (clang-1700.6.4.2).
- **Compiler:** `11cdf717a` (`main` at the branch point). The branch changes no compiler source.
- **Load:** 1-minute load average 5.5 at the start, 9–15 during the run (other sessions were
  active). That's lighter than baseline 2's 11.6–22.4. The first leaf run (20.7 s wall, back end
  14.9 s) caught a load spike. The median excludes it, and the other two runs agree within 0.4 s.
- **Rows:** `bench/results/2026-11-24-compile-time-arm64-opt2.tsv`.
- **Command:** `scripts/compile-time-bench.sh --opt 2 --corpus topology`.
