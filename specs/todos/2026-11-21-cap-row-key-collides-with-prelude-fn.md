# A user top-level fn named like a Prelude fn shares its capability row (2026-11-21)

Found by the ocap phase 5 final review (pre-existing, not introduced by phase 5).

A program that declares a top-level `fn map()` that reads a file, and elsewhere writes
`restrict IO.Console do println("x") end`, is refused with "`println` needs `IO.FileRead`".
`MARCH_DUMP_CAP_ROWS=1` shows the program's `map` and Prelude's `map` (stdlib/prelude.march)
share one bare row key (`cap-row map caps=[IO.FileRead] deps=[f,xs]`); Prelude's `show`
reaches `map`, so `println` inherits `IO.FileRead`. The same keying also feeds per-function
`needs` bounds and `march caps`, so they over-report the same way.

What to do: key capability rows by module-qualified name for Prelude/stdlib fns (as other
modules' fns already are), and pin it with a `test_restrict_reach` case and a `needs`-bound
case using a user fn named `map`.

## To check when fixing (added 2026-11-23)

A reading of `record_body_caps` (lib/typecheck/typecheck_caps.ml, about line 1085) suggests the
shared key is also added to `env.stdlib_fns` when the Prelude function's span is seen, which
would make a user function of the same name transparent to the `--check` ceiling
(`check_stdlib_mediated_ceiling`), not only merge the rows. This is not confirmed: a user
`fn map` that calls `println` in a module with no `needs` line is still reported (`cap_needs`,
tried on a build of `4744a0830`). The ceiling path through a nested module was not tried. The
same bare-name match exists in lib/driver/cap_static.ml (`prelude_fns`); fix the three places
together.
