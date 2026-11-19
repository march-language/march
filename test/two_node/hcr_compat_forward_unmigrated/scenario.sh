# @compat(forward) with an added field that cannot be derived (its `init`
# value is a parameter) and no counter_migrate_state: the deploy is refused,
# and the running v1 is untouched (node_a.expected: its own Report).  Before
# the fix the deploy activated and the node died on its first message.
deploy=$root/_build/default/test/hcr_deploy.exe
need_built test/hcr_deploy.exe
mkdir -p "$work/keys" "$work/base" "$work/v2"
"$deploy" keygen "$work/keys" || fail "keygen"
pk=$(cat "$work/keys/pk")
COMPILE_FLAGS_a="--hot-reload Fwd --signing-pubkey $pk"
compile a
# v1's schema sidecar, as a deploy would have left it.
cp "$dir/node_a.march" "$work/base/base.march"
bg_build "$work/base" "$work/base/build.log" "v1 schema" \
  "$MARCH" --compile --compile-so --hot-reload Fwd -o base.so base.march
wait_builds
cp "$dir/node_a_v2.march" "$work/v2/patch.march"
bg_build "$work/v2" "$work/v2/build.log" "patch v2" \
  "$MARCH" --compile --compile-so --hot-reload Fwd \
  --hcr-baseline "$work/base/base.so.schemas.json" -o patch.so patch.march
wait_builds
grep -q '"compat": *"forward"' "$work/v2/patch.so.schemas.json" \
  || { cat "$work/v2/patch.so.schemas.json" >&2; fail "v2's schema does not say @compat(forward)"; }
grep -q 'migrate_not_derived' "$work/v2/patch.so.schemas.json" \
  || { cat "$work/v2/patch.so.schemas.json" >&2; fail "v2 derived a migration: the scenario needs one that is not"; }
socks=$(mktemp -d /tmp/hcr-fwd.XXXXXX)
export MARCH_HOT_RELOAD_SOCKET=$socks/a.sock
start_node a
wait_line a "ready"
export MARCH_BIN=$MARCH
if ENTRY=$work/v2/patch.march "$deploy" deploy "$socks/a.sock" "$work/keys" \
  "$work/v2/patch.so" > "$work/v2.log" 2>&1; then
  cat "$work/v2.log" >&2; fail "an unmigrated state change under @compat(forward) was deployed"
fi
grep -q '@compat(forward) does not waive a migration for a state change: .*field added: label : String' \
  "$work/v2.log" || { cat "$work/v2.log" >&2; fail "the refusal does not say why"; }
grep -q 'not derived: the `init` value of label is not a constant' "$work/v2.log" \
  || { cat "$work/v2.log" >&2; fail "the refusal does not say why nothing was derived"; }
wait_exit a
rm -rf "$socks"
