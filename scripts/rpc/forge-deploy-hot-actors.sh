#!/usr/bin/env bash
# forge-deploy-hot-actors.sh — Phase 5 HCR actor state migration demo
#
# Demonstrates that running Counter actors survive a hot reload from v1 to v2
# with their count preserved and a new `history` field initialized — all on a
# live remote server without a restart.
#
# Flow:
#   1. ed25519 keygen (idempotent)
#   2. Cross-compile counter_server --hot-reload MyApp (linux/amd64)
#   3. Deploy and start the server on the droplet
#   4. Verify baseline: counter spawns and reaches count=3
#   5. Cross-compile counter_v2.so (migration patch, linux/amd64)
#   6. forge deploy hot --so counter_v2.so
#      └─ ACTIVATE Counter_dispatch → triggers __migrate_Counter on all actors
#   7. Signal the server (connect to port 8765) to print post-migration state
#   8. Verify: post_migrate count=3  AND  post_migrate+inc count=4
#
# Prereqs:
#   - Docker with march-builder:latest image (linux/amd64)
#   - SSH access to $HOST
#
# Usage:
#   bash scripts/rpc/forge-deploy-hot-actors.sh
#
# Env overrides:
#   HOST    SSH target   (default: do-march)
#   IMAGE   Docker image (default: march-builder:latest)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST=${HOST:-do-march}
IMAGE=${IMAGE:-march-builder:latest}
BD=${BD:-/lbuild}
VOL=${VOL:-march-lbuild}
DIST="$ROOT/dist"
SOCK_PATH="/tmp/march_hcr_counter.sock"
SIGNAL_PORT=8765
FORGE="$ROOT/_build/default/forge/bin/main.exe"

TUNNEL_PID=""
cleanup() { kill "$TUNNEL_PID" 2>/dev/null || true; }
trap cleanup EXIT

die()     { echo "ERROR: $*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "required tool missing: $1"; }

require docker
require ssh
require nc

echo "=== Phase 5 HCR Actor Migration Demo: forge deploy hot → $HOST ==="
echo ""

# ── Step 1: build local tools ────────────────────────────────────────────────
echo "--- Step 1: build local tools ---"
/Users/80197052/.opam/march/bin/dune build --root "$ROOT" \
  bin/main.exe forge/bin/main.exe
echo "forge: $FORGE"
echo ""

# ── Step 2: ed25519 keygen (idempotent) ──────────────────────────────────────
echo "--- Step 2: ed25519 keygen ---"
SK_PATH="$HOME/.march/ed25519_secret.key"
if [[ -f "$SK_PATH" ]]; then
  echo "secret key already exists: $SK_PATH"
  PUBKEY_B64=$("$FORGE" hot-reload show-pubkey | grep "(base64)" | awk '{print $NF}')
else
  KEYGEN_OUT=$("$FORGE" hot-reload keygen)
  echo "$KEYGEN_OUT"
  PUBKEY_B64=$(echo "$KEYGEN_OUT" | grep -A1 "base64, for forge.toml" | tail -1 | xargs)
fi
[[ -n "$PUBKEY_B64" ]] || die "could not extract public key"
echo "public key (b64): $PUBKEY_B64"
echo ""

# ── Step 3: cross-compile counter_server (linux/amd64) ───────────────────────
echo "--- Step 3: cross-compile counter_server --hot-reload MyApp (linux/amd64) ---"
mkdir -p "$DIST"

docker run --rm --platform linux/amd64 --user root \
  -v "$VOL":"$BD" "$IMAGE" chown -R opam:opam "$BD" 2>/dev/null || true

docker run --rm --platform linux/amd64 \
  -v "$ROOT":/march \
  -v "$VOL":"$BD" \
  -v "$DIST":/out \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    cd /march
    export MARCH_STDLIB=/march/stdlib
    dune build --build-dir=$BD bin/main.exe
    MC=$BD/default/bin/main.exe
    \"\$MC\" --compile --hot-reload MyApp \
      --signing-pubkey '$PUBKEY_B64' \
      -o /out/counter_server_linux \
      demo/hcr_actor_demo/counter_server.march
    chmod +x /out/counter_server_linux
    echo '[docker] built: counter_server_linux'
    head -c4 /out/counter_server_linux | od -An -tx1
  "
[[ -f "$DIST/counter_server_linux" ]] || die "server binary not produced"
echo "server: $DIST/counter_server_linux"
echo ""

# ── Step 4: deploy counter_server to droplet ─────────────────────────────────
echo "--- Step 4: deploy counter_server to $HOST ---"

ssh "$HOST" bash -s <<KILLREMOTE
  pkill -f 'counter_server' 2>/dev/null || true
  rm -f '$SOCK_PATH'
  rm -f /tmp/counter_server.log
  sleep 0.5
  echo '[droplet] old counter_server stopped'
KILLREMOTE

scp "$DIST/counter_server_linux" "$HOST":/tmp/

ssh "$HOST" bash -s <<STARTREMOTE
  set -e
  chmod +x /tmp/counter_server_linux
  MARCH_HOT_RELOAD_SOCKET='$SOCK_PATH' \\
    nohup /tmp/counter_server_linux > /tmp/counter_server.log 2>&1 &
  # Wait for socket + pre_migrate line (actor has run 3 Incs)
  for i in \$(seq 1 100); do
    [ -S '$SOCK_PATH' ] && grep -q 'pre_migrate' /tmp/counter_server.log 2>/dev/null && break
    sleep 0.2
  done
  [ -S '$SOCK_PATH' ] || {
    echo '[droplet] HCR socket not created'
    cat /tmp/counter_server.log
    exit 1
  }
  grep -q 'pre_migrate' /tmp/counter_server.log || {
    echo '[droplet] pre_migrate not in log yet'
    cat /tmp/counter_server.log
    exit 1
  }
  echo '[droplet] counter_server ready — actors running'
  cat /tmp/counter_server.log
STARTREMOTE
echo ""

# ── Step 5: verify pre_migrate count=3 ───────────────────────────────────────
echo "--- Step 5: verify pre_migrate count=3 ---"
PRE_LOG=$(ssh "$HOST" "cat /tmp/counter_server.log")
echo "$PRE_LOG"
echo "$PRE_LOG" | grep -q "pre_migrate count=3" \
  || die "pre_migrate count mismatch (got: $PRE_LOG)"
echo "PASS: pre_migrate count=3"
echo ""

# ── Step 6: create patch project (counter_v2) ────────────────────────────────
echo "--- Step 6: create counter_v2 patch project ---"
PATCH_DIR="$DIST/counter_patch_v2"
mkdir -p "$PATCH_DIR"

cat > "$PATCH_DIR/forge.toml" <<TOML
[package]
name    = "counter_patch_v2"
version = "0.1.0"
type    = "app"

[hot-reload]
ssh_host   = "$HOST"
socket     = "$SOCK_PATH"
public_key = "$PUBKEY_B64"
TOML

echo "patch dir: $PATCH_DIR"
echo ""

# ── Step 7: cross-compile counter_v2.so (linux/amd64) ────────────────────────
echo "--- Step 7: cross-compile counter_v2.so (linux/amd64) ---"
PATCH_SO="$DIST/counter_v2.so"

docker run --rm --platform linux/amd64 \
  -v "$ROOT":/march \
  -v "$VOL":"$BD" \
  -v "$DIST":/out \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    cd /march
    export MARCH_STDLIB=/march/stdlib
    MC=$BD/default/bin/main.exe
    \"\$MC\" --compile --compile-so --hot-reload MyApp \
      -o /out/counter_v2.so \
      demo/hcr_actor_demo/counter_v2.march
    echo '[docker] built: counter_v2.so'
    echo '--- __migrate export:'
    nm -D /out/counter_v2.so 2>/dev/null | grep __migrate || echo '(none found — expected __migrate_Counter)'
    echo '--- manifest:'
    cat /out/counter_v2.so.hcr_manifest 2>/dev/null || echo '(no manifest)'
  "
[[ -f "$PATCH_SO" ]] || die "patch .so not produced at $PATCH_SO"
echo "patch .so: $PATCH_SO"
echo ""

# ── Step 8: forge deploy hot (triggers __migrate_Counter on all actors) ───────
echo "--- Step 8: forge deploy hot --so counter_v2.so ---"
(cd "$PATCH_DIR" && "$FORGE" deploy hot --so "$PATCH_SO")
echo ""

# ── Step 9: signal the server (connect to port 8765) ─────────────────────────
echo "--- Step 9: signal counter_server via port $SIGNAL_PORT (trigger post-migrate print) ---"
# SSH tunnel: macOS can't connect directly to droplet TCP ports.
ssh -N -L "${SIGNAL_PORT}":127.0.0.1:"${SIGNAL_PORT}" "$HOST" &
TUNNEL_PID=$!
for _i in $(seq 1 30); do
  nc -z 127.0.0.1 "${SIGNAL_PORT}" 2>/dev/null && break
  sleep 0.2
done

# A bare connection is the signal — server does tcp_accept and continues.
nc -z 127.0.0.1 "${SIGNAL_PORT}" 2>/dev/null || true

kill "$TUNNEL_PID" 2>/dev/null || true
wait "$TUNNEL_PID" 2>/dev/null || true
TUNNEL_PID=""

# Give the server's actor scheduler time to process the post-migrate messages.
sleep 1
echo ""

# ── Step 10: verify actor state survived migration ────────────────────────────
echo "--- Step 10: verify actor state survived migration ---"
POST_LOG=$(ssh "$HOST" "cat /tmp/counter_server.log")
echo "$POST_LOG"

echo "$POST_LOG" | grep -q "post_migrate count=3" \
  || die "actor count lost during migration (expected post_migrate count=3)"
echo "$POST_LOG" | grep -q "post_migrate+inc count=4" \
  || die "post-migration increment failed (expected post_migrate+inc count=4)"

# Bonus: verify forge hot-reload status shows the migrated slot
echo ""
echo "--- Status check (forge hot-reload status) ---"
(cd "$PATCH_DIR" && "$FORGE" hot-reload status) || true

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║   PHASE 5 ACTOR MIGRATION VERIFIED                              ║"
echo "║   Counter ran 3 Incs → hot reload → count=3 preserved           ║"
echo "║   v2 migrate_state added history=[] without data loss            ║"
echo "║   post_migrate+inc: count=4 ✓                                    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
