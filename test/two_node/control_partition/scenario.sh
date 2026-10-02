# Scenario "control_partition" (dd step 12a): the leader is cut off in the
# middle of a rollout and comes back. There is no strict lease (D40), so for a
# while both sides can lead: SIGSTOP stands in for the partition (the stopped
# node answers nothing, so SWIM declares it dead and the standby takes over;
# SIGCONT is the heal, and the old leader wakes up still believing it leads).
# Releases stay correct: the nodes enforce sequence and refuse a fork, and an
# order already applied is a no-op. What two leaders can break is rollout
# policy: the old one, whose canary window ran out while it was stopped, may
# order the next step while the new one is still inside its own window. STATUS
# says so. After healing, every node, the stopped one included, holds the
# release and runs the patch once.
source "$root/test/two_node/control_plane/lib.sh"
ctl_prepare
ctl_up
ctl_until 40 "a leader" ctl_leader
ctl_until 40 "every node reporting" ctl_all_reporting a b c

(ctl_release 1 15000 > "$work/release.out" 2>&1; echo "exit $?" >> "$work/release.out") &
rel_pid=$!

canary_applied() { ctl_status | grep "^  [abc]: " | grep -q "versions [*]="; }
ctl_until 40 "the canary to run the patch" canary_applied
old=$(ctl_leader) || fail "no leader to stop"
survivor=$([ "$old" = a ] && echo b || echo a)
echo "cutting off the leader, node $old" >&2
stop_node "$old"

# The standby takes over (its gate window starts over) ...
leader_is_survivor() { [ "$(ctl_leader)" = "$survivor" ]; }
ctl_until 60 "the standby to lead" leader_is_survivor
sleep 2
# ... then the partition heals: the old leader wakes up.
echo "healing" >&2
cont_node "$old"

i=0
until grep -q "^exit " "$work/release.out" 2>/dev/null; do
  i=$((i + 1)); [ "$i" -gt 900 ] && { cat "$work/release.out" >&2; fail "the release never finished"; }
  sleep 0.2
done
grep -q "^exit 0" "$work/release.out" || { cat "$work/release.out" >&2; fail "forge's follow ended badly"; }

# Both sides converged: every node runs the patch, once.
settled() { local s; s=$(ctl_status) || return 1; for n in a b c; do echo "$s" | grep "^  $n: " | grep -q "versions [*]=" || return 1; done; }
ctl_until 60 "every node to run the patch after healing" settled
for n in a b c; do
  [ "$(ctl_node_deploys "$n")" = 1 ] || fail "node $n applied the release $(ctl_node_deploys "$n") times, not once"
done
echo "--- final status" >&2; ctl_status >&2
wait "$rel_pid" 2>/dev/null
ctl_no_ssh
ctl_done
