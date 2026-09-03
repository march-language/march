`[P2]` `unreflectable-predicate` is mostly a misattributed subject failure (filed 2026-09-02)

All 11 user-code `unreflectable-predicate` skips have predicates inside the
supported fragment. Seven are arithmetic actuals (`n - 1`, `i + 1`) that
`reflect_scalar` routes through a path whose variable resolver is hard-coded
to `None`; four are opaque-call actuals. Zero are genuine predicate failures.

Design: `specs/2026-09-02-unreflectable-predicate-attribution-design.md`.
Reflect arithmetic actuals, file failed scalar subjects under
`unreflectable-subject` naming the actual, and name the failing
sub-expression for real predicate failures via an `smt_of_r` wrapper.
