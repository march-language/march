# Road to 1.0, Phase 1: the normative claim pages

**Landed:** 2026-10-30. Plan: `specs/plans/2026-09-28-road-to-1.0.md`, "Sequence
(2026-10-30)", Phase 1.

## What exists now

Seven new `specs/lang/` chapters, generated into `docs/` and linked from the site's
landing page ("What 1.0 promises") and the reference index:

- `claim-deploys.md`, `claim-capabilities.md`, `claim-performance.md`,
  `claim-refinements.md`: one per pillar. Each states the guarantee, its assumptions, what
  is not claimed, and the CI gate, with every missing gate written as "planned".
- `capability-threat-model.md`: the single capability threat model.
- `platforms.md`: tier 1/2/3.
- `compatibility.md`: the 1.x promise, deprecation process and stability tiers.

## Checked against the code, 2026-10-30

Each claim was checked by running the compiler built from this branch, not taken from the
older pages:

- An undeclared direct builtin call (`file_write` in a module declaring only
  `IO.Console`) is a `cap_needs` **error** under `--check`, `--compile` and
  `--no-cap-strict`, even when unreached from `main`. The same call through `File.write` is
  a `cap_ceiling` error under `--check`. `docs/capability-audit.md` still said "warning"
  (stale since `progress/2026-08-06-cap-severity-flip.md`); fixed.
- An `extern` block without `needs IO.Foreign` is still only a warning
  (`extern_needs_foreign`), and reaching it under a grant narrower than `Cap(IO)` is a
  `cap_grant_exceeded` error.
- `check_fn_grants` (R1 stage C) is gone from `lib/typecheck/` (removed 2026-08-13); the
  provable-sandbox design still called it built. It now carries a pointer to the threat
  model.
- `--cap-sandbox` exits 70 on an unsupported platform or architecture
  (`runtime/march_runtime.c`, `march_sandbox_install`).
- A user `@[assume]` is accepted under `cap verified` and counted as `trusted` by
  `--refine-report`, but no flag names it (`--refine-report-sites` lists skips only). So
  "cap verified lists every assumption" (decided 2026-10-30) is written as planned.
- With z3 missing (`MARCH_Z3=/nonexistent`, fresh `HOME`), a `cap verified` module whose
  obligation needs the solver fails as `solver-undecided`, with no "z3 missing" message.
  **Trap found while checking:** with a warm `HOME`, the same run exited 0, because the
  build cache replayed the earlier run's pass. The cache does not record whether z3 was
  available. Stated as an assumption on the refinement claim page; not filed separately
  because the plan's z3-bundling item (version in the cache key) covers it.
- `CtlFetch` exists only in `test/session/control_peers.march`; the generated control
  plane (`lib/desugar/control_wiring.march`) has `Ctl` only, so the compatibility page
  names `Ctl`.
- CI runs no test suite on linux-aarch64 (`.github/workflows/README.md`), so the platform
  page lists that as the one tier-1 gap.

## Left for later phases

The pages name every unbuilt gate. The Int overflow trap (Phase 2, in progress elsewhere)
changes the refinement claim's overflow assumption: update `claim-refinements.md` when it
lands. Performance targets per benchmark are still an open owner decision (TBD in
`claim-performance.md`).
