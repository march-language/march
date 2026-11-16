`[P3]` Checked solver proofs: take z3 out of the trusted base for `cap verified` modules.

Medium step 9 of `2026-11-06-verification-ladder-roadmap`.

## Now

Every `proved` verdict trusts z3 (and the checker's own encoding). A z3 bug or an encoding bug that
makes a VC trivially unsat yields a false proof that nothing re-checks.

## Wanted

For an explicit checked-proof mode (opt-in, it costs time), obtain a certificate for the exact
unsat VC and check it independently. Start by measuring a supported producer/checker pair;
do not assume the pinned z3 has a usable Alethe exporter. Keep normal z3 verification unchanged.
A proof that does not check is reported as `unverified (proof rejected)`, never silently accepted.

## Notes

- This removes z3 from the trusted base, not the encoding: a wrong encoding still yields a
  correctly-checked proof of the wrong VC. The `reflect-parity`, refine-oracle and conformance
  corpora remain the encoding's evidence.
- Proof-production cost and theory coverage are measured properties of the pinned toolchain.
  An unsupported format, rule, or theory is `not exportable`, never an unchecked success.

## Done when

- `march --check --checked-proofs FILE` on the stdlib `cap verified` modules reports, per
  obligation, `checked` / `not exportable` / `rejected`, with totals; CI runs it on a small corpus.

## Certificate feasibility before integration (2026-11-07)

[Carcara, TACAS 2023](https://doi.org/10.1007/978-3-031-30823-9_19) checks and elaborates Alethe
proofs. [cvc5's Alethe documentation](https://cvc5.github.io/docs/cvc5-1.4.2/proofs/output_alethe.html)
provides a concrete producer/checker route, with stated theory limitations; that is evidence for
an experiment, not evidence that all March VCs can use it.

1. Freeze a corpus of March's actual emitted VCs by theory: arithmetic/EUF, datatypes, sets,
   strings, floats, reflected functions and quantifiers. Record status, certificate size,
   generation/check cost, unsupported rules and exact producer/checker versions.
2. Compare a supported z3-native certificate checker, if available for the pinned version,
   with replay of the *same* VC through cvc5 -> Alethe -> Carcara. A second solver's `unsat`
   answer alone is cross-checking, not independent proof checking. Any VC normalization needs
   checked justification or must be explicitly included in the trusted translation.
3. Reject proof holes, admitted rules, missing certificates, truncated output and failed checks.
   Add tampered-proof, wrong-VC and stale-cache negative controls. Check that the certificate's
   assumptions are precisely the requested VC plus its declared trusted axioms.
4. Bind cached evidence to VC bytes, logic/encoding version, trusted axioms, toolchain versions
   and checking policy. Report logical `proved` separately from certificate `checked`.
5. In `--checked-proofs` mode, any required obligation without checked evidence fails the gate;
   still emit the complete `checked` / `not exportable` / `rejected` report. Do not silently
   fall back to ordinary solver trust. Ordinary `cap verified` keeps its documented semantics.

A checked proof establishes the encoded formula. It does not establish source-to-VC correctness,
prove `@[assume]` contracts, or validate the runtime. Keep those trust dependencies in the report.
