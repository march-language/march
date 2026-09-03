# Refinement precision: `let` equalities and nested-pattern facts (filed 2026-09-02, landed 2026-09-02)

Design: `specs/2026-09-02-refinement-precision-lets-and-arms-design.md`.
Commits: `211b501c`, `40c51d1d`, `f1801a38`, and this record.

**Original open item, kept verbatim:**

> `[P2]` Refinement precision: `let` equalities and nested-pattern facts (filed 2026-09-02)
>
> Two facts the checker never derives, left out of scope by the 2026-09-01
> diagnosis split: a `let` with a literal or arithmetic right-hand side records
> nothing, and a binder inside a constructor pattern (`t` in `Cons(_, t)`)
> receives no fact even when a previous arm excludes the only other shape.
> `stdlib/list.march:128` (`last`'s recursive call) is the flagship case.
>
> Design: `specs/2026-09-02-refinement-precision-lets-and-arms-design.md`.
> Corpus payoff is small and stated in the design; do not oversell it.

## What shipped

Two facts, each one push into an existing channel; no new channel and no new
solver query.

**(1) A `let`'s literal or arithmetic value, as a path equality.**
`Refine_scope.let_equality_rhs` (`lib/refinecheck/refine_scope.ml`, §10, beside
`launder`) admits an integer literal, a bare variable, `+`/`-` over two admitted
shapes, and `*` with exactly one integer-literal operand. Calls, `if` and floats
are excluded. `refine_check.ml`'s block fold, `A.ELet` arm only (line ~245),
retires facts about the bound names as before and then pushes `n == rhs` onto
`path` as an ordinary non-negated user fact. So `let n = 0` followed by
`Enum.chunk_every(xs, n)` is now the same definite violation the literal call
already was.

**(2) A nullary sibling sub-pattern excluded by an earlier arm, over the later
arm's binder.** `Refine_scope.arm_excludes_nested : A.branch -> (string * int *
string) option` returns `Some (ctor, i, d)` for an unguarded arm with head
`ctor` whose sub-patterns are all irrefutable except exactly one nullary
`PatCon d` at index `i`. `refine_check.ml`'s `EMatch` arm fold (line ~490) adds
a third derivation of `p`, after the two existing exclusion folds and after the
current arm's own binders have been shadowed: when an earlier arm gives
`(ctor, i, d)`, this arm's head is `ctor`, `sort_of_ctor d` is known, and this
arm's sub-pattern at `i` is a bare `PatVar t`, it pushes `(is_d(t), true)`, the
same negated-tester shape the scrutinee-level exclusion uses, aimed at the
binder. `path_resolve_tester` in `refine_call.ml` already bridges `not is_Nil(t)`
to `len(t) > 0` for a bare variable, so no code in `refine_call.ml` changed.

Commits: `211b501c` (1), `40c51d1d` (2), `f1801a38` (test hardening), plus this
record.

## Two deviations from the approved design, both simplifications

Both were found while planning, before implementation, and are recorded in the
design doc's "Corrections made while planning" paragraph.

- **Design A proposed a new `lets_eq` channel on `call_ctx`**, with entries
  reflected at `check_call`. Shipped instead as an ordinary **path fact**. The
  path translator already reflects arithmetic over variables, `path_shadow`
  already retires a fact when the bound name or any name the right-hand side
  mentions rebinds, and the fact reaches `Undecided.diagnose` through
  `push_user` without further work. Three construction sites of `call_ctx` were
  therefore not touched.
- **Design B proposed three pieces**: a binder-to-selector alias map, an
  exclusion phrased as `not is_d(<ctor>_<i>(s))` over that selector, and an
  extension of `path_resolve_tester` to accept a selector application. Shipped
  instead as **one piece**: the exclusion is phrased directly over the later
  arm's binder `t`, which the existing bare-variable bridge already handles. No
  alias map, no selector spelling, no bridge extension.

## Corpus sweep, measured

Baseline compiler built from `7549ea9f` in a throwaway worktree. Note this is
**not** the merge-base with `origin/main`: the branch stacks on an unmerged PR
whose own diagnostic changes would swamp the diff. Both sweeps ran under a
private `HOME`, with `.march/cas/artifacts-v2` and `.march/cas/vc` cleared once
before each, over the same 299 files (`stdlib/*.march` and
`test/native/*.march`), one foreground process.

The report prints two blocks per file that share a line format. They are summed
separately below. The `user code` block is the clean number; the
`user + stdlib` block re-counts every stdlib obligation once per file, so its
totals are inflated by a factor of the corpus size and are useful only as a
consistency check.

**`user code` (clean):**

| bucket | before | after |
|---|---|---|
| proved | 95 | 96 |
| violated | 4 | 4 |
| trusted | 0 | 0 |
| skipped | 66 | 65 |

Skip causes, `user code`: `unconstrained-subject` 41 to 40;
`unreflectable-predicate` 11, `partial-conjunct` 6, `solver-undecided` 8, all
unchanged.

**`user + stdlib` (inflated, 299 re-counts of the same stdlib obligations):**

| bucket | before | after |
|---|---|---|
| proved | 5450 | 5749 |
| violated | 4 | 4 |
| trusted | 0 | 0 |
| skipped | 18496 | 18197 |

Skip causes there: `unconstrained-subject` 13420 to 13121; the other three
unchanged. The delta is exactly `+1 proved, -1 skipped` in **every one** of the
299 files, which is what a single stdlib obligation changing bucket looks like
when each file re-counts the whole stdlib.

**Every obligation that moved, in full:**

| site | before | after | explained by |
|---|---|---|---|
| `stdlib/list.march:128`, `Cons(_, t) -> last(t)` | skipped (unconstrained-subject) | proved | (2) |

That is the whole list: one site, corpus-wide. No skip changed to another skip
cause, and no obligation moved in either direction other than this one. Its
HINT ("precondition `len(_) > 0` on `last` was NOT verified here / no fact the
checker derived constrains `t`") is gone from the report.

**Improvement (1) moves nothing in this corpus,** exactly as the design
predicted: over `stdlib/list.march`'s six user-code skips none is a `let` with a
literal or arithmetic right-hand side (four are `let t = pmap_threshold()`, an
unrefined builtin return, and `let csize2 = if ... end`, neither of which this
work reaches). Its value is generality, and it is exercised by the
`let-equality` tests rather than by the corpus. Do not sell it as a corpus win.

Beyond the refinement blocks, the only other text difference across the 299
outputs was the absolute worktree path printed inside `stdlib/prelude.march`'s
pre-existing overlapping-implementation error, which is a property of where the
compiler was built and not of the checker.

## Oracle: proven RED, then a fully classified diff

`scripts/refine-oracle.sh` over the same 299 fixtures, baseline recorded from
the `7549ea9f` worktree: **6567 report lines**.

- **RED proof, run first.** In this worktree, `refine_call.ml`'s call-site
  verdict `| Refine.Verified -> note Obligation.Proved` was changed to
  `note Obligation.Trusted`, rebuilt, and checked: the oracle reported a
  difference of **631 removed and 621 added** lines. It detects a verdict change
  on this corpus. The perturbation was reverted with `git checkout
  lib/refinecheck/refine_call.ml` and the compiler rebuilt before the real run.
- **Real check: 610 removed, 600 added.** Every line falls into one of four
  categories, and the categories account for the totals exactly:

| lines | category |
|---|---|
| 299 removed / 299 added | `refinement obligations (user + stdlib)` summary lines, one per fixture, each `+1 proved, -1 skipped`, report counts reflecting the one newly proved obligation |
| 300 removed / 300 added | `skipped (unconstrained-subject): N` lines, each down by one: 299 `user + stdlib` blocks plus `stdlib_list`'s own `user code` block |
| 1 removed / 1 added | `stdlib_list`'s `user code` summary, `0 proved, 6 skipped` to `1 proved, 5 skipped` |
| 10 removed / 0 added | the `stdlib/list.march:128` HINT block (header, two message lines, source line, caret, blanks), gone because the obligation is now proved |

610 = 299 + 300 + 1 + 10 and 600 = 299 + 300 + 1. **Zero unexplained lines**,
and zero newly violated. Every moved line is "newly proved" at one site or a
report count reflecting it.

## Test expectations that changed, and why

- **`let-annotation` LA4 and LA6** (Task 1) asserted `violated = 1` and now
  assert `2`. Both fixtures are `let m : {Int | _ > 0} = 0 - 5` followed by
  `inner(m)`. Previously the downstream call was *skipped*: nothing tied `m` to
  its actual value, so only the annotation itself was decided. With (1), `m ==
  0 - 5` is pushed regardless of whether the annotation proved, so `inner(m)` is
  independently decided, and `m` really is `-5`, so the call is genuinely
  violated. This is the design's "every obligation that moves must move to
  proved or violated" invariant behaving as intended: a distinct obligation
  moved out of the skip bucket, not a false positive on an existing one.
- **AE2 and AE3** (Task 2, hardened in `f1801a38`) originally asserted only
  `proved = 0`. That cannot distinguish a genuine skip from a false `violated`,
  which is exactly what a reviewer's mutation produced: relaxing
  `arm_excludes_nested`'s `A.PatCon (d, [])` to `A.PatCon (d, _)` makes AE3's
  own source push `not is_Cons(t)`, translating to the false `len(t) = 0`, and
  the checker reports a hard `violated` that the old assertion never looked at.
  Both now assert the full triple `(proved, violated, skipped) = (0, 0, 1)`.
  **A silence guard must assert every verdict a false positive can take**, not
  just the absence of a proof.

## Gates

All run in this worktree, one foreground process each, with
`.march/cas/vc` cleared before the suite.

- `scripts/run-tests.sh` (full, not `-q`): **all suites passed, exit 0**,
  3809 `[OK]` and 0 `[FAIL]` across the twelve alcotest executables. The
  z3-backed `test_refinecheck.exe` ran **606 tests, 0 failures, 0 skipped**
  in 270.7s, which includes the new `let-equality` (3 cases) and
  `arm-exclusion-nested` (3 cases) groups. z3 was on `PATH`, so nothing
  silently no-opped.
- `dune build --root . @types-check --force`: exit 0, log **25508 bytes**,
  `core-march-types: 303 passed, 0 failed`. Run with `--force`, since without
  it the check is vacuous (exit 0, zero-byte log) and the log is what carries
  the result.
- `dune build --root . @grammar-check --force`: exit 0, log 3309 bytes,
  `grammar: 48 passed, 0 failed`.
- `scripts/check-docs.sh`: `doc-lint passed`, run again after the doc edits in
  this commit.

## Cost

Cold `--check` on a three-line module, both caches and `HOME` cleared before
each run: baseline compiler 1.59s wall / 1.28s user, this branch 1.40s wall /
1.26s user. No measurable cost, which is the expected shape: (1) adds one path
fact per admitted `let` and (2) one tester per qualifying binder, and neither
adds a solver query.
