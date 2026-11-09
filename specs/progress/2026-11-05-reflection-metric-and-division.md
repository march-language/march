Reflection: metric-certified functions and division by a non-literal are encoded

Two gaps of `specs/todos/2026-10-31-reflection-encoder-gaps.md`. Both came from the encoder
being built before the refinement walk, which decides the facts each rule read.

**R4, division by a non-literal.** The encoder now translates `a / b` and `a % b` with a
non-literal `b` through `Refine_scope.truncating_division` (`` `Term ``), and keeps the
template only when `Refine_reflect.divisions_defined` shows every divisor non-zero from the
function's own facts: its parameter refinements (`_ != 0`, `_ > 0`, `_ >= 1`, `_ < 0`, ...), the
case's guards in order, and the conditions `&&`, `||` and `if` put in force on the way down. It is
structural, so it needs no solver and answers the same every run. A function it cannot show
total declines (the symbol stays uninterpreted) and is reported `R4:divides by a value nothing
shows is non-zero`. `--reflect-report` takes that verdict when the ledger has no `Division`
obligation (a module without `cap no_panic`).

**R2, metric certificates.** A `metric` certificate is decided after the walk. `Refine_check.
check_module` now runs a second pass when the walk certified a function the encoder had
blocked only for lacking one, with the certificate seeded into the encoder
(`Refine_reflect.seed_certs`); the first pass's diagnostics are dropped. The certificate was
proved without the function's own equation, so the second pass may rely on it. Only a module
whose walk plans metrics (`@[decreases]`, `cap total`, `--termination-report`) can need it.

Tests (`test/test_refine_lemma.ml`): `div_param`, `div_guard`, `div_red`, `metric_cert`,
`metric_cert_red` (a false theorem, and a `@[decreases]` whose metric does not hold, do not
prove); `report_div` in `test/test_refine_reflect.ml` pins the report.
