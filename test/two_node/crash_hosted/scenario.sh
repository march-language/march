# Scenario "crash_hosted": a crash branch taken by an ACTOR-HOSTED role.
# The same Logging protocol and the same kill as crash_before_send, but I --
# the detector -- lives in an actor (`Logging_Run.host_I`, the event API)
# instead of running from callbacks. The transport forwards the crash on the
# delivery route, so the actor's resume handler gets `Crashed_Msg_C_I_1` with
# the crash branch's first state, sends L the Fatal and finishes. I and L both
# return Ok: the session completed without C, and nothing was cancelled.
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
