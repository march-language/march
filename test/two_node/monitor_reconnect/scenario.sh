# Scenario "monitor_reconnect": node-a monitors an actor on node-b, asks
# node-b to kill it, and DROPS its connection before the MONITOR_FIRE can be
# read (the fault is the socket close itself: node-a closes without reading).
# The fire is written into a dead connection and stays pending on node-b.
# node-a reconnects; node-b resends on the new connection; node-a delivers
# exactly one Down and acks; node-b's pending table is empty at exit.
# Design: specs/progress/2026-09-15-monitor-fire-at-least-once.md.

start_node b
wait_line b "node-b: up"
start_node a
wait_exit a
wait_exit b
