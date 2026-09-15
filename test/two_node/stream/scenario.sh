# Scenario "stream": the Stream protocol's two endpoints on two nodes, over
# the Session.Ops network transport. No fault; the claim is that the generated
# endpoint code runs unchanged with every message crossing a TCP connection,
# and that each node's trace is exactly its projection of the in-process
# trace (test/session/stream_endpoints.expected). One actor prints per node,
# so the goldens are ORDERED.

ORDERED=1
start_node b
wait_line b "node-b: up"
start_node a
wait_exit a
wait_exit b
