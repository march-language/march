# Scenario "drain_initiated": the SIGTERM drain waits for a session the node
# INITIATED, not only for its offers' sessions. node-a offers Echo.Server and
# answers after 2 s; node-b serves no role (it offers nothing), installs
# `Topology.drain_on_signal` and initiates one session as Client. Once node-a
# has the question, node-b gets SIGTERM: it must drain (report the session
# still running, get the answer) before it exits 0, rather than exit at once
# and cut the session. See node_b.march.
start_node a
wait_line a "node-a: offering"
start_node b
wait_line a "Server: got 7"
kill -TERM "$(pid_of b)"
wait_exit b
wait_exit a
