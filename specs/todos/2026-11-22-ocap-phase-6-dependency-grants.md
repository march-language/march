`[P2]` Object capabilities phase 6: dependency grants (2026-11-22)

Filed by the 2026-11-22 todo sweep: phase 6 of `specs/2026-11-10-object-capability-design.md`
(§10, §17) had no todo and no plan. Its prerequisites, phases 3 and 4, are on main; phase 5
(`restrict`, scope values) landed in #1309.

What it is: a dependency's entry in `forge.toml` carries a grant
(`weather = { version = "2.0", grant = [...] }`), and the grant is a limit around every function
defined in the dependency's package, checked at compile time and at run time.

Not started (checked on `40f901bab`): no dependency `grant` key in `forge/lib`, no plan under
`specs/plans/`.

Closes with it: `2026-08-04-cap-ceiling-follow-ups.md` (per-dependency budgets, a package
laundering authority internally). Related: `2026-08-04-dependency-cap-audit-followups.md`,
`2026-11-12-march-caps-misses-stdlib-mediated-caps.md` (the extractor the audit reads
under-reports), `2026-11-09-host-scope-phase-2.md` (hosts in `forge.caps.lock`).

Breaking for `forge.toml`, so it lands before the 1.0 freeze.
