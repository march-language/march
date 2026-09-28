# `[P1]` DONE A borrowed field projection outlived its record's owner (compiled use-after-free)

Filed and fixed 2026-09-28 (dd step 12a). First seen as a scripted session peer in
`test/session/control_peers.march` printing another string's bytes for a received
order's `action` field, compiled only.

## The bug

```march
type R = { a : String, b : String, n : Int }
type R2 = { a : String, b : String }
pfn copy(r : R) : R2 do { a: r.a, b: r.b } end          -- takes r, drops it
pfn blen(r : R2) : Int do String.byte_size(r.b) end
pfn show(r : R) : String do
  int_to_string(r.n) ++ ": " ++ r.a ++ " / " ++ r.b ++ " / " ++ int_to_string(blen(copy(r)))
end
```

Interpreted: `7: alpha1 / beta2 / 5`. Compiled: `7: :  / 5 / 5`. Perceus
(`lib/tir/perceus_core.ml`, the `ELet` rule) classifies `let x = r.a` as a BORROWED
field (no refcount of its own; "the record owner manages it") whenever `r` is still in
scope or used again in the body. Here the later use is `copy(r)`, which CONSUMES `r`:
`show` owns `r` and hands it over, and `copy`'s drop releases `r.a` and `r.b`. The
concatenation then read freed strings, and the next allocations reused their memory.
Any function that reads a field into a local, passes the record to a consuming call,
then uses the local, was exposed.

In the session fixture the shape was `show_order(o)`, which read `o.action` and
`o.want`, then called `Control.order_lines(order_of(o))`; the inlined `order_of`
consumed `o`.

## The fix

In the `ELet` rule, `dup_owned_field`: when the projection's source is owned here (not
live after the scope, not itself a borrowed field, not a closure capture, `Unr`) and the
body uses it other than as a projection source (`used_only_as_field_source` is false),
the binding is NOT borrowed. It takes its own reference (`inc_rc` right after the
projection) and is released like any owned binding, at its last use. A source that is
only ever projected keeps the borrowed classification: nothing in the body can release
it before the binding's scope ends.

## Tests

- `test/test_codegen.ml`, group `borrowed_field_owner_consumed`: the program above,
  compiled, plus 2000 iterations under `march_live_allocs` (delta 0, so an over-dup
  would fail as a leak). RED with the rule disabled (`7: :  / 5 / 5`).
- `test/session/control_peers.march`: the scripted Agent's `Expect_Apply` callback
  prints the order's String fields again, identical on both backends.
