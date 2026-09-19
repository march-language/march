# Scenario "cluster_crash": SIGKILL node-b; node-a's redial is refused and it
# declares node-b dead for that reason. See node_a.march.
export CLUSTER_STOP_FILE="$work/stop"
start_node a
wait_line a "node-a: up"
start_node b
wait_line a "node-a: node-b up"
wait_line b "node-b: joined"
kill_node b
wait_line a "node-a: node-b dead"
wait_exit a
