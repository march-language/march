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

Added 2026-11-19 (PR B final review):

- The `cap_grant_exceeded` chain also lost its last hop: test/errors/cap_grant_exceeded_2
  went from `main → slurp → File.read` to `main → slurp` with the source unchanged,
  because the per-function closures (which feed `cap_grant_exceeded`) now charge the
  entry-point call to the function that makes it (comment at the `entry_caps_of_expr`
  definition in lib/typecheck/typecheck_caps.ml).
- The real size of this item: the call-site reports of diagnostics plan F1/X3 are now
  reachable only from stdlib-spanned code, so `test/errors/cap_needs_10` and
  `role_grant_exceeded_1` pin output that no user program can produce. Restoring them
  for user code means charging entry-point calls at the call (see above), not a wording
  change.
