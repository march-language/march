# Scenario "topology_rejoin" (todo 2026-10-05-lab-rejoining-node-offers-count-
# role-at-once): node-b ranks first for the count = 1 Ledger.Server and
# offers it; SIGKILLed, node-a takes it over; started again (creation 2),
# node-b must leave the role on node-a for the settle period (node-a does
# not count it for that long) and only then take it back. A short settle
# period and tick keep the scenario fast. See node_a.march / node_b.march.
export TOPOLOGY_STOP_FILE="$work/stop"
export MARCH_PLACEMENT_SETTLE_MS=4000
export MARCH_PLACEMENT_TICK_MS=100
compile a
compile b
start_node a
wait_line a "node-a: up"
start_node b 1
wait_line a "node-a: ranked second"
wait_line b "node-b: offering Ledger.Server"
kill_node b
wait_line a "node-a: offering Ledger.Server"
start_node b 2
wait_line b "node-b: took Ledger.Server back"
wait_line a "node-a: not offering Ledger.Server"
touch "$TOPOLOGY_STOP_FILE"
wait_exit a
wait_exit b
