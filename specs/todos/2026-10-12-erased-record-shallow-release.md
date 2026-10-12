# `[P3]` An erased record released by a generic dec leaks its heap fields

Found while fixing `specs/progress/2026-10-12-erased-param-field-read-leak.md`.

A lambda whose parameter stays erased (`TVar`) because the container it is
stored in hides the element type now releases that parameter after reading a
field of it. The release is a plain `dec_rc` on a `TVar`, which the runtime
implements as `march_decrc`: it frees ONE cell and never its children, since
only the compiler knows a value's layout. When the lambda holds the last
reference (the caller handed over a record it no longer needs), the record's
heap fields (a String, a List) are never released.

Repro: `test/native/erased_param_field_read_leak_probe.march`'s `fresh` leg
with `rows(i)` (String names) instead of `scalar_rows(i)`: 3 objects per
iteration (the three name strings), against 6 before the fix.

The same shallow release applies to any erased value Perceus drops with a
plain `dec_rc` (the unused-parameter drop in `insert_dead_apply_param_drops`,
`Clo_flags`' trampoline release for generic named fns). Possible directions:
specialise such lambdas from the field set they read; or register a typed
drop per closure parameter type the way `march_clo_register_drops` registers
capture releases.
