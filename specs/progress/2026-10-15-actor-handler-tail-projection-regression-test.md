`[P1]` Regression test for #705: an actor handler ending in a projected field read freed state

Filed as march-language/march#705 (2026-09-29), found through depot's
connection pool (`on Checkout ... result.new_state`): an actor handler whose
result is `result.new_state`, a field of a helper's result record, compiled to
a read after Perceus released `result`, so the actor kept its old state
(`b-0 b-0 b-0 b-0` compiled, `b-0 b-1 b-2 b-3` interpreted).

Already fixed in general by e7f16a50b (2026-09-30, "perceus: dup a tail-position
field projection before the aggregate scope-end drop";
`specs/progress/2026-09-30-compiled-tuple-destructure-leaks-moved-fields.md`),
whose own test pinned a `match`-arm shape, not the actor handler. Verified by
building the compiler at e7f16a50b~1 (prints `b-0 b-0 b-0 b-0`) and at e7f16a50b
(correct).

`test/native/actor_handler_tail_field_projection.march` pins the issue's shape,
with and without a reply, on both backends against the interpreter's output; it
is red on the e7f16a50b~1 compiler.
