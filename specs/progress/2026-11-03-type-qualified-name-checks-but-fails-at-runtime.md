`[P2]` `Int.to_string(5)` passes `march --check` but the interpreter fails with "unbound variable:
Int.to_string" and the compiled program prints `()`. `Int` is not a module; the typechecker's
dot-suffix fallback (the `EVar` case of `infer_expr`, `lib/typecheck/typecheck.ml`) strips the
qualifier and types the bare `to_string`, but neither backend resolves the qualified name the same
way. Present on main before 2026-11-02 (checked with a September build).

The 2026-11-02 fix for a qualifier naming nothing (`Lsit.length`,
`specs/progress/2026-11-02-qualified-builtin-fallback-accepts-unknown-module.md`) keeps this
fallback for a qualifier that names a TYPE, because tests and user code write `Int.to_string`
(`test/test_provenance.ml`, `test/test_cap_markers.ml`, `test/test_stdlib_suite.ml`).

Fix one of two ways: rewrite the type-qualified name to the bare name it typed as (so both backends
see `to_string`), or reject it with a specific message ("`Int` is a type, not a module: write
`int_to_string(n)` or `to_string(n)`") and migrate the tests. Repro:
`mod T do needs IO  fn main(cap : Cap(IO)) do println(Int.to_string(5)) end end`.

## Completed 2026-11-07

Chose the diagnostic alternative: after genuine qualified module/interface
resolution, a single type qualifier no longer enters the suffix fallback.
`Int.to_string(5)` now reports “`Int` is a type, not a module. Write
`to_string` without the type qualifier.” This also rejects first-class value
references and user-defined type/alias qualifiers. Actual exported module
members and bare functions continue to resolve normally. The existing
capability-marker, provenance and lint fixtures now use `int_to_string`.

Root cause was the typechecker accepting the bare suffix without rewriting
its immutable AST name; neither evaluator nor lowering had the same lookup.
The fix avoids introducing a second runtime name-resolution policy.

Verification:
- `scripts/triage.sh` reproduced interpreter exit 1 versus compiled exit 0
  with `()`; none of its optional-pass switches changed the divergence.
- New compiler regression failed before the fix because `Int.to_string(5)`
  was accepted. The `error_improvements` group passes after the fix, including
  direct calls, a value reference, a user ADT, an alias and valid module/bare
  function controls.
- `unknown_qualified_name_7` pins rendered and JSON diagnostics. All seven
  qualified-name corpus cases plus the style check pass.
- The original reproduction is rejected by `--check`, interpreter entry and
  `--compile` with the same diagnostic.
- The migrated unused-private-function lint regression, all 12 capability-marker
  cases, and compiled provenance/debug-info regression pass.

Compatibility: this deliberately rejects previously typechecked programs
whose type-qualified value names did not execute correctly. Type-qualified
constructors and genuine module/interface exports are unaffected.
