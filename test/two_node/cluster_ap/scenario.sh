# Scenario "cluster_ap": an access point. node-a offers the Server role of
# Echo; node-b initiates two sessions as Client, one after the other. Each
# session is formed by invitation under a fresh session id, and node-a runs
# both from one offer. See node_a.march and
# specs/2026-09-19-choreography-access-points-and-crash-branches-design.md.
ORDERED=1
start_node a
wait_line a "node-a: offering"
start_node b
wait_exit b
wait_exit a
