# Scenario "stream_labelled": the "stream" scenario (see test/two_node/stream)
# with the protocol's plain step labelled, `item: Prod -> Cons : Int`, so the
# endpoint code is written against `send_Item`/`recv_Item` instead of
# `send_Msg_Prod_Cons_1`/`recv_Msg_Prod_Cons_1`. No fault; the claim is that a
# label changes the generated names and nothing on the wire: the goldens are
# "stream"'s, unchanged. One actor prints per node, so they are ORDERED.
# Both nodes are compiled up front so the run's timing holds no compile.

ORDERED=1
compile a
compile b
start_node b
wait_line b "node-b: up"
start_node a
wait_exit a
wait_exit b
