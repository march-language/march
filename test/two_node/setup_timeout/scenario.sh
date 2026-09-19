# Scenario "setup_timeout": a role that fails its own setup no longer leaves
# the others waiting for ever. Tri's roles are A = 1, B = 2, C = 3 (first
# appearance): A listens for B and C, B dials A and listens for C, C dials A
# and B. C is given a dead address for B, so it reaches A, cannot reach B,
# and gives up. C's program then stays alive, as one that handles the error
# and carries on would. Before 2026-09-18 a listener's accept had no
# deadline, so B waited for C for ever; and a role that failed setup kept
# the connections it had made, so A heard nothing from the still-running C
# until the heartbeat. Now:
#   C  fails to connect to B and tears down its connection to A at once;
#   B  stops waiting for C after MARCH_SESSION_CONNECT_MS;
#   A  is cancelled ("connection lost", not "no heartbeat"), because it
#      was waiting on C when C's connection ended.
# See specs/progress/2026-09-18-session-accept-deadline.md.
# A and B wait 5 s (room for a slow CI box to start C); C gives up on B
# after 1 s, well inside that.
export MARCH_SESSION_CONNECT_MS=5000
export TRI_A_ADDR=127.0.0.1:$PORT_A
export TRI_B_ADDR=127.0.0.1:$PORT

# Compile every node first: the deadlines must not count a compile.
compile a
compile b
compile c

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: up"
# Nothing listens on port 1: C's dial to B is refused on every attempt.
export TRI_B_ADDR=127.0.0.1:1
export MARCH_SESSION_CONNECT_MS=1000
start_node c
wait_line c "C: could not connect"
wait_exit b
wait_exit a
kill_node c
