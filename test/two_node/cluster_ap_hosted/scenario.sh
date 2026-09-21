# Scenario "cluster_ap_hosted": a HOSTED access point. node-a offers the
# Server role of Echo from one actor that keeps every session's parked
# endpoint in a LinearMap (capacity 4); node-b initiates three sessions at
# once, then one more. Each session gets its own answers. Sorted goldens:
# three sessions run concurrently. Both nodes are compiled first so no
# session's setup time includes a compile.
compile a
compile b
start_node a
wait_line a "node-a: offering"
start_node b
wait_exit b
wait_exit a
