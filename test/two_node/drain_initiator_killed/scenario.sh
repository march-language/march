# Scenario "drain_initiator_killed" (three nodes): the INITIATOR's node dies
# while sessions are forming. node-a serves Order.Stock, node-b
# Order.Ledger; node-c's 8 tasks each loop `initiate_Shop` without pause.
# Once traffic flows node-c is SIGKILLed: sessions node-a and node-b have
# accepted from it are left waiting for a link to node-c's endpoints that
# never comes. Each must give up once SWIM declares node-c dead, not after
# the 30 s link wait, so node-b's SIGTERM drain (hard deadline 4 s), sent
# once node-b has seen node-c dead, ends with no session left: exit 0.
# Before the fix node-b reached its hard deadline with the stranded
# sessions still counted and exited 1. Then node-a drains the same way.
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: up"
start_node c
wait_line c "node-c: traffic flowing"
sleep 1
kill_node c
wait_line b "node-b: node-c dead"
kill -TERM "$(pid_of b)"
wait_exit b
kill -TERM "$(pid_of a)"
wait_exit a
