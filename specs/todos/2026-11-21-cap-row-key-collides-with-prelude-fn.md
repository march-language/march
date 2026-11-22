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
