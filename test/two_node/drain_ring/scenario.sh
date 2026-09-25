# Scenario "drain_ring" (D27, three roles): Ring over three nodes, one role
# each (A = 1, B = 2, C = 3). A's loop head is a send; B's and C's are
# receives. After C has chosen `more` twice, node-c drains its epochs. In
# the third iteration B consumes A's `a` (B's node is not draining), then
# B's `b` reaches C at its boundary: it goes back to B undelivered and C
# drains. B, waiting on C's choice, drains with `b` in hand; A, waiting on
# C's choice too, drains with nothing back. Results: A Drained(0), B
# Drained(1), C Drained(0) -- one message in flight, one returned.
export MARCH_NUM_SCHEDULERS=1
export RING_A_ADDR=127.0.0.1:$PORT_A
export RING_B_ADDR=127.0.0.1:$PORT

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: up"
start_node c
wait_exit c
wait_exit b
wait_exit a
