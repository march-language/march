# Scenario "cluster_queue_limit": a cluster session gives up on a peer that
# stops reading, before SWIM notices anything. node-b (Server) sends the
# go-ahead and is frozen; node-a (Client) then sends three 200 KB messages
# and waits for the answer. The first goes out within the node's 256 KB
# credit window, the second waits for credit node-b never sends, so with
# MARCH_SESSION_QUEUE_MAX_BYTES at 64 KB the third finds more than that
# queued and unread for node-b, and
# node-a's session ends at once: "stopped reading". Cluster sessions have
# no heartbeat (SWIM watches the node, not whether it reads its data), so
# before 2026-09-19 nothing bounded that queue.
# See specs/progress/2026-09-19-cluster-session-hardening.md.
export MARCH_SESSION_QUEUE_MAX_BYTES=65536

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "Server: sent go"
stop_node b
wait_exit a
kill_node b
