# DONE 2026-10-07: D5, type errors that show the provided side's origin

Diagnostics plan (`specs/plans/diagnostics-and-triage-plan.md`) §9.

## What landed

`report_mismatch` already labelled where the *expected* type came from
(`span_of_reason`). It now also labels the *provided* side:

- `Typecheck_types.provided = { p_span; p_name; p_ty }`, built by
  `provided_of_expr e t` at the **top-level** `unify` call for a sub-expression
  and carried unchanged through `unify`'s recursion (type arguments, arrows,
  tuples, records, the nat solver). So the label describes the whole
  expression and its whole type even when the headline is about an inner
  argument (`expected Int but got String` on a `List(String)` value).
- Labels: `this is `T`` on `p_span`, omitted when that is the primary caret
  (the renderer drops a label on the primary span); and, when the expression
  is a plain variable with an in-scope binder, ``x` was bound here as `T`` on
  the binder.
- **Binder spans.** `env.binder_spans : span StrMap.t` is immutable and
  scope-correct: `bind_var`/`bind_linear`/`bind_pending` take `?span` and set
  or *clear* the entry, so a rebinding without a span never leaves a stale one.
  Spans reach them from: named-fn parameters (`FPNamed`, `FPPat (PatVar _)`),
  lambda parameters (`bind_lam_param`), and every pattern binding through
  `infer_pattern`, which records each `PatVar`'s span in the transient
  `env.pat_spans` table that `bind_pattern_bindings` consumes (and removes)
  right after. This covers `let`, `let?`, `let*`, `with`, match arms and
  destructuring parameters without changing `infer_pattern`'s result type.
- **Call sites given a provided origin** (the plan's "top-level call only"):
  `check_expr`'s infer-then-unify arms (which is where every call argument
  and constructor argument lands), the lambda fallback, the `if` else branch,
  both match-scrutinee-vs-pattern sites, the three `let` rhs-vs-pattern
  sites, and both `let?` rhs-must-be-Result sites. Pattern-vs-pattern and
  type-vs-type unifications (annotations, or-patterns, record updates,
  interface methods, caps) have no provided expression and pass none.

## Verified

- D7 corpus regenerated; the diff adds the two labels to the type-mismatch
  cases and nothing else changes. Two new cases pin the binder labels:
  `type_mismatch_8` (a `let`-bound `String` added to an `Int`) and
  `type_mismatch_9` (a `List(String)` passed where `List(Int)` is
  required: headline `Int`/`String`, label `List(String)`).
- `run_compiler -q`, `run_eval -q`, `run_stdlib -q`, `test_lsp`, `run_errors` green.
- Oracles: `types-oracle` is the relevant one (diagnostic text changes are
  the intended effect, so its red is the review artifact, not a regression);
  `ir-oracle` does not apply (no codegen change).

## Not done

- The renderer still prints one excerpt per label, so a primary caret and a
  label on the same line show that line twice (pre-existing; §9's "print each
  excerpt once" is a renderer change left for a follow-up).
- `match do` arm bodies and record-update field values pass no provided
  origin yet.
