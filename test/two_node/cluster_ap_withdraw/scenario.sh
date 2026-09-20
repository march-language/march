# Scenario "cluster_ap_withdraw": an offer that accepted an invitation is
# released when the initiator gives up on the session. Ring needs three
# roles; node-b offers B with capacity 1 and node-c offers C, but node-c
# starts late. node-a's first attempt fills B, finds no C, and withdraws
# from B. Once node-c is up, the next attempt must fill B again: without the
# withdrawal, node-b's one slot would still be held by the abandoned session
# (which would only give up 30 s later, when it stopped waiting for its
# peers) and node-a would be told "full".
ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line a "Client: no session yet"
start_node c
wait_exit a
kill_node b
kill_node c
