# Diagnose reports capped snapshots

**Fixed 2026-10-08.** `forge diagnose` now adds capped actor and crash sections
to `coverage.partial` as `shown N of total`. `Diagnose.coverage(before, after)`
exposes the same information to March programs, considering either endpoint of
the sampling window.

**Verification:** the focused Forge Diagnose suite covers a synthetic capped
envelope, and the shared native Diagnose fixture exercises the March API on
both compiled and interpreted backends.
