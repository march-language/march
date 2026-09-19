# Scenario "cluster_ap_restart": Maty's local restart. node-b offers the
# Server role; node-a initiates one session, node-b is killed and started
# again with a new creation, and node-a's next session finds the new offer
# and completes. Nothing coordinates the restart across nodes: the restarted
# program offers again, and the next session forms.
# See specs/2026-09-19-choreography-access-points-and-crash-branches-design.md.
ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line a "Client: session 1 done"
kill_node b
start_node b 2
wait_exit a
kill_node b
