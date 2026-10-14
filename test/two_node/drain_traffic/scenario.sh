# Scenario "drain_traffic" (three nodes): SIGTERM reaches a node whose tasks
# keep INITIATING sessions back to back, as a topology pool's hook does
# under continuous traffic. node-a serves Order.Stock, node-b Order.Ledger;
# node-c's 8 tasks each loop `initiate_Shop` without pause. Once traffic
# flows node-c gets SIGTERM, and must be gone by its hard deadline (4 s)
# plus slack. Before the fix it never was: new sessions kept starting
# during the drain, and ClusterNode.stop at the hard deadline did not end
# the process either. Then node-b and node-a drain and exit 0.
start_node a
wait_line a "node-a: up"
start_node b
wait_line b "node-b: up"
start_node c
wait_line c "node-c: traffic flowing"
sleep 1
kill -TERM "$(pid_of c)"
t0=$(date +%s)
p=$(pid_of c)
while kill -0 "$p" 2>/dev/null; do
  [ $(( $(date +%s) - t0 )) -le $(( 12 * TIME_SCALE )) ] || fail "node-c still running $(( $(date +%s) - t0 )) s after SIGTERM (hard deadline 4 s)"
  sleep 0.1
done
wait "$p"; code=$?
pid_c=''
[ "$code" -eq 0 ] || fail "node-c exited $code"
kill -TERM "$(pid_of b)"
wait_exit b
kill -TERM "$(pid_of a)"
wait_exit a
