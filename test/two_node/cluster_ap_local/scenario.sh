# Scenario "cluster_ap_local": ONE node plays both roles of each session --
# an access point's offer and the initiator that invites it -- over the
# ClusterNode loopback link (distributed-deploys plan II.3, the level-0
# prerequisite). The harness runs a single node. Output is ordered: one
# session at a time, and each role prints before the other can proceed.
ORDERED=1
start_node a
wait_exit a
