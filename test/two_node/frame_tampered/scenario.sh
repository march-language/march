# Scenario "frame_tampered": node-a reaches node-b only through node-c, a
# proxy that flips one byte in one sealed data frame. node-b drops and
# counts that frame and keeps the link. See node_b.march.
export CLUSTER_STOP_FILE="$work/stop"
start_node b
wait_line b "node-b: up"
start_node c
wait_line c "node-c: up"
start_node a
wait_line b "of 10 pings arrived"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
wait_exit c
