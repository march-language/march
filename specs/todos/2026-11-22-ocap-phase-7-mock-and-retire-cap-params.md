`[P2]` Object capabilities phase 7b: retire `Cap(IO.*)`, `root_cap` and `cap_narrow` (2026-11-22)

Phase 7a (`specs/progress/2026-11-24-ocap-p7a-mock.md`) landed `mock`, removed `with_cap`
and the IO dictionaries, and made the witness APIs checked operations. What remains is PR
7b of `specs/plans/2026-11-24-ocap-p7-mock-plan.md` (Tasks 7–9):

- `fn main(c : Cap(IO.X))` accepted for one release with `deprecated_main_cap` and a
  machine fix to `fn main() : () needs IO.X`; `Cap(IO.*)` elsewhere, `root_cap` (outside
  the stdlib) and `cap_narrow` are errors with fixes (Q1).
- The diagnostics that still recommend a `Cap` parameter (`typecheck.ml`'s main-grant fix
  and hints) recommend a `needs` clause; closes
  `2026-11-19-ocap-cap-grant-exceeded-invalid-fix.md`.
- A choreography `role R needs ...` becomes a limit around the role's body; `run_<Role>`,
  `host_<Role>`, `SessionNode.run*` and `drain_epochs` lose their `Cap(IO)`; topology's
  generated `main` gets a `needs` clause. Closes `2026-11-05-direct-runner-root-cap.md`.
- `mint_cap` stops taking a `Cap(IO)` once `root_cap` is gone.
- Migrate the corpus (about 1,190 test files, `specs/lang/`, `docs/`, examples, benches,
  forge templates) and revise `specs/lang/capability-threat-model.md`.
