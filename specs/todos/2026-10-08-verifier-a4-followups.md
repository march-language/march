# A1/A4 follow-ups left after checks 2-3 and pass bisection

Logged 2026-10-08, from `specs/progress/2026-10-07-verify-rc-types-and-pass-bisect.md`.

- **Leak reporting.** `MARCH_VERIFY_TIR_LEAKS=1` has not been swept. Expect the drop-glue
  fallbacks the module doc lists as accepted leaks.
- **Check 5's post-escape contract** ("`EStackAlloc` values do not escape", plan §6). Checks 4 and
  5's Defun contracts landed (`specs/progress/2026-10-12-verifier-check4-repr.md`,
  `specs/progress/2026-10-11-verifier-defun-contracts.md`); this one needs a checking mode in
  `Escape.escape_analysis`, which is a transform.
- **`test_oracle` integration (plan §9).** On a compiled-vs-interpreted mismatch, run
  `--bisect-pass` and attach the blamed passes. The reducer needs an oracle command per
  failure, so it is probably opt-in.
- **Expression-level reduction** (plan §9): replace an expression with a literal of its
  inferred type, inline a `let`, drop an unused match arm. `--reduce` only removes
  declarations and lines today.
