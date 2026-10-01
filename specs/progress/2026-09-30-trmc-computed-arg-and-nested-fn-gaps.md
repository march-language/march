# TRMC: computed call arguments and nested functions (fixed 2026-09-30)

Both gaps were filed 2026-09-28 from the stdlib natural-style rewrite. Fixed in
`lib/tir/trmc.ml`.

**Reproduced on origin/main (771430bf3).** `test/native/trmc_computed_arg_nested.march`
(five shapes over 1,000,000 elements) compiled and run: **SIGBUS in the stack
guard page** (exit 138). `MARCH_TRMC_REPORT=1` said `non-trmc` for the
computed-argument functions and, for the nested `go`, `TRMC eligible` with no
`TRMCXFORM` line.

## 1. Computed argument: let-floating

Lowering nests the argument's `let` inside the call's binding
(`let t = (let n = a + 1 in f(n, b)) in alloc Cons(a, t)`), so the site was
scanned as a value computation. `float_lets ~self` now hoists such a binding
(`ELet (x, ELet (y, e1, e2), k)` -> `ELet (y, e1, ELet (x, e2, k))`) before the
analysis and before `returnify`/`seed_entry`, which match the same shape.

- It fires only for a let whose RHS contains a self-call and only when `y` is
  not free in `k` (no capture). Every unrelated function is untouched: it is
  applied to a private copy, and a function that is not then transformed keeps
  its original body. (A first version floated every nested let in a transformed
  function and changed the perceus snapshots of `trmc_modulo_cons` and
  `nested_cons_ctor_heap` for no reason; the self-call restriction removed
  that diff.)
- Evaluation order is unchanged: the inner binding already ran first.

## 2. Nested functions: transform, do not stop reporting

Decision: transform. Reporting them as ineligible would leave natural-style
nested helpers overflowing the stack, which is the very thing the pass exists to
prevent. `transform_nested` rewrites a self-named lambda-shape binding
(`let go = letrec [go] in go in rest`) into
`let go$dps = letrec [go$dps] in go$dps in let go = letrec [go] in go in rest`:
two single-function bindings because the dependence is one-directional (the
entry calls the helper; a `$dps` body never calls the entry) and `Defun`
consumes exactly the single-function lambda shape. Nested-in-nested is handled
innermost-first. A lambda-kind `ELetRec` member the analysis calls eligible but
which is not in this shape now prints `TRMCSKIP ... nested-shape` instead of
silently staying untransformed. The helper keeps the entry's `fn_kind`.

Side effect worth knowing: 10+ stdlib nested helpers that were "eligible but
never transformed" (`Http.encode_query`'s `go`, `HttpClient.list_steps`'
`*_names`, `Dir.list_full`'s `prepend`, ...) are now genuinely transformed.

## Verification

- `test/test_trmc.ml`: `computed argument is eligible`, `let-float respects
  continuation` (a name the constructor reads is not floated), `nested fn is
  transformed` (helper bound before entry, lambda kind kept, second run adds
  nothing). RED with `float_lets` disabled: the first fails
  (`Expected "eligible", Received "non-trmc"`).
- `test/snapshots/src/trmc_computed_arg_nested.march` (lower + perceus): pins the
  hoisted shape and both `$dps` helpers, including the nested one as a closure.
- `test/native/trmc_computed_arg_nested.march` golden (interpreter output as
  `.expected`): five shapes over 1,000,000 elements, three of them with an
  ALTERNATING two-branch arm and one capturing an outer variable; compiled run
  matches the interpreter.
- Benchmarks compiled `--opt 2`, same box, origin/main (771430bf3) vs branch.
  `list_ops`, 15 interleaved runs: median 0.0864s / 0.0861s, min 0.0835s /
  0.0825s. `tree_transform`, 5 runs: min 0.734s / 0.741s (within noise).
  Load average 4.3 during the runs.
- Unit tests RED on origin/main: copying the new `test/test_trmc.ml` there
  fails `computed argument is eligible` and `nested fn is transformed`.
