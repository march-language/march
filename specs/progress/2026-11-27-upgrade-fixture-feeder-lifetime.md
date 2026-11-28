# Keep the Forge upgrade fixture sending through deployment

The old-version feeder in `forge/test/fixtures/upgrade` stopped after 300 sends.
A deployment that took more than about six seconds could see no old-format
messages, so the drop and conversion cases failed on their counters even
though all traffic-driver sessions passed.

The fixtures now keep sending one message every 20 ms until Tally stops
accepting messages. The drop and migration overlays still send their respective
message formats. A seven-second delay before the traffic driver signals
readiness reproduces the original failure and exercises the fix.
