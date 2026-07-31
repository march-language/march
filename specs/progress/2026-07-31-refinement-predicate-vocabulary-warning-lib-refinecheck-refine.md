- Refinement predicate-vocabulary warning: `lib/refinecheck/refine_check.ml`
  names the predicate vocabulary in one place (`predicate_operators`,
  `is_predicate_operator`, `known_predicate_fn` = operators ∪ `len` ∪
  registered `@[measure]`s) instead of leaving it scattered across
  `is_measure`/`is_nonneg_measure`/inline `"len"` checks, and adds
  `is_string_base`/`is_adt_base` base-type predicates for the ADT-tag and
  String-refinement features to dispatch on (no consumer yet). A predicate
  applying a name outside that vocabulary — e.g. `{Int | totally_bogus_fn(_) >
  0}`, which previously compiled clean and enforced nothing — now draws a
  Warning (never an Error; `--check` still exits 0) covering parameter,
  return, and local-binding refinements. Verified zero spurious warnings on a
  real stdlib-using program. `test_refinecheck.exe`: 94 tests, exit 0 (was
  86); `run_compiler`/`run_eval` both exit 0.
