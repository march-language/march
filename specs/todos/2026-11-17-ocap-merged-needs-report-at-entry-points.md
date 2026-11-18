# Capability diagnostics are less precise through a stdlib entry point (2026-11-17)

Found by ocap phase 4 Task 8, which made the raw capability builtins
stdlib-only. The capability checker charges a capability at the CALL only for a
builtin (`builtin_cap_table`, `Typecheck_caps.cap_of_builtin_call`); a call of a
stdlib entry point (`File.write`) is charged through the function's capability
closure instead. User code now reaches every gated operation through an entry
point, so it gets the closure-path diagnostics:

- the merged missing-authority report (diagnostics plan X3/F1: one `cap_needs`
  error at the call, `main`'s grant as a label, both edits as one fix) splits into
  `cap_ceiling` at the module's `needs` line plus `cap_grant_exceeded` at `main`
  (docs/error-messages.md "Writing a file without saying so",
  test/errors/cap_grant_21);
- `cap_grant_exceeded` and `role_grant_exceeded` point at `main` / the role body
  with a chain (`main → save → File.write`) instead of at the call with "calls X
  here" labels (test/errors/cap_grant_exceeded_1, _3, docs "A role reaching past
  its grant").


test/errors/cap_needs_10 and role_grant_exceeded_1 keep a raw builtin call to pin
the precise reports, so they also draw `stdlib_internal`.

Task 8 charges the gated rows' entry points in the per-function capability
CLOSURES (`entry_cap_table`, so `march caps`, the hot-reload manifest and the
--cap-sandbox profile see them), but not in the diagnostic body scan. Tried in
Task 8 and backed out: charging them in the body scan too (`cap_of_builtin_call`). It restores
the merged report, but it also turns the deliberate wrapper-path `cap_ceiling`
reports (test/errors/cap_ceiling_2, _3: a nested module reaching
`IO.FileRead` through `File.read`) into `cap_needs`, and changes every existing
program's diagnostics, so it wants its own change and review. Ban lists by name
in `cap pure` / `cap deterministic` (`Typecheck_modcaps.pure_banned`) would need
the same entries for the call-level report, which the `needs` half
(issue #1180) currently stands in for.
