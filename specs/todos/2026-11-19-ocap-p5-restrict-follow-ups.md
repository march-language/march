# ocap phase 5: restrict follow-ups (perf and coverage)

Logged 2026-11-19 by ocap phase 5 (specs/plans/2026-11-19-ocap-p5-restrict-plan.md). Minor
items the phase-5 reviews deferred; none changes what a program is allowed to do.

- **The drop rule keeps frames a callee's machinery makes look necessary.** `Auth_rt.restricts`
  keeps a literal restrict whose block reaches a call of a function value. A block that calls a
  function which itself contains a kept restrict or a framed call reaches
  `Authority.restrict_layer` → `parse` → `List.map`, an indirect call, so the outer frame is
  kept although the block itself calls no value. The frame machinery is excluded only inside the
  block's own body. Fix: also exclude the layer fns, `Authority.enter_fn` and
  `Authority.restrict_layer` from the reaching seed of callees. Perf only.
- **The interpreter's `+` guard is still quadratic on some shapes.** `lib/eval/eval.ml`'s
  `EApp "+"` arm runs a cheap pre-check before `Scope_expr.classify`, but a balanced
  `(a + b) + (c + d) + ...` chain is still classified once per node. No test pins the pre-check.
- **`restrict_layers` memo is never reset.** The interpreter memoises literal restrict layers by
  site; the table grows for the life of the process, which is unbounded across a long REPL
  session that keeps redefining functions with restricts. Reset it with the REPL's per-load state,
  or key it weakly.
- **The named-function-value rule has no JS coverage.** `restrict_named_fn_value_inside` is in
  `js_unsupported` because the JS target has no `file_read`; a fixture over an operation
  JS has (`IO.Console` with a `()` restrict, or `IO.Clock`) would pin it there.
- **Scope helpers duplicate Authority's tables.** `stdlib/scope.march`'s `dotdot_path` repeats
  `Authority.path_kind`'s list of path kinds; add a cross-reference or share it. `Scope.build`'s
  doc does not say that `\` is accepted and escaped, nor that a computed `..` is rejected while a
  literal one follows the `needs` grammar.
- **`cap_restrict` diagnostic spans.** When a block calls a local `fn go` and later the top-level
  `go`, the error is right but the caret lands on the first `go()` (the reference span is looked up
  by name in an unscoped call list, `lib/typecheck/typecheck_caps.ml`, restrict walker). A function
  used as a value is reported at the `restrict` keyword rather than at the reference. The `let?`
  hint renders string literals with OCaml `%S`, so non-ASCII text shows as byte escapes.
