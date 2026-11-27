`[P3]` Flake: `forge test --upgrade-from` case 4 ("an upgrade that drops ...") passes nothing dropped

`forge/test/test_upgrade_from.ml` `test_dropping_upgrade_fails` expects forge to exit 1 because
the `drops` fixture's Tally loses its Legacy handler with no `migrate_msg`, so a Legacy message
the old feeder sends after Tally moves is dropped and counted. It assumes the old feeder is
still sending when Tally moves. If the feeder finishes first, nothing is dropped, the counters
read 0 and forge exits 0: `forge exits 1 / Expected: 1 / Received: 0`.

Seen once, CI `test (ubuntu-24.04, forge)` on PR #1342 (head bcbce60c3), run
https://github.com/march-language/march/actions/runs/45914265945 (the case ran in 1,114 s
there, three at a time beside the other upgrade cases). The same case passed three times out of
three locally on that branch (arm64 macOS, about 93 s each), and nothing on the branch touches
the actor runtime or the upgrade driver.

Fix direction: make the drop deterministic, e.g. have the feeder keep sending Legacy messages
until the drain report shows Tally on the new code (or for a fixed number of messages after the
switch), rather than relying on it still being mid-stream.
