# Grant extern guard: three follow-ups

Logged 2026-11-24 from the scoped re-review of the phase 6 final-review fixes (`386ed9ba9`). None
weakens the static check (`--check` still fails for a granted package that reaches an extern
without `IO.Foreign`); each is a run-time or tooling inconsistency.

1. **A module-level extern value in a granted package is not eta-wrapped.** `let p = getpid` at
   the top of a granted package: the eta pass's reach (`lib/tir/auth_rt.ml`, around the
   module-level named-value rewrite) is computed before `guard_externs` adds the
   `foreign_guard` call, and an extern is neither a defined fn nor an op builtin, so `Pkg.p()`
   from the app runs the C under the app's authority, whereas `let reader = File.read` is
   treated as the package's own function. Fix: treat an extern atom like a named fn in that
   rewrite (eta lambda with the grant prologue).
2. **The stdlib's JS externs under `--target js`.** `dom`, `canvas`, `audio` (`Cap(Ffi)`) calls
   are guarded on `--target js` when grants are active. If their stdlib rows do not carry
   `IO.Foreign`, `--check` can pass while the run panics with an `IO.Foreign` refusal.
   Unverified; check the rows and add a conformance fixture.
3. **`march repl FILE` preload verdict and early-phase errors.** `Dep_grants.preload_check_verdict`
   loads on exit 1 whenever a rendered diagnostic is present. An exit 1 from a phase that stops
   before typecheck (parse, desugar, resolve) therefore also loads; harmless only if the REPL's
   own load stops on the same error. Verify, and refuse if not.
