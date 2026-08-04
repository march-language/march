# `--cap-strict` capability ceiling — remaining follow-ups

Shipped 2026-08-04: `--cap-strict`, per-module attribution, and the three
items closed below. See `specs/progress/2026-08-04-cap-ceiling-strict.md`.

## Closed 2026-08-04

- **`println` not tripping Check 1b — root-caused and fixed.** It was never
  about `println`. `prelude.march` is unwrapped into GLOBAL scope, so its
  declarations are prepended to the ENTRY module's decl list. Check 1b dedups
  its body scan to one `(capability, span)` pair and keeps the FIRST, so any
  capability prelude also uses got a *prelude* span — which the driver's
  `is_user_file` filter then discarded. The warning was generated and thrown
  away.

  That suppressed Check 1b for **every capability the standard library
  happens to use**, not just `IO.Console`. `file_exists` warned only because
  prelude never calls it. Fixed by `Typecheck.stdlib_source_files` +
  `span_is_stdlib`, filtering stdlib-sourced uses out of the body scan.
  Default-build warnings are now a faithful preview of what `--cap-strict`
  demands. Two test fixtures needed `needs IO.Console` added — the migration
  burden is real and immediate.

- **`ECallPtr` witness hunt — no witness found, and there is a reason.** The
  atom scan added with `--cap-strict` catches a capability at the point its
  name is *mentioned*, not where it is invoked. Tried and all attributed
  correctly: builtin returned from a branch as a function value; builtin
  stored in a `Cons` cell, pattern-matched out, and called through a function
  parameter. A capability must be named somewhere to be obtained, and every
  naming site is an atom position. `Cap_ceiling.Unattributed` remains as a
  fail-closed backstop with no known trigger — worth revisiting if
  reflection, dynamic module loading, or runtime-provided closures ever land.

- **`forge cap inspect --strict`.** Binaries now carry a second per-module
  channel, `__march_capdecl_<CAP>__<OWNER>` (what each module declared),
  alongside `__march_capfrom_` (what it was measured to use). The ceiling can
  therefore be re-checked on a binary you did not build. Fails closed when
  the attribution channel is absent rather than reporting a clean ceiling for
  a binary whose ceiling cannot be read.

## Open

- [ ] **`--cap-strict` is compile-only, not available to `--check`.** The
  check needs TIR and `--check` stops after typecheck, so editors and
  `forge check` cannot preview ceiling violations. With the `println` fix
  above, the *source-level warnings* are now a much better proxy than they
  were — they cover the direct-builtin route faithfully — but they still miss
  the stdlib-mediated and value-passing routes, which only the TIR channel
  sees. Either lower far enough under a flag, or document strict as a build
  gate and lean on the warnings for editor feedback.

- [ ] **No migration autofix.** `--cap-strict` rejects most existing code,
  including this repo's own `examples/`, because `needs IO.Console` is almost
  never declared. Check 1b already emits the right `FInsert` autofix, and
  with the stdlib-span fix it now fires for every direct-builtin case, so a
  `forge fix`-style bulk apply is mostly wiring. The stdlib-mediated route
  still has no source-level diagnostic to hang a fix on.

- [ ] **Per-dependency capability budgets in `forge.toml`** — the original
  motivation, now unblocked on both sides: attribution names the module and
  the ceiling proves the module stays inside its declaration, verifiable from
  source or from the artifact. What remains is the module→package mapping,
  which `forge/lib/cap_package.ml` already computes from source. Design note
  from the earlier analysis: check budgets against *reachability*, not
  against the dependency's declared package set — the latter is stricter than
  reality and would train people to widen budgets until they mean nothing.

- [ ] **Ceiling checking is per-module, so a package can still launder
  authority internally.** Module A of a dependency may declare
  `needs IO.FileRead` legitimately while module B calls A. Both stay inside
  their own ceilings; the package as a whole holds the capability. This is
  correct behaviour for the module rule, but it means "which package can
  touch my files" needs the package-level roll-up above, not just the module
  check.
