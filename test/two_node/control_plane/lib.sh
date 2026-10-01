# Shared by the control-plane scenarios (test/two_node/control_*); sourced from
# their scenario.sh. Three nodes of one topology app (app.march, a hot-reload
# build): a and b are control candidates (label "control"), c is a plain node.
# Every node runs the Agent; the candidates serve the control API, on their
# cluster port + 1000 (MARCH_CONTROL_PORT_OFFSET: they share one machine).
#
# Nothing here reaches a node by ssh. A fake `ssh` first on PATH records any
# attempt, and ctl_no_ssh fails if there was one.

CP="$root/test/two_node/control_plane"
HCR="$root/_build/default/test/hcr_deploy.exe"
need_built test/hcr_deploy.exe

# ctl_prepare [extra compile flags...]: keys, the topology digest, the app
# built once (every node runs the same binary) and its two patches.
ctl_prepare() {
  mkdir -p "$work/keys" "$work/p1" "$work/p2" "$work/fakebin" "$work/nodes"
  "$HCR" keygen "$work/keys" || fail "keygen failed"
  pk=$(cat "$work/keys/pk")
  printf '#!/bin/sh\necho "ssh $*" >> "%s/ssh.log"\nexit 1\n' "$work" > "$work/fakebin/ssh"
  chmod +x "$work/fakebin/ssh"
  export PATH="$work/fakebin:$PATH"
  cat > "$work/topology.json" <<JSON
{ "version": 1, "env": null, "sources": ["topology.toml"], "roles": [],
  "pools": [ { "name": "main", "start": "CtlApp.start", "serves": [], "serves_all": false, "initiates": null,
               "caps": null, "isolate": false, "public": [], "main": null, "replicas": null, "hosts": [] } ],
  "drain": { "soft_ms": 2000, "hard_ms": 5000 }, "backend": null,
  "control": { "candidates": "control", "port": 7947 } }
JSON
  cp "$CP/app.march" "$work/p1/ctl_app.march"
  cp "$CP/app_v2.march" "$work/p2/ctl_app.march"
  local flags="--hot-reload CtlApp --signing-pubkey $pk --topology $work/topology.json"
  (cd "$work/p1" && "$MARCH" --compile $flags "$@" -o "$work/node_a" ctl_app.march) > "$work/compile.log" 2>&1 \
    || { cat "$work/compile.log" >&2; fail "the app did not compile"; }
  cp "$work/node_a" "$work/node_b"; cp "$work/node_a" "$work/node_c"
  for v in 1 2; do
    (cd "$work/p$v" && "$MARCH" --compile --compile-so $flags "$@" -o "$work/p$v/v$v.so" ctl_app.march) > "$work/patch$v.log" 2>&1 \
      || { cat "$work/patch$v.log" >&2; fail "patch $v did not build"; }
  done
  socks=$(mktemp -d /tmp/hs.XXXXXX)
}

ctl_port() { case $1 in a) echo "$PORT_A" ;; b) echo "$PORT" ;; c) echo "$PORT_C" ;; esac; }
ctl_api_ep() { echo "127.0.0.1:$(( $(ctl_port "$1") + 1000 ))"; }
ctl_sock() { echo "$socks/$1.sock"; }

# ctl_start <a|b|c> <labels> <seeds>: start a node, with every setting in its
# environment. Seeds name every candidate (membership gossip does not carry a
# node's address to a node that did not meet it).
ctl_start() {
  local n=$1 labels=$2 seeds=$3 d="$work/nodes/$1"
  mkdir -p "$d/home" "$d/state"
  (
    export MARCH_NODE_NAME=$n MARCH_NODE_PORT=$(ctl_port "$n") MARCH_NODE_LABELS=$labels MARCH_CLUSTER_NODES=$seeds
    export MARCH_CLUSTER_SECRET=ctl MARCH_POOLS=main MARCH_NODE_CREATION=1
    export MARCH_TOPOLOGY_FILE="$work/topology.json" MARCH_TOPOLOGY_STATUS="$d/status"
    export MARCH_HOT_RELOAD_SOCKET="$(ctl_sock "$n")" MARCH_CONTROL_DIR="$d/control"
    export MARCH_CONTROL_PORT_OFFSET=1000 MARCH_PLACEMENT_SETTLE_MS=1500 MARCH_PLACEMENT_TICK_MS=200
    export MARCH_CONTROL_POLL_MS=200 MARCH_CONTROL_SESSION_POLLS=25
    export MARCH_SWIM_PROBE_MS=300 MARCH_SWIM_SUSPECT_MS=1500
    export HOME="$d/home"
    # Certificate mode, when the scenario made a PKI (control_cert).
    if [ -n "${PKI:-}" ]; then
      export MARCH_NODE_CERT="$PKI/$n.cert" MARCH_NODE_KEY="$PKI/$n.key" MARCH_CLUSTER_OPERATOR_PUBKEY="$PKI/operator.pub"
    fi
    exec "$work/node_$n"
  ) >> "$work/$n.out" 2>> "$work/$n.err" &
  eval "pid_$n=$!"
}

# ctl_up: the three nodes, each candidate seeded with the other, c with both.
ctl_up() {
  local pa pb
  pa=$(ctl_port a); pb=$(ctl_port b)
  ctl_start a control ""
  sleep 1
  ctl_start b control "127.0.0.1:$pa"
  ctl_start c "" "127.0.0.1:$pa,127.0.0.1:$pb"
}

# ctl_until <seconds> <description> <command...>: poll until it succeeds.
ctl_until() {
  local limit=$1 what=$2; shift 2
  local i=0
  until "$@" > /dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -gt $((limit * 5)) ] && fail "timed out waiting for: $what"
    sleep 0.2
  done
}

# The candidate that answers LEADER yes.
ctl_leader() {
  local n
  for n in a b; do
    [ -n "$(pid_of "$n")" ] || continue
    if "$HCR" api "$(ctl_api_ep "$n")" LEADER 2> /dev/null | grep -q "^LEADER yes"; then echo "$n"; return 0; fi
  done
  return 1
}

# Every node of $* reports in STATUS (asked of any live candidate).
ctl_status() {
  local n eps=""
  for n in a b; do [ -n "$(pid_of "$n")" ] && eps="$eps,$(ctl_api_ep "$n")"; done
  "$HCR" status "${eps#,}"
}

ctl_all_reporting() { local s; s=$(ctl_status) || return 1; for n in "$@"; do echo "$s" | grep -q "^  $n: " || return 1; done; }

# ctl_release <canary> <canary window ms>: the hot release v1 -> v2, as forge
# deploy on the cluster backend sends it. Output to $work/release.out.
ctl_release() {
  local eps="" n
  for n in a b; do eps="$eps,$(ctl_api_ep "$n")"; done
  CANARY=$1 CANARY_MS=$2 FOLLOW_S=${FOLLOW_S:-90} "$HCR" release "$work/keys" "${eps#,}" render main \
    "$work/p2/v2.so" "$work/p1/v1.so.hcr_manifest" "$work/p1/v1.so.schemas.json"
}

ctl_node_deploys() { "$HCR" reload "$(ctl_sock "$1")" COMPACT | sed -n 's/.*deploys:\([0-9]*\).*/\1/p'; }

ctl_no_ssh() { [ ! -s "$work/ssh.log" ] || fail "something tried to reach a node by ssh: $(cat "$work/ssh.log")"; }

ctl_done() {
  for n in a b c; do kill_node "$n"; done
  rm -rf "$socks"
}
