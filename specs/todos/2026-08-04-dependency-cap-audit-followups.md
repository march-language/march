# Dependency capability audit — follow-ups

Shipped 2026-08-04. `forge audit --inferred` was folded into `forge audit --inferred`
(#167 owns the dependency audit; the inferred extraction is the mode that
closes its declared-set gap). `march caps` is the underlying extractor. Design context: `specs/2026-08-03-forge-cap-audit-design.md` §4.3.

- [x] **Require a toolchain `march` that supports `caps`.** `Cmd_build.lib_path_env`
  prepends `~/.march/versions/<v>/bin` to `PATH`, so an installed compiler that
  predates the `caps` subcommand silently takes over: it treats `caps` as a
  filename, exits nonzero, and every dependency reports `NOT ANALYZABLE` with
  no hint that the toolchain is the problem. Probe for support once
  (`march caps` with no files should be a usage error, not "file not found")
  and fail with a version message instead. Cost me a full debugging cycle;
  it will cost a user more. Done 2026-09-24, see [../progress/2026-09-24-forge-audit-toolchain-cache-flag.md](../progress/2026-09-24-forge-audit-toolchain-cache-flag.md).

- [x] **Speed.** Each dependency is a separate `march caps` invocation that
  loads the whole stdlib and the dep's tree; four dependencies took minutes on
  forgepm. Options: reuse the `check_all` marker-cache idea (skip re-analysis
  when a dep's file contents and lib path are unchanged), or teach `march caps`
  to take several package roots in one run. The cache is the cheaper win and
  fits the existing pattern. (Shipped as the cache.) Done 2026-09-24, see [../progress/2026-09-24-forge-audit-toolchain-cache-flag.md](../progress/2026-09-24-forge-audit-toolchain-cache-flag.md).

- [x] **Dependencies that do not typecheck are common.** Of forgepm's four,
  two (`bastion`, `conduit`) are `NOT ANALYZABLE` — conduit has a genuine
  ambiguous-constructor error that reproduces under plain `march check`. The
  current behaviour is right (loud, never "no capabilities"), but it means the
  gate cannot be adopted until a project's dependency graph checks cleanly.
  Consider `--allow-unanalyzable` to record and gate on the analyzable subset
  while listing the rest, so a project can start using the check incrementally
  rather than needing a fully clean tree on day one. Done 2026-09-24, see [../progress/2026-09-24-forge-audit-toolchain-cache-flag.md](../progress/2026-09-24-forge-audit-toolchain-cache-flag.md).

- [x] **Wire into `forge add` / `forge outdated`.** Done 2026-09-28, see
  [../progress/2026-09-28-forge-add-outdated-cap-gate.md](../progress/2026-09-28-forge-add-outdated-cap-gate.md).
  `forge add` gates every dependency the add touched against forge.caps.lock
  (refuse + restore forge.toml/forge.lock, or `--accept-caps`), analyzing only
  those; `forge outdated` previews each upgrade's new capabilities.

- [ ] **`forge deps` after a hand-edited version bump is not gated.** Changing
  a version in forge.toml and running `forge deps` upgrades without the
  `forge add` check (`forge audit` in CI still fails on it). Gating it means
  deciding what an unacknowledged widening does to a `forge deps` that is also
  the offline/restore path, and which flag acknowledges it there.

- [ ] **Registry cross-check.** Once the registry stores capability sets
  (`specs/todos/2026-08-03-registry-capability-notarization.md`), compare the
  locally computed set against the published one. A mismatch means the
  published artifact does not correspond to the published source — a stronger
  signal than either check alone.
