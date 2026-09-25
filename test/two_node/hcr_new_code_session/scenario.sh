# Scenario "hcr_new_code_session": a hot patch deployed to BOTH nodes of a
# two-node cluster while sessions form between them, the patch's new code
# starting sessions and green threads of its own.
#
# The minimal network acceptance test for the two 2026-09-25 hot-reload
# fixes (specs/progress/2026-09-25-hcr-patch-so-private-runtime-copy.md):
#   - a patch .so no longer carries its own copy of the C runtime, so the
#     task node-b's Driver spawns per session on the NEW code (a party
#     endpoint actor, a cluster session) runs on the host process's
#     scheduler instead of a second one ("no green thread running on this
#     scheduler"), and node-a's new hosting code finds the offer the OLD
#     code stored in a Vault instead of a second, empty vault registry;
#   - a call dispatches whenever its callee is reloadable, so the entry
#     module's `drive` loop and the Driver's task reach the new `session`
#     and `version` rather than the baseline they used to be pinned to.
# The protocol does not change between the versions (that is step 9's
# protocol_evolve, which this scenario is the reduced form of): version 2
# only reports a different version number and prints what it sees. Rollout
# order is node-b (the initiator) first, then node-a, with sessions started
# every 150 ms throughout.
#
# node-b prints the invariants: no session lost or refused, every session
# Finished or Drained, both nodes' version-2 code seen in sessions, and the
# version pairings the order implies (never a v1 Buyer with a v2 Shop). Both
# reload servers must count nothing dropped, killed or lost.
deploy=$root/_build/default/test/hcr_deploy.exe
[ -x "$deploy" ] || fail "test/hcr_deploy.exe is not built (dune build --root . test/hcr_deploy.exe)"
mkdir -p "$work/keys" "$work/patch_a" "$work/patch_b"
"$deploy" keygen "$work/keys" || fail "keygen failed"
pk=$(cat "$work/keys/pk")

COMPILE_FLAGS_a="--hot-reload Host --signing-pubkey $pk"
COMPILE_FLAGS_b="--hot-reload Buy --signing-pubkey $pk"
compile a
compile b

# Each node's version-2 patch, built in its own directory: a warm artifact
# cache copies the .so without its manifest.
for n in a b; do
  cp "$dir/node_${n}_v2.march" "$work/patch_$n/node_$n.march"
  mod=$( [ "$n" = a ] && echo Host || echo Buy )
  (cd "$work/patch_$n" && "$MARCH" --compile --compile-so --hot-reload "$mod" \
     -o "$work/patch_$n/v2.so" node_$n.march) \
     > "$work/patch_$n.log" 2>&1 || { cat "$work/patch_$n.log" >&2; fail "node_${n}_v2.march did not build"; }
  [ -f "$work/patch_$n/v2.so.hcr_manifest" ] || fail "no manifest for node-$n's patch"
done

# Reload sockets under a short directory: a Unix socket path is cut at 104
# bytes on macOS, and two long paths cut to one name collide.
socks=$(mktemp -d /tmp/hs.XXXXXX)
export HCR_DRIVE_MS=12000
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
sleep 3
"$deploy" deploy "$socks/a.sock" "$work/keys" "$work/patch_a/v2.so" $(old_schemas a) > "$work/deploy_a.log" 2>&1 \
  || { cat "$work/deploy_a.log" >&2; fail "the deploy to node-a failed"; }
wait_line a "node-a: version 2 host sees the version-1 offer"
wait_line b "node-b: v1 Buyer with a v2 Shop"

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
