# Scenario "cluster_fan_late_crash": fan_late_crash over the cluster node
# service. B is SIGKILLed after its send; A and C must both return Ok. A
# sends only when FAN_GO_FILE exists, after node-b is dead: B's message is
# parked at C, and C is waiting on A, at the moment B goes. See node_a.march.
export FAN_GO_FILE="$work/go"

ORDERED=1
start_node a
start_node b
start_node c
wait_line a "node-a: up"
wait_line b "B: sent 9"
sleep 0.3                      # B's frame reaches C's socket
kill_node b                    # SIGKILL after its send, before its close
sleep 1.5                      # a refused redial: node-b is dead at A and C
touch "$FAN_GO_FILE"           # only now does A send
wait_exit c
wait_exit a
