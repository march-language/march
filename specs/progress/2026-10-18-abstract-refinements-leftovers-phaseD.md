# Abstract refinements, the leftovers: phase D (the stdlib sweep)

**Date:** 2026-10-18
**Design:** `specs/2026-10-18-abstract-refinements-leftovers-design.md` §4.2, §6.4, §9.4, and the
user's decision 2 (rewrite `Enum.filter`, `Enum.take_while`, `Iterable.filter` and `Prelude.filter`)
**Base:** `72c1eb52a` (branch `claude/refinement-todos-73b0dc`: phases A–C, element-flow phase 3)

Stdlib, tests and docs only. No OCaml in `lib/` changed.

## What a user sees

| Program (design row) | Before | After |
|---|---|---|
| `sum_pos(filter(ys, fn y -> y > 0))`, a bare `filter` = `Prelude.filter` (B1) | `parametric-source-unproved` | **proved** |
| `sum_pos(Enum.filter(…))`, `sum_pos(Iterable.filter(…))` (B2) | 2 × `parametric-source-unproved` | **proved** |
| `one_pos(Enum.find(ys, fn y -> y > 0))`, the same with `Iterable.find` (E1) | `parametric-source-unproved` | **proved** |
| `sum_pos(Enum.take_while(ys, fn y -> y > 0))` (§9.4) | `parametric-source-unproved` | **proved** |
| `sum_pos(Range.filter(Range.new(0, n), fn y -> y > 0))` (R2) | `unreflectable-subject` | **proved** |
| any of the above with `fn y -> y >= 0` | the same skips | `abstract-refinement-too-weak` |

## Signatures and bodies

| Function | Signature after | Body | Definition side |
|---|---|---|---|
| `Enum.find` | `(xs : List(a), pred : a -> Bool[p]) : Option(a[p])` | unchanged (already natural) | 2 obligations, both proved |
| `Iterable.find` | the same | unchanged | 2, proved |
| `Enum.filter` | `(xs : List(a), pred : a -> Bool[p]) : List(a[p])` | `List.filter`'s natural body, copied (the module avoids `List`) | 3, proved |
| `Enum.take_while` | `(xs : List(a), pred : a -> Bool[p]) : List(a[p])` | `List.take_while`'s natural body, copied | 2, proved |
| `Iterable.filter` | `(xs : List(a), pred : a -> Bool[p]) : List(a[p])` | `List.filter`'s body, copied | 3, proved |
| `Prelude.filter` | `(xs : List(a), pred : a -> Bool[p]) : List(a[p])` | `List.filter`'s body, copied (the prelude does not depend on `List`) | 3, proved |
| `Range.filter` | `(r, f : Int -> Bool[p]) : List(Int[p])` | `filter_list(to_list(r), f)`, a private natural-style `pfn filter_list(xs : List(Int), f : Int -> Bool[p]) : List(Int[p])` (`List.filter`'s body over `Int`, a concrete base); see the follow-up below | 8, proved (with `filter_list`) |

Every contract is proved on the definition side; nothing is `@[assume]`d. Every recursive body
passes its own `pred` unchanged (phase C's own-predicate induction rule). `List.filter`'s
`subset(elts(_), elts(xs))` container refinement is not copied: the design asks for `List(a[p])`
only, and `elts` would be new vocabulary for these modules.

**Stack and speed.** The old `Enum.filter`, `Enum.take_while`, `Iterable.filter` and
`Prelude.filter` were O(1)-stack accumulators plus a reverse. The new bodies are `List.filter`'s
TRMC shape: the recursive call is the direct argument of `Cons` in tail position (or a plain tail
call on the rejecting branch), which compiles to a loop, so compiled stack stays O(1). Checked: a
5,000,000-element all-pass `Enum.filter`, `filter`, `Iterable.filter` and `Enum.take_while`
compiled at `--opt 2` run to completion. No accumulator helper was needed. The interpreter runs the
natural body recursively, exactly as it already did for `List.filter`; the 100,000-element runtime
tests below pass interpreted.

## Runtime tests (pinned on the OLD bodies first, all green there and after)

- `test/stdlib/test_enum.march`: `filter` order preserved, duplicates kept in place, empty, all
  pass, all fail, a 100k list; `find` returns the FIRST match, empty; new `take_while` block (stops
  at the first failure, empty, all pass, first fails, a 100k prefix); new `Range.filter` block
  (order, empty range, all pass, all fail).
- `test/stdlib/test_iterable.march`: `filter` duplicates in place, a 100k list (order, empty,
  all-pass and all-fail were already pinned).
- `test/stdlib/test_prelude.march`: `filter` order preserved, empty, all pass is the input, a 100k
  list.

Run with `march test FILE` (these three files are dune `runtest` rules, not part of
`test_stdlib_march.exe`): 480 / 527 / 475 passed on base and branch.

## Refinement tests (`test/test_refinecheck.ml`, group `abstract-leftovers-d`, 20 cases)

Each case checks the user module with the REAL `stdlib/list.march`, `enum.march`,
`iterable.march`, `range.march` beside it and `prelude.march` flattened in (as the driver does),
loaded relative to the cwd. Per function:

- **accept**: the caller's demand proved, the user module `(1, 0, 0)`, and the function's own
  definition side (its obligations by line range in its stdlib file) `(n, 0, 0)` with `n` above;
- **too-weak**: `fn y -> y >= 0` gives `abstract-refinement-too-weak`, user module `(0, 0, 1)`;
- **wrong body**: a copy with a bug in the user module (`bfilter` keeping rejected elements,
  `bfind` with its branches swapped, `btw` keeping the first failing element, `pfilter` with its
  branches swapped, `bifind` returning the head untested, `rfilter` delegating with
  `fn y -> true`): its return not all proved (a violation for all but `bifind`, whose untested
  `Some(h)` is an `unconstrained-subject` skip as in phase B's I3, and `rfilter`, too-weak), and
  the caller's demand recorded and not proved.

**RED on base**: the new test binary run from a `72c1eb52a` checkout's root (so it loads the base
stdlib): all 7 accept and all 7 too-weak cases FAIL (the demands are `parametric-source-unproved` /
`unreflectable-subject` there), the 6 wrong-body cases pass (they do not depend on the stdlib: they
are guards). GREEN on the branch.

**Conformance corpus.** `accept/t410_refine_abstract_stdlib_sweep` (B1, B2, E1, R2 and
`take_while` under `cap verified`; on the base it is rejected with 7 `refinement_unverified`
errors) and `reject/t411_refine_abstract_bare_filter_too_weak` (a bare `filter` with
`fn y -> y >= 0`, pinned on the too-weak text; on the base it is rejected for a different reason,
`parametric-source-unproved`, so the pinned text is RED there). `check_types.sh`: 468 passed, 0
failed. INDEX counts updated (198 accept, 270 reject).

## Verification

- `dune build --root . bin/main.exe test/test_refinecheck.exe test/run_compiler.exe
  test/test_stdlib_march.exe test/run_stdlib.exe`: ok.
- `./_build/default/test/test_refinecheck.exe -e` (VC cleared once): 1217 tests, 0 `[SKIP]`; the
  only two failures were the `audit-baseline` snapshots, regenerated (below), then green.
- `scripts/run-tests.sh -q compiler`: 1348 passed. `scripts/run-tests.sh -q stdlib`: 825 passed.
  `test_stdlib_march.exe -e`: 80 passed. `scripts/check-docs.sh`: passed.
- **Refine oracle** (baseline from a detached `72c1eb52a` worktree at the same depth, both with
  `_build/default/stdlib` absent, private HOME): 549 fixtures. Explained line by line:
  - 547 fixtures: `user + stdlib` **+16 proved**, skipped unchanged: the 16 definition-side proofs
    in the table above (3 + 2 + 2 + 3 + 2 + 3 + 1), precondition count +16 to match.
  - `stdlib_prelude`: +19 proved (the prelude is both the entry and the injected prelude, so its 3
    are counted twice), user `0 → 3` proved. Its pre-existing `overlapping_impl` errors move 8 lines
    down (the longer doc string); text otherwise identical.
  - `stdlib_enum` (user `0 → 7`), `stdlib_iterable` (`0 → 5`), `stdlib_range` (`2 → 3`): each
    module's own new proofs as the entry.
  - `stdlib_list`: +15 proved, **+1 skipped**: `range.march:89 return of filter p(_)`,
    `unreflectable-subject`. Only when `list.march` itself is the entry: the entry's declarations
    are flat and the stdlib `List` module is stripped (`bin/main.ml`, `entry_shadows_stdlib`), so
    `Range.filter`'s `List.filter(…)` resolves to no definition for the checker (the same reason the
    `List.nth` callers in `hamt`/`stats` record no obligation in that run). The obligation is new
    (base `Range.filter` had no element return); with any other entry it is proved (`stdlib_range`,
    the 547 fixtures, `t410`). Nothing moved from proved to skipped or violated.
  - New `non_tail_recursion` warnings, only where the module is itself the entry: `Enum.filter`,
    `Enum.take_while`, `Iterable.filter`, `Prelude.filter` (the TRMC shape `List.take_while` already
    warns with), and `List.filter` in `stdlib_list`. The last is a pre-existing blind spot now
    visible: the tail-call pass keys an entry-level function's call graph by bare name, the prelude
    is injected into the entry before the entry's own decls, and `List.assoc_opt "filter"` found the
    prelude's (then non-recursive) `filter` first, so `List.filter` was never checked. The warning
    text is correct for it. No user program sees either: stdlib spans are not user files.
- `stdlib/list.march` CI ratchet (`.github/workflows/ci.yml`, ceiling 42): **37 → 38** skipped
  (user + stdlib), proved 77 → 92, in this first commit. The +1 is the entry-configuration skip
  above. **Fixed by the second commit (37 again)**, see the follow-up below. Proved floor
  (`accept/t118`): 1, unchanged.
- `test/refine_audit` baselines regenerated: every fixture `145 → 166 enforced` (7 functions × 3
  sites: the `Bool[p]` domain and codomain and the return slot); `stdlib_enum` user `1 → 10`,
  `stdlib_iterable` `0 → 6`, `stdlib_range` `1 → 4`, `stdlib_prelude` `3 → 6` (`148 → 172`
  user + stdlib, counted twice as above). 0 unenforced everywhere but the holes fixture's
  deliberate 1.
- **Cold `--check`** (`--stdlib-source --refine-report stdlib/list.march`, private HOME rebuilt per
  run, VC cleared once, interleaved, load ~11): base 1.30 (cold) / 1.22 / 1.22 / 1.21 s, median
  **1.22 s**; branch 1.31 / 1.23 / 1.23 / 1.23 s, median **1.23 s** (101%, within 110%).
- **Runtime** (`--compile --opt 2`, 200k-element list ×50 per function, interleaved warm runs, 5
  each, load ~7-8), median ms base → branch: `Enum.filter` 72 → 44, `Prelude.filter` 69 → 44,
  `Iterable.filter` 69 → 43, `Enum.take_while` 85 → 59. Identical output. One pass instead of
  pass-plus-reverse. `bench/list_ops.march` compiled: output identical (`333333666666`), 0.02 s on
  both.
- Ecosystem repos (`conduit`, `depot`): not re-run.

## Follow-up (second commit): `Range.filter` no longer delegates

The first commit kept `Range.filter` as `List.filter(to_list(r), f)` (the design's route 2). That
raised the `stdlib/list.march` CI skip ratchet from 37 to 38: with `list.march` as the entry the
stdlib `List` is stripped and the call resolves to no definition, so the new return obligation was
an `unreflectable-subject` skip there (proved everywhere else). Decision (coordinator): keep the
ratchet non-increasing. `Range.filter` now calls a private `pfn filter_list(xs : List(Int),
f : Int -> Bool[p]) : List(Int[p])` in the same module, `List.filter`'s natural TRMC body over
`Int`, recursing with its own `f` unchanged. A same-module call resolves in every configuration.

- `stdlib/list.march` ratchet: **37 skipped** (user + stdlib), 100 proved (base 77 / 37).
- `stdlib/range.march` as the entry: 10 proved, 0 skipped (user code).
- `abstract-leftovers-d`, 21 cases: the Range accept now pins the definition side at `(8, 0, 0)`
  (`filter`'s tail plus `filter_list`'s pushes and tails); RED against the first commit's stdlib,
  where it was `(1, 0, 0)` (exactly that case fails, the other 20 pass). New wrong-body case: a
  `filter_list` copy that keeps rejected elements, a violation, and its caller not proved. The
  wrong-delegation (`fn y -> true`) case is kept.
- Runtime: the `Range.filter` block in `test_enum.march` (order, empty range, all pass, all fail)
  passes on both.
- `test/refine_audit` baselines: every fixture `166 → 169 enforced` (`filter_list`'s domain,
  codomain and return slot), `stdlib_range` user `4 → 7`, `stdlib_prelude` `172 → 175`;
  0 unenforced but the holes fixture's deliberate 1.
- `check_types.sh`: 468 passed.
- Compiled `Range.filter` (`Range.new(0, 200000)` filtered ×50, 7 interleaved warm runs, load
  30-40, so noisy), median ms: base `72c1eb52a` 151, branch 157; the first commit's delegating
  version measured 156 vs the branch's 157 in a separate interleaved run. Parity within the noise:
  the same single-pass loop either way. A 5,000,000-element all-pass `Range.filter` completes
  compiled. Identical output.
- The refine oracle was not re-run for this commit; its section above describes the first.

## Still open

Phase E of the design (`Within` field roles, `Deque.filter`), and the String-callback todo from
phase B. Deliberately not carrying `p` (design §4.2): `drop_while` (`List`, `Enum`), `filter_map`,
`find_index`, `any`/`all`, `Gen`/`Seq`/`Flow` filters, the two-argument `Map` filters.
