`[P3]` Checked solver proofs: take z3 out of the trusted base for `cap verified` modules.

Medium step 9 of `2026-11-06-verification-ladder-roadmap`.

## Now

Every `proved` verdict trusts z3 (and the checker's own encoding). A z3 bug or an encoding bug that
makes a VC trivially unsat yields a false proof that nothing re-checks.

## Wanted

For modules under `cap verified` (opt-in, it costs time): ask z3 for a proof of each unsat VC,
export it in the Alethe format, and check it with an independent checker (Carcara, or `lean-smt`
for a Lean-kernel check). A proof that does not check is reported as `unverified (proof rejected)`,
never silently accepted.

## Notes

- This removes z3 from the trusted base, not the encoding: a wrong encoding still yields a
  correctly-checked proof of the wrong VC. The `reflect-parity`, refine-oracle and conformance
  corpora remain the encoding's evidence.
- z3's proof production is slower and its Alethe export is partial (quantifier instantiation,
  datatypes); measure which of today's VCs export and check, and say so in the report.

## Done when

- `march --check --checked-proofs FILE` on the stdlib `cap verified` modules reports, per
  obligation, `checked` / `not exportable` / `rejected`, with totals; CI runs it on a small corpus.
