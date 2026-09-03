`[P2]` `unreflectable-predicate` is mostly a misattributed subject failure (filed 2026-09-02)

All 11 user-code `unreflectable-predicate` skips have predicates inside the
supported fragment. Seven are arithmetic actuals (`n - 1`, `i + 1`) that
`reflect_scalar` routes through a path whose variable resolver is hard-coded
to `None`; four are opaque-call actuals. Zero are genuine predicate failures.

Design: `specs/2026-09-02-unreflectable-predicate-attribution-design.md`.
Reflect arithmetic actuals, file failed scalar subjects under
`unreflectable-subject` naming the actual, and name the failing
sub-expression for real predicate failures via an `smt_of_r` wrapper.

## Noted during implementation (2026-09-03)

- An opaque actual for a sibling parameter (`at(i, lane(4))` against `{Int | _ < n}`) is still filed as `unreflectable-predicate`; only the self binder is consulted. Out of the design scope. Task 4 must count it in the sweep rather than claim the bucket is empty.
- The unreflectable-subject rule as built: the subject is blamed when the predicate consulted the bare binder and that reflection failed. A predicate that never reaches a bare binder (only a measure over it, or an opaque call over it) still blames the predicate even when the subject is also opaque. The docs must state this in one sentence.
