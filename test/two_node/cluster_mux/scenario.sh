# Scenario "cluster_mux": two actor-message streams, a refused message and a
# remote monitor's fire, all over one connection pair. See node_b.march.
export CLUSTER_STOP_FILE="$work/stop"
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: ready"
wait_line b "node-b: sx got"
wait_line b "node-b: sy got"
wait_line a "node-a: target down"
wait_line a "node-a: undeliverable message refused"
sleep 1                        # a duplicate Down would print by now
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
