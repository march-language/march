# A cyclic type alias is an error, not a compiler hang

**Landed:** 2026-09-21. Follow-up to #558 (`<P>_<Role>.Entry`), which made
`Ast.TDAlias` transparent.

## Problem

`surface_ty` (`lib/typecheck/typecheck_unify.ml`) expands an alias by resolving
its right-hand side, with no record of which aliases were already being expanded
on that path. `type A = A`, or a cycle `type A = B` / `type B = A`, recursed
forever: the compiler hung with no diagnostic.

This could not happen yet. The only `TDAlias` built anywhere is
`desugar_endpoints.ml`'s generated `Entry`, whose right-hand side is always an
`S_` state type, and the parser has no alias syntax (`type A = B` parses as a
variant with one nullary constructor `B`). The first person to add alias syntax
would have inherited the hang.

## Fix

`expanding_aliases` holds the aliases being expanded on the current path,
innermost first, and follows the pattern of the existing `expanding_records`
guard. A repeat reports ``"`A` is defined in terms of itself (`A` -> `B` -> `A`)."``
at the repeated mention and returns `TError`. The list is restored with
`Fun.protect`, so an alias used twice side by side (`(A, A)`) is not a cycle.

## Tests

`test/test_endpoints.ml`, `alias_cycles` (compiler suite, `endpoints`). No
source can produce a cyclic alias, so the test builds the `TDAlias` declarations
directly and puts them in front of a parsed module. It checks that `A = A` and
`A = B` / `B = A` are rejected with the cycle message, and that a non-cyclic
chain `A = B` / `B = C` used as `(A, A)` is accepted.

The test is not vacuous: with the guard disabled, the case was still running
after 60s, compared with 0.02s with the guard. A module's aliases are keyed by
their qualified name only. A first draft of the test used bare `A`, which
resolved to the nominal type and never reached the alias path: the reject cases
got no error, and the accept case would have passed vacuously. Every mention in
the test is therefore `Main.A`.
