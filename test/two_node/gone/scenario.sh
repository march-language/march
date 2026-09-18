# Scenario "gone": SIGKILL node-b while node-a is mid-session waiting for its
# reply. node-a's `Gone_Run.run_A` must return `Err(Cancelled(2, _))` -- the
# survivor learns a peer is gone and decides what to do, where a dead peer
# used to be a hang -- and the process must exit (its readers ended, none
# left parked). Both nodes are the generated role runner.
export MARCH_NUM_SCHEDULERS=1
export GONE_A_ADDR=127.0.0.1:$PORT_A

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "B: got 1"
kill_node b                    # SIGKILL: a crash, not a close
wait_exit a
