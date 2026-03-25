#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# Local TFB-style benchmark: March vs Node.js vs Python
#
# Runs plaintext and JSON tests with the same wrk parameters for each
# framework. Uses TFB methodology (primer → warmup → captured run).
#
# Usage: ./bench/tfb/run.sh [march|node|node-cluster|python|all]
#        Default: all
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

PORT=8080
WRK_THREADS=4
DURATION=15s
WARMUP=5s
PIPELINE_LUA="pipeline.lua"

# Colors
G='\033[1;32m'; Y='\033[1;33m'; C='\033[1;36m'; R='\033[0m'

wait_for_port() {
  for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://localhost:$PORT/plaintext" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  echo "ERROR: server did not start on port $PORT"
  return 1
}

kill_port() {
  lsof -ti :$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
  sleep 0.3
}

run_bench() {
  local name="$1"
  echo ""
  echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"
  echo -e "${C}  $name${R}"
  echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"

  # ── JSON (no pipelining) ──
  echo -e "\n${Y}── JSON  (c=256, no pipeline) ──${R}"
  echo -e "${G}Primer...${R}"
  wrk -t 2 -c 8 -d 3s "http://localhost:$PORT/json" > /dev/null 2>&1
  echo -e "${G}Warmup...${R}"
  wrk -t $WRK_THREADS -c 256 -d $WARMUP "http://localhost:$PORT/json" > /dev/null 2>&1
  echo -e "${G}Captured run:${R}"
  wrk -t $WRK_THREADS -c 256 -d $DURATION "http://localhost:$PORT/json"

  # ── Plaintext (no pipelining — apples-to-apples) ──
  echo -e "\n${Y}── Plaintext  (c=256, no pipeline) ──${R}"
  echo -e "${G}Primer...${R}"
  wrk -t 2 -c 8 -d 3s "http://localhost:$PORT/plaintext" > /dev/null 2>&1
  echo -e "${G}Warmup...${R}"
  wrk -t $WRK_THREADS -c 256 -d $WARMUP "http://localhost:$PORT/plaintext" > /dev/null 2>&1
  echo -e "${G}Captured run:${R}"
  wrk -t $WRK_THREADS -c 256 -d $DURATION "http://localhost:$PORT/plaintext"

  # ── Plaintext (pipelined ×16 — TFB official) ──
  echo -e "\n${Y}── Plaintext  (c=256, pipeline ×16) ──${R}"
  echo -e "${G}Primer...${R}"
  wrk -t 2 -c 8 -d 3s -s "$PIPELINE_LUA" "http://localhost:$PORT/plaintext" -- 16 > /dev/null 2>&1
  echo -e "${G}Warmup...${R}"
  wrk -t $WRK_THREADS -c 256 -d $WARMUP -s "$PIPELINE_LUA" "http://localhost:$PORT/plaintext" -- 16 > /dev/null 2>&1
  echo -e "${G}Captured run:${R}"
  wrk -t $WRK_THREADS -c 256 -d $DURATION -s "$PIPELINE_LUA" "http://localhost:$PORT/plaintext" -- 16
}

# ── Framework launchers ──

bench_march() {
  kill_port
  ../../examples/http_hello &
  local PID=$!
  wait_for_port
  run_bench "March (compiled, 28 worker threads)"
  kill $PID 2>/dev/null; wait $PID 2>/dev/null || true
}

bench_node() {
  kill_port
  node node_http.js &
  local PID=$!
  wait_for_port
  run_bench "Node.js (single-thread, http module)"
  kill $PID 2>/dev/null; wait $PID 2>/dev/null || true
}

bench_node_cluster() {
  kill_port
  node node_cluster.js &
  local PID=$!
  wait_for_port
  run_bench "Node.js cluster (multi-process, http module)"
  kill $PID 2>/dev/null; wait $PID 2>/dev/null || true
}

bench_python() {
  kill_port
  python3 python_http.py &
  local PID=$!
  wait_for_port
  run_bench "Python 3 (ThreadingHTTPServer, stdlib)"
  kill $PID 2>/dev/null; wait $PID 2>/dev/null || true
}

# ── Main ──

TARGET="${1:-all}"

echo "╔═══════════════════════════════════════════════════╗"
echo "║  Local TFB Benchmark — $(date '+%Y-%m-%d %H:%M')        ║"
echo "║  wrk: ${WRK_THREADS}t, 256c, ${DURATION}, pipeline ×16       ║"
echo "╚═══════════════════════════════════════════════════╝"

case "$TARGET" in
  march)        bench_march ;;
  node)         bench_node ;;
  node-cluster) bench_node_cluster ;;
  python)       bench_python ;;
  all)
    bench_march
    bench_node
    bench_node_cluster
    bench_python
    echo ""
    echo -e "${C}━━━ All benchmarks complete ━━━${R}"
    ;;
  *) echo "Usage: $0 [march|node|node-cluster|python|all]"; exit 1 ;;
esac
