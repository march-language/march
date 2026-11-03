# `Diagnose`: queued mailbox growth no longer raises `rc.climb`

`forge diagnose` and `Diagnose.findings` both considered every increase in
`live_objects` when deciding whether reference counts were climbing. A growing
mailbox is intentionally retained work and is already reported as
`mailbox.growth`, so a backed-up actor produced a misleading second leak
warning.

Both implementations now subtract the net `queued_messages` increase across
the snapshot window before applying the `rc.climb` threshold. A real residual
heap increase still reports `rc.climb`; a window whose entire increase is
queued messages reports only `mailbox.growth`.

## Verification

- Added `rc_climb_mailbox_growth` to the shared Diagnose fixture corpus. It
  crosses the raw live-object threshold solely through 120 queued messages and
  expects only `mailbox.growth/critical`.
- `dune exec --root . forge/test/test_diagnose.exe` — 15 tests passed.
- `dune build --root . test/native_diagnose_fixtures.out
  test/interp_diagnose_fixtures.out`, with both outputs diffing cleanly against
  the shared expected fixture file.
