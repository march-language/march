# Scenario "fan": three processes, one per role of the Fan protocol, over
# SessionNode's per-role routing. A listens for C, C listens for B (roles
# A = 1, C = 2, B = 3; "i < j: i listens, j connects"). A sleeps before its
# send, so B's message reaches C first and C must park it until it has asked
# for it -- the cross-peer race, across real processes.

# Each node is its own process, but node-c alone keeps FOUR readers in
# blocking socket calls (two data, two control) and accept/recv block their
# scheduler thread (specs/todos/2026-09-16-blocking-accept-starves-the-scheduler.md).
# Measured: 1 and 2 threads stall node-c after "up"; 4 pass. A 4-CPU runner
# resolves "auto" to exactly 4, which is too close to the floor to rely on.
export MARCH_NUM_SCHEDULERS=8

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node c
wait_line c "node-c: up"
start_node b
wait_exit b
wait_exit c
wait_exit a
