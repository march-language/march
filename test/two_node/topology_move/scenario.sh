# Scenario "topology_move": both nodes place Echo.Server with `count = 1`.
# node-a ranks first for it (rendezvous hashing over the two node ids, which
# every node computes the same), so node-a offers and node-b does not. node-a
# is SIGKILLed; once SWIM declares it dead, node-b ranks alone and starts
# offering. See node_a.march.
export TOPOLOGY_STOP_FILE="$work/stop"
compile a
compile b
start_node a
wait_line a "node-a: up"
start_node b
wait_line a "node-a: offering Echo.Server"
wait_line b "node-b: ranked second"
sleep 2
kill_node a
wait_line b "node-b: offering Echo.Server"
touch "$TOPOLOGY_STOP_FILE"
wait_exit b
