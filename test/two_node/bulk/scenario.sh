# Scenario "bulk": messages the credit window cannot simply carry, over the
# role runner. No fault; the claim is that every message arrives. Before
# 2026-09-18 every session frame went through NodeQueue under DropNew with
# the result ignored, so a message over the 4096-byte budget was refused
# and a burst lost most of its frames, silently: the 20000-byte message
# left B waiting for it and A waiting for B's reply, both heartbeating, for
# good. The 900 + 3400 pair is a second hang that was independent of the
# drop: 900 consumed bytes stay unannounced (credit goes out every 1024),
# and a frame over 3/4 of the budget then waited on credit that never came.
# See specs/progress/2026-09-18-session-frames-never-dropped.md.
export BULK_A_ADDR=127.0.0.1:$PORT_A

ORDERED=1
start_node a
wait_line a "node-a: up"
start_node b
wait_exit b
wait_exit a
