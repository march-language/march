# Run by CI like every scenario here since 2026-09-25, when a hot patch .so
# stopped carrying its own copy of the C runtime (specs/progress/
# 2026-09-25-hcr-patch-so-private-runtime-copy.md): before that, node-b's
# first new-code session killed the process and node-a's new code could not
# find the offer the old code stored. It needs test/hcr_deploy.exe built.
#
# Scenario "protocol_evolve" (distributed-deploys build step 9, acceptance): a
# protocol that adds a choice branch deploys HOT across a two-node cluster
# with sessions in flight on both fingerprints.
#
# `Order`'s `choose by Shop` gains `later`. node-a offers Shop (the chooser)
# from a hosting actor; node-b initiates Buyer (a receiver) over and over
# from a Driver actor. Both are hot-reload builds signed by a key minted
# here. The rollout goes receivers first (plan 6.4): node-b's patch, then,
# with node-b's new Buyers forming sessions with node-a's old Shop (the
# compatibility table: Buyer accepts the old fingerprint, and vouches for the
# old offer), node-a's patch, after which node-a's hosting actor, on the new
# code, re-offers Shop under the new fingerprint and the old offer drains. Sessions formed before a deploy
# finish on the code they formed under or end at a loop boundary (D27).
#
# node-b prints the invariants: no session lost, none refused, every one
# Finished or Drained, all three version pairings seen, `later` only from a
# version-2 Shop, and never a version-1 Buyer with a version-2 Shop. The
# reload servers' counters must show nothing dropped, killed or lost.
# Not under AddressSanitizer: this scenario's invariants are timing-bound
# (sessions start every 150 ms and none may be lost across two deploys), and
# ASan's slowdown turns the re-offer window into lost or refused sessions, or
# stalls node-b past any deadline. Memory safety of a hot deploy is covered
# under ASan by hcr_new_code_session. Exit 3 is the harness's "skipped",
# which the sanitize gate reports as SKIP, not as a pass.
# specs/todos/2026-09-25-protocol-evolve-under-asan.md
if [ -n "${MARCH_SANITIZE:-}" ]; then
  echo "two-node[protocol_evolve]: skipped under MARCH_SANITIZE (timing-bound; see scenario.sh)"
  exit 3
fi
deploy=$root/_build/default/test/hcr_deploy.exe
[ -x "$deploy" ] || fail "test/hcr_deploy.exe is not built (dune build --root . test/hcr_deploy.exe)"
mkdir -p "$work/keys" "$work/base" "$work/patch_a" "$work/patch_b"
"$deploy" keygen "$work/keys" || fail "keygen failed"
pk=$(cat "$work/keys/pk")

COMPILE_FLAGS_a="--hot-reload ProtocolEvolveA --signing-pubkey $pk"
COMPILE_FLAGS_b="--hot-reload ProtocolEvolveB --signing-pubkey $pk"
compile a
compile b

# Version 1's baseline, then each node's version-2 patch against it. Each
# patch builds in its own directory: a warm artifact cache copies the .so
# without its manifest and schemas.
(cd "$work/base" && "$MARCH" --check --emit-protocols "$work/base" "$work/node_a.march") > "$work/base.log" 2>&1 \
  || { cat "$work/base.log" >&2; fail "the version-1 baseline did not build"; }
[ -f "$work/base/Order.json" ] || fail "no baseline for Order"
for n in a b; do
  cp "$dir/node_${n}_v2.march" "$work/patch_$n/node_$n.march"
  mod=$( [ "$n" = a ] && echo ProtocolEvolveA || echo ProtocolEvolveB )
  (cd "$work/patch_$n" && "$MARCH" --compile --compile-so --hot-reload "$mod" \
     --protocol-baseline "$work/base/Order.json" -o "$work/patch_$n/v2.so" node_$n.march) \
     > "$work/patch_$n.log" 2>&1 || { cat "$work/patch_$n.log" >&2; fail "node_${n}_v2.march did not build"; }
  [ -f "$work/patch_$n/v2.so.hcr_manifest" ] || fail "no manifest for node-$n's patch"
done

# Reload sockets under a short directory: a Unix socket path is cut at 104
# bytes on macOS, and two long paths cut to one name collide.
socks=$(mktemp -d /tmp/pe.XXXXXX)
export EVOLVE_DRIVE_MS=14000
export MARCH_HOT_RELOAD_SOCKET=$socks/a.sock
start_node a
wait_line a "node-a: offering"
export MARCH_HOT_RELOAD_SOCKET=$socks/b.sock
start_node b
wait_line b "node-b: driving"

old_schemas() { if [ -f "$work/node_$1.schemas.json" ]; then echo "$work/node_$1.schemas.json $work/node_$1.hcr_manifest"; fi; }
sleep 3
"$deploy" deploy "$socks/b.sock" "$work/keys" "$work/patch_b/v2.so" $(old_schemas b) > "$work/deploy_b.log" 2>&1 \
  || { cat "$work/deploy_b.log" >&2; fail "the deploy to node-b failed"; }
sleep 4
"$deploy" deploy "$socks/a.sock" "$work/keys" "$work/patch_a/v2.so" $(old_schemas a) > "$work/deploy_a.log" 2>&1 \
  || { cat "$work/deploy_a.log" >&2; fail "the deploy to node-a failed"; }
wait_line a "Shop re-offered under version 2"
wait_line b "node-b: later from a v1 Shop"

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
