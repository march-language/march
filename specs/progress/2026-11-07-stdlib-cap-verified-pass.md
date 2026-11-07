# `cap verified` pass over List, Option, Result and Math (2026-11-07)

A stdlib module's `cap verified` is a claim that every refinement obligation and lemma in it is
proved. Only `Udp` made it, and nothing enforced it (stdlib diagnostics are filtered out of user
builds).

## Measured

| Module | In an ordinary program (`--refine-report-sites=all` rows in the file) | As its own entry with `cap verified` added (`--check --stdlib-source`) |
|---|---|---|
| Math | 7 proved, 0 skipped | clean |
| Option | 1 proved, 0 skipped | clean |
| Result | no obligations | clean |
| List | 37 proved, 28 trusted (manifest-admitted lemmas), 0 skipped | fails: `reverse` ambiguous with `Prelude.reverse` when List is the entry (4 `invalid_lemma`, 7 `lemma_unproved`, 9 unreflectable sites), and `task_spawn` needs `IO.Spawn` |

## What changed

- `stdlib/math.march`, `stdlib/option.march`, `stdlib/result.march` declare `cap verified`.
- `reflect-stdlib-sweep` gains two cases: the expected set of `cap verified` stdlib modules
  (Math, Option, Result, Udp), and "every `cap verified` stdlib module checks clean as its own
  entry": its user-code summary shows 0 violated and 0 skipped, and no refinement, lemma or
  termination error appears. Shown to fail on a scratch copy of `math.march` with a false
  postcondition added (`7 proved, 1 violated`). This also enforces `Udp`'s claim for the first time.
- List's two blockers are `specs/todos/2026-11-07-stdlib-list-cap-verified.md`.

## Verification

| Check | Result |
|---|---|
| the two new cases | RED (Math/Option/Result not declared) → GREEN |
| `audit-baseline` | unchanged |
| `scripts/affected.sh --run --full` | see the PR |
