# Scenario "control_plane" (dd step 12a): a hot release through the in-cluster
# control plane, with no ssh. Three nodes of one topology app; a and b are
# control candidates, so one leads (`count = 1` placement over SWIM) and the
# other is a standby; every node runs the Agent. The release (v1 -> v2 of
# `Ver.version`, a canary node first, then the rest, then done) is built and
# signed as `forge deploy` does on the cluster backend (Cluster_deploy), sent to
# the control API, and followed to the end. Every node must then report the
# new release and run the new patch exactly once.
source "$root/test/two_node/control_plane/lib.sh"
ctl_prepare
ctl_up
ctl_until 40 "a leader" ctl_leader
ctl_until 40 "every node reporting" ctl_all_reporting a b c

ctl_release 1 1500 > "$work/release.out" 2>&1 || { cat "$work/release.out" >&2; fail "the release did not complete"; }
grep -q "complete" "$work/release.out" || fail "the release did not report completion"

# Every node holds the release and runs the patch, once.
status=$(ctl_status)
for n in a b c; do
  echo "$status" | grep "^  $n: " | grep -q "versions [*]=" || fail "node $n does not report the patch: $status"
  [ "$(ctl_node_deploys "$n")" = 1 ] || fail "node $n applied the release $(ctl_node_deploys "$n") times, not once"
done

# A re-read of the topology (SIGHUP here; a signed TOPOLOGY push or a restart
# onto a verified copy does the same) must leave the control plane's own role
# alone. Ctl.Control is placed by the generated main (from [control]) and the
# digest cannot name it; every re-read used to place it "not served here" on
# every candidate, so the cluster lost its leader after its first deploy
# (specs/progress/2026-10-05-lab-topology-reread-closes-ctl-control.md).
for n in a b c; do kill -HUP "$(pid_of "$n")"; done
reread_all() { local n; for n in a b c; do grep -q "^topology [0-9a-f]" "$work/nodes/$n/status" || return 1; done; }
ctl_until 40 "every node re-reading its topology" reread_all
sleep 1   # a few placement ticks (MARCH_PLACEMENT_TICK_MS=200)
! grep -h "Ctl.Control: placement .*not served here" "$work/a.out" "$work/b.out" \
  || fail "a topology re-read closed Ctl.Control on a candidate"
ctl_until 10 "a leader after the topology re-read" ctl_leader

ctl_no_ssh
ctl_done
