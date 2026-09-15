# Scenario "skew": node-b's clock runs 30 s ahead of node-a's. It sends one
# load report stamped with its own clock; node-a must still age that report
# on its own clock (fresh on arrival, stale once load_stale_ms has passed).
# VectorClock ordering is not exercised: it has no wall-clock input at all.

ORDERED=1
MARCH_CLOCK_SKEW_MS=30000 start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: done"
wait_exit a
wait_exit b
