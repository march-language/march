#!/usr/bin/env bash
# Capacity-aware routing smoke test (same-host).
#
# Builds load_server + load_client, starts two local server nodes, runs the
# client, and asserts it queried both nodes' headroom over RPC, picked one, and
# executed square(7)=49 on it. On one host both nodes report identical headroom
# (a tie → first node), so this proves the query→pick→route path end-to-end
# without hanging; cross-host headroom *differences* are exercised by deploying
# one server to a remote host (see deploy-droplet.sh / the ssh -L tunnel).
#
# Usage: scripts/rpc/route-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
DUNE=${DUNE:-dune}
PA=${PA:-29853}
PB=${PB:-29852}
SRV=_build/default/demo/load_server.exe
CLI=_build/default/demo/load_client.exe

echo "==> build server + client"
$DUNE build --root . demo/load_server.exe demo/load_client.exe

sa="" ; sb=""
cleanup() { [[ -n "$sa" ]] && kill "$sa" 2>/dev/null || true; [[ -n "$sb" ]] && kill "$sb" 2>/dev/null || true; }
trap cleanup EXIT

"$SRV" "$PA" >/tmp/route_srv_a.log 2>&1 & sa=$!
"$SRV" "$PB" >/tmp/route_srv_b.log 2>&1 & sb=$!
for _ in $(seq 1 50); do
  grep -q ready /tmp/route_srv_a.log 2>/dev/null && grep -q ready /tmp/route_srv_b.log 2>/dev/null && break
  sleep 0.1
done

echo "==> run client (routes between the two local nodes)"
out="$("$CLI" 127.0.0.1 "$PA" 127.0.0.1 "$PB" 2>&1)" || { echo "client failed:"; echo "$out"; exit 1; }
echo "$out"

if echo "$out" | grep -qE "^node A:" && echo "$out" | grep -qE "^node B:" \
   && echo "$out" | grep -q "routing square to node" \
   && echo "$out" | grep -q "= 49"; then
  echo "PASS: queried both nodes over RPC, routed, and executed square(7)=49"
else
  echo "FAIL: unexpected output"
  exit 1
fi
