# Scenario "cluster_fingerprint_skew": `fingerprint_skew` over the cluster
# runner (`cluster_<Role>`), which finds its peers by registry name and had
# no hello to carry a fingerprint, so two nodes built from different versions
# of a protocol formed a session and found the skew mid-session. Each role now
# registers its fingerprint beside its endpoint, and a peer with a different
# one (s1), or none at all (s2: a node built before the check), is refused
# before the session forms. See node_a.march.
export CLUSTER_FP_PEER_DONE="$work/peer-done"
start_node a
wait_line a "node-a: up"
start_node b
# A local setup error only queues the peer's refusal. Wait for B to receive
# and report it before allowing A to close the link; otherwise disconnect
# can win the race and replace the intended fingerprint diagnostic.
wait_exit b
touch "$CLUSTER_FP_PEER_DONE"
wait_exit a
