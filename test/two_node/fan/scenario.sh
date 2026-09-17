# Scenario "fan": three processes, one per role of the Fan protocol, over
# SessionNode's per-role routing. A listens for C, C listens for B (roles
# A = 1, C = 2, B = 3; "i < j: i listens, j connects"). A sleeps before its
# send, so B's message reaches C first and C must park it until it has asked
# for it -- the cross-peer race, across real processes.
#
# Every node is the generated role runner (`Fan_Run.run_<Role>`), which
# reads the address table from `FAN_<ROLE>_ADDR`: one entry per role that
# listens (A and C; B is the highest role and only dials).

# Socket waits park the green thread (march_sched_wait_fd), so node-c's four
# readers cost no thread each; pinned to ONE scheduler thread per node so a
# wait that blocked the thread again would stall node-c right after "up", as
# it did before that change at 1 or 2 threads
# (specs/progress/2026-09-16-park-socket-waits.md).
export MARCH_NUM_SCHEDULERS=1
export FAN_A_ADDR=127.0.0.1:$PORT_A
export FAN_C_ADDR=127.0.0.1:$PORT_C

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node c
wait_line c "node-c: up"
start_node b
wait_exit b
wait_exit c
wait_exit a
