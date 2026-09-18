# Scenario "silent": failure detection without an end of file. node-b is
# SIGSTOPped after connecting: its process is alive, its kernel keeps the
# TCP connection open, and it sends nothing -- a hung or partitioned peer.
# node-a is waiting on it. The heartbeat (200 ms, 1 s limit here) must take
# it for dead and cancel node-a's endpoint with "no heartbeat" rather than
# let node-a wait forever. node-b is killed afterwards to clean up.
export MARCH_NUM_SCHEDULERS=1
export MARCH_SESSION_HEARTBEAT_MS=200
export MARCH_SESSION_TIMEOUT_MS=1000
export SILENT_A_ADDR=127.0.0.1:$PORT_A

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "B: connected"
stop_node b                    # SIGSTOP: alive, connected, silent
wait_exit a
kill_node b
