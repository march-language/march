`[P3]` Show the run-time bound of a value created inside a `restrict` (2026-11-24)

A value a call returns inside a `restrict` keeps the type its function declares: the type
does not show the block's narrowing (design `specs/2026-11-11-ocap-capture-checking-design.md`
§6.2), though the run-time layer applies it. The design lets tooling print that bound as a
note ("created inside `restrict` at line 28; at run time at most ..."). Not built. The capture
pass tracks the static authority at each creation site (`ctx.auth` in
`lib/typecheck/capture.ml`) but not at call sites; the note needs the authority at the call
recorded beside the binding.
