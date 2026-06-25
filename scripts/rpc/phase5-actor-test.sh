#!/usr/bin/env bash
# phase5-actor-test.sh — HCR Phase 5 end-to-end: actor state migration on DigitalOcean.
#
# Sequence:
#   1. Cross-compile counter_server (linux/amd64) — persistent Counter actor server
#   2. Cross-compile v1.so (linux/amd64) — baseline patch (Counter with count only)
#   3. Cross-compile v2.so (linux/amd64) — migration patch (Counter + history + migrate_state)
#   4. Deploy server binary to droplet, start it
#   5. Verify baseline: server prints "pre_migrate count=3"
#   6. forge deploy hot --so v1.so  (sets schema baseline)
#   7. forge deploy hot --so v2.so  (schema diff: history added → migrate_required=1)
#      → broadcast MARCH_MIGRATE_TAG to all Counter actors
#      → migrate_state called: {count=3} → {count=3, history=[]}
#   8. Connect to server port 8765 to unblock tcp_accept
#   9. Verify: "post_migrate count=3"  (count preserved through migration)
#  10. Verify: "post_migrate+inc count=4"  (actor still works after migration)
#
# Prerequisites:
#   - Docker with march-builder:latest image (linux/amd64)
#   - SSH alias "do-march" configured in ~/.ssh/config
#
# Usage:
#   bash scripts/rpc/phase5-actor-test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${HOST:-do-march}"
IMAGE="${IMAGE:-march-builder:latest}"
BD="${BD:-/lbuild}"
VOL="${VOL:-march-lbuild}"
DIST="$ROOT/dist/phase5"
SOCK_PATH="/tmp/march_counter_p5.sock"
SERVER_PORT=8765
SERVER_LOG="/tmp/counter_server_p5.log"

FORGE="$ROOT/_build/default/forge/bin/main.exe"

cleanup() {
  # Shut down the remote server
  ssh "$HOST" "pkill -f counter_server_p5 2>/dev/null; rm -f '$SOCK_PATH'" 2>/dev/null || true
}
trap cleanup EXIT

die()  { echo "ERROR: $*" >&2; exit 1; }

echo "=== HCR Phase 5: Actor State Migration Demo → $HOST ==="
echo ""

# ── Step 1: build local forge ─────────────────────────────────────────────────
echo "--- Step 1: build local tools ---"
/Users/80197052/.opam/march/bin/dune build --root "$ROOT" \
  bin/main.exe forge/bin/main.exe
echo "forge: $FORGE"
echo ""

# ── Step 2: ed25519 keygen (idempotent) ──────────────────────────────────────
echo "--- Step 2: ed25519 keygen ---"
SK_PATH="$HOME/.march/ed25519_secret.key"
if [[ -f "$SK_PATH" ]]; then
  PUBKEY_B64=$("$FORGE" hot-reload show-pubkey | grep "(base64)" | awk '{print $NF}')
else
  KEYGEN_OUT=$("$FORGE" hot-reload keygen)
  echo "$KEYGEN_OUT"
  PUBKEY_B64=$(echo "$KEYGEN_OUT" | grep -A1 "base64, for forge.toml" | tail -1 | xargs)
fi
[[ -n "$PUBKEY_B64" ]] || die "could not extract public key"
echo "public key: $PUBKEY_B64"
echo ""

mkdir -p "$DIST"

# ── Step 3: cross-compile server + both .so patches ─────────────────────────
echo "--- Step 3: cross-compile (linux/amd64) ---"

# Fix build volume ownership
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

    echo '[docker] building counter_server (persistent server binary)...'
    \"\$MC\" --compile --hot-reload MyApp \\
      --signing-pubkey '$PUBKEY_B64' \\
      -o /out/counter_server_p5 \\
      demo/hcr_actor_demo/counter_server.march
    chmod +x /out/counter_server_p5
    echo '[docker] counter_server_p5 built'

    echo '[docker] building counter_v1.so (baseline patch)...'
    \"\$MC\" --compile --compile-so --hot-reload MyApp \\
      -o /out/counter_v1_p5.so \\
      demo/hcr_actor_demo/counter_v1.march
    echo '[docker] counter_v1_p5.so built'
    echo '--- v1 exported symbols (migration):'
    nm -D /out/counter_v1_p5.so 2>/dev/null | grep __migrate || echo '(none — expected for v1)'
    echo '--- v1 schemas:'
    cat /out/counter_v1_p5.so.schemas.json 2>/dev/null || echo '(no schemas)'

    echo '[docker] building counter_v2.so (migration patch)...'
    \"\$MC\" --compile --compile-so --hot-reload MyApp \\
      -o /out/counter_v2_p5.so \\
      demo/hcr_actor_demo/counter_v2.march
    echo '[docker] counter_v2_p5.so built'
    echo '--- v2 exported symbols (migration, expect __migrate_Counter):'
    nm -D /out/counter_v2_p5.so 2>/dev/null | grep __migrate || echo '(none)'
    echo '--- v2 schemas:'
    cat /out/counter_v2_p5.so.schemas.json 2>/dev/null || echo '(no schemas)'
    echo '--- v2 manifest:'
    cat /out/counter_v2_p5.so.hcr_manifest 2>/dev/null || echo '(no manifest)'
  "

[[ -f "$DIST/counter_server_p5" ]]    || die "server binary not produced"
[[ -f "$DIST/counter_v1_p5.so" ]]     || die "v1.so not produced"
[[ -f "$DIST/counter_v2_p5.so" ]]     || die "v2.so not produced"
[[ -f "$DIST/counter_v2_p5.so.hcr_manifest" ]] || die "v2 manifest not found"
echo ""

# ── Step 4: deploy server to droplet ─────────────────────────────────────────
echo "--- Step 4: deploy + start counter_server on $HOST ---"

# Kill any old instance and clean up
ssh "$HOST" bash -s <<KILLREMOTE
  pkill -f counter_server_p5 2>/dev/null || true
  rm -f '$SOCK_PATH'
  sleep 0.3
  echo '[droplet] old server stopped'
KILLREMOTE

scp "$DIST/counter_server_p5" "$HOST":/tmp/

ssh "$HOST" bash -s <<STARTREMOTE
  set -e
  chmod +x /tmp/counter_server_p5
  MARCH_HOT_RELOAD_SOCKET='$SOCK_PATH' \\
    nohup /tmp/counter_server_p5 > '$SERVER_LOG' 2>&1 &
  echo "[droplet] counter_server_p5 started, log: $SERVER_LOG"
  # Wait for hot-reload socket to appear (up to 10s)
  for i in \$(seq 1 50); do
    [ -S '$SOCK_PATH' ] && break
    sleep 0.2
  done
  [ -S '$SOCK_PATH' ] || { echo 'ERROR: hot-reload socket did not appear'; cat '$SERVER_LOG'; exit 1; }
  echo '[droplet] hot-reload socket ready: $SOCK_PATH'
STARTREMOTE
echo ""

# ── Step 5: verify baseline output ───────────────────────────────────────────
echo "--- Step 5: verify server printed pre_migrate count=3 ---"
# Give the server a moment to print its initial state
sleep 2
PRE=$(ssh "$HOST" "grep 'pre_migrate' '$SERVER_LOG' 2>/dev/null || true")
echo "$PRE"
echo "$PRE" | grep -q "pre_migrate count=3" || die "expected 'pre_migrate count=3', got: $PRE"
echo "PASS: pre_migrate count=3"
echo ""

# ── Step 6: create forge.toml for patch project ──────────────────────────────
echo "--- Step 6: create patch forge.toml ---"
PATCH_DIR="$DIST/patch_project"
mkdir -p "$PATCH_DIR"

cat > "$PATCH_DIR/forge.toml" <<TOML
[package]
name    = "counter_patch"
version = "0.1.0"
type    = "app"

[hot-reload]
ssh_host   = "$HOST"
socket     = "$SOCK_PATH"
public_key = "$PUBKEY_B64"
TOML

echo "forge.toml written for $HOST / $SOCK_PATH"
echo ""

# ── Step 7: deploy v1.so (set schema baseline) ───────────────────────────────
echo "--- Step 7: forge deploy hot --so v1.so (baseline) ---"
(cd "$PATCH_DIR" && "$FORGE" deploy hot --so "$DIST/counter_v1_p5.so")
echo ""

# ── Step 8: deploy v2.so (triggers migration) ────────────────────────────────
echo "--- Step 8: forge deploy hot --so v2.so (migration) ---"
(cd "$PATCH_DIR" && "$FORGE" deploy hot --so "$DIST/counter_v2_p5.so")
echo ""

# Brief pause to let migration messages propagate through the actor's mailbox
sleep 1

# ── Step 9: connect to port 8765 to unblock server's tcp_accept ──────────────
echo "--- Step 9: signal server to continue (connect to port $SERVER_PORT) ---"
# Connect directly from the droplet — avoids SSH-tunnel hang issues.
# -z = scan mode (connect and immediately exit, no I/O), -w 3 = 3s timeout.
ssh "$HOST" "nc -z -w 3 localhost $SERVER_PORT" 2>/dev/null || true
echo "connected to port $SERVER_PORT — server's tcp_accept should now return"
sleep 2
echo ""

# ── Step 10: verify post-migration output ────────────────────────────────────
echo "--- Step 10: verify post-migration state ---"
FULL_LOG=$(ssh "$HOST" "cat '$SERVER_LOG' 2>/dev/null || true")
echo "$FULL_LOG"

echo "$FULL_LOG" | grep -q "post_migrate count=3" \
  || die "expected 'post_migrate count=3' — count not preserved through migration"

echo "$FULL_LOG" | grep -q "post_migrate+inc count=4" \
  || die "expected 'post_migrate+inc count=4' — actor broken after migration"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  HCR PHASE 5 VERIFIED                                       ║"
echo "║  Actor state migration: count 3 → preserved → 4 after Inc   ║"
echo "║  migrate_state ran · \$f_state swapped · v2 handlers active  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
