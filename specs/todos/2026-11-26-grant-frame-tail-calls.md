`[P3]` A call into a kept grant frame is never a tail call (2026-11-26)

Split out of `progress/2026-11-26-ocap-framed-mutual-tail-recursion.md`, whose
function-frame half is fixed (`Auth_rt.hop_tail_calls`). The dependency-grant half is
not: a granted package's function `f` is a wrapper that enters the grant around
`f$grant`, and the restore after the call means a crossing into the package costs one
stack frame, whatever the call's position. `hop_tail_calls` skips granted functions,
because entering their wrapper also enters the grant, which `Authority.frame_in_force`
on a function layer does not see.

Pinned by `test/cap_conformance/grant_callback_reentry.march` at 1,000 deep (3,000
overflows compiled at `--opt 0` and under node). Raise it to 10,000 when this is fixed.

Fix sketch: the same shape as `hop_tail_calls`, testing the grant's layer instead
(`Authority.frame_in_force` on `grant_layer_fn_of p`), for a tail call to a kept P
function from code already under that grant.
