# Scenario "session_churn": the two nodes form session after session, over
# the cluster runner (clean finishes, and every third one cancelled by role B
# leaving) and then over the standalone runner (its own connections), and
# each node checks that a session leaves no Vault table behind
# (specs/progress/2026-10-01-session-node-vault-tables-leak.md). Before the
# fix every session kept its 13 tables (14 with the cluster runner's slot)
# registered, contents and all, for the life of the process.
# The nodes run SWIM at its default 3 s suspect timeout, except under
# AddressSanitizer (the sanitize gate), where they get 15 s, as
# hcr_new_code_session does. Measured 2026-10-05 in the ubuntu two-node
# container: under ASan, 1 run in 4 had node-a declare node-b dead ("suspect
# timeout") one session in, so that session failed on both sides (finished 39,
# cancelled 21); without ASan it passed 10/10 on macOS.
if [ -n "${MARCH_SANITIZE:-}" ]; then export CHURN_SUSPECT_MS=15000; fi
export ECHO_A_ADDR=127.0.0.1:$PORT_C
start_node a
wait_line a "node-a: up"
start_node b
wait_exit a
wait_exit b
