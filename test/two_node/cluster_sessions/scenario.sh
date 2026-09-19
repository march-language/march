# Scenario "cluster_sessions": two concurrent sessions between the same two
# nodes over the node service's one connection pair. See node_a.march.
start_node a
wait_line a "node-a: up"
start_node b
wait_exit a
wait_exit b
