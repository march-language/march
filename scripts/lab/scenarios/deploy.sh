# lab-scenario: fresh hosts, `forge host init`, the first `forge deploy` over ssh; sessions flow across hosts
#
# From nothing: new containers, a fresh copy of examples/lab_app, a deploy key
# and a cluster operator key (certificate mode: every node gets a certificate
# naming the roles its pool offers and initiates). Then:
#
#   forge host init --env lab     prepares every host and records its target
#   forge deploy --env lab        nothing runs yet, so every pool restarts onto
#                                 a base image cross-built for that target
#
# and the lab checks that the cluster formed and works: a control-plane leader,
# Order.Ledger offered on exactly one "books" host, Stock replies from all three
# work hosts, Ledger totals coming back, and no session failed.

"$here/up.sh" || exit $?
rm -rf "$LAB_DIR/app" "$LAB_DIR/home" "$LAB_DIR/mhome"
mkdir -p "$LAB_DIR/home" "$LAB_DIR/mhome"
cp -R "$lab_root/examples/lab_app" "$LAB_DIR/app" && chmod -R u+w "$LAB_DIR/app" || fail "copying the app"
rm -rf "$LAB_DIR/app/.forge" "$LAB_DIR/app/.march"

lab_forge_ok hot-reload keygen
lab_forge_ok cluster keygen
lab_forge_ok host init --env lab
for h in $LAB_HOSTS; do
  lab_expect "host init" "$LAB_OUT" "$(lab_node "$h") (root@$h, pool $(lab_pool "$h"))"
done
lab_expect "host init" "$LAB_OUT" "target $LAB_TARGET"
# One session a second, at most 4 at once: every cluster session leaves
# memory behind on each node it touches (specs/todos/2026-10-01-session-node-vault-tables-leak.md,
# 2026-10-04-dropped-closure-leaks-its-captures.md), so the lab keeps traffic
# modest. lab-1's hook re-reads this file before each session.
lab_traffic 1000 4

lab_forge_ok deploy --env lab --plan
lab_expect "first plan" "$LAB_OUT" "nothing has been deployed to this environment yet" \
  "pool ingress (build shared, 1 host): restart" "pool work (build shared, 3 hosts): restart"
if ! lab_forge deploy --env lab --yes; then
  # The restarts went over ssh; the topology then goes out as a release
  # through the control plane. Its step can halt on a race: the Agent checks
  # the node's report right after relaying TOPOLOGY, before the node's
  # placement loop has re-read it (specs/todos/2026-10-04-lab-control-topology-step-races-report.md).
  # Say so, and deploy again, as an operator would.
  case $LAB_OUT in
    *"ingress-lab-1: restarted"*"work-lab-4: restarted"*"does not report topology at"*)
      lab_note "FINDING: the first deploy's topology release halted (the Agent's report race); deploying again" ;;
    *) echo "$LAB_OUT" >&2; lab_node_logs 30 >&2; fail "forge deploy --env lab --yes failed" ;;
  esac
  lab_forge_ok deploy --env lab --yes
else
  lab_expect "first deploy" "$LAB_OUT" "ingress-lab-1: restarted" "work-lab-2: restarted" "work-lab-3: restarted" \
    "work-lab-4: restarted"
fi
lab_expect "deploy" "$LAB_OUT" "deploy complete"

lab_until 90 "a control-plane leader" lab_leader
lab_note "leader: $(lab_leader)"
lab_until 90 "Order.Ledger offered on one books host" test "$(lab_ledger_hosts | wc -l | tr -d ' ')" = 1
ledger=$(lab_ledger_hosts)
case $ledger in lab-3 | lab-4) ;; *) fail "Order.Ledger is offered on $ledger, which has no \"books\" label" ;; esac
lab_note "Order.Ledger on $ledger"

lab_until 120 "30 sessions finished" lab_stat_ge finished 30
for h in lab-2 lab-3 lab-4; do
  lab_until 60 "a Stock reply from $h" lab_stat_ge "have:stock-v1@$(lab_node "$h")" 1
done
lab_until 30 "a Ledger total from $ledger" lab_stat_ge "booked@$(lab_node "$ledger")" 1
[ "$(lab_stat failed)" = 0 ] || { lab_stats >&2; fail "$(lab_stat failed) session(s) failed"; }
[ "$(lab_stat bad_reply)" = 0 ] || fail "a reply did not parse"

lab_forge_ok topology status --env lab
for h in $LAB_HOSTS; do
  lab_expect "topology status" "$LAB_OUT" "$(lab_node "$h"): running code matches what forge last deployed"
done

for h in $LAB_HOSTS; do lab_note "$h: rss $(( $(lab_rss_kb "$h") / 1024 )) MB, live objects $(lab_live "$h")"; done
lab_note "$(lab_stat started) sessions started, $(lab_stat finished) finished, $(lab_stat refused) refused (before the offers opened), 0 failed"
touch "$LAB_DIR/deployed"
