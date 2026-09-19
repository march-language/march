# Scenario "cluster_fd_release": a peer joins and leaves 15 times; the node
# that stays must not keep the dropped links' sockets open. One process (see
# node_a.march); node-b's port is only used as the flapping node's port.
start_node a
wait_exit a
