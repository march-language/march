#!/usr/bin/env bash
# hot-deploy.sh — demonstrate live hot reload against the DigitalOcean droplet.
#
# Builds hcr_server with --hot-reload Server (nested mod Server in mod App),
# deploys to the droplet, then compiles a patch that changes square(n) from
# n*n to n*n*n and delivers it over the reload socket while the server is
# live — no restart, no downtime.
#
# Why nested modules matter:
#   With `mod App do fn square...end`, TIR emits the symbol as plain `square`,
#   so `module_of_name("square") = ""` ≠ "App" and nothing is reloadable.
#   With `mod App do mod Server do fn square...end end`, TIR emits `Server.square`
#   and `--hot-reload Server` correctly marks it as a dispatch boundary.
#
# Prereqs:
#   - Docker (for cross-compiling to linux/amd64)
#   - march-builder Docker image (see scripts/rpc/build-linux.sh for build instructions)
#   - SSH access to 198.199.121.160 (root)
#   - socat on macOS (brew install socat)
#
# Usage:
#   bash scripts/rpc/hot-deploy.sh
#
# Env:
#   HOST     droplet SSH target (default: root@198.199.121.160)
#   PORT     RPC port (default: 29852)
#   IMAGE    Docker builder image (default: march-builder:latest)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST=${HOST:-root@198.199.121.160}
PORT=${PORT:-29852}
IMAGE=${IMAGE:-march-builder:latest}
BD=${BD:-/lbuild}
VOL=${VOL:-march-lbuild}
DIST="$ROOT/dist"
SLUG="$(basename "$ROOT")"
SOCK_PATH="/tmp/march_hcr_${SLUG}.sock"

die() { echo "ERROR: $*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "required tool missing: $1"; }

require docker
require ssh
require socat

echo "=== HCR Phase 3 Demo: live hot reload to $HOST ==="
echo ""

# ── Step 1: cross-compile hcr_server WITH --hot-reload Server ───────────────
echo "--- Step 1: cross-compile hcr_server --hot-reload Server (linux/amd64) ---"
mkdir -p "$DIST"

docker run --rm --platform linux/amd64 \
  -v "$ROOT":/march \
  -v "$VOL":"$BD" \
  -v "$DIST":/out \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    cd /march
    export MARCH_STDLIB=/march/stdlib
    /Users/80197052/.opam/march/bin/dune build --build-dir=$BD bin/main.exe
    MC=$BD/default/bin/main.exe
    \"\$MC\" --compile --hot-reload Server \
      -o /out/hcr_server_linux demo/hcr_server.march
    chmod +x /out/hcr_server_linux
    head -c4 /out/hcr_server_linux | od -An -tx1  # expect 7f 45 4c 46 (ELF)
  "
echo "built: $DIST/hcr_server_linux"
echo ""

# ── Step 2: deploy and start the server ─────────────────────────────────────
echo "--- Step 2: deploy and start hcr_server on $HOST ---"
scp -q "$DIST/hcr_server_linux" "$HOST":/tmp/

ssh "$HOST" bash -s <<REMOTE
  set -e
  pkill -f 'hcr_server_linux' 2>/dev/null || true
  rm -f "$SOCK_PATH"
  for holder in \$(ss -tlnpH "sport = :$PORT" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do
    kill -9 "\$holder" 2>/dev/null || true
  done
  sleep 0.5
  chmod +x /tmp/hcr_server_linux
  MARCH_HOT_RELOAD_SOCKET=$SOCK_PATH nohup /tmp/hcr_server_linux > /tmp/hcr_server.log 2>&1 &
  for _ in \$(seq 1 60); do
    ss -tlnp 2>/dev/null | grep -q ":$PORT " && break
    sleep 0.2
  done
  ss -tlnp 2>/dev/null | grep ":$PORT " || {
    echo "server did not bind :$PORT"
    cat /tmp/hcr_server.log
    exit 1
  }
  echo "[droplet] server ready on :$PORT (socket: $SOCK_PATH)"
REMOTE
echo ""

# ── Step 3: build the macOS hcr_client and verify square(7) = 49 ────────────
echo "--- Step 3: verify baseline square(7) = 49 ---"
MARCH_EXE="$ROOT/_build/default/bin/main.exe"
[[ -x "$MARCH_EXE" ]] || die "march compiler not built: run: /Users/80197052/.opam/march/bin/dune build --root $ROOT bin/main.exe"

CLIENT="$ROOT/_build/default/demo/hcr_client.exe"
if [[ ! -x "$CLIENT" ]]; then
  echo "building hcr_client..."
  /Users/80197052/.opam/march/bin/dune build --root "$ROOT" demo/hcr_client.exe
fi

LPORT=29852
ssh -N -L "$LPORT":127.0.0.1:"$PORT" "$HOST" &
TUNNEL_PID=$!
cleanup_tunnel() { kill "$TUNNEL_PID" 2>/dev/null || true; }
trap cleanup_tunnel EXIT
sleep 1.5

OUT_BEFORE=$("$CLIENT" 127.0.0.1 "$LPORT" 7 2>&1 || true)
echo "$OUT_BEFORE"
echo "$OUT_BEFORE" | grep -q "square(7) = 49" \
  || die "baseline check failed: expected 'square(7) = 49' in output (got: $OUT_BEFORE)"
echo "PASS: square(7) = 49 (baseline)"
kill "$TUNNEL_PID" 2>/dev/null || true
trap - EXIT
echo ""

# ── Step 4: create patch — Server.square(n) → n*n*n ─────────────────────────
echo "--- Step 4: create patch (square: n*n → n*n*n) ---"
PATCH_SRC="/tmp/hcr_server_patch_${SLUG}.march"
cat > "$PATCH_SRC" << 'MARCH'
-- Patch: Server.square now returns n*n*n instead of n*n.
-- Compiled with: march --compile --compile-so --hot-reload Server -o patch.so this.march
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

  pfn serve_loop(listen_fd : Int) do
    match tcp_accept(listen_fd) do
      Ok(conn_fd) ->
        NodeCall.serve_loop(NodeRpc.empty(), conn_fd)
        tcp_close(conn_fd)
        serve_loop(listen_fd)
      Err(e) -> println("accept error: " ++ e)
    end
  end

  fn main() do
    println("patch placeholder main (not called in --compile-so mode)")
  end
end
MARCH
echo "patch source: $PATCH_SRC"
echo ""

# ── Step 5: cross-compile patch .so for linux/amd64 ─────────────────────────
echo "--- Step 5: cross-compile patch .so for linux/amd64 ---"
PATCH_SO_DIST="$DIST/hcr_server_patch_${SLUG}.so"

docker run --rm --platform linux/amd64 \
  -v "$ROOT":/march \
  -v "$VOL":"$BD" \
  -v "$DIST":/out \
  -v "$(dirname "$PATCH_SRC")":"$(dirname "$PATCH_SRC")" \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    cd /march
    export MARCH_STDLIB=/march/stdlib
    MC=$BD/default/bin/main.exe  # reuse compiler built in Step 1
    \"\$MC\" --compile --compile-so --hot-reload Server \
      -o /out/hcr_server_patch_${SLUG}.so $PATCH_SRC
    head -c4 /out/hcr_server_patch_${SLUG}.so | od -An -tx1  # expect 7f 45 4c 46 (ELF)
    echo '--- exported symbols (Server.*):'
    nm -D /out/hcr_server_patch_${SLUG}.so 2>/dev/null | grep -E 'Server\.(square|report)' || true
  "
echo "patch so: $PATCH_SO_DIST"
echo ""

# ── Step 6: copy patch .so to droplet ───────────────────────────────────────
echo "--- Step 6: scp patch .so to droplet ---"
DROPLET_PATCH_SO="/tmp/hcr_patch_${SLUG}.so"
scp -q "$PATCH_SO_DIST" "$HOST":"$DROPLET_PATCH_SO"
echo "copied to $HOST:$DROPLET_PATCH_SO"
echo ""

# ── Step 7: send ACTIVATE via Unix socket tunnel ─────────────────────────────
echo "--- Step 7: send ACTIVATE Server.square via tunneled reload socket ---"
LOCAL_SOCK="/tmp/hcr_tunnel_mac_${SLUG}.sock"
rm -f "$LOCAL_SOCK"

ssh -N -L "$LOCAL_SOCK:$SOCK_PATH" "$HOST" &
SOCK_TUNNEL_PID=$!
cleanup_all() {
  kill "$SOCK_TUNNEL_PID" 2>/dev/null || true
}
trap cleanup_all EXIT
sleep 1.5

IMPL_HASH="cube_patch_v1"
RESPONSE="$(echo "ACTIVATE Server.square $IMPL_HASH $DROPLET_PATCH_SO" \
  | socat - "UNIX-CONNECT:$LOCAL_SOCK" 2>&1)" || true
echo "reload server response: $RESPONSE"
[[ "$RESPONSE" == OK* ]] || die "hot reload activation failed: $RESPONSE"
kill "$SOCK_TUNNEL_PID" 2>/dev/null || true
trap - EXIT
echo ""

# ── Step 8: verify square(7) = 343 after hot reload ─────────────────────────
echo "--- Step 8: verify square(7) = 343 after hot reload ---"
ssh -N -L "$LPORT":127.0.0.1:"$PORT" "$HOST" &
TUNNEL_PID=$!
cleanup_tunnel2() { kill "$TUNNEL_PID" 2>/dev/null || true; }
trap cleanup_tunnel2 EXIT
sleep 1.5

OUT_AFTER=$("$CLIENT" 127.0.0.1 "$LPORT" 7 2>&1 || true)
echo "$OUT_AFTER"
kill "$TUNNEL_PID" 2>/dev/null || true
trap - EXIT

echo "$OUT_AFTER" | grep -q "square(7) = 343" \
  || die "post-reload check failed: expected 'square(7) = 343' in output (got: $OUT_AFTER)"

echo ""
echo "=== HOT RELOAD VERIFIED ==="
echo "    square(7) changed from 49 → 343"
echo "    live server, no restart, no downtime"
