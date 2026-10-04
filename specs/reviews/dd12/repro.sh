#!/usr/bin/env bash
# DD step 12 security review — reproduction driver (NOT run in CI: there is no
# dune file under specs/, so dune never builds or runs anything here).
#
# Confirms two findings against a real compiled March node:
#   1. (P1) The CAS stores artifact bytes under a client-declared content hash
#      WITHOUT verifying the bytes hash to it; `activate_items` later only
#      `access(F_OK)` + dlopen()s them, so a signed ACTIVATE naming that hash
#      loads whatever bytes an unauthenticated peer put there.  (cas_probe.py
#      over the local reload socket; api_probe.py over the network control API.)
#   2. (P2) AUDIT_COPY on the control API appends attacker-controlled bytes to
#      a candidate's audit log with no authentication.  (api_probe.py)
#
# Usage: bash specs/reviews/dd12/repro.sh
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
march="$root/_build/default/bin/main.exe"
hcr="$root/_build/default/test/hcr_deploy.exe"
[ -x "$march" ] || { echo "build first: dune build --root . bin/main.exe"; exit 2; }
[ -x "$hcr" ]   || { echo "build first: dune build --root . test/hcr_deploy.exe"; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/dd12-repro.XXXXXX")
mkdir -p "$work/keys" "$work/app/home" "$work/app/home2"
"$hcr" keygen "$work/keys"
pk=$(cat "$work/keys/pk")

cp "$root/test/two_node/control_plane/app.march" "$work/app/ctl_app.march"
cat > "$work/app/topology.json" <<'JSON'
{ "version": 1, "env": null, "sources": ["topology.toml"], "roles": [],
  "pools": [ { "name": "main", "start": "CtlApp.start", "serves": [], "serves_all": false, "initiates": null,
               "caps": null, "isolate": false, "public": [], "main": null, "replicas": null, "hosts": [] } ],
  "drain": { "soft_ms": 2000, "hard_ms": 5000 }, "backend": null,
  "control": { "candidates": "control", "port": 7947 } }
JSON
( cd "$work/app" && "$march" --compile --hot-reload CtlApp --signing-pubkey "$pk" \
    --topology "$work/app/topology.json" -o node ctl_app.march ) >/dev/null 2>&1
echo "== node compiled =="

sock="$work/reload.sock"; rm -f "$sock"
# --- finding 1, local reload socket ---
( cd "$work/app" && env MARCH_NODE_NAME=solo MARCH_NODE_PORT=28050 MARCH_POOLS=main \
    MARCH_NODE_CREATION=1 MARCH_CLUSTER_SECRET=x MARCH_HOT_RELOAD_SOCKET="$sock" \
    HOME="$work/app/home" ./node >"$work/node.out" 2>&1 ) &
node_pid=$!
for _ in $(seq 1 50); do [ -S "$sock" ] && break; sleep 0.1; done
echo "== cas_probe over the local reload socket =="
python3 "$root/specs/reviews/dd12/cas_probe.py" "$sock" || true
kill -9 "$node_pid" 2>/dev/null || true

# --- findings 1+2, network control API on a candidate ---
( cd "$work/app" && env MARCH_NODE_NAME=solo MARCH_NODE_PORT=28051 MARCH_POOLS=main \
    MARCH_NODE_CREATION=1 MARCH_CLUSTER_SECRET=x MARCH_NODE_LABELS=control \
    MARCH_CONTROL_PORT_OFFSET=1000 MARCH_CONTROL_DIR="$work/app/control2" \
    MARCH_HOT_RELOAD_SOCKET="$work/reload2.sock" HOME="$work/app/home2" ./node \
    >"$work/cand.out" 2>&1 ) &
cand_pid=$!
for _ in $(seq 1 60); do grep -q "API listening" "$work/cand.out" 2>/dev/null && break; sleep 0.1; done
grep "API listening" "$work/cand.out" || { echo "candidate API did not come up"; cat "$work/cand.out"; }
echo "== api_probe over the unauthenticated network control API (port 29051) =="
python3 "$root/specs/reviews/dd12/api_probe.py" 29051 || true
echo "== audit log on disk (attacker-forged line) =="
tail -2 "$work/app/control2/audit.jsonl" 2>/dev/null || true
kill -9 "$cand_pid" 2>/dev/null || true
echo "== done; workdir $work =="
