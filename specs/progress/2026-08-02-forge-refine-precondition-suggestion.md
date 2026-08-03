# `forge refine` — suggest the parameter refinement that discharges a body's unproven obligations

**Filed / landed:** 2026-08-02

## What shipped

Three surfaces over one inference engine:

| Surface | Entry point |
|---|---|
| Compiler | `march --refine-suggest <fn>` / `--refine-suggest-all` / `--refine-suggest-json` / `--refine-suggest-budget N` |
| Build tool | `forge refine <fn>` / `--all` / `--apply` / `--budget N` |
| Editor | code action *"Suggest a refinement type for `f`"* → `march.suggestRefinement` → `workspace/applyEdit` |

New files:

- `lib/refinecheck/precond_infer.ml` — the inference.
- `lib/refactor/refine_edit.ml` — the annotation splice, shared by `forge refine --apply`
  and the LSP so the two produce byte-identical edits.
- `forge/lib/cmd_refine.ml` — project front end (which files to ask about, rendering, `--apply`).
- `lsp/lib/refine_command.ml` — the executeCommand handler.

## The design decision that shapes everything

`Obligation.t` records a span, a callee, a predicate and a verdict. It does **not**
record which *parameter* is to blame, and there is no honest way to recover that after
the fact — an argument is an arbitrary expression over several parameters.

So the engine does not attribute anything. It **hypothesises** a refinement onto the
signature, re-runs the real `Refine_check` over the function, and reads the ledger back.
A candidate is admissible only if the debt count strictly shrank and no new `Violated`
appeared.

The property this buys: a suggestion exists *because the checker proved obligations under
it*, so `march check` after `--apply` agrees with what was printed. There is no second
implementation of VC generation to drift out of sync — the failure mode a "suggest" tool
develops silently, since a wrong suggestion still looks exactly like a right one.

The dual property is equally deliberate: the tool can never exceed the checker. Where
`Refine_check` is incomplete, the honest report is `no-candidate`, not a contract that
would not actually help. This is observable today — see "Known gap" below.

## Cost, and why the naive version was unusable

A full `check_module` is ~1.2s, almost entirely stdlib parse + registration, and probing
needs tens of re-checks. So:

- The caller runs `check_module` **once** (which populates every registration global:
  ADT tables, measure preamble, alias gates).
- Each probe re-walks a **pruned** decl tree (`Precond_infer.prune`) holding only the
  target function plus the context-bearing decls (`DUse` / `DAlias` / `DNeeds` / `DOpts`)
  of its enclosing modules — those decide callee resolution and `cap` escalation. Types
  and ADTs are deliberately absent: they were registered globally already.

Measured: a 4-function file with `--refine-suggest-all` costs 1.15s total, i.e. the probes
are free relative to the one pipeline run. Budget (`--refine-suggest-budget`, default 200)
caps the probe count.

## Candidate grammar and the ranking rule

Ordered **weakest first**, and the order *is* the tie-break: among candidates discharging
the same debt, the earliest wins.

- `Int`: `_ != 0`, `_ >= 0`, `_ > 0`, `_ <= 0`, `_ < 0`, then per List/String parameter
  `l` in the same clause: `_ < len(l)`, `_ >= 0 && _ < len(l)`.
- `Float`: `_ != 0.0`, `_ >= 0.0`, `_ > 0.0`.
- `List` / `String`: `len(_) > 0`.

`_ != 0` leads because a divisor contract must not also forbid negatives. A contract
narrows the caller set, so proposing a stronger one than the body needs is a real cost.

Greedy, one candidate per parameter per round, and never two candidates conjoined onto one
parameter — so the loop cannot synthesise a contradictory contract that "proves"
everything vacuously.

## Statuses — silence is never ambiguous

`No_debt` / `Solved` / `Partial` / `No_candidate` / `Budget_exhausted` / `Not_found` are
distinct. `Budget_exhausted` is deliberately not folded into `No_candidate`: "nothing in
the grammar fits your code" and "I stopped looking" are different facts, and reporting the
second as the first is a truncated search that reads exactly like a complete one. The
budget is also **per function**, not per sweep, so a `--all` run cannot have later
functions starved by earlier ones. This mirrors
why `Obligation` exists at all: a contract that checks nothing and a contract that passes
look identical from outside unless the outcome is countable.

## Validated on real code, and what that changed

Swept three corpora before calling it done:

| Corpus | Result |
|---|---|
| conduit — 43 files, ~7k lines | 80s, no crashes, 0 suggestions — a TRUE negative (it declares no refinements and calls none of the refined stdlib API) |
| a 7-case project | every case correct, incl. picking `size` over an unconstrained `String`, and `_ >= 0` (not `_ > 0`) for `Crypto.random_hex` |
| all 112 stdlib modules | 4 suggestions — **and 3 of them were wrong** |

The three wrong ones were `Stats.mean_safe` / `min_safe` / `max_safe`: documented
"returning Err on empty list", opening with `match xs do Nil -> Err(…)`, and doing the
real work in the `_` arm. The checker cannot derive `len(xs) > 0` from "the `Nil` arm was
excluded", so there is genuine debt — and `{List(Float) | len(_) > 0}` discharges it by
forbidding the exact input the function exists to accept. Applying it makes the `Nil` arm
dead and moves the obligation onto callers: a legitimate `mean_safe([])` goes from 0
obligations to 1 unproven one.

That is a suggestion that is *provably* debt-discharging and *semantically* the opposite
of correct — the class of error the assume-and-recheck design cannot catch on its own,
because it only ever asks "did the debt shrink". Hence `contradicts_handled_case`: if the
function handles the excluded input NON-fatally, do not propose. If it handles it by
PANICKING, still propose — converting that panic into a compile error is the entire point,
and a guard that suppressed those would over-correct while looking like an improvement.
Both directions are pinned by tests.

The real fix was in the checker, and it landed:
`specs/progress/2026-08-03-match-arm-exclusion-refutes-a-measure-fact.md`. With
arm-exclusion propagating to the `len` measure, four of those five functions have no debt
at all and there is nothing to suppress — a post-fix sweep of the stdlib returns zero
suggestions. The guard stays, because it is cheap and covers shapes the checker fix does
not reach.

Also learned: contracts propagate one call hop per round, so `--all --apply` must be run to
a fixpoint (three rounds on the 7-case project). Now built as `--fixpoint`.

## Two traps hit on the way

1. **Warm-CAS short circuit.** `--check` exits on a CAS artifact hit *before* the
   refinement passes run, so a flag whose whole output comes from those passes prints
   nothing on a warm cache. Fixed for `--refine-suggest*` and, in the same edit, for the
   pre-existing `--refine-report` (which had the same latent bug).
2. **Candidate text vs. candidate AST.** Each candidate carries its predicate twice — as
   source text (what `--apply` writes) and as an AST (what the prover saw). Nothing forces
   them to agree, and a mismatch would write a contract the solver never verified. Pinned
   by `test_precond_infer_candidate_text_matches_ast`, which parses every candidate's text
   through the real parser and compares it structurally to the AST.

## Known gap at the time — since fixed

```march
fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do … end
fn pick(xs : List(Int), i : Int) : Int do at(xs, i) end
```

`pick` reported `no-candidate`, and writing the ideal contract by hand left the obligation
`solver-undecided` too — so the tool was correctly declining to propose something that
would not have helped.

Filed as a `len`-propagation bug, which measurement then refuted: `len` was incidental. A
caller's promise was dropped whenever it mentioned **any** name other than its own subject,
measure or not. Fixed in
`specs/progress/2026-08-03-caller-refinement-survives-mentioning-another-name.md`;
`forge refine pick` now proposes `{Int | _ >= 0 && _ < len(xs)}`.

## Tests

`test/test_compiler.ml`, groups `precond_infer` (6) and `refine_edit` (4). Verified
non-vacuous by inverting an expectation and confirming the failure — the z3-gated bodies
are genuinely running, not skipping.
