#!/usr/bin/env bash
# bench/run_interp_bench.sh — interpreted / compiled / REPL A-B over bench/interp.
# Usage: bash bench/run_interp_bench.sh [--modes interp,compiled,repl-clang,repl-orc]
#                                       [--only fib,json_stream] [--runs 3]
#                                       [--march path/to/main.exe] [--tag label]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARCH="$ROOT/_build/default/bin/main.exe"
MODES="interp,jit,compiled,repl-clang,repl-orc"; ONLY=""; RUNS=3; TAG="$(git -C "$ROOT" rev-parse --short HEAD)"
while [ $# -gt 0 ]; do case "$1" in
  --modes) MODES="$2"; shift 2;; --only) ONLY="$2"; shift 2;; --runs) RUNS="$2"; shift 2;;
  --march) MARCH="$2"; shift 2;; --tag) TAG="$2"; shift 2;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
ARCH="$(uname -m)"; DATE="$(date +%Y-%m-%d)"
OUT="$ROOT/bench/results/$DATE-interp-$ARCH.jsonl"; mkdir -p "$ROOT/bench/results"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/march-interp-bench.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

ms_now() { python3 -c 'import time;print(int(time.time()*1000))'; }
emit() { # bench mode run ms checksum ok
  printf '{"tag":"%s","bench":"%s","mode":"%s","run":%s,"ms":%s,"checksum":"%s","ok":%s}\n' \
    "$TAG" "$1" "$2" "$3" "$4" "$5" "$6" | tee -a "$OUT"; }
want() { [ -z "$ONLY" ] || [[ ",$ONLY," == *",$1,"* ]]; }
has_mode() { [[ ",$MODES," == *",$1,"* ]]; }

# --- file benchmarks -------------------------------------------------------
for src in "$ROOT"/bench/interp/*.march; do
  b="$(basename "$src" .march)"; want "$b" || continue
  [ "$b" = http_server ] && continue
  # bash 3.2 (macOS default) has no associative arrays; use plain vars, reset per benchmark.
  sum_interp=""; sum_jit=""; sum_compiled=""
  ok_interp=""; ok_jit=""; ok_compiled=""
  if has_mode compiled; then
    "$MARCH" --compile --opt 2 "$src" -o "$TMP/$b.bin" > "$TMP/$b.compile.log" 2>&1 \
      || { echo "compile failed for $b (see $TMP/$b.compile.log)" >&2; exit 1; }
  fi
  for run in $(seq 1 "$RUNS"); do
    for mode in interp jit compiled; do
      has_mode "$mode" || continue
      t0=$(ms_now)
      if [ "$mode" = interp ]; then "$MARCH" "$src" > "$TMP/$b.$mode.out" 2>&1 || true
      elif [ "$mode" = jit ]; then "$MARCH" --jit "$src" > "$TMP/$b.$mode.out" 2>&1 || true
      else "$TMP/$b.bin" > "$TMP/$b.$mode.out" 2>&1 || true; fi
      t1=$(ms_now)
      ck="$(grep -o 'checksum=[-0-9]*' "$TMP/$b.$mode.out" | head -1 || true)"
      ok=true; [ -n "$ck" ] || ok=false
      if [ "$mode" = interp ]; then sum_interp="$ck"; ok_interp="$ok"
      elif [ "$mode" = jit ]; then sum_jit="$ck"; ok_jit="$ok"
      else sum_compiled="$ck"; ok_compiled="$ok"; fi
      emit "$b" "$mode" "$run" "$((t1 - t0))" "$ck" "$ok"
    done
  done
  # Cross-check checksums across modes that actually produced output (ok=true).
  # A crashing mode (ok=false, e.g. a JIT SIGBUS) is reported as a FAILED row but
  # excluded from the mismatch comparison — only a DIFFERING checksum between two
  # modes that both succeeded is a hard failure.
  ref=""; ref_name=""
  for pair in "interp:$sum_interp:$ok_interp" "jit:$sum_jit:$ok_jit" "compiled:$sum_compiled:$ok_compiled"; do
    m="${pair%%:*}"; rest="${pair#*:}"; ck="${rest%%:*}"; ok="${rest#*:}"
    has_mode "$m" || continue
    [ "$ok" = true ] || continue
    if [ -z "$ref_name" ]; then ref="$ck"; ref_name="$m"
    elif [ "$ck" != "$ref" ]; then
      echo "CHECKSUM MISMATCH $b: $ref_name=$ref $m=$ck" >&2; exit 1
    fi
  done
done

# --- http server -------------------------------------------------------------
if want http_server; then
  for mode in interp compiled; do
    has_mode "$mode" || continue
    if [ -n "$(lsof -ti :18080 2>/dev/null || true)" ]; then
      echo "port 18080 already in use before starting http_server ($mode); aborting" >&2; exit 1
    fi
    if [ "$mode" = compiled ]; then
      "$MARCH" --compile --opt 2 "$ROOT/bench/interp/http_server.march" -o "$TMP/http.bin" > "$TMP/http.compile.log" 2>&1
      "$TMP/http.bin" > "$TMP/http.$mode.log" 2>&1 & SRV=$!
    else
      "$MARCH" "$ROOT/bench/interp/http_server.march" > "$TMP/http.$mode.log" 2>&1 & SRV=$!
    fi
    sleep 1
    for run in $(seq 1 "$RUNS"); do
      t0=$(ms_now); python3 "$ROOT/bench/interp/http_client.py" 500 > "$TMP/http.$mode.out"; t1=$(ms_now)
      ck="$(grep -o 'checksum=[0-9]*' "$TMP/http.$mode.out")"; ok=true; [ "$ck" = checksum=500 ] || ok=false
      emit http_server "$mode" "$run" "$((t1 - t0))" "$ck" "$ok"
    done
    kill "$SRV" 2>/dev/null || true; wait "$SRV" 2>/dev/null || true
    sleep 1
    survivor="$(pgrep -lf 'march-interp-http|http_server' 2>/dev/null || true)"
    if [ -n "$survivor" ]; then
      echo "WARNING: http_server ($mode) process survived kill: $survivor" >&2
    fi
  done
fi

# --- repl session ------------------------------------------------------------
for mode in repl-clang repl-orc; do
  has_mode "$mode" || continue
  for run in $(seq 1 "$RUNS"); do
    t0=$(ms_now)
    if [ "$mode" = repl-orc ]; then MARCH_JIT_BACKEND=orc "$MARCH" < "$ROOT/bench/interp/repl_session.txt" > "$TMP/$mode.out" 2>&1 || true
    else MARCH_JIT_BACKEND=clang "$MARCH" < "$ROOT/bench/interp/repl_session.txt" > "$TMP/$mode.out" 2>&1 || true; fi
    t1=$(ms_now)
    # Non-tty REPL prints prompt+result on one line ("> = ..."), not a leading "= ".
    n="$(grep -c '> = ' "$TMP/$mode.out" || true)"; ok=true; [ "$n" = 6 ] || ok=false
    emit repl_session "$mode" "$run" "$((t1 - t0))" "exprs=$n" "$ok"
  done
done

# --- table -------------------------------------------------------------------
python3 - "$OUT" "$TAG" <<'PY' >&2
import json, sys, collections
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rows = [r for r in rows if r["tag"] == sys.argv[2]]
by = collections.defaultdict(list)
for r in rows: by[(r["bench"], r["mode"])].append(r["ms"])
benches = sorted({b for b, _ in by}); modes = ["interp", "jit", "compiled", "repl-clang", "repl-orc"]
print(f"\n| bench | " + " | ".join(f"{m} min/median ms" for m in modes) + " |")
print("|---|" + "---:|" * len(modes))
for b in benches:
    cells = []
    for m in modes:
        xs = sorted(by.get((b, m), []))
        cells.append(f"{xs[0]} / {xs[len(xs)//2]}" if xs else "–")
    print(f"| {b} | " + " | ".join(cells) + " |")
bad = [r for r in rows if not r["ok"]]
if bad: print(f"\n{len(bad)} FAILED rows (ok=false): " + ", ".join(f'{r["bench"]}/{r["mode"]}' for r in bad))
PY
