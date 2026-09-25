# Scenario "drain_hard" (DD step 6, follow-up 3): a party session whose held
# Endpoint actor is killed at a hot-reload HARD drain deadline ends as
# `Left("draining")`, as a hosted one does, not through the dead-endpoint
# paths. The protocol's loop is `atomic`, so D27 cannot end the session at
# the soft point; node-b arms a drain of its epochs with a 300 ms hard
# deadline after its first item, keeps the session going, and the deadline
# kills its Endpoint (it holds the epoch). node-b's `run_Cons` returns
# `Err(Left("draining"))`; node-a's Prod, waiting on Cons, is cancelled by
# the connection ending. ORDERED: one actor prints per node.
export STREAM_PROD_ADDR=127.0.0.1:$PORT_A

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
