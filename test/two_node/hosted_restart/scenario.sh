# Scenario "hosted_restart": node-b's Cons actor (hosted, under a supervisor)
# crashes after answering Item(1); the replacement starts Idle, the forwarder's
# send_checked on the old incarnation's cap fails, host_Cons returns
# Err(HostGone(2)); its node sends a Cancel frame, and node-a's run_Prod returns Cancelled(2, "host gone").
export MARCH_NUM_SCHEDULERS=1
export STREAM_PROD_ADDR=127.0.0.1:$PORT_A

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
