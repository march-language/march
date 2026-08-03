# `--coverage` reports an expression percentage above 100%

Filed 2026-08-03. Found while fixing the interpreter FFI drop bug
(`specs/progress/2026-08-03-interpreter-ffi-int-arg-misdropped-as-heap-pointer.md`).

## Symptom

`march test --coverage` on `~/code/mgrep` (203 tests, all passing) prints:

```
=== Coverage Summary [mgrep_test.march] ===
  Expressions: 2095 /  430  (487.2%)
  Branches:       6 /    9  ( 66.7%)
  Functions called: 219 unique
```

487.2% is not a meaningful coverage number.

## Likely cause

The numerator and denominator are computed over different file scopes:

- the denominator comes from `count_totals ~file` in `lib/coverage/coverage.ml`,
  which walks only the target file's AST, while
- the numerator (`count_unique_hits`) folds over `expr_hits`, which
  `record_expr` populates for every expression evaluated anywhere — including
  the project's `lib/` modules and stdlib.

So a test file that mostly drives library code counts far more hits than it has
own expressions. Note `record_expr`'s span filtering and the `in_file` guard in
`walk_expr` differ; the fix is presumably to filter recorded hits by the same
`file` the totals are counted for, or to report per-file rows rather than one
aggregate.

Branches (6/9) look plausible, so this may be specific to the expression
counter's key filtering.

## Also worth a look while in here

Coverage is very slow: the mgrep suite takes ~1900s with `--coverage` versus
seconds without. `record_expr` builds a fresh `string` span key
(`span_key`) and does a `Hashtbl.find` + `Hashtbl.replace` on *every*
expression evaluation. An int-keyed table, or memoizing the key on the span,
would likely remove most of that constant factor. Separate concern from the
wrong percentage — do not conflate the two in one change.

## Not a bug in

Coverage instrumentation is not implicated in FFI crashes. The
previously-suspected "coverage breaks on FFI file operations" was an unrelated
reference-counting bug in the interpreter's FFI argument cleanup; `--coverage`
merely selected the interpreter path that exposed it.
