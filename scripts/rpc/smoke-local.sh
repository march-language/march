#!/usr/bin/env bash
# Same-host RPC smoke test.
#
# Builds the two demo binaries, launches the server in the background, runs the
# client against 127.0.0.1, and asserts the two remote calls return 49 and 144.
# Exits non-zero (and prints captured output) on any mismatch — suitable as a
# fast inner-loop regression check for the distributed RPC path.
#
# Usage:
#   scripts/rpc/smoke-local.sh            # build + run
#   PORT=29853 scripts/rpc/smoke-local.sh # override port
#
# Env:
#   DUNE   dune binary (default: dune)
#   PORT   listen port (default: 29852)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DUNE=${DUNE:-dune}
PORT=${PORT:-29852}
SERVER=_build/default/demo/two_node_server.exe
CLIENT=_build/default/demo/two_node_client.exe

echo "==> build server + client"
$DUNE build --root . demo/two_node_server.exe demo/two_node_client.exe

SRV_LOG="$(mktemp -t rpc_smoke_srv.XXXXXX)"
srv_pid=""
cleanup() {
  [[ -n "$srv_pid" ]] && kill "$srv_pid" 2>/dev/null || true
  rm -f "$SRV_LOG"
}
trap cleanup EXIT

echo "==> start server on :$PORT"
"$SERVER" >"$SRV_LOG" 2>&1 &
srv_pid=$!

# Wait (max 5s) for the listener to announce readiness.
for _ in $(seq 1 50); do
  grep -q "server ready" "$SRV_LOG" 2>/dev/null && break
  kill -0 "$srv_pid" 2>/dev/null || { echo "server died early:"; cat "$SRV_LOG"; exit 1; }
  sleep 0.1
done

echo "==> run client against 127.0.0.1:$PORT"
out="$("$CLIENT" 127.0.0.1 "$PORT" 2>&1)" || { echo "client failed:"; echo "$out"; exit 1; }
echo "$out"

if echo "$out" | grep -q "square(7)  = 49" && echo "$out" | grep -q "square(12) = 144"; then
  echo "PASS: local RPC returned 49 and 144"
  exit 0
else
  echo "FAIL: unexpected client output"
  echo "--- server log ---"; cat "$SRV_LOG"
  exit 1
fi
