# Scenario "cluster_ap_retry": choosing among access points. Two nodes offer
# role Server of Echo: node-a, with capacity 2, and node-c, built from a
# DIFFERENT version of Echo (its Client sends a String), whose fingerprint
# therefore differs. node-b initiates as Client:
#   - four sessions in a row: the initiator's rotation makes some of them try
#     node-c first; node-c refuses ("protocol differs") and the initiator
#     moves on, so every session lands on node-a;
#   - then two sessions that node-a holds for 3 s, and meanwhile another:
#     node-a is full and node-c refuses, so it fails with NoOffer.
# See specs/2026-09-19-choreography-access-points-and-crash-branches-design.md.
ORDERED=1
start_node a
wait_line a "node-a: offering"
start_node c
wait_line c "node-c: offering"
start_node b
wait_exit b
wait_exit a
kill_node c
