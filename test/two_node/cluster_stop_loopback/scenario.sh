# Scenario "cluster_stop_loopback": ONE node whose loopback link must not
# outlive `ClusterNode.stop` (review finding, specs/progress/
# 2026-09-25-dd-review-loopback-link-outlives-stop.md). A session over the
# loopback works before stop; after it, `queue_for(own id)` is None, the
# loopback's sink is gone from NodeQueue's table, a raw send to itself is
# refused, and a local initiate fails instead of running a session on a
# stopped node. Output is ordered: one actor prints.
ORDERED=1
start_node a
wait_exit a
