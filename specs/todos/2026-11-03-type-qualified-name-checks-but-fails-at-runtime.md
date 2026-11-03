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
