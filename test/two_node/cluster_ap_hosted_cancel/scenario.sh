# Scenario "cluster_ap_hosted_cancel": a hosted access point with one of its
# sessions cancelled. node-a hosts the Server role of Echo in one actor;
# node-c starts a session and stalls half way through it; node-b then runs
# two sessions at once, so the actor holds three parked endpoints. node-c
# is killed once node-b is done: node-a declares it dead, and the actor's
# Cancel handler runs for that one session id; the other two had finished.
# All three nodes are compiled first so no session's setup time includes a
# compile.
compile a
compile b
compile c
start_node a
wait_line a "node-a: offering"
start_node c
wait_line c "Client: got 10"
start_node b
wait_exit b
kill_node c
wait_exit a
