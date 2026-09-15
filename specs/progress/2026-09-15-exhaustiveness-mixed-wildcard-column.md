# Exhaustiveness: mixed wildcard/constructor column false positive, fixed

Shipped 2026-09-15.

## Symptom

```march
type Zz = Lf(Int) | Nd(Zz, Zz)
match t do
Nd(Lf(a), Lf(b)) -> a * 10 + b
Nd(Nd(_, _), Lf(b)) -> 100 + b
Nd(_, Nd(_, _)) -> 200
Lf(n) -> n
end
```

warned `Non-exhaustive pattern match — missing case: Nd(_, Lf(0))`, though
`Nd(x, Lf)` is covered by rows 1 and 2. No stdlib name collision involved.

## Defect

`find_missing_mc` (`lib/typecheck/typecheck_exhaustive.ml`) short-circuited to
the **default matrix** whenever *any* row's first column was a wildcard. The
default matrix keeps only the wildcard rows, so it forgets every value the
constructor rows cover. After specializing on `Nd` the matrix is
`[Lf; Lf]`, `[Nd; Lf]`, `[_; Nd]`; the shortcut reduced it to `[[Nd]]`, which
"misses" `Lf` in the second column.

Maranget's rule is to specialize per constructor whenever the explicit
constructors in the column form a complete signature (the `spec_*_mc`
helpers already carry wildcard rows into each specialization), and fall back
to the default matrix only when the signature is incomplete. `is_useful`
(redundancy) already did this; only the missing-case search was wrong.

## Fix

The wildcard shortcut now applies only when the signature is incomplete:

- ADT: complete explicit ctor set → specialize each ctor, else default.
- Bool: both literals present → specialize both, else default.
- Tuple / record (single shape): any tuple/record row → specialize.
- Infinite domains, type vars, opaque types: default (unchanged).

When the default path is taken with a wildcard row present the counterexample
still uses the `_` placeholder, so existing messages are unchanged.

## Tests

`test/test_compiler.ml`, `match_diagnostics`:

- `mixed wildcard/ctor column exhaustive is silent` (the match above)
- `mixed wildcard/ctor column missing row warns` (row 2 removed → warns with
  an `Nd(_, Lf(` counterexample)
- `mixed wildcard/tuple column exhaustive is silent` (`(true, _)`,
  `(_, true)`, `(false, false)`)

Both silence tests fail against the pre-fix checker.
