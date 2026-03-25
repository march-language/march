#!/usr/bin/env bash
# bench/bench_http_simd.sh — wrk throughput comparison: SIMD vs scalar HTTP parser
#
# Compiles http_hello (LLVM IR) against two runtime variants:
#   1. SIMD parser  (new path; SSE4.2 on x86-64, scalar fallback on ARM64)
#   2. Scalar parser (old path; -DMARCH_HTTP_DISABLE_SIMD legacy code)
#
# Usage (from repo root — the worktree directory):
#   bash bench/bench_http_simd.sh
#
# Requirements: wrk (brew install wrk), clang

set -euo pipefail

PORT=8080
WRK_ARGS="-t4 -c100 -d10s --latency"
LL="examples/http_hello.ll"
RT="runtime"

die()  { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing '$1' (brew install $1)"; }

need wrk
need clang
[[ -f "$LL" ]] || die "Missing $LL"
for f in march_runtime.c march_http.c march_http_parse_simd.c sha1.c base64.c; do
    [[ -f "$RT/$f" ]] || die "Missing $RT/$f"
done

SIMD_BIN=$(mktemp /tmp/march_http_simd_XXXX)
SCAL_BIN=$(mktemp /tmp/march_http_scal_XXXX)
SERVER_PID=""

cleanup() {
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
    rm -f "$SIMD_BIN" "$SCAL_BIN"
}
trap cleanup EXIT

echo "=== March HTTP parser benchmark ==="
echo "    wrk $WRK_ARGS http://127.0.0.1:$PORT/"
echo "    On ARM64: both paths use scalar loops (SSE4.2 fast path needs x86-64)"
echo ""

# ── Compile ──────────────────────────────────────────────────────────────
printf "Compiling SIMD variant...   "
clang -O2 -msse4.2 -Wno-unused-command-line-argument -I"$RT" \
    "$RT/march_runtime.c" \
    "$RT/march_http.c" \
    "$RT/march_http_parse_simd.c" \
    "$RT/sha1.c" \
    "$RT/base64.c" \
    "$LL" -o "$SIMD_BIN" 2>&1
echo "ok"

printf "Compiling scalar variant... "
clang -O2 -DMARCH_HTTP_DISABLE_SIMD -I"$RT" \
    "$RT/march_runtime.c" \
    "$RT/march_http.c" \
    "$RT/march_http_parse_simd.c" \
    "$RT/sha1.c" \
    "$RT/base64.c" \
    "$LL" -o "$SCAL_BIN" 2>&1
echo "ok"
echo ""

run_bench() {
    local label="$1" bin="$2"
    kill $(lsof -ti:$PORT) 2>/dev/null || true; sleep 0.1

    echo "--- $label ---"
    "$bin" &
    SERVER_PID=$!
    sleep 0.5   # let the server bind

    # quick sanity check
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/")
    if [[ "$status" != "200" ]]; then
        echo "  WARNING: server returned HTTP $status (expected 200)"
    fi

    # warm-up pass
    wrk -t1 -c10 -d1s "http://127.0.0.1:$PORT/" >/dev/null 2>&1 || true

    # timed benchmark
    wrk $WRK_ARGS "http://127.0.0.1:$PORT/"

    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
    sleep 0.3
    echo ""
}

run_bench "SIMD parser  (new, march_http_parse_simd.c)" "$SIMD_BIN"
run_bench "Scalar parser (legacy, -DMARCH_HTTP_DISABLE_SIMD)" "$SCAL_BIN"

echo "=== Done ==="
