# Refinement predicates: zero-argument constant functions as bounds

Filed and closed 2026-09-04. Reported as G78 in `cube_forge`'s `GAPS.md`.

## The bug

`fn index(x : {Int | 0 <= _ && _ < size_x()})` with `fn size_x() : Int do 128 end`
warned "`size_x` is not a measure or known predicate … Annotate the function
`@[measure]`" and filed an unreflectable-predicate hint at every call site.
Taking the warning's advice removed the warning and changed nothing else:
the call sites stayed unverified, now silently.

Root cause: two gates disagreed about what `@[measure]` means.
`Refine_encode.is_measure` (the predicate vocabulary, populated from every
`@[measure]`-annotated `DFn`) accepted the name; `build_measure_preamble` /
`resolve_measure` only ever reflect a measure as `m(arg)`, so a nullary (or
multi-parameter) measure had no reflection at all, and the obligation died as
`Unreflectable_predicate`.

## What landed

1. **Constant-function folding** (`Refine_encode.register_const_fns`,
   `fold_const_body`, `const_fns`). Once per `check_module`, every single-
   clause unguarded `fn f()` whose body folds — Int/Bool literals, `+ - *
   negate`, `&& || not`, calls to other constant functions (cycle-safe) — is
   registered under its bare name and every module-qualified suffix
   (`size`, `World.size`, `M.World.size`). `smt_of_r` reflects
   `EApp (EVar f, [])` to the literal. `known_predicate_fn` includes these
   names, so the vocabulary warning no longer fires. `/` and `%` are excluded
   on purpose: a fold disagreeing with runtime truncation would assert a
   false fact.
   - Collisions (the stdlib is merged into the checked module): a spelling
     with several definitions folds only if they all agree; otherwise it is
     withdrawn with a reason.
   - A zero-argument function that does not fold lands in `const_fn_rejected`
     with the reason, and the vocabulary warning reports it instead of
     sending the user to `@[measure]`.
   - **Shadowing.** Folding runs wherever `smt_of_r` runs (guards, actuals,
     tails), and a local `let size_x = fn -> 7` in a body would make the
     top-level value a false fact. `Refine_check.visit_fn` now loads
     `const_shadowed` with every name the function binds (`fn_binders`) and
     `is_const_fn` refuses those; over-retiring costs a proof, never soundness.
     Pinned by the "local binding shadowing the constant's name" test, whose
     discriminating half puts 7 at top level and 128 in the local.

2. **The gate reconciliation** (`Refine_encode.measure_shape_error`). Run in
   `check_module` after `register_adt_names`, regardless of
   `--no-measure-axioms`: a `@[measure]` that does not take exactly one
   parameter is a hard error at the annotation, with the remedy, and is NOT
   added to `registered_measures`. Whether the parameter's type is a declared
   ADT is deliberately not gated: the P1b fixtures measure over an undeclared
   `Tree(a)` and symbolic fallback is a (weaker) translation — the first
   version of the gate required a declared ADT and broke `measures-p1b`.

## Behaviour change outside predicates

Three fixtures used `fn g() : Int do 5 end` as a deliberately unreflectable
tail/argument. Those now fold, so the fixtures take a parameter instead
(`test_refinecheck.ml`: "inline call to a non-refined function is skipped",
"a postcondition whose TAIL expression fails to reflect …", and its Tier-2
constructor-literal sibling). `takepos(plain())` with a constant negative
`plain` is now a definite violation, which is the correct verdict.

## Tests

`test/test_refinecheck.ml`, suite `const-fn-predicate` (13 cases): in/out of
bounds, exclusive bound, derived constant, Bool constant, qualified spelling
through desugar, no vocabulary warning, the non-constant reason, nullary and
two-parameter `@[measure]` errors, undeclared-type measure passes the gate,
shadowing, and "annotation rejected but the constant still verifies".

## Docs

`specs/lang/refinement-types.md` and `docs/refinement-types.md` (the site
copy): new "Constant functions as bounds" section and a gate bullet.
