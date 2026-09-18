# Scenario "cluster_takeover": node-b holds "leader" and is SIGKILLed;
# node-a takes the name over; node-b restarts as creation 2 and must see
# node-a's binding win, and retire its own stale one. See node_a.march.
export CLUSTER_STOP_FILE="$work/stop"
start_node a
wait_line a "node-a: up"
start_node b 1
wait_line b "node-b: registered leader and cfg"
wait_line a "node-a: leader bound to node-b"
kill_node b
wait_line a "node-a: leader unbound"
wait_line a "node-a: leader bound to node-a"
start_node b 2
wait_line a "node-a: node-b rejoined"
wait_line b "node-b: cfg visible"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
