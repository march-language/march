# `unreflectable-predicate` is mostly a misattributed subject failure (filed 2026-09-02, landed 2026-09-03)

Design: `specs/2026-09-02-unreflectable-predicate-attribution-design.md`.
Plan: `specs/plans/2026-09-02-unreflectable-predicate-attribution-plan.md`.
Commits: `082d5bf5`, `9a985302`, `33b942c8`, `bd9b8339`, `4bddf8cb`, `b4583fef`,
`17aaf225`, and this record.

**Original open item, kept verbatim:**

> `[P2]` `unreflectable-predicate` is mostly a misattributed subject failure (filed 2026-09-02)
>
> All 11 user-code `unreflectable-predicate` skips have predicates inside the
> supported fragment. Seven are arithmetic actuals (`n - 1`, `i + 1`) that
> `reflect_scalar` routes through a path whose variable resolver is hard-coded
> to `None`; four are opaque-call actuals. Zero are genuine predicate failures.
>
> Design: `specs/2026-09-02-unreflectable-predicate-attribution-design.md`.
> Reflect arithmetic actuals, file failed scalar subjects under
> `unreflectable-subject` naming the actual, and name the failing
> sub-expression for real predicate failures via an `smt_of_r` wrapper.
>
> ## Noted during implementation (2026-09-03)
>
> - An opaque actual for a sibling parameter (`at(i, lane(4))` against `{Int | _ < n}`) is still filed as `unreflectable-predicate`; only the self binder is consulted. Out of the design scope. Task 4 must count it in the sweep rather than claim the bucket is empty.
> - The unreflectable-subject rule as built: the subject is blamed when the predicate consulted the bare binder and that reflection failed. A predicate that never reaches a bare binder (only a measure over it, or an opaque call over it) still blames the predicate even when the subject is also opaque. The docs must state this in one sentence.

## What shipped

Three independent parts, matching the design exactly:

1. **`reflect_scalar` reflects arithmetic actuals** (`lib/refinecheck/refine_resolve.ml`).
   `EApp (EVar ("+" | "-"), [a; b])` and `*` with one integer-literal operand
   recursively reflect their operands through the same function, so `n - 1`
   under a guard on `n` carries that guard instead of falling to `plain`'s
   hard-coded `None` variable resolver. Guarded to `~sort:SInt` only (fix
   loop 1: the arms are otherwise numeric-polymorphic and would reach Float
   arithmetic, which the design explicitly excludes).
2. **A failed scalar subject files `Unreflectable_subject`, naming the actual**
   (`lib/refinecheck/obligation.ml`, `refine_call.ml`). Decided after the
   predicate's own reflection has already run, by reading the memo
   (`reflect_cache["$self"]` for Int/Bool/ADT, `str_reflected["$self"]` for
   String, added in fix loop 1) rather than forcing a second, eager
   reflection; the eager version the design's own Step 3 text described
   broke 4 of 16 `tier2-induction` fixtures by forcing work (and a failure)
   that would not otherwise happen. When the payload would otherwise be the
   `<predicate>` placeholder (an actual `pred_str` cannot render as source
   syntax), fix loop 1 falls back to the declared parameter name instead.
3. **`smt_of_r` names the failing sub-expression of a genuine predicate
   failure** (`lib/refinecheck/refine_scope.ml`, `obligation.ml`,
   `refine_call.ml`, `refine_post.ml`). A `(Smt.term, A.expr) result`-returning
   twin of `smt_of`; a leaf failure's `Error` carries the leaf, a recursive
   arm's `Error` propagates the child's unchanged. `smt_of` is now
   `Result.to_option (smt_of_r ...)`, so its 18 pre-existing callers are
   unaffected. The two `refine_post.ml` sites with no sub-expression in hand
   (the postcondition's own return expression failing to reflect) were
   changed in fix loop 1 to file `Unreflectable_subject` naming the return
   expression, not `Unreflectable_predicate` naming the whole predicate; the
   postcondition analogue of part 2's subject rule, added after the Task 3
   reviewer showed the brief's original text ("name the whole predicate
   there") produced a false statement whenever the predicate itself was
   perfectly reflectable and only the tail was not.

Both `Unreflectable_predicate` and `Unreflectable_subject` moved from the
once-per-module throttle to the per-site diagnosed set, since their messages
now name a specific sub-expression or argument rather than saying the same
thing everywhere.

## The subject-blame rule, as built

A call's actual argument (or, for a postcondition, the function's own return
expression) is reflected first. If that reflection fails, the whole
obligation is filed as `unreflectable-subject` naming the actual, and the
predicate is never reached. Only when the subject reflects fine does a
further failure file as `unreflectable-predicate`, naming the innermost
failing leaf.

Two known gaps, both out of this design's scope and left as follow-ups:

- **A predicate that never reaches the bare subject at all** (only a measure
  over it, or an opaque call over it) still blames the predicate when the
  predicate is itself unreflectable, even though the subject may also be
  opaque. Distinguishing the two would need reflecting the subject
  speculatively, which risks the same induction hazard fix loop 1 in Task 2
  found and worked around.
- **A sibling parameter's actual** (an opaque or unreflectable argument for a
  parameter the predicate mentions by name, not the refined parameter's own
  subject, e.g. `at(i, lane(4))` against `{Int | _ < n}`) is not covered;
  only the self binder is consulted. Still files `unreflectable-predicate`.

## Corpus sweep, measured

Baseline compiler built from `271d259c` (the plan's start commit, not the
merge-base with `origin/main`) in a throwaway worktree
(`git worktree add <scratch>/base-271d259c 271d259c`). Both sweeps ran under
a private `HOME`, `.march/cas/artifacts-v2` and `.march/cas/vc` cleared once
before each, over the same 300 entry files (`stdlib/*.march`, 117 files, and
`test/native/*.march`, 183 files, `git diff --stat 271d259c HEAD -- stdlib/
test/native/` is empty, so both sweeps ran the identical corpus). One
foreground process per sweep.

**`user code` slice (clean, one obligation counted once):**

| bucket | before (271d259c) | after (17aaf225) | delta |
|---|---:|---:|---:|
| proved | 96 | 96 | 0 |
| violated | 4 | 4 | 0 |
| trusted | 0 | 0 | 0 |
| `unconstrained-subject` | 40 | 40 | 0 |
| `unreflectable-predicate` | **11** | **0** | −11 |
| `unreflectable-subject` | 0 | **4** | +4 |
| `solver-undecided` | 8 | **13** | +5 |
| `partial-conjunct` | 6 | **8** | +2 |
| total skipped | 65 | 65 | 0 |

**`user + stdlib` slice (inflated, every entry file re-counts every stdlib
obligation it pulls in; included only to show the same shape at scale):**

| bucket | before | after | delta |
|---|---:|---:|---:|
| proved | 5768 | 5768 | 0 |
| violated | 4 | 4 | 0 |
| `unconstrained-subject` | 13165 | 13165 | 0 |
| `unreflectable-predicate` | 2993 | 0 | −2993 |
| `unreflectable-subject` | 0 | 898 | +898 |
| `solver-undecided` | 306 | 1802 | +1496 |
| `partial-conjunct` | 1794 | 2393 | +599 |
| total skipped | 18258 | 18258 | 0 |

**The plan's prediction (11 to 0, 7 via Task 1, 4 via Task 2) is confirmed
exactly**, with one wording correction: the design's own text hedged this as
"become proved, violated, or a diagnosed skip", and the real outcome is the
diagnosed-skip branch for all 7, none of the 7 arithmetic sites became a new
`proved` or `violated` (those totals are unchanged, 96 and 4), all 7 moved to
`solver-undecided` (5) or `partial-conjunct` (2). This is not a wrong
prediction; it is the outcome the design's own hedge anticipated, stated
precisely instead of loosely. `unconstrained-subject` and `proved`/`violated`
are untouched, and `total skipped` for the user-code slice is unchanged at 65
(11 obligations changed bucket, none left or entered the skipped set).

### Per-site accounting: all 11 before-run `unreflectable-predicate` sites

Each row's "new slug" was read directly from the after-sweep report (either
the per-site HINT text for a newly-diagnosed reason, or the bucket-count
delta for a still-throttled one); the count-delta arithmetic in the table
above closes exactly against this list, which is the proof that every site
is accounted for and none is double-counted.

| site | shape | new slug | moved by |
|---|---|---|---|
| `decimal.march:175` (`round(div(a, b, precision + 1), precision)`) | arithmetic actual (`precision + 1`) | `solver-undecided` | Task 1 |
| `list.march:144` (`nth(t, n - 1)`) | arithmetic actual (`n - 1`) | `partial-conjunct` | Task 1 |
| `stats.march:81` (`List.nth(sorted, i + 1)`) | arithmetic actual (`i + 1`) | `solver-undecided` | Task 1 |
| `stats.march:130` (`List.nth(sorted, i + 1)`, `linear_interp`) | arithmetic actual (`i + 1`) | `solver-undecided` | Task 1 |
| `stats.march:137` (`List.nth(sorted, i + 1)`, quantile interpolation) | arithmetic actual (`i + 1`) | `solver-undecided` | Task 1 |
| `stats.march:209` (`let b = List.nth(sorted, i + 1)`) | arithmetic actual (`i + 1`) | `partial-conjunct` | Task 1 |
| `stats.march:323` (`let hi = List.nth(sorted, n - 1)`) | arithmetic actual (`n - 1`) | `solver-undecided` | Task 1 |
| `simd_lane_panic.march:25` (`Simd.extract_i32x4(v, lane(1))`) | opaque call actual (`lane(1)`) | `unreflectable-subject` (names `lane(1)`) | Task 2 |
| `stats.march:191` (`List.nth(sorted, clamp_idx(idx, n))`) | opaque call actual (`clamp_idx(idx, n)`) | `unreflectable-subject` (names `clamp_idx(idx, n)`) | Task 2 |
| `stats.march:213` (`List.nth(sorted, clamp_idx(fl, n))`) | opaque call actual (`clamp_idx(fl, n)`) | `unreflectable-subject` (names `clamp_idx(fl, n)`) | Task 2 |
| `stats.march:222` (`List.nth(sorted, clamp_idx(j, n))`) | opaque call actual (`clamp_idx(j, n)`) | `unreflectable-subject` (names `clamp_idx(j, n)`) | Task 2 |

7 arithmetic sites (Task 1: 5 → `solver-undecided`, 2 → `partial-conjunct`) +
4 opaque-call sites (Task 2: 4 → `unreflectable-subject`) = 11. Zero sites
remain `unreflectable-predicate` in the user-code slice on this corpus; the
bucket is genuinely empty here, not merely unmeasured; the two known gaps
above (predicate never reaches the bare subject; sibling-parameter actuals)
are real limitations but do not happen to be exercised by this corpus.

## Oracle: proven RED, then a fully classified diff

`scripts/refine-oracle.sh baseline <scratch>/oracle` run from the
`271d259c` worktree: **6562 report lines over 300 fixtures**. `check` run
from this worktree at HEAD.

- **RED proof, run first.** `s/was NOT verified here\./was NOT verified
  HERE./` in `lib/refinecheck/refine_call.ml`, rebuilt, checked: **1964
  differing lines**. Reverted (`cp` round-trip back to the pre-perturbation
  file; `git diff --stat` empty), rebuilt.
- **Real check: 1858 differing lines** (`refine_call.ml` restored, `git
  status --short` clean before this run).

**Classification of all 1858 moved lines**, computed by extracting every
unique added/removed line's content (stripped of its per-fixture tag) and
matching each against the known re-attribution shapes:

| category | lines | what it is |
|---|---:|---|
| Re-attribution of a before-run `unreflectable-predicate` site | **1858** | bucket-count deltas (`skipped (unreflectable-predicate): N` removed; `skipped (partial-conjunct\|solver-undecided\|unreflectable-subject): N` added, repeated once per entry file that transitively imports `decimal`/`list`/`stats`/`simd_lane_panic`), the removed `reason: unreflectable-predicate — the predicate uses vocabulary...` / `note:` boilerplate at the throttled representative site, the added `reason: solver-undecided ...` / `` `_ >= 0` established here; `_ < len(xs)` not `` / `` the argument `X` could not be translated to SMT `` replacement text, four newly-shown `-- HINT --` blocks (headers, span lines, carets) for the sites that moved from throttled to per-site reporting, and their surrounding blank lines |
| New proof from Task 1 | **0** | `proved` is unchanged at 96 (user code) / 5768 (user + stdlib) corpus-wide; none of the 7 arithmetic sites happened to become provable on this corpus, only diagnosable |
| Detail-text change from Task 2 or 3 unrelated to the 11 sites | **0** | no corpus predicate contains `/`, `%`, or a string literal in a position `pred_str` would render (`grep -c '<predicate>' refine.diff` = 0), so the `pred_str` wording improvements from Task 3 (finding 4 of the Task 3 review) are real but corpus-invisible |
| unclassifiable | **0** |, |

100% of the diff is re-attribution of one of the 11 sites in the table
above; there is no unclassifiable line, so the oracle's move is fully
explained.

## Gates

Run in this worktree at HEAD (`17aaf225` plus the docs/obligation.ml changes
in this commit), one foreground process per suite, `.march/cas/vc` cleared
before the z3-backed suite.

`scripts/run-tests.sh` itself timed out twice at the tool's 600000ms
foreground limit while another, unrelated worktree on the same machine
(`mystifying-kirch-9fca5f`) was concurrently running its own full test suite
and compiling native binaries (`ps aux` showed its `bin/main.exe --compile`
and `clang` invocations consuming most of a CPU core the whole time, load
average 5.8-7.5 on an otherwise idle box). Rather than retry a script whose
internal `dune shutdown` step interacts with a shared dune RPC daemon under
that contention, the twelve suites `run-tests.sh` would have run were built
once and invoked directly as binaries (the script's own documented method 2),
each within its own foreground call:

| suite | result |
|---|---|
| `run_compiler.exe -e` | 973 tests run, Test Successful, 107.2s |
| `run_eval.exe -e` | 273 tests run, Test Successful, 0.9s |
| `run_codegen.exe -e` | 593 tests run, Test Successful, 316.6s (1 tool-skip: no cross-arch sysroot, pre-existing) |
| `run_stdlib.exe -e` | 878 tests run, Test Successful, 147.8s |
| `test_stdlib_march.exe -e` | 61 tests run, Test Successful, 6.7s |
| `test_jit.exe -e` (MARCH_BIN set) | 24 tests run, Test Successful, 34.6s |
| `lsp/test/test_lsp.exe -e` | 354 tests run, Test Successful, 27.8s |
| `lsp/test/test_utf16.exe -e` | 5 tests run, Test Successful, 0.001s |
| `lsp/test/test_jsonrpc.exe -e` | 36 tests run, Test Successful, 11.0s |
| `lsp/test/test_incremental.exe -e` | 10 tests run, Test Successful, 1.2s |
| `lsp/test/test_query_cli.exe -e` | 7 tests run, Test Successful, 1.3s |
| `test/test_refinecheck.exe -e` (z3 on PATH, `.march/cas/vc` cleared first) | **621 tests run, Test Successful, 270.7s** (matches Task 3's final count exactly) |

All twelve green, 0 failures. `dune build --root . @types-check --force`:
log ends `=== core-march-types: 303 passed, 0 failed ===`, exit 0
(non-vacuous, the pass count printed, not a zero-byte log).
`dune build --root . @grammar-check --force`: log ends
`=== grammar: 48 passed, 0 failed ===`, exit 0. `scripts/check-docs.sh`:
`doc-lint passed` (checks A, B, C all ok), run again after the doc edits in
this commit to confirm they introduced no stale pointer or count.

## Cost

Cold `--check` on three representative corpus files, three runs each,
`.march/cas/artifacts-v2` and `.march/cas/vc` cleared before every run,
median of the three reported:

| file | before (271d259c) median | after (17aaf225) median | delta |
|---|---:|---:|---:|
| `stdlib/stats.march` | 1.309s | 1.345s | +2.7% |
| `stdlib/list.march` | 1.184s | 1.178s | −0.5% |
| `test/native/simd_lane_panic.march` | 0.318s | 0.310s | −2.5% |

All three within 5%; no slowdown finding. (The three-run spread for
`simd_lane_panic.march` includes one cold-`HOME` outlier per file group,
~1.3s for the first of three runs sharing a `HOME`, populating the
`~/.cache/march` stdlib blob; the median is unaffected by it either way.)

## Deferred items

- **Sibling-parameter actuals** (noted during implementation, kept above)
  still file `unreflectable-predicate`; only the self binder is consulted.
  Not exercised by this corpus's 11 sites (verified above, all 11 are
  accounted for without it), so it does not change this measurement, but it
  is a real gap in the subject-blame rule.
- **`{String | ...}` return refinements are checked by nothing**, a
  separate, more severe hole (zero obligations filed, not a skip), found
  while implementing Task 3 and confirmed by its reviewer. Filed as
  `specs/todos/2026-09-03-string-return-refinement-unchecked.md` with a
  minimal reproducer, root cause, and a candidate fix location.
