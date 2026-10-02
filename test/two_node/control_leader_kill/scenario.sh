# Scenario "control_leader_kill" (dd step 12a): the leader is killed in the
# middle of a rollout. The release has a canary step with a long gate; once the
# canary node runs the patch, the leader (whichever candidate placement chose)
# is SIGKILLed. The standby becomes the leader, loads the newest release from
# its own disk (the old leader made it durable on every reachable candidate
# before answering forge), re-derives where the rollout stands from what the
# agents report, restarts the gate window and finishes. No node applies the
# release twice, none skips it, and the node that died is simply gone.
source "$root/test/two_node/control_plane/lib.sh"
ctl_prepare
ctl_up
ctl_until 40 "a leader" ctl_leader
ctl_until 40 "every node reporting" ctl_all_reporting a b c

(ctl_release 1 12000 > "$work/release.out" 2>&1; echo "exit $?" >> "$work/release.out") &
rel_pid=$!

# The canary step has run on some node.
canary_applied() { ctl_status | grep "^  [abc]: " | grep -q "versions [*]="; }
ctl_until 40 "the canary to run the patch" canary_applied
old=$(ctl_leader) || fail "no leader to kill"
survivor=$([ "$old" = a ] && echo b || echo a)
echo "killing the leader, node $old" >&2
kill_node "$old"

# The standby takes over and the release completes on the nodes still alive.
leader_is_survivor() { [ "$(ctl_leader)" = "$survivor" ]; }
ctl_until 60 "the standby to lead" leader_is_survivor
i=0
until grep -q "^exit " "$work/release.out" 2>/dev/null; do
  i=$((i + 1)); [ "$i" -gt 900 ] && { cat "$work/release.out" >&2; fail "the release never finished"; }
  sleep 0.2
done
grep -q "^exit 0" "$work/release.out" || { cat "$work/release.out" >&2; fail "forge's follow ended badly"; }
grep -q "complete" "$work/release.out" || fail "the release did not complete under the new leader"

# Every node still alive applied it exactly once.
for n in a b c; do
  [ "$n" = "$old" ] && continue
  [ "$(ctl_node_deploys "$n")" = 1 ] || fail "node $n applied the release $(ctl_node_deploys "$n") times, not once"
done
status=$(ctl_status)
for n in a b c; do
  [ "$n" = "$old" ] && continue
  echo "$status" | grep "^  $n: " | grep -q "versions [*]=" || fail "node $n does not run the patch: $status"
done
wait "$rel_pid" 2>/dev/null
ctl_no_ssh
ctl_done
