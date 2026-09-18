# Scenario "cluster_partition": the partition scenario on the cluster node
# service. Drop both nodes' listen ports until each has marked the other
# Dead, let each claim "leader", heal, and require one winner on both sides
# and a Lost on the loser. Needs root for iptables (see drop_link); on macOS
# run it through scripts/two-node-docker.sh. See node_a.march.
export CLUSTER_STOP_FILE="$work/stop"
start_node a
wait_line a "node-a: up"
start_node b
wait_line a "node-a: node-b up"
wait_line b "node-b: node-a up"
drop_link "$PORT" "$PORT_A"
wait_line a "node-a: registered leader"
wait_line b "node-b: registered leader"
heal
wait_line a "node-a: leader after heal"
wait_line b "node-b: leader after heal"
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
