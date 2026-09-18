# Scenario "cluster_join" (three nodes): node-a starts with no seeds; node-b
# and node-c are each given only node-a. All three must converge on a full
# mesh -- node-c reaching node-b at the address node-b advertised, which only
# gossip could have told it. See node_a.march.
export CLUSTER_STOP_FILE="$work/stop"

start_node a
wait_line a "node-a: up"
start_node b
start_node c
wait_line a "node-a: linked to both"
wait_line b "node-b: linked to both"
wait_line c "node-c: linked to both"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
wait_exit c
