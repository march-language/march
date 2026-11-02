`[P2]` Per-function `needs` bounds, phase 3: semver, audit and editor tooling

Road to 1.0 decision 3 (2026-09-29): a declared bound is public API. Widening one is a
major bump in forge's semver check and shows in `forge audit` upgrade diffs (the cap diff
`forge add`/`outdated` already gate on). Also: `forge fix` writes the tightest bound;
LSP hover shows the inferred row for any function; `forge doc` renders the bound in the
signature; `forge audit` reports per-function rows.
