# Scenario "partition": drop every packet between the two nodes until each has
# marked the other Dead (both keep running; the connection stays open), let
# each claim "leader" in its own half, heal, and require the post-heal registry
# merge to pick the same winner on both sides. Needs root for iptables (see
# drop_link in scripts/two-node.sh); exits 3 (skipped) where it cannot apply.

start_node b
wait_line b "node-b: up"
start_node a
wait_line a "node-a: first ack from node-b"
wait_line b "node-b: first ack from node-a"
drop_link
wait_line a "node-a: node-b Dead"
wait_line b "node-b: node-a Dead"
heal
wait_exit a
wait_exit b
