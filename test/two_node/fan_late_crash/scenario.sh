# Scenario "fan_late_crash": the drain rule (Maty's E-CancelH side condition,
# specs/todos/2026-09-18-choreography-failure-handling.md). B sends C its 9
# and is SIGKILLed before it closes. B has nothing left to do in the
# protocol, and C's receive from B is satisfied by the message B already
# sent, so the session COMPLETES: A and C both return Ok. The runner before
# failure handling aborted it (PeerGone) the moment B's connection dropped.
# A sends only when this script creates FAN_GO_FILE, after B is dead and C
# has seen its connection drop: B's message is parked at C, and C is waiting
# on A, at the moment B goes.
export MARCH_NUM_SCHEDULERS=1
export FAN_A_ADDR=127.0.0.1:$PORT_A
export FAN_C_ADDR=127.0.0.1:$PORT_C
export FAN_GO_FILE="$work/go"

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node c
wait_line c "node-c: up"
start_node b
wait_line b "B: sent 9"
sleep 0.3                      # B's frame reaches C's socket
kill_node b                    # SIGKILL after its send, before its close
sleep 0.5                      # C's reader sees B's connection drop
touch "$FAN_GO_FILE"           # only now does A send
wait_exit c
wait_exit a
