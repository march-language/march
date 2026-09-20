# Scenario "wrong_secret": the two nodes run with different cluster secrets.
# The listener (A) refuses the handshake and gives up on B; B must report
# THAT, not keep retrying and end with a "Connection refused" from dialling
# a listener that has already given up (what it did before 2026-09-20).
# See specs/progress/2026-09-20-choreography-ux-hardening.md.
export Q_A_ADDR=127.0.0.1:$PORT_A
export MARCH_SESSION_CONNECT_MS=8000
export SECRET_A=first
export SECRET_B=second

# Compile both nodes first: A's accept window (8 s) must not include B's
# compile, which on a CI runner can be longer than that -- A then gave up
# and B's dials were refused for a different reason than the one tested.
compile a
compile b

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
