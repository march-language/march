# lab-scenario: restart a host after a hot deploy: it comes back on its persisted patches and pushed topology before opening offers
#
# A hot deploy (the Stock tag goes to the next
# version), then lab-2 is restarted (`docker restart`: its node is killed and
# started again at boot from the base image on its disk). The lab checks:
#
#   - from the moment it is back, every Stock reply from lab-2 carries the
#     NEW tag: an offer opened before the persisted patch stack was restored
#     would answer with the base build's code at least once;
#   - its status file reports the topology forge pushed (the verified copy,
#     not the base's), and `forge topology status` says it runs what forge
#     last deployed, with its patches persisted;
#   - its log shows the patch stack restored before any offer opened.
#
# Expected to fail at the last step: after the restart the node's offers are
# open (its status file says so) but no initiator sees them, so it serves no
# session again (the checks before that pass).
LAB_XFAIL=specs/todos/2026-10-05-lab-restarted-node-offers-invisible.md
LAB_XFAIL_AT="waiting for: Stock replies from lab-2 again"

host=lab-2
lab_fresh_cluster
lab_traffic 2000 16
lab_traffic_flows 5
# Over ssh until the control plane keeps a leader after a topology push
# (specs/todos/2026-10-05-lab-topology-reread-closes-ctl-control.md); the
# node persists a patch the same way whichever way it arrives.
# Traffic paused while forge builds the patch: every session costs memory
# (docs/lab.md, "Expected failures and workarounds"), and this scenario is
# about the restart, not the deploy.
lab_traffic 0
lab_hot_deploy_next_tag ssh
lab_traffic 2000 16
lab_until 90 "a $LAB_NEW_TAG reply from $host" lab_stat_ge "have:$LAB_NEW_TAG@$(lab_node "$host")" 1
digest=$(lab_status "$host" | sed -n 's/^topology \([0-9a-f]*\).*/\1/p' | head -1)
[ -n "$digest" ] || fail "$host's status names no topology digest: $(lab_status "$host")"
lab_exec "$host" "wc -l < /var/log/march-work.service.log" > "$LAB_DIR/restart-logline"
lab_snapshot restart_persist

docker restart -t 0 "$host" > /dev/null || fail "docker restart $host"
lab_until 60 "sshd on $host" lab_ssh "$host" true
lab_until 60 "$host's node running" lab_exec "$host" "pgrep -x $LAB_PROJECT"
from=$(cat "$LAB_DIR/restart-logline")
newlog() { lab_exec "$host" "tail -n +$((from + 1)) /var/log/march-work.service.log"; }
lab_until 60 "$host's node to report its restore" sh -c "docker exec $host tail -n +$((from + 1)) /var/log/march-work.service.log | grep -q 'hcr. restore: republished'"
lab_until 60 "$host's node to apply its topology" sh -c "docker exec $host tail -n +$((from + 1)) /var/log/march-work.service.log | grep -q '^topology: topology re-read'"
newlog > "$LAB_DIR/logs/restart_persist-$host.log"
# The persisted stack is put back before the generated main opens anything:
# the restore line comes before the first line the topology runner prints.
first_restore=$(grep -n 'hcr. restore: republished' "$LAB_DIR/logs/restart_persist-$host.log" | head -1 | cut -d: -f1)
first_topo=$(grep -n '^topology:' "$LAB_DIR/logs/restart_persist-$host.log" | head -1 | cut -d: -f1)
[ "$first_restore" -lt "$first_topo" ] || fail "$host's log has the topology runner (line $first_topo) before the patch restore (line $first_restore)"
lab_expect "$host's restore" "$(grep 'hcr. restore: republished' "$LAB_DIR/logs/restart_persist-$host.log")" "republished 1 patch(es), skipped 0"
lab_until 30 "$host's status file rewritten" sh -c "[ \"\$(docker exec $host sed -n 's/^topology //p' $LAB_STATE/run/work.status)\" != '' ]"
d2=$(lab_status "$host" | sed -n 's/^topology \([0-9a-f]*\).*/\1/p' | head -1)
[ "$d2" = "$digest" ] || fail "$host came back on topology $d2, not the pushed $digest"
lab_forge_ok topology status --env lab
lab_expect "topology status" "$LAB_OUT" "$(lab_node "$host"): running code matches what forge last deployed" "persisted patch"

# Then it serves again, with the new code from its first session.
lab_until 90 "Stock replies from $host again" \
  lab_stat_ge "have:$LAB_NEW_TAG@$(lab_node "$host")" $(( $(awk -v k="have:$LAB_NEW_TAG@$(lab_node "$host")" '$1 == k { print $2 }' "$LAB_DIR/snap-restart_persist") + 3 ))
old=$(lab_delta restart_persist "have:$LAB_OLD_TAG@$(lab_node "$host")")
[ "$old" = 0 ] || fail "$host answered $old time(s) with the base build's $LAB_OLD_TAG after its restart"
lab_note "$host restarted: back on $LAB_NEW_TAG and topology ${digest:0:12}; $(lab_delta restart_persist failed) session(s) failed while it was down"
