#!/usr/bin/env bash
# forge-deploy-hot.sh — Phase 4 HCR demo: forge deploy hot to DigitalOcean.
#
# Demonstrates the full Phase 4 flow:
#   1. ed25519 keygen (idempotent)
#   2. Cross-compile hcr_server --signing-pubkey <b64> --hot-reload Server (linux/amd64)
#   3. Deploy and start the server on the droplet
#   4. Verify baseline: square(7) = 49
#   5. Cross-compile patch .so + .hcr_manifest (linux/amd64)
#   6. forge deploy hot --so dist/hcr_patch_p4.so
#      ├─ SSH tunnel → remote reload socket
#      ├─ VERSIONS (crash-restart drift detection)
#      ├─ ABI_QUERY (set-diff against running impl_hash values)
#      ├─ CAS_CHECK / CAS_PUT (upload artifact)
#      └─ ed25519-signed ACTIVATE per changed function
#   7. Verify post-reload: square(7) = 343
#
# Prereqs:
#   - Docker with march-builder:latest image (linux/amd64)
#   - SSH access to $HOST
#
# Usage:
#   bash scripts/rpc/forge-deploy-hot.sh
#
# Env overrides:
#   HOST    SSH target   (default: root@198.199.121.160)
#   PORT    RPC TCP port (default: 29852)
#   IMAGE   Docker image (default: march-builder:latest)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST=${HOST:-root@198.199.121.160}
PORT=${PORT:-29852}
IMAGE=${IMAGE:-march-builder:latest}
BD=${BD:-/lbuild}
VOL=${VOL:-march-lbuild}
DIST="$ROOT/dist"
# Per-worktree socket name avoids collisions across concurrent sessions.
SLUG="$(basename "$ROOT")"
SOCK_PATH="/tmp/march_hcr_${SLUG}.sock"
FORGE="$ROOT/_build/default/forge/bin/main.exe"
CLIENT="$ROOT/_build/default/demo/hcr_client.exe"

die()     { echo "ERROR: $*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "required tool missing: $1"; }

require docker
require ssh

echo "=== Phase 4 HCR Demo: forge deploy hot → $HOST ==="
echo ""

# ── Step 1: build local tools ────────────────────────────────────────────────
echo "--- Step 1: build local tools ---"
/Users/80197052/.opam/march/bin/dune build --root "$ROOT" \
  bin/main.exe forge/bin/main.exe demo/hcr_client.exe
echo "forge:  $FORGE"
echo "client: $CLIENT"
echo ""

# ── Step 2: ed25519 keygen (idempotent) ──────────────────────────────────────
echo "--- Step 2: ed25519 keygen ---"
SK_PATH="$HOME/.march/ed25519_secret.key"
if [[ -f "$SK_PATH" ]]; then
  echo "secret key already exists: $SK_PATH"
  # show-pubkey output: "Public key (base64): <b64>"
  PUBKEY_B64=$("$FORGE" hot-reload show-pubkey | grep "(base64)" | awk '{print $NF}')
else
  KEYGEN_OUT=$("$FORGE" hot-reload keygen)
  echo "$KEYGEN_OUT"
  # keygen output includes a line "  <b64>" after "Public key (base64, for forge.toml...)"
  PUBKEY_B64=$(echo "$KEYGEN_OUT" | grep -A1 "base64, for forge.toml" | tail -1 | xargs)
fi
[[ -n "$PUBKEY_B64" ]] || die "could not extract public key"
echo "public key (b64): $PUBKEY_B64"
echo ""

# ── Step 3: cross-compile hcr_server WITH --signing-pubkey (linux/amd64) ────
echo "--- Step 3: cross-compile hcr_server --signing-pubkey (linux/amd64) ---"
mkdir -p "$DIST"

# Ensure build volume ownership is correct.
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
    # --signing-pubkey accepts base64 (compiler converts to hex internally)
    \"\$MC\" --compile --hot-reload Server \
      --signing-pubkey '$PUBKEY_B64' \
      -o /out/hcr_server_p4_linux \
      demo/hcr_server.march
    chmod +x /out/hcr_server_p4_linux
    echo '[docker] built: hcr_server_p4_linux'
    head -c4 /out/hcr_server_p4_linux | od -An -tx1
  "
[[ -f "$DIST/hcr_server_p4_linux" ]] || die "server binary not produced"
echo "server: $DIST/hcr_server_p4_linux"
echo ""

# ── Step 4: deploy server to droplet ────────────────────────────────────────
echo "--- Step 4: deploy server to $HOST ---"

# Kill all old server processes first (so scp can overwrite the binary).
ssh "$HOST" bash -s <<KILLREMOTE
  fuser -k '${PORT}/tcp' 2>/dev/null || true
  pkill -f 'hcr_server' 2>/dev/null || true
  rm -f '$SOCK_PATH'
  sleep 0.5
  echo '[droplet] old servers stopped'
KILLREMOTE

scp "$DIST/hcr_server_p4_linux" "$HOST":/tmp/

ssh "$HOST" bash -s <<STARTREMOTE
  set -e
  chmod +x /tmp/hcr_server_p4_linux
  MARCH_HOT_RELOAD_SOCKET='$SOCK_PATH' \\
    nohup /tmp/hcr_server_p4_linux > /tmp/hcr_server_p4.log 2>&1 &
  for i in \$(seq 1 60); do
    ss -tlnp 2>/dev/null | grep -q ':$PORT ' && break
    sleep 0.2
  done
  ss -tlnp 2>/dev/null | grep ':$PORT ' || {
    echo 'server did not bind :$PORT'; cat /tmp/hcr_server_p4.log; exit 1
  }
  echo '[droplet] hcr_server_p4_linux ready on :$PORT (socket: $SOCK_PATH)'
STARTREMOTE
echo ""

# ── Step 5: verify baseline square(7) = 49 ──────────────────────────────────
echo "--- Step 5: verify baseline square(7) = 49 ---"
# Use SSH tunnel: the march macOS binary can't make direct outbound TCP connections
# to remote IPs (macOS network privacy for unsigned binaries), but localhost works.
LPORT=29862  # local forwarding port — avoids clash with remote PORT
ssh -N -L "${LPORT}":127.0.0.1:"${PORT}" "$HOST" &
TUNNEL1_PID=$!
# Poll until local port is bound (up to 6 seconds)
for _i in $(seq 1 30); do
  nc -z 127.0.0.1 "${LPORT}" 2>/dev/null && break
  sleep 0.2
done

OUT_BEFORE=$("$CLIENT" 127.0.0.1 "$LPORT" 7 2>&1 || true)
echo "$OUT_BEFORE"

kill "$TUNNEL1_PID" 2>/dev/null || true
wait "$TUNNEL1_PID" 2>/dev/null || true

echo "$OUT_BEFORE" | grep -q "square(7) = 49" \
  || die "baseline check failed (got: $OUT_BEFORE)"
echo "PASS: square(7) = 49"
echo ""

# ── Step 6: write forge.toml + patch source ──────────────────────────────────
echo "--- Step 6: create patch project ---"
PATCH_DIR="$DIST/hcr_patch_p4"
mkdir -p "$PATCH_DIR"

# forge.toml for the patch project — forge deploy hot reads [hot-reload] from here.
cat > "$PATCH_DIR/forge.toml" <<TOML
[package]
name    = "hcr_patch_p4"
version = "0.1.0"
type    = "app"

[hot-reload]
ssh_host   = "$HOST"
socket     = "$SOCK_PATH"
public_key = "$PUBKEY_B64"
TOML

# Patch: Server.square n*n → n*n*n (same structure as hcr_server.march, body changed).
cat > "$PATCH_DIR/main.march" <<'MARCH'
mod App do
  needs IO.NetListen

  mod Server do
    fn square(n : Int) : Int do n * n * n end

    pfn square__rpc_stub(args : List(Int)) : Result(List(Int), String) do
      match Msgpack.decode(args) do
        Err(e) -> Err(e)
        Ok(v) ->
          match v do
            Msgpack.Array(Cons(Msgpack.Int(n), Nil)) ->
              Ok(Msgpack.encode(Msgpack.int(square(n))))
            _ -> Err("square: expected one Int argument")
          end
      end
    end

    fn report_load(_tag : Int) : List(Int) do
      ClusterLoad.to_ints(ClusterLoad.local("node"))
    end

    pfn report_load__rpc_stub(args : List(Int)) : Result(List(Int), String) do
      match Msgpack.decode(args) do
        Err(e) -> Err(e)
        Ok(v) ->
          match v do
            Msgpack.Array(Cons(Msgpack.Int(tag), Nil)) ->
              let metrics = report_load(tag)
              let items = List.map(metrics, fn x -> Msgpack.int(x))
              Ok(Msgpack.encode(Msgpack.array(items)))
            _ -> Err("report_load: expected one Int argument")
          end
      end
    end
  end

  fn main() do
    println("patch placeholder")
  end
end
MARCH

echo "patch dir: $PATCH_DIR"
echo ""

# ── Step 7: cross-compile patch .so for linux/amd64 ─────────────────────────
echo "--- Step 7: cross-compile patch .so (linux/amd64) ---"
PATCH_SO="$DIST/hcr_patch_p4.so"

docker run --rm --platform linux/amd64 \
  -v "$ROOT":/march \
  -v "$VOL":"$BD" \
  -v "$DIST":/out \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    cd /march
    export MARCH_STDLIB=/march/stdlib
    # Reuse the compiler binary from Step 3 (same build dir).
    MC=$BD/default/bin/main.exe
    \"\$MC\" --compile --compile-so --hot-reload Server \
      -o /out/hcr_patch_p4.so \
      /out/hcr_patch_p4/main.march
    echo '[docker] built: hcr_patch_p4.so'
    head -c4 /out/hcr_patch_p4.so | od -An -tx1
    echo '--- exported symbols (Server.*):'
    nm -D /out/hcr_patch_p4.so 2>/dev/null | grep -i 'server\.' | head -20 || true
    echo '--- manifest:'
    cat /out/hcr_patch_p4.so.hcr_manifest 2>/dev/null || echo '(no manifest found)'
  "
[[ -f "$PATCH_SO" ]] || die "patch .so not produced at $PATCH_SO"
[[ -f "${PATCH_SO}.hcr_manifest" ]] || die "manifest not found: ${PATCH_SO}.hcr_manifest"
echo "patch .so:  $PATCH_SO"
echo "manifest:   ${PATCH_SO}.hcr_manifest"
echo ""

# ── Step 8: forge deploy hot --so dist/hcr_patch_p4.so ─────────────────────
echo "--- Step 8: forge deploy hot ---"
# forge reads forge.toml from cwd for [hot-reload] config (ssh_host, socket, public_key).
# The --so flag bypasses the local build step (pre-built linux/amd64 artifact).
(cd "$PATCH_DIR" && "$FORGE" deploy hot --so "$PATCH_SO")
echo ""

# ── Step 9: verify square(7) = 343 after hot reload ─────────────────────────
echo "--- Step 9: verify square(7) = 343 after hot reload ---"
ssh -N -L "${LPORT}":127.0.0.1:"${PORT}" "$HOST" &
TUNNEL2_PID=$!
for _i in $(seq 1 30); do
  nc -z 127.0.0.1 "${LPORT}" 2>/dev/null && break
  sleep 0.2
done

OUT_AFTER=$("$CLIENT" 127.0.0.1 "$LPORT" 7 2>&1 || true)
echo "$OUT_AFTER"

kill "$TUNNEL2_PID" 2>/dev/null || true
wait "$TUNNEL2_PID" 2>/dev/null || true

echo "$OUT_AFTER" | grep -q "square(7) = 343" \
  || die "post-reload check failed (got: $OUT_AFTER)"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   PHASE 4 HCR VERIFIED                                  ║"
echo "║   square(7): 49 → 343                                   ║"
echo "║   live server · no restart · ed25519-signed · CAS-dist  ║"
echo "╚══════════════════════════════════════════════════════════╝"
