Second slice of §X1 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (first slice:
`specs/progress/2026-11-03-diag-x1-blame-literals-and-ctors.md`): a lambda passed to a call whose
result alone decides the wrong part of the call's type is blamed at its body, not the whole call.

`List.map(xs, fn x -> x + 1)` against a declared `List(String)` used to underline the whole call.
`map`'s result element `b` is a fresh variable that the lambda decides, so the mismatch only showed
up when the result met the return type. Now `x + 1` is underlined with "expected `String` but got
`Int`." and the note "`List.map` has type `List(a) -> (a -> b) -> List(b)`, and this function's
result is its `b`."

**Diagnostics only**, like slice 1: `check_expr`'s infer-then-unify arm calls
`relocate_callback_mismatch` (`lib/typecheck/typecheck.ml`) after the literal relocation. It reads
the callee's generic scheme (`lookup_var`, `Poly`), peels one arrow per argument, and takes the
first part where the call's inferred type and the expected type differ (X2's `type_diffs`). It
walks the scheme's result along that part's path (`type_at`) to the first quantified variable on it.
The move happens only when exactly one argument's parameter type mentions that variable, that
argument is a lambda, the lambda's result is exactly the variable, and the lambda's own parameters
don't mention it. So `fold_left`, whose accumulator type is also decided by its initial value, keeps
the error on the call (`type_mismatch_38` pins that).

The moved diagnostic lands on the body's final expression (a block's last one). Its headline is the
body's type against the expected type's part at the variable, with an X2 diff when they differ
further in, or that pair's hint when they don't. A literal body narrows further through slice 1's
`locate_literal_part` ("In the `port` field."). The call-level diff note and hint are dropped. The
signature in the note letters its own variables from `a` in order of appearance.

Corpus: `test/errors/type_mismatch_35` (map), `_36` (record body, narrowed to the field), `_37`
(block body, tuple component), `_38` (the `fold_left` guard).

Not in this slice: `if`/`cond` branches against a known type, the swapped pair on `x ++ "no"`, a
callee that is not a plain name (a local closure, a pipe target already desugared differently),
and a named function passed where the lambda would be.
