# Scenario "hosted": the Stream protocol across two processes with Cons
# hosted in an actor on node-b (the event API through `host_Cons`) and Prod
# a plain body on node-a. The trace is stream_actor_events' split by node.
export MARCH_NUM_SCHEDULERS=1
export STREAM_PROD_ADDR=127.0.0.1:$PORT_A

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
