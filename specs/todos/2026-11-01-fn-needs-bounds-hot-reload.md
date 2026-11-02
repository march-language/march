`[P2]` Per-function `needs` bounds, phase 4: hot reload may widen a bound only explicitly

Road to 1.0 decision 4 (2026-09-29): a hot patch that widens any declared bound is
refused unless the deploy authorises that widening explicitly (per function, alongside
`--grant-cap`), and the widening is recorded in the HCR audit log. Still capped by the
running program's `main` grant. Today a patch's bounds are checked at compile time only,
like the rest of the patch; nothing compares them with the running build's.
