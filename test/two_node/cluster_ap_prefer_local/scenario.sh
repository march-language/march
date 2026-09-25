# Scenario "cluster_ap_prefer_local": prefer a local offer (plan 4.2, II.3
# item 3). BOTH nodes offer role Server of Echo; node-b also initiates three
# sessions as Client once it sees both offers. Every session must be served
# by node-b's own offer (over its loopback link), none by node-a's, although
# node-a's offer is live and connected. cluster_ap_local cannot show this:
# a single node's only candidate is local.
start_node a
wait_line a "node-a: offering"
start_node b
wait_exit b
wait_exit a
