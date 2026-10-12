# Scenario "session_refused": a cluster session whose peer's node refuses
# its frames (DELIVERY_FAILED: no session route for that endpoint) must fail,
# not hang. node-b binds role B's registry name to an actor that is no
# session endpoint, as a peer party that ended leaves its name behind until
# the unregistration arrives; node-a's role A finds it, forms, and its
# message is refused. Before 2026-10-12 no cluster session read
# DELIVERY_FAILED, and node-a waited for B's reply for ever (the one way the
# 2026-10-12 session_churn traces hung: a party that formed after its peer's
# party had ended across a redial). Then a normal session must still work.
# See specs/progress/2026-10-12-session-redial-hang.md.
# node-b stays up until A's first session has ended (its stopping would end
# that session as "connection lost" and hide the hang).
export REFUSED_GO_FILE="$work/go"
start_node a
wait_line a "node-a: up"
start_node b
wait_line a "A: session to a stale endpoint failed"
touch "$REFUSED_GO_FILE"
wait_exit a
wait_exit b
