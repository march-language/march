`[P2]` Diagnostics for capabilities: passing `Cap(IO.Console)` where `Cap(IO.FileRead)` is needed is
reported as a plain `type_mismatch` (plus `cap_grant_exceeded`); IO in an actor handler reports `cap_ceiling`
on `mod Main` and `cap_needs` on `main`'s param, naming neither the handler nor `println`; one missing
authority yields up to three reports. Target: a capability-specific message with the lattice relation, use-site
primary span, named context, one merged fix, explain pages. specs/plans/2026-11-02-diagnostics-depth-plan.md §F1.
