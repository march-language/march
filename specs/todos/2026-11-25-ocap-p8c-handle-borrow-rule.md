`[P2]` 8c: the definition-site rule for handle parameters, and `(T needs h)` (2026-11-25)

Design §7.2 says a bare handle-typed parameter in a public signature *borrows*: the function
may not let it escape, and one that keeps it names it in its result,
`fn BufReader.new(h : File.Handle) : (BufReader needs h)`. Phase 8b did not ship this (plan
`specs/plans/2026-11-25-ocap-p8b-scoped-escape-plan.md`, Q1, approved by the owner): in 8b every
function's handle parameters are inferred, public or private, and the error is reported at the
scoped callback that lets the handle out through whatever it called.

For 8c, with the other public-signature rules:

- Parse a capture set inside a type (`(T needs h)`), which 8b did not need.
- Check a public function's body against its signature: a handle parameter not named in the
  result type may not reach the result, a table, a message or a spawned actor. The escape
  positions already exist (`sink` and `find_escapes` in `lib/typecheck/capture.ml`); the new
  part is a tracked name per handle parameter of a public function, checked at its definition.
- The message for an escape through a library function can then point at the function's
  signature instead of following the handle into its body.
- Design §18's two escape tests that 8b left out: `BufReader.new` with a named handle
  parameter, and a borrowing public function that stores its handle parameter, rejected at its
  definition.
