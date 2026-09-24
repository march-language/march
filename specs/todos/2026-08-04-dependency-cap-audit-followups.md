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

- [ ] **Wire into `forge add` / `forge outdated`.** Today the check is
  explicit (`forge audit`). The moment that matters most is when a
  dependency is added or upgraded — surface the delta there, and require
  acknowledgement before writing the lockfile. That is the xz/event-stream
  moment. Needs the speed item first, or every `forge add` pays minutes. (The cache has landed;
  a cold `forge add` still pays one `march caps` run for the new dependency.)

- [ ] **Registry cross-check.** Once the registry stores capability sets
  (`specs/todos/2026-08-03-registry-capability-notarization.md`), compare the
  locally computed set against the published one. A mismatch means the
  published artifact does not correspond to the published source — a stronger
  signal than either check alone.
