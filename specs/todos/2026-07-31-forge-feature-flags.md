`[P3]` # forge: optional dependencies / feature flags — needs a language decision first

Split 2026-09-18 out of `2026-07-31-p1-tooling-forge-build-tool.md` per
`specs/2026-09-18-forge-p1-design.md` §2, which lays out the options.

This is a language question before it is a forge feature, and a design written
now would be a design for a decision nobody has made. The three options:

- **A. Cargo-style additive features** + conditional compilation. Familiar, and
  the most expensive: March has no `cfg`, and one would touch refinement
  checking, the capability ceiling, the exhaustive-stdlib manifest, mono and the
  LSP.
- **B. Optional deps gated by the module system.** No language change; coarser.
- **C. Capability-shaped features.** Distinctive and on-brand, but it gates
  *effects*, not *code presence*, so it does not remove a dependency.

**First step:** establish which question users are actually asking — smaller
binaries and fewer deps (A or B) or finer-grained permission (C). Do not design
A speculatively.

`[P3]`: no user is blocked on it.
