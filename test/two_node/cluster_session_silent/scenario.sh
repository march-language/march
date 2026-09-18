# Scenario "cluster_session_silent": failure detection without an end of
# file, in cluster mode. node-b is SIGSTOPped once its role is running; node-a
# is waiting on it. SWIM (no session heartbeat) must declare node-b dead and
# the session must be cancelled with that cause. node-b is killed afterwards.
ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "B: connected"
stop_node b                    # SIGSTOP: alive, connected, silent
wait_exit a
kill_node b
