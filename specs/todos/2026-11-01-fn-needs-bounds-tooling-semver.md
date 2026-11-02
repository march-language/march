`[P2]` Per-function `needs` bounds, phase 3: semver, audit and editor tooling

Road to 1.0 decision 3 (2026-09-29): a declared bound is public API. Widening one is a
major bump in forge's semver check and shows in `forge audit` upgrade diffs (the cap diff
`forge add`/`outdated` already gate on). Also: `forge fix` writes the tightest bound;
LSP hover shows the inferred row for any function; `forge doc` renders the bound in the
signature; `forge audit` reports per-function rows.

Interface bounds (phase 2, done 2026-11-02): ANY change to an interface method's bound is
a major bump, not only widening. Widening breaks callers relying on the guarantee;
narrowing breaks implementors whose impls no longer fit. That includes the four built-in
interfaces' `needs ()`.
