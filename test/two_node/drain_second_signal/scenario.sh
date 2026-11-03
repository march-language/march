# Scenario "drain_second_signal": a second SIGTERM to a node that is
# already draining stops it at once, as `Topology.drain_on_signal`
# documents. node-a offers Echo.Server and answers only after 30 s; node-b
# installs the drain (soft 10 s, hard 30 s) and initiates one session.
# Once node-a has the question, node-b gets SIGTERM (it starts draining,
# the session still running), then a second SIGTERM: node-b must exit 1
# within a few seconds. Before the fix the runtime's second-signal escape
# only stopped an HTTP server's loop, so the signal was ignored and node-b
# ran on to its hard deadline. See node_b.march.
start_node a
wait_line a "node-a: offering"
start_node b
wait_line a "Server: got 7"
kill -TERM "$(pid_of b)"
wait_line b "topology: draining node-b"
kill -TERM "$(pid_of b)"
t0=$(date +%s)
p=$(pid_of b)
while kill -0 "$p" 2>/dev/null; do
  [ $(( $(date +%s) - t0 )) -le $(( 5 * TIME_SCALE )) ] || fail "node-b still running $(( $(date +%s) - t0 )) s after its second SIGTERM"
  sleep 0.1
done
wait "$p"; code=$?
pid_b=''
[ "$code" -eq 1 ] || fail "node-b exited $code after its second SIGTERM, not 1"
kill_node a
