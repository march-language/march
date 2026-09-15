# Scenario "restart": SIGKILL node-b while node-a holds a GlobalPid for an
# actor on it; restart node-b (creation 2) which spawns an actor at the same
# local pid. node-a's send to the held pid must be refused as stale; a send
# to the re-announced pid must be delivered.
#
# Sourced by scripts/two-node.sh, which provides start_node / kill_node /
# wait_line / wait_exit and the PORT variable.

start_node b 1                 # node-b, creation 1
wait_line b "node-b: up, creation 1"
start_node a
wait_line b "node-b: item 1"   # delivered to incarnation 1
kill_node b                    # SIGKILL: a crash, not a close
start_node b 2                 # same port, creation 2
wait_exit a
wait_exit b
