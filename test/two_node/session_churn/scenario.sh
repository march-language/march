# Scenario "session_churn": the two nodes form session after session, over
# the cluster runner (clean finishes, and every third one cancelled by role B
# leaving) and then over the standalone runner (its own connections), and
# each node checks that a session leaves no Vault table behind
# (specs/progress/2026-10-01-session-node-vault-tables-leak.md). Before the
# fix every session kept its 13 tables (14 with the cluster runner's slot)
# registered, contents and all, for the life of the process.
export ECHO_A_ADDR=127.0.0.1:$PORT_C
start_node a
wait_line a "node-a: up"
start_node b
wait_exit a
wait_exit b
