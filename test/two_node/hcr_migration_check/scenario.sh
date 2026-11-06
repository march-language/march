# The live-data migration check (M10): v2's migration keeps count = 137,
# which its invariant rejects.  The prover cannot decide `not_137`, so both
# patches are built with --accept-unproved; the reload server then runs each
# migration on a copy of the live state before ACTIVATE.  v2 is refused,
# naming the actor and the conjunct, and changes nothing (the actor still
# runs v1); v3's migration passes and is activated.
deploy=$root/_build/default/test/hcr_deploy.exe
need_built test/hcr_deploy.exe
mkdir -p "$work/keys" "$work/v2" "$work/v3"
"$deploy" keygen "$work/keys" || fail "keygen"
pk=$(cat "$work/keys/pk")
COMPILE_FLAGS_a="--hot-reload MigCheck --signing-pubkey $pk"
compile a
for version in 2 3; do
  cp "$dir/node_a_v$version.march" "$work/v$version/patch.march"
  bg_build "$work/v$version" "$work/v$version/build.log" "patch v$version" \
    "$MARCH" --compile --compile-so --hot-reload MigCheck --accept-unproved Counter \
    -o patch.so patch.march
done
wait_builds
socks=$(mktemp -d /tmp/hcr-mc.XXXXXX)
export MARCH_HOT_RELOAD_SOCKET=$socks/a.sock
start_node a
wait_line a "ready"
"$deploy" reload "$socks/a.sock" SCHEMAS > "$work/base.schemas"
export MARCH_BIN=$MARCH
if ENTRY=$work/v2/patch.march "$deploy" deploy "$socks/a.sock" "$work/keys" "$work/v2/patch.so" \
  > "$work/v2.log" 2>&1; then
  cat "$work/v2.log" >&2; fail "v2's migration was activated over a state its invariant rejects"
fi
grep -q 'migration_check Counter pid:[0-9]* @invariant: not_137(count)' "$work/v2.log" \
  || { cat "$work/v2.log" >&2; fail "v2's refusal does not name the actor and conjunct"; }
"$deploy" reload "$socks/a.sock" SCHEMAS > "$work/refused.schemas"
cmp "$work/base.schemas" "$work/refused.schemas" || fail "the refused deploy changed the schemas"
ENTRY=$work/v3/patch.march "$deploy" deploy "$socks/a.sock" "$work/keys" "$work/v3/patch.so" \
  > "$work/v3.log" 2>&1 || { cat "$work/v3.log" >&2; fail "v3 deploy"; }
wait_exit a
grep -q 'migrate check: Counter: checked on live data (1 actor)' "$work/a.err" \
  || { cat "$work/a.err" >&2; fail "the server did not report the live-data check"; }
rm -rf "$socks"
