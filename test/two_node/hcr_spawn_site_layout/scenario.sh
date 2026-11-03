# Scenario "hcr_spawn_site_layout": a hot patch that changes an actor's state
# layout (C gains two fields and a c_migrate_state), deployed while three
# spawn sites keep spawning fresh C's and asking each to print its state:
#   slot: a function reached through its dispatch slot, which the patch
#         replaces (its impl hash moves with C's inlined init);
#   task: a task started before the deploy, at the old epoch;
#   main: main's own closure, built by the old code, though main itself
#         follows the current epoch.
# specs/progress/2026-09-21-hcr-spawn-site-state-layout.md
deploy=$root/_build/default/test/hcr_deploy.exe
need_built test/hcr_deploy.exe
mkdir -p "$work/keys" "$work/patch_a"
"$deploy" keygen "$work/keys" || fail "keygen failed"
pk=$(cat "$work/keys/pk")

COMPILE_FLAGS_a="--hot-reload SpawnSite --signing-pubkey $pk"
compile a

cp "$dir/node_a_v2.march" "$work/patch_a/node_a.march"
(cd "$work/patch_a" && "$MARCH" --compile --compile-so --hot-reload SpawnSite \
   -o "$work/patch_a/v2.so" node_a.march) > "$work/patch_a.log" 2>&1 \
  || { cat "$work/patch_a.log" >&2; fail "node_a_v2.march did not build"; }
[ -f "$work/patch_a/v2.so.hcr_manifest" ] || fail "no manifest for the patch"
# No local baseline: the first deploy obtains the running schemas from SCHEMAS.

# A Unix socket path is cut at 104 bytes on macOS.
socks=$(mktemp -d /tmp/ss.XXXXXX)
export MARCH_HOT_RELOAD_SOCKET=$socks/a.sock
start_node a
wait_line a "node-a: version 1 up"
sleep 2
"$deploy" deploy "$socks/a.sock" "$work/keys" "$work/patch_a/v2.so" > "$work/deploy_a.log" 2>&1 \
  || { cat "$work/deploy_a.log" >&2; fail "the deploy failed"; }
grep -v "^  " "$work/deploy_a.log" >&2
wait_exit a
cp "$work/a.out" "${SS_KEEP_OUT:-/dev/null}" 2>/dev/null || true
rm -rf "$socks"
