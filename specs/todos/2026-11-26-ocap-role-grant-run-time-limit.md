`[P3]` A role's grant is a compile-time limit only (2026-11-26)

Since ocap phase 7b (`specs/progress/2026-11-26-ocap-p7b-retire-cap-values.md`) a
choreography `role R needs ...` adds no `Cap` parameters; the role walk
(`Typecheck.check_role_grants`) bounds everything the body reaches at compile time, and
reports a body it cannot trace (`role_grant_unverified`) instead of refusing it.

At run time the body runs under the authority it was made under, like every function
value, so a body the walk cannot see (read from a record, received in a message) can use
whatever its creator could. Design §21 asks for "a limit around the role's body".

A generated `restrict` around the runner's call of `body(...)` does not do it: a function
value made outside the block keeps its outside authority (phase 4 capture, design §5,
`test/cap_conformance/restrict_closure_outside_called_inside`).

What it needs: a runtime primitive that calls a function value under its captured
authority intersected with a layer (`Authority.call_limited(layer, f, args)`), in every
runtime, used by the generated fronts. Then a conformance fixture: an untraceable body
that performs an operation outside its role's grant is refused at run time.
