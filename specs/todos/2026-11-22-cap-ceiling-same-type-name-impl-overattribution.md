# Module ceiling charges a same-named impl of another module's type (2026-11-22)

Found while testing ocap phase 6 Task 3 (fix round 3). An app declares
`type Box = MyBox(Int)`, its own `interface Speak` with `announce`, and
`impl Speak(Box)`, and calls `announce(MyBox(1))`. A dependency on
`MARCH_LIB_PATH` declares `Loud.Box`, an `interface Announce` with a method also
named `announce`, and a printing `impl Announce(Box)`. `march --check` reports
`cap_ceiling`: "Module `Main` uses `IO.Console`". This happens with no dependency
grants at all. The program prints `mine` both interpreted and compiled, so the
attribution on lowered TIR is wrong, not the program.

Fixture: `test/dep_grants/apps/own_box/main.march` with
`test/dep_grants/deps/loud` (the dep_grants suite asserts only that no
`dep_grant_*` diagnostic is produced for it).

What to do: find where the TIR capability attribution (`lib/tir/cap_attrib.ml`)
or the impl mangling it reads keys impls by short type name and method, and
qualify it the way lowering does when a short type name is declared twice.
