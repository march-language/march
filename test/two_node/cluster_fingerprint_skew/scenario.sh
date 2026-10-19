# Scenario "cluster_fingerprint_skew": `fingerprint_skew` over the cluster
# runner (`cluster_<Role>`), which finds its peers by registry name and had
# no hello to carry a fingerprint, so two nodes built from different versions
# of a protocol formed a session and found the skew mid-session. Each role now
# registers its fingerprint beside its endpoint, and a peer with a different
# one (s1), or none at all (s2: a node built before the check), is refused
# before the session forms. See node_a.march.
start_node a
wait_line a "node-a: up"
start_node b
wait_exit a
wait_exit b
