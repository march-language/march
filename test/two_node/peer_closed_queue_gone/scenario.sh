# Scenario "peer_closed_queue_gone": node-b links to node-a, then node-a is
# SIGKILLed. node-b's `on_peer_closed` handler asks for its session queue to
# node-a and must find none. Before the fix the data reader told the close
# handlers first and only then asked the node actor to drop the connection,
# so in between `session_queue_for` still handed out the dead queue: a
# session forming in that window linked to it, subscribed to the close too
# late, and its recheck saw the queue as current. Its link to the dead node
# never ended, and the session never did (drain_initiator_killed, under
# ASan: node-b's drain hit its hard deadline with 1 session running).
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: linked"
kill_node a
wait_exit b
