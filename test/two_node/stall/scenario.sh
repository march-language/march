# Scenario "stall": SIGSTOP node-b for longer than SWIM's suspicion timeout,
# then SIGCONT. A stall is not a crash: the socket stays open and nothing is
# refused, so node-a must reach Dead on timeouts alone; on resume node-b
# refutes with a higher incarnation and node-a must accept it as Alive.

ORDERED=1
start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: first ack from node-b"
stop_node b                    # a stall, distinct from a crash
wait_line a "node-a: node-b Dead"
cont_node b
wait_exit a
wait_exit b
