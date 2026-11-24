# ocap: should `needs` frames also keep their frame on an unresolved interface call?

Logged 2026-11-23 by ocap phase 6 (Task 4 fix round 1, I2; Task 8 measurement). An open design
question, not a known bug.

A granted package's function keeps its run-time grant frame when it reaches, by direct calls,
an interface method that lowering left generic (`Auth_rt.reaches_indirect_or_dispatch`):
mono may resolve it to an impl outside the package, such as the app's, which is not the
package's proven code. Phase 4's `needs`-clause frames and phase 5's restricts use the
narrower `reaches_indirect_call` (calls of function values only). Using the wider seed there
too is a one-line switch, but it re-frames existing `needs` functions and restricts that call
generic interface methods, so it moves IR for programs with no grants, which phase 6's
"byte-identical with no grants" budget ruled out.

A cost of the wider rule, measured in Task 8: under an unscoped grant, a proven package
function that calls `println` keeps its native frame (`MARCH_DUMP_GRANT_FRAMES` shows
`proven=true wrapped=true`), because the prelude's polymorphic `println` calls `show(x)`.
`println(s)` on a `String` resolves to `String`'s impl after mono, so the frame is not needed
there; it costs one boundary frame (about 16 ns, `bench/grant_enter.march`) per call.

What to decide: whether a `needs` frame or a restrict dropped by the narrower rule can be
reached by an app impl through generic code in a way that matters (if so, switch it and
accept the IR churn), and whether the drop rule can look through calls whose type arguments
are already concrete at the call site (`show` on a `String`), which would drop the `println`
frame above.
