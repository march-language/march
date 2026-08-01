- String refinements integrated with the predicate-vocabulary foundation and
  ADT constructor-tag refinements (`lib/refinecheck/refine_check.ml`,
  2026-07-24). `rparam` now carries a single `sort : string option` covering
  `Int`/`String`/ADT instead of the two branches' parallel flags; `smt_of`
  carries both `?resolve_tester` and `?resolve_str_lit`; path conditions
  resolve in the caller's namespace *and* see the string-literal table. One
  hazard existed only in the combination: `path_resolve_var` would declare a
  `$Str`-sorted caller variable a second time as `Int`, which makes z3 emit an
  error line and silently disables refinement checking for the rest of the
  compilation — it now yields the string-sorted constant, with a
  drop-`Int`-decls-for-`$Str`-symbols guard at VC assembly as backstop. The
  measure, ADT-datatype and `$Str` preambles compose in any combination
  (verified by teeing the solver channel: zero `(error` lines, and a later
  violation in the same file still reported). `test_refinecheck` = 124 tests,
  19/19 suites registered.
