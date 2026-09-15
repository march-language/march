# Two-node scenario `skew`: a peer's load report is aged on the receiver's clock

Shipped 2026-09-15, closing the `skew` part of
[[2026-09-14-two-node-scenarios-partition-skew-monitor]] (which stays open for
`partition` and the Docker variant).

## What the scenario pins

`test/two_node/skew`: node-b runs with `MARCH_CLOCK_SKEW_MS=30000`, a knob read by the
fixture's own `now()` (never the runtime: the skew is the scenario's). After its first
ack it piggybacks one `SwimGossipLoad` stamped with its skewed clock, then runs plain
SWIM. node-a, clock correct, prints booleans only: the report is fresh on arrival, and
stale 11 s later (`SwimDriver.load_stale_ms` is 10 s). Picked up by CI through
`scripts/two-node.sh --list`.

## The outcome decided the question the todo left open

The todo asked whether `load_stale_ms` becomes a documented limit ("peer clocks within N
s") or a bug. It was the bug. Before the fix node-a printed `stale 11 s after its only
report: false`, since it computed `now - sampled_at` with its own `now` and node-b's
stamp, so a report from a clock 30 s ahead would stay fresh for 40 s. A clock behind
would have made every report stale on arrival. The control run, same programs with skew
0, printed `true`, which pins the cause on the skew.

Fix, `stdlib/swim_driver.march`: `apply_load_events` takes the step's `now` and stores
each received `NodeLoad` with `sampled_at = now`, its receipt time on the receiver's
clock. `peer_load`, `fresh_peer_loads` and `WorkDispatch`'s filter need no change: every
stored stamp is now on one clock. `NodeLoad.sampled_at`'s field comment says so.

The unit test "stale peer_load returns None beyond LOAD_STALE_MS" encoded the old
semantics (it aged from the sender's stamp, 100, rather than receipt, 500) and now
asserts both sides of the receipt boundary. Two new tests cover a stamp 30 s ahead
(stale on the receiver's clock) and 30 s behind (fresh on arrival).

## VectorClock is not exercised, on purpose

`VectorClock` takes no wall-clock input: `new`/`increment`/`merge`/`compare` are pure
counters, and `advance(vc, id, ts)` has no caller in the stdlib. Skew cannot reorder
it, so a scenario would pin nothing. The docs say this instead
(`specs/lang/clustering.md`, `docs/clustering.md`).
