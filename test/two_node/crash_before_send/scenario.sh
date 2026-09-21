# Scenario "crash_before_send": a crash branch taken. The Logging protocol
# (design Part B, specs/2026-09-19-choreography-access-points-and-crash-
# branches-design.md) declares `may crash C`; C is SIGKILLed after connecting
# and BEFORE it sends Read. I is waiting on C with nothing queued from it,
# and has a crash continuation installed for C (`recv_Msg_C_I_1`'s second
# callback), so instead of being cancelled it takes the crash branch: it
# sends L the Fatal and closes. L, which offered over Read/Fatal, gets the
# Fatal and closes. Both return Ok. Nothing is cancelled and no Cancel frame
# goes out: the session finished, without C.
#
# Every node is compiled up front: with a compile inside the window between
# C connecting and the kill, CI's slower compile made the timing differ.
export MARCH_NUM_SCHEDULERS=1
export LOGGING_L_ADDR=127.0.0.1:$PORT_A
export LOGGING_I_ADDR=127.0.0.1:$PORT

ORDERED=1
compile a
compile b
compile c
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: up"
start_node c
wait_line c "C: connected"
kill_node c                    # SIGKILL before its send
wait_exit b
wait_exit a
