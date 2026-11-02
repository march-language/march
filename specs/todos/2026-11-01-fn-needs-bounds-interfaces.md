`[P1]` Per-function `needs` bounds, phase 2: interface method bounds

Road to 1.0 decision 2 (2026-09-29): an interface method signature may carry a `needs`
bound, and every impl of it is checked against it. Optional per interface; must land
before 1.0, since adding it later breaks impls. Phase 1
(`specs/progress/2026-11-01-per-function-needs-bounds-phase1.md`) checks a bound written
on an impl method itself; nothing yet ties it to the interface.

To do: grammar for `fn name : a -> b needs IO.X` in an interface body (and tree-sitter);
record the bound per (interface, method); check each impl method's row against the
interface's bound (an impl's own bound must be within it); a call dispatched through the
interface is then bounded too. Measure on the stdlib's interfaces first.

Implementation plan (2026-11-02): `specs/plans/2026-11-02-interface-needs-bounds.md`.
