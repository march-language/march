# Scenario "protocol_expand_contract" (distributed-deploys D21, plan 4.2 and
# 6.4; build step 9 item 3, wired into `forge deploy` by Deploy_plan.splits_of
# and Cmd_deploy): in a replicated monolith a compatible protocol change is
# TWO deploys, and within each one the order of the nodes does not matter.
#
# One program (node_b.march links to node_a.march) holds both roles of
# `Order`: Shop chooses, Buyer receives `choose by Shop`, which version 2
# (app_v2.march) extends with `later`. node-a offers Shop from a hosting
# actor; node-b initiates Buyer over and over. Version 2 is built the way
# `forge deploy` builds it (Cmd_deploy.protocol_build_flags): against the
# baseline of what runs (--protocol-baseline), once with --protocol-expand
# Order:later (the expand) and once without (the contract).
#
#   1. the expand to node-a FIRST, the chooser's node: the order that would
#      break a single deploy (a new Shop re-offering under the new
#      fingerprint and choosing `later` towards node-b's old Buyers). The
#      expand keeps Shop's fingerprint (`role_fingerprint`) at version 1's, so
#      the host re-offers nothing: the offer version 1 opened stays open on
#      version 1's fingerprint, and nothing on node-a chooses `later`. A
#      session pins the epoch it FORMS in (plan 6.1), so one formed before
#      the deploy finishes on version 1's code and one formed after it runs
#      the expand's (Shop phase 2), on that same offer. Then the expand to
#      node-b, whose version-2 Buyers form sessions with that offer (the
#      compatibility table: Buyer accepts the previous fingerprint): "v2
#      Buyer with an expand Shop". Until 2026-10-02 this read "v2 Buyer with
#      a v1 Shop": the entry module's functions had no dispatch slots, so
#      the old offer's handler called version 1's `shop` directly for ever,
#      whatever epoch its session formed in.
#   2. the contract to node-a, then node-b: the Shop re-offers under the new
#      fingerprint and chooses `later`; every Buyer already handles it.
#
# node-b prints the invariants: no session lost or refused, every one
# Finished or Drained, the pairings of each stage seen, `later` only from a
# contract Shop, never a version-1 Buyer with a contract Shop. Sessions start
# every 300 ms (see node_a.march's `drive`). Red control
# (2026-09-28): the contract build deployed where the expand goes (one plain
# deploy, chooser first) had node-a re-offer under the new fingerprint while
# node-b still ran version 1, and formation refused 27 sessions ("protocol
# differs") until node-b caught up; no v2 Buyer ever met a Shop on version
# 1's fingerprint. The reload
# servers' counters must show nothing dropped, killed or lost.
#
# Not under AddressSanitizer, for protocol_evolve's reason (timing-bound
# invariants; see its scenario.sh). Exit 3 is the harness's "skipped".
if [ -n "${MARCH_SANITIZE:-}" ]; then
  echo "two-node[protocol_expand_contract]: skipped under MARCH_SANITIZE (timing-bound; see scenario.sh)"
  exit 3
fi
deploy=$root/_build/default/test/hcr_deploy.exe
need_built test/hcr_deploy.exe
cmp -s "$dir/node_a.march" "$dir/node_b.march" || fail "node_a.march and node_b.march must be one program (a monolith)"
mkdir -p "$work/keys" "$work/base" "$work/expand" "$work/contract"
"$deploy" keygen "$work/keys" || fail "keygen failed"
pk=$(cat "$work/keys/pk")

COMPILE_FLAGS_a="--hot-reload ProtocolSplit --signing-pubkey $pk"
COMPILE_FLAGS_b="--hot-reload ProtocolSplit --signing-pubkey $pk"
compile a
compile b

# What runs: version 1's baseline (a deploy keeps it under
# .forge/deploy/<env>/protocols/). Then version 2's two builds against it,
# each in its own directory (a warm artifact cache copies the .so without
# its manifest and schemas).
(cd "$work/base" && "$MARCH" --check --emit-protocols "$work/base" "$work/node_a.march") > "$work/base.log" 2>&1 \
  || { cat "$work/base.log" >&2; fail "the version-1 baseline did not build"; }
[ -f "$work/base/Order.json" ] || fail "no baseline for Order"
for half in expand contract; do
  cp "$dir/app_v2.march" "$work/$half/app.march"
  extra=$( [ "$half" = expand ] && echo "--protocol-expand Order:later" )
  # shellcheck disable=SC2086 # $extra is words
  (cd "$work/$half" && "$MARCH" --compile --compile-so --hot-reload ProtocolSplit \
     --protocol-baseline "$work/base/Order.json" $extra -o "$work/$half/v2.so" app.march) \
     > "$work/$half.log" 2>&1 || { cat "$work/$half.log" >&2; fail "the $half build of app_v2.march failed"; }
  [ -f "$work/$half/v2.so.hcr_manifest" ] || fail "no manifest for the $half patch"
done

socks=$(mktemp -d /tmp/pxc.XXXXXX)
export SPLIT_DRIVE_MS=18000
export SPLIT_NODE=a MARCH_HOT_RELOAD_SOCKET=$socks/a.sock
start_node a
wait_line a "node-a: offering"
export SPLIT_NODE=b MARCH_HOT_RELOAD_SOCKET=$socks/b.sock
start_node b
wait_line b "node-b: driving"

# The code each node runs, for the next deploy's schema and manifest diff.
running_a="$work/node_a.schemas.json $work/node_a.hcr_manifest"
running_b="$work/node_b.schemas.json $work/node_b.hcr_manifest"
step() {  # step <node> <half>
  local n=$1 half=$2 was
  was=$( [ "$n" = a ] && echo "$running_a" || echo "$running_b" )
  [ -f "${was%% *}" ] || was=""
  # shellcheck disable=SC2086 # $was is words
  "$deploy" deploy "$socks/$n.sock" "$work/keys" "$work/$half/v2.so" $was > "$work/deploy_${half}_$n.log" 2>&1 \
    || { cat "$work/deploy_${half}_$n.log" >&2; fail "the $half deploy to node-$n failed"; }
  if [ "$n" = a ]; then running_a="$work/$half/v2.so.schemas.json $work/$half/v2.so.hcr_manifest"
  else running_b="$work/$half/v2.so.schemas.json $work/$half/v2.so.hcr_manifest"; fi
}

sleep 2
step a expand
sleep 3
step b expand
sleep 3
step a contract
wait_line a "node-a: Shop re-offered in phase 3"
sleep 1
step b contract
wait_line b "node-b: later from a contract Shop"

# node-b lingers five seconds after its summary for this.
for n in a b; do
  counters=$("$deploy" counters "$socks/$n.sock" dropped killed markers_lost 2>&1)
  case "$counters" in
    *"dropped=0"*"killed=0"*"markers_lost=0"*) ;;
    *) fail "node-$n's reload counters: $counters" ;;
  esac
done
wait_exit b
kill_node a
rm -rf "$socks"
