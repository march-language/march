# Warning: a function body fixes a signature type variable (`annotated_tyvar_fixed`)

Landed 2026-09-22. This is option (b) of
`specs/todos/2026-09-18-typecheck-annotated-tyvars-flexible.md`, which stays
open for option (a), rigid annotation variables, and carries the measurement.

## What it does

`check_fn` (lib/typecheck/typecheck.ml) checks each single-clause function
after its body is checked and its self-type unified, and before
generalization. For each type variable written in the signature
(`annotated_tyvar_fixings`):

- **bound to a non-variable type** gives `The type variable `a` in `bad`'s
  signature is not generic: the body fixes it to `Int`, …` with the hint
  "write `Int` in place of `a` … or make the body generic". When that type
  still contains variables (e.g. `b -> b`), the hint says "write the type the
  body needs" instead, rather than printing internal variable names as advice.
- **unified with an earlier-written variable of the same signature** gives
  `The type variables `a` and `b` in `second`'s signature are not
  independent: …`, reported at the later one.

Both carry code `annotated_tyvar_fixed` and are Warnings, so `--check` exit
codes do not change. The span is the variable's first occurrence in the
parameter annotations, the return annotation, or the bounds.

### Deliberate choices

- **Aliased pairs warn.** A signature `(a, b) -> a` whose body returns the
  `b` argument promises callers two independent types and gives them one.
  That is the same over-claim as fixing to `Int`, and rigid variables (the
  planned (a)) reject both, so warning on both now keeps (b) a faithful
  preview of (a). The measurement found 0 aliased sites, so the choice costs
  no noise.
- **Only written variables.** A variable must have a source occurrence in
  the signature. Unannotated parameters, and any annotation variables a
  desugar pass synthesises without a source name, are skipped.
- **Skipped after a body error.** When the function's body reported an Error
  (`Err.mark`/`Err.error_since`, lib/errors/errors.ml), its unifications are
  unreliable evidence, and the error is the diagnostic to read.
- Local `let x : a = …` annotations and lambda annotations are out of scope:
  their variables are not in `fn_tvars`.

## Stdlib changes

`OrderedMap.keys`/`values`/`from_list` used `fn (k, _) -> k`, a
two-parameter lambda, where a pair callback was expected. The warning found
`values` (typed `List(b -> b)` for callers). `keys` and `from_list` were
hidden type errors (`from_list` also had `List.fold_left`'s arguments out of
order). All three now destructure the pair in a `match`. New
`test/stdlib/test_ordered_map.march` (Alcotest `ordered_map` group, plus a
`dune runtest` rule) is red on the pre-change stdlib and green after.

Behaviour identity: all 124 stdlib modules were `--check`ed with the
pre-change compiler + stdlib and the post-change ones, using separate HOMEs.
After normalizing paths and fresh type-variable names, the only difference
is `ordered_map.march`: its 5 errors are gone and it exits 0. No stdlib module
gains a warning.

## Tests

`test/test_compiler.ml` group `annotated_tyvar_fixed` (7 cases): the todo's
example warns (span, message, hint); a generic set (`id`, `swap`, recursive
`len`, `apply`, `pick`) does not; unannotated parameters do not; an aliased
pair warns; the two-parameter-lambda shape warns; a body with a type error
does not. On the pre-change typechecker the three positive cases fail and the
three negative controls pass.

## Follow-up landed the same day

`specs/progress/2026-09-22-curried-lambda-over-tuple-diagnostic.md` gives
`fn (k, v) -> …` passed where a pair callback is expected its own error
(`curried_lambda_over_tuple`). That is the shape behind the OrderedMap bugs
this warning found. The two do not overlap: the error fires first and this
warning is skipped for a body with an error, so the user sees the diagnostic
that names the actual mistake. `test_tyvar_warning_yields_to_curried_lambda_error`
pins that.
