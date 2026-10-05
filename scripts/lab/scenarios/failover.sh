# lab-scenario: `docker stop` the host running the count=1 Ledger: it moves within the SWIM timeout; back, it waits out the settle period
#
# Order.Ledger is placed `{ on = "books", count = 1 }`: on one of lab-3 and
# lab-4, chosen by rendezvous hashing over the live members. The lab stops
# the container that offers it (its node dies with it, no drain) and checks:
#
#   - the other books host offers Order.Ledger within the SWIM suspect
#     timeout (3 s, ClusterNode.config's default) plus a margin
#     (LAB_FAILOVER_MARGIN_S, default 17 s: probe period, ack timeout,
#     gossip, the placement tick);
#   - Ledger totals come back from the new host and sessions finish again;
#   - the stopped host, started again (its node is restarted at boot), does
#     not take the role back before MARCH_PLACEMENT_SETTLE_MS (15 s) has
#     passed, and at the end exactly one host offers it.
#
# Sessions that had the dead node as a party fail while it is being
# detected; that number is reported, not asserted.
#
# Expected to fail: the returning host offers the role about a second after
# it starts, while the other still holds it, until the settle period passes
# on the other's side (the timeline is in LAB_DIR/logs/failover-timeline.txt).
# Once the role is back on the restarted host, no initiator sees its offer,
# so sessions stop finishing (the first todo's sibling, the second).
LAB_XFAIL="specs/todos/2026-10-05-lab-rejoining-node-offers-count-role-at-once.md, 2026-10-05-lab-restarted-node-offers-invisible.md"
LAB_XFAIL_AT="inside the 15s settle period|sessions finishing after"

settle_s=15
margin=${LAB_FAILOVER_MARGIN_S:-17}
lab_fresh_cluster
lab_traffic 2000 16
lab_traffic_flows 5
victim=$(lab_ledger_hosts)
[ "$(echo "$victim" | wc -w | tr -d ' ')" = 1 ] || fail "Order.Ledger is offered on '$victim', not exactly one host"
case $victim in lab-3) other=lab-4 ;; lab-4) other=lab-3 ;; *) fail "Order.Ledger is on $victim, not a books host" ;; esac
lab_snapshot failover

t0=$(date +%s)
docker stop -t 0 "$victim" > /dev/null || fail "docker stop $victim"
moved_on() { lab_status "$other" | grep -q '^offer Order.Ledger '; }
lab_until $((3 + margin)) "Order.Ledger offered on $other after $victim stopped" moved_on
took=$(( $(date +%s) - t0 ))
lab_note "Ledger moved $victim -> $other in ${took}s (SWIM suspect 3s + margin ${margin}s)"
lab_until 60 "a Ledger total from $other" lab_stat_ge "booked@$(lab_node "$other")" $(( $(awk -v k="booked@$(lab_node "$other")" '$1 == k { print $2 }' "$LAB_DIR/snap-failover") + 1 ))
lab_traffic_flows 10
lab_note "while $victim was down: $(lab_delta failover failed) failed, $(lab_delta failover refused) refused, $(lab_delta failover finished) finished"

# Back: boot.sh starts the enabled unit; the node rejoins.
t1=$(date +%s)
docker start "$victim" > /dev/null || fail "docker start $victim"
lab_until 60 "sshd on $victim" lab_ssh "$victim" true
# The status file on its disk still says what it offered before the stop:
# only a file written since the start (by the host's own clock) counts.
t1c=$(lab_exec "$victim" "date +%s")
fresh_offer() {
  lab_exec "$victim" "f=$LAB_STATE/run/work.status; [ \$(stat -c %Y \$f) -ge $t1c ] && grep -q '^offer Order.Ledger ' \$f"
}
lab_until 60 "$victim's node running" lab_exec "$victim" "pgrep -x $LAB_PROJECT"
# A timeline, every half second for the settle period plus 45 s: whether
# each books host offers Order.Ledger (the victim's only once it rewrote its
# status file after the start).
tl=$LAB_DIR/logs/failover-timeline.txt
: > "$tl"
reclaimed_at=; both=0
while [ $(( $(date +%s) - t1 )) -lt $((settle_s + 45)) ]; do
  t=$(( $(date +%s) - t1 ))
  v=no; fresh_offer 2> /dev/null && v=yes
  o=no; lab_status "$other" | grep -q '^offer Order.Ledger ' && o=yes
  echo "t=${t}s $victim=$v $other=$o" >> "$tl"
  [ "$v" = yes ] && [ -z "$reclaimed_at" ] && reclaimed_at=$t
  [ "$v$o" = yesyes ] && both=$((both + 1))
  sleep 0.5
done
lab_note "after docker start: $victim offered Order.Ledger from ${reclaimed_at:-never}s; both offered it in $both of $(wc -l < "$tl" | tr -d ' ') samples ($tl)"
early=
if [ -n "$reclaimed_at" ] && [ "$reclaimed_at" -lt "$settle_s" ]; then
  early="$victim offered Order.Ledger ${reclaimed_at}s after it started, inside the ${settle_s}s settle period ($tl)"
fi
n=$(lab_ledger_hosts | wc -l | tr -d ' ')
[ "$n" = 1 ] || fail "Order.Ledger is offered on $n hosts at the end: $(lab_ledger_hosts | tr '\n' ' ')"
want=$(( $(lab_stat finished) + 10 ))
lab_until 120 "10 sessions finishing after $victim rejoined" lab_stat_ge finished "$want"
# Reported last, so the checks above still run when it happens.
[ -z "$early" ] || fail "$early"
