# Scenario "hcr_role_policy": hot patches of a topology role body on a node
# that runs under the capability policy `forge host init` generates, through
# both deploy paths
# (specs/progress/2026-10-01-role-body-hot-patch-needs-session-live-in-policy.md).
#
# app.march is a topology app with two pools: node-a runs `back`, which
# serves Echo.Server through the function Back.serve_one, under
# MARCH_DEPLOY_POLICY; node-b runs `front`, which asks it for 4 every 150 ms
# and prints each new answer. Both nodes are control candidates (label
# "control"), so the in-cluster control plane runs too. The policy is
# Host_init.policy_text over the pool and the base build's manifest (the
# pool's written caps, IO.Console and IO.Mut, plus its runner's): IO caps
# only. serve_one's own caps are IO.Console,IO.Mut,Session.Live: the session
# it is handed is a proof capability, which the node's gate does not police.
#
#   v1 (base)  answers n * 10                                        40
#   v2         n * 100 + the Vault mark v1's code set, over the reload
#              socket, as `forge deploy hot` sends it                407
#   v3         n * 1000 + the mark, as a release through the control
#              plane (the Agent relays it to the same gate)          4007
#   v4         answers n, and widens Back.audit (a direct file_write, so
#              it is the function's own cap; reached by no role, so
#              the compiler's grant check cannot see it) to IO.FileWrite,
#              which the operator grants (--grant-cap) but the node's
#              policy does not: ERR cap_policy IO.FileWrite, and the
#              whole batch, serve_one included, is refused           4007
#
# Before the fix, v2 was refused with `ERR cap_policy Session.Live`.
source "$root/test/two_node/control_plane/lib.sh"
FORGE="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
need_built forge/bin/main.exe

proj="$work/proj"
mkdir -p "$proj/src" "$work/keys" "$work/fakebin" "$work/nodes" "$work/home"
for v in 1 2 3 4; do mkdir -p "$work/v$v"; done
printf '#!/bin/sh\necho "ssh $*" >> "%s/ssh.log"\nexit 1\n' "$work" > "$work/fakebin/ssh"
chmod +x "$work/fakebin/ssh"
export PATH="$work/fakebin:$PATH"

cp "$dir/app.march" "$proj/src/role_app.march"
printf '[package]\nname = "role_app"\nversion = "0.1.0"\n' > "$proj/forge.toml"
cat > "$proj/topology.toml" <<'TOML'
[roles]
"Echo.Server" = { body = "RoleApp.Back.serve_one", capacity = 8 }

[pool.back]
start  = "RoleApp.Back.start"
serves = ["Echo.Server"]
caps   = ["IO.Console", "IO.Mut"]

[pool.front]
start = "RoleApp.Front.start"

[control]
candidates = "control"

[drain]
soft_ms = 2000
hard_ms = 5000
TOML
(cd "$proj" && HOME="$work/home" "$FORGE" topology check) > "$work/check.log" 2>&1 \
  || { cat "$work/check.log" >&2; fail "topology check failed"; }
digest="$proj/.forge/topology.json"

"$HCR" keygen "$work/keys" || fail "keygen failed"
pk=$(cat "$work/keys/pk")

# Each version from app.march: the `-- ANSWER` and `-- AUDIT` lines.
version() {
  local v=$1 answer audit
  case $v in
    1) answer='n * env.factor + m * 0' ;;
    2) answer='n * env.factor * 10 + m' ;;
    3) answer='n * env.factor * 100 + m' ;;
    4) answer='n + env.factor * 0 + m * 0' ;;
  esac
  audit='fn audit(_path : String) : Int do 0 end'
  [ "$v" = 4 ] && audit=$'fn audit(path : String) : Int do\n      let _ = file_write(path, "x")\n      1\n    end'
  ANSWER="$answer" AUDIT="$audit" perl -pe '
    s/^(\s*let a = ).*(-- ANSWER)$/$1$ENV{ANSWER} $2/;
    s/^(\s*)fn audit.*(-- AUDIT)$/$1$ENV{AUDIT} $2/' "$dir/app.march" > "$work/v$v/role_app.march"
  grep -qF "$answer -- ANSWER" "$work/v$v/role_app.march" || fail "version $v: the ANSWER line was not rewritten"
}
flags="--hot-reload RoleApp --signing-pubkey $pk --topology $digest"
for v in 1 2 3 4; do
  version "$v"
  (cd "$work/v$v" && HOME="$work/home" "$MARCH" --compile --compile-so $flags -o "$work/v$v/v$v.so" role_app.march) \
    > "$work/patch$v.log" 2>&1 || { cat "$work/patch$v.log" >&2; fail "version $v's patch did not build"; }
  [ -f "$work/v$v/v$v.so.hcr_manifest" ] || fail "no manifest for version $v"
done
(cd "$work/v1" && HOME="$work/home" "$MARCH" --compile $flags -o "$work/node_base" role_app.march) \
  > "$work/compile.log" 2>&1 || { cat "$work/compile.log" >&2; fail "the base did not compile"; }
cp "$work/node_base" "$work/node_a"; cp "$work/node_base" "$work/node_b"

# What the bug was about: the role body's own caps hold the session.
grep -q '^Back.serve_one .*caps=IO.Console,IO.Mut,Session.Live$' "$work/v2/v2.so.hcr_manifest" \
  || fail "serve_one's manifest line no longer holds Session.Live: $(grep '^Back.serve_one ' "$work/v2/v2.so.hcr_manifest")"

# The node policy, as forge host init writes it for the back pool.
"$HCR" policy "$proj" back "$work/v1/v1.so.hcr_manifest" > "$work/back.policy" 2> "$work/policy.err" \
  || { cat "$work/policy.err" >&2; fail "no policy for the back pool"; }
grep -qx "IO.Console" "$work/back.policy" && grep -qx "IO.Mut" "$work/back.policy" \
  || fail "the policy lacks the pool's caps: $(cat "$work/back.policy")"
grep -qx "serves Echo.Server" "$work/back.policy" || fail "the policy does not name the roles back serves: $(cat "$work/back.policy")"
if grep -v '^serves' "$work/back.policy" | grep -qvx 'IO\(\..*\)\{0,1\}'; then fail "the generated policy names a non-IO cap: $(cat "$work/back.policy")"; fi
if grep -qx "IO.FileWrite" "$work/back.policy"; then fail "the policy allows IO.FileWrite: $(cat "$work/back.policy")"; fi

socks=$(mktemp -d /tmp/hs.XXXXXX)
rp_start() {
  local n=$1 pool=$2 seeds=$3 d="$work/nodes/$1"
  mkdir -p "$d/home"
  (
    export MARCH_NODE_NAME=$pool-$n MARCH_NODE_PORT=$(ctl_port "$n") MARCH_NODE_LABELS=control MARCH_CLUSTER_NODES=$seeds
    export MARCH_CLUSTER_SECRET=ctl MARCH_POOLS=$pool MARCH_NODE_CREATION=1
    export MARCH_TOPOLOGY_FILE="$digest" MARCH_TOPOLOGY_STATUS="$d/status"
    export MARCH_HOT_RELOAD_SOCKET="$(ctl_sock "$n")" MARCH_CONTROL_DIR="$d/control"
    export MARCH_CONTROL_PORT_OFFSET=1000 MARCH_PLACEMENT_SETTLE_MS=1500 MARCH_PLACEMENT_TICK_MS=200
    export MARCH_CONTROL_POLL_MS=200
    export ROLE_APP_STOP="$work/stop" HOME="$d/home"
    [ "$pool" = back ] && export MARCH_DEPLOY_POLICY="$work/back.policy"
    run_node "$work/node_$n"
  ) >> "$work/$n.out" 2>> "$work/$n.err" &
  eval "pid_$n=$!"
}
rp_start a back ""
sleep 1
rp_start b front "127.0.0.1:$(ctl_port a)"
wait_line a "back: hook ran"
wait_line b "front: answer 40"

# v2 over the reload socket: what `forge deploy hot` sends (Cmd_deploy_hot.run).
"$HCR" deploy "$(ctl_sock a)" "$work/keys" "$work/v2/v2.so" "$work/v1/v1.so.schemas.json" "$work/v1/v1.so.hcr_manifest" \
  > "$work/deploy_v2.log" 2>&1 || { cat "$work/deploy_v2.log" >&2; fail "the role body patch (v2) was refused over the socket"; }
grep -q "Back.serve_one" "$work/deploy_v2.log" || fail "v2 did not activate serve_one: $(cat "$work/deploy_v2.log")"
wait_line b "front: answer 407"

# v3 through the control plane: a signed release the Agent relays.
ctl_until 40 "a leader" ctl_leader
ctl_until 40 "both nodes reporting" ctl_all_reporting back-a front-b
eps="$(ctl_api_ep a),$(ctl_api_ep b)"
CANARY=0 FOLLOW_S=90 "$HCR" release "$work/keys" "$eps" shared back "$work/v3/v3.so" "$work/v2/v2.so.hcr_manifest" \
  "$work/v2/v2.so.schemas.json" > "$work/release_v3.out" 2>&1 \
  || { cat "$work/release_v3.out" >&2; fail "the role body release (v3) through the control plane failed"; }
grep -q "complete" "$work/release_v3.out" || fail "the v3 release did not complete: $(cat "$work/release_v3.out")"
wait_line b "front: answer 4007"

# v4 widens Back.audit to IO.FileWrite: the operator grants it, the node's
# policy still refuses it, and nothing of v4 runs.
if GRANT_CAPS=IO.FileWrite "$HCR" deploy "$(ctl_sock a)" "$work/keys" "$work/v4/v4.so" \
     "$work/v3/v3.so.schemas.json" "$work/v3/v3.so.hcr_manifest" > "$work/deploy_v4.log" 2>&1; then
  fail "a patch widening to IO.FileWrite beyond the node's policy was admitted: $(cat "$work/deploy_v4.log")"
fi
grep -q "cap_policy IO.FileWrite\|IO.FileWrite.*capability policy\|capability policy.*IO.FileWrite" "$work/deploy_v4.log" \
  || fail "v4 was refused, but not by the node's policy: $(cat "$work/deploy_v4.log")"
sleep 1.5
touch "$work/stop"
wait_line b "front: done"
# Every answer front saw, in order: v4's (4) never.
answers=$(grep '^front: answer ' "$work/b.out" | sed 's/^front: answer //' | tr '\n' ' ')
[ "$answers" = "40 407 4007 " ] || fail "front saw the answers: $answers"
ctl_no_ssh
ctl_done
