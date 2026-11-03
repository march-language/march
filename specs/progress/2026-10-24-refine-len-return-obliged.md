# A length-only list return contract is obliged at every tail

Found by the 2026-10-24 stdlib refinement audit (probe p5):

```march
fn f(xs : List(Int)) : {List(Int) | len(_) == len(xs) + 5} do xs end
```

passed `--check` with no error, and `--refine-report` raised no obligation for
it. `--refine-audit` already flagged the site ("routed to no path that checks it").

## Root cause

`Refine_post.check_fn_post_verdict` sends a `{List(_) | …}` return whose
predicate has no `elts`/`keys` to Tier 2 (`check_post_induction`). Tier 2 handled
two body shapes: a constructor literal (Shape 1) and a `match` on a parameter of
declared ADT type (Shape 2). Every other path returned `false` without recording
anything:

- any other body (`| _ -> false`): a bare variable, `let` (unless it inlined to
  one of the two shapes), `if`, a call, a `match` on a non-parameter;
- a Shape 2 `match` on a parameter with no declared ADT type;
- a signature `post_induction_shape` declines: several clauses, a guard, an
  unusable predicate, or a return type with no declared measure.

So the definition side filed nothing, and the contract simply did not propagate.
The same omission hid a second hole: Tier 2 wrote its ledger entry with
`Obligation.record` and stopped there, so a Tier 2 skip inside `cap verified`
compiled without an error (the direct path's `note` escalates; Tier 2 had no
equivalent). A third, smaller gap was in the direct `elts` path: in a mixed
`elts(_) == elts(xs) && len(_) == len(xs)` contract, `len(_)` resolved to a fresh
unconstrained constant, so the true contract was always `solver-undecided`.

## Fix (`lib/refinecheck/refine_post.ml`)

- **Shape 3** in `check_post_induction`: any single-clause, unguarded body that
  is not Shape 1/2 is walked with `tails_bound`, and each tail goes through the
  existing `check_tail` with `~mctx:None ~pat:None`. No induction hypothesis can
  be assumed (no matched parameter), and no pattern equation is asserted (an
  inner match's binders are free constants), so it is strictly weaker than Shape
  2, never stronger. A tail binder that shadows a parameter is renamed apart
  (`inner_name`, as `check_fn_post_verdict` does); an incomplete renaming is a
  recorded skip. One obligation per function, proved iff every tail is; a
  refutation goes through `settle_refutation` like Shape 1/2, so it is reported
  only when the interpreter reproduces it. Shape 2's "no declared ADT" exit now
  falls to Shape 3 too.
- **`record_tier2`**: every Tier 2 verdict is recorded through one helper that
  applies `@[trusted]` (skip → trusted) and escalates a skip to
  `refinement_unverified` under `cap verified`, with the direct path's wording.
- **`tier2_declined_reason`**: a REFINED return `post_induction_shape` declines
  records a skip naming why (several clauses, a guard, an unusable predicate,
  no declared measure). An unrefined return still files nothing.
- **Mixed `elts && len`** (`check_post`, `goal_resolve_measure`, three lines of
  logic): under `list_ret`, `len(_)` is the tail's length: a returned name's
  `len` constant, `1 + len(t)` per `Cons`, `0` for `Nil`, a call's proved
  contract via `measure_of_call`. Anything else keeps the fresh constant. This
  is the only `check_post` edit; PR #1021 also edits `check_post` (scalar tail
  calls), and this hunk does not touch the demand plumbing it changes.
- `return_refinement_checked` (the audit's routing) now says Enforced for every
  signature `post_induction_shape` accepts; `post_induction_checks` still gates
  the `elts` path's induction attempt and is unchanged.

`Cons(h, t)` has length `1 + len(t)`: the equation IS available inside Tier 2
(the structural `len` over `List` is declared per query), contrary to the audit's
note, which was about the direct `elts` path. So the constructor tails prove
rather than skip.

## Shape map (`--check --refine-report --refine-report-sites`, private HOME, z3)

| body | before | after |
|---|---|---|
| bare `xs`, true / false `+5` | nothing / nothing | proved / violated |
| `let ys = xs; ys`, true / false | nothing / nothing | proved / violated |
| `if b do xs else xs end`, true / false | nothing / nothing | proved / violated |
| call to a proved `id(xs)`, true / false | nothing / nothing | proved / violated |
| call to `List.reverse(xs)` (elts-only contract) | nothing | skipped, solver-undecided |
| call to an uncontracted `g(xs)` | nothing | skipped, unreflectable-subject |
| `Cons(h, t)`, `[]` | proved / violated (Shape 1) | unchanged |
| `match` on a parameter (Shape 2) | proved / violated | unchanged |
| `match g(xs) do … -> xs end` (non-parameter scrutinee) | nothing | proved / violated |
| mixed `elts && len`, true / false | skipped, solver-undecided / violated | proved / violated |
| guarded clause | nothing | skipped, unreflectable-predicate |
| Shape 2 skip under `cap verified` | recorded, NO error | error |
| non-list ADT: `push(t, x)` matching an UNANNOTATED `t` (`size` contract) | nothing | skipped, solver-undecided (Shape 3, no IH) |

Before: 10 of 20 probe functions filed nothing. After: every one files a verdict.

## Tests (`test/test_refinecheck.ml`, group `len-return-obliged`, 24 cases)

RED against the unfixed checker: 16 failures (cases 0-9, 13-15, 17-19); the 8
that passed are the Shape 1 constructor cases, the false mixed contract, the
proved-under-`cap verified` case and the three controls, all of which worked
before. GREEN: 24/24 after the fix (one expectation corrected: the guarded
clause's skip reason is `unreflectable-predicate`, see the ruling below).

One existing test moved, deliberately: `audit-classify` pinned "a Tier 2 match
on an unannotated parameter is Unenforced". That function now files an
obligation (Shape 3, last row above), so the case is flipped to Enforced.

## Oracle

`scripts/refine-oracle.sh baseline` before the edits and `check` after, each
under its own private HOME: **identical, 7865 lines over 551 fixtures**. No
`test/native` or stdlib function had a contract in the newly checked shapes:
every stdlib `{List(_) | …}` return uses `elts`, which never took the silent
path, no stdlib or corpus module is `cap verified`, and no corpus refined return
is declined by `post_induction_shape`. So no stdlib contract turned out false,
and none newly skips. Red-proof: with one probe fixture
(`test/native/zz_oracle_redprobe.march`, a guarded `len` contract and a false
`len` contract over a let-then-match body) added and the same baseline, `check`
goes RED on exactly that fixture's lines; the probe was removed afterwards.

## Audit baselines

`test/refine_audit/corpus.baseline` and `holes.baseline` are unchanged: the
corpus has no Return site the old routing called Unenforced, so the reclassified
sites do not occur in it. The CI skip ceiling (`stdlib/list.march`, user +
stdlib slice) measures 37 skipped against a ceiling of 42, unchanged from main;
the ceiling is not touched.

## Rulings

- Ruling: the false `xs` contract is a **violation**, not a skip — the negated
  goal `len(xs) != len(xs) + 5` is valid and the interpreter reproduces it
  (`f([])` returns `[]`) — cost if wrong: a correct program reported, which
  `settle_refutation`'s confirmation step exists to prevent.
- Ruling: Shape 3 uses NO induction hypothesis — the IH is licensed only by a
  match on the recursion parameter, which Shape 3 by definition lacks — cost if
  wrong: none for soundness; a recursive function not shaped as Shape 2 loses
  a proof (a skip).
- Ruling: one obligation per function, not per tail — Shape 2 already counts
  that way and the ledger counts are what the oracle pins — cost if wrong:
  `--refine-report` names the first failing tail's reason only.
- Ruling: Tier 2 skips now escalate under `cap verified`, for Shape 1 and 2 as
  well as Shape 3 — the brief requires an unproved contract to be an error
  there, and the direct path already did this — cost if wrong: a `cap verified`
  module with a Tier 2 contract it cannot prove stops compiling (none exists in
  stdlib or `test/native`; it gets `@[trusted]` or a weaker contract).
- Ruling: a guarded clause is a skip with reason `unreflectable-predicate` —
  desugar rewrites a guarded head over fresh argument names, so the predicate's
  `xs` names no parameter — cost if wrong: the reason reads as a predicate
  problem rather than a shape problem; the obligation is still recorded.
- Ruling: no `@[assume]`, no ceiling change — nothing in the stdlib moved.

## Not done

- A guarded or multi-clause list return is still only a recorded skip, not
  checked clause by clause.
