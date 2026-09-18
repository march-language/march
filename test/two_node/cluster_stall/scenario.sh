# Scenario "cluster_stall": SIGSTOP node-b past the suspect timeout, then
# SIGCONT; node-a must see it suspect, dead, and rejoined. See node_a.march.
export CLUSTER_STOP_FILE="$work/stop"
start_node a
wait_line a "node-a: up"
start_node b
wait_line a "node-a: node-b up"
wait_line b "node-b: joined"
stop_node b
wait_line a "node-a: node-b dead"
sleep 1                        # a few redials meet a stopped peer
cont_node b
wait_line a "node-a: node-b rejoined"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
