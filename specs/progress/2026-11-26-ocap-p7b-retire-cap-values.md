# Object capabilities, phase 7b: `Cap(IO.*)` values retired (2026-11-26)

Plan: `specs/plans/2026-11-24-ocap-p7-mock-plan.md` (Tasks 7–9; Q1–Q8 approved as
recommended). Design: `specs/2026-11-10-object-capability-design.md` §11, §14, §17, §21.
Follows phase 7a (`2026-11-24-ocap-p7a-mock.md`) and its gap fixes
(`2026-11-26-ocap-p7a-actor-kinds-roles-restrict.md`).

## What landed

- **Retirement diagnostics** (`lib/typecheck/typecheck_retire.ml`, run at the end of
  `check_module`):
  - `deprecated_main_cap` (warning, one release): `fn main(c : Cap(K))`. Its fix (machine
    applicable, verified) replaces the parameter list with `()` and writes `needs K` before
    the `do`; it adds no return type, since a `main` without one returns its last
    expression.
  - `cap_param_retired` (error): a `Cap(IO.X)` type anywhere else. For a named function's
    parameters the fix deletes them and the argument at every same-file call.
  - `cap_narrow_retired` (error), not repeated inside an argument a fix already deletes.
  - `mint_cap()` takes no argument (`mint_cap(c)` is `mint_cap_invalid` with a fix);
    `root_cap` is refused everywhere (`root_cap_reference`, new message); the
    `root_cap_allowed` exemption for tests, setup blocks and the REPL is gone.
- **`main`'s `needs` clause is judged as its grant.** A function-level bound refuses
  untraceable calls; `main`'s does not (design §D3, the program is closed at `main`), as
  its `Cap` parameters never did. Without this the migration failed programs that call a
  closure from a record field.
- **A function `needs` clause counts as a use of the module line it names**
  (`unused_needs`): `cap_bound_needs` requires that line, and `main` now names kinds the
  program reaches only through other modules (`IO.Foreign` behind `Js.Dom`).
- **Main-grant diagnostics recommend `needs`** (`cap_grant`, `cap_grant_exceeded`,
  `role_grant_too_wide`): the fix appends to `main`'s clause, or adds a module `needs`
  line when that line is `main`'s request. The old fix could write `fn main(, ...)`
  (closes `2026-11-19-ocap-cap-grant-exceeded-invalid-fix.md`). The `cap_mismatch` and
  unify helps no longer suggest `cap_narrow`.
- **Choreography** (`lib/desugar/desugar_endpoints.ml`): every body is
  `(Cap(Session.Live), Entry) -> Yield`; `run_`/`host_`/`host_*_or` take no `Cap(IO)`;
  cluster, offer, initiate and hosted fronts take no grant; hosted `start` is `(s)` /
  `(sid, s)`; `script`/`chaos` take no `Cap` parameters. The grant is a compile-time limit
  (the role walk); a generated `restrict` around `body(...)` would not bind, because a
  function value keeps the authority it was made under. Closes
  `2026-11-05-direct-runner-root-cap.md`.
- **Topology** (`lib/desugar/desugar_topology.ml`): a hook takes only the node; the
  generated `main` is `fn main() : () needs IO do`; adapters and the control plane lose
  `topology_io`. `lib/desugar/control_wiring.march` migrated.
- **Stdlib**: `SessionNode.run*`, `run_party`, `serve_party` take no `Cap(IO)`;
  `SessionNode.drain_epochs(soft, hard)` is a checked operation under `IO.Cluster`
  returning `Result((), CapError)`; the stdlib mints with `mint_cap()`.
- **Corpus**: about 1,250 `.march` files (tests, examples, benches, demos, forge
  fixtures and templates, the type corpus, the error corpus, the error tour) migrated by a
  one-off driver applying the compiler's own fixes through `--check-json` (verified fixes
  only), plus text rules for `main` in OCaml tests and markdown and for `run_R(io, ...)`.
  What it could not rewrite was finished by hand. Reject witnesses for the retired forms
  stay as written; accept witnesses show the same rule in the current form (see
  `specs/lang/types/INDEX.md`). Two fixtures keep the deprecated `main` on purpose:
  `test/native/main_cap_io.march` and `test/errors/deprecated_main_cap_1.march`.
- **Docs**: the capabilities, choreography, clustering, actors, linear-types, threat-model,
  type-system and safety chapters, the error pages, the error tour, the cookbook, the
  examples page and the README.

## Not done (todos)

- `2026-11-26-ocap-role-grant-run-time-limit.md`: a role's grant is enforced at compile
  time only.
- `2026-11-26-ocap-remove-deprecated-main-cap-form.md`: remove the deprecated `main` form
  next release, with the now-dead `cap_narrow` typing machinery and `Cap(IO)` cases in the
  checker.
