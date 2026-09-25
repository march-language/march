# Scenario "drain_stream" (D27): the Stream protocol over two nodes through
# the generated role runners. After Cons has taken its third item, node-b
# drains every code epoch it runs (`SessionNode.drain_epochs`, the reload
# server's DRAIN for all epochs). Prod's fourth item reaches Cons at its loop
# boundary and is NOT consumed: it goes back to node-a as Undelivered, Cons
# drains, and Prod, waiting on Cons, drains in turn with the item in its
# drain handler. Both runners return `Ok(Drained(n))`; Prod's n (1) is
# exactly what was in flight (one item: Prod sends the next only after
# `more`). One actor prints per node, so the goldens are ORDERED.
export STREAM_PROD_ADDR=127.0.0.1:$PORT_A

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
