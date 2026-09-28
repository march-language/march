# Scenario "hcr_remote_msg_epoch": a remote message sent ACROSS a hot deploy
# that changes the receiving actor's message type, from a sender already on
# the new format, must be delivered: not converted, not dropped (review
# finding specs/progress/2026-09-25-dd-review-link-reader-tasks-pin-epoch.md).
#
# node-b's data-reader task for the link to node-a is spawned when the link
# forms, before the deploy. A task never advances its code epoch (II.4.3), so
# before the fix that reader routed every later delivery at the baseline
# epoch: it ran version 1 of the route's decoder and its `send` stamped the
# message with epoch 1, so the version-2 sink (message type changed at epoch
# 2, no migrate_msg) dropped it. Now a link reader that finds its epoch
# draining hands its connection to a fresh reader the node actor spawns (the
# node actor has passed its marker), and that reader routes the message.
#
# The version-1 message goes before the deploy (forming the link), the
# version-2 one after it; node-b's reload server must count nothing
# converted, dropped, killed or lost.
deploy=$root/_build/default/test/hcr_deploy.exe
need_built test/hcr_deploy.exe
mkdir -p "$work/keys"
"$deploy" keygen "$work/keys" || fail "keygen failed"
pk=$(cat "$work/keys/pk")
export CLUSTER_STOP_FILE="$work/stop"
export DEPLOYED_FILE="$work/deployed"

COMPILE_FLAGS_b="--hot-reload Recv --signing-pubkey $pk"
compile a
compile b

# The patch, and version 1 built the same way for its schema and manifest
# sidecars: the deploy compares the two to learn that Sink's message type
# changed (a plain --compile writes no .schemas.json, and without one the
# runtime never knows). Each in its own directory: a warm artifact cache
# copies the .so without its manifest.
for v in 1 2; do
  src=$( [ "$v" = 1 ] && echo node_b.march || echo node_b_v2.march )
  mkdir -p "$work/patch_b$v"
  cp "$dir/$src" "$work/patch_b$v/node_b.march"
  (cd "$work/patch_b$v" && "$MARCH" --compile --compile-so --hot-reload Recv \
     -o "$work/patch_b$v/v$v.so" node_b.march) \
     > "$work/patch_b$v.log" 2>&1 || { cat "$work/patch_b$v.log" >&2; fail "$src did not build as a patch"; }
  [ -f "$work/patch_b$v/v$v.so.hcr_manifest" ] || fail "no manifest for version $v"
  [ -f "$work/patch_b$v/v$v.so.schemas.json" ] || fail "no schemas for version $v"
done

# The reload socket under a short directory (a Unix socket path is cut at
# 104 bytes on macOS).
socks=$(mktemp -d /tmp/hs.XXXXXX)
export MARCH_HOT_RELOAD_SOCKET=$socks/b.sock
start_node b
wait_line b "node-b: up"
unset MARCH_HOT_RELOAD_SOCKET
start_node a
wait_line b "node-b: version 1 sink got 1"

"$deploy" deploy "$socks/b.sock" "$work/keys" "$work/patch_b2/v2.so" \
    "$work/patch_b1/v1.so.schemas.json" "$work/patch_b1/v1.so.hcr_manifest" > "$work/deploy_b.log" 2>&1 \
  || { cat "$work/deploy_b.log" >&2; fail "the deploy to node-b failed"; }
touch "$DEPLOYED_FILE"
wait_line b "node-b: version 2 sink got 7 from a version-2 sender"

counters=$("$deploy" counters "$socks/b.sock" converted dropped killed markers_lost 2>&1)
case "$counters" in
  *"converted=0"*"dropped=0"*"killed=0"*"markers_lost=0"*) ;;
  *) fail "node-b's reload counters: $counters" ;;
esac
touch "$CLUSTER_STOP_FILE"
wait_exit a
wait_exit b
rm -rf "$socks"
