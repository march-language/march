# Scenario "crash_after_send": the drain rule with a crash branch. C sends
# its Read and is SIGKILLed before I answers. The Read is delivered (messages
# sent before a crash are always delivered first), so I's `recv_Msg_C_I_1`
# takes its MESSAGE callback, not its crash callback, and the protocol goes
# on: I forwards to L, L reports, I answers C. The protocol never waits on C
# again, so nobody takes a crash branch and nobody is cancelled; I's Report
# to the dead C is dropped, and L and I both return Ok.
#
# L answers only once this script creates LOGGING_GO_FILE, after C is dead
# and I has seen its connection drop, so I's send to C is a send to a role
# known gone (dropped), not a write on a socket that is about to close.
# Every node is compiled up front so the window is not eaten by a compile.
export MARCH_NUM_SCHEDULERS=1
export LOGGING_L_ADDR=127.0.0.1:$PORT_A
export LOGGING_I_ADDR=127.0.0.1:$PORT
export LOGGING_GO_FILE="$work/go"

ORDERED=1
compile a
compile b
compile c
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: up"
start_node c
wait_line c "C: sent Read"
sleep 0.3                      # C's frame reaches I's socket
kill_node c                    # SIGKILL after its send, before its close
sleep 0.5                      # I's reader sees C's connection drop
touch "$LOGGING_GO_FILE"       # only now does L report
wait_exit b
wait_exit a
