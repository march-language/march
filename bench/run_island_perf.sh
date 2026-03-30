#!/bin/bash
# Island concurrency performance test.
#
# Usage:
#   bench/run_island_perf.sh           # build + compile + run
#   bench/run_island_perf.sh --no-build  # skip dune build (already built)
#
# Output: throughput/latency/error rate/consistency at 10/50/100/500/1000 concurrency.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT/_build"
MARCH="$BUILD_DIR/default/bin/main.exe"
SERVER_SRC="$SCRIPT_DIR/island_perf_server.march"
SERVER_BIN="./island_perf_server"
BENCH_JS="$SCRIPT_DIR/island_perf_bench.mjs"
PORT=8899
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
}
trap cleanup EXIT INT TERM

# ---- 1. Build compiler (unless --no-build) ----
if [[ "${1:-}" != "--no-build" ]]; then
  echo "=== Building march compiler ==="
  /Users/80197052/.opam/march/bin/dune build --root "$ROOT" --build-dir "$BUILD_DIR" 2>&1
  echo "    done"
fi

# ---- 2. Compile the server ----
echo "=== Compiling island_perf_server.march ==="
cd "$ROOT"
"$MARCH" --compile "$SERVER_SRC"
echo "    done → $SERVER_BIN"

# ---- 3. Start server in background ----
echo "=== Starting server on port $PORT ==="
"$SERVER_BIN" &
SERVER_PID=$!

# Wait until server is accepting connections (max 5s)
for i in $(seq 1 20); do
  if curl -s "http://127.0.0.1:$PORT/ping" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "ERROR: server exited prematurely" >&2
  exit 1
fi
echo "    server up (pid=$SERVER_PID)"

# ---- 4. Run benchmark ----
echo ""
node "$BENCH_JS" 127.0.0.1 $PORT

# ---- 5. cleanup (trap handles it) ----
