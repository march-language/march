# Scenario "fan_early_crash": the cascade. B is SIGKILLed after connecting
# and BEFORE it sends. C waits on B with nothing queued from it, so C's
# endpoint is cancelled -- C uses the `_or` receive, so its cancel handler
# runs and prints -- and C sends A a Cancel. A is waiting on C, so A is
# cancelled in turn, with the cause chain back to B, although A has no
# connection to B at all.
export MARCH_NUM_SCHEDULERS=1
export FAN_A_ADDR=127.0.0.1:$PORT_A
export FAN_C_ADDR=127.0.0.1:$PORT_C

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node c
wait_line c "node-c: up"
start_node b
wait_line b "B: connected"
kill_node b                    # SIGKILL before its send
wait_exit c
wait_exit a
