#!/usr/bin/env bash
# Steady-state tail-latency + flat-RSS demo runner.
#
# Compiles bench/steady_state_ring.march, then runs it at several CPU-bound
# sibling counts. For each run it:
#   - samples the process RSS over time (external `ps`, the same methodology as
#     specs/benchmarks.md's RSS sections — there is no in-process RSS builtin),
#   - reads the program's own threaded latency histogram and derives
#     p50/p90/p99/p99.9 (bucket upper bounds) plus exact min/max.
#
# Output: a human table + one JSONL record per scenario (schema documented
# below), plus a per-scenario RSS trace under the results dir.
#
# Usage:
#   bash bench/run_steady_state.sh
#   STEADY_OPS=5000000 SIBLINGS="0 4 8 16 32" bash bench/run_steady_state.sh
#   MARCH=/path/to/march bash bench/run_steady_state.sh   # skip dune build
#
# Env knobs (all optional — defaults are laptop-sized):
#   STEADY_OPS    ops per run              (default 2000000)
#   STEADY_WORK   LCG rounds per request   (default 512, ~2-4us/op)
#   SIBLINGS      space-separated counts   (default "0 4 8 16")
#   STEADY_SIBWORK  per-sibling fib size   (default 28)
#   OUT_JSONL     machine-readable output  (default results/<date>-steady-state-<arch>.jsonl)
#   RSS_INTERVAL  RSS sample period (s)    (default 0.2)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH_DIR="$REPO_ROOT/bench"
RESULTS_DIR="$BENCH_DIR/results"
SRC="$BENCH_DIR/steady_state_ring.march"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STEADY_OPS="${STEADY_OPS:-2000000}"
STEADY_WORK="${STEADY_WORK:-512}"
STEADY_SIBWORK="${STEADY_SIBWORK:-28}"
SIBLINGS="${SIBLINGS:-0 4 8 16}"
RSS_INTERVAL="${RSS_INTERVAL:-0.2}"

ARCH="$(uname -m)"
DATE="$(date -u '+%Y-%m-%d')"
OUT_JSONL="${OUT_JSONL:-$RESULTS_DIR/${DATE}-steady-state-${ARCH}-laptop.jsonl}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ── Toolchain: prefer $MARCH, else build this working tree and use its exe ────
OPAM_BIN="${OPAM_SWITCH_BIN:-$HOME/.opam/march/bin}"
DUNE="${DUNE:-}"
[ -n "$DUNE" ] || DUNE="$(command -v dune 2>/dev/null || true)"
[ -n "$DUNE" ] || { [ -x "$OPAM_BIN/dune" ] && DUNE="$OPAM_BIN/dune"; }

MARCH="${MARCH:-}"
if [ -z "$MARCH" ]; then
  [ -n "$DUNE" ] || { echo "ERROR: need dune (or set MARCH=/path/to/march)"; exit 1; }
  bold "Building the compiler (dune build --root . bin/main.exe)..."
  (cd "$REPO_ROOT" && "$DUNE" build --root . bin/main.exe)
  MARCH="$REPO_ROOT/_build/default/bin/main.exe"
fi

# ── Provenance ────────────────────────────────────────────────────────────────
mkdir -p "$RESULTS_DIR"
: > "$OUT_JSONL"
if [ -r /proc/cpuinfo ]; then
  CPU="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
  CORES="$(nproc 2>/dev/null || echo 0)"
else
  CPU="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
  CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo 0)"
fi
LOAD="$(uptime | sed 's/.*load average[s]*: *//')"
printf '{"meta":true,"date":"%s","host":"%s","cpu":"%s","cores":%s,"ops":%s,"work":%s,"sibwork":%s,"load":"%s"}\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(json_escape "$(uname -srm)")" "$(json_escape "$CPU")" \
  "$CORES" "$STEADY_OPS" "$STEADY_WORK" "$STEADY_SIBWORK" "$(json_escape "$LOAD")" >> "$OUT_JSONL"

bold "═══ Environment ═══"
printf '  %-10s %s\n' "date"  "$(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
printf '  %-10s %s\n' "host"  "$(uname -srm)"
printf '  %-10s %s\n' "cpu"   "$CPU"
printf '  %-10s %s\n' "cores" "$CORES"
printf '  %-10s %s\n' "load"  "$LOAD"
printf '  %-10s %s\n' "march" "$MARCH"
printf '  %-10s ops=%s work=%s sibwork=%s siblings=[%s]\n' "config" "$STEADY_OPS" "$STEADY_WORK" "$STEADY_SIBWORK" "$SIBLINGS"
printf '\n'

# ── Compile ───────────────────────────────────────────────────────────────────
bold "Compiling $SRC (--opt 2)..."
BIN="$TMP/steady_state_ring"
(cd "$REPO_ROOT" && "$MARCH" --compile --opt 2 "$SRC" -o "$BIN" >/dev/null 2>&1) \
  || { echo "ERROR: compile failed"; (cd "$REPO_ROOT" && "$MARCH" --compile --opt 2 "$SRC" -o "$BIN"); exit 1; }
printf '  done -> %s\n\n' "$BIN"

# ── Percentiles from the program's threaded histogram ─────────────────────────
# Bucket k covers [2^(SHIFT+k), 2^(SHIFT+k+1)) ns; bucket 0 = [0, 2^(SHIFT+1)),
# bucket NB-1 = [2^(SHIFT+NB-1), inf). We report each percentile as the bucket's
# UPPER bound in ns (i.e. "p <= X"), which is the honest resolution of a
# power-of-two histogram; exact min/max come from the program.
PCTL_PY="$TMP/pctl.py"
cat > "$PCTL_PY" <<'PYEOF'
import sys
buckets={}; shift=10; nb=12; mn=mx=ops=0
for line in sys.stdin:
    t=line.split()
    if not t: continue
    if t[0]=="SHIFT": shift=int(t[1])
    elif t[0]=="NB": nb=int(t[1])
    elif t[0]=="OPS": ops=int(t[1])
    elif t[0]=="MIN_NS": mn=int(t[1])
    elif t[0]=="MAX_NS": mx=int(t[1])
    elif t[0]=="BUCKET": buckets[int(t[1])]=int(t[2])
tot=sum(buckets.values()) or 1
def upper(k):
    if k>=nb-1: return mx            # open-ended top bucket: report exact max
    return 1<<(shift+k+1)
def pctl(p):
    thr=p*tot; run=0
    for k in range(nb):
        run+=buckets.get(k,0)
        if run>=thr: return upper(k)
    return mx
print(pctl(0.50), pctl(0.90), pctl(0.99), pctl(0.999), mn, mx)
PYEOF
percentiles() { python3 "$PCTL_PY"; }   # reads program stdout on stdin

# ── RSS sampler: run BIN in background, sample ps RSS until it exits ───────────
run_scenario() { # sib_count -> echoes "p50 p90 p99 p999 min max rss_min rss_max wall"
  local sib="$1"
  local out="$TMP/out_${sib}.txt" rss="$RESULTS_DIR/${DATE}-steady-state-${ARCH}-sib${sib}.rss"
  : > "$rss"
  local t_start t_end
  t_start="$(date +%s.%N)"
  STEADY_OPS="$STEADY_OPS" STEADY_WORK="$STEADY_WORK" \
    STEADY_SIBLINGS="$sib" STEADY_SIBWORK="$STEADY_SIBWORK" "$BIN" > "$out" 2>/dev/null &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    local r; r="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$r" ] && printf '%s %s\n' "$(date +%s.%N)" "$r" >> "$rss"
    sleep "$RSS_INTERVAL"
  done
  wait "$pid" || true
  t_end="$(date +%s.%N)"
  local wall; wall="$(python3 -c "print(f'{$t_end-$t_start:.2f}')")"
  # RSS min/max in KB over the STEADY region — drop sub-256 KB samples, which
  # catch the process before it has faulted in its working set (a misleading
  # ~32 KB). What we care about is that the steady set does not grow with ops.
  local rmin rmax
  rmin="$(awk '$2>256{print $2}' "$rss" | sort -n | head -1)"
  rmax="$(awk '$2>256{print $2}' "$rss" | sort -n | tail -1)"
  [ -n "$rmin" ] || rmin=0; [ -n "$rmax" ] || rmax=0
  local pcts; pcts="$(percentiles < "$out")"
  echo "$pcts $rmin $rmax $wall"
}

fmt_ns() { # ns -> human (us/ms)
  python3 -c "n=int('$1'); print(f'{n/1e6:.2f}ms' if n>=1e6 else (f'{n/1e3:.1f}us' if n>=1e3 else f'{n}ns'))"
}

bold "═══ Steady-state: latency vs CPU-bound-sibling contention ═══"
dim  "  $STEADY_OPS ops/run, WORK=$STEADY_WORK. p-values are power-of-two-bucket upper bounds (p <= X)."
printf '  %-9s %9s %9s %9s %9s %10s %14s %7s\n' "siblings" "p50" "p90" "p99" "p99.9" "max" "RSS(KB)min/max" "wall_s"
printf '  %-9s %9s %9s %9s %9s %10s %14s %7s\n' "--------" "---" "---" "---" "-----" "---" "-------------" "------"

for sib in $SIBLINGS; do
  read -r p50 p90 p99 p999 mn mx rmin rmax wall < <(run_scenario "$sib")
  printf '  %-9s %9s %9s %9s %9s %10s %6s/%-7s %7s\n' \
    "$sib" "$(fmt_ns "$p50")" "$(fmt_ns "$p90")" "$(fmt_ns "$p99")" "$(fmt_ns "$p999")" "$(fmt_ns "$mx")" "$rmin" "$rmax" "$wall"
  printf '{"scenario":"steady_state_ring","siblings":%s,"ops":%s,"work":%s,"p50_ns":%s,"p90_ns":%s,"p99_ns":%s,"p999_ns":%s,"min_ns":%s,"max_ns":%s,"rss_kb_min":%s,"rss_kb_max":%s,"wall_s":%s}\n' \
    "$sib" "$STEADY_OPS" "$STEADY_WORK" "$p50" "$p90" "$p99" "$p999" "$mn" "$mx" "$rmin" "$rmax" "$wall" >> "$OUT_JSONL"
done

printf '\n'
bold "Done."
printf '  JSONL:      %s\n' "$OUT_JSONL"
printf '  RSS traces: %s/%s-steady-state-%s-sib*.rss\n' "$RESULTS_DIR" "$DATE" "$ARCH"
printf '  Interpret:  p50/p90/p99 near-constant across siblings => scheduler protects the\n'
printf '              common case; a bounded (not unbounded) p99.9 growth => no starvation;\n'
printf '              flat RSS(KB) across all rows => RC reclaims per-op transients (no GC heap).\n'
