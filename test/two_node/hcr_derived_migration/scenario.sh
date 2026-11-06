# A derived state migration (M11).  v2 adds `label` and `history` to
# Counter's state and has no counter_migrate_state.  Built against v1's
# schema (--hcr-baseline, what `forge deploy hot` keeps as .schemas.json.prev)
# the compiler derives the migration, and the deploy goes through: the live
# count survives and the new fields hold their `init` values.  The control is
# the same source built with no baseline: it has no migration and is refused.
deploy=$root/_build/default/test/hcr_deploy.exe
need_built test/hcr_deploy.exe
mkdir -p "$work/keys" "$work/base" "$work/v2" "$work/nobase"
"$deploy" keygen "$work/keys" || fail "keygen"
pk=$(cat "$work/keys/pk")
COMPILE_FLAGS_a="--hot-reload Derived --signing-pubkey $pk"
compile a
# v1's schema sidecar, as a deploy would have left it.
cp "$dir/node_a.march" "$work/base/base.march"
bg_build "$work/base" "$work/base/build.log" "v1 schema" \
  "$MARCH" --compile --compile-so --hot-reload Derived -o base.so base.march
cp "$dir/node_a_v2.march" "$work/nobase/patch.march"
bg_build "$work/nobase" "$work/nobase/build.log" "patch without a baseline" \
  "$MARCH" --compile --compile-so --hot-reload Derived -o patch.so patch.march
wait_builds
cp "$dir/node_a_v2.march" "$work/v2/patch.march"
bg_build "$work/v2" "$work/v2/build.log" "patch v2" \
  "$MARCH" --compile --compile-so --hot-reload Derived \
  --hcr-baseline "$work/base/base.so.schemas.json" -o patch.so patch.march
wait_builds
grep -q '"migrate_derived": \["label", "history"\]' "$work/v2/patch.so.schemas.json" \
  || fail "v2's schema does not record the derived migration"
grep -q 'migrate_derived' "$work/nobase/patch.so.schemas.json" \
  && fail "a build with no baseline derived a migration"
socks=$(mktemp -d /tmp/hcr-dm.XXXXXX)
export MARCH_HOT_RELOAD_SOCKET=$socks/a.sock
start_node a
wait_line a "ready"
export MARCH_BIN=$MARCH
if ENTRY=$work/nobase/patch.march "$deploy" deploy "$socks/a.sock" "$work/keys" \
  "$work/nobase/patch.so" > "$work/nobase.log" 2>&1; then
  cat "$work/nobase.log" >&2; fail "a state change with no migration was deployed"
fi
grep -q 'compat' "$work/nobase.log" \
  || { cat "$work/nobase.log" >&2; fail "the control was refused for another reason"; }
ENTRY=$work/v2/patch.march "$deploy" deploy "$socks/a.sock" "$work/keys" "$work/v2/patch.so" \
  > "$work/v2.log" 2>&1 || { cat "$work/v2.log" >&2; fail "v2 deploy"; }
grep -q 'actor Counter: migrate_state derived from the running version.s state (adds label, history from init)' \
  "$work/v2.log" || { cat "$work/v2.log" >&2; fail "the deploy did not say the migration was derived"; }
wait_exit a
rm -rf "$socks"
