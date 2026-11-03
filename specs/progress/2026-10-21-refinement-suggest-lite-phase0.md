# Inference-lite, phase 0: guards for the shipped suggest tools

Landed 2026-10-21. Design: `specs/2026-10-20-refinement-suggest-lite-design.md` §0, §2, §5.1, §9 D2/D3/D4.
Plan: `specs/plans/2026-10-21-refinement-suggest-lite-plan.md` Tasks 1-3.

## What a user sees

- `march --refine-suggest-all` no longer proposes a precondition that turns an existing caller into a
  refinement violation (row G0: `go(n) = need_pos(n)` with `caller() = go(0 - 5)` was proposed
  `n : {Int | _ > 0}`, "discharges all"). It now prints `go: refused (caller-violation)` with the
  call it would break.
- A hypothesis is accepted per site: it must close a site, open none and create no violation. The
  count it replaced accepted "proved two, broke one".
- A candidate that would make the clause's parameters unsatisfiable is rejected.
- A public function with no caller in the unit is marked `external-callers` (D3).

## What landed

| Change | Where |
|---|---|
| `Ledger_diff`: per-site snapshot and diff (`closed`/`opened`/`new-skip`/`new-violated`) | `lib/refinecheck/ledger_diff.ml` |
| `Precond_infer.admissible`; `walk_ledger` replaces `count_debt`/`walk_debt` (also in `Postcond_infer`) | `precond_infer.ml`, `postcond_infer.ml` |
| `prune_with_callers` (every in-unit caller, any module) shared by both tools; the hypothesis signature is put into the callers' `defs` | `precond_infer.ml` |
| `Refused { rf_reason; rf_sites }` status, `rs_external_callers`, `?allow_caller_violations`, `satisfiable` | `precond_infer.ml`, `bin/main.ml` |
| `Obligation.t.inst`: the demand re-spelled in the caller's scope (record-only) | `obligation.ml`, `refine_call.ml` |

`satisfiable` asks the real checker: a probe calls `never : {Int | _ < 0 && _ > 0}` with each Int
parameter as the subject (a literal `false` goal is reported violated outright, and a goal loads only
the facts of names its subject mentions — both probed).

## Tests

`test_refinecheck` group `infer-guards` (13): ledger diff classification; "proves two, opens one"
rejected (synthetic snapshots); S1 unchanged; G0 refused with the caller's site; G0 with
`~allow_caller_violations`; `satisfiable`; same name in two modules; a caller in a sibling module;
`external-callers`; `inst` for R1 and `None` for an expression actual.

## Filed (the oracle gaps the design's probes found)

R2 `2026-10-21-refine-relational-filter-return-unproved.md`, O1 `…-local-fn-option-return-unproved.md`,
C1 `…-post-through-callee-post-unproved.md`, G1 `…-relational-scalar-return-not-lent.md`.
