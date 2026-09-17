# Scenario "protocol": node-b answers node-a's typed message with bytes that
# are not a Bad_Msg. node-a's generated handler cannot decode them, hands
# them to the transport (Session.fail), and run_A returns Err(Protocol(2, _))
# instead of panicking inside the endpoint actor. node-b closes its own
# endpoint right after replying, so its run ends cleanly.
export MARCH_NUM_SCHEDULERS=1
export BAD_A_ADDR=127.0.0.1:$PORT_A

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
