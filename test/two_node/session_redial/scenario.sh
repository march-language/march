# Scenario "session_redial": a session whose node pair ends and is redialled
# while its two parties are at different stages must end on both sides,
# never hang (specs/progress/2026-10-12-session-redial-hang.md).
#
# node-a's role A registers for session "redial-1" and node-a is frozen
# (SIGSTOP) before A finds B. node-b's role B then forms against A on the
# current pair and waits for A's message. node-b's SWIM declares the frozen
# node-a dead and drops the pair, so B's session fails, and its Cancel to A
# can only go over a pair that does not exist yet. On SIGCONT the nodes
# redial. A then either finds B's endpoint (its name is stale: B's party
# ended) and forms on the new pair, where node-b refuses its message, or it
# never finds B. Either way it must fail: B's Cancel reaches it over the new
# pair, node-b's DELIVERY_FAILED reaches it, or its setup gives up. Before
# the fix, A waited for B's reply for ever whenever it found the stale name
# (session_churn under ASan hung that way about 1 run in 8). Then a fresh
# session over the new pair must finish.
#
# Under AddressSanitizer the nodes get a longer SWIM suspect timeout, as
# session_churn's do, so no other session sees a spurious death; node-b
# still declares the frozen node-a dead, only later.
if [ -n "${MARCH_SANITIZE:-}" ]; then export REDIAL_SUSPECT_MS=15000; fi
export REDIAL_FROZEN_FILE="$work/frozen"
export REDIAL_NEXT_FILE="$work/next"
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "B: sees A"
stop_node a                       # A registered, has not found B
touch "$REDIAL_FROZEN_FILE"
wait_line b "B: cut-off session failed"
cont_node a
wait_line a "A: cut-off session failed"
touch "$REDIAL_NEXT_FILE"
wait_exit a
wait_exit b
