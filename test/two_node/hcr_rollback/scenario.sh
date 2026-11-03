# Rollback is another signed activation, with an explicit reverse migration.
deploy=$root/_build/default/test/hcr_deploy.exe
need_built test/hcr_deploy.exe
mkdir -p "$work/keys" "$work/v1" "$work/v2" "$work/v3"
"$deploy" keygen "$work/keys" || fail "keygen"
pk=$(cat "$work/keys/pk")
COMPILE_FLAGS_a="--hot-reload Rollback --signing-pubkey $pk"
compile a
for version in 1 2 3; do
  source=$dir/node_a_v$version.march
  [ "$version" = 1 ] && source=$dir/node_a.march
  cp "$source" "$work/v$version/patch.march"
  bg_build "$work/v$version" "$work/v$version/build.log" "patch v$version" \
    "$MARCH" --compile --compile-so --hot-reload Rollback -o patch.so patch.march
done
wait_builds
socks=$(mktemp -d /tmp/hcr-rb.XXXXXX)
export MARCH_HOT_RELOAD_SOCKET=$socks/a.sock
start_node a
wait_line a "behavior: good"
"$deploy" reload "$socks/a.sock" SCHEMAS > "$work/base.schemas"
# No local .prev: first deploy must obtain its baseline from the server.
"$deploy" deploy "$socks/a.sock" "$work/keys" "$work/v2/patch.so" \
  > "$work/forward.log" 2>&1 || { cat "$work/forward.log" >&2; fail "forward deploy"; }
wait_line a "behavior: bad"
"$deploy" reload "$socks/a.sock" SCHEMAS > "$work/v2.schemas"
# The original code cannot interpret v2 state without a reverse migration.
if "$deploy" deploy "$socks/a.sock" "$work/keys" "$work/v1/patch.so" \
  > "$work/refused.log" 2>&1; then fail "rollback without reverse migration accepted"; fi
"$deploy" reload "$socks/a.sock" SCHEMAS > "$work/refused.schemas"
cmp "$work/v2.schemas" "$work/refused.schemas" || fail "failed rollback changed schemas"
# A stale checkout baseline is intentionally supplied: server data must win.
"$deploy" deploy "$socks/a.sock" "$work/keys" "$work/v3/patch.so" \
  "$work/v1/patch.so.schemas.json" "$work/v2/patch.so.hcr_manifest" \
  > "$work/reverse.log" 2>&1 || { cat "$work/reverse.log" >&2; fail "reverse deploy"; }
grep -q 'local schema baseline is stale' "$work/reverse.log" || fail "stale baseline not diagnosed"
"$deploy" reload "$socks/a.sock" SCHEMAS > "$work/v3.schemas"
python3 - "$work" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
def read(name):
    text = (root / name).read_text().strip()
    assert text.startswith('SCHEMAS '), text
    return json.loads(text[8:])
a, b, c = [read(n) for n in ('base.schemas', 'v2.schemas', 'v3.schemas')]
assert a['schemas']['Counter'] == c['schemas']['Counter'], 'rollback did not restore schema'
assert b['schemas']['Counter'] != c['schemas']['Counter'], 'forward schema never changed'
assert a['releases']['Counter']['seq'] < b['releases']['Counter']['seq'] < c['releases']['Counter']['seq'], 'release sequence did not advance'
PY
[ "$?" = 0 ] || fail "schema/release rollback assertions"
wait_exit a
rm -rf "$socks"
