# Scenario "control_forge_deploy" (dd step 12a): the real `forge deploy` on the
# cluster backend. A forge project whose topology has a [control] section and
# an ssh overlay (`topology.local.toml`, hosts a and b labelled "control", c
# plain) runs as three local nodes started from its v1 base build; forge
# recorded v1 as deployed. The working tree then changes `Ver.version`, and:
#
#   forge deploy --env local --plan   says every step goes through the control
#                                     plane and prints the release it would sign
#   forge deploy --env local --yes    builds, classifies, writes and signs the
#                                     release, uploads the patch, sends it and
#                                     follows it to "complete", with no ssh
#   forge deploy --env local --status the leader's view: every node holds it
#   forge deploy --env local --audit  the release accepted and a step ordered
#                                     on every node, from the candidates' logs
#
# Then a release refused at the compare-and-set (a stale seq, sent as-is) is
# in the audit log too. A fake `ssh` first on PATH records any attempt.
source "$root/test/two_node/control_plane/lib.sh"
FORGE="${FORGE_BIN:-$root/_build/default/forge/bin/main.exe}"
need_built forge/bin/main.exe

proj="$work/proj"
mkdir -p "$proj/src" "$work/bin" "$work/home" "$work/fakebin" "$work/nodes"
# Wrappers, not symlinks: the compiler finds its stdlib and runtime next to
# its own executable, which a symlink's directory is not.
printf '#!/bin/sh\nexec "%s" "$@"\n' "$MARCH" > "$work/bin/march"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$FORGE" > "$work/bin/forge"
chmod +x "$work/bin/march" "$work/bin/forge"
printf '#!/bin/sh\necho "ssh $*" >> "%s/ssh.log"\nexit 1\n' "$work" > "$work/fakebin/ssh"
chmod +x "$work/fakebin/ssh"
export PATH="$work/fakebin:$work/bin:$PATH" HOME="$work/home"
# Hosts of this machine's own target are built natively (no zig cross build).
export FORGE_DEPLOY_NATIVE=1
export FORGE_CONTROL_ENDPOINTS="$(ctl_api_ep a),$(ctl_api_ep b)"

cp "$CP/app.march" "$proj/src/ctl_app.march"
printf '[package]\nname = "ctl_app"\nversion = "0.1.0"\n' > "$proj/forge.toml"
cat > "$proj/topology.toml" <<'TOML'
[pool.main]
start = "CtlApp.start"

[control]
candidates = "control"

[drain]
soft_ms = 2000
hard_ms = 5000
TOML
cat > "$proj/topology.local.toml" <<'TOML'
[backend]
kind = "ssh"

[pool.main]
hosts = [ { host = "a", labels = ["control"] }, { host = "b", labels = ["control"] }, { host = "c" } ]
TOML

(cd "$proj" && forge hot-reload keygen) > "$work/keygen.log" 2>&1 || { cat "$work/keygen.log" >&2; fail "keygen failed"; }
pk=$(sed -n 's/^ *public_key = "\(.*\)"$/\1/p' "$work/keygen.log")
[ -n "$pk" ] || fail "no public key in: $(cat "$work/keygen.log")"
(cd "$proj" && forge topology check --env local) > "$work/check.log" 2>&1 || { cat "$work/check.log" >&2; fail "topology check failed"; }
digest="$proj/.forge/topology.json"

# v1, built as forge builds it: the base image every node runs, and its patch,
# whose manifest is what forge records as deployed.
flags="--hot-reload CtlApp --signing-pubkey $pk --topology $digest"
mkdir -p "$work/v1"
(cd "$work/v1" && "$MARCH" --compile $flags -o "$work/node_base" "$proj/src/ctl_app.march") > "$work/compile.log" 2>&1 \
  || { cat "$work/compile.log" >&2; fail "the base did not compile"; }
(cd "$work/v1" && "$MARCH" --compile --compile-so $flags -o "$work/v1/v1.so" "$proj/src/ctl_app.march") > "$work/patch1.log" 2>&1 \
  || { cat "$work/patch1.log" >&2; fail "the v1 patch did not build"; }
dep="$proj/.forge/deploy/local"
mkdir -p "$dep" "$proj/.forge/hosts"
cp "$work/v1/v1.so.hcr_manifest" "$dep/shared.hcr_manifest"
[ -f "$work/v1/v1.so.schemas.json" ] && cp "$work/v1/v1.so.schemas.json" "$dep/shared.schemas.json"
cp "$digest" "$dep/topology.json"
case "$(uname -sm)" in
  "Darwin arm64") target=darwin/arm64 ;; "Darwin x86_64") target=darwin/amd64 ;;
  "Linux x86_64") target=linux/amd64 ;; "Linux aarch64") target=linux/arm64 ;;
  *) fail "unknown machine: $(uname -sm)" ;;
esac
cat > "$proj/.forge/hosts/local.json" <<JSON
{ "version": 1, "env": "local", "hosts": [
  { "host": "a", "pool": "main", "node": "main-a", "target": "$target", "triple": "-", "uname": "-", "initialized_at": 0 },
  { "host": "b", "pool": "main", "node": "main-b", "target": "$target", "triple": "-", "uname": "-", "initialized_at": 0 },
  { "host": "c", "pool": "main", "node": "main-c", "target": "$target", "triple": "-", "uname": "-", "initialized_at": 0 } ] }
JSON
for n in a b c; do cp "$work/node_base" "$work/node_$n"; done
socks=$(mktemp -d /tmp/hs.XXXXXX)

# The nodes, named as forge names an ssh host's node (pool-host).
fd_start() {
  local n=$1 labels=$2 seeds=$3 d="$work/nodes/$1"
  mkdir -p "$d/home"
  (
    export MARCH_NODE_NAME=main-$n MARCH_NODE_PORT=$(ctl_port "$n") MARCH_NODE_LABELS=$labels MARCH_CLUSTER_NODES=$seeds
    export MARCH_CLUSTER_SECRET=ctl MARCH_POOLS=main MARCH_NODE_CREATION=1
    export MARCH_TOPOLOGY_FILE="$digest" MARCH_TOPOLOGY_STATUS="$d/status"
    export MARCH_HOT_RELOAD_SOCKET="$(ctl_sock "$n")" MARCH_CONTROL_DIR="$d/control"
    export MARCH_CONTROL_PORT_OFFSET=1000 MARCH_PLACEMENT_SETTLE_MS=1500 MARCH_PLACEMENT_TICK_MS=200
    export MARCH_CONTROL_POLL_MS=200 MARCH_SWIM_PROBE_MS=300 MARCH_SWIM_SUSPECT_MS=1500
    export HOME="$d/home"
    exec "$work/node_$n"
  ) >> "$work/$n.out" 2>> "$work/$n.err" &
  eval "pid_$n=$!"
}
fd_start a control ""
sleep 1
fd_start b control "127.0.0.1:$(ctl_port a)"
fd_start c "" "127.0.0.1:$(ctl_port a),127.0.0.1:$(ctl_port b)"
ctl_until 40 "a leader" ctl_leader
fd_reporting() { local s; s=$(ctl_status) || return 1; for n in a b c; do echo "$s" | grep -q "^  main-$n: " || return 1; done; }
ctl_until 40 "every node reporting" fd_reporting

# The new version.
cp "$CP/app_v2.march" "$proj/src/ctl_app.march"

(cd "$proj" && forge deploy --env local --plan) > "$work/plan.out" 2>&1 || { cat "$work/plan.out" >&2; fail "forge deploy --plan failed"; }
grep -q "Through the control plane" "$work/plan.out" || fail "the plan does not say how the control plane carries it: $(cat "$work/plan.out")"
grep -q "nothing needs ssh" "$work/plan.out" || fail "the plan does not say that nothing needs ssh: $(cat "$work/plan.out")"
grep -q "^release v1$" "$work/plan.out" || fail "the plan does not print the release it would sign: $(cat "$work/plan.out")"
grep -q "do:activate(shared)" "$work/plan.out" || fail "the release has no activate step: $(cat "$work/plan.out")"
grep -q "^sig [0-9a-f]\{128\}$" "$work/plan.out" || fail "the release is not signed: $(cat "$work/plan.out")"
[ "$(ctl_node_deploys a)" = 0 ] || fail "--plan changed a node"

(cd "$proj" && forge deploy --env local --yes --canary 1 --timeout 1500) > "$work/deploy.out" 2>&1 \
  || { cat "$work/deploy.out" >&2; fail "forge deploy failed"; }
grep -q "deploy complete" "$work/deploy.out" || fail "the deploy did not complete: $(cat "$work/deploy.out")"
grep -q "release [0-9]* accepted" "$work/deploy.out" || fail "no release was accepted: $(cat "$work/deploy.out")"
grep -q "step 2 of 2" "$work/deploy.out" || fail "no per-step progress: $(cat "$work/deploy.out")"
for n in a b c; do
  [ "$(ctl_node_deploys "$n")" = 1 ] || fail "node $n applied the release $(ctl_node_deploys "$n") times, not once"
done
# What forge recorded is the new version: a second deploy has nothing to do.
(cd "$proj" && forge deploy --env local --yes) > "$work/deploy2.out" 2>&1 || { cat "$work/deploy2.out" >&2; fail "the second deploy failed"; }
grep -q "nothing to deploy" "$work/deploy2.out" || fail "the second deploy was not a no-op: $(cat "$work/deploy2.out")"

(cd "$proj" && forge deploy --env local --status) > "$work/status.out" 2>&1 || { cat "$work/status.out" >&2; fail "--status failed"; }
grep -q ": complete" "$work/status.out" || fail "--status does not show the release complete: $(cat "$work/status.out")"

seq=$(sed -n 's/^release \([0-9]*\) accepted.*/\1/p' "$work/deploy.out" | head -1)
[ -n "$seq" ] || fail "no release seq in: $(cat "$work/deploy.out")"
sleep 2
(cd "$proj" && forge deploy --env local --audit) > "$work/audit.out" 2>&1 || { cat "$work/audit.out" >&2; fail "--audit failed"; }
grep -q "\"type\":\"release\".*\"seq\":$seq,.*\"result\":\"ok\"" "$work/audit.out" || fail "the audit log lacks the accepted release: $(cat "$work/audit.out")"
for n in a b c; do
  grep -q "\"type\":\"order\".*\"node\":\"main-$n\"" "$work/audit.out" || fail "the audit log lacks an order to main-$n: $(cat "$work/audit.out")"
done
grep -q "\"type\":\"complete\".*\"seq\":$seq" "$work/audit.out" || fail "the audit log lacks the completion: $(cat "$work/audit.out")"
# Both candidates hold the log (the leader copies its lines to the other).
for n in a b; do
  "$HCR" api "$(ctl_api_ep "$n")" AUDIT > "$work/audit_$n.out" 2>&1
  grep -q "\"seq\":$seq,.*\"result\":\"ok\"" "$work/audit_$n.out" || fail "candidate $n's audit log lacks the release: $(cat "$work/audit_$n.out")"
done

# A refusal at the compare-and-set: a release older than the head.
"$HCR" release-stale "$FORGE_CONTROL_ENDPOINTS" "$((seq - 1))" > "$work/stale.out" 2>&1
grep -q "ERR stale" "$work/stale.out" || fail "a stale release was not refused: $(cat "$work/stale.out")"
sleep 2
(cd "$proj" && forge deploy --env local --audit 3) > "$work/audit2.out" 2>&1 || fail "--audit 3 failed"
grep -q "\"result\":\"err_stale\"" "$work/audit2.out" || fail "the refusal is not audited: $(cat "$work/audit2.out")"
[ "$(grep -c '"type"' "$work/audit2.out")" = 3 ] || fail "--audit 3 did not show 3 lines: $(cat "$work/audit2.out")"

ctl_no_ssh
ctl_done
