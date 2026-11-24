# ocap p6: should an app impl called from a granted package run under the grant?

Logged 2026-11-22 by ocap phase 6, Task 4 fix round 1 (review finding I2).

A granted package's generic code (`fn describe(x) do "<" ++ show(x) ++ ">" end`) calls an
interface method that mono resolves to the caller's impl (the app's `impl Show(Probe)`). The
impl is the app's code, passed in by type rather than by value. Design §5 says a callback runs
with its caller's authority, which argues it should *not* be narrowed by the grant. But today
it runs inside the package fn's grant frame, so it is.

What Task 4 does for now: `Auth_rt.grants` counts an unresolved interface-method call as an
indirect call (`reaches_indirect_or_dispatch`). Such a fn keeps its frame even when it is
proven under an unscoped grant, so the impl runs under the grant consistently, whatever the
grant's scope, and the same way the always-framing interpreter will run it. Pinned by
`test_dep_grants` `frames` "an app impl reached from generic package code keeps the frame",
which expects `<refused>`.

Open question: give a dispatch into an impl outside the package the caller's authority, as a
function value gets its maker's. Doing that needs mono-time knowledge of which impl a call
resolves to (only mono knows), e.g. an impl-call trampoline that restores the authority saved
at the package boundary. Decide before Task 6's five-mode fixtures pin either behaviour across
runtimes.
