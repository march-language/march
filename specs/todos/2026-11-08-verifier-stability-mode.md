`[P2]` Proof stability mode: rerun each VC perturbed and report how much its cost varies, plus a CI ratchet.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 2.

## Why

Mariposa (FMCAD 2023) found 2.6% of 17k Dafny/F* queries unstable on current z3 (up to 5% in one
project). Instability shows up when a query is shuffled, renamed or reseeded, so normal CI never
sees it until an unrelated edit flips a proof. AWS's Dafny authorization engine (ICSE 2025) lost
up to 14 days per deployment to proofs broken by unrelated changes. What fixed it was a CI check
that reran each obligation under several seeds and blocked PRs whose resource-count variation got
worse. Together with opaque definitions, it cut brittle VCs from 41 to 4.

## Now

z3 runs under a deterministic rlimit (`lib/refine/solver.ml`), and the VC cache is keyed on the
query text, the z3 version and the rlimit. So a verdict is reproducible, but nothing measures how
close to the edge it sits.

## Wanted

- `march --check --stability N FILE`: for each discharged VC, run N perturbations (z3
  `smt.random_seed` / `sat.random_seed`, assertion shuffling, symbol renaming) and record the
  outcome and rlimit count of each. Report, per obligation: proved in k/N, mean and coefficient
  of variation of the cost, and the worst case. Flag "unstable" (any non-proof) and "fragile"
  (high variation or a worst case near the budget).
- A machine-readable report, so CI can ratchet: the set of unstable obligations in the stdlib
  `cap verified` modules may only shrink.
- Treat a z3 upgrade as a stability event: run the sweep over the refine-oracle corpus before
  bumping the pinned version. Mariposa traced 67% of one upgrade's 285 regressions to two small
  z3 commits.

## Done when

The mode exists with negative controls: a deliberately unstable query, such as one with a
matching loop, is flagged. CI runs it on a small corpus with a ratchet, and the docs explain
what to do about a fragile obligation (opaque, fewer facts, a hint).
