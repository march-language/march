# lab-scenario: a role-body change hot-deployed through the control plane (no ssh); seen on every host, no session fails
#
# The Stock reply's tag (`Work.reply`, which Order.Stock's body calls) goes
# from stock-vN to stock-vN+1 and `forge deploy` sends it as a signed release
# to the control-plane leader: no ssh (a stand-in `ssh` records any attempt).
# With sessions flowing the whole time, the lab checks that:
#
#   - the new tag comes back from all three work hosts;
#   - no session failed or was refused while it rolled out;
#   - `served`, a counter the new code keeps in the node's Vault, kept
#     counting from where the old code left it (the patch shares the old
#     code's runtime; a patch with its own runtime copy would start at 1);
#   - once rolled out, no host answers with the old tag any more.
#
# Expected to fail until the control plane keeps its leader across a
# topology push: the first deploy's push closes Ctl.Control on every node,
# so there is no leader to send the release to (the scenario stops at
# "waiting for: a control-plane leader", before forge plans anything).
LAB_XFAIL=specs/todos/2026-10-05-lab-topology-reread-closes-ctl-control.md
LAB_XFAIL_AT="waiting for: a control-plane leader"

lab_traffic 2000 16
lab_traffic_flows 5
lab_snapshot hot_role
lab_hot_deploy_next_tag
lab_note "rolled out $LAB_OLD_TAG -> $LAB_NEW_TAG through the control plane: $(echo "$LAB_OUT" | grep -m1 -o 'release [0-9]* accepted')"

for h in lab-2 lab-3 lab-4; do
  lab_until 90 "a $LAB_NEW_TAG reply from $h" lab_stat_ge "have:$LAB_NEW_TAG@$(lab_node "$h")" 1
done
# Sessions that formed before the deploy finish on the old code; then the old
# tag must stop for good.
sleep 10
old_before=$(lab_stat_sum "have:$LAB_OLD_TAG@")
lab_traffic_flows 15
old_after=$(lab_stat_sum "have:$LAB_OLD_TAG@")
[ "$old_after" = "$old_before" ] || fail "$((old_after - old_before)) reply(ies) with the old tag after the rollout"

failed=$(lab_delta hot_role failed); refused=$(lab_delta hot_role refused)
[ "$failed" = 0 ] || { lab_stats >&2; fail "$failed session(s) failed during the rollout"; }
[ "$refused" = 0 ] || { lab_stats >&2; fail "$refused session(s) were refused during the rollout"; }
[ "$(lab_stat served_went_back)" = 0 ] || fail "a node's served counter started again after the patch (a second runtime?)"

lab_forge_ok deploy --env lab --status
lab_expect "status" "$LAB_OUT" ": complete"
lab_note "$(lab_delta hot_role finished) finished, $(lab_delta hot_role drained) drained, 0 failed, 0 refused across the rollout"
