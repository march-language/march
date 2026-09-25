# One-node scenario "hosted_protocol_change" (distributed-deploys build step
# 9, item 4): a hosted access point's actor keeps its old-version sessions
# while a fresh actor serves the new version, and exits once they end. See
# node_a.march. A short placement tick so the drained offer is noticed fast.
export MARCH_PLACEMENT_TICK_MS=100
start_node a
wait_exit a
