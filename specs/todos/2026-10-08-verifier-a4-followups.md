# A1/A4 follow-ups left after checks 2-3 and pass bisection

Logged 2026-10-08, from `specs/progress/2026-10-07-verify-rc-types-and-pass-bisect.md`.

- **Check 3 in the snapshot harness.** `test/test_snapshots.ml` runs Perceus by hand. It
  should compute `Kind.of_module` and `Borrow.infer_module` once, pass both to Perceus, and
  pass both to `Tir_verify.check`.
- **Leak reporting.** `MARCH_VERIFY_TIR_LEAKS=1` has not been swept. Expect the drop-glue
  fallbacks the module doc lists as accepted leaks.
- **Checks 4 (repr invariants) and 5 (pass contracts)** from plan §6.
- **`test_oracle` integration (plan §9).** On a compiled-vs-interpreted mismatch, run
  `--bisect-pass` and attach the blamed passes. The reducer needs an oracle command per
  failure, so it is probably opt-in.
- **Expression-level reduction** (plan §9): replace an expression with a literal of its
  inferred type, inline a `let`, drop an unused match arm. `--reduce` only removes
  declarations and lines today.
