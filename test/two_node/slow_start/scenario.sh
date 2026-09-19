# Scenario "slow_start": a role that works longer than the heartbeat timeout
# before its first send is not taken for dead. A spins the CPU for 4 s (on
# one scheduler thread) before sending; the timeout is 2 s. Before
# 2026-09-19 heartbeats started only in `serve`, after a role had driven to
# its first suspension, so B (already serving) heard nothing from A for 4 s
# and cancelled with "no heartbeat", and A found B gone. Heartbeats now
# start with the connection, and a side counts silence only once it reads,
# so A pings throughout its start and does not take B for dead either.
# See specs/progress/2026-09-19-session-heartbeat-from-connect.md.
export SLOW_A_ADDR=127.0.0.1:$PORT_A
export MARCH_SESSION_HEARTBEAT_MS=200
export MARCH_SESSION_TIMEOUT_MS=2000
export MARCH_NUM_SCHEDULERS=1

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
