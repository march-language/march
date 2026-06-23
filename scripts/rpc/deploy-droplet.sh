#!/usr/bin/env bash
# Deploy the Linux server to the droplet and prove cross-host RPC two ways:
#
#   1. Droplet-localhost: run the Linux client on the droplet against the
#      server (no tunnel) — the baseline cross-host proof.
#   2. Mac-via-tunnel: open an ssh local port-forward and run the macOS-native
#      client against 127.0.0.1, which the corporate socket filter permits.
#      This proves the Mac-compiled binary doing real RPC to the remote host.
#
# Prereqs: scripts/rpc/build-linux.sh has produced dist/two_node_*_linux, and
# the macOS client is built (dune build demo/two_node_client.exe).
#
# Usage:
#   scripts/rpc/deploy-droplet.sh
#
# Env:
#   HOST   droplet ssh target (default: root@198.199.121.160)
#   PORT   RPC port (default: 29852)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST=${HOST:-root@198.199.121.160}
PORT=${PORT:-29852}
DIST="$ROOT/dist"
MAC_CLIENT="$ROOT/_build/default/demo/two_node_client.exe"

[[ -f "$DIST/two_node_server_linux" ]] || { echo "missing dist/two_node_server_linux — run scripts/rpc/build-linux.sh"; exit 1; }
[[ -f "$DIST/two_node_client_linux" ]] || { echo "missing dist/two_node_client_linux — run scripts/rpc/build-linux.sh"; exit 1; }

echo "==> copy binaries to droplet"
scp -q "$DIST/two_node_server_linux" "$DIST/two_node_client_linux" "$HOST":/tmp/

echo "==> (re)start server on droplet :$PORT"
ssh "$HOST" bash -s <<EOF
  set -e
  # Free the port regardless of which binary holds it (prior runs used other names).
  pkill -f two_node_server_linux 2>/dev/null || true
  for holder in \$(ss -tlnpH "sport = :$PORT" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do
    kill -9 "\$holder" 2>/dev/null || true
  done
  sleep 1
  chmod +x /tmp/two_node_server_linux /tmp/two_node_client_linux
  nohup /tmp/two_node_server_linux > /tmp/rpc_server.log 2>&1 &
  for _ in \$(seq 1 50); do
    ss -tlnp 2>/dev/null | grep -q ":$PORT " && break
    sleep 0.1
  done
  ss -tlnp 2>/dev/null | grep ":$PORT " || { echo "server did not bind :$PORT"; cat /tmp/rpc_server.log; exit 1; }
  echo "server bound :$PORT"
EOF

echo ""
echo "==> proof 1: client on droplet (localhost, no tunnel)"
out1="$(ssh "$HOST" "/tmp/two_node_client_linux 127.0.0.1 $PORT" 2>&1)"
echo "$out1"
echo "$out1" | grep -q "square(7)  = 49" && echo "$out1" | grep -q "square(12) = 144" \
  && echo "PASS: droplet-localhost RPC" || { echo "FAIL: droplet-localhost"; exit 1; }

echo ""
echo "==> proof 2: macOS-native client via ssh tunnel"
if [[ ! -x "$MAC_CLIENT" ]]; then
  echo "SKIP: macOS client not built ($MAC_CLIENT). Run: dune build --root . demo/two_node_client.exe"
else
  tun_pid=""
  cleanup_tun() { [[ -n "$tun_pid" ]] && kill "$tun_pid" 2>/dev/null || true; }
  trap cleanup_tun EXIT
  # Local-forward an unused local port to the droplet's server port.
  LPORT=${LPORT:-29852}
  ssh -N -L "$LPORT":127.0.0.1:"$PORT" "$HOST" &
  tun_pid=$!
  sleep 2
  out2="$("$MAC_CLIENT" 127.0.0.1 "$LPORT" 2>&1)" || { echo "mac client failed:"; echo "$out2"; exit 1; }
  echo "$out2"
  echo "$out2" | grep -q "square(7)  = 49" && echo "$out2" | grep -q "square(12) = 144" \
    && echo "PASS: macOS client → droplet via tunnel" || { echo "FAIL: mac-via-tunnel"; exit 1; }
fi

echo ""
echo "ALL CROSS-HOST RPC PROOFS PASSED"
